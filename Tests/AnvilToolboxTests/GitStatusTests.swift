import Foundation
import Testing

@testable import AnvilToolbox

@Suite("Git-Status lesen")
struct GitStatusTests {
    @Test
    func theBranchAndItsCounterpartAreRead() {
        let status = GitStatus(porcelain: "## main...origin/main\n")
        #expect(status.branch == "main")
        #expect(status.upstream == "origin/main")
        #expect(status.ahead == 0)
        #expect(status.behind == 0)
        #expect(status.isClean)
    }

    @Test
    func aheadAndBehindAreRead() {
        let status = GitStatus(porcelain: "## main...origin/main [ahead 3, behind 12]\n")
        #expect(status.ahead == 3)
        #expect(status.behind == 12)
    }

    @Test
    func onlyAheadIsAlsoAForm() {
        let status = GitStatus(porcelain: "## feature/x...origin/feature/x [ahead 1]\n")
        #expect(status.branch == "feature/x")
        #expect(status.ahead == 1)
        #expect(status.behind == 0)
    }

    /// Ein Zweig ohne Gegenstück ist kein Fehler — er ist der Normalfall,
    /// solange man noch nicht gepusht hat.
    @Test
    func aBranchWithoutACounterpartHasNone() {
        let status = GitStatus(porcelain: "## entwurf\n")
        #expect(status.branch == "entwurf")
        #expect(status.upstream == nil)
    }

    @Test
    func aDetachedHeadHasNoBranch() {
        let status = GitStatus(porcelain: "## HEAD (no branch)\n")
        #expect(status.branch == nil)
    }

    @Test
    func aFreshRepositoryIsMarkedAsSuch() {
        let status = GitStatus(porcelain: "## No commits yet on main\n")
        #expect(status.hasNoCommitsYet)
        #expect(status.branch == "main")
    }

    // MARK: - Änderungen

    private let mixed = """
    ## main...origin/main [ahead 2]
     M Sources/App.swift
    A  Sources/Neu.swift
    ?? notizen.txt
    MM Sources/Beides.swift
    """

    @Test
    func everyKindOfChangeLandsInItsOwnDrawer() {
        let status = GitStatus(porcelain: mixed)
        #expect(status.count(.untracked) == 1)
        // „A " ist vorgemerkt, „MM" ist beides — macht zwei vorgemerkte.
        #expect(status.count(.staged) == 2)
        // „ M" und die zweite Hälfte von „MM".
        #expect(status.count(.unstaged) == 2)
        #expect(!status.isClean)
    }

    /// Eine Datei, die vorgemerkt und danach nochmal geändert wurde, ist zwei
    /// Dinge gleichzeitig — und beide will man wissen.
    @Test
    func stagedAndChangedAgainCountsTwice() {
        let status = GitStatus(porcelain: "## main\nMM datei.txt")
        #expect(status.changes.count == 2)
        #expect(status.changes.allSatisfy { $0.path == "datei.txt" })
    }

    @Test
    func aConflictIsItsOwnKind() {
        let status = GitStatus(porcelain: "## main\nUU streit.txt\nAA beide.txt\n")
        #expect(status.count(.conflicted) == 2)
        #expect(status.count(.staged) == 0)
    }

    /// Bei einer Umbenennung zählt, wo die Datei jetzt liegt.
    @Test
    func aRenameIsReportedByItsNewName() {
        let status = GitStatus(porcelain: "## main\nR  alt.txt -> neu.txt\n")
        #expect(status.changes.count == 1)
        #expect(status.changes[0].path == "neu.txt")
        #expect(status.changes[0].stage == .staged)
    }

    /// Pfade mit Leerzeichen oder Umlauten setzt git in Anführungszeichen.
    @Test
    func aQuotedPathLosesItsQuotes() {
        let status = GitStatus(porcelain: "## main\n?? \"mit leerzeichen.txt\"\n")
        #expect(status.changes[0].path == "mit leerzeichen.txt")
    }

    /// Ignorierte Dateien sind keine Änderung, sondern eine Auskunft.
    @Test
    func ignoredFilesAreNotChanges() {
        let status = GitStatus(porcelain: "## main\n!! .build/\n")
        #expect(status.isClean)
    }

