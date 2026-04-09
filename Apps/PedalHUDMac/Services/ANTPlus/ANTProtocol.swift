import Foundation

/// ANT+ message constants and framing
enum ANTMessage {
    static let sync: UInt8 = 0xA4

    // Message IDs
    static let systemReset: UInt8 = 0x4A
    static let assignChannel: UInt8 = 0x46
    static let setChannelID: UInt8 = 0x51
    static let setChannelRFFreq: UInt8 = 0x43
    static let setChannelPeriod: UInt8 = 0x44
    static let openChannel: UInt8 = 0x4B
    static let closeChannel: UInt8 = 0x4C
    static let broadcastData: UInt8 = 0x4E
    static let channelResponse: UInt8 = 0x40
    static let startupMessage: UInt8 = 0x6F

    /// Build a complete ANT+ message with sync byte, length, ID, data, and checksum
    static func build(messageID: UInt8, data: [UInt8]) -> Data {
        var msg: [UInt8] = [sync, UInt8(data.count), messageID] + data
        let checksum = msg.reduce(0, ^)
        msg.append(checksum)
        return Data(msg)
    }

    /// Parse an ANT+ message from a data buffer. Returns (messageID, payload, bytesConsumed) or nil.
    static func parse(from data: Data) -> (messageID: UInt8, payload: Data, bytesConsumed: Int)? {
        guard data.count >= 4 else { return nil }

        // Find sync byte
        guard let syncIndex = data.firstIndex(of: sync) else { return nil }
        let remaining = data[syncIndex...]
        guard remaining.count >= 4 else { return nil }

        let length = Int(remaining[remaining.startIndex + 1])
        let totalLength = length + 4 // sync + length + msgID + data + checksum

        guard remaining.count >= totalLength else { return nil }

        let messageID = remaining[remaining.startIndex + 2]
        let payloadStart = remaining.startIndex + 3
        let payload = remaining[payloadStart..<payloadStart + length]

        // Verify checksum
        let messageBytes = remaining[remaining.startIndex..<remaining.startIndex + totalLength - 1]
        let computed = messageBytes.reduce(0, ^)
        let expected = remaining[remaining.startIndex + totalLength - 1]

        guard computed == expected else { return nil }

        let bytesConsumed = (syncIndex - data.startIndex) + totalLength
        return (messageID, Data(payload), bytesConsumed)
    }
}
