import Foundation

@testable import SignCore

/// In-memory card for tests. Answers SELECT and READ BINARY over a map of
/// file identifiers to content, chunking reads at 256 bytes like a real card.
final class MockCardSession: CardSession, @unchecked Sendable {
    private let files: [UInt16: Data]
    private var selected: UInt16?

    init(files: [UInt16: Data]) {
        self.files = files
    }

    func transmit(_ apdu: Data) async throws -> APDUResponse {
        let bytes = [UInt8](apdu)
        guard bytes.count >= 2 else { return APDUResponse(data: Data(), sw1: 0x6F, sw2: 0x00) }
        switch bytes[1] {
        case 0xA4:
            return handleSelect(bytes)
        case 0xB0:
            return handleReadBinary(bytes)
        default:
            return APDUResponse(data: Data(), sw1: 0x6D, sw2: 0x00)
        }
    }

    func end() async {}

    private func handleSelect(_ bytes: [UInt8]) -> APDUResponse {
        // Master file select carries 3F00; file select carries a 2-byte id.
        if bytes[2] == 0x02, bytes.count >= 7 {
            let fid = (UInt16(bytes[5]) << 8) | UInt16(bytes[6])
            guard files[fid] != nil else { return APDUResponse(data: Data(), sw1: 0x6A, sw2: 0x82) }
            selected = fid
        }
        return APDUResponse(data: Data(), sw1: 0x90, sw2: 0x00)
    }

    private func handleReadBinary(_ bytes: [UInt8]) -> APDUResponse {
        guard let fid = selected, let content = files[fid] else {
            return APDUResponse(data: Data(), sw1: 0x6B, sw2: 0x00)
        }
        let offset = Int(bytes[2]) << 8 | Int(bytes[3])
        guard offset < content.count else {
            return APDUResponse(data: Data(), sw1: 0x6B, sw2: 0x00)
        }
        let end = min(offset + 256, content.count)
        let chunk = content.subdata(in: offset..<end)
        return APDUResponse(data: chunk, sw1: 0x90, sw2: 0x00)
    }
}
