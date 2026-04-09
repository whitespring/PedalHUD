import Foundation
import IOKit
import IOKit.usb
import os.log

private let logger = Logger(subsystem: "com.pedalhud", category: "ANTPlus")

/// ANT+ USB heart rate client — same callback interface as HeartRateBluetoothClient
@MainActor
final class ANTUSBHeartRateClient: NSObject {
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

    private let usbQueue = DispatchQueue(label: "com.pedalhud.ant.usb", qos: .userInitiated)
    private let readQueue = DispatchQueue(label: "com.pedalhud.ant.read", qos: .userInitiated)

    private static let vendorID: Int = 0x0FCF
    private static let productIDs: [Int] = [0x1004, 0x1006, 0x1007, 0x1008, 0x1009]

    private var discoveredSticks: [DiscoveredPeripheral] = []
    private var connectedStickName: String?
    private var sensorFound = false

    // MARK: - Public Interface

    func start() {
        updateState("Searching for ANT+ USB sticks")
        startUSBMonitoring()
    }

    func stop() {
        isReading = false
        usbDevice?.close()
        usbDevice = nil
        connectedStickName = nil
        sensorFound = false
        stopUSBMonitoring()
        discoveredSticks = []
        onPeripheralsChanged?([])
        updateState("Not connected")
        onDisconnected?()
    }

    func connectPeripheral(id: UUID) {
        // ANT+ auto-connects — just initialize HR scanning
        guard let device = usbDevice, device.isOpen else {
            updateState("ANT+ stick not available")
            return
        }
        initializeHeartRate()
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
                port,
                kIOFirstMatchNotification,
                matchCopy as CFDictionary,
                { refcon, iterator in
                    guard let refcon else { return }
                    let client = Unmanaged<ANTUSBHeartRateClient>.fromOpaque(refcon).takeUnretainedValue()
                    client.handleDeviceArrival(iterator: iterator)
                },
                Unmanaged.passUnretained(self).toOpaque(),
                &matchIterator
            )

            handleDeviceArrival(iterator: matchIterator)
        }
    }

    private func stopUSBMonitoring() {
        if matchIterator != 0 {
            IOObjectRelease(matchIterator)
            matchIterator = 0
        }
        if let port = notificationPort {
            IONotificationPortDestroy(port)
            notificationPort = nil
        }
    }

    private func handleDeviceArrival(iterator: io_iterator_t) {
        var service: io_object_t
        repeat {
            service = IOIteratorNext(iterator)
            guard service != 0 else { break }

            // Skip if already open
            if let existing = usbDevice, existing.isOpen {
                IOObjectRelease(service)
                continue
            }

            let name = getPropertyValue(service: service, key: "USB Product Name") as? String ?? "ANT+ USB Stick"
            let locationID = getPropertyValue(service: service, key: "locationID") as? UInt64 ?? UInt64(service)

            logger.info("ANT+ device found: \(name)")

            let device = ANTUSBDevice()
            let opened = device.open(withService: service)

            if opened {
                self.usbDevice = device
                let stickID = UUID(uuidString: String(format: "%08X-0000-0000-0000-%012X", UInt32(locationID >> 32), UInt64(locationID & 0xFFFFFFFFFFFF)))
                    ?? UUID()

                let peripheral = DiscoveredPeripheral(id: stickID, name: name, rssi: -30)
                discoveredSticks = [peripheral]

                DispatchQueue.main.async {
                    self.onPeripheralsChanged?(self.discoveredSticks)
                    self.onUSBAvailableChanged?(true)
                    self.updateState("ANT+ stick found: \(name)")
                }

                // Auto-start HR scanning
                initializeHeartRate()
            } else {
                DispatchQueue.main.async {
                    self.updateState("Failed to open ANT+ stick")
                }
            }

            IOObjectRelease(service)
        } while true
    }

    private func getPropertyValue(service: io_object_t, key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    // MARK: - ANT+ HR Initialization

    private func initializeHeartRate() {
        guard let device = usbDevice, device.isOpen else { return }

        // Start read loop first
        startReading()

        usbQueue.async {
            let sequence = ANTHeartRateProfile.initSequence()

            // Send reset
            if let resetMsg = sequence.first {
                device.write(resetMsg as Data)
            }

            // Wait for reset, then send config
            self.usbQueue.asyncAfter(deadline: .now() + 1.0) {
                guard let device = self.usbDevice, device.isOpen else { return }

                for msg in sequence.dropFirst() {
                    device.write(msg as Data)
                    Thread.sleep(forTimeInterval: 0.1)
                }

                DispatchQueue.main.async {
                    self.connectedStickName = self.discoveredSticks.first?.name
                    self.onConnected?(self.connectedStickName ?? "ANT+ Stick")
                    self.updateState("Searching for HR sensor")
                }
            }
        }
    }

    // MARK: - Reading

    private func startReading() {
        guard let device = usbDevice, device.isOpen else { return }
        isReading = true

        readQueue.async { [weak self] in
            guard let self else { return }

            while self.isReading {
                guard let data = device.readData(withMaxLength: 64, timeout: 1000) else {
                    if self.isReading {
                        self.isReading = false
                        DispatchQueue.main.async {
                            self.updateState("ANT+ stick disconnected")
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
                if let hr = ANTHeartRateProfile.parseHeartRate(from: parsed.payload) {
                    if !sensorFound {
                        sensorFound = true
                        DispatchQueue.main.async {
                            self.updateState("Receiving heart rate")
                        }
                    }
                    DispatchQueue.main.async {
                        self.onHeartRate?(hr)
                    }
                }

            case ANTMessage.channelResponse:
                handleChannelResponse(parsed.payload)

            case ANTMessage.startupMessage:
                logger.info("ANT+ stick startup received")

            default:
                break
            }
        }
    }

    private func handleChannelResponse(_ payload: Data) {
        guard payload.count >= 3 else { return }
        let code = payload[payload.startIndex + 2]

        // Search timeout
        if code == 1 {
            DispatchQueue.main.async {
                self.updateState("No HR sensor found — is the chest strap active?")
            }
        }
    }

    private func updateState(_ state: String) {
        onStateChange?(state)
    }
}
