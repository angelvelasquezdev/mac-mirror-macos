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
}
