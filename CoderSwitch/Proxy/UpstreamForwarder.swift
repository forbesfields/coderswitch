import Foundation
import NIOCore

/// Forwards a request to an upstream provider and returns a streaming body.
struct UpstreamForwarder {
    struct Forwarded {
        let status: Int
        let headers: [(String, String)]
        let body: ByteStream
    }

    /// AsyncSequence of ByteBuffers wrapping URLSession.AsyncBytes.
    struct ByteStream: AsyncSequence, Sendable {
        typealias Element = ByteBuffer
        let bytes: URLSession.AsyncBytes

        struct AsyncIterator: AsyncIteratorProtocol {
            var inner: URLSession.AsyncBytes.AsyncIterator

            mutating func next() async throws -> ByteBuffer? {
                var chunk: [UInt8] = []
                chunk.reserveCapacity(4096)
                while chunk.count < 4096 {
                    guard let byte = try await inner.next() else { break }
                    chunk.append(byte)
                }
                if chunk.isEmpty { return nil }
                return ByteBuffer(bytes: chunk)
            }
        }

        func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(inner: bytes.makeAsyncIterator())
        }
    }

    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func forward(
        method: String,
        url: URL,
        headers: [(String, String)],
        body: Data?
    ) async throws -> Forwarded {
        var request = URLRequest(url: url)
        request.httpMethod = method
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody = body
        request.timeoutInterval = 600

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProxyError.upstreamFailed("non-HTTP response")
        }

        var outHeaders: [(String, String)] = []
        for (key, value) in http.allHeaderFields {
            guard let k = key as? String, let v = value as? String else { continue }
            let lower = k.lowercased()
            if lower == "transfer-encoding" || lower == "content-encoding" || lower == "connection" {
                continue
            }
            outHeaders.append((k, v))
        }

        return Forwarded(
            status: http.statusCode,
            headers: outHeaders,
            body: ByteStream(bytes: bytes)
        )
    }
}

enum ProxyError: Error, CustomStringConvertible {
    case unauthorized
    case badRequest(String)
    case noAccount(String)
    case upstreamFailed(String)

    var description: String {
        switch self {
        case .unauthorized: "unauthorized"
        case .badRequest(let m): "bad request: \(m)"
        case .noAccount(let m): "no account: \(m)"
        case .upstreamFailed(let m): "upstream failed: \(m)"
        }
    }
}
