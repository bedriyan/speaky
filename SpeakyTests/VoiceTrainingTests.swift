import Foundation
import Testing
@testable import Speaky

/// A tiny dictionary so tests don't depend on the system spell checker.
private let commonWords: Set<String> = [
    "the", "a", "to", "please", "sign", "it", "send", "notes", "about", "team", "there", "their",
    "they", "said", "move", "over", "by", "friday", "we", "use", "every", "day", "i", "work", "at",
    "cuba", "cooper", "netties", "is", "ready", "for", "demo", "check", "whether", "can", "you",
    "on", "of", "and", "deploy", "write", "right", "answer", "e-mail", "email", "good", "morning",
]
private let learner = TrainingLearner(isDictionaryWord: { commonWords.contains($0) })

@Suite("WordAligner")
struct WordAlignerTests {
    @Test("identical text has no differences, ignoring case and punctuation")
    func identical() {
        let a = WordAligner.align(reference: "Good morning, team.", transcript: "good morning team")
        #expect(a.differences.isEmpty)
        #expect(a.accuracy == 1)
    }

    @Test("finds a one-word substitution and where it is")
    func substitution() {
        let a = WordAligner.align(reference: "Please send the notes to the team", transcript: "Please sent the notes to the team")
        #expect(a.differences == [.init(expected: ["send"], heard: ["sent"], expectedStart: 1)])
        #expect(a.wrongReferenceIndices == [1])
        #expect(a.wrongWordCount == 1)
    }

    @Test("groups a word heard as several words")
    func split() throws {
        let a = WordAligner.align(reference: "I work at Signit every day", transcript: "I work at sign it every day")
        try #require(a.differences.count == 1)
        #expect(a.differences[0].expected == ["Signit"])
        #expect(a.differences[0].heard == ["sign", "it"])
        #expect(a.differences[0].expectedStart == 3)
    }

    @Test("reports missed and extra words")
    func missedAndExtra() {
        let missed = WordAligner.align(reference: "send the notes to the team", transcript: "send notes to the team")
        #expect(missed.differences == [.init(expected: ["the"], heard: [], expectedStart: 1)])
        let extra = WordAligner.align(reference: "send notes", transcript: "send the notes")
        #expect(extra.differences.count == 1)
        #expect(extra.differences[0].expected.isEmpty)
        #expect(extra.differences[0].heard == ["the"])
    }

    @Test("punctuation-only differences are not mistakes, but a different split is")
    func punctuation() {
        #expect(WordAligner.align(reference: "send an e-mail", transcript: "send an email").differences.isEmpty)
        #expect(WordAligner.align(reference: "today's plan", transcript: "todays plan").differences.isEmpty)
        #expect(WordAligner.align(reference: "every day", transcript: "everyday").differences.count == 1)
    }

    @Test("empty transcript means every word was missed")
    func emptyTranscript() {
        let a = WordAligner.align(reference: "send the notes", transcript: "")
        #expect(a.wrongWordCount == 3)
        #expect(a.accuracy == 0)
    }
}

@Suite("TrainingLearner")
struct TrainingLearnerTests {
    @Test("records what was heard and what was meant")
    func learnsCorrection() {
        let (profile, _) = learner.learn(reference: "I work at Signit every day", transcript: "I work at sign it every day", into: VoiceProfile())
        #expect(profile.corrections.count == 1)
        #expect(profile.corrections[0].heard == "sign it")
        #expect(profile.corrections[0].meant == "Signit")
        #expect(profile.corrections[0].count == 1)
    }

    @Test("seeing the same mistake again raises its count")
    func countsRepeats() {
        var profile = VoiceProfile()
        for _ in 0..<3 {
            profile = learner.learn(reference: "I work at Signit", transcript: "I work at sign it", into: profile).0
        }
        #expect(profile.corrections.count == 1)
        #expect(profile.corrections[0].count == 3)
    }

    @Test("a phrase the user really says is marked as a contradiction")
    func contradiction() {
        var profile = learner.learn(reference: "I work at Signit", transcript: "I work at sign it", into: VoiceProfile()).0
        profile = learner.learn(reference: "Please sign it", transcript: "Please sign it", into: profile).0
        #expect(profile.corrections[0].contradictions == 1)
        #expect(!learner.isActive(profile.corrections[0], in: profile))
    }

