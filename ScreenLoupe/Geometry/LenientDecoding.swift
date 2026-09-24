import Foundation

extension KeyedDecodingContainer {
    /// The value for `key`, or `fallback` when it is missing or can't be decoded: a key a later
    /// version added, or a value only a later version knows, such as a new enum case. One such value
    /// then costs that setting alone, not everything saved beside it.
    func value<T: Decodable>(_ key: Key, or fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}

/// An array element that is `nil` when it can't be decoded, so one bad element doesn't fail the
/// whole array: `[Lenient<T>]` decodes, then `compactMap(\.value)`.
struct Lenient<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}
