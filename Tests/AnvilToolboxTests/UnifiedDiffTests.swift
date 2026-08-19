import AnvilKit
import Foundation
import Testing

@testable import AnvilToolbox

@Suite("Patch lesen")
struct UnifiedDiffParsingTests {
    private let simple = """
    --- a/gruss.txt
    +++ b/gruss.txt
    @@ -1,3 +1,3 @@
     eins
    -zwei
    +ZWEI
     drei
    """

    @Test
    func aPatchHasFilesHunksAndCounts() {
        let diff = UnifiedDiff(parsing: simple)
        #expect(diff.files.count == 1)
        #expect(diff.files[0].oldPath == "gruss.txt")
        #expect(diff.files[0].newPath == "gruss.txt")
        #expect(diff.files[0].hunks.count == 1)
        #expect(diff.additions == 1)
        #expect(diff.deletions == 1)
    }

    /// Das `a/`- und `b/`-Präfix gehört Git, nicht dem Pfad — und hinter dem
    /// Namen steht oft noch ein Zeitstempel.
    @Test
    func pathsAreCleanedUp() {
        #expect(UnifiedDiff.path(from: "a/src/datei.swift") == "src/datei.swift")
        #expect(UnifiedDiff.path(from: "b/src/datei.swift") == "src/datei.swift")
        #expect(UnifiedDiff.path(from: "datei.txt\t2026-08-09 21:00:00") == "datei.txt")
        #expect(UnifiedDiff.path(from: "/dev/null") == "/dev/null")
    }

    @Test
    func theHunkHeaderIsReadWithAndWithoutCounts() throws {
        let full = try #require(UnifiedDiff.hunkHeader("@@ -12,7 +14,9 @@ func etwas()"))
        #expect(full.old == 12)
        #expect(full.oldCount == 7)
        #expect(full.new == 14)
        #expect(full.newCount == 9)
        #expect(full.heading == "func etwas()")

        let short = try #require(UnifiedDiff.hunkHeader("@@ -3 +3 @@"))
        #expect(short.oldCount == 1)
        #expect(short.heading.isEmpty)
    }

    @Test
    func severalFilesInOnePatchStayApart() {
        let diff = UnifiedDiff(parsing: """
        diff --git a/eins.txt b/eins.txt
        --- a/eins.txt
        +++ b/eins.txt
        @@ -1 +1 @@
        -alt
        +neu
        diff --git a/zwei.txt b/zwei.txt
        --- a/zwei.txt
        +++ b/zwei.txt
        @@ -1 +1 @@
        -alt
        +neu
        """)
        #expect(diff.files.count == 2)
        #expect(diff.files.map(\.displayPath) == ["eins.txt", "zwei.txt"])
    }

    @Test
    func newAndDeletedFilesAreRecognised() {
        let created = UnifiedDiff(parsing: "--- /dev/null\n+++ b/neu.txt\n@@ -0,0 +1 @@\n+inhalt")
        #expect(created.files[0].isNew)

        let removed = UnifiedDiff(parsing: "--- a/weg.txt\n+++ /dev/null\n@@ -1 +0,0 @@\n-inhalt")
        #expect(removed.files[0].isDeleted)
        #expect(removed.files[0].displayPath == "weg.txt")
    }

    @Test
    func aRenameIsNeitherNewNorDeleted() {
        let diff = UnifiedDiff(parsing: "--- a/alt.txt\n+++ b/neu.txt\n@@ -1 +1 @@\n-x\n+y")
        #expect(diff.files[0].isRename)
        #expect(!diff.files[0].isNew)
    }

    /// Ein Patch aus einem Ticket hat oben und unten Fließtext. Der soll nicht
    /// stören.
    @Test
    func textAroundThePatchIsIgnored() {
        let diff = UnifiedDiff(parsing: """
        Hallo, hier ist der Patch:

        --- a/datei.txt
        +++ b/datei.txt
        @@ -1 +1 @@
        -alt
        +neu

        Viele Grüße
        """)
        #expect(diff.files.count == 1)
        #expect(diff.files[0].hunks[0].additions == 1)
        #expect(diff.files[0].hunks[0].lines.count == 2)
    }

    @Test
    func nothingInIsNoPatch() {
        #expect(UnifiedDiff(parsing: "").isEmpty)
        #expect(UnifiedDiff(parsing: "nur ein Satz").isEmpty)
        #expect(UnifiedDiff(parsing: "--- a/x\n+++ b/x").isEmpty)
    }

