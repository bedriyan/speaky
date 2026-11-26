import Foundation

/// Text the user reads aloud during training.
struct TrainingPassage: Equatable, Sendable, Identifiable {
    enum Kind: Sendable { case builtIn, yourWords, practice }
    let id: String
    let title: String
    let text: String
    let kind: Kind
}

enum TrainingPassages {
    /// Everyday dictation: emails, meetings, planning and technical work, with a
    /// spread of sounds that engines commonly confuse (th/s/f, v/w, b/p, r/l,
    /// short vowels, word endings). No digits, so spoken numbers can't be
    /// "wrong" just for being written as words.
    static let builtIn: [TrainingPassage] = [
        p("warm-up", "Warm-up",
          "Good morning everyone. I hope you all had a restful weekend. Today I want to walk through the plan for this week, share a few updates from the leadership meeting, and answer any questions you might have about the new process."),
        p("email", "Writing an email",
          "Hi team, thank you for the quick reply. I have attached the revised proposal with the changes we discussed on Thursday. Please review the pricing section and let me know if anything looks unclear before we send it to the customer."),
        p("meeting", "Meeting notes",
          "Action items from today's meeting. The product team will finalize the requirements by Wednesday. Engineering will estimate the effort and flag any risks. Support will prepare a short guide for customers, and we will review progress together next week."),
        p("tech", "Technical update",
          "The deployment failed because the database migration timed out. We rolled back the release, increased the timeout, and added a health check before traffic is switched over. The fix is now in staging and passed all automated tests."),
        p("sounds-1", "Tricky sounds",
          "Three thin thieves thought they would thrive through the thunder. Very few vans were waiting on the west wing of the village. The brave pilot parked the big blue plane beside the busy port."),
        p("sounds-2", "Similar words",
          "Their team said they're ready to move over there by Friday. I would like to write the right answer, but it's hard to know whether the weather will change. Please accept the offer, except for the last clause."),
        p("planning", "Planning",
          "Our priority for the next quarter is reliability. We will reduce incidents, improve monitoring, and make on-call less stressful. Every team should choose one measurable goal, share it with their manager, and report on it at the end of each month."),
        p("customer", "Customer reply",
          "Thank you for reaching out and sorry for the inconvenience. I have checked your account and the issue is now resolved. If you still see the error after refreshing the page, please reply to this email and we will look into it straight away."),
        p("security", "Security",
          "Never share your password or verification code with anyone, including our staff. Enable two-factor authentication, review active sessions regularly, and report any suspicious activity to the security team immediately."),
        p("endings", "Word endings",
          "She asked whether he finished the reports. They walked, talked, and laughed while the kids played outside. The developer fixed the bugs, tested the changes, and pushed the updates before the deadline passed."),
        p("product", "Product description",
          "The new dashboard gives managers a clear view of documents waiting for approval. Users can filter by status, search by name, and export a summary. Notifications remind signers when a request is about to expire."),
        p("conversation", "Natural speech",
          "Honestly, I think we should keep it simple. Let's ship the smaller version first, see how people actually use it, and then decide what to build next. There's no point polishing features nobody asked for."),
    ]

    private static func p(_ id: String, _ title: String, _ text: String) -> TrainingPassage {
        TrainingPassage(id: id, title: title, text: text, kind: .builtIn)
    }

    private static let templates = [
        "Please send the latest notes about %@ to the whole team.",
        "I spoke with %@ this morning and everything looks good.",
        "We need to update %@ before the end of the week.",
        "Can you check whether %@ is ready for the demo?",
        "Yesterday %@ came up again in the planning meeting.",
        "Let me know what you think about %@ when you have a moment.",
    ]

    /// Sentences built around the user's own words (names, products, jargon).
    static func yourWords(_ words: [String]) -> TrainingPassage? {
        guard !words.isEmpty else { return nil }
        return TrainingPassage(
            id: "your-words", title: "Your words",
            text: sentences(for: words, offset: 0), kind: .yourWords
        )
    }

    /// Sentences built around words Speaky got wrong before, so it can confirm it learned them.
    static func practice(_ words: [String]) -> TrainingPassage? {
        guard !words.isEmpty else { return nil }
        return TrainingPassage(
            id: "practice", title: "Words to practice",
            text: sentences(for: words, offset: 3), kind: .practice
        )
    }

    private static func sentences(for words: [String], offset: Int) -> String {
        words.prefix(8).enumerated().map { index, word in
            String(format: templates[(index + offset) % templates.count], word)
        }.joined(separator: " ")
    }

    /// What to read next: built-in passages in turn, with the user's words and
    /// earlier mistakes mixed in every third round once there are any.
    static func next(for profile: VoiceProfile, practiceWords: [String]) -> TrainingPassage {
        let round = profile.sessions.count
        if round % 3 == 2 {
            if round % 6 == 2, let passage = yourWords(profile.customWords) ?? practice(practiceWords) { return passage }
            if let passage = practice(practiceWords) ?? yourWords(profile.customWords) { return passage }
        }
        return builtIn[profile.nextPassageIndex % builtIn.count]
    }
}
