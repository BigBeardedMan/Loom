import SwiftUI

/// Square Loom mark — three stacked terminal-windows on a near-black canvas.
/// Mirrors the design used in `loom_logo_banner.svg` so the app icon matches
/// the in-app banner. Used both for the in-app header (small size) and as the
/// source rendered out to the macOS AppIcon set (see AppIconExporter).
struct LoomLogoMark: View {
    var size: CGFloat = 1024

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225)
                .fill(Color(hex: 0x0a0a0a))

            // Art occupies ~62% of the canvas width centered. Native art
            // dimensions in SVG units are 70 × 56 (5:4). One SVG unit becomes
            // `unit` pixels.
            let unit = size * 0.0089
            stackedWindows(unit: unit)
        }
        .frame(width: size, height: size)
    }

    private func stackedWindows(unit: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // Back window @ (14,14)
            window(fillHex: 0x18181b, strokeHex: 0x3f3f46, unit: unit)
                .offset(x: 14 * unit, y: 14 * unit)

            // Middle window @ (7,7) with two dim window-control dots
            ZStack(alignment: .topLeading) {
                window(fillHex: 0x1c1c20, strokeHex: 0x52525b, unit: unit)
                dot(unit: unit, hex: 0x52525b, opacity: 1, x: 11, y: 11, r: 1.5)
                dot(unit: unit, hex: 0x3f3f46, opacity: 1, x: 16, y: 11, r: 1.5)
            }
            .offset(x: 7 * unit, y: 7 * unit)

            // Front window @ (0,0): three control dots + three "code lines"
            ZStack(alignment: .topLeading) {
                window(fillHex: 0x27272a, strokeHex: 0xa1a1aa, unit: unit)

                // Window-control dots
                dot(unit: unit, hex: 0x5eead4, opacity: 1.0,  x: 6,  y: 6, r: 1.8)
                dot(unit: unit, hex: 0xa1a1aa, opacity: 0.40, x: 12, y: 6, r: 1.8)
                dot(unit: unit, hex: 0xa1a1aa, opacity: 0.25, x: 18, y: 6, r: 1.8)

                // Code line 1: green tag + gray bar (20)
                bar(unit: unit, hex: 0x5eead4, opacity: 1.0,  x: 6,  y: 16, w: 3,  h: 2)
                bar(unit: unit, hex: 0xa1a1aa, opacity: 0.5,  x: 12, y: 16, w: 20, h: 2)
                // Code line 2: green tag + gray bar (14)
                bar(unit: unit, hex: 0x5eead4, opacity: 1.0,  x: 6,  y: 22, w: 3,  h: 2)
                bar(unit: unit, hex: 0xa1a1aa, opacity: 0.5,  x: 12, y: 22, w: 14, h: 2)
                // Code line 3: green tag + green bar (6) — the "active" line
                bar(unit: unit, hex: 0x5eead4, opacity: 1.0,  x: 6,  y: 28, w: 3,  h: 2)
                bar(unit: unit, hex: 0x5eead4, opacity: 1.0,  x: 12, y: 28, w: 6,  h: 2)
            }
        }
        .frame(width: 70 * unit, height: 56 * unit)
    }

    private func window(fillHex: UInt32, strokeHex: UInt32, unit: CGFloat) -> some View {
        // SVG stroke-width was 1.2 in art units. Translate to pixels.
        let strokeW = max(0.5, 1.2 * unit)
        return RoundedRectangle(cornerRadius: 5 * unit)
            .fill(Color(hex: fillHex))
            .frame(width: 56 * unit, height: 42 * unit)
            .overlay {
                RoundedRectangle(cornerRadius: 5 * unit)
                    .stroke(Color(hex: strokeHex), lineWidth: strokeW)
            }
    }

    private func dot(unit: CGFloat, hex: UInt32, opacity: Double, x: CGFloat, y: CGFloat, r: CGFloat) -> some View {
        Circle()
            .fill(Color(hex: hex).opacity(opacity))
            .frame(width: 2 * r * unit, height: 2 * r * unit)
            .offset(x: (x - r) * unit, y: (y - r) * unit)
    }

    private func bar(unit: CGFloat, hex: UInt32, opacity: Double, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> some View {
        Rectangle()
            .fill(Color(hex: hex).opacity(opacity))
            .frame(width: w * unit, height: h * unit)
            .offset(x: x * unit, y: y * unit)
    }
}

private extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xff) / 255
        let g = Double((hex >> 8) & 0xff) / 255
        let b = Double(hex & 0xff) / 255
        self.init(red: r, green: g, blue: b)
    }
}

#Preview("1024") {
    LoomLogoMark(size: 1024)
        .frame(width: 1024, height: 1024)
        .background(Color(red: 0.18, green: 0.20, blue: 0.24))
}

#Preview("256") {
    LoomLogoMark(size: 256)
        .frame(width: 256, height: 256)
        .padding()
        .background(Color(red: 0.18, green: 0.20, blue: 0.24))
}

#Preview("64") {
    LoomLogoMark(size: 64)
        .frame(width: 64, height: 64)
        .padding()
        .background(Color(red: 0.18, green: 0.20, blue: 0.24))
}
