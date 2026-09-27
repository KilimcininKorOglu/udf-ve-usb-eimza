import Foundation

/// Response to a single APDU command: payload plus the SW1/SW2 status word.
public struct APDUResponse: Sendable {
    public let data: Data
    public let sw1: UInt8
    public let sw2: UInt8

    public var statusWord: UInt16 {
        (UInt16(sw1) << 8) | UInt16(sw2)
    }

    public var isSuccess: Bool {
        statusWord == 0x9000
    }

    public init(data: Data, sw1: UInt8, sw2: UInt8) {
        self.data = data
        self.sw1 = sw1
        self.sw2 = sw2
    }

    /// Splits a raw card response (payload followed by SW1 SW2) into parts.
    public init(raw: Data) throws {
        guard raw.count >= 2 else { throw CardError.shortResponse }
        let bytes = [UInt8](raw)
        self.sw1 = bytes[bytes.count - 2]
        self.sw2 = bytes[bytes.count - 1]
        self.data = Data(bytes[0..<(bytes.count - 2)])
    }
}

/// Errors raised by the card layer.
public enum CardError: Error, Sendable, Equatable {
    case slotManagerUnavailable
    case noReader
    case slotNotFound(String)
    case cardUnavailable
    case sessionFailed
    case shortResponse
    case apduFailed(UInt16)
    case pinIncorrect(retriesLeft: Int?)
    case fileNotFound
    case parse(String)
}

/// An open session with one card. Commands are serialised by the caller.
public protocol CardSession: Sendable {
    func transmit(_ apdu: Data) async throws -> APDUResponse
    func end() async
}

/// Access to card readers and cards.
public protocol CardTransport: Sendable {
    /// Names of the currently connected reader slots.
    func listSlots() async throws -> [String]
    /// Opens a session on the given slot, or the first slot when `nil`.
    func openSession(slotName: String?) async throws -> CardSession
}
