import AVKit
import SwiftUI
import UIKit

enum Palette {
    static let paper = Color(red: 241/255, green: 245/255, blue: 248/255)
    static let ink = Color(red: 16/255, green: 38/255, blue: 53/255)
    static let muted = Color(red: 71/255, green: 96/255, blue: 109/255)
    static let line = Color(red: 216/255, green: 229/255, blue: 233/255)
    static let accent = Color(red: 0, green: 104/255, blue: 117/255)
    static let tint = Color(red: 225/255, green: 241/255, blue: 240/255)
}

extension View {
    func panel(_ tint: Color = .white, inset: CGFloat = 16) -> some View {
        padding(inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint, in: RoundedRectangle(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(Palette.line).allowsHitTesting(false) }
    }

    func surface() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(Palette.ink)
            .background(Palette.paper.ignoresSafeArea())
    }
}

struct Hint: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.footnote).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
    }
}

struct Eyebrow: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(Palette.accent)
    }
}

struct Page<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) { content }
                .frame(maxWidth: 570)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
        }
        .surface()
    }
}

struct Heading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.largeTitle.weight(.bold)).accessibilityAddTraits(.isHeader)
            Hint(subtitle)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct ActionButton: View {
    enum Style { case primary, stop, secondary, text }
    let title: String
    let id: String
    var style: Style = .secondary
    var icon: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).accessibilityHidden(true) }
                Text(title).multilineTextAlignment(.center)
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: style == .text ? nil : .infinity, minHeight: style == .primary || style == .stop ? 52 : 44)
            .padding(.horizontal, 10)
            .foregroundStyle(style == .primary || style == .stop ? .white : Palette.accent)
            .background(background, in: RoundedRectangle(cornerRadius: 13))
            .overlay {
                if style == .secondary { RoundedRectangle(cornerRadius: 13).strokeBorder(Palette.line).allowsHitTesting(false) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private var background: Color {
        switch style {
        case .primary: return Palette.accent
        case .stop: return Palette.ink
        case .secondary: return .white
        case .text: return .clear
        }
    }
}

struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = UIColor(Palette.accent)
        view.activeTintColor = UIColor(Palette.accent)
        view.subviews.compactMap { $0 as? UIButton }.first?.accessibilityIdentifier = "route.change"
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

struct RouteLine: View {
    let output: OutputKind
    var picker = false
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(output == .unknown ? Palette.muted : Palette.accent)
                .frame(width: 8, height: 8).accessibilityHidden(true)
            Text(output.title).font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("route.current")
            Spacer(minLength: 0)
            if picker {
                RoutePicker().frame(width: 44, height: 44)
            } else {
                Hint(L.t("route.current"))
            }
        }
        .panel(inset: 10)
    }
}

struct Waveform: View {
    let progress: Double?
    private let bars: [CGFloat] = [5, 8, 10, 16, 19, 13, 24, 30, 23, 27, 38, 34, 24, 41, 42, 26, 38,
                                    46, 34, 30, 43, 37, 21, 35, 35, 22, 24, 27, 20, 14, 16, 12, 7, 5]
    var body: some View {
        HStack(spacing: 3) {
            ForEach(bars.indices, id: \.self) { index in
                Capsule()
                    .fill(Palette.accent.opacity(progress.map { Double(index + 1) / Double(bars.count) <= $0 ? 1 : 0.25 } ?? 0.85))
                    .frame(maxWidth: 6)
                    .frame(height: bars[index])
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .accessibilityHidden(true)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    let completed: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, didComplete, _, _ in
            DispatchQueue.main.async { completed(didComplete) }
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
