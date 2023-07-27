import Foundation
import Parsing

/// Represents a boundary in a multipart request body.
struct Boundary {
    let value: String
    let type: BoundaryType

    enum BoundaryType {
        case initial, separator, terminator
    }

    private let crlf = "\r\n"

    var dataValue: Data {
        stringValue.data(using: .utf8)!
    }

    var stringValue: String {
        switch type {
        case .initial:
            return "--\(value)\(crlf)"
        case .separator:
            return "\(crlf)--\(value)\(crlf)"
        case .terminator:
            return "\(crlf)--\(value)--\(crlf)"
        }
    }
}

extension Boundary: ParserPrinter {
    func parse(_ input: inout Data) throws {
        guard let range = input.range(of: dataValue), range.startIndex == input.startIndex else {
            throw Parsers.MultipartParsingError("Data does not start with a boundary marker")
        }
        input.removeSubrange(range)
    }

    func print(_ output: (), into input: inout Data) throws {
        input.prepend(contentsOf: dataValue)
    }
}
