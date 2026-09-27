import Foundation

/// A parsed HTTP/1.1 request.
public struct HTTPRequest: Sendable {
    public let method: String
    public let path: String
    public let query: [String: String]
    public let headers: [String: String]
    public let body: Data

    public func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

/// A plain HTTP/1.1 response.
public struct HTTPResponse: Sendable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    public static func json(_ body: Data, status: Int = 200) -> HTTPResponse {
        HTTPResponse(
            status: status,
            headers: ["content-type": "application/json; charset=utf-8"],
            body: body
        )
    }
}

/// Incremental parser for HTTP/1.1 request bytes.
///
/// Handles the request line, headers and a `Content-Length` body. Returns
/// `nil` while more bytes are needed.
public struct HTTPRequestParser: Sendable {
    private var buffer = Data()

    public init() {}

    public mutating func append(_ data: Data) {
        buffer.append(data)
    }

    public mutating func next() -> HTTPRequest? {
        guard let headerEnd = rangeOfHeaderTerminator() else { return nil }
        let headerData = buffer[buffer.startIndex..<headerEnd.lowerBound]
        guard let head = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        let headers = parseHeaders(Array(lines.dropFirst()))
        let bodyStart = headerEnd.upperBound
        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let available = buffer.distance(from: bodyStart, to: buffer.endIndex)
        guard available >= contentLength else { return nil }

        let bodyEnd = buffer.index(bodyStart, offsetBy: contentLength)
        let body = Data(buffer[bodyStart..<bodyEnd])
        buffer.removeSubrange(buffer.startIndex..<bodyEnd)

        let (path, query) = Self.splitPath(String(parts[1]))
        return HTTPRequest(
            method: String(parts[0]).uppercased(),
            path: path,
            query: query,
            headers: headers,
            body: body
        )
    }

    private func rangeOfHeaderTerminator() -> Range<Data.Index>? {
        buffer.range(of: Data("\r\n\r\n".utf8))
    }

    private func parseHeaders(_ lines: [String]) -> [String: String] {
        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        return headers
    }

    static func splitPath(_ target: String) -> (String, [String: String]) {
        guard let mark = target.firstIndex(of: "?") else { return (target, [:]) }
        let path = String(target[target.startIndex..<mark])
        var query: [String: String] = [:]
        let raw = target[target.index(after: mark)...]
        for pair in raw.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard let key = kv.first else { continue }
            let value = kv.count > 1 ? String(kv[1]) : ""
            query[String(key).removingPercentEncoding ?? String(key)] =
                value.removingPercentEncoding ?? value
        }
        return (path, query)
    }
}

/// Serialises an `HTTPResponse` into wire bytes.
public func serializeResponse(_ response: HTTPResponse) -> Data {
    var headers = response.headers
    headers["content-length"] = String(response.body.count)
    headers["connection"] = "close"
    var head = "HTTP/1.1 \(response.status) \(reasonPhrase(response.status))\r\n"
    for (name, value) in headers.sorted(by: { $0.key < $1.key }) {
        head += "\(name): \(value)\r\n"
    }
    head += "\r\n"
    var out = Data(head.utf8)
    out.append(response.body)
    return out
}

func reasonPhrase(_ status: Int) -> String {
    switch status {
    case 200: return "OK"
    case 204: return "No Content"
    case 400: return "Bad Request"
    case 404: return "Not Found"
    case 405: return "Method Not Allowed"
    case 500: return "Internal Server Error"
    case 501: return "Not Implemented"
    default: return "Status"
    }
}
