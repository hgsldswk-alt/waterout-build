import SwiftUI

extension RootView {
    var historyPage: some View {
        Page {
            Heading(title: L.t("history.title"), subtitle: L.t("history.hint"))
            ActionButton(title: L.t("history.new"), id: "history.new", style: .primary, icon: "plus") {
                before = nil
                after = nil
                recordTarget = .speaker
                path.append(.comparison)
            }.disabled(!Launch.freePeriod)
            if library.data.comparisons.isEmpty { Hint(L.t("history.empty")) }
            ForEach(library.data.comparisons) { record in
                let date = record.after.date.formatted(date: .abbreviated, time: .omitted)
                ActionButton(title: L.f("history.row", date, record.after.check.title),
                             id: "history.record") { path.append(.saved(record.id)) }
            }
        }
    }

    var comparisonPage: some View {
        Page {
            Heading(title: L.t("history.comparison"), subtitle: L.t("history.hint"))
            Picker(L.t("history.sample"), selection: $recordTarget) {
                ForEach([SoundCheck.speaker, .receiver]) { target in
                    Text(L.t("check.\(target.rawValue).title")).tag(target)
                }
            }
            .disabled(before != nil || after != nil || audio.busy)
            .accessibilityIdentifier("history.target")
            RouteLine(output: audio.output, picker: !audio.busy)
            recordingRow(before, first: true)
            recordingRow(after, first: false)
            if audio.busy {
                ActionButton(title: L.t("check.stop"), id: "history.stop", style: .stop) { audio.stop() }
            }
            if let problem = audio.problem { Hint(L.t(problem)).accessibilityIdentifier("audio.problem") }
            if let before, let after {
                let record = ListeningComparison(before: before, after: after)
                Hint(L.t(record.sameConditions ? "history.same" : "history.different"))
                ActionButton(title: L.t("history.save"), id: "history.save", style: .primary) {
                    guard library.ready else { return }
                    library.update { $0.comparisons.insert(record, at: 0) }
                    path.removeLast()
                    path.append(.saved(record.id))
                }.disabled(!library.ready || audio.busy)
            }
        }
        .onDisappear { if audio.busy { audio.stop() } }
    }

    private func recordingRow(_ sample: CheckSession?, first: Bool) -> some View {
        let key = first ? "before" : "after"
        let title = L.t("history." + key)
        return VStack(alignment: .leading, spacing: 8) {
            Eyebrow(title)
            if let sample {
                Hint(sample.conditions.text)
                Picker(L.t("hearing.title"), selection: Binding(get: {
                    (first ? before : after)?.hearing ?? .skip
                }, set: { hearing in
                    if first { before?.hearing = hearing }
                    else { after?.hearing = hearing }
                })) {
                    ForEach([Hearing.skip, .clear, .muffled]) { note in Text(note.title).tag(note) }
                }
                .accessibilityIdentifier("history.note." + key)
            }
            ActionButton(title: L.t("history.playSample"), id: "history.play." + key, icon: "play.fill") {
                audio.start(.check(recordTarget, nil)) { conditions in
                    let sample = CheckSession(check: recordTarget, conditions: conditions, hearing: .skip)
                    if first { before = sample; after = nil }
                    else { after = sample }
                    complete(recordTarget)
                }
            }.disabled(audio.busy || (!first && before == nil))
        }.panel()
    }

    func savedPage(_ id: UUID) -> some View {
        Page {
            Heading(title: L.t("history.comparison"), subtitle: L.t("history.hint"))
            if let record = library.data.comparisons.first(where: { $0.id == id }) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L.t(record.sameConditions ? "history.same" : "history.different"))
                        .font(.headline).accessibilityIdentifier("history.conditions")
                    if record.sameConditions { Hint(record.before.conditions.text) }
                }.panel(Palette.tint)
                HistoryNotes(record: record)
                ActionButton(title: L.t("history.export"), id: "history.export", icon: "square.and.arrow.up") {
                    share([record.exportText])
                }
                ActionButton(title: L.t("card.title"), id: "history.card", icon: "checklist") {
                    lastHearing = nil
                    path.append(.card)
                }
            }
            feedback
        }
    }
}

private struct HistoryNotes: View {
    let record: ListeningComparison

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 8) { rows }
            VStack(spacing: 8) { rows }
        }
    }

    @ViewBuilder private var rows: some View {
        note("history.before", record.before)
        note("history.after", record.after)
    }

    private func note(_ key: String, _ sample: CheckSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(L.t(key))
            Text(sample.hearing.title).font(.headline)
            if !record.sameConditions { Hint(sample.conditions.text) }
        }.panel()
    }
}
