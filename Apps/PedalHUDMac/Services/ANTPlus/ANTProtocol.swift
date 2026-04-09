import Foundation

/// ANT+ message constants and framing
/// Message IDs from: https://github.com/Loghorn/ant-plus/blob/master/src/ant.ts
enum ANTMessage {
    static let sync: UInt8 = 0xA4

    // Config messages
    static let systemReset: UInt8 = 0x4A
    static let setNetworkKey: UInt8 = 0x46       // MESSAGE_NETWORK_KEY
    static let assignChannel: UInt8 = 0x42       // MESSAGE_CHANNEL_ASSIGN
    static let setChannelID: UInt8 = 0x51        // MESSAGE_CHANNEL_ID
    static let setChannelPeriod: UInt8 = 0x43    // MESSAGE_CHANNEL_PERIOD
    static let setSearchTimeout: UInt8 = 0x44    // MESSAGE_CHANNEL_SEARCH_TIMEOUT
    static let setChannelRFFreq: UInt8 = 0x45    // MESSAGE_CHANNEL_FREQUENCY
    static let setLowPrioritySearchTimeout: UInt8 = 0x63
    static let libConfig: UInt8 = 0x6E           // MESSAGE_LIB_CONFIG
    static let openChannel: UInt8 = 0x4B         // MESSAGE_CHANNEL_OPEN
    static let closeChannel: UInt8 = 0x4C

    // Data messages
    static let broadcastData: UInt8 = 0x4E
    static let channelResponse: UInt8 = 0x40
    static let requestMessage: UInt8 = 0x4D
    static let channelIDResponse: UInt8 = 0x51
    static let startupMessage: UInt8 = 0x6F

    /// Build a complete ANT+ message with sync byte, length, ID, data, and checksum
    static func build(messageID: UInt8, data: [UInt8]) -> Data {
        var msg: [UInt8] = [sync, UInt8(data.count), messageID] + data
        let checksum = msg.reduce(0, ^)
        msg.append(checksum)
        return Data(msg)
    }

    /// Parse an ANT+ message from a data buffer.
    static func parse(from data: Data) -> (messageID: UInt8, payload: Data, bytesConsumed: Int)? {
        guard data.count >= 4 else { return nil }
        guard let syncIndex = data.firstIndex(of: sync) else { return nil }
        let remaining = data[syncIndex...]
        guard remaining.count >= 4 else { return nil }

        let length = Int(remaining[remaining.startIndex + 1])
        let totalLength = length + 4

        guard remaining.count >= totalLength else { return nil }

        let messageID = remaining[remaining.startIndex + 2]
        let payloadStart = remaining.startIndex + 3
        let payload = remaining[payloadStart..<payloadStart + length]

        let messageBytes = remaining[remaining.startIndex..<remaining.startIndex + totalLength - 1]
        let computed = messageBytes.reduce(0, ^)
        let expected = remaining[remaining.startIndex + totalLength - 1]

        guard computed == expected else { return nil }

        let bytesConsumed = (syncIndex - data.startIndex) + totalLength
        return (messageID, Data(payload), bytesConsumed)
    }
}
