import Foundation
import Network

/// Local HTTP/1.1 server bound to the loopback interface.
///
/// Serves the signing endpoints and the card status SSE stream. It only
/// accepts connections from `127.0.0.1`, so no remote host can reach it.
public final class LoopbackServer: @unchecked Sendable {
    private let router: Router
    private let port: NWEndpoint.Port
    private let queue = DispatchQueue(label: "signbridge.loopback")
    private var listener: NWListener?

    public init(router: Router, port: UInt16 = SignBridgeInfo.port) {
        self.router = router
        self.port = NWEndpoint.Port(rawValue: port)!
    }

    public func start() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, parser: HTTPRequestParser())
    }

    private func receive(_ connection: NWConnection, parser: HTTPRequestParser) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var parser = parser
            if let data, !data.isEmpty {
                parser.append(data)
                if let request = parser.next() {
                    self.handle(request, on: connection)
                    return
                }
            }
            if isComplete || error != nil {
                connection.cancel()
            } else {
                self.receive(connection, parser: parser)
            }
        }
    }

    private func handle(_ request: HTTPRequest, on connection: NWConnection) {
        Task {
            let outcome = await self.router.route(request)
            switch outcome {
            case .response(let response):
                self.send(serializeResponse(response), on: connection, close: true)
            case .eventStream(let stream):
                self.streamEvents(stream, on: connection)
            }
        }
    }

    private func streamEvents(_ stream: AsyncStream<CardStatusEvent>, on connection: NWConnection) {
        let head = sseHead()
        send(Data(head.utf8), on: connection, close: false)
        Task {
            let encoder = JSONEncoder()
            for await event in stream {
                guard let json = try? encoder.encode(event),
                    let text = String(data: json, encoding: .utf8)
                else { continue }
                let frame = "data: \(text)\n\n"
                self.send(Data(frame.utf8), on: connection, close: false)
            }
            // Close after the queued frames flush, in FIFO order.
            self.send(Data(": end\n\n".utf8), on: connection, close: true)
        }
    }

    private func sseHead() -> String {
        var lines = "HTTP/1.1 200 OK\r\n"
        lines += "content-type: text/event-stream\r\n"
        lines += "cache-control: no-cache\r\n"
        lines += "access-control-allow-origin: *\r\n"
        lines += "connection: keep-alive\r\n\r\n"
        return lines
    }

    private func send(_ data: Data, on connection: NWConnection, close: Bool) {
        connection.send(
            content: data,
            completion: .contentProcessed { _ in
                if close { connection.cancel() }
            })
    }
}
