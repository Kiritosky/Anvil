import AnvilKit
import Foundation
import Testing

@testable import AnvilToolbox

@Suite("IPv4")
struct IPv4NetworkTests {
    @Test
    func anAddressIsThirtyTwoBitsAndComesBackTheSame() throws {
        let address = try IPv4Address(parsing: "192.168.1.42")
        #expect(address.value == 0xC0A8_012A)
        #expect(address.text == "192.168.1.42")
    }

    /// Ohne `omittingEmptySubsequences: false` wären das gültige Adressen.
    @Test(arguments: [
        "1..2.3", "1.2.3.", ".1.2.3", "1.2.3", "1.2.3.4.5",
        "1.2.3.256", "1.2.3.00004", "1.2.3.-1", "eins.zwei.drei.vier", ""
    ])
    func whatIsNotAnAddressIsRejected(_ text: String) {
        #expect(throws: AnvilError.self) { try IPv4Address(parsing: text) }
    }

    @Test
    func hostBitsFallAwayButTheInputIsKept() throws {
        let network = try IPv4Network(parsing: "192.168.1.42/24")
        #expect(network.address.text == "192.168.1.42")
        #expect(network.networkAddress.text == "192.168.1.0")
        #expect(network.description == "192.168.1.0/24")
    }

    @Test
    func aMaskCountsAsAPrefixLength() throws {
        let written = try IPv4Network(parsing: "10.0.0.0/255.255.0.0")
        #expect(written.prefixLength == 16)

        let spaced = try IPv4Network(parsing: "10.0.0.0 255.255.0.0")
        #expect(spaced.prefixLength == 16)

        // Cisco schreibt die Maske andersherum; gemeint ist dasselbe Netz.
        let wildcard = try IPv4Network(parsing: "10.0.0.0/0.0.255.255")
        #expect(wildcard.prefixLength == 16)
    }

    @Test
    func aMaskWithGapsIsNoMask() {
        #expect(IPv4Network.prefixLength(mask: 0xFF00_FF00) == nil)
        #expect(IPv4Network.prefixLength(mask: 0xFFFF_FF00) == 24)
        #expect(IPv4Network.prefixLength(mask: 0) == 0)
        #expect(IPv4Network.prefixLength(mask: .max) == 32)
        #expect(throws: AnvilError.self) { try IPv4Network(parsing: "10.0.0.0/255.0.255.0") }
    }

    @Test
    func aBareAddressIsAHostRoute() throws {
        let network = try IPv4Network(parsing: "8.8.8.8")
        #expect(network.prefixLength == 32)
        #expect(network.isHostRoute)
        #expect(network.usableHostCount == 0)
        #expect(network.broadcastAddress == nil)
        #expect(network.firstUsableAddress == nil)
    }

    /// RFC 3021: bei /31 gibt es keinen Broadcast, dafür zwei benutzbare
    /// Adressen — die Standardrechnung `addressCount - 2` ergäbe hier 0.
    @Test
    func pointToPointHasNoBroadcast() throws {
        let network = try IPv4Network(parsing: "10.0.0.0/31")
        #expect(network.isPointToPoint)
        #expect(network.addressCount == 2)
        #expect(network.broadcastAddress == nil)
        #expect(network.note != nil)
    }

    @Test
    func theUsualNumbersForATwentyFour() throws {
        let network = try IPv4Network(parsing: "192.168.1.0/24")
        #expect(network.mask.text == "255.255.255.0")
        #expect(network.wildcard.text == "0.0.0.255")
        #expect(network.lastAddress.text == "192.168.1.255")
        #expect(network.broadcastAddress?.text == "192.168.1.255")
        #expect(network.firstUsableAddress?.text == "192.168.1.1")
        #expect(network.lastUsableAddress?.text == "192.168.1.254")
        #expect(network.addressCount == 256)
        #expect(network.usableHostCount == 254)
    }

    /// Ein /0 hat 2^32 Adressen — mehr, als in den `UInt32` passt, aus dem sie
    /// gerechnet werden.
    @Test
    func theWholeInternetDoesNotOverflow() throws {
        let network = try IPv4Network(parsing: "0.0.0.0/0")
        #expect(network.mask.value == 0)
        #expect(network.addressCount == 4_294_967_296)
        #expect(network.lastAddress.text == "255.255.255.255")
    }

