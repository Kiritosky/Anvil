import AnvilKit
import Foundation
import Testing

@testable import AnvilToolbox

@Suite("Umbenennen planen")
struct RenamePlanTests {
    private func urls(_ names: [String], in folder: String = "/tmp/anvil") -> [URL] {
        names.map { URL(fileURLWithPath: folder).appendingPathComponent($0) }
    }

    private func rules(_ build: (inout RenamePlan.Rules) -> Void) -> RenamePlan.Rules {
        var rules = RenamePlan.Rules()
        build(&rules)
        return rules
    }

    @Test
    func withoutRulesNothingChanges() {
        let plan = RenamePlan(files: urls(["a.txt", "b.txt"]), rules: RenamePlan.Rules())
        #expect(plan.changing.isEmpty)
        #expect(plan.entries.allSatisfy { $0.problem == .unchanged })
        // „Unverändert" ist kein Fehler — die Dateien bleiben einfach.
        #expect(plan.blocked.isEmpty)
        #expect(!plan.isReady)
    }

    @Test
    func searchAndReplaceWorksOnTheNameWithoutTheExtension() {
        let plan = RenamePlan(
            files: urls(["Urlaub Foto.jpg"]),
            rules: rules { $0.search = "Foto"; $0.replacement = "Bild" }
        )
        #expect(plan.entries[0].newName == "Urlaub Bild.jpg")
    }

    /// Die Endung darf nicht mitgesucht werden: sonst würde aus `.txt` bei
    /// einer Suche nach „t" schnell etwas anderes.
    @Test
    func theExtensionIsLeftAlone() {
        let plan = RenamePlan(
            files: urls(["text.txt"]),
            rules: rules { $0.search = "t"; $0.replacement = "T" }
        )
        #expect(plan.entries[0].newName == "TexT.txt")
    }

    @Test
    func aPatternBuildsTheWholeName() {
        let plan = RenamePlan(
            files: urls(["a.jpg", "b.jpg", "c.jpg"]),
            rules: rules { $0.pattern = "Bild-{n}" }
        )
        #expect(plan.entries.map(\.newName) == ["Bild-001.jpg", "Bild-002.jpg", "Bild-003.jpg"])
    }

    @Test
    func theCounterStartsAndStepsWhereItIsTold() {
        let plan = RenamePlan(
            files: urls(["a.txt", "b.txt"]),
            rules: rules {
                $0.pattern = "{n}"
                $0.counterStart = 10
                $0.counterStep = 5
                $0.counterWidth = 2
            }
        )
        #expect(plan.entries.map(\.newName) == ["10.txt", "15.txt"])
    }

    @Test
    func placeholdersReachEveryPart() {
        let plan = RenamePlan(
            files: urls(["notiz.md"]),
            rules: rules { $0.pattern = "{name}-{ext}-{n}" }
        )
        #expect(plan.entries[0].newName == "notiz-md-001.md")
    }

    @Test
    func casingAndSpacesAreAppliedAfterTheRest() {
        let plan = RenamePlan(
            files: urls(["Mein Langer Name.TXT"]),
            rules: rules { $0.casing = .lower; $0.spaceReplacement = "-" }
        )
        #expect(plan.entries[0].newName == "mein-langer-name.TXT")
    }

    @Test
    func aNewExtensionReplacesTheOldOne() {
        let plan = RenamePlan(
            files: urls(["daten.txt"]),
            rules: rules { $0.newExtension = "csv" }
        )
        #expect(plan.entries[0].newName == "daten.csv")
    }

    @Test
    func aRegularExpressionCanUseItsGroups() {
        let plan = RenamePlan(
            files: urls(["2026-08-10 Bericht.pdf"]),
            rules: rules {
                $0.search = #"^(\d{4})-(\d{2})-(\d{2}) (.+)$"#
                $0.replacement = "$4 ($1)"
                $0.isRegularExpression = true
            }
        )
        #expect(plan.entries[0].newName == "Bericht (2026).pdf")
    }

    /// Beim Tippen ist ein Ausdruck die meiste Zeit unfertig. Ein Fehler bei
    /// jedem Tastendruck hülfe niemandem.
    @Test
    func abrokenRegularExpressionLeavesTheNameAlone() {
        let plan = RenamePlan(
            files: urls(["a.txt"]),
            rules: rules { $0.search = "([unfertig"; $0.replacement = "x"; $0.isRegularExpression = true }
        )
        #expect(plan.entries[0].newName == "a.txt")
    }
}

@Suite("Umbenennen prüfen")
struct RenamePlanProblemTests {
    private func urls(_ names: [String]) -> [URL] {
        names.map { URL(fileURLWithPath: "/tmp/anvil").appendingPathComponent($0) }
    }

    /// Der eigentliche Zweck der Vorschau: Zwei Dateien mit demselben neuen
    /// Namen würden sich beim Ausführen gegenseitig überschreiben.
    @Test
    func twoFilesWithTheSameNewNameAreBothMarked() {
        var rules = RenamePlan.Rules()
        rules.pattern = "gleich"
        let plan = RenamePlan(files: urls(["a.txt", "b.txt"]), rules: rules)
        #expect(plan.entries.allSatisfy { $0.problem == .duplicate })
        #expect(!plan.isReady)
    }

    @Test
    func aNameThatIsAlreadyTakenIsMarked() {
        var rules = RenamePlan.Rules()
        rules.pattern = "belegt"
        let plan = RenamePlan(
            files: urls(["a.txt"]),
            rules: rules,
            existingNames: ["belegt.txt", "a.txt"]
        )
        #expect(plan.entries[0].problem == .occupied)
    }

