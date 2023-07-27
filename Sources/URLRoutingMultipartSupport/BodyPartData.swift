import Foundation
import URLRouting

/// A parseable body part from a multipart request body.
public struct BodyPartData: Equatable {
    /// The individual headers for this body part.
    public var headers: URLRequestData.Fields = .init([:], isNameCaseSensitive: false)
    /// The body part content.
    public var data: Data?
}
