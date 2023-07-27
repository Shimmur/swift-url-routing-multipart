import Foundation
import Parsing

public struct DataToString: Conversion {
    private let encoding: String.Encoding

    init(encoding: String.Encoding) {
        self.encoding = encoding
    }

    public func apply(_ output: Data) throws -> String {
        guard let input = String(data: output, encoding: encoding)
        else { throw ConversionError() }
        return input
    }

    public func unapply(_ input: String) throws -> Data {
        guard let data = input.data(using: encoding)
        else { throw ConversionError() }
        return data
    }

    struct ConversionError: Error {}
}

extension Conversion where Self == DataToString {
    public static func string(encoding: String.Encoding) -> DataToString {
        DataToString(encoding: encoding)
    }
}
