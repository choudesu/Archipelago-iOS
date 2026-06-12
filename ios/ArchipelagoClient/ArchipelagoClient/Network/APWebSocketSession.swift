import Foundation

final class APWebSocketSession: NSObject, URLSessionDelegate, URLSessionWebSocketDelegate {
    private let url: URL
    private var task: URLSessionWebSocketTask?
    private lazy var session: URLSession = {
        URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }()

    var isOpen = false
    var onMessage: ((String) -> Void)?
    var onClose: ((Error?) -> Void)?

    init(url: URL) {
        self.url = url
        super.init()
    }

    func open() async throws {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        task = session.webSocketTask(with: request)
        task?.resume()
        isOpen = true
        receiveNext()
    }

    func send(_ text: String) async throws {
        guard let task else { return }
        try await task.send(.string(text))
    }

    func close() async {
        isOpen = false
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func receiveNext() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.onMessage?(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.onMessage?(text)
                    }
                @unknown default:
                    break
                }
                if self.isOpen {
                    self.receiveNext()
                }
            case .failure(let error):
                self.isOpen = false
                self.onClose?(error)
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        isOpen = false
        onClose?(nil)
    }
}
