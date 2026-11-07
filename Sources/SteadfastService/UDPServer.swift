import Foundation
import Darwin

@MainActor final class UDPServer {
    private let descriptor: Int32
    private let source: any DispatchSourceRead
    private let answer: (Data) -> Data?
    private var buffer = [UInt8](repeating: 0, count: 4097)

    init(port: UInt16, answer: @escaping (Data) -> Data?) throws {
        let descriptor = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        do {
            guard fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0,
                  fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
            guard bound == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        } catch { Darwin.close(descriptor); throw error }
        self.descriptor = descriptor; self.answer = answer
        source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.receive() } }
        source.setCancelHandler { Darwin.close(descriptor) }
        source.resume()
    }
    isolated deinit { source.cancel() }

    private func receive() {
        // Bound each turn so a burst cannot starve XPC or commitment deadlines.
        for _ in 0..<64 {
            var peer = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = buffer.withUnsafeMutableBytes { bytes in
                withUnsafeMutablePointer(to: &peer) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.recvfrom(descriptor, bytes.baseAddress, bytes.count, 0, $0, &length)
                    }
                }
            }
            if count < 0 {
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK { return }
                fputs("steadfastd: udp receive failed: \(POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO).localizedDescription)\n", stderr)
                exit(1)
            }
            guard count <= 4096, let response = answer(Data(buffer.prefix(count))) else { continue }
            response.withUnsafeBytes { bytes in
                withUnsafePointer(to: &peer) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        _ = Darwin.sendto(descriptor, bytes.baseAddress, bytes.count, 0, $0, length)
                    }
                }
            }
        }
    }
}
