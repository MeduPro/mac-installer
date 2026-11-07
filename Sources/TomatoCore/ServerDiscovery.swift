import Darwin
import Foundation

/// Ein im Netz gefundener tomedo-Server.
public struct DiscoveredServer: Hashable, Sendable, Identifiable {
    public var address: ServerAddress
    /// Rechnername per Rückwärtsauflösung, falls vorhanden.
    public var hostName: String?
    public var tomedoSize: Int64?

    public var id: String { address.baseURL.absoluteString }

    public init(address: ServerAddress, hostName: String? = nil, tomedoSize: Int64? = nil) {
        self.address = address
        self.hostName = hostName
        self.tomedoSize = tomedoSize
    }
}

/// IPv4-Netz einer Netzwerkschnittstelle des Macs.
public struct LocalNetwork: Hashable, Sendable, CustomStringConvertible {
    public var address: UInt32
    public var prefixLength: Int

    public init(address: UInt32, prefixLength: Int) {
        self.address = address
        self.prefixLength = prefixLength
    }

    var mask: UInt32 { prefixLength == 0 ? 0 : UInt32.max << (32 - prefixLength) }
    var network: UInt32 { address & mask }

    /// Alle Adressen außer Netz-, Broadcast- und eigener Adresse.
    public var hosts: [UInt32] {
        guard prefixLength >= 1, prefixLength <= 30 else { return [] }
        let first = network + 1
        let last = (network | ~mask) - 1
        return (first...last).filter { $0 != address }
    }

    public var description: String { "\(Self.string(network))/\(prefixLength)" }

    /// Private Adressbereiche (RFC 1918) – nur dort wird gesucht.
    public var isPrivate: Bool {
        let a = address >> 24, b = (address >> 16) & 0xFF
        return a == 10 || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168)
    }

    public static func string(_ ip: UInt32) -> String {
        "\(ip >> 24).\((ip >> 16) & 0xFF).\((ip >> 8) & 0xFF).\(ip & 0xFF)"
    }

    /// Netze der aktiven Schnittstellen (WLAN, Ethernet), ohne VPN-Tunnel und Loopback.
    /// Netze größer als /22 werden auf das /24 um die eigene Adresse begrenzt,
    /// damit die Suche in wenigen Sekunden fertig ist.
    public static func current() -> [LocalNetwork] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }

        var result: [LocalNetwork] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            let flags = Int32(entry.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0,
                  flags & IFF_LOOPBACK == 0, flags & IFF_POINTOPOINT == 0,
                  let addr = entry.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  let netmask = entry.ifa_netmask else { continue }
            let ip = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let mask = netmask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            var network = LocalNetwork(address: ip, prefixLength: mask.nonzeroBitCount)
            guard network.isPrivate else { continue }
            if network.prefixLength < 22 { network.prefixLength = 24 }
            if !result.contains(where: { $0.network == network.network && $0.prefixLength == network.prefixLength }) {
                result.append(network)
            }
        }
        return result
    }
}

/// Sucht tomedo-Server, indem sie bei jeder Adresse im Praxisnetz nachfragt, ob dort
/// tomedo ausgeliefert wird. tomedo-Server melden sich nicht per Bonjour an, darum
/// dieser Weg.
public struct ServerDiscovery: Sendable {
    public var port = ServerAddress.defaultPort
    public var path = ServerAddress.defaultPath
    public var timeout: TimeInterval = 1.5
    /// Gleichzeitige Anfragen.
    public var width = 64

    public init() {}

    /// Liefert gefundene Server, sobald sie antworten.
    public func discover(in networks: [LocalNetwork] = LocalNetwork.current()) -> AsyncStream<DiscoveredServer> {
        let hosts = networks.flatMap(\.hosts).map(LocalNetwork.string)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        config.httpMaximumConnectionsPerHost = 1
        let session = URLSession(configuration: config)
        let (port, path, width, timeout) = (port, path, width, timeout)

        return AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: DiscoveredServer?.self) { group in
                    var pending = hosts.makeIterator()
                    func addNext() -> Bool {
                        guard let host = pending.next() else { return false }
                        group.addTask {
                            let address = ServerAddress(host: host, port: port, path: path)
                            guard case .reachable(let size) = await TomedoServer(address: address, session: session).check(timeout: timeout) else {
                                return nil
                            }
                            return DiscoveredServer(address: address, hostName: Self.reverseLookup(host), tomedoSize: size)
                        }
                        return true
                    }
                    for _ in 0..<width where addNext() {}
                    for await found in group {
                        if let found { continuation.yield(found) }
                        if Task.isCancelled { group.cancelAll(); break }
                        _ = addNext()
                    }
                }
                session.invalidateAndCancel()
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Rechnername zu einer IP (DNS oder mDNS), ohne lange zu warten.
    static func reverseLookup(_ ip: String) -> String? {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        guard inet_pton(AF_INET, ip, &addr.sin_addr) == 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getnameinfo($0, socklen_t(MemoryLayout<sockaddr_in>.size), &buffer, socklen_t(buffer.count), nil, 0, NI_NAMEREQD)
            }
        }
        guard result == 0 else { return nil }
        let name = String(cString: buffer)
        return name == ip ? nil : name
    }
}
