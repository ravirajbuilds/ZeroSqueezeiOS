import Foundation

/// Decodes `T` but never throws: a failed element becomes `value == nil`
/// instead of failing the whole array. Lets one corrupt record be dropped
/// while the rest of the history survives.
struct FailableDecodable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try? container.decode(T.self)
    }
}

enum StoreDecoding {
    /// Strict decode → lenient per-element decode → quarantine.
    ///
    /// A present-but-unparseable file is renamed to `*.corrupt` rather than
    /// returning `[]` and letting the next `append()` overwrite (and
    /// permanently destroy) recoverable history.
    static func loadArray<T: Decodable>(_ type: T.Type, from url: URL) -> [T] {
        guard let data = try? Data(contentsOf: url) else { return [] } // no file yet
        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode([T].self, from: data) {
            return decoded
        }
        if let lenient = try? decoder.decode([FailableDecodable<T>].self, from: data) {
            let recovered = lenient.compactMap(\.value)
            if !recovered.isEmpty {
                ZSLogger.warn(.data, "Recovered \(recovered.count) records after a partial decode failure")
                return recovered
            }
        }
        quarantine(url)
        return []
    }

    /// Rename a corrupt file aside so it isn't silently overwritten.
    static func quarantine(_ url: URL) {
        let dest = url.appendingPathExtension("corrupt")
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: url, to: dest)
            ZSLogger.error(.data, "Quarantined unparseable store file to \(dest.lastPathComponent)")
        } catch {
            // Best-effort; if the move fails the original stays put (no overwrite yet).
        }
    }
}
