import Foundation
import OrderedCollections
import URLRouting

extension Parsers {
    public struct MultipartParsingError: Error {
        public let message: String

        init(_ message: String) {
            self.message = message
        }
    }

    /// Parses a multipart request body into well structured parts.
    ///
    /// When parsing an incoming request, it will pass the boundary value from the HTTP headers and use
    /// that to parse the body - when printing back to URL request data, it will use the provided print boundary.
    ///
    /// This parser is intended to be used instead of the normal `Body` parser and cannot be used alongside it -
    /// it will attempt to fully consume the entire body data and will fail if it does not.
    ///
    public struct MultipartBody<BodyPartParsers: Parser>: Parser where BodyPartParsers.Input == ArraySlice<BodyPartData> {
        private let printBoundary: String
        private let partParsers: BodyPartParsers

        /// Initializes a new multipart body parser.
        ///
        /// - Parameters:
        ///    - printBoundary: A string to be used as part of the part boundary string when printing.
        ///    - build: A parser builder closure that should return a parser of the individual body parts.
        ///
        public init(printBoundary: String, @ParserBuilder<ArraySlice<BodyPartData>> build: () -> BodyPartParsers) {
            self.printBoundary = printBoundary
            self.partParsers = build()
        }

        public func parse(_ input: inout URLRequestData) throws -> BodyPartParsers.Output {
            guard var body = input.body
            else {
                throw MultipartParsingError("Expected request data to have a body but body was nil.")
            }
            // Parse the boundary from the request headers.
            let boundaryValue = try HeaderBoundaryValue().parse(input)
            // Now we need to parse the multipart data into something more structured that
            // can be passed to the part parsers. PartsParser will try to parse the entire
            // request body and will fail if it does not.
            let parts = try BodyParts(boundaryValue: boundaryValue).parse(&body)
            input.body = body
            // Now we need to exhaustively parse each part.
            return try partParsers.parse(parts)
        }
    }

    struct BodyParts: ParserPrinter {
        let boundaryValue: String

        var body: some ParserPrinter<Data, [BodyPartData]> {
            Boundary(value: boundaryValue, type: .initial)
            Many {
                BodyPart(boundaryValue: boundaryValue)
            } separator: {
                Boundary(value: boundaryValue, type: .separator)
            } terminator: {
                Boundary(value: boundaryValue, type: .terminator)
            }
            End()
        }
    }

    struct BodyPart: ParserPrinter {
        let boundaryValue: String

        private var nextBoundaryValue: Data {
            "\r\n--\(boundaryValue)".data(using: .utf8)!
        }

        var body: some ParserPrinter<Data, BodyPartData> {
            Parse(.memberwise(BodyPartData.init)) {
                PartHeaderFields()
                Optionally { PrefixUpTo(nextBoundaryValue) }
            }
        }
    }

    /// Parses the content-type header for a match on `multipart/form-data` and extracts the boundary value.
    ///
    /// When printing, this will overwrite any existing content-type header with a `multipart/form-data` and the
    /// boundary value.
    struct HeaderBoundaryValue: ParserPrinter {
        func parse(_ input: inout URLRequestData) throws -> String {
            guard
                let contentTypes = input.headers["Content-Type"],
                let contentType = contentTypes.compactMap({ $0 }).first,
                contentType.hasPrefix("multipart/form-data")
            else {
                throw MultipartParsingError("Expected to find a single content-type header with type multipart/form-data.")
            }
            guard let boundaryRange = contentType.range(of: "boundary=") else {
                throw MultipartParsingError("Could not find boundary value in content-type header.")
            }
            input.headers["Content-Type"] = nil
            return String(contentType[boundaryRange.upperBound..<contentType.endIndex])
        }

        func print(_ output: String, into input: inout URLRequestData) throws {
            input.headers["Content-Type"] = ["multipart/form-data; boundary=\(output)"]
        }
    }

    /// A parser-printer of multi-part form data values, passed in a content-disposition header for a part inside a multipart HTTP request.
    public struct MultipartFormData<FieldParsers: ParserPrinter>: ParserPrinter where FieldParsers.Input == URLRequestData.Fields {
        private let fieldParsers: FieldParsers

        public init(@ParserBuilder<URLRequestData.Fields> build: () -> FieldParsers) {
            self.fieldParsers = build()
        }

