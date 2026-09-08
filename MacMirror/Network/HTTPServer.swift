import Foundation
import Network

final class HTTPServer: @unchecked Sendable {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.angelsoft.macmirror.server")
    var port: UInt16 = 50001

    // Router endpoints
    var onInitiatePair: ((Data) -> (statusCode: Int, responseData: Data))?
    var onConfirmPair: ((Data) -> (statusCode: Int, responseData: Data))?
    var onNotification: ((Data) -> (statusCode: Int, responseData: Data))?
    var onUnpair: ((Data) -> (statusCode: Int, responseData: Data))?
    var onStatus: (() -> (statusCode: Int, responseData: Data))?

    func start() throws {
        let portVal = NWEndpoint.Port(rawValue: port)!
        let listener = try NWListener(using: .tcp, on: portVal)
        self.listener = listener

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("HTTP Server successfully listening on port \(listener.port?.rawValue ?? 0)")
            case .failed(let error):
                print("HTTP Server failed to start: \(error)")
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        readRequest(connection: connection, accumulatedData: Data())
    }

    private func readRequest(connection: NWConnection, accumulatedData: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, context, isComplete, error in
            guard let self = self else { return }
            if let error = error {
                print("Connection read error: \(error)")
                connection.cancel()
                return
            }

            var newData = accumulatedData
            if let data = data {
                newData.append(data)
            }

            // Look for HTTP header end sequence "\r\n\r\n"
            if let headersEndRange = newData.range(of: Data([13, 10, 13, 10])) {
                let headersData = newData.subdata(in: 0..<headersEndRange.lowerBound)
                guard let headersStr = String(data: headersData, encoding: .utf8) else {
                    self.sendResponse(connection: connection, statusCode: 400, body: "{\"error\":\"Bad Request (Invalid Encoding)\"}")
                    return
                }

                let lines = headersStr.components(separatedBy: "\r\n")
                guard !lines.isEmpty else {
                    self.sendResponse(connection: connection, statusCode: 400, body: "{\"error\":\"Bad Request\"}")
                    return
                }

                let requestLine = lines[0].components(separatedBy: " ")
                guard requestLine.count >= 2 else {
                    self.sendResponse(connection: connection, statusCode: 400, body: "{\"error\":\"Bad Request (Invalid Start Line)\"}")
                    return
                }

                let method = requestLine[0]
                let path = requestLine[1]

                // Parse Content-Length header robustly
                var contentLength = 0
                for line in lines.dropFirst() {
                    let parts = line.components(separatedBy: ":")
                    if parts.count >= 2 && parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                        let valStr = parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
                        contentLength = Int(valStr) ?? 0
                    }
                }

                let bodyStartIndex = headersEndRange.upperBound
                let bodyDataAvailable = newData.count - bodyStartIndex

                if bodyDataAvailable >= contentLength {
                    // Extract exactly Content-Length bytes for the payload body
                    let bodyData = newData.subdata(in: bodyStartIndex..<(bodyStartIndex + contentLength))
                    self.route(connection: connection, method: method, path: path, body: bodyData)
                } else {
                    // Not all body bytes have arrived, keep reading
                    self.readRequest(connection: connection, accumulatedData: newData)
                }
            } else if isComplete {
                connection.cancel()
            } else {
                // Headers are still incomplete, keep reading
                self.readRequest(connection: connection, accumulatedData: newData)
            }
        }
    }

    private func route(connection: NWConnection, method: String, path: String, body: Data) {
        if method == "GET" && path == "/status" {
            let (statusCode, responseData) = onStatus?() ?? (200, Data("{\"status\":\"ok\"}".utf8))
            sendResponse(connection: connection, statusCode: statusCode, bodyData: responseData)
            return
        }

        guard method == "POST" else {
            sendResponse(connection: connection, statusCode: 405, body: "{\"error\":\"Method Not Allowed\"}")
            return
        }

        var (statusCode, responseData) = (404, Data("{\"error\":\"Not Found\"}".utf8))

        if path == "/pair/initiate" {
            if let onInitiatePair = onInitiatePair {
                (statusCode, responseData) = onInitiatePair(body)
            }
        } else if path == "/pair/confirm" {
            if let onConfirmPair = onConfirmPair {
                (statusCode, responseData) = onConfirmPair(body)
            }
        } else if path == "/pair/unpair" {
            if let onUnpair = onUnpair {
                (statusCode, responseData) = onUnpair(body)
            } else {
                (statusCode, responseData) = (200, Data("{\"success\":true}".utf8))
            }
        } else if path == "/notification" {
            if let onNotification = onNotification {
                (statusCode, responseData) = onNotification(body)
            }
        }

        sendResponse(connection: connection, statusCode: statusCode, bodyData: responseData)
    }

    private func sendResponse(connection: NWConnection, statusCode: Int, body: String) {
        sendResponse(connection: connection, statusCode: statusCode, bodyData: Data(body.utf8))
    }

    private func sendResponse(connection: NWConnection, statusCode: Int, bodyData: Data) {
        var statusStr = "200 OK"
        switch statusCode {
        case 400: statusStr = "400 Bad Request"
        case 401: statusStr = "401 Unauthorized"
        case 404: statusStr = "404 Not Found"
        case 405: statusStr = "405 Method Not Allowed"
        case 500: statusStr = "500 Internal Server Error"
        default: break
        }

        let responseStr = """
        HTTP/1.1 \(statusStr)\r
        Content-Length: \(bodyData.count)\r
        Content-Type: application/json\r
        Connection: close\r
        \r
        
        """

        var responseData = Data(responseStr.utf8)
        responseData.append(bodyData)

        connection.send(content: responseData, completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
}
