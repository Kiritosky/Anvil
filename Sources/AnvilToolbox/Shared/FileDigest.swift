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
