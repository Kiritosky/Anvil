import AnvilKit
import Foundation
import Testing

@testable import AnvilToolbox

@Suite("Dubletten finden")
struct DuplicateScanTests {
    private func file(_ path: String, _ size: Int) -> DuplicateScan.File {
        DuplicateScan.File(url: URL(fileURLWithPath: path), size: size)
    }

    /// Der Inhalt steckt hier im Pfad: Was gleich heißt, ist gleich.
    private func digest(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    private func scan(_ files: [DuplicateScan.File]) -> DuplicateScan {
        DuplicateScan.scan(files) { digest($0) }
    }

    // MARK: - Die erste Stufe

    /// Zwei Dateien unterschiedlicher Größe können nie gleich sein — das ist
    /// der ganze Grund, warum die Suche in zwei Stufen läuft.
    @Test
    func onlyFilesOfTheSameSizeAreCandidates() {
        let candidates = DuplicateScan.candidates([
            file("/a/eins.txt", 100),
            file("/b/eins.txt", 100),
            file("/c/allein.txt", 50)
        ])
        #expect(candidates.count == 1)
        #expect(candidates[0].count == 2)
    }

    /// „Diese 240 leeren Dateien sind Dubletten" hilft niemandem.
    @Test
    func emptyFilesAreLeftOut() {
        #expect(DuplicateScan.candidates([file("/a", 0), file("/b", 0)]).isEmpty)
    }

    @Test
    func theBiggestGroupComesFirst() {
        let candidates = DuplicateScan.candidates([
            file("/a/klein.txt", 10), file("/b/klein.txt", 10),
            file("/a/gross.txt", 1_000), file("/b/gross.txt", 1_000)
        ])
        #expect(candidates[0][0].size == 1_000)
    }

    // MARK: - Die zweite Stufe

    @Test
    func sameSizeButDifferentContentIsNoDuplicate() {
        let result = scan([file("/a/eins.txt", 100), file("/b/zwei.txt", 100)])
        #expect(result.isEmpty)
        // Gelesen wurde trotzdem — anders ließe sich das nicht feststellen.
        #expect(result.hashed == 2)
    }

    @Test
    func sameContentIsAGroup() {
        let result = scan([file("/a/eins.txt", 100), file("/b/eins.txt", 100)])
        #expect(result.groups.count == 1)
        #expect(result.groups[0].count == 2)
        #expect(result.duplicateCount == 1)
        #expect(result.wastedBytes == 100)
    }

    /// Drei gleiche Dateien sind zwei zu viel, nicht drei.
    @Test
    func threeOfTheSameWasteTwice() {
        let result = scan([
            file("/a/x.txt", 100), file("/b/x.txt", 100), file("/c/x.txt", 100)
        ])
        #expect(result.duplicateCount == 2)
        #expect(result.wastedBytes == 200)
    }

    /// Was nach der Größe schon ausscheidet, wird nie gelesen — daran hängt
    /// die ganze Geschwindigkeit.
    @Test
    func whatIsAloneInItsSizeIsNeverRead() {
        let result = scan([
            file("/a/x.txt", 100), file("/b/x.txt", 100), file("/c/allein.txt", 7)
        ])
        #expect(result.examined == 3)
        #expect(result.hashed == 2)
    }

    @Test
    func theGroupWithTheMostToGainComesFirst() {
        let result = scan([
            file("/a/klein.txt", 10), file("/b/klein.txt", 10),
            file("/a/gross.txt", 5_000), file("/b/gross.txt", 5_000)
        ])
        #expect(result.groups.count == 2)
        #expect(result.groups[0].size == 5_000)
    }

    /// Eine Datei, die sich nicht lesen lässt, darf den Rest nicht aufhalten.
    @Test
    func aFileThatCannotBeReadIsSkipped() {
        let result = DuplicateScan.scan(
            [file("/a/x.txt", 100), file("/b/x.txt", 100), file("/c/kaputt.txt", 100)]
        ) { url in
            guard !url.lastPathComponent.hasPrefix("kaputt") else {
                throw AnvilError.storage("geht nicht")
            }
            return digest(url)
        }
        #expect(result.groups.count == 1)
        #expect(result.groups[0].count == 2)
    }

    @Test
    func nothingInIsAnEmptyScan() {
        #expect(scan([]).isEmpty)
        #expect(DuplicateScan.empty.wastedBytes == 0)
        #expect(DuplicateScan.empty.duplicateCount == 0)
    }

    // MARK: - Ausgeben

    @Test
    func theReportHasAHeaderAndOneLinePerFile() {
        let result = scan([file("/a/x.txt", 100), file("/b/x.txt", 100)])
        let lines = result.report.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 3)
        #expect(lines[0].split(separator: "\t").count == DuplicateScan.reportColumns.count)
    }

    /// Je Gruppe bleibt die erste Datei stehen — sonst wäre der Befehl kein
    /// Aufräumen, sondern ein Verlust.
    @Test
    func theCommandKeepsOneOfEachGroup() {
        let result = scan([
            file("/a/x.txt", 100), file("/b/x.txt", 100), file("/c/x.txt", 100)
        ])
        let lines = result.removalCommands.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(!result.removalCommands.contains("'/a/x.txt'"))
        #expect(result.removalCommands.contains("'/b/x.txt'"))
    }

    @Test
    func thePathsInTheCommandAreQuoted() {
        let result = scan([
            file("/Meine Projekte/x.txt", 100), file("/b/x.txt", 100)
        ])
        #expect(result.removalCommands.contains("'"))
        #expect(result.removalCommands.hasPrefix("rm '"))
    }

    @Test
    func nothingDoubleIsNoCommand() {
        #expect(scan([file("/a/x.txt", 100)]).removalCommands.isEmpty)
    }
}
