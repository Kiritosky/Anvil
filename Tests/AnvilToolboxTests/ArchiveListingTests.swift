import AnvilKit
import Foundation
import Testing

@testable import AnvilToolbox

@Suite("Ein Archiv lesen")
struct ArchiveListingTests {
    /// So sieht `unzip -l` aus — Kopf, Trennlinie, Einträge, Summe.
    private let sample = """
        Archive:  beispiel.zip
          Length      Date    Time    Name
        ---------  ---------- -----   ----
                0  01-15-2026 10:00   projekt/
              412  01-15-2026 10:00   projekt/liesmich.md
            10240  01-15-2026 10:01   projekt/bild.png
              128  01-15-2026 10:02   projekt/notiz mit leerzeichen.txt
        ---------                     -------
            10780                     4 files
        """

    @Test
    func onlyTheEntriesAreRead() {
        let listing = ArchiveListing.read(sample)
        #expect(listing.entries.count == 4)
        #expect(listing.files.count == 3)
        #expect(listing.folders.count == 1)
    }

    /// Kopf- und Fußzeilen haben genauso vier Felder wie ein Eintrag. Ohne
    /// die Prüfung auf Zahl und Uhrzeit stünde „Length Date Time Name" als
    /// Datei in der Liste.
    @Test
    func headersAndFootersAreNoEntries() {
        let listing = ArchiveListing.read(sample)
        #expect(listing.entries.allSatisfy { !$0.path.contains("Name") })
        #expect(listing.entries.allSatisfy { !$0.path.contains("files") })
    }

    @Test
    func aNameMayContainSpaces() throws {
        let listing = ArchiveListing.read(sample)
        let entry = try #require(listing.entries.first { $0.path.hasSuffix(".txt") })
        #expect(entry.path == "projekt/notiz mit leerzeichen.txt")
        #expect(entry.name == "notiz mit leerzeichen.txt")
        #expect(entry.size == 128)
        #expect(entry.dateText == "01-15-2026 10:02")
    }

    @Test
    func sizesAddUp() {
        let listing = ArchiveListing.read(sample)
        #expect(listing.totalBytes == 10_780)
        #expect(listing.largest.first?.name == "bild.png")
    }

    @Test
    func aTrailingSlashMeansFolder() throws {
        let listing = ArchiveListing.read(sample)
        let folder = try #require(listing.folders.first)
        #expect(folder.isDirectory)
        #expect(folder.path == "projekt/")
        #expect(listing.files.allSatisfy { !$0.isDirectory })
    }

    // MARK: - Wie es gepackt ist

    @Test
    func oneCommonFolderDoesNotScatter() {
        let listing = ArchiveListing.read(sample)
        #expect(listing.roots == ["projekt"])
        #expect(!listing.scatters)
    }

    /// Der Fall, der einen Download-Ordner ruiniert: dreihundert Dateien
    /// ohne gemeinsame Hülle.
    @Test
    func severalEntriesAtTheTopScatter() {
        let listing = ArchiveListing.read("""
                  1  01-15-2026 10:00   eins.txt
                  1  01-15-2026 10:00   zwei.txt
                  1  01-15-2026 10:00   drei/vier.txt
            """)
        #expect(listing.roots == ["drei", "eins.txt", "zwei.txt"])
        #expect(listing.scatters)
    }

    @Test
    func kindsAreCountedByExtension() {
        let listing = ArchiveListing.read("""
                  1  01-15-2026 10:00   a.png
                  1  01-15-2026 10:00   b.png
                  1  01-15-2026 10:00   c.txt
                  1  01-15-2026 10:00   liesmich
            """)
        #expect(listing.kinds.first?.name == "png")
        #expect(listing.kinds.first?.count == 2)
        #expect(listing.kinds.contains { $0.name == localized("ohne Endung") })
    }

    // MARK: - Auffällige Pfade

    @Test
    func aPathLeavingTheFolderIsFlagged() {
        let entry = ArchiveEntry(path: "../../.ssh/authorized_keys", size: 1)
        #expect(entry.risk == .escapes)
    }

    @Test
    func anAbsolutePathIsFlagged() {
        #expect(ArchiveEntry(path: "/etc/hosts", size: 1).risk == .absolute)
        #expect(ArchiveEntry(path: "C:\\Windows\\system32", size: 1).risk == .absolute)
    }

    /// Zwei Punkte im Dateinamen sind kein Ausbruch — nur ein Dateiname.
    @Test
    func dotsInsideANameAreHarmless() {
        #expect(ArchiveEntry(path: "projekt/..versteckt.txt", size: 1).risk == nil)
        #expect(ArchiveEntry(path: "projekt/liesmich.md", size: 1).risk == nil)
    }

    @Test
    func riskyEntriesAreCollected() {
        let listing = ArchiveListing.read("""
                  1  01-15-2026 10:00   ok/datei.txt
                  1  01-15-2026 10:00   ../weg.txt
            """)
        #expect(listing.risky.count == 1)
        #expect(listing.risky.first?.risk == .escapes)
    }

    // MARK: - Ausgeben

    @Test
    func theReportHasAHeaderAndALinePerEntry() {
        let listing = ArchiveListing.read(sample)
        let lines = listing.report.components(separatedBy: "\n")
        #expect(lines.count == listing.entries.count + 1)
        #expect(lines[0].components(separatedBy: "\t").count == ArchiveListing.reportColumns.count)
        #expect(listing.rows().allSatisfy { $0.count == ArchiveListing.reportColumns.count })
    }

    @Test
    func anEmptyArchiveIsNoError() {
        let listing = ArchiveListing.read("")
        #expect(listing.isEmpty)
        #expect(listing.totalBytes == 0)
        #expect(!listing.scatters)
        #expect(listing.roots.isEmpty)
    }
}

@Suite("Archive ein- und auspacken")
struct ArchiveToolTests {
    @Test
    func onlyZipCountsAsAnArchive() {
        #expect(ArchiveTool.isArchive(URL(fileURLWithPath: "/tmp/a.zip")))
        #expect(ArchiveTool.isArchive(URL(fileURLWithPath: "/tmp/a.ZIP")))
        #expect(ArchiveTool.isArchive(URL(fileURLWithPath: "/tmp/app.ipa")))
        #expect(!ArchiveTool.isArchive(URL(fileURLWithPath: "/tmp/a.tar.gz")))
        #expect(!ArchiveTool.isArchive(URL(fileURLWithPath: "/tmp/ordner")))
    }

    /// Ein zweites Archiv desselben Namens darf das erste nicht überschreiben.
    @Test
    func theFolderNameIsCountedUp() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "anvil-archive-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let first = ArchiveTool.uniqueFolder(in: root, named: "projekt")
        #expect(first.lastPathComponent == "projekt")

        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        let second = ArchiveTool.uniqueFolder(in: root, named: "projekt")
        #expect(second.lastPathComponent == "projekt 2")
    }

    /// Die beiden Werkzeuge liegen auf jedem Mac; fehlt eines, sagt das
    /// Werkzeug es, statt beim ersten Klick zu scheitern.
    @Test
    func theSystemToolsAreThere() {
        #expect(ArchiveTool().isAvailable())
    }
}
