import Testing
import AppKit
@testable import Speaky

@Suite("PasteService clipboard handling")
@MainActor
struct PasteServiceTests {
    private func makePasteboard() -> NSPasteboard {
        let pb = NSPasteboard(name: NSPasteboard.Name("speaky.tests.\(UUID().uuidString)"))
        pb.clearContents()
        return pb
    }

    private func make(_ pb: NSPasteboard, trusted: Bool = true) -> PasteService {
        PasteService(pasteboard: pb, isTrusted: { trusted }, sendPasteKeystroke: {}, readyDelay: 0.01, restoreDelay: 0.05)
    }

    /// Let the paste's background + main-queue hops run.
    private func settle() async throws { try await Task.sleep(for: .milliseconds(300)) }

    @Test("restores the user's clipboard after pasting")
    func restoresClipboard() async throws {
        let pb = makePasteboard()
        pb.setString("user copy", forType: .string)
        let service = make(pb)
        #expect(service.paste("dictated") == .pasted)
        #expect(pb.string(forType: .string) == "dictated")
        try await settle()
        #expect(pb.string(forType: .string) == "user copy")
    }

    @Test("a copy made right after the paste is not overwritten")
    func userCopyWins() async throws {
        let pb = makePasteboard()
        pb.setString("old", forType: .string)
        let service = make(pb)
        service.paste("dictated")
        pb.clearContents()
        pb.setString("copied just now", forType: .string)
        try await settle()
        #expect(pb.string(forType: .string) == "copied just now")
    }

    @Test("back-to-back dictations restore the clipboard from before the first one")
    func backToBack() async throws {
        let pb = makePasteboard()
        pb.setString("original", forType: .string)
        let service = make(pb)
        service.paste("first")
        service.paste("second")
        try await settle()
        #expect(pb.string(forType: .string) == "original")
    }

    @Test("an empty clipboard is left empty, not holding the dictation")
    func emptyStaysEmpty() async throws {
        let pb = makePasteboard()
        let service = make(pb)
        service.paste("dictated")
        try await settle()
        #expect(pb.string(forType: .string) == nil)
    }

    @Test("dictated text is marked transient for clipboard managers")
    func markedTransient() {
        let pb = makePasteboard()
        make(pb).paste("dictated")
        let types = pb.pasteboardItems?.first?.types.map(\.rawValue) ?? []
        #expect(types.contains("org.nspasteboard.TransientType"))
    }

    @Test("without Accessibility the text stays on the clipboard")
    func clipboardOnly() async throws {
        let pb = makePasteboard()
        pb.setString("old", forType: .string)
        #expect(make(pb, trusted: false).paste("dictated") == .clipboardOnly)
        try await settle()
        #expect(pb.string(forType: .string) == "dictated")
    }

    @Test("non-text clipboard contents survive the round trip")
    func preservesOtherTypes() async throws {
        let pb = makePasteboard()
        let png = NSPasteboard.PasteboardType.png
        pb.declareTypes([png, .string], owner: nil)
        pb.setData(Data([1, 2, 3]), forType: png)
        pb.setString("caption", forType: .string)
        let service = make(pb)
        service.paste("dictated")
        try await settle()
        withExtendedLifetime(service) {}
        #expect(pb.data(forType: png) == Data([1, 2, 3]))
        #expect(pb.string(forType: .string) == "caption")
    }
}
