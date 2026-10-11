import Darwin
import Foundation

public enum SocketError: Error, CustomStringConvertible {
    case pathTooLong(String)
    case system(operation: String, code: Int32)
    case closed
    case timedOut

    public var description: String {
        switch self {
        case .pathTooLong(let path): return "Socket path too long: \(path)"
        case .system(let op, let code): return "\(op) failed: \(String(cString: strerror(code)))"
        case .closed: return "Socket closed by peer"
        case .timedOut: return "Socket timed out"
        }
    }
}

/// Thin, explicit wrapper over a POSIX `AF_UNIX` stream socket.
public struct UnixSocket: Sendable {
    public let fd: Int32

    public init(fd: Int32) { self.fd = fd }

    // MARK: Lifecycle

    public static func connect(to url: URL) throws -> UnixSocket {
        let socket = try makeSocket()
        do {
            try withAddress(url.path) { address, length in
                guard Darwin.connect(socket.fd, address, length) == 0 else {
                    throw SocketError.system(operation: "connect", code: errno)
                }
            }
            return socket
        } catch {
            socket.close()
            throw error
        }
    }

    public static func listen(at url: URL, backlog: Int32 = 32) throws -> UnixSocket {
        unlink(url.path) // Remove a stale socket left by a previous crash.
        let socket = try makeSocket()
        do {
            try withAddress(url.path) { address, length in
                guard bind(socket.fd, address, length) == 0 else {
                    throw SocketError.system(operation: "bind", code: errno)
                }
            }
            chmod(url.path, 0o600)
            guard Darwin.listen(socket.fd, backlog) == 0 else {
                throw SocketError.system(operation: "listen", code: errno)
            }
            return socket
        } catch {
            socket.close()
            throw error
        }
    }

    public func accept() throws -> UnixSocket {
        let client = Darwin.accept(fd, nil, nil)
        guard client >= 0 else { throw SocketError.system(operation: "accept", code: errno) }
        let socket = UnixSocket(fd: client)
        socket.disableSigPipe()
        return socket
    }

    public func close() {
        Darwin.close(fd)
    }

    // MARK: Options

    public func setNonBlocking() {
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
    }

    public func setReceiveTimeout(seconds: Int) {
        var timeout = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    private func disableSigPipe() {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    // MARK: I/O

    /// Writes the full buffer, retrying on partial writes.
    public func send(_ data: Data) throws {
        try data.withUnsafeBytes { raw in
            guard var pointer = raw.baseAddress else { return }
            var remaining = raw.count
            while remaining > 0 {
                let written = Darwin.write(fd, pointer, remaining)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw SocketError.system(operation: "write", code: errno)
                }
                remaining -= written
                pointer = pointer.advanced(by: written)
            }
        }
    }

    /// Reads whatever is available. Returns an empty `Data` on EOF.
    public func receive(maxLength: Int = 64 * 1024) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: maxLength)
        while true {
            let count = Darwin.read(fd, &buffer, maxLength)
            if count >= 0 { return Data(buffer.prefix(count)) }
            if errno == EINTR { continue }
            if errno == EAGAIN || errno == EWOULDBLOCK { throw SocketError.timedOut }
            throw SocketError.system(operation: "read", code: errno)
        }
    }

    // MARK: Helpers

    private static func makeSocket() throws -> UnixSocket {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.system(operation: "socket", code: errno) }
        let socket = UnixSocket(fd: fd)
        socket.disableSigPipe()
        return socket
    }

    private static func withAddress(
        _ path: String,
        _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> Void
    ) throws {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        let bytes = Array(path.utf8)
        guard bytes.count < capacity else { throw SocketError.pathTooLong(path) }

        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        try withUnsafePointer(to: &address) { pointer in
            try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { try body($0, length) }
        }
    }
}
