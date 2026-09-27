@preconcurrency import CryptoTokenKit
import Foundation

/// Card access backed by CryptoTokenKit. Works on macOS and on iOS/iPadOS 16+
/// with a USB-C connected CCID reader; the same slot manager serves all.
public struct TKSmartCardTransport: CardTransport {
    public init() {}

    private func manager() throws -> TKSmartCardSlotManager {
        guard let manager = TKSmartCardSlotManager.default else {
            throw CardError.slotManagerUnavailable
        }
        return manager
    }

    public func listSlots() async throws -> [String] {
        try manager().slotNames
    }

    public func openSession(slotName: String?) async throws -> CardSession {
        let manager = try manager()
        guard let name = slotName ?? manager.slotNames.first else { throw CardError.noReader }
        // The non-Sendable slot never leaves this closure; only the Sendable
        // session wrapper crosses the continuation boundary.
        return try await withCheckedThrowingContinuation { continuation in
            manager.getSlot(withName: name) { slot in
                guard let slot else {
                    continuation.resume(throwing: CardError.slotNotFound(name))
                    return
                }
                guard slot.state == .validCard, let card = slot.makeSmartCard() else {
                    continuation.resume(throwing: CardError.cardUnavailable)
                    return
                }
                card.beginSession { ok, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if ok {
                        continuation.resume(returning: TKCardSession(card: card, readerName: name))
                    } else {
                        continuation.resume(throwing: CardError.sessionFailed)
                    }
                }
            }
        }
    }
}

/// A live session over one `TKSmartCard`.
///
/// The card object is not `Sendable`; access is serialised by the caller,
/// which issues APDUs one at a time within a single signing flow.
struct TKCardSession: CardSession, @unchecked Sendable {
    let card: TKSmartCard
    let readerName: String

    func transmit(_ apdu: Data) async throws -> APDUResponse {
        let response: Data = try await withCheckedThrowingContinuation { continuation in
            card.transmit(apdu) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: CardError.shortResponse)
                }
            }
        }
        return try APDUResponse(raw: response)
    }

    func end() async {
        card.endSession()
    }
}
