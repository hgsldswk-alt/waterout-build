import SwiftUI

extension RootView {
    var home: some View {
        Page {
            HStack(alignment: .top) {
                Heading(title: L.t("app.title"), subtitle: L.t(audio.busy ? "tone.title" : "app.subtitle"))
                Spacer()
                if !audio.busy {
                    ActionButton(title: L.t("settings.title"), id: "home.settings", style: .text) {
                        path.append(.settings)
                    }
                }
            }
            RouteLine(output: audio.output, picker: !audio.busy)
            playbackDeck
            if audio.busy {
                Hint(L.t("tone.autoStop"))
                VStack(alignment: .leading, spacing: 5) {
                    Text(L.t("tone.after")).font(.headline)
                    Hint(L.t("tone.afterHint"))
                }.panel()
            } else {
                if let problem = audio.problem {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L.t(problem)).font(.subheadline.weight(.semibold))
                            .accessibilityIdentifier("audio.problem")
                        if audio.needsPhoneOutput {
                            HStack { Hint(L.t("audio.switch")) }
                        }
                    }.panel()
                }
                if showToneCard || library.data.milestones.completedChecklist {
                    ActionButton(title: L.t("card.title"), id: "home.card", icon: "checklist") {
                        milestone = library.data.milestones.completedChecklist
                        lastHearing = nil
                        path.append(.card)
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { transferActions }
                    VStack(alignment: .leading, spacing: 0) { transferActions }
                }.font(.footnote.weight(.semibold))
                Text(L.t("check.section")).font(.headline).accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    ForEach(SoundCheck.allCases) { check in
                        if check != .speaker { Divider().padding(.horizontal, 12) }
                        Button { openCheck(check) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(check.title).font(.subheadline.weight(.semibold))
                                    Hint(check.subtitle)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.weight(.bold))
                                    .foregroundStyle(Palette.accent).accessibilityHidden(true)
                            }
                            .frame(minHeight: 44)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("home.check." + check.rawValue)
                    }
                }.panel(inset: 0)
                ActionButton(title: L.t("help.home"), id: "home.help", style: .text) { path.append(.help) }
                feedback
            }
        }
    }

    @ViewBuilder private var transferActions: some View {
        Button { path.append(.history) } label: {
            Text(L.t("history.title")).frame(minHeight: 44).contentShape(Rectangle())
        }
            .accessibilityIdentifier("home.history")
        Button { openPresetImport() } label: {
            Text(L.t("import.title")).frame(minHeight: 44).contentShape(Rectangle())
        }
            .accessibilityIdentifier("home.import")
        Button { choosePresetFile() } label: {
            Text(L.t("import.file")).frame(minHeight: 44).contentShape(Rectangle())
        }
            .accessibilityIdentifier("home.importFile")
    }

    private var playbackDeck: some View {
        let duration = audio.job?.duration ?? Double(selectedPreset.seconds)
        let progress = audio.busy ? min(1, audio.elapsed / duration) : nil
        return VStack(alignment: .leading, spacing: 10) {
            if audio.busy {
                Eyebrow(audio.preparing ? L.t("audio.preparing") : L.f("tone.playing", Int(duration)))
            } else {
                HStack {
                    Text(selectedPreset.mode == .basic ? L.t("tone.title") : selectedPreset.mode.title).font(.headline)
                    Spacer()
                    Eyebrow(L.t("tone.offline"))
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(String(format: "%02d", audio.busy ? audio.remaining : selectedPreset.seconds))
                    .font(.system(.largeTitle, design: .monospaced).weight(.heavy))
                    .scaleEffect(1.35, anchor: .leading)
                    .padding(.trailing, 13)
                Hint(L.t(audio.busy ? "tone.left" : "tone.seconds"))
            }
            .padding(.vertical, 7)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("tone.countdown")
            Waveform(progress: progress)
            if let progress {
                ProgressView(value: progress).tint(Palette.accent).accessibilityLabel(L.t("tone.progress"))
                ActionButton(title: L.t("tone.stop"), id: "tone.stop", style: .stop, icon: "stop.fill") {
                    audio.stop()
                    playbackFinished = true
                }
            } else {
                ActionButton(title: L.t(playbackFinished ? "tone.replay" : "tone.play"), id: "tone.play",
                             style: .primary, icon: "play.fill", action: playTone)
                Hint(L.t("tone.safety"))
            }
        }.panel(Palette.tint)
    }

    func checkPage(_ check: SoundCheck) -> some View {
        Page {
            Heading(title: L.t("check.\(check.rawValue).title"), subtitle: check.subtitle)
            RouteLine(output: audio.output, picker: !audio.busy)
            if let problem = audio.problem {
                Text(L.t(problem)).font(.subheadline.weight(.semibold)).accessibilityIdentifier("audio.problem")
                    .panel()
                if audio.needsPhoneOutput { Hint(L.t("audio.switch")) }
                if audio.allowsMonoFallback || audio.receiverUnavailable {
                    ActionButton(title: L.t("check.fallback"), id: "check.fallback") {
                        if check == .receiver { openCheck(.speaker) }
                        else { runCheck(check, mono: true) }
                    }
                }
            }
            if check == .stereo {
                HStack(spacing: 10) {
                    channelButton(.left)
                    channelButton(.right)
                }
                Hint(L.t("check.stereoNote"))
            }
            if audio.busy {
                ActionButton(title: L.t("check.stop"), id: "check.stop", style: .stop, icon: "stop.fill") {
                    audio.stop()
                }
            } else {
                ActionButton(title: L.t("check.replay"), id: "check.replay", style: .primary, icon: "play.fill") {
                    runCheck(check)
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                Text(L.t("hearing.title")).font(.headline)
                if lastCheck == nil {
                    Hint(L.t("hearing.wait"))
                } else {
                    let choices: [Hearing] = lastCheckWasStereo ? [.both, .one, .skip] : [.clear, .muffled, .skip]
                    ForEach(choices) { hearing in
                        ActionButton(title: hearing.title, id: "hearing." + hearing.rawValue,
                                     style: lastHearing == hearing ? .primary : .secondary) {
                            lastHearing = hearing
                            lastCheck?.hearing = hearing
                        }
                    }
                }
            }.panel()
            if lastCheck != nil {
                ActionButton(title: L.t(milestone ? "card.keep" : "card.title"), id: "check.card", icon: "checklist") {
                    path.append(.card)
                }
            }
            feedback
        }
        .task(id: check) {
            guard pendingCheck == check else { return }
            pendingCheck = nil
            runCheck(check)
        }
        .onDisappear { if audio.job?.target == check { audio.stop() } }
    }

    private func channelButton(_ side: Channel) -> some View {
        let active = audio.activeChannel == side
        return Button { runCheck(.stereo, side: side) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(L.t(side == .left ? "channel.markLeft" : "channel.markRight"))
                    .font(.system(.largeTitle, design: .monospaced).weight(.heavy))
                Hint(side.title)
                if active { Eyebrow(L.t("channel.playing")) }
                else if audio.job == .check(.stereo, nil) && side == .right { Eyebrow(L.t("channel.next")) }
            }
            .panel(active ? Palette.tint : .white)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("channel." + side.rawValue)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}
