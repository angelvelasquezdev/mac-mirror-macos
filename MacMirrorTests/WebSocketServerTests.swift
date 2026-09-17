import Testing
import Foundation
@testable import MacMirror

@Suite struct WebSocketServerTests {

    @Test func testWebSocketServerTransmission() async throws {
        let server = WebSocketServer(port: 50003)

        // Set up an expectation to capture the message received by the server
        let messageExpectation = Task {
            await withCheckedContinuation { continuation in
                server.onMessageReceived = { message in
                    continuation.resume(returning: message)
                }
            }
        }

        // Start the WebSocket server
        server.start()
        
        defer {
            server.stop()
        }

        // Connect using URLSession WebSocketTask
        let url = URL(string: "ws://127.0.0.1:50003")!
        let webSocketTask = URLSession.shared.webSocketTask(with: url)
        webSocketTask.resume()

        // Send a test message frame
        let testMessage = "{\"iv\":\"test-iv\",\"ciphertext\":\"test-ciphertext\",\"tag\":\"test-tag\"}"
        try await webSocketTask.send(.string(testMessage))

        // Wait for the server to receive the message and assert correctness
        let receivedMessage = await messageExpectation.value
        #expect(receivedMessage == testMessage)

        // Clean up connection
        webSocketTask.cancel(with: .normalClosure, reason: nil)
    }

    @Test func testWebSocketClientConnectionTracking() async throws {
        let server = WebSocketServer(port: 50014)
        #expect(server.connectedClientCount == 0)
        #expect(!server.hasActiveConnections)

        let connectionExpectation = Task {
            await withCheckedContinuation { continuation in
                var hasResumed = false
                server.onClientCountChanged = { count in
                    if count > 0 && !hasResumed {
                        hasResumed = true
                        continuation.resume(returning: count)
                    }
                }
            }
        }

        server.start()
        defer {
            server.stop()
        }

        let url = URL(string: "ws://127.0.0.1:50014")!
        let webSocketTask = URLSession.shared.webSocketTask(with: url)
        webSocketTask.resume()

        let clientCount = await connectionExpectation.value
        #expect(clientCount == 1)
        #expect(server.hasActiveConnections)
        #expect(server.connectedClientCount == 1)

        webSocketTask.cancel(with: .normalClosure, reason: nil)
    }

    @Test @MainActor func testRemoteTestFailsImmediatelyWhenNoWebSocketClient() async throws {
        let viewModel = MenuBarViewModel.shared
        viewModel.isPaired = true
        viewModel.isClientConnected = false

        viewModel.triggerRemoteTestNotification()

        switch viewModel.remoteTestStatus {
        case .error(let message):
            #expect(message == NSLocalizedString("remote_test_bridge_offline", comment: ""))
        default:
            Issue.record("Expected remoteTestStatus to be .error with bridge offline message")
        }
    }
}

