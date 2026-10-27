import SwiftUI

enum Theme {
    static let mint = Color(red: 26 / 255, green: 200 / 255, blue: 164 / 255)
    static let teal = Color(red: 4 / 255, green: 78 / 255, blue: 96 / 255)
    static let accent = Color(red: 8 / 255, green: 122 / 255, blue: 112 / 255)
    static let coral = Color(red: 255 / 255, green: 107 / 255, blue: 94 / 255)
    static let alert = Color(red: 217 / 255, green: 69 / 255, blue: 58 / 255)
    static let background = Color(red: 239 / 255, green: 245 / 255, blue: 245 / 255)
    static let gradient = LinearGradient(colors: [mint, teal], startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct PulseShape: Shape {
    private static let points: [(x: Double, y: Double)] = [
        (0, 0.551), (0.349, 0.551), (0.471, 0.551), (0.593, 0), (0.727, 1), (0.843, 0.551), (1, 0.551),
    ]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (index, point) in Self.points.enumerated() {
            let location = CGPoint(x: rect.minX + rect.width * point.x, y: rect.minY + rect.height * point.y)
            if index == 0 { path.move(to: location) } else { path.addLine(to: location) }
        }
        return path
    }
}

struct LogoMark: View {
    var size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
                .fill(Theme.gradient)
            PulseShape()
                .stroke(.white, style: StrokeStyle(lineWidth: size * 0.0527, lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.672, height: size * 0.539)
                .offset(x: -size * 0.055)
            Circle()
                .fill(Theme.coral)
                .frame(width: size * 0.0977, height: size * 0.0977)
                .offset(x: size * 0.377, y: size * 0.027)
        }
        .frame(width: size, height: size)
    }
}

struct SectionHeader: View {
    private let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.teal)
            .textCase(nil)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
    }
}

extension View {
    func themedField() -> some View {
        padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.teal.opacity(0.15)))
    }
}