    @Test
    func aNoNewlineNoteIsNotALineOfTheFile() {
        let diff = UnifiedDiff(parsing: """
        --- a/x
        +++ b/x
        @@ -1 +1 @@
        -alt
        +neu
        \\ No newline at end of file
        """)
        let hunk = diff.files[0].hunks[0]
        #expect(hunk.lines.count == 3)
        #expect(hunk.newLines == ["neu"])
        #expect(hunk.oldLines == ["alt"])
    }
}

@Suite("Patch umkehren")
struct UnifiedDiffReverseTests {
    private let diff = UnifiedDiff(parsing: """
    --- a/gruss.txt
    +++ b/gruss.txt
    @@ -1,3 +2,3 @@
     eins
    -zwei
    +ZWEI
     drei
    """)

    @Test
    func whatWasAddedIsRemovedAndTheOtherWayRound() {
        let back = diff.reversed
        #expect(back.additions == diff.deletions)
        #expect(back.deletions == diff.additions)
        #expect(back.files[0].hunks[0].newLines == diff.files[0].hunks[0].oldLines)
    }

    @Test
    func thePathsAndPositionsSwapSides() {
        let back = diff.reversed
        #expect(back.files[0].oldPath == diff.files[0].newPath)
        #expect(back.files[0].hunks[0].oldStart == diff.files[0].hunks[0].newStart)
    }

    @Test
    func reversingTwiceIsTheOriginal() {
        #expect(diff.reversed.reversed.text == diff.text)
    }
}

@Suite("Patch anwenden")
struct UnifiedDiffApplyTests {
    private let source = """
    eins
    zwei
    drei
    vier
    fünf
    """

    private func diff(_ text: String) -> UnifiedDiff { UnifiedDiff(parsing: text) }

    @Test
    func aSimpleChangeIsApplied() throws {
        let patch = diff("""
        --- a/x
        +++ b/x
        @@ -1,3 +1,3 @@
         eins
        -zwei
        +ZWEI
         drei
        """)
        let result = try patch.applied(patch.files[0], to: source)
        #expect(result == "eins\nZWEI\ndrei\nvier\nfünf")
    }

    @Test
    func applyingAndReversingGivesTheOriginalBack() throws {
        let patch = diff("""
        --- a/x
        +++ b/x
        @@ -1,3 +1,3 @@
         eins
        -zwei
        +ZWEI
         drei
        """)
        let changed = try patch.applied(patch.files[0], to: source)
        let back = patch.reversed
        #expect(try back.applied(back.files[0], to: changed) == source)
    }

    /// Der eigentliche Grund für die Suche: Patches werden gegen eine Fassung
    /// geschrieben und gegen eine leicht andere angewendet.
    @Test
    func aShiftedFileStillWorks() throws {
        let shifted = "davor\nnoch davor\n" + source
        let patch = diff("""
        --- a/x
        +++ b/x
        @@ -1,3 +1,3 @@
         eins
        -zwei
        +ZWEI
         drei
        """)
        let result = try patch.applied(patch.files[0], to: shifted)
        #expect(result == "davor\nnoch davor\neins\nZWEI\ndrei\nvier\nfünf")
    }

    /// Lieber ein Fehler als eine stille Verstümmelung.
    @Test
    func aPatchThatDoesNotFitThrows() {
        let patch = diff("""
        --- a/x
        +++ b/x
        @@ -1,3 +1,3 @@
         ganz
        -woanders
        +anders
         her
        """)
        #expect(throws: AnvilError.self) {
            try patch.applied(patch.files[0], to: source)
        }
    }

    @Test
    func severalHunksAreAppliedFromTheBack() throws {
        let patch = diff("""
        --- a/x
        +++ b/x
        @@ -1,2 +1,2 @@
         eins
        -zwei
        +ZWEI
        @@ -4,2 +4,2 @@
         vier
        -fünf
        +FÜNF
        """)
        let result = try patch.applied(patch.files[0], to: source)
        #expect(result == "eins\nZWEI\ndrei\nvier\nFÜNF")
    }

    /// Ein Abschnitt, der nur hinzufügt, hat keinen Kontext zum Suchen — die
    /// Zeilennummer ist dann alles, was es gibt.
    @Test
    func aHunkThatOnlyAddsUsesItsLineNumber() throws {
        let patch = diff("""
        --- a/x
        +++ b/x
        @@ -2,0 +3 @@
        +neu
        """)
        let result = try patch.applied(patch.files[0], to: source)
        #expect(result == "eins\nneu\nzwei\ndrei\nvier\nfünf")
    }

    @Test
    func aTrailingNewlineSurvives() throws {
        let patch = diff("""
        --- a/x
        +++ b/x
        @@ -1,1 +1,1 @@
        -eins
        +EINS
        """)
        let result = try patch.applied(patch.files[0], to: "eins\nzwei\n")
        #expect(result == "EINS\nzwei\n")
    }
}
