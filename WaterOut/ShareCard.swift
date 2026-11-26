import SwiftUI
import UIKit

extension RootView {
    var cardPage: some View {
        CardPage(milestone: milestone || library.data.milestones.completedChecklist, hearing: lastHearing,
                 shareRequested: shareRequested, shareImage: { share([$0, L.t("card.caption")]) },
                 copyCode: { UIPasteboard.general.string = selectedPreset.code })
    }
}

private struct CardPage: View {
    let milestone: Bool
    let hearing: Hearing?
    let shareRequested: Bool
    let shareImage: (UIImage) -> Void
    let copyCode: () -> Void
    @State private var includeHearing = false
    @State private var qr: CGImage?
    @State private var notice: String?

    private var storeURL: URL? { CardCode.storeURL(id: Bundle.main.object(forInfoDictionaryKey: "APP_STORE_ID") as? String) }
    private var note: Hearing? { includeHearing ? hearing : nil }

    var body: some View {
        Page {
            Heading(title: L.t("card.title"), subtitle: L.t("card.preview"))
            ChecklistCard(milestone: milestone, qr: qr, storeLink: storeURL != nil, hearing: note)
                .panel()
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("card.preview")
            if let hearing, hearing != .skip {
                Toggle(L.t("card.includeNote"), isOn: $includeHearing).accessibilityIdentifier("card.includeNote")
            }
            Hint(L.t("card.privacy"))
            ActionButton(title: L.t("card.share"), id: "card.share", style: .primary, icon: "square.and.arrow.up") {
                let artwork = ChecklistCard(milestone: milestone, qr: qr, storeLink: storeURL != nil, hearing: note)
                    .padding(20)
                    .frame(width: 360, height: 450, alignment: .center)
                    .background(Color.white)
                    .environment(\.dynamicTypeSize, .medium)
                let renderer = ImageRenderer(content: artwork)
                renderer.scale = 3
                if let image = renderer.uiImage { shareImage(image) }
                else { notice = "card.failed" }
            }.disabled(qr == nil)
            ActionButton(title: L.t("preset.copy"), id: "card.copy") {
                copyCode()
                notice = "preset.copied"
            }
            ActionButton(title: L.t("card.copyCaption"), id: "card.caption") {
                UIPasteboard.general.string = L.t("card.caption")
                notice = "card.captionCopied"
            }
            if let notice { Hint(L.t(notice)) }
            if shareRequested {
                Text(L.t("share.requested")).font(.footnote).accessibilityIdentifier("share.requested")
            }
        }
        .task {
            let target = storeURL ?? CardCode.supportURL
            qr = await Task.detached { CardCode.image(for: target) }.value
            if qr == nil { notice = "card.failed" }
        }
    }
}

private struct ChecklistCard: View {
    let milestone: Bool
    let qr: CGImage?
    let storeLink: Bool
    let hearing: Hearing?

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Eyebrow(L.t("card.brand"))
            Text(L.t(milestone ? "card.milestone" : "card.heading"))
                .font(.largeTitle.weight(.bold)).foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Hint(L.t("card.lowVolume"))
            VStack(alignment: .leading, spacing: 7) {
                ForEach(1...3, id: \.self) { number in
                    Label(L.t("card.step\(number)"), systemImage: "\(number).circle.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.accent)
                }
            }
            if let hearing { Hint(L.f("card.note", hearing.title)) }
            Divider()
            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L.t("card.hashtags")).font(.caption.weight(.semibold)).foregroundStyle(Palette.accent)
                    Hint(L.t(storeLink ? "card.getApp" : "card.previewQR"))
                }
                Spacer(minLength: 4)
                if let qr {
                    Image(decorative: qr, scale: 1)
                        .resizable().interpolation(.none).frame(width: 94, height: 94)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
