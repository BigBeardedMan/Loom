import Foundation
import Observation

/// Persists user-configured local LLM endpoints in `UserDefaults` as a JSON
/// blob. Auth tokens are stored separately in Keychain via
/// `LocalEndpoint.keychainAccount`, so deleting an endpoint also clears its
/// secret. The store is `@MainActor` because SwiftUI views observe and mutate
/// it directly from the Settings UI.
@Observable
@MainActor
final class LocalEndpointStore {
    static let defaultsKey = "loom.localEndpoints"

    private(set) var endpoints: [LocalEndpoint] = []

    init() {
        load()
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey) else {
            endpoints = []
            return
        }
        endpoints = (try? JSONDecoder().decode([LocalEndpoint].self, from: data)) ?? []
    }

    private func persist() {
        let data = (try? JSONEncoder().encode(endpoints)) ?? Data()
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    func upsert(_ endpoint: LocalEndpoint) {
        if let idx = endpoints.firstIndex(where: { $0.id == endpoint.id }) {
            endpoints[idx] = endpoint
        } else {
            endpoints.append(endpoint)
        }
        persist()
    }

    func remove(_ endpoint: LocalEndpoint) {
        endpoints.removeAll { $0.id == endpoint.id }
        KeychainStore.delete(account: endpoint.keychainAccount)
        persist()
    }

    func authToken(for endpoint: LocalEndpoint) -> String? {
        guard endpoint.requiresAuth else { return nil }
        let value = KeychainStore.load(account: endpoint.keychainAccount)
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    func setAuthToken(_ token: String, for endpoint: LocalEndpoint) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainStore.delete(account: endpoint.keychainAccount)
        } else {
            KeychainStore.save(account: endpoint.keychainAccount, value: trimmed)
        }
    }
}
