import AnvilKit
import CryptoKit
import Foundation

/// Prüfsummen von Dateien, ohne die Datei in den Arbeitsspeicher zu holen.
///
/// Der Grund, warum das nicht `Data(contentsOf:)` plus `SHA256.hash(data:)`
/// ist: eine Prüfsumme rechnet man über das, was gerade heruntergeladen wurde,
/// und das sind gerne mal vier Gigabyte. `Data(contentsOf:)` würde die
/// vollständig laden — der Weg über Blöcke braucht so viel Speicher wie ein
/// Block, egal wie groß die Datei ist.
enum FileDigest {
    /// So viel wird auf einmal gelesen. Groß genug, dass der Systemaufruf nicht
    /// ins Gewicht fällt, klein genug, dass es niemandem auffällt.
    static let chunkSize = 1024 * 1024

    /// Die Prüfsumme als Hex-Zeichenkette.
    static func hex<Function: HashFunction>(
        _ function: Function.Type,
        of url: URL
    ) throws -> String {
        var hasher = Function()
        try read(url) { hasher.update(data: $0) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// So weit reicht der schnelle Blick.
    ///
    /// Genug, dass zwei verschiedene Dateien sich fast immer schon hier
    /// unterscheiden — Kopfdaten, Auflösung, erste Bilder eines Videos stehen
    /// alle darin — und wenig genug, dass es einmal Kopfnicken kostet statt
    /// einer Wartezeit.
    static let prefixSize = 64 * 1024

    /// Die Prüfsumme über den Anfang der Datei.
    ///
    /// Für den Vergleich vieler großer Dateien: Zwei Videos von vier Gigabyte
    /// unterscheiden sich fast immer im ersten Block. Sie ganz zu lesen, um
    /// das festzustellen, sind acht Gigabyte für eine Antwort, die nach
    /// vierundsechzig Kilobyte feststand.
    static func prefixHex<Function: HashFunction>(
        _ function: Function.Type,
        of url: URL,
        bytes: Int = prefixSize
    ) throws -> String {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw AnvilError.storage(
                localized("„\(url.lastPathComponent)\" ließ sich nicht öffnen: \(error.localizedDescription)")
            )
        }
        defer { try? handle.close() }

        var hasher = Function()
        if let chunk = try handle.read(upToCount: bytes) {
            hasher.update(data: chunk)
        }
        return hex(hasher.finalize())
    }

    /// Alle vier auf einmal — und dabei die Datei nur einmal lesen.
    ///
    /// Vier Durchläufe wären bei einem großen Image vier Mal dieselbe Wartezeit
    /// für dasselbe Ergebnis.
    static func all(of url: URL) throws -> [(name: String, value: String)] {
        var md5 = Insecure.MD5()
        var sha1 = Insecure.SHA1()
        var sha256 = SHA256()
        var sha512 = SHA512()

        try read(url) { chunk in
            md5.update(data: chunk)
            sha1.update(data: chunk)
            sha256.update(data: chunk)
            sha512.update(data: chunk)
        }

        return [
            ("MD5", hex(md5.finalize())),
            ("SHA-1", hex(sha1.finalize())),
            ("SHA-256", hex(sha256.finalize())),
            ("SHA-512", hex(sha512.finalize()))
        ]
    }

    /// Was das Werkzeug anzeigt — je nachdem, wie viele Dateien da sind.
    ///
    /// Bei einer Datei nur die Prüfsumme: Man will sie neben die von der
    /// Webseite halten, und ein Dateiname daneben stört dabei. Ab zwei die
    /// shasum-Form mit Namen, weil eine Liste ohne Namen nutzlos ist.
    static func report<Function: HashFunction>(
        _ function: Function.Type,
        of urls: [URL]
    ) throws -> String {
        guard urls.count != 1 else { return try hex(function, of: urls[0]) }
        return lines(function, of: urls)
    }

    /// Mehrere Dateien, eine Zeile je Datei.
    ///
    /// Das Format ist nicht frei gewählt: `<prüfsumme>␣␣<name>` ist das, was
    /// `shasum` ausgibt und `shasum -c` wieder liest. Wer die Liste einer
    /// Veröffentlichung beilegt, gibt damit etwas heraus, das der Empfänger
    /// ohne Abtippen prüfen kann.
    ///
    /// Eine Datei, die nicht gelesen werden kann, bekommt ihre Zeile mit dem
    /// Fehler statt einer Prüfsumme — sie fällt nicht stillschweigend aus der
    /// Liste, sonst prüft jemand fünf von sechs Dateien und hält das für alle.
    static func lines<Function: HashFunction>(
        _ function: Function.Type,
        of urls: [URL]
    ) -> String {
        urls.map { url in
            do {
                return "\(try hex(function, of: url))  \(url.lastPathComponent)"
            } catch let error as AnvilError {
                return "\(localized("FEHLER")): \(error.message)  \(url.lastPathComponent)"
            } catch {
                return "\(localized("FEHLER")): \(error.localizedDescription)  \(url.lastPathComponent)"
            }
        }
        .joined(separator: "\n")
    }

    /// Dasselbe mit allen vier Verfahren, nach Datei gruppiert.
    static func allLines(of urls: [URL]) -> String {
        urls.map { url in
            let header = url.lastPathComponent
            do {
                let rows = try all(of: url)
                    .map { "  \($0.name.padding(toLength: 9, withPad: " ", startingAt: 0))\($0.value)" }
                    .joined(separator: "\n")
                return "\(header)\n\(rows)"
            } catch let error as AnvilError {
                return "\(header)\n  \(error.message)"
            } catch {
                return "\(header)\n  \(error.localizedDescription)"
            }
        }
        .joined(separator: "\n\n")
    }

    /// Die Größe der Datei, für die Anzeige daneben.
    static func size(of url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    // MARK: - Intern

    private static func hex<Digest: Sequence>(_ digest: Digest) -> String
    where Digest.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Reicht die Datei blockweise weiter.
    private static func read(_ url: URL, into consume: (Data) -> Void) throws {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw AnvilError.storage(
                localized("„\(url.lastPathComponent)\" ließ sich nicht öffnen: \(error.localizedDescription)")
            )
        }
        defer { try? handle.close() }

        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            consume(chunk)
        }
    }
}
