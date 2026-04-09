import Foundation
import IOKit
import IOKit.usb
import os.log

private let logger = Logger(subsystem: "com.pedalhud", category: "ANTPlus")

// ANTUSBDevice is thread-safe (all methods are self-contained with internal locking)
extension ANTUSBDevice: @unchecked @retroactive Sendable {}

/// ANT+ USB heart rate client with device scanning and selection.
/// Phase 1 (Scan): Opens wildcard channel, collects all HR device IDs in range.
/// Phase 2 (Connect): User selects a device, channel re-opens targeting that specific device.
final class ANTUSBHeartRateClient: NSObject, @unchecked Sendable {
    var onHeartRate: ((Int) -> Void)?
    var onStateChange: ((String) -> Void)?
    var onPeripheralsChanged: (([DiscoveredPeripheral]) -> Void)?
    var onConnected: ((String) -> Void)?
    var onDisconnected: (() -> Void)?
    var onUSBAvailableChanged: ((Bool) -> Void)?

    private var usbDevice: ANTUSBDevice?
    private var notificationPort: IONotificationPortRef?
    private var matchIterator: io_iterator_t = 0
    private var readBuffer = Data()
    private var isReading = false
    private var sensorFound = false

    private let usbQueue = DispatchQueue(label: "com.pedalhud.ant.usb", qos: .userInitiated)
    private let readQueue = DispatchQueue(label: "com.pedalhud.ant.read", qos: .userInitiated)

    private static let vendorID: Int = 0x0FCF
    private static let productIDs: [Int] = [0x1004, 0x1006, 0x1007, 0x1008, 0x1009]

    /// Discovered ANT+ HR sensors: key = deviceNumber (UInt16), value = DiscoveredPeripheral
    private var discoveredSensors: [UInt16: DiscoveredPeripheral] = [:]

    /// The device number the user selected (nil = scanning/wildcard mode)
    private var selectedDeviceNumber: UInt16?

    // MARK: - Public Interface

    func start() {
        DispatchQueue.main.async {
            self.onStateChange?("Searching for ANT+ USB sticks")
        }
        startUSBMonitoring()
    }

    func stop() {
        isReading = false
        usbDevice?.abortRead()  // unblock the blocking ReadPipe
        selectedDeviceNumber = nil
        sensorFound = false
        discoveredSensors.removeAll()
        usbDevice?.close()
        usbDevice = nil
        stopUSBMonitoring()
        DispatchQueue.main.async {
            self.onPeripheralsChanged?([])
            self.onStateChange?("Not connected")
            self.onDisconnected?()
            self.onUSBAvailableChanged?(false)
        }
    }

    /// User selected a sensor from the discovered list — reconnect targeting that specific device
    func connectPeripheral(id: UUID) {
        // Find the device number from our discovered list
        guard let entry = discoveredSensors.first(where: { $0.value.id == id }) else { return }
        let deviceNumber = entry.key
        let name = entry.value.name

        logger.info("User selected ANT+ sensor: \(name) (device #\(deviceNumber))")
        selectedDeviceNumber = deviceNumber
        sensorFound = false

        DispatchQueue.main.async {
            self.onStateChange?("Connecting to \(name)")
        }

        // Close current channel and re-open targeting this specific device
        reconnectToDevice(deviceNumber: deviceNumber, name: name)
    }

    // MARK: - USB Monitoring

    private func startUSBMonitoring() {
        notificationPort = IONotificationPortCreate(kIOMainPortDefault)
        guard let port = notificationPort else { return }

        let runLoopSource = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)

