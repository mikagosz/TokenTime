import SwiftUI
import AppKit

// MARK: - Znak graficzny TokenTime (nawiązuje do ikony aplikacji)

/// Zegar z dwiema krzyżującymi się orbitami — monochromatyczny, skalowalny.
struct TokenTimeGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let lw = max(1, s * 0.08)
            ZStack {
                // Tarcza zegara / planeta
                Circle()
                    .stroke(lineWidth: lw)
                    .padding(lw / 2)

                // Dwie krzyżujące się orbity
                Ellipse()
                    .stroke(lineWidth: lw * 0.85)
                    .frame(width: s * 0.44, height: s * 0.98)
                    .rotationEffect(.degrees(38))
                Ellipse()
                    .stroke(lineWidth: lw * 0.85)
                    .frame(width: s * 0.44, height: s * 0.98)
                    .rotationEffect(.degrees(-38))

                // Wskazówki zegara
                ClockHands()
                    .stroke(style: StrokeStyle(lineWidth: lw, lineCap: .round))

                // Piasta wskazówek
                Circle()
                    .frame(width: lw * 1.8, height: lw * 1.8)
            }
            .frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct ClockHands: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        // wskazówka minutowa (do góry)
        path.move(to: center)
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.30))
        // wskazówka godzinowa (w prawo-dół)
        path.move(to: center)
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.66,
                                 y: rect.midY + rect.height * 0.06))
        return path
    }
}

#Preview {
    TokenTimeGlyph()
        .frame(width: 120, height: 120)
        .foregroundStyle(.primary)
        .padding()
}

extension TokenTimeGlyph {
    /// Szablonowa ikona do paska menu — system sam dobiera kolor (jasny/ciemny pasek).
    @MainActor static let menuBarImage: NSImage = {
        let renderer = ImageRenderer(content:
            TokenTimeGlyph()
                .foregroundStyle(.black)
                .frame(width: 18, height: 18)
                .padding(1)
        )
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = true
        return image
    }()
}
