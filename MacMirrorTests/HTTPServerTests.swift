import Testing
import Foundation
@testable import MacMirror

@Suite struct HTTPServerTests {

    @Test func testHTTPServerRouting() async throws {
        let server = HTTPServer()
        server.port = 50004

        // Set up a promise-like task to capture the request body received by the server
        let initiateExpectation = Task {
            await withCheckedContinuation { continuation in
                server.onInitiatePair = { data in
                    continuation.resume(returning: data)
                    return (200, Data("{\"status\":\"ok\"}".utf8))
                }
            }
        }

        // Start the server
        try server.start()
        
        // Ensure server stops even if test fails
        defer {
            server.stop()
        }

        // Send a real HTTP POST request to local loopback (127.0.0.1:50004)
        var request = URLRequest(url: URL(string: "http://127.0.0.1:50004/pair/initiate")!)
        request.httpMethod = "POST"
        request.httpBody = Data("{\"client_ephemeral_pub_key\":\"test-key-bytes\",\"device_name\":\"AndroidDeviceTest\"}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse

        // Assert response status code is 200
        #expect(httpResponse?.statusCode == 200)

        // Assert response body content
        let responseJson = try JSONSerialization.jsonObject(with: data) as? [String: String]
        #expect(responseJson?["status"] == "ok")

        // Assert server received the correct request body bytes
        let receivedData = await initiateExpectation.value
        let receivedJson = try JSONSerialization.jsonObject(with: receivedData) as? [String: String]
        #expect(receivedJson?["client_ephemeral_pub_key"] == "test-key-bytes")
        #expect(receivedJson?["device_name"] == "AndroidDeviceTest")
    }
}
