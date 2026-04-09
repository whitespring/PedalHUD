import Foundation

/// ANT+ Heart Rate Monitor device profile
/// Sequence matches ant-plus npm library exactly:
/// https://github.com/Loghorn/ant-plus/blob/master/src/ant.ts
enum ANTHeartRateProfile {
    static let deviceType: UInt8 = 0x78     // 120 = Heart Rate Monitor
    static let rfFrequency: UInt8 = 57      // 2457 MHz
    static let channelPeriod: UInt16 = 8070 // ~4.06 Hz
    static let channel: UInt8 = 0
    static let networkNumber: UInt8 = 0
    static let searchTimeout: UInt8 = 255

    /// ANT+ managed network key
    static let networkKey: [UInt8] = [0xB9, 0xA5, 0x21, 0xFB, 0xBD, 0x72, 0xC3, 0x45]

    /// Init sequence matching ant-plus library's attach() exactly:
    ///   1. Reset
    ///   2. Set Network Key (0x46)
    ///   3. Assign Channel (0x42) — receive mode
    ///   4. Set Channel ID (0x51) — wildcard or specific
    ///   5. Set Search Timeout (0x44) — 255 = infinite
    ///   6. Set RF Frequency (0x45) — 57 = 2457MHz
    ///   7. Set Channel Period (0x43) — 8070
    ///   8. Lib Config (0x6E) — enable extended messages
    ///   9. Open Channel (0x4B)
    static func initSequence(deviceNumber: UInt16 = 0) -> [Data] {
        let devLo = UInt8(deviceNumber & 0xFF)
        let devHi = UInt8(deviceNumber >> 8)

        return [
            // 1. Reset
            ANTMessage.build(messageID: ANTMessage.systemReset, data: [0x00]),

            // 2. Set Network Key
            ANTMessage.build(messageID: ANTMessage.setNetworkKey, data: [networkNumber] + networkKey),

            // 3. Assign Channel (0x42, type=0x00=receive, network=0)
            ANTMessage.build(messageID: ANTMessage.assignChannel, data: [channel, 0x00, networkNumber]),

            // 4. Set Channel ID
            ANTMessage.build(messageID: ANTMessage.setChannelID, data: [channel, devLo, devHi, deviceType, 0x00]),

            // 5. Set Search Timeout (0x44, value=255)
            ANTMessage.build(messageID: ANTMessage.setSearchTimeout, data: [channel, searchTimeout]),

            // 6. Set RF Frequency (0x45, value=57)
            ANTMessage.build(messageID: ANTMessage.setChannelRFFreq, data: [channel, rfFrequency]),

            // 7. Set Channel Period (0x43, 8070 LE)
            ANTMessage.build(messageID: ANTMessage.setChannelPeriod, data: [
                channel, UInt8(channelPeriod & 0xFF), UInt8(channelPeriod >> 8)
            ]),

            // 8. Lib Config — enable extended messages (0xE0)
            ANTMessage.build(messageID: ANTMessage.libConfig, data: [0x00, 0xE0]),

            // 9. Open Channel
            ANTMessage.build(messageID: ANTMessage.openChannel, data: [channel]),
        ]
    }

    /// Extract heart rate from broadcast payload (includes channel byte)
    static func parseHeartRate(from payload: Data) -> Int? {
        guard payload.count >= 9 else { return nil }
        let hr = Int(payload[payload.startIndex + 8])
        return hr > 0 ? hr : nil
    }
}