    @Test("an invented non-word is fixed after one sighting")
    func nonWordActive() {
        let profile = learner.learn(reference: "Check whether Kubernetes is ready", transcript: "Check whether cuba netties is ready", into: VoiceProfile()).0
        // "cuba netties" are both words in the test dictionary, so try one that isn't:
        let profile2 = learner.learn(reference: "Check whether Kubernetes is ready", transcript: "Check whether kubernetis is ready", into: VoiceProfile()).0
        #expect(!learner.isActive(profile.corrections[0], in: profile))
        #expect(learner.isActive(profile2.corrections[0], in: profile2))
    }

    @Test("a name heard as real words is fixed only after it is seen twice")
    func jargonNeedsTwo() {
        var profile = learner.learn(reference: "I work at Signit", transcript: "I work at sign it", into: VoiceProfile()).0
        #expect(!learner.isActive(profile.corrections[0], in: profile))
        profile = learner.learn(reference: "I work at Signit", transcript: "I work at sign it", into: profile).0
        #expect(learner.isActive(profile.corrections[0], in: profile))
    }

    @Test("swaps between two common words stay off unless the user turns them on")
    func commonSwapOff() {
        var profile = VoiceProfile()
        for _ in 0..<4 {
            profile = learner.learn(reference: "their team", transcript: "there team", into: profile).0
        }
        #expect(!learner.isActive(profile.corrections[0], in: profile))
        profile.corrections[0].userOverride = true
        #expect(learner.isActive(profile.corrections[0], in: profile))
    }

    @Test("ignores long garbled runs")
    func ignoresLongRuns() {
        let (profile, _) = learner.learn(
            reference: "please send the notes about the team to the demo",
            transcript: "we use every good morning answer right write",
            into: VoiceProfile()
        )
        #expect(profile.corrections.isEmpty)
    }

    @Test("vocabulary has the user's words and learned names, not ordinary words")
    func vocabulary() {
        var profile = VoiceProfile()
        profile.customWords = ["Nafath", "nafath ", "Signit"]
        profile = learner.learn(reference: "Check whether Kubernetes is ready", transcript: "Check whether kubernetis is ready", into: profile).0
        #expect(learner.vocabulary(for: profile) == ["Nafath", "Signit", "Kubernetes"])
    }
}

@Suite("PersonalCorrector")
struct PersonalCorrectorTests {
    private func corrector(_ pairs: [(String, String)]) -> PersonalCorrector {
        PersonalCorrector(corrections: pairs.map { VoiceProfile.Correction(heard: $0.0, meant: $0.1) })
    }

    @Test("replaces whole words and phrases only")
    func wholeWords() {
        let c = corrector([("sign it", "Signit"), ("kubernetis", "Kubernetes")])
        #expect(c.apply("I work at sign it. Kubernetis is up.") == "I work at Signit. Kubernetes is up.")
        #expect(c.apply("designit kubernetisx") == "designit kubernetisx")
    }

    @Test("matches across a comma Speaky inserted and ignores case")
    func commaAndCase() {
        let c = corrector([("sign it", "Signit")])
        #expect(c.apply("We use Sign, it daily") == "We use Signit daily")
    }

    @Test("keeps a capital at the start of a sentence")
    func capital() {
        let c = corrector([("there", "their")])
        #expect(c.apply("There team is here. there it is") == "Their team is here. their it is")
    }

    @Test("prefers the longest phrase")
    func longest() {
        let c = corrector([("sign", "Sine"), ("sign it", "Signit")])
        #expect(c.apply("sign it now") == "Signit now")
    }

    @Test("no corrections leaves text alone")
    func none() {
        #expect(PersonalCorrector.none.apply("Hello there.") == "Hello there.")
    }
}

