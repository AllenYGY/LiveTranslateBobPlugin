import Foundation
import Network

// This bridge only accepts loopback HTTP from the Bob plugin. No credentials enter URLs or logs.
final class LocalBridge {
    private weak var model: LiveTranslateModel?
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "LiveTranslate.localBridge")

    init(model: LiveTranslateModel) { self.model = model }

    func start() {
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 17764)
            let listener = try NWListener(using: parameters)
            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state { fputs("Live Translate local bridge failed: \(error)\n", stderr) }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.receive(connection) }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            fputs("Live Translate local bridge could not start: \(error)\n", stderr)
        }
    }

    private func receive(_ connection: NWConnection) {
        connection.start(queue: queue)
        read(connection, data: Data())
    }

    private func read(_ connection: NWConnection, data: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] chunk, _, complete, error in
            guard let self else { connection.cancel(); return }
            var buffer = data
            if let chunk { buffer.append(chunk) }
            guard buffer.count <= 65536, error == nil else { connection.cancel(); return }
            guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                if complete { connection.cancel() } else { self.read(connection, data: buffer) }
                return
            }
            let header = String(decoding: buffer[..<headerEnd.lowerBound], as: UTF8.self)
            let lengthLine = header.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("content-length:") }
            let bodyLength = Int(lengthLine?.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? "0") ?? 0
            guard bodyLength >= 0, bodyLength < 32768 else { connection.cancel(); return }
            let bodyStart = headerEnd.upperBound
            if buffer.count - bodyStart < bodyLength {
                if complete { connection.cancel() } else { self.read(connection, data: buffer) }
                return
            }
            let body = Data(buffer[bodyStart..<(bodyStart + bodyLength)])
            self.handle(header: header, body: body, connection: connection)
        }
    }

    private func handle(header: String, body: Data, connection: NWConnection) {
        let lines = header.components(separatedBy: "\r\n")
        let route = lines.first?.split(separator: " ").prefix(2).map(String.init) ?? []
        guard route.count == 2,
              !lines.contains(where: { $0.lowercased().hasPrefix("origin:") }),
              (route[0] == "GET" || route[0] == "POST") else {
            respond(["ok": false, "message": "Invalid request"], to: connection); return
        }
        let payload = (try? JSONSerialization.jsonObject(with: body)) as? [String: String] ?? [:]
        Task { @MainActor [weak self] in
            guard let model = self?.model else { return }
            let answer: [String: Any]
            switch (route[0], route[1]) {
            case ("GET", "/snapshot"):
                answer = model.snapshot()
            case ("POST", "/start"):
                if let id = await model.configureAndStart(
                    deepgramKey: payload["deepgramKey"] ?? "",
                    backend: payload["backend"] ?? "apple",
                    accessKeyID: payload["accessKeyID"] ?? "",
                    secretAccessKey: payload["secretAccessKey"] ?? "") {
                    answer = ["ok": true, "session": id]
                } else {
                    answer = ["ok": false, "message": model.status]
                }
            case ("POST", "/stop"):
                model.stop(session: payload["session"])
                answer = ["ok": true]
            default:
                answer = ["ok": false, "message": "Unknown route"]
            }
            self?.respond(answer, to: connection)
        }
    }

    private func respond(_ value: [String: Any], to connection: NWConnection) {
        let body = (try? JSONSerialization.data(withJSONObject: value)) ?? Data("{}".utf8)
        let header = "HTTP/1.1 200 OK\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n"
        connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }
}
