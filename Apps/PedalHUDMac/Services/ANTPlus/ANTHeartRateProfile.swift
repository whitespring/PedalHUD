import Foundation

/// ANT+ Heart Rate Monitor device profile
/// Matches the ant-plus npm library's channel configuration exactly
enum ANTHeartRateProfile {
    static let deviceType: UInt8 = 0x78     // 120 = Heart Rate Monitor
    static let rfFrequency: UInt8 = 57      // 2457 MHz (ANT+ frequency)
    static let channelPeriod: UInt16 = 8070 // ~4.06 Hz message rate
    static let channel: UInt8 = 0
    static let networkNumber: UInt8 = 0
    static let searchTimeout: UInt8 = 255   // Never stop searching (like ant-plus library)

    /// Generate the full initialization sequence to start receiving HR data.
    /// Matches the ant-plus npm library's attach() sequence exactly:
    ///   1. Reset
    ///   2. Assign channel (receive/slave)
    ///   3. Set channel ID (wildcard or specific device)
    ///   4. Set channel period
    ///   5. Set RF frequency
    ///   6. Set search timeout (255 = infinite)
    ///   7. Set low priority search timeout (0 = disable)
    ///   8. Open channel
    static func initSequence(deviceNumber: UInt16 = 0) -> [Data] {
        let devLo = UInt8(deviceNumber & 0xFF)
        let devHi = UInt8(deviceNumber >> 8)

        return [
            // 1. Reset system
            ANTMessage.build(messageID: ANTMessage.systemReset, data: [0x00]),

            // 2. Assign channel (channel 0, type 0x00 = slave/receive, network 0)
            ANTMessage.build(messageID: ANTMessage.assignChannel, data: [channel, 0x00, networkNumber]),

            // 3. Set channel ID (device number, device type 0x78, transmission type 0x00)
            ANTMessage.build(messageID: ANTMessage.setChannelID, data: [channel, devLo, devHi, deviceType, 0x00]),

            // 4. Set channel period (8070 = ~4.06 Hz, little-endian)
            ANTMessage.build(messageID: ANTMessage.setChannelPeriod, data: [
                channel,
                UInt8(channelPeriod & 0xFF),
                UInt8(channelPeriod >> 8)
            ]),

            // 5. Set RF frequency (57 = 2457 MHz)
            ANTMessage.build(messageID: ANTMessage.setChannelRFFreq, data: [channel, rfFrequency]),

            // 6. Set search timeout to 255 (infinite — keeps searching until found)
            ANTMessage.build(messageID: ANTMessage.setSearchTimeout, data: [channel, searchTimeout]),

            // 7. Set low priority search timeout to 0 (disable)
            ANTMessage.build(messageID: ANTMessage.setLowPrioritySearchTimeout, data: [channel, 0x00]),

            // 8. Open channel
            ANTMessage.build(messageID: ANTMessage.openChannel, data: [channel]),
        ]
    }

    /// Extract heart rate from a broadcast data payload
    /// Broadcast message (0x4E) payload structure (9 bytes with channel):
    ///   Byte 0: Channel number
    ///   Bytes 1-8: Data page (8 bytes)
    ///     Byte 1: Data page number / toggle
    ///     Bytes 2-4: Page-specific data
    ///     Bytes 5-6: Heart beat event time (little-endian, 1/1024 sec)
    ///     Byte 7: Heart beat count
    ///     Byte 8: Computed heart rate (BPM)
    static func parseHeartRate(from payload: Data) -> Int? {
        // Payload includes channel byte at start
        // HR is at the LAST byte of the 9-byte payload (index 8)
        guard payload.count >= 9 else { return nil }
        let hr = Int(payload[payload.startIndex + 8])
        return hr > 0 ? hr : nil
    }
}
