import Darwin
import Foundation

/// Listens on 127.0.0.1 only for HTTP POST requests from the Cue browser extension.
///
/// Uses POSIX sockets with SO_REUSEADDR/SO_REUSEPORT instead of Network.framework's
/// NWListener. NWListener makes an NECP port reservation on start() that can linger
/// after failure, causing persistent "Address already in use" loops on app restart.
/// POSIX sockets bypass NECP entirely and behave correctly across debug cycles.
private struct BrowserPushPayload: Decodable, Sendable {
    let url: String
    let title: String
    let text: String
    let browser: String
}

enum BrowserPagePushResult: Sendable {
    case accepted
    case duplicate
}

final class BrowserWebServer: Sendable {
    /// Avoids macOS `rapportd`, which binds port 49152 on IPv6 when `localhost` is used.
    static let port: UInt16 = 52473

    private let onPageReceived: @MainActor (BrowserPageContext) -> BrowserPagePushResult
    private let socketHolder = SocketHolder()

    init(onPageReceived: @escaping @MainActor (BrowserPageContext) -> BrowserPagePushResult) {
        self.onPageReceived = onPageReceived
    }

    // MARK: - Lifecycle

    @MainActor
    func start() {
        // Close any socket from a prior run so the port is immediately available.
        socketHolder.closeServer()

        let sock = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return }

        var reuse: Int32 = 1
        Darwin.setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        Darwin.setsockopt(sock, SOL_SOCKET, SO_REUSEPORT, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len    = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port   = Self.port.bigEndian
        addr.sin_addr   = in_addr(s_addr: Darwin.inet_addr("127.0.0.1"))

        let bound = withUnsafePointer(to: addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        } == 0

        guard bound else {
            Darwin.close(sock)
            let reason = String(cString: strerror(errno))
            print("[BrowserWebServer] Bind failed (\(reason)) — retrying in 2s")
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.start()
            }
            return
        }

        guard Darwin.listen(sock, 10) == 0 else {
            Darwin.close(sock)
            return
        }

        socketHolder.serverFD = sock
        print("[BrowserWebServer] Listening on port \(Self.port)")

        let onPageReceived = onPageReceived
        DispatchQueue.global(qos: .utility).async { [holder = socketHolder] in
            BrowserWebServer.acceptLoop(serverFD: sock, holder: holder, onPageReceived: onPageReceived)
        }
    }

    @MainActor
    func stop() {
        socketHolder.closeServer()
    }

    // MARK: - Accept loop (background thread, blocking)

    nonisolated private static func acceptLoop(
        serverFD: Int32,
        holder: SocketHolder,
        onPageReceived: @escaping @MainActor (BrowserPageContext) -> BrowserPagePushResult
    ) {
        while true {
            let clientFD = Darwin.accept(serverFD, nil, nil)
            guard clientFD >= 0 else {
                // EBADF/EINVAL means the server socket was closed — clean exit.
                break
            }
            DispatchQueue.global(qos: .utility).async {
                BrowserWebServer.handleClient(clientFD, onPageReceived: onPageReceived)
            }
        }
    }

    // MARK: - Request / response (per-connection, background thread)

    nonisolated private static func handleClient(
        _ fd: Int32,
        onPageReceived: @escaping @MainActor (BrowserPageContext) -> BrowserPagePushResult
    ) {
        defer { Darwin.close(fd) }

        // 5-second read timeout so idle connections don't block threads.
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        Darwin.setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        // Read until the header/body separator appears.
        let separator = Data([0x0D, 0x0A, 0x0D, 0x0A]) // \r\n\r\n
        var received = Data()
        var chunk = [UInt8](repeating: 0, count: 8192)

        while received.range(of: separator) == nil {
            let n = Darwin.read(fd, &chunk, chunk.count)
            guard n > 0 else { break }
            received.append(contentsOf: chunk.prefix(n))
            if received.count > 131_072 { break } // 128 KB hard cap
        }

        guard let headerEnd = received.range(of: separator),
              let headerString = String(data: received[..<headerEnd.lowerBound], encoding: .utf8) else {
            sendHTTPResponse(fd: fd, status: 400, body: #"{"ok":false}"#)
            return
        }

        let firstLine = headerString.components(separatedBy: "\r\n").first ?? ""

        if firstLine.hasPrefix("OPTIONS") {
            print("[BrowserWebServer] CORS preflight")
            sendHTTPResponse(fd: fd, status: 204, body: "")
            return
        }

        guard firstLine.hasPrefix("POST") else {
            print("[BrowserWebServer] Rejected non-POST: \(firstLine)")
            sendHTTPResponse(fd: fd, status: 405, body: #"{"ok":false}"#)
            return
        }

        // Parse Content-Length so we wait for the full JSON body.
        var contentLength = 0
        for line in headerString.components(separatedBy: "\r\n") {
            if line.lowercased().hasPrefix("content-length:") {
                contentLength = Int(line.dropFirst("content-length:".count)
                    .trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }

        // Read any remaining body bytes beyond what we already have.
        var body = received[headerEnd.upperBound...]
        while body.count < contentLength {
            let n = Darwin.read(fd, &chunk, min(chunk.count, contentLength - body.count))
            guard n > 0 else { break }
            received.append(contentsOf: chunk.prefix(n))
            body = received[headerEnd.upperBound...]
        }

        guard let payload = try? JSONDecoder().decode(BrowserPushPayload.self, from: body) else {
            print("[BrowserWebServer] Failed to decode payload")
            sendHTTPResponse(fd: fd, status: 400, body: #"{"ok":false,"error":"invalid_payload"}"#)
            return
        }

        print("[BrowserWebServer] Received page from \(payload.browser): \(payload.url)")

        let context = BrowserPageContext(
            id: UUID(),
            createdAt: Date(),
            url: payload.url,
            pageTitle: payload.title,
            extractedText: payload.text,
            browserName: payload.browser
        )

        let pushResult: BrowserPagePushResult
        if Thread.isMainThread {
            pushResult = MainActor.assumeIsolated {
                onPageReceived(context)
            }
        } else {
            pushResult = DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    onPageReceived(context)
                }
            }
        }

        let responseBody: String
        switch pushResult {
        case .accepted:
            responseBody = #"{"ok":true}"#
        case .duplicate:
            print("[BrowserWebServer] Duplicate URL skipped: \(payload.url)")
            responseBody = #"{"ok":true,"duplicate":true}"#
        }

        sendHTTPResponse(fd: fd, status: 200, body: responseBody)
    }

    nonisolated private static func sendHTTPResponse(fd: Int32, status: Int, body: String) {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 204: statusText = "No Content"
        case 400: statusText = "Bad Request"
        case 405: statusText = "Method Not Allowed"
        default:  statusText = "Error"
        }

        let bodyData = body.data(using: .utf8) ?? Data()
        let headers = [
            "HTTP/1.1 \(status) \(statusText)",
            "Content-Type: application/json",
            "Content-Length: \(bodyData.count)",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: POST, OPTIONS",
            "Access-Control-Allow-Headers: Content-Type",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")

        var response = headers.data(using: .utf8)!
        response.append(bodyData)
        response.withUnsafeBytes { _ = Darwin.write(fd, $0.baseAddress, $0.count) }
    }

    // MARK: - Socket holder

    private final class SocketHolder: @unchecked Sendable {
        var serverFD: Int32 = -1

        func closeServer() {
            guard serverFD >= 0 else { return }
            // shutdown() unblocks any accept() call waiting in the background thread.
            Darwin.shutdown(serverFD, SHUT_RDWR)
            Darwin.close(serverFD)
            serverFD = -1
        }
    }
}

