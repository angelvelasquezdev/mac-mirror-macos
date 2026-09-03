import Foundation

final class BonjourPublisher: NSObject, NetServiceDelegate, @unchecked Sendable {
    private var netService: NetService?

    func startPublishing(port: Int) {
        let deviceName = Host.current().localizedName ?? "MacMirror Server"
        netService = NetService(
            domain: "local.",
            type: "_macmirror._tcp.",
            name: deviceName,
            port: Int32(port)
        )
        netService?.delegate = self
        netService?.publish()
    }

    func stopPublishing() {
        netService?.stop()
        netService = nil
    }

    func netServiceDidPublish(_ sender: NetService) {
        print("Bonjour service successfully published: \(sender.name) on port \(sender.port)")
    }

    func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        print("Bonjour service failed to publish: \(errorDict)")
    }
}
