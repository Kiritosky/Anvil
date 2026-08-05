import Foundation
import Testing

@testable import AnvilKit

@Suite("FuzzyMatch")
struct FuzzyMatchTests {
    @Test
    func matchesSubsequences() {
        #expect(FuzzyMatch.matches(query: "jsf", in: "JSON Formatter"))
        #expect(FuzzyMatch.matches(query: "json", in: "JSON"))
        #expect(FuzzyMatch.matches(query: "xyz", in: "JSON Formatter") == false)
    }

    @Test
    func prefersWordBoundaryMatches() throws {
        let boundary = try #require(FuzzyMatch.score(query: "jf", in: "JSON Formatter"))
        let scattered = try #require(FuzzyMatch.score(query: "jf", in: "Jumbled offer"))
        #expect(boundary > scattered)
    }

    @Test
    func prefersConsecutiveMatches() throws {
        let consecutive = try #require(FuzzyMatch.score(query: "form", in: "Formatter"))
        let spread = try #require(FuzzyMatch.score(query: "form", in: "Flow of remarks"))
        #expect(consecutive > spread)
    }

    @Test
    func emptyQueryMatchesAnything() {
        #expect(FuzzyMatch.score(query: "", in: "whatever") == 0)
    }
}

@Suite("TextDiff")
struct TextDiffTests {
    @Test
    func identicalTextHasNoChanges() {
        let segments = TextDiff.words(from: "hallo welt", to: "hallo welt")
        #expect(segments.count == 1)
        #expect(segments.first?.kind == .unchanged)
    }

    @Test
    func removedWordsAreMarked() {
        let segments = TextDiff.words(from: "das ist ähm gut", to: "das ist gut")
        #expect(segments.contains { $0.kind == .removed && $0.text == "ähm" })
        #expect(segments.contains { $0.kind == .inserted } == false)
    }

    @Test
    func insertedWordsAreMarked() {
        let segments = TextDiff.words(from: "das gut", to: "das ist gut")
        #expect(segments.contains { $0.kind == .inserted && $0.text == "ist" })
    }

    @Test
    func adjacentSegmentsAreMerged() {
        let segments = TextDiff.words(from: "a b c d", to: "a d")
        let removed = segments.filter { $0.kind == .removed }
        #expect(removed.count == 1)
        #expect(removed.first?.text == "b c")
    }

    @Test
    func similarityReflectsHowMuchSurvived() {
        #expect(TextDiff.similarity(from: "eins zwei drei", to: "eins zwei drei") == 1)
        #expect(TextDiff.similarity(from: "eins zwei drei", to: "völlig anderer text") < 0.3)
    }
}

@Suite("SettingsStore")
struct SettingsStoreTests {
    @Test @MainActor
    func returnsDefaultsForUnsetKeys() {
        let store = SettingsStore.ephemeral()
        #expect(store[.favouriteTools].isEmpty)
        #expect(store[.autoCopyResults] == false)
    }

    @Test @MainActor
    func roundTripsValues() {
        let store = SettingsStore.ephemeral()
        store[.favouriteTools] = ["a", "b"]
        store[.historyLimitPerTool] = 25

        #expect(store[.favouriteTools] == ["a", "b"])
        #expect(store[.historyLimitPerTool] == 25)
    }

    @Test @MainActor
    func resetRestoresTheDefault() {
        let store = SettingsStore.ephemeral()
        store[.autoCopyResults] = true
        store.reset(.autoCopyResults)
        #expect(store[.autoCopyResults] == false)
    }
}
