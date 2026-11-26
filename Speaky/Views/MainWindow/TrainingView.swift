import SwiftUI
@preconcurrency import KeyboardShortcuts

/// Voice training: the user reads passages aloud and Speaky learns which words
/// it gets wrong for their voice.
struct TrainingView: View {
    @Environment(AppState.self) private var appState
    @State private var newWords = ""
    @State private var confirmReset = false

    private var trainer: VoiceTrainer { appState.voiceTrainer }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                passageCard
                yourWordsCard
                learnedCard
                footer
            }
            .padding(20)
        }
        .background(Theme.bgDark.ignoresSafeArea())
        .navigationTitle("Voice training")
        .onAppear { trainer.isOpen = true }
        .onDisappear {
            trainer.isOpen = false
            if appState.isTrainingReading { appState.cancelRecording() }
        }
        .confirmationDialog("Reset voice training?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { trainer.resetTraining() }
        } message: {
            Text("Speaky forgets the mistakes it learned and your reading history. Your words are kept.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Read each passage aloud at your normal pace. Speaky compares what it heard with the text, learns the words it gets wrong for your voice, and fixes them in your dictations from then on.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if trainer.sessionCount > 0 {
                HStack(spacing: 10) {
                    stat("\(trainer.sessionCount)", trainer.sessionCount == 1 ? "reading" : "readings")
                    if let start = trainer.startingAccuracy, let now = trainer.currentAccuracy {
                        stat("\(percent(start)) → \(percent(now))", "accuracy")
                    }
                    stat("\(trainer.activeCorrectionCount)", trainer.activeCorrectionCount == 1 ? "fix in use" : "fixes in use")
                }
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall).fill(Theme.bgCard))
    }

    // MARK: - Passage

    private var passageCard: some View {
        card {
            HStack {
                Text(trainer.passage.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                    .textCase(.uppercase)
                Spacer()
                if trainer.phase == .ready || trainer.isFailed {
                    Button("Skip") { trainer.nextPassage() }
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                        .buttonStyle(.handCursor)
                }
            }

            passageText
                .font(.system(size: 19, weight: .regular, design: .serif))
                .lineSpacing(6)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if let review = trainer.review, trainer.phase == .reviewed {
                reviewSummary(review)
            }
            if case .failed(let message) = trainer.phase {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.recording)
            }

            controls
        }
    }

    /// The passage, with words Speaky got wrong marked after a reading.
    private var passageText: Text {
        let wrong = trainer.phase == .reviewed ? (trainer.review?.alignment.wrongReferenceIndices ?? []) : []
        var result = AttributedString()
        var index = 0
        for (position, word) in trainer.passage.text.split(separator: " ").enumerated() {
            if position > 0 { result += AttributedString(" ") }
            var piece = AttributedString(String(word))
            let counts = !WordAligner.normalize(String(word)).isEmpty
            if counts {
                if wrong.contains(index) {
                    piece.foregroundColor = Theme.recording
                    piece.underlineStyle = .single
                } else {
                    piece.foregroundColor = trainer.phase == .reviewed ? Theme.success : Theme.textPrimary
                }
                index += 1
            } else {
                piece.foregroundColor = Theme.textPrimary
            }
            result += piece
        }
        return Text(result)
    }

    private func reviewSummary(_ review: VoiceTrainer.Review) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            let total = review.alignment.reference.count
            let right = max(0, total - review.alignment.wrongWordCount)
            Text("Speaky got \(right) of \(total) words right (\(percent(review.alignment.accuracy))).")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textPrimary)

            if review.correctedAccuracy > review.alignment.accuracy {
                Text("With what it has learned, it would now get \(percent(review.correctedAccuracy)).")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.success)
            }
            if review.newMistakes > 0 {
                Text("It noted \(review.newMistakes) new \(review.newMistakes == 1 ? "word" : "words") to watch for.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }

            if !review.alignment.differences.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(review.alignment.differences.prefix(12).enumerated()), id: \.offset) { _, difference in
                        HStack(spacing: 6) {
                            Text(difference.expected.isEmpty ? "(extra)" : difference.expected.joined(separator: " "))
                                .foregroundStyle(Theme.textPrimary)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.textTertiary)
                            Text(difference.heard.isEmpty ? "(missed)" : difference.heard.joined(separator: " "))
                                .foregroundStyle(Theme.recording)
                        }
                        .font(.system(size: 12))
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall).fill(Theme.bgElevated))
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 10) {
            switch trainer.phase {
            case .ready, .failed:
                primaryButton(trainer.isFailed ? "Try again" : "Start reading", systemImage: "mic.fill", tint: Theme.amber) {
                    appState.beginTrainingReading()
                }
                .disabled(appState.isRecording || appState.isTranscribing)
                if let hotkey = KeyboardShortcuts.getShortcut(for: .toggleRecording) {
                    Text("or press \(hotkey.description)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                }
            case .reading:
                primaryButton("Done", systemImage: "stop.fill", tint: Theme.recording) {
                    appState.endTrainingReading()
                }
                Button("Cancel") { appState.cancelRecording() }
                    .buttonStyle(.handCursor)
                    .foregroundStyle(Theme.textSecondary)
                Text("Listening… read the passage, then click Done.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.amber)
            case .transcribing:
                ProgressView().controlSize(.small)
                Text("Checking what Speaky heard…")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            case .reviewed:
                primaryButton("Next passage", systemImage: "arrow.right", tint: Theme.amber) {
                    trainer.nextPassage()
                }
                Button("Read again") { appState.beginTrainingReading() }
                    .buttonStyle(.handCursor)
                    .foregroundStyle(Theme.textSecondary)
                    .disabled(appState.isRecording || appState.isTranscribing)
            }
            Spacer()
        }
        .padding(.top, 4)
    }

    private func primaryButton(_ title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(tint))
        }
        .buttonStyle(.handCursor)
    }

    // MARK: - Your words

    private var yourWordsCard: some View {
        card {
            sectionTitle("Your words", detail: "Names, products and terms you use. Speaky listens for them and practices them with you.")

            HStack {
                TextField("For example: Signit, Kubernetes, Nafath", text: $newWords)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addWords)
                Button("Add", action: addWords)
                    .disabled(newWords.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if !trainer.profile.customWords.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(trainer.profile.customWords, id: \.self) { word in
                        HStack(spacing: 4) {
                            Text(word).font(.system(size: 12))
                            Button {
                                trainer.removeCustomWord(word)
                            } label: {
                                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                            }
                            .buttonStyle(.handCursor)
                            .help("Remove \(word)")
                        }
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Theme.bgElevated))
                    }
                }
            }
        }
    }

    private func addWords() {
        trainer.addCustomWords(newWords)
        newWords = ""
    }

    // MARK: - Learned

    private var learnedCard: some View {
        card {
            sectionTitle("What Speaky learned", detail: "Words it heard wrong for your voice, and what you actually said. Swaps between two ordinary words (like \"there\" and \"their\") start switched off because they depend on context. Switch one on if it's always wrong for you.")

            if trainer.profile.corrections.isEmpty {
                Text("Nothing yet. Read a passage to start.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                VStack(spacing: 0) {
                    ForEach(trainer.sortedCorrections) { correction in
                        correctionRow(correction)
                        Divider().opacity(0.3)
                    }
                }
            }
        }
    }

    private func correctionRow(_ correction: VoiceProfile.Correction) -> some View {
        HStack(spacing: 8) {
            Text(correction.heard)
                .strikethrough()
                .foregroundStyle(Theme.textTertiary)
            Image(systemName: "arrow.right")
                .font(.system(size: 9))
                .foregroundStyle(Theme.textTertiary)
            Text(correction.meant)
                .foregroundStyle(Theme.textPrimary)
            Text(correction.count == 1 ? "seen once" : "seen \(correction.count) times")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            Toggle("", isOn: Binding(
                get: { trainer.isActive(correction) },
                set: { trainer.setActive(correction, $0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .help(trainer.isActive(correction) ? "Fixed in your dictations" : "Not applied")
            Button {
                trainer.deleteCorrection(correction)
            } label: {
                Image(systemName: "trash").font(.system(size: 11))
            }
            .buttonStyle(.handCursor)
            .foregroundStyle(Theme.textTertiary)
            .help("Forget this")
        }
        .font(.system(size: 13))
        .padding(.vertical, 6)
    }

    // MARK: - Footer

    private var footer: some View {
        @Bindable var settings = appState.settings
        return HStack {
            Toggle("Use training in dictation", isOn: Binding(
                get: { settings.useVoiceTraining },
                set: {
                    settings.useVoiceTraining = $0
                    appState.refreshVoiceTraining()
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.system(size: 12))
            .foregroundStyle(Theme.textSecondary)
            Spacer()
            Button("Reset training…") { confirmReset = true }
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .buttonStyle(.handCursor)
                .disabled(trainer.sessionCount == 0 && trainer.profile.corrections.isEmpty)
        }
    }

    // MARK: - Helpers

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium).fill(Theme.bgCard))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadiusMedium).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }

    private func sectionTitle(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

/// Lays out chips left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            var row = rows[rows.count - 1]
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.indices.isEmpty {
                let y = row.y + row.height + spacing
                rows.append(Row(indices: [index], y: y, width: size.width, height: size.height))
                continue
            }
            row.indices.append(index)
            row.width = needed
            row.height = max(row.height, size.height)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