    @Test
    func containsIsAboutTheNetworkAndNotTheWrittenAddress() throws {
        let network = try IPv4Network(parsing: "192.168.1.42/24")
        #expect(network.contains(try IPv4Address(parsing: "192.168.1.0")))
        #expect(network.contains(try IPv4Address(parsing: "192.168.1.255")))
        #expect(!network.contains(try IPv4Address(parsing: "192.168.2.1")))
    }

    @Test
    func splittingCountsAllOfThemAndShowsTheFirstFew() throws {
        let network = try IPv4Network(parsing: "10.0.0.0/8")
        #expect(try network.subnetCount(splittingInto: 10) == 4)
        #expect(try network.subnetCount(splittingInto: 24) == 65536)

        let shown = try network.split(into: 24, limit: 3)
        #expect(shown.count == 3)
        #expect(shown.map(\.description) == ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"])
    }

    @Test
    func aSubnetCannotBeBiggerThanItsParent() throws {
        let network = try IPv4Network(parsing: "10.0.0.0/16")
        #expect(throws: AnvilError.self) { try network.subnetCount(splittingInto: 8) }
        #expect(throws: AnvilError.self) { try network.subnetCount(splittingInto: 33) }
        // Gleich groß ist erlaubt: genau ein Teilnetz.
        #expect(try network.subnetCount(splittingInto: 16) == 1)
    }
}

@Suite("IPv6")
struct IPv6NetworkTests {
    @Test
    func compressionFollowsRFC5952() throws {
        #expect(try IPv6Address(parsing: "2001:0db8:0000:0000:0000:0000:0000:0001").compressedText
            == "2001:db8::1")
        #expect(try IPv6Address(parsing: "::").compressedText == "::")
        #expect(try IPv6Address(parsing: "::1").compressedText == "::1")
    }

    /// Ein einzelner Nullblock bleibt stehen — `::` würde dort nichts kürzen
    /// und die Adresse nur schwerer lesbar machen.
    @Test
    func aSingleZeroGroupIsNotCompressed() throws {
        let address = try IPv6Address(parsing: "2001:db8:0:1:1:1:1:1")
        #expect(address.compressedText == "2001:db8:0:1:1:1:1:1")
    }

    /// Bei zwei gleich langen Nullfolgen gewinnt die erste — sonst hinge die
    /// Ausgabe von der Laune des Algorithmus ab.
    @Test
    func theLongestRunWinsAndTiesGoToTheFirst() throws {
        let address = try IPv6Address(parsing: "2001:0:0:1:0:0:0:1")
        #expect(address.compressedText == "2001:0:0:1::1")

        let tie = try IPv6Address(parsing: "1:0:0:1:0:0:1:1")
        #expect(tie.compressedText == "1::1:0:0:1:1")
    }

    @Test
    func expandedTextIsAlwaysEightGroupsOfFour() throws {
        let address = try IPv6Address(parsing: "2001:db8::1")
        #expect(address.expandedText == "2001:0db8:0000:0000:0000:0000:0000:0001")
        #expect(address.groups.count == 8)
    }

    @Test(arguments: ["2001:db8:::1", "12345::", "2001:db8::1::2", "gggg::", ""])
    func whatIsNotAnAddressIsRejected(_ text: String) {
        #expect(throws: AnvilError.self) { try IPv6Address(parsing: text) }
    }

    @Test
    func aPrefixMasksAcrossTheSixtyFourBitBoundary() throws {
        let network = try IPv6Network(parsing: "2001:db8:abcd:1234::1/48")
        #expect(network.networkAddress.compressedText == "2001:db8:abcd::")
        #expect(network.lastAddress.compressedText == "2001:db8:abcd:ffff:ffff:ffff:ffff:ffff")

        let long = try IPv6Network(parsing: "2001:db8::abcd:1234/96")
        #expect(long.networkAddress.compressedText == "2001:db8::")
        #expect(long.lastAddress.compressedText == "2001:db8::ffff:ffff")
    }

    /// 2^128 passt in keine Ganzzahl dieses Rechners.
    @Test
    func theAddressCountIsTextBecauseItHasTo() throws {
        let all = try IPv6Network(parsing: "::/0")
        #expect(all.addressCountText == "340282366920938463463374607431768211456")

        let sixtyFour = try IPv6Network(parsing: "2001:db8::/64")
        #expect(sixtyFour.addressCountText == "18446744073709551616")
    }

    @Test
    func splittingStepsThroughTheHighWord() throws {
        let network = try IPv6Network(parsing: "2001:db8::/32")
        #expect(try network.subnetCountText(splittingInto: 48) == "65536")

        let shown = try network.split(into: 48, limit: 3)
        #expect(shown.map(\.description) == ["2001:db8::/48", "2001:db8:1::/48", "2001:db8:2::/48"])
    }

    @Test
    func splittingBelowTheSixtyFourBitBoundaryCarriesIntoTheLowWord() throws {
        let network = try IPv6Network(parsing: "2001:db8::/64")
        let shown = try network.split(into: 66, limit: 4)
        #expect(shown.map(\.description) == [
            "2001:db8::/66",
            "2001:db8:0:0:4000::/66",
            "2001:db8:0:0:8000::/66",
            "2001:db8:0:0:c000::/66"
        ])
    }
}

