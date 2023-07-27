# Multipart support for URLRouting

This package contains parsers for parsing multipart request bodies when using
the [URLRouting](https://github.com/pointfreeco/swift-url-routing/tree/main) library.

## Example

```swift
enum MultipartRequests: Equatable {
  case twoTexts(String, String)
}

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
```

It can also be used to implement multipart file uploads:

```swift
struct FileUpload: Equatable {
    let mimeType: String
    let fileName: String
    let fileData: Data
}

enum MultipartRequests: Equatable {
  case uploadFile(FileUpload)
}

let routeParser = Route(MultipartRequests.fileUpload) {
    Path { "multipart" }
    Method.post
    MultipartBody(printBoundary: "abcde12345") {
        MultipartPart(.memberwise(FileUpload.init)) {
            PartHeaders {
                Field("Content-Type", .string)
                Field("Content-Disposition") {
                    MultipartFormData {
                        Field("name") { "image" }
                        Field("filename", .string)
                    }
                }
            }
            PartBody()
        }
    }
}
```

## LICENCE

This library is licensed under the Apache 2.0 licence.