        /// A convenience initializer that creates field parsers for the most common content-disposition values.
        public init(name: String, filename: String) where FieldParsers == AnyParserPrinter<URLRequestData.Fields, Void> {
            self.fieldParsers = ParsePrint {
                Field("name") { name }
                Field("filename") { filename }
            }.eraseToAnyParserPrinter()
        }

        @ParserBuilder<Substring>
        private var fieldsParser: some ParserPrinter<Substring, Array<(String, Substring)>> {
            "form-data; "
            Many {
                PrefixUpTo("=").map(.string)
                #"=""#
                PrefixUpTo(#"""#)
                #"""#
            } separator: {
                ";"
                Whitespace(1..., .horizontal)
            }
        }

        /// A convenience initializer that creates field parsers for the most common content-disposition values.
        public init(name: String) where FieldParsers == AnyParserPrinter<URLRequestData.Fields, Void> {
            self.fieldParsers = ParsePrint {
                Field("name") { name }
            }.eraseToAnyParserPrinter()
        }

        public func parse(_ input: inout Substring) rethrows -> FieldParsers.Output {
            let fieldValues = try fieldsParser.parse(&input)
            var fields: FieldParsers.Input = fieldValues.reduce(into: .init([:], isNameCaseSensitive: false)) { partialResult, field in
                partialResult[field.0, default: []].append(field.1)
            }
            let output = try self.fieldParsers.parse(&fields)
            return output
        }

        public func print(_ output: FieldParsers.Output, into input: inout Substring) throws {
            var fields = URLRequestData.Fields([:], isNameCaseSensitive: false)
            try self.fieldParsers.print(output, into: &fields)
            let fieldValues: Array<(String, Substring)> = fields.compactMap { (key, value) in
                guard let valueSubstring = value[0] else {
                    return nil
                }
                return (key, valueSubstring)
            }
            try fieldsParser.print(fieldValues, into: &input)
        }
    }

    public struct MultipartPart<Parsers: Parser>: Parser where Parsers.Input == BodyPartData {
        let parsers: Parsers

        public init(@ParserBuilder<BodyPartData> build: () -> Parsers) {
            self.parsers = build()
        }

        public func parse(_ input: inout ArraySlice<BodyPartData>) throws -> Parsers.Output {
            guard let part = input.first else {
                throw MultipartParsingError("Expected at least one part")
            }
            let output = try parsers.parse(part)
            input = input.dropFirst()
            return output
        }
    }

    /// Parses a multipart request body part's headers using field parsers.
    public struct PartHeaders<FieldParsers: Parser>: Parser where FieldParsers.Input == URLRequestData.Fields {
        let fieldParsers: FieldParsers

        public init(@ParserBuilder<URLRequestData.Fields> build: () -> FieldParsers) {
            self.fieldParsers = build()
        }

        public func parse(_ input: inout BodyPartData) rethrows -> FieldParsers.Output {
            try fieldParsers.parse(&input.headers)
        }
    }

    /// Parses a request's body using a byte parser.
    public struct PartBody<Bytes: Parser>: Parser where Bytes.Input == Data {
        let bytesParser: Bytes

        public init(@ParserBuilder<Data> _ bytesParser: () -> Bytes) {
            self.bytesParser = bytesParser()
        }

        /// Initializes a body parser from a byte conversion.
        ///
        /// Useful for parsing a request body in its entirety, for example as a JSON payload.
        ///
        /// ```swift
        /// struct Comment: Codable {
        ///   var author: String
        ///   var message: String
        /// }
        ///
        /// PartBody(.json(Comment.self))
        /// ```
        ///
        /// - Parameter bytesConversion: A conversion that transforms bytes into some other type.
        public init<C>(_ bytesConversion: C)
        where Bytes == Parsers.MapConversion<Parsers.ReplaceError<Rest<Data>>, C> {
            self.bytesParser = Rest().replaceError(with: .init()).map(bytesConversion)
        }

        /// Initializes a body parser that parses the the entire body's data as-is.
        public init() where Bytes == Parsers.ReplaceError<Rest<Bytes.Input>> {
            self.bytesParser = Rest().replaceError(with: .init())
        }

        public func parse(_ input: inout BodyPartData) throws -> Bytes.Output {
            guard var data = input.data else {
                throw MultipartParsingError("Expected body part data to have a parseable data but data was nil.")
            }
            let output = try self.bytesParser.parse(&data)
            input.data = data
            return output
        }
    }

