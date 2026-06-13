import Foundation
import Starscream

enum APWebSocketError: Error, LocalizedError {
    case notConnected
    case connectionFailed(String)
    case closed
    case timedOut

    var errorDescription: String? {
        switch self {
        case .notConnected: return "WebSocket is not connected"
        case .connectionFailed(let reason): return reason
        case .closed: return "WebSocket connection closed"
        case .timedOut: return "WebSocket connection timed out"
        }
    }
}

final class APWebSocketSession: WebSocketDelegate {
    private let url: URL
    private var socket: WebSocket?
    private var openContinuation: CheckedContinuation<Void, Error>?
    private var openTimeoutTask: Task<Void, Never>?
    private let callbackQueue = DispatchQueue(label: "gg.archipelago.websocket", qos: .userInitiated)

    private(set) var isOpen = false
    var onMessage: ((String) -> Void)?
    var onClose: ((Error?) -> Void)?

    init(url: URL) {
        self.url = url
    }

    func open(timeout: TimeInterval = 30) async throws {
        guard socket == nil else {
            throw APWebSocketError.connectionFailed("Already connected or connecting")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("Archipelago-iOS", forHTTPHeaderField: "User-Agent")

        let compression = APWSCompression()
        let webSocket = WebSocket(request: request, compressionHandler: compression)
        webSocket.respondToPingWithPong = true
        webSocket.callbackQueue = callbackQueue
        webSocket.delegate = self
        socket = webSocket

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            openContinuation = continuation
            openTimeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard let openContinuation = self.openContinuation else { return }
                self.openContinuation = nil
                self.isOpen = false
                self.socket?.disconnect()
                self.socket = nil
                openContinuation.resume(throwing: APWebSocketError.timedOut)
            }
            webSocket.connect()
        }
    }

    func send(_ text: String) async throws {
        guard let socket, isOpen else {
            throw APWebSocketError.notConnected
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            callbackQueue.async {
                socket.write(string: text) {
                    continuation.resume()
                }
            }
        }
    }

    func close() {
        openTimeoutTask?.cancel()
        openTimeoutTask = nil
        isOpen = false
        onMessage = nil
        onClose = nil
        if let openContinuation {
            self.openContinuation = nil
            openContinuation.resume(throwing: APWebSocketError.closed)
        }
        socket?.disconnect()
        socket = nil
    }

    // MARK: - WebSocketDelegate

    func didReceive(event: WebSocketEvent, client: WebSocketClient) {
        switch event {
        case .connected:
            openTimeoutTask?.cancel()
            openTimeoutTask = nil
            isOpen = true
            finishOpenContinuation()

        case .disconnected(let reason, let code):
            let wasOpen = isOpen
            isOpen = false
            socket = nil
            if openContinuation != nil {
                finishOpen(with: APWebSocketError.connectionFailed(Self.describeDisconnect(reason: reason, code: code)))
            } else if wasOpen {
                dispatchClose(APWebSocketError.connectionFailed(Self.describeDisconnect(reason: reason, code: code)))
            }

        case .text(let string):
            dispatchMessage(string)

        case .binary(let data):
            if let string = String(data: data, encoding: .utf8) {
                dispatchMessage(string)
            }

        case .error(let error):
            isOpen = false
            let described = error.map { Self.describeError($0) } ?? "Unknown WebSocket error"
            if openContinuation != nil {
                finishOpen(with: APWebSocketError.connectionFailed(described))
            } else {
                dispatchClose(error ?? APWebSocketError.connectionFailed(described))
            }

        case .cancelled:
            isOpen = false
            if openContinuation != nil {
                finishOpen(with: APWebSocketError.closed)
            } else {
                dispatchClose(APWebSocketError.closed)
            }

        case .peerClosed:
            isOpen = false
            dispatchClose(nil)

        case .ping, .pong, .viabilityChanged, .reconnectSuggested:
            break
        }
    }

    private func finishOpenContinuation() {
        guard let openContinuation else { return }
        self.openContinuation = nil
        openContinuation.resume()
    }

    private func finishOpen(with error: Error) {
        openTimeoutTask?.cancel()
        openTimeoutTask = nil
        guard let openContinuation else { return }
        self.openContinuation = nil
        socket = nil
        openContinuation.resume(throwing: error)
    }

    private func dispatchMessage(_ text: String) {
        guard let onMessage else { return }
        if Thread.isMainThread {
            onMessage(text)
        } else {
            DispatchQueue.main.async {
                onMessage(text)
            }
        }
    }

    private static func describeDisconnect(reason: String, code: UInt16) -> String {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            switch code {
            case 1002:
                return "WebSocket protocol error — server rejected a compressed control frame or invalid data (code 1002)"
            default:
                return "Connection closed (code \(code))"
            }
        }
        return "\(trimmed) (code \(code))"
    }

    private static func describeError(_ error: Error) -> String {
        if let wsError = error as? WSError {
            if wsError.message.isEmpty {
                return "WebSocket error (code \(wsError.code))"
            }
            return "\(wsError.message) (code \(wsError.code))"
        }
        return error.localizedDescription
    }

    private func dispatchClose(_ error: Error?) {
        guard let onClose else { return }
        if Thread.isMainThread {
            onClose(error)
        } else {
            DispatchQueue.main.async {
                onClose(error)
            }
        }
    }
}