@Suite("Einordnung")
struct IPScopeTests {
    @Test(arguments: [
        ("10.1.2.3", IPScope.privateUse),
        ("172.16.0.1", IPScope.privateUse),
        ("172.32.0.1", IPScope.global),
        ("192.168.0.1", IPScope.privateUse),
        ("127.0.0.1", IPScope.loopback),
        ("169.254.1.1", IPScope.linkLocal),
        ("100.64.0.1", IPScope.sharedAddressSpace),
        ("192.0.2.1", IPScope.documentation),
        ("224.0.0.1", IPScope.multicast),
        ("8.8.8.8", IPScope.global)
    ])
    func v4AddressesLandInTheRightRange(_ text: String, _ expected: IPScope) throws {
        #expect(IPScope.of(try IPv4Address(parsing: text)) == expected)
    }

    /// 255.255.255.255 liegt in 240.0.0.0/4, ist aber nicht bloß „reserviert" —
    /// der engere Eintrag muss zuerst greifen.
    @Test
    func broadcastBeatsTheReservedBlockAroundIt() throws {
        #expect(IPScope.of(try IPv4Address(parsing: "255.255.255.255")) == .broadcast)
        #expect(IPScope.of(try IPv4Address(parsing: "240.0.0.1")) == .reserved)
    }

    @Test(arguments: [
        ("::", IPScope.unspecified),
        ("::1", IPScope.loopback),
        ("::ffff:192.168.1.1", IPScope.ipv4Mapped),
        ("fe80::1", IPScope.linkLocal),
        ("fd00::1", IPScope.uniqueLocal),
        ("ff02::1", IPScope.multicast),
        ("2001:db8::1", IPScope.documentation),
        ("2606:4700::1111", IPScope.global)
    ])
    func v6AddressesLandInTheRightRange(_ text: String, _ expected: IPScope) throws {
        #expect(IPScope.of(try IPv6Address(parsing: text)) == expected)
    }
}

@Suite("Netz, beide Familien")
struct IPNetworkTests {
    @Test
    func theFamilyComesOutOfTheInput() throws {
        #expect(try IPNetwork(parsing: "10.0.0.0/8").family == .v4)
        #expect(try IPNetwork(parsing: "2001:db8::/32").family == .v6)
        // Auch eine abgebildete IPv4-Adresse ist IPv6.
        #expect(try IPNetwork(parsing: "::ffff:10.0.0.1").family == .v6)
    }

    @Test
    func containmentSaysWhyItIsNoAndNotJustNo() throws {
        let network = try IPNetwork(parsing: "192.168.1.0/24")
        #expect(network.containment(of: "192.168.1.42") == .inside)
        #expect(network.containment(of: "192.168.2.42") == .outside)
        #expect(network.containment(of: "2001:db8::1") == .differentFamily)
        #expect(network.containment(of: "Kaffee") == .unreadable)
        #expect(network.containment(of: "   ") == .unreadable)
    }

    @Test
    func aTruncatedSplitSaysSo() throws {
        let network = try IPNetwork(parsing: "10.0.0.0/8")
        let split = try network.split(into: 24, limit: 4)
        #expect(split.countText == "65536")
        #expect(split.subnets.count == 4)
        #expect(split.isTruncated)

        let complete = try network.split(into: 10, limit: 64)
        #expect(complete.countText == "4")
        #expect(!complete.isTruncated)
    }

    @Test
    func onlyIPv4HasAHostCountAndAMask() throws {
        let v4 = try IPNetwork(parsing: "192.168.1.0/24")
        #expect(v4.usableHostCountText == "254")
        #expect(v4.maskText == "255.255.255.0")

        let v6 = try IPNetwork(parsing: "2001:db8::/64")
        #expect(v6.usableHostCountText == nil)
        #expect(v6.maskText == nil)
    }
}