    struct PartHeaderFields: ParserPrinter {
        var body: some ParserPrinter<Data, URLRequestData.Fields> {
            Many {
                PartHeaderLine()
            } separator: {
                Whitespace(2, .vertical).printing { _, data in
                    data.prepend(contentsOf: "\r\n".data(using: .utf8)!)
                }
            } terminator: {
                Whitespace(4, .vertical).printing { _, data in
                    data.prepend(contentsOf: "\r\n\r\n".data(using: .utf8)!)
                }
            }
            .map(HeadersToFields())
        }
    }

    struct PartHeaderLine: ParserPrinter {
        private let separator = ": ".data(using: .utf8)!
        private let terminator = "\r\n".data(using: .utf8)!

        func parse(_ input: inout Data) throws -> (String, Substring) {
            guard !input.starts(with: terminator) else {
                throw MultipartParsingError("Not a header line")
            }
            guard let separatorRange = input.range(of: separator) else {
                throw MultipartParsingError("Could not parse header line")
            }
            let headerNameRange = input.startIndex..<separatorRange.startIndex
            let headerName = input[headerNameRange]
            guard let headerNameString = String(data: headerName, encoding: .utf8) else {
                throw MultipartParsingError("Could not convert header name data to string")
            }
            input.removeSubrange(headerNameRange)
            input.removeSubrange(input.range(of: separator)!)
            guard let terminatorRange = input.range(of: terminator) else {
                throw MultipartParsingError("Could not find header line terminator")
            }
            let headerValueRange = input.startIndex..<terminatorRange.startIndex
            let headerValue = input[headerValueRange]
            guard let headerValueString = String(data: headerValue, encoding: .utf8) else {
                throw MultipartParsingError("Could not convert header value data to string")
            }
            let headerValueSubstring = headerValueString[headerValueString.startIndex..<headerValueString.endIndex]
            input.removeSubrange(headerValueRange)
            return (headerNameString, headerValueSubstring)
        }

        func print(_ output: (String, Substring), into input: inout Data) throws {
            input.prepend(contentsOf: output.1.data(using: .utf8)!)
            input.prepend(contentsOf: separator)
            input.prepend(contentsOf: output.0.data(using: .utf8)!)
        }
    }
}

// MARK: - Printers

extension Parsers.MultipartBody: ParserPrinter where BodyPartParsers: ParserPrinter {
    public func print(_ output: BodyPartParsers.Output, into input: inout URLRequestData) throws {
        try Parsers.HeaderBoundaryValue().print(printBoundary, into: &input)
        let parts = try Array(partParsers.print(output))
        let partsData = try Parsers.BodyParts(boundaryValue: printBoundary).print(parts)
        input.body = partsData
    }
}

extension Parsers.MultipartPart: ParserPrinter where Parsers: ParserPrinter {
    public func print(_ output: Parsers.Output, into input: inout ArraySlice<BodyPartData>) throws {
        var partData = BodyPartData()
        try parsers.print(output, into: &partData)
        input.prepend(partData)
    }
}

extension Parsers.PartBody: ParserPrinter where Bytes: ParserPrinter {
    public func print(_ output: Bytes.Output, into input: inout BodyPartData) rethrows {
        input.data = try self.bytesParser.print(output)
    }
}

extension Parsers.PartHeaders: ParserPrinter where FieldParsers: ParserPrinter {
    public func print(_ output: FieldParsers.Output, into input: inout BodyPartData) throws {
        try fieldParsers.print(output, into: &input.headers)
    }
}

// MARK: - Public Types

public typealias MultipartBody = Parsers.MultipartBody
public typealias MultipartPart = Parsers.MultipartPart
public typealias MultipartFormData = Parsers.MultipartFormData
public typealias PartBody = Parsers.PartBody
public typealias PartHeaders = Parsers.PartHeaders

// MARK: - Internal

/// Converts an array of header name/values represented as a tuple to a Fields struct.
private struct HeadersToFields: Conversion {
    func apply(_ input: [(String, Substring)]) throws -> URLRequestData.Fields {
        var fields: URLRequestData.Fields = [:]
        for (name, value) in input {
            fields[name, default: []].append(value)
        }
        return fields
    }

    func unapply(_ output: URLRequestData.Fields) throws -> [(String, Substring)] {
        var result: [(String, Substring)] = []
        for (name, values) in output {
            for value in values {
                if let value {
                    result.append((name, value))
                }
            }
        }
        return result
    }
}