        for productID in Self.productIDs {
            guard let matchingDict = IOServiceMatching(kIOUSBDeviceClassName) as? NSMutableDictionary else {
                continue
            }
            matchingDict[kUSBVendorID] = Self.vendorID
            matchingDict[kUSBProductID] = productID
            let matchCopy = matchingDict.mutableCopy() as! NSMutableDictionary

            IOServiceAddMatchingNotification(
                port, kIOFirstMatchNotification, matchCopy as CFDictionary,
                { refcon, iterator in
                    guard let refcon else { return }
                    Unmanaged<ANTUSBHeartRateClient>.fromOpaque(refcon).takeUnretainedValue()
                        .handleDeviceArrival(iterator: iterator)
                },
                Unmanaged.passUnretained(self).toOpaque(),
                &matchIterator
            )
            handleDeviceArrival(iterator: matchIterator)
        }
    }

    private func stopUSBMonitoring() {
        if matchIterator != 0 { IOObjectRelease(matchIterator); matchIterator = 0 }
        if let port = notificationPort { IONotificationPortDestroy(port); notificationPort = nil }
    }

    private func handleDeviceArrival(iterator: io_iterator_t) {
        var service: io_object_t
        repeat {
            service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            if let existing = usbDevice, existing.isOpen { IOObjectRelease(service); continue }

            let name = getPropertyValue(service: service, key: "USB Product Name") as? String ?? "ANT+ USB Stick"
            logger.info("ANT+ stick found: \(name)")

            let device = ANTUSBDevice()
            if device.open(withService: service) {
                self.usbDevice = device
                DispatchQueue.main.async {
                    self.onUSBAvailableChanged?(true)
                    self.onStateChange?("ANT+ stick connected — scanning for sensors")
                }
                // Start wildcard scan
                beginScan()
            } else {
                DispatchQueue.main.async { self.onStateChange?("Failed to open ANT+ stick") }
            }
            IOObjectRelease(service)
        } while true
    }

    private func getPropertyValue(service: io_object_t, key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    // MARK: - ANT+ Scan (wildcard — discover all HR sensors)

    private func beginScan() {
        guard let device = usbDevice, device.isOpen else { return }
        selectedDeviceNumber = nil
        sensorFound = false
        discoveredSensors.removeAll()

        startReading()

        usbQueue.async { [weak self, device] in
            guard let self else { return }
            self.sendInitSequence(device: device, deviceNumber: 0x0000) // wildcard
        }
    }

    // MARK: - ANT+ Connect (specific device)

    private func reconnectToDevice(deviceNumber: UInt16, name: String) {
        guard let device = usbDevice, device.isOpen else { return }

        usbQueue.async { [weak self, device] in
            guard let self else { return }

            // Close current channel
            let closeMsg = ANTMessage.build(messageID: ANTMessage.closeChannel, data: [ANTHeartRateProfile.channel])
            device.write(closeMsg)
            Thread.sleep(forTimeInterval: 0.3)

            // Re-init with specific device number
            self.sendInitSequence(device: device, deviceNumber: deviceNumber)

            DispatchQueue.main.async {
                self.onConnected?(name)
                self.onStateChange?("Receiving from \(name)")
            }
        }
    }

    private func sendInitSequence(device: ANTUSBDevice, deviceNumber: UInt16) {
        let ch = ANTHeartRateProfile.channel
        let devLo = UInt8(deviceNumber & 0xFF)
        let devHi = UInt8(deviceNumber >> 8)

        let sequence: [Data] = [
            ANTMessage.build(messageID: ANTMessage.systemReset, data: [0x00]),
        ]

        // Send reset
        if let reset = sequence.first { device.write(reset) }

        usbQueue.asyncAfter(deadline: .now() + 1.0) {
            let config: [Data] = [
                ANTMessage.build(messageID: ANTMessage.assignChannel, data: [ch, 0x00, ANTHeartRateProfile.networkNumber]),
                ANTMessage.build(messageID: ANTMessage.setChannelID, data: [ch, devLo, devHi, ANTHeartRateProfile.deviceType, 0x00]),
                ANTMessage.build(messageID: ANTMessage.setChannelRFFreq, data: [ch, ANTHeartRateProfile.rfFrequency]),
                ANTMessage.build(messageID: ANTMessage.setChannelPeriod, data: [
                    ch, UInt8(ANTHeartRateProfile.channelPeriod & 0xFF), UInt8(ANTHeartRateProfile.channelPeriod >> 8)
                ]),
                ANTMessage.build(messageID: ANTMessage.openChannel, data: [ch]),
            ]
            for msg in config {
                device.write(msg)
                Thread.sleep(forTimeInterval: 0.1)
            }
            logger.info("ANT+ channel opened (device=\(deviceNumber))")
        }
    }

    // MARK: - Reading

    private func startReading() {
        guard let device = usbDevice, device.isOpen, !isReading else { return }
        isReading = true

        readQueue.async { [weak self] in
            guard let self else { return }
            while self.isReading {
                // Blocking read — returns when data arrives or abortRead is called
                guard let data = device.readData(withMaxLength: 64) else {
                    // nil = error or abort
                    if self.isReading {
                        self.isReading = false
                        DispatchQueue.main.async {
                            self.onStateChange?("ANT+ stick disconnected")
                            self.onDisconnected?()
                        }
                    }
                    break
                }
                if data.count > 0 {
                    self.processReceivedData(data)
                }
            }
        }
    }

    // MARK: - Message Processing

    private func processReceivedData(_ data: Data) {
        readBuffer.append(data)

        while let parsed = ANTMessage.parse(from: readBuffer) {
            readBuffer = Data(readBuffer.dropFirst(parsed.bytesConsumed))

            switch parsed.messageID {
            case ANTMessage.broadcastData:
                handleBroadcast(parsed.payload)

            case ANTMessage.channelResponse:
                handleChannelResponse(parsed.payload)

            case ANTMessage.startupMessage:
                logger.info("ANT+ startup received")

            default:
                break
            }
        }
    }

    private func handleBroadcast(_ payload: Data) {
        guard payload.count >= 9 else { return }

        // In wildcard mode, the ANT+ stick auto-tracks whichever device it finds.
        // We extract the HR and also request the Channel ID to get the sender's device number.
        let channel = payload[payload.startIndex]

        // Parse HR from broadcast (byte 8 = computed HR, offset by channel byte)
        let hrByte = payload[payload.startIndex + 8]
        let hr = Int(hrByte)

        if hr > 0 {
            // If we're in scan mode (no specific device selected), request channel ID
            if selectedDeviceNumber == nil && !sensorFound {
                // Request Channel ID to learn who is sending
                if let device = usbDevice, device.isOpen {
                    let reqMsg = ANTMessage.build(messageID: ANTMessage.requestMessage, data: [channel, ANTMessage.channelIDResponse])
                    usbQueue.async { device.write(reqMsg) }
                }
            }

            DispatchQueue.main.async {
                self.onHeartRate?(hr)
            }

            if !sensorFound && selectedDeviceNumber != nil {
                sensorFound = true
            }
        }
    }

    private func handleChannelResponse(_ payload: Data) {
        guard payload.count >= 3 else { return }
        let msgID = payload[payload.startIndex + 1]
        let code = payload[payload.startIndex + 2]

        // Check if this is a Channel ID response (response to our request)
        if msgID == ANTMessage.channelIDResponse && payload.count >= 5 {
            let devLo = payload[payload.startIndex + 1]
            let devHi = payload[payload.startIndex + 2]
            let deviceNumber = UInt16(devLo) | (UInt16(devHi) << 8)

            if deviceNumber != 0 && discoveredSensors[deviceNumber] == nil {
                let sensorID = UUID()
                let name = "HR Sensor #\(deviceNumber)"
                let peripheral = DiscoveredPeripheral(id: sensorID, name: name, rssi: -40)
                discoveredSensors[deviceNumber] = peripheral

                logger.info("Discovered ANT+ sensor: \(name)")

                let list = Array(discoveredSensors.values).sorted { $0.name < $1.name }
                DispatchQueue.main.async {
                    self.onPeripheralsChanged?(list)
                    self.onStateChange?("Found \(self.discoveredSensors.count) HR sensor\(self.discoveredSensors.count == 1 ? "" : "s")")
                }
            }
        }

        // Search timeout
        if code == 1 {
            DispatchQueue.main.async {
                self.onStateChange?("No HR sensor found — is chest strap active?")
            }
        }
    }
}
