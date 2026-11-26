import SwiftUI
import UIKit

extension RootView {
    var settingsPage: some View {
        Page {
            Heading(title: L.t("settings.title"), subtitle: L.t("settings.hint"))
            ActionButton(title: L.t("history.title"), id: "settings.history", icon: "list.bullet.rectangle") {
                path.append(.history)
            }
            ActionButton(title: L.t("preset.title"), id: "settings.presets", icon: "slider.horizontal.3") {
                draft = selectedPreset
                path.append(.presets)
            }
            ActionButton(title: L.t("import.title"), id: "settings.import", icon: "square.and.arrow.down") {
                openPresetImport()
            }
            ActionButton(title: L.t("help.title"), id: "settings.help", icon: "questionmark.circle") {
                path.append(.help)
            }
            feedback
        }
    }

    var presetsPage: some View {
        Page {
            Heading(title: L.t("preset.title"), subtitle: L.t("preset.hint"))
            VStack(alignment: .leading, spacing: 10) {
                Picker(L.t("preset.mode"), selection: Binding(get: { draft.mode }, set: {
                    draft = SoundPreset(mode: $0, seconds: draft.seconds)
                })) {
                    ForEach(SoundMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                .accessibilityIdentifier("preset.mode")
                Picker(L.t("preset.duration"), selection: Binding(get: { draft.seconds }, set: {
                    draft = SoundPreset(mode: draft.mode, seconds: $0)
                })) {
                    ForEach(SoundPreset.durations, id: \.self) { seconds in Text(L.f("preset.seconds", seconds)).tag(seconds) }
                }
                .accessibilityIdentifier("preset.duration")
                let canUseDraft = Launch.freePeriod || draft.mode == .basic ||
                    library.data.presets.contains(draft) || library.data.imported == draft
                ActionButton(title: L.t("preset.use"), id: "preset.use", style: .primary) {
                    usePreset(draft)
                }.disabled(!library.ready || !canUseDraft)
                ActionButton(title: L.t("preset.save"), id: "preset.save") {
                    if !library.data.presets.contains(draft) {
                        library.update { $0.presets.append(draft) }
                    }
                    pageMessage = "preset.savedNotice"
                }.disabled(!library.ready || !Launch.freePeriod)
            }.panel()
            if let imported = library.data.imported {
                Text(L.t("preset.imported")).font(.headline)
                presetRow(imported, id: "preset.imported")
            }
            if !library.data.presets.isEmpty {
                Text(L.t("preset.saved")).font(.headline)
                ForEach(Array(library.data.presets.enumerated()), id: \.offset) { index, saved in
                    presetRow(saved, id: "preset.saved.\(index)")
                }
            }
            ActionButton(title: L.t("preset.copy"), id: "preset.copy") {
                UIPasteboard.general.string = selectedPreset.code
                pageMessage = "preset.copied"
            }
            ActionButton(title: L.t("preset.export"), id: "preset.export", action: exportPreset)
            feedback
        }
    }

    private func presetRow(_ preset: SoundPreset, id: String) -> some View {
        ActionButton(title: L.f("preset.short", preset.mode.title, preset.seconds), id: id) { usePreset(preset) }
    }

    private func usePreset(_ preset: SoundPreset) {
        library.update { $0.selected = preset }
        path.removeAll()
    }

    var importPage: some View {
        Page {
            Heading(title: L.t("import.title"), subtitle: L.t("import.hint"))
            TextField(L.t("import.placeholder"), text: Binding(get: { importText }, set: { value in
                importText = value
                importedPreview = nil
                importFailed = false
            }), axis: .vertical)
                .lineLimit(2...4)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .panel()
                .accessibilityIdentifier("import.code")
            if Launch.testing, let code = ProcessInfo.processInfo.environment["WATEROUT_PRESET"] {
                Button(L.t("import.paste")) { pastePreset(code) }.accessibilityIdentifier("import.paste")
            } else {
                PasteButton(payloadType: String.self) { values in
                    if let code = values.first { pastePreset(code) }
                }.accessibilityLabel(Text(L.t("import.paste"))).accessibilityIdentifier("import.paste")
            }
            ActionButton(title: L.t("import.preview"), id: "import.preview", style: .primary, action: previewPreset)
            ActionButton(title: L.t("import.file"), id: "import.file", action: choosePresetFile)
            if importFailed { Text(L.t("import.invalid")).accessibilityIdentifier("import.invalid").panel() }
            if let preview = importedPreview {
                VStack(alignment: .leading, spacing: 9) {
                    Text(L.f("preset.short", preview.mode.title, preview.seconds))
                        .font(.headline).accessibilityIdentifier("import.result")
                    Hint(L.t("import.confirm"))
                    ActionButton(title: L.t("import.use"), id: "import.use", style: .primary) {
                        library.update { $0.imported = preview; $0.selected = preview }
                        path.removeAll()
                    }.disabled(!library.ready)
                }.panel(Palette.tint)
            }
            feedback
        }
    }

    var helpPage: some View {
        Page {
            Heading(title: L.t("help.title"), subtitle: L.t("app.subtitle"))
            VStack(alignment: .leading, spacing: 11) {
                Text(L.t("help.home")).font(.headline)
                Hint(L.t("help.wet"))
                Hint(L.t("help.limits"))
                Link(L.t("help.appleWater"), destination: CardCode.waterURL)
                    .frame(minHeight: 44).accessibilityIdentifier("help.appleWater")
                Link(L.t("help.appleLiquid"), destination: CardCode.liquidURL)
                    .frame(minHeight: 44).accessibilityIdentifier("help.appleLiquid")
            }.panel()
            VStack(alignment: .leading, spacing: 8) {
                Text(L.t("help.output")).font(.headline)
                Hint(L.t("audio.switch"))
                Hint(L.t("check.stereoNote"))
                Hint(L.t("help.silent"))
            }.panel()
            Link(L.t("help.privacy"), destination: CardCode.supportURL)
                .frame(minHeight: 44).accessibilityIdentifier("help.privacy")
        }
    }
}
