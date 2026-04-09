import Foundation

/// ANT+ Heart Rate Monitor device profile
enum ANTHeartRateProfile {
    static let deviceType: UInt8 = 0x78     // 120 = Heart Rate Monitor
    static let rfFrequency: UInt8 = 57      // 2457 MHz (ANT+ frequency)
    static let channelPeriod: UInt16 = 8070 // ~4.06 Hz message rate
    static let channel: UInt8 = 0
    static let networkNumber: UInt8 = 0

    /// Generate the full initialization sequence to start receiving HR data
    static func initSequence() -> [Data] {
        [
            // 1. Reset system
            ANTMessage.build(messageID: ANTMessage.systemReset, data: [0x00]),

            // 2. Assign channel (slave/receive on network 0)
            ANTMessage.build(messageID: ANTMessage.assignChannel, data: [channel, 0x00, networkNumber]),

            // 3. Set channel ID (wildcard device, HR device type, wildcard transmission)
            ANTMessage.build(messageID: ANTMessage.setChannelID, data: [channel, 0x00, 0x00, deviceType, 0x00]),

            // 4. Set RF frequency
            ANTMessage.build(messageID: ANTMessage.setChannelRFFreq, data: [channel, rfFrequency]),

            // 5. Set channel period (little-endian)
            ANTMessage.build(messageID: ANTMessage.setChannelPeriod, data: [
                channel,
                UInt8(channelPeriod & 0xFF),
                UInt8(channelPeriod >> 8)
            ]),

            // 6. Open channel
            ANTMessage.build(messageID: ANTMessage.openChannel, data: [channel]),
        ]
    }

    /// Extract heart rate from a broadcast data payload (8 bytes)
    /// - Parameter payload: The 8-byte data payload from a broadcast message (0x4E)
    /// - Returns: Heart rate in BPM, or nil if invalid
    static func parseHeartRate(from payload: Data) -> Int? {
        // Payload structure (8 bytes):
        // Byte 0: Page number / toggle bits
        // Bytes 1-3: Page-specific data
        // Byte 4-5: Heart beat event time (little-endian, 1/1024 sec)
        // Byte 6: Heart beat count
        // Byte 7: Computed heart rate (BPM)
        guard payload.count >= 8 else { return nil }

        let hr = Int(payload[payload.startIndex + 7])
        // 0 typically means no valid reading
        return hr > 0 ? hr : nil
    }
}
