import AppKit
import SwiftUI

@MainActor
enum AppIconExporter {
    static let pixelSizes: [Int] = [16, 32, 64, 128, 256, 512, 1024]

    /// Default location: `~/Documents/XCode/Loom/Loom/Resources/Assets.xcassets/AppIcon.appiconset`.
    /// Returns nil if the path doesn't exist (e.g. running from a relocated copy).
    static func defaultAssetURL() -> URL? {
        let candidate = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/XCode/Loom/Loom/Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    static func export(to url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url, withIntermediateDirectories: true)

        for px in pixelSizes {
            let view = LoomLogoMark(size: CGFloat(px))
                .frame(width: CGFloat(px), height: CGFloat(px))
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            renderer.isOpaque = false
            guard let cgImage = renderer.cgImage else {
                throw NSError(
                    domain: "AppIconExporter",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "ImageRenderer failed for \(px)px"]
                )
            }
            let rep = NSBitmapImageRep(cgImage: cgImage)
            rep.size = NSSize(width: px, height: px)
            guard let data = rep.representation(using: .png, properties: [:]) else {
                throw NSError(
                    domain: "AppIconExporter",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "PNG encoding failed for \(px)px"]
                )
            }
            try data.write(to: url.appendingPathComponent("AppIcon-\(px).png"))
        }

        try contentsJSON.write(
            to: url.appendingPathComponent("Contents.json"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static let contentsJSON = """
    {
      "images" : [
        { "filename" : "AppIcon-16.png",   "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
        { "filename" : "AppIcon-32.png",   "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
        { "filename" : "AppIcon-32.png",   "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
        { "filename" : "AppIcon-64.png",   "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
        { "filename" : "AppIcon-128.png",  "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
        { "filename" : "AppIcon-256.png",  "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
        { "filename" : "AppIcon-256.png",  "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
        { "filename" : "AppIcon-512.png",  "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
        { "filename" : "AppIcon-512.png",  "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
        { "filename" : "AppIcon-1024.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
      ],
      "info" : { "author" : "xcode", "version" : 1 }
    }
    """
}