@Suite("Zahlen ohne Ganzzahl")
struct IPMathTests {
    @Test
    func doublingDigitsGetsTheSameAnswerAsTheHardware() {
        #expect(IPMath.powerOfTwo(0) == "1")
        #expect(IPMath.powerOfTwo(1) == "2")
        #expect(IPMath.powerOfTwo(10) == "1024")
        #expect(IPMath.powerOfTwo(64) == "18446744073709551616")
        #expect(IPMath.powerOfTwo(128) == "340282366920938463463374607431768211456")
    }

    @Test
    func groupingUsesANarrowSpaceAndNotADot() {
        // Ein Punkt als Tausendertrenner wäre neben Adressen mit Punkten
        // schlicht nicht lesbar.
        #expect(IPMath.grouped("254") == "254")
        #expect(IPMath.grouped("1024") == "1024")
        #expect(IPMath.grouped("65536") == "65\u{202F}536")
        #expect(IPMath.grouped("4294967296") == "4\u{202F}294\u{202F}967\u{202F}296")
    }
}

@Suite("Liste von Netzen")
struct NetworkListTests {
    private let sample = """
    192.168.1.0/24
    # aus der Firewall
    10.0.0.0 255.0.0.0

    2001:db8::/48
    ; Kommentar
    keine Adresse
    """

    @Test
    func commentsAndBlankLinesFallAwayButBrokenLinesStay() {
        let list = NetworkList(parsing: sample)
        #expect(list.entries.count == 4)
        #expect(list.readableCount == 3)
        #expect(list.unreadableCount == 1)
        #expect(list.entries.last?.text == "keine Adresse")
        #expect(list.entries.last?.message != nil)
    }

    /// Eine Liste aus einer Windows-Datei ist eine Liste und keine Zeile.
    @Test
    func windowsLineEndingsSeparateNetworksToo() {
        let list = NetworkList(parsing: "10.0.0.0/8\r\n192.168.0.0/16\r\n")
        #expect(list.readableCount == 2)
    }

    @Test
    func normalFormIsWhatGoesBackIntoTheConfiguration() {
        let list = NetworkList(parsing: "192.168.1.42/24\n2001:0db8:0000::1/32")
        #expect(list.normalizedText == "192.168.1.0/24\n2001:db8::/32")
    }

    /// Eine einzelne Zeile ist die Ausnahme, nicht der Normalfall — die
    /// Oberfläche zeigt dann den Steckbrief statt einer Liste mit einem
    /// Eintrag.
    @Test
    func oneNetworkIsRecognisedAsOne() {
        #expect(NetworkList(parsing: "  10.0.0.0/8  ").single != nil)
        #expect(NetworkList(parsing: "10.0.0.0/8\n10.1.0.0/16").single == nil)
        #expect(NetworkList(parsing: "keine Adresse").single == nil)
        #expect(NetworkList(parsing: "\n\n# nur Kommentar\n").isEmpty)
    }

    @Test
    func lookingUpAnAddressFindsEveryNetworkItFallsInto() {
        let list = NetworkList(parsing: "10.0.0.0/8\n10.1.0.0/16\n192.168.0.0/16\n2001:db8::/32")
        let hits = list.entries(containing: "10.1.2.3")
        #expect(hits.count == 2)
        #expect(hits.map(\.text) == ["10.0.0.0/8", "10.1.0.0/16"])
        #expect(list.entries(containing: "8.8.8.8").isEmpty)
    }

    @Test
    func theReportHasAHeaderAndOneLinePerEntry() {
        let list = NetworkList(parsing: sample)
        let lines = list.report.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 5)
        #expect(lines[0].split(separator: "\t").count == 6)
        #expect(lines[1].hasPrefix("192.168.1.0/24\t"))
    }

    @Test
    func theDetailsOfANetworkAreTheSameOnScreenAndInTheClipboard() throws {
        let keys = try IPNetwork(parsing: "192.168.1.0/24").details.map(\.key)
        #expect(keys.contains(localized("Maske")))
        #expect(keys.contains(localized("Wildcard")))
        #expect(keys.contains(localized("Broadcast")))

        let v6Keys = try IPNetwork(parsing: "2001:db8::/64").details.map(\.key)
        #expect(!v6Keys.contains(localized("Broadcast")))
        #expect(v6Keys.contains(localized("Ausgeschrieben")))
    }
}