    @Test
    func windowsLineEndingsChangeNothing() {
        let status = GitStatus(porcelain: "## main...origin/main [ahead 1]\r\n M a.txt\r\n")
        #expect(status.branch == "main")
        #expect(status.ahead == 1)
        #expect(status.changes.count == 1)
    }

    // MARK: - Zusammenfassen

    @Test
    func unsavedWorkIsEitherUncommittedOrUnpushed() {
        #expect(GitStatus(porcelain: "## main...origin/main").hasUnsavedWork == false)
        #expect(GitStatus(porcelain: "## main...origin/main [ahead 1]").hasUnsavedWork)
        #expect(GitStatus(porcelain: "## main\n M a.txt").hasUnsavedWork)
        // Nur hinterher zu sein kostet nichts — das holt ein Pull.
        #expect(GitStatus(porcelain: "## main...origin/main [behind 9]").hasUnsavedWork == false)
    }

    @Test
    func theShortSummaryLeavesOutWhatIsZero() {
        #expect(GitStatus(porcelain: "## main...origin/main").shortSummary == "—")
        let busy = GitStatus(porcelain: "## main...origin/main [ahead 2, behind 1]\n M a.txt")
        #expect(busy.shortSummary == "2↑ 1↓ 1✚")
    }
}

@Suite("Git-Zweige lesen")
struct GitBranchTests {
    private func line(
        name: String,
        date: String = "2026-01-15T10:00:00+01:00",
        upstream: String = "",
        track: String = "",
        head: String = " "
    ) -> String {
        [name, date, upstream, track, head].joined(separator: "\t")
    }

    @Test
    func aBranchWithACounterpartIsRead() {
        let branches = GitBranch.list(
            line(name: "main", upstream: "origin/main", track: "[ahead 1, behind 2]", head: "*")
        )
        #expect(branches.count == 1)
        #expect(branches[0].name == "main")
        #expect(branches[0].upstream == "origin/main")
        #expect(branches[0].ahead == 1)
        #expect(branches[0].behind == 2)
        #expect(branches[0].isCurrent)
        #expect(branches[0].isGone == false)
    }

    /// Das Alter wird gegen den gelesenen Zeitpunkt selbst geprüft — eine
    /// feste Sekundenzahl hier wäre nur eine zweite Gelegenheit, sich zu
    /// verrechnen.
    @Test
    func theDateIsRead() throws {
        let branches = GitBranch.list(line(name: "main", date: "2026-01-15T10:00:00Z"))
        let commit = try #require(branches[0].lastCommit)
        #expect(branches[0].age(now: commit.addingTimeInterval(86_400 * 10)) == 10)
        #expect(branches[0].age(now: commit) == 0)
    }

    /// Ein Zweig, den es noch nie gab, hat kein Alter — und das ist etwas
    /// anderes als „heute".
    @Test
    func aBranchWithoutADateHasNoAge() {
        let branches = GitBranch.list(line(name: "main", date: ""))
        #expect(branches[0].lastCommit == nil)
        #expect(branches[0].age() == nil)
    }

    /// Der Fall, für den es das Werkzeug gibt.
    @Test
    func aBranchWhoseCounterpartIsGoneAndThatHasNothingOwnCanGo() {
        let branches = GitBranch.list(
            line(name: "feature/alt", upstream: "origin/feature/alt", track: "[gone]")
        )
        #expect(branches[0].isGone)
        #expect(branches[0].isStale)
    }

    /// Der Fall, in dem ein Vorschlag zum Aufräumen eine Aufforderung wäre,
    /// Arbeit wegzuwerfen.
    @Test
    func aGoneBranchWithOwnCommitsIsNeverSuggested() {
        let branches = GitBranch.list(
            line(name: "feature/alt", upstream: "origin/feature/alt", track: "[gone, ahead 3]")
        )
        #expect(branches[0].isGone)
        #expect(branches[0].ahead == 3)
        #expect(branches[0].isStale == false)
    }

