import Foundation

protocol TimeProvider {
    func now() -> Date
    func currentTimeMillis() -> Int64
}

struct SystemTimeProvider: TimeProvider {
    func now() -> Date { Date() }
    func currentTimeMillis() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
}
