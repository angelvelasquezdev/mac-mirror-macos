import Foundation
import Network

class WebSocketServer: @unchecked Sendable {
    private let port: NWEndpoint.Port
    private var listener: NWListener?
    private var activeConnections: [UUID: NWConnection] = [:]
    private var messageBuffers: [UUID: Data] = [:]
    
    // Callback when a WebSocket payload string is received
    var onMessageReceived: ((String) -> Void)?
    var onClientCountChanged: ((Int) -> Void)?

    init(port: UInt16 = 50002) {
        self.port = NWEndpoint.Port(rawValue: port)!
    }
    
    func start() {
        do {
            let wsOptions = NWProtocolWebSocket.Options()
            wsOptions.autoReplyPing = true
            
            let parameters = NWParameters(tls: nil)
            parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
            
            let listener = try NWListener(using: parameters, on: port)
            self.listener = listener
            
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("WebSocket Server successfully listening on port \(self.port)")
                case .failed(let error):
                    print("WebSocket Server listener failed with error: \(error)")
                default:
                    break
                }
            }
            
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }
            
            listener.start(queue: .global(qos: .userInitiated))
            
        } catch {
            print("Failed to start WebSocket Server: \(error)")
        }
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
        for connection in activeConnections.values {
            connection.cancel()
        }
        activeConnections.removeAll()
        messageBuffers.removeAll()
        onClientCountChanged?(0)
        print("WebSocket Server stopped.")
    }

    func broadcast(message: String) {
        guard let data = message.data(using: .utf8) else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "textContext", metadata: [metadata])
        
        for connection in activeConnections.values {
            connection.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
        }
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        let connectionId = UUID()
        activeConnections[connectionId] = connection
        messageBuffers[connectionId] = Data()
        
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                print("WebSocket Connection established with client.")
                self.onClientCountChanged?(self.activeConnections.count)
                self.receiveMessage(from: connection, connectionId: connectionId)
            case .cancelled, .failed:
                print("WebSocket Connection closed or failed.")
                self.activeConnections.removeValue(forKey: connectionId)
                self.messageBuffers.removeValue(forKey: connectionId)
                self.onClientCountChanged?(self.activeConnections.count)
            default:
                break
            }
        }
        
        connection.start(queue: .global(qos: .userInitiated))
    }
    
    private func receiveMessage(from connection: NWConnection, connectionId: UUID) {
        connection.receiveMessage { [weak self] content, messageContext, isComplete, error in
            guard let self = self else { return }
            if let error = error {
                print("WebSocket receive error: \(error)")
                connection.cancel()
                self.activeConnections.removeValue(forKey: connectionId)
                self.messageBuffers.removeValue(forKey: connectionId)
                self.onClientCountChanged?(self.activeConnections.count)
                return
            }
            
            if let content = content, !content.isEmpty {
                if self.messageBuffers[connectionId] == nil {
                    self.messageBuffers[connectionId] = Data()
                }
                self.messageBuffers[connectionId]?.append(content)
            }
            
            if isComplete {
                if let accumulatedData = self.messageBuffers[connectionId], !accumulatedData.isEmpty {
                    if let text = String(data: accumulatedData, encoding: .utf8) {
                        self.onMessageReceived?(text)
                    }
                }
                self.messageBuffers[connectionId] = Data()
            }
            
            // Continue receiving messages on this connection
            if error == nil && self.activeConnections[connectionId] != nil {
                self.receiveMessage(from: connection, connectionId: connectionId)
            }
        }
    }
}
