import Foundation
import Starscream

enum APWebSocketError: Error, LocalizedError {
    case notConnected
    case connectionFailed(String)
    case closed

    var errorDescription: String? {
        switch self {
        case .notConnected: return "WebSocket is not connected"
        case .connectionFailed(let reason): return reason
        case .closed: return "WebSocket connection closed"
        }
    }
}

final class APWebSocketSession: WebSocketDelegate {
    private let url: URL
    private var socket: WebSocket?
    private var openContinuation: CheckedContinuation<Void, Error>?
    private let queue = DispatchQueue(label: "gg.archipelago.websocket", qos: .userInitiated)

    private(set) var isOpen = false
    var onMessage: ((String) -> Void)?
    var onClose: ((Error?) -> Void)?

    init(url: URL) {
        self.url = url
    }

    func open() async throws {
        guard socket == nil else {
            throw APWebSocketError.connectionFailed("Already connected or connecting")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Archipelago-iOS", forHTTPHeaderField: "User-Agent")

        let compression = WSCompression()
        let webSocket = WebSocket(request: request, compressionHandler: compression)
        webSocket.callbackQueue = queue
        webSocket.delegate = self
        socket = webSocket

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            openContinuation = continuation
            webSocket.connect()
        }
    }

    func send(_ text: String) async throws {
        guard let socket, isOpen else {
            throw APWebSocketError.notConnected
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                socket.write(string: text) {
                    continuation.resume()
                }
            }
        }
    }

    func close() async {
        isOpen = false
        socket?.disconnect()
        socket = nil
        openContinuation?.resume(throwing: APWebSocketError.closed)
        openContinuation = nil
    }

    // MARK: - WebSocketDelegate

    func didReceive(event: WebSocketEvent, client: WebSocketClient) {
        switch event {
        case .connected:
            isOpen = true
            openContinuation?.resume()
            openContinuation = nil

        case .disconnected(let reason, let code):
            let wasOpen = isOpen
            isOpen = false
            socket = nil
            if let openContinuation {
                self.openContinuation = nil
                let message = "Disconnected during connect: \(reason) (code \(code))"
                openContinuation.resume(throwing: APWebSocketError.connectionFailed(message))
            } else if wasOpen {
                onClose?(APWebSocketError.connectionFailed("\(reason) (code \(code))"))
            }

        case .text(let string):
            onMessage?(string)

        case .binary(let data):
            if let string = String(data: data, encoding: .utf8) {
                onMessage?(string)
            }

        case .error(let error):
            isOpen = false
            if let openContinuation {
                self.openContinuation = nil
                openContinuation.resume(throwing: error ?? APWebSocketError.connectionFailed("Unknown WebSocket error"))
            } else {
                onClose?(error)
            }

        case .cancelled:
            isOpen = false
            if let openContinuation {
                self.openContinuation = nil
                openContinuation.resume(throwing: APWebSocketError.closed)
            } else {
                onClose?(APWebSocketError.closed)
            }

        case .peerClosed:
            isOpen = false
            onClose?(nil)

        case .ping, .pong, .viabilityChanged, .reconnectSuggested:
            break
        }
    }
}
