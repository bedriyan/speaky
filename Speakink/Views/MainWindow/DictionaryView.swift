import SwiftUI

struct DictionaryView: View {
    @State private var replacements: [WordReplacement] = []
    @State private var newOriginal = ""
    @State private var newReplacement = ""

    var body: some View {
        Form {
            Section("Add Replacement") {
                HStack(spacing: 12) {
                    TextField("Word or phrase", text: $newOriginal)
                        .textFieldStyle(.roundedBorder)

                    Image(systemName: "arrow.right")
                        .foregroundStyle(Theme.textTertiary)

                    TextField("Replace with", text: $newReplacement)
                        .textFieldStyle(.roundedBorder)

                    Button("Add") {
                        addReplacement()
                    }
                    .disabled(newOriginal.trimmingCharacters(in: .whitespaces).isEmpty)
                    .foregroundStyle(Theme.amber)
                }

                Text("Examples: \"api\" → \"API\", \"speakink\" → \"Speakink\"")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }

            Section("Active Replacements") {
                if replacements.isEmpty {
                    Text("No word replacements configured.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    ForEach(replacements) { item in
                        HStack {
                            Text(item.original)
                                .foregroundStyle(Theme.textPrimary)
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundStyle(Theme.textTertiary)
                            Text(item.replacement)
                                .foregroundStyle(Theme.amber)
                            Spacer()
                            Button {
                                removeReplacement(item)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red.opacity(0.7))
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Dictionary")
        .onAppear {
            replacements = WordReplacementStore.load()
        }
    }

    private func addReplacement() {
        let original = newOriginal.trimmingCharacters(in: .whitespaces)
        guard !original.isEmpty else { return }
        let replacement = WordReplacement(
            original: original,
            replacement: newReplacement.trimmingCharacters(in: .whitespaces)
        )
        replacements.append(replacement)
        WordReplacementStore.save(replacements)
        newOriginal = ""
        newReplacement = ""
    }

    private func removeReplacement(_ item: WordReplacement) {
        replacements.removeAll { $0.id == item.id }
        WordReplacementStore.save(replacements)
    }
}
