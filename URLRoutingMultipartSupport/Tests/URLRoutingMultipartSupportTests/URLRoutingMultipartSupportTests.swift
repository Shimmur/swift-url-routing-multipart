import CustomDump
import XCTest

@testable import URLRouting
@testable import URLRoutingMultipartSupport

final class URLRoutingMultipartSupportTests: XCTestCase {
    enum MultipartRequests: Equatable {
        case twoTexts(String, String)
    }

    // MARK: - Integration Tests

    func testMultipartRequest() throws {
        let requestBodyString = """
        --abcde12345\r
        Content-Disposition: form-data; name="first"\r
        Content-Type: text/plain\r
        \r
        This is some text\r
        --abcde12345\r
        Content-Disposition: form-data; name="second"\r
        Content-Type: text/plain\r
        \r
        This is some more text\r
        --abcde12345--\r

        """

        var request = URLRequestData()
        request.path = ["multipart"]
        request.method = "POST"
        request.headers["Content-Type"] = ["multipart/form-data; boundary=abcde12345"]
        request.body = requestBodyString.data(using: .utf8)!

        let routeParser = Route(MultipartRequests.twoTexts) {
            Path { "multipart" }
            Method.post
            MultipartBody(printBoundary: "abcde12345") {
                MultipartPart {
                    PartHeaders {
                        Field("Content-Type") { "text/plain" }
                        Field("Content-Disposition") {
                            MultipartFormData(name: "first")
                        }
                    }
                    PartBody(.string(encoding: .utf8))
                }
                MultipartPart {
                    PartHeaders {
                        Field("Content-Type") { "text/plain" }
                        Field("Content-Disposition") {
                            MultipartFormData(name: "second")
                        }
                    }
                    PartBody(.string(encoding: .utf8))
                }
            }
        }

        let route = try routeParser.parse(request)
        XCTAssertEqual(route, MultipartRequests.twoTexts("This is some text", "This is some more text"))
    }

    // MARK: - Unit Tests

    func testMultipartFormDataParser() throws {
        var request = URLRequestData(string: "https://www.example.com/upload")!
        request.headers["Content-Disposition"] = [#"form-data; name="fieldOne"; filename="foo.txt""#]

        let parser = Headers {
            Field("Content-Disposition") {
                MultipartFormData {
                    Field("name", .string)
                    Field("filename", .string)
                }
            }
        }

        let (name, filename) = try parser.parse(request)
        XCTAssertEqual(name, "fieldOne")
        XCTAssertEqual(filename, "foo.txt")

        var printedRequest = URLRequestData(string: "https://www.example.com/upload")!
        try parser.print((name, filename), into: &printedRequest)
        XCTAssertNoDifference(request, printedRequest)
    }

    func testHeaderLineParser() throws {
        let parser = Parsers.PartHeaderLine()
        var input = "Content-Type: text/plain\r\n".data(using: .utf8)!
        let output = try parser.parse(&input)
        XCTAssertEqual("Content-Type", output.0)
        XCTAssertEqual("text/plain", output.1)
    }

    func testPartHeaderFieldsParser() throws {
        let inputString = """
      Content-Disposition: form-data; name="id"\r
      Content-Type: text/plain\r
      \r

      """
        var inputData = inputString.data(using: .utf8)!

        let expected: URLRequestData.Fields = [
            "Content-Disposition": [#"form-data; name="id""#],
            "Content-Type": ["text/plain"]
        ]
        let parser = Parsers.PartHeaderFields()
        let output = try parser.parse(&inputData)
        XCTAssertNoDifference(output, expected)

        var printedData = Data()
        try parser.print(output, into: &printedData)
        let printedString = String(data: printedData, encoding: .utf8)
        XCTAssertNoDifference(inputString, printedString)
    }

    func testPartParser() throws {
        let inputString = """
    Content-Disposition: form-data; name="id"\r
    Content-Type: text/plain\r
    \r
    This is some text\r
    --abcde12345--\r

    """
        var inputData = inputString.data(using: .utf8)!

        let expected = BodyPartData(
            headers: [
                "Content-Disposition": [#"form-data; name="id""#],
                "Content-Type": ["text/plain"]
            ],
            data: "This is some text".data(using: .utf8)!
        )
        let parser = Parsers.BodyPart(boundaryValue: "abcde12345")
        let output = try parser.parse(&inputData)
        XCTAssertNoDifference(output, expected)

        let terminator = Boundary(value: "abcde12345", type: .terminator)
        try terminator.parse(&inputData)
        XCTAssert(inputData.isEmpty, "Input should be fully consumed")

        var printedData = Data()
        try terminator.print((), into: &printedData)
        try parser.print(output, into: &printedData)
        let printedInput = String(data: printedData, encoding: .utf8)

        XCTAssertNoDifference(inputString, printedInput)
    }

    func testPartsParser() throws {
        let inputString = """
    --abcde12345\r
    Content-Disposition: form-data; name="id"\r
    Content-Type: text/plain\r
    \r
    This is some text\r
    --abcde12345\r
    Content-Disposition: form-data; name="image"\r
    Content-Type: text/plain\r
    \r
    This is some more text\r
    --abcde12345--\r

    """
        var inputData = inputString.data(using: .utf8)!

        let expected: [BodyPartData] = [
            BodyPartData(
                headers: [
                    "Content-Disposition": [#"form-data; name="id""#],
                    "Content-Type": ["text/plain"]
                ],
                data: "This is some text".data(using: .utf8)!
            ),
            BodyPartData(
                headers: [
                    "Content-Disposition": [#"form-data; name="image""#],
                    "Content-Type": ["text/plain"]
                ],
                data: "This is some more text".data(using: .utf8)!
            )
        ]
        let parser = Parsers.BodyParts(boundaryValue: "abcde12345")
        let output = try parser.parse(&inputData)

        XCTAssertNoDifference(expected, output)
        XCTAssert(inputData.isEmpty)

        var printedData = Data()
        try parser.print(output, into: &printedData)
        let printedInput = String(data: printedData, encoding: .utf8)
        XCTAssertNoDifference(inputString, printedInput)
    }
}
