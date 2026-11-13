import Foundation
import Network

// MARK: - A key's trip to the TV

/// What became of one key's HTTP request.
enum KeyDelivery: Equatable, Sendable {
    /// The TV answered, with this HTTP status.
    case answered(status: Int)
    /// No connection to the TV in time: nothing left the iPhone, so the key did nothing there.
    case notSent
    /// The request left and no answer came back in time: the TV may or may not have run the key.
    case unanswered
}

/// Takes a key's HTTP request to the TV over a connection of its own, so the app knows how far the
/// request got: one that never left can be tried again, one that left can't (the TV might run the key
/// twice). URLSession doesn't tell the two apart.
///
/// The TV drops a connection request (SYN) now and then (2 in 474 on the xxLN5700, with nothing else
/// wrong), and the kernel repeats it only after a full second, so the key landed a second late. While
/// no connection is established a fresh attempt starts every `stagger`; the first to connect carries
/// the request and the others are closed without a byte sent.
enum TVKeyLink {
    /// Well above a handshake on the LAN (15 ms median, 68 ms at the 95th percentile, measured).
    static let stagger: TimeInterval = 0.25
    static let maxAttempts = 4

    /// Sends `request` if a connection is established within `connectWithin`, then waits up to
    /// `answerWithin` for the TV's answer.
    static func deliver(_ request: URLRequest, connectWithin: TimeInterval, answerWithin: TimeInterval) async -> KeyDelivery {
        guard connectWithin > 0, let url = request.url, let host = url.host(percentEncoded: false), !host.isEmpty,
              let port = NWEndpoint.Port(rawValue: UInt16(clamping: url.port ?? 80)),
              let message = httpMessage(for: request) else { return .notSent }
        let exchange = KeyExchange(host: NWEndpoint.Host(host), port: port, message: message, answerWithin: answerWithin)
        return await exchange.run(connectWithin: connectWithin)
    }

    /// `request` as the bytes of an HTTP/1.1 message, with the headers URLSession would add on its own
    /// (Host, Content-Length) and none of its extras.
    static func httpMessage(for request: URLRequest) -> Data? {
        guard let url = request.url, let host = url.host(percentEncoded: false), !host.isEmpty else { return nil }
        let method = request.httpMethod ?? "GET"
        var target = url.path(percentEncoded: true)
        if target.isEmpty { target = "/" }
        if let query = url.query(percentEncoded: true), !query.isEmpty { target += "?\(query)" }
        let body = request.httpBody ?? Data()

        var head = "\(method) \(target) HTTP/1.1\r\n"
        head += "Host: \(host)\(url.port.map { ":\($0)" } ?? "")\r\n"
        for (name, value) in (request.allHTTPHeaderFields ?? [:]).sorted(by: { $0.key < $1.key }) {
            let lowered = name.lowercased()
            guard lowered != "host", lowered != "content-length" else { continue }
            head += "\(name): \(value)\r\n"
        }
        if !body.isEmpty || method != "GET" {
            head += "Content-Length: \(body.count)\r\n"
        }
        head += "\r\n"
        return Data(head.utf8) + body
    }

    /// The status code of an HTTP response, once its status line is in.
    static func httpStatus(of response: Data) -> Int? {
        guard let lineEnd = response.range(of: Data("\r\n".utf8)),
              let line = String(data: response[response.startIndex..<lineEnd.lowerBound], encoding: .utf8) else { return nil }
        let parts = line.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2, parts[0].hasPrefix("HTTP/"), let status = Int(parts[1]),
              (100...599).contains(status) else { return nil }
        return status
    }

    /// Whether `response` holds a whole HTTP response: its head and, when the head says how long it
    /// is, the body. Without a Content-Length the body ends when the TV closes the connection.
    static func isWhole(_ response: Data) -> Bool {
        guard let headEnd = response.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: response[response.startIndex..<headEnd.lowerBound], encoding: .utf8) else { return false }
        for line in head.components(separatedBy: "\r\n").dropFirst() {
            let field = line.split(separator: ":", maxSplits: 1)
            guard field.count == 2, field[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length",
                  let length = Int(field[1].trimmingCharacters(in: .whitespaces)) else { continue }
            return response.distance(from: headEnd.upperBound, to: response.endIndex) >= length
        }
        return false
    }
}

/// One request to the TV: the race for a connection, then the request and its answer on the winner.
private final class KeyExchange: @unchecked Sendable {
    private let queue = DispatchQueue(label: "lanremote.key-link")
    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port
    private let message: Data
    private let answerWithin: TimeInterval

    // Everything below is touched on `queue` only.
    private var racing: [NWConnection] = []
    private var carrier: NWConnection?
    private var attempts = 0
    private var response = Data()
    private var continuation: CheckedContinuation<KeyDelivery, Never>?

    init(host: NWEndpoint.Host, port: NWEndpoint.Port, message: Data, answerWithin: TimeInterval) {
        self.host = host
        self.port = port
        self.message = message
        self.answerWithin = answerWithin
    }

    func run(connectWithin: TimeInterval) async -> KeyDelivery {
        await withCheckedContinuation { continuation in
            queue.async {
                self.continuation = continuation
                self.attempt()
                self.queue.asyncAfter(deadline: .now() + connectWithin) {
                    if self.carrier == nil { self.finish(.notSent) }
                }
            }
        }
    }

    private func attempt() {
        guard continuation != nil, carrier == nil, attempts < TVKeyLink.maxAttempts else { return }
        attempts += 1
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let connection = NWConnection(host: host, port: port, using: NWParameters(tls: nil, tcp: tcp))
        racing.append(connection)
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            self.connection(connection, became: state)
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + TVKeyLink.stagger) { [weak self] in self?.attempt() }
    }

    private func connection(_ connection: NWConnection, became state: NWConnection.State) {
        guard continuation != nil else { return }
        switch state {
        case .ready:
            guard carrier == nil else { return }
            carrier = connection
            for other in racing where other !== connection { close(other) }
            racing.removeAll()
            // From here on the TV may run the key, whatever happens to the answer.
            connection.send(content: message, completion: .contentProcessed { _ in })
            receive(from: connection)
            queue.asyncAfter(deadline: .now() + answerWithin) { [weak self] in self?.finishWithWhatCame() }
        case .waiting, .failed:
            if connection === carrier {
                finishWithWhatCame()
            } else {
                // Refused, unreachable or denied by iOS: over for this attempt; the next may do better.
                close(connection)
                racing.removeAll { $0 === connection }
            }
        default:
            break
        }
    }

    private func receive(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self, self.continuation != nil else { return }
            if let data { self.response.append(data) }
            if isComplete || error != nil || self.response.count > 65_536 || TVKeyLink.isWhole(self.response) {
                self.finishWithWhatCame()
            } else {
                self.receive(from: connection)
            }
        }
    }

    private func finishWithWhatCame() {
        finish(TVKeyLink.httpStatus(of: response).map { .answered(status: $0) } ?? .unanswered)
    }

    private func finish(_ delivery: KeyDelivery) {
        guard let continuation else { return }
        self.continuation = nil
        racing.forEach(close)
        racing.removeAll()
        if let carrier { close(carrier) }
        continuation.resume(returning: delivery)
    }

    private func close(_ connection: NWConnection) {
        connection.stateUpdateHandler = nil
        connection.cancel()
    }
}