    @Test
    func theCurrentBranchIsNeverStale() {
        let branches = GitBranch.list(
            line(name: "main", upstream: "origin/main", track: "[gone]", head: "*")
        )
        #expect(branches[0].isStale == false)
    }

    @Test
    func aLocalOnlyBranchHasNoCounterpart() {
        let branches = GitBranch.list(line(name: "entwurf"))
        #expect(branches[0].upstream == nil)
        #expect(branches[0].isGone == false)
        #expect(branches[0].isStale == false)
    }

    @Test
    func severalLinesBecomeSeveralBranches() {
        let text = [
            line(name: "main", upstream: "origin/main", head: "*"),
            line(name: "entwurf"),
            line(name: "feature/x", upstream: "origin/feature/x", track: "[gone]")
        ].joined(separator: "\n")

        let branches = GitBranch.list(text)
        #expect(branches.count == 3)
        #expect(branches.filter(\.isStale).count == 1)
    }

    @Test
    func nonsenseIsSkippedRatherThanCrashing() {
        #expect(GitBranch.list("kaputt\n\n").isEmpty)
        #expect(GitBranch.list("").isEmpty)
    }
}

@Suite("Repositories zusammenfassen")
struct GitOverviewTests {
    private func repository(
        _ name: String,
        porcelain: String,
        branches: [GitBranch] = [],
        failure: String? = nil
    ) -> GitRepository {
        GitRepository(
            url: URL(fileURLWithPath: "/Code/\(name)"),
            status: GitStatus(porcelain: porcelain),
            branches: branches,
            failure: failure
        )
    }

    private var overview: GitOverview {
        GitOverview([
            repository("sauber", porcelain: "## main...origin/main"),
            repository("geaendert", porcelain: "## main...origin/main\n M a.txt"),
            repository("nicht-gepusht", porcelain: "## main...origin/main [ahead 2]"),
            repository("hinterher", porcelain: "## main...origin/main [behind 5]"),
            repository("kaputt", porcelain: "", failure: "dubious ownership")
        ])
    }

    @Test
    func eachFilterFindsItsOwn() {
        #expect(overview.count == 5)
        #expect(overview.dirty.count == 1)
        #expect(overview.ahead.count == 1)
        #expect(overview.behind.count == 1)
        #expect(overview.failed.count == 1)
    }

    /// Hinterher zu sein ist nicht auffällig — das holt ein Pull. Auffällig
    /// ist, was nur hier liegt.
    @Test
    func attentionMeansSomethingCouldBeLost() {
        let names = overview.needingAttention.map(\.name)
        #expect(names.contains("geaendert"))
        #expect(names.contains("nicht-gepusht"))
        #expect(names.contains("kaputt"))
        #expect(!names.contains("hinterher"))
        #expect(!names.contains("sauber"))
    }

    @Test
    func staleBranchesAreCountedAcrossAllRepositories() {
        let stale = GitBranch(
            name: "alt",
            upstream: "origin/alt",
            isGone: true
        )
        let overview = GitOverview([
            repository("a", porcelain: "## main...origin/main", branches: [stale]),
            repository("b", porcelain: "## main...origin/main", branches: [stale, stale])
        ])
        #expect(overview.staleBranchCount == 3)
        // Ein alter Zweig ist ein Grund hinzusehen, auch wenn sonst alles
        // sauber ist.
        #expect(overview.needingAttention.count == 2)
    }

    @Test
    func theReportHasAHeaderAndOneLinePerRepository() {
        let lines = overview.report().split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 6)
        #expect(lines[0].split(separator: "\t").count == GitOverview.reportColumns.count)
        #expect(lines[1].hasPrefix("sauber\t"))
    }

    @Test
    func theReportFollowsTheFilter() {
        let lines = overview.report(.dirty).split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 2)
        #expect(lines[1].hasPrefix("geaendert\t"))
    }

    @Test
    func nothingInIsAnEmptyOverview() {
        #expect(GitOverview.empty.isEmpty)
        #expect(GitOverview.empty.staleBranchCount == 0)
        #expect(GitOverview.empty.needingAttention.isEmpty)
    }
}