    /// Eine Datei darf den Namen einer anderen aus demselben Stapel bekommen —
    /// die gibt ihn ja ab.
    @Test
    func namesInsideTheBatchDoNotCountAsTaken() {
        var rules = RenamePlan.Rules()
        rules.search = "a"
        rules.replacement = "b"
        let plan = RenamePlan(
            files: urls(["a.txt"]),
            rules: rules,
            existingNames: ["a.txt"]
        )
        #expect(plan.entries[0].newName == "b.txt")
        #expect(plan.entries[0].problem == nil)
    }

    @Test
    func anEmptyNameIsMarked() {
        var rules = RenamePlan.Rules()
        rules.search = "a"
        rules.replacement = ""
        let plan = RenamePlan(files: urls(["a"]), rules: rules)
        #expect(plan.entries[0].newName.isEmpty)
        #expect(plan.entries[0].problem == .empty)
    }

    @Test
    func aSlashOrColonIsMarked() {
        var rules = RenamePlan.Rules()
        rules.pattern = "Ordner/Datei"
        #expect(RenamePlan(files: urls(["a.txt"]), rules: rules).entries[0].problem == .invalidCharacter)

        rules.pattern = "12:30"
        #expect(RenamePlan(files: urls(["a.txt"]), rules: rules).entries[0].problem == .invalidCharacter)
    }

    @Test
    func aPlanIsOnlyReadyWhenNothingIsInTheWay() {
        var rules = RenamePlan.Rules()
        rules.pattern = "datei-{n}"
        let good = RenamePlan(files: urls(["a.txt", "b.txt"]), rules: rules)
        #expect(good.isReady)
        #expect(good.changing.count == 2)

        rules.pattern = "gleich"
        #expect(!RenamePlan(files: urls(["a.txt", "b.txt"]), rules: rules).isReady)
    }
}

@Suite("Umbenennen ausführen")
struct RenameExecutionTests {
    private func makeFolder() throws -> URL {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("anvil-rename-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func write(_ names: [String], in folder: URL) throws -> [URL] {
        try names.map { name in
            let url = folder.appendingPathComponent(name)
            try Data(name.utf8).write(to: url)
            return url
        }
    }

    @Test
    func filesActuallyGetTheirNewNames() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let files = try write(["eins.txt", "zwei.txt"], in: folder)
        var rules = RenamePlan.Rules()
        rules.pattern = "datei-{n}"
        let plan = RenamePlan(files: files, rules: rules)

        let outcome = try plan.execute()
        #expect(outcome.renamed == 2)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("datei-001.txt").path))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("datei-002.txt").path))
        #expect(!FileManager.default.fileExists(atPath: files[0].path))
    }

    /// Der Grund für die zwei Durchgänge: Beim Neunummerieren rutschen die
    /// Namen ineinander. In einem einzigen Durchgang überschriebe der erste
    /// Schritt die Datei, die als zweite dran wäre.
    @Test
    func renumberingDoesNotOverwriteTheFileItShiftsInto() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let files = try write(["1.txt", "2.txt"], in: folder)
        var rules = RenamePlan.Rules()
        rules.pattern = "{n}"
        rules.counterStart = 2
        rules.counterWidth = 1
        let plan = RenamePlan(files: files, rules: rules)

        // Der neue Name der ersten Datei ist der jetzige der zweiten.
        #expect(plan.entries.map(\.newName) == ["2.txt", "3.txt"])
        #expect(plan.isReady)

        try plan.execute()
        let two = try String(contentsOf: folder.appendingPathComponent("2.txt"), encoding: .utf8)
        let three = try String(contentsOf: folder.appendingPathComponent("3.txt"), encoding: .utf8)
        // Nichts ist verlorengegangen: In 2.txt steht, was vorher in 1.txt
        // stand, und in 3.txt, was in 2.txt stand.
        #expect(two == "1.txt")
        #expect(three == "2.txt")
    }

    @Test
    func theUndoLeadsBackToTheOriginalNames() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let files = try write(["eins.txt", "zwei.txt"], in: folder)
        var rules = RenamePlan.Rules()
        rules.pattern = "neu-{n}"
        let outcome = try RenamePlan(files: files, rules: rules).execute()

        for step in outcome.undo {
            try FileManager.default.moveItem(at: step.from, to: step.to)
        }
        #expect(FileManager.default.fileExists(atPath: files[0].path))
        #expect(FileManager.default.fileExists(atPath: files[1].path))
    }

    /// Ein Plan mit einem Problem wird gar nicht erst angefangen — sonst wäre
    /// die Hälfte umbenannt, wenn es klemmt.
    @Test
    func aPlanWithProblemsIsRefused() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let files = try write(["a.txt", "b.txt"], in: folder)
        var rules = RenamePlan.Rules()
        rules.pattern = "gleich"
        let plan = RenamePlan(files: files, rules: rules)

        #expect(throws: AnvilError.self) { try plan.execute() }
        #expect(FileManager.default.fileExists(atPath: files[0].path))
        #expect(FileManager.default.fileExists(atPath: files[1].path))
    }
}

@Suite("Nummern auffüllen")
struct RenameNumberTests {
    @Test
    func numbersArePaddedToTheGivenWidth() {
        #expect(RenamePlan.number(7, width: 3) == "007")
        #expect(RenamePlan.number(1234, width: 3) == "1234")
        #expect(RenamePlan.number(0, width: 1) == "0")
        #expect(RenamePlan.number(-3, width: 3) == "-003")
    }
}