@Suite("VoiceTrainer")
@MainActor
struct VoiceTrainerTests {
    private func makeTrainer() -> (VoiceTrainer, VoiceProfileFile) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("speaky-voice-\(UUID().uuidString)")
            .appendingPathComponent("VoiceProfile.json")
        let file = VoiceProfileFile(url: url)
        return (VoiceTrainer(file: file, learner: learner), file)
    }

    @Test("a reading is learned, scored and saved")
    func reading() {
        let (trainer, file) = makeTrainer()
        let passage = trainer.passage
        var heard = passage.text.split(separator: " ").map(String.init)
        heard[2] = "zzqx"
        trainer.finishReading(heard: heard.joined(separator: " "))

        #expect(trainer.phase == .reviewed)
        #expect(trainer.review?.alignment.wrongWordCount == 1)
        #expect(trainer.review?.newMistakes == 1)
        #expect(trainer.sessionCount == 1)
        // A non-word fix applies at once, so the corrected score is perfect.
        #expect(trainer.review?.correctedAccuracy == 1)
        #expect(file.load() == trainer.profile)
    }

    @Test("next passage moves through the built-in list")
    func next() {
        let (trainer, _) = makeTrainer()
        let first = trainer.passage
        trainer.nextPassage()
        #expect(trainer.passage != first)
        #expect(trainer.profile.nextPassageIndex == 1)
    }

    @Test("your words are added once and can be removed")
    func customWords() {
        let (trainer, _) = makeTrainer()
        #expect(trainer.addCustomWords("Signit, Nafath\nsignit, ") == 2)
        #expect(trainer.profile.customWords == ["Signit", "Nafath"])
        trainer.removeCustomWord("Signit")
        #expect(trainer.profile.customWords == ["Nafath"])
    }

    @Test("turning a fix on or off sticks, and back to automatic clears the override")
    func override() {
        let (trainer, _) = makeTrainer()
        trainer.finishReading(heard: trainer.passage.text.replacingOccurrences(of: "morning", with: "mourning"))
        guard let correction = trainer.profile.corrections.first else {
            Issue.record("expected a correction"); return
        }
        let automatic = trainer.isActive(correction)
        trainer.setActive(correction, !automatic)
        #expect(trainer.isActive(trainer.profile.corrections[0]) == !automatic)
        trainer.setActive(trainer.profile.corrections[0], automatic)
        #expect(trainer.profile.corrections[0].userOverride == nil)
    }

    @Test("reset keeps your words")
    func reset() {
        let (trainer, _) = makeTrainer()
        trainer.addCustomWords("Signit")
        trainer.finishReading(heard: "nothing like the passage")
        trainer.resetTraining()
        #expect(trainer.sessionCount == 0)
        #expect(trainer.profile.corrections.isEmpty)
        #expect(trainer.profile.customWords == ["Signit"])
    }

    @Test("your words get their own passage every few rounds")
    func yourWordsPassage() {
        var profile = VoiceProfile()
        profile.customWords = ["Signit"]
        profile.sessions = Array(repeating: .init(date: .now, passageTitle: "x", wordCount: 1, rawErrors: 0, correctedErrors: 0), count: 2)
        let passage = TrainingPassages.next(for: profile, practiceWords: [])
        #expect(passage.kind == .yourWords)
        #expect(passage.text.contains("Signit"))
    }
}

@Suite("Vocabulary prompt")
struct VocabularyPromptTests {
    @Test("lists words and stays short")
    func prompt() {
        #expect(VocabularyPrompt.make([]) == nil)
        #expect(VocabularyPrompt.make(["Signit", "Nafath"]) == "Signit, Nafath.")
        let long = VocabularyPrompt.make(Array(repeating: "Supercalifragilistic", count: 100))!
        #expect(long.count <= 600)
    }
}

@Suite("BoostGuard")
struct BoostGuardTests {
    @Test("keeps a one-word fix with the engine's punctuation")
    func keepsWordFix() {
        let original = "I work at Signet, please sign it today."
        let boosted = "I work at Signit please Signit today."
        #expect(BoostGuard.filter(original: original, boosted: boosted) == "I work at Signit, please sign it today.")
    }

    @Test("unchanged text passes through")
    func unchanged() {
        #expect(BoostGuard.filter(original: "Hello there.", boosted: "Hello there.") == "Hello there.")
    }

    @Test("rejects splitting one word into several")
    func rejectsSplit() {
        #expect(BoostGuard.filter(original: "the Kubernetes cluster", boosted: "the Cuba Netties cluster") == "the Kubernetes cluster")
    }
}
