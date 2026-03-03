import SwiftUI

struct LanguagePicker: View {
    @Binding var selection: String

    var body: some View {
        Picker("Language", selection: $selection) {
            ForEach(Constants.supportedLanguages, id: \.code) { lang in
                Text(lang.name).tag(lang.code)
            }
        }
    }
}
