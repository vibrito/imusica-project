import CryptoKit
import Foundation

/// Filesystem-safe cache keys.
///
/// Hashing rather than escaping the URL keeps filenames fixed-length, avoids
/// the path-length limit, and sidesteps every character a publisher might put
/// in a query string.
enum SHA256Digest {
    static func hexString(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
