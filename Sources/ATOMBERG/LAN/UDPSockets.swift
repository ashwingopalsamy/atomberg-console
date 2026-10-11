import Darwin
import Foundation

enum LANError: Error, Sendable {
    case socket(Int32)
    case badAddress(String)
}

struct ReceivedDatagram: Sendable {
    let payload: Data
    /// Dotted-quad IPv4 address of the sender.
    let sender: String
}

/// Binds 0.0.0.0:`port` so that broadcasts reach it. SO_REUSEPORT lets other listeners share the port.
func openReceiver(port: UInt16) throws -> Int32 {
    let fd = try makeNonBlockingSocket()
    var enable: Int32 = 1
    let size = socklen_t(MemoryLayout<Int32>.size)
    guard setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &enable, size) == 0,
          setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &enable, size) == 0 else {
        let code = errno
        closeSocket(fd)
        throw LANError.socket(code)
    }
    let address = ipv4Address(host: INADDR_ANY, port: port)
    guard withSocketAddress(address, { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }) == 0 else {
        let code = errno
        closeSocket(fd)
        throw LANError.socket(code)
    }
    return fd
}

/// Sends one datagram from a fresh ephemeral socket. Commands are rare, so a socket per send is cheaper to reason about than a shared one.
func sendDatagram(_ data: Data, to address: String, port: UInt16, broadcast: Bool = false) throws {
    // The second door. Only the fan ports, and only addresses on your own network.
    guard NetworkPolicy.allowsLAN(address: address, port: port) else { throw LANError.badAddress(address) }
    var host = in_addr()
    guard inet_pton(AF_INET, address, &host) == 1 else { throw LANError.badAddress(address) }
    let fd = try makeNonBlockingSocket()
    defer { closeSocket(fd) }
    if broadcast {
        var enable: Int32 = 1
        guard setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &enable, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw LANError.socket(errno)
        }
    }
    let destination = ipv4Address(host: host.s_addr, port: port)
    guard withSocketAddress(destination, { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }) == 0 else {
        throw LANError.socket(errno)
    }
    let sent = data.withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
    guard sent == data.count else { throw LANError.socket(errno) }
}

/// Reads every datagram queued on a non-blocking socket. Datagrams longer than the buffer are truncated.
func receiveAvailable(on fd: Int32) -> [ReceivedDatagram] {
    var datagrams: [ReceivedDatagram] = []
    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
        var sender = sockaddr_in()
        var senderLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let count = buffer.withUnsafeMutableBytes { bytes in
            withUnsafeMutablePointer(to: &sender) { senderPointer in
                senderPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                    recvfrom(fd, bytes.baseAddress, bytes.count, 0, address, &senderLength)
                }
            }
        }
        // EAGAIN means the queue is empty. Any other error also ends this pass; the read source fires again if data remains.
        guard count >= 0 else { break }
        datagrams.append(ReceivedDatagram(payload: Data(buffer[..<count]), sender: ipv4String(sender.sin_addr)))
    }
    return datagrams
}

func closeSocket(_ fd: Int32) {
    _ = close(fd)
}

private func makeNonBlockingSocket() throws -> Int32 {
    let fd = socket(AF_INET, SOCK_DGRAM, 0)
    guard fd >= 0 else { throw LANError.socket(errno) }
    // A send the system refuses (for instance without Local Network access) must come back as an error code.
    // Without this the default action of SIGPIPE ends the whole app.
    var noSignal: Int32 = 1
    _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
    let flags = fcntl(fd, F_GETFL)
    guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else {
        let code = errno
        closeSocket(fd)
        throw LANError.socket(code)
    }
    return fd
}

private func ipv4Address(host: in_addr_t, port: UInt16) -> sockaddr_in {
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = port.bigEndian
    address.sin_addr = in_addr(s_addr: host)
    return address
}

private func withSocketAddress<R>(_ address: sockaddr_in, _ body: (UnsafePointer<sockaddr>) -> R) -> R {
    var address = address
    return withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1, body)
    }
}

private func ipv4String(_ address: in_addr) -> String {
    var address = address
    var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
    _ = inet_ntop(AF_INET, &address, &text, socklen_t(INET_ADDRSTRLEN))
    return text.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
}
