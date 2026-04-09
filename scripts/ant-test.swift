#!/usr/bin/env swift
// ANT+ USB Heart Rate Test — pure command line
// Translates WebANT's server.js flow to native Swift/IOKit
// Usage: swift scripts/ant-test.swift

import Foundation
import IOKit
import IOKit.usb

// ── ANT+ Constants ──
let SYNC: UInt8 = 0xA4
let MSG_SYSTEM_RESET: UInt8 = 0x4A
let MSG_ASSIGN_CHANNEL: UInt8 = 0x46
let MSG_SET_CHANNEL_ID: UInt8 = 0x51
let MSG_SET_CHANNEL_FREQ: UInt8 = 0x43
let MSG_SET_CHANNEL_PERIOD: UInt8 = 0x44
let MSG_OPEN_CHANNEL: UInt8 = 0x4B
let MSG_BROADCAST_DATA: UInt8 = 0x4E
let MSG_CHANNEL_RESPONSE: UInt8 = 0x40
let MSG_STARTUP: UInt8 = 0x6F

let ANT_VENDOR_ID: Int = 0x0FCF
let ANT_PRODUCT_IDS: [Int] = [0x1004, 0x1006, 0x1007, 0x1008, 0x1009]

// ── IOKit USB UUIDs ──
let kIOUSBDeviceUserClientTypeID_UUID = CFUUIDGetConstantUUIDWithBytes(nil,
    0x9d, 0xc7, 0xb7, 0x80, 0x9e, 0xc0, 0x11, 0xD4,
    0xa5, 0x4f, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)
let kIOCFPlugInInterfaceID_UUID = CFUUIDGetConstantUUIDWithBytes(nil,
    0xC2, 0x44, 0xE8, 0x58, 0x10, 0x9C, 0x11, 0xD4,
    0x91, 0xD4, 0x00, 0x50, 0xE4, 0xC6, 0x42, 0x6F)
let kIOUSBDeviceInterfaceID_UUID = CFUUIDGetConstantUUIDWithBytes(nil,
    0x5c, 0x81, 0x87, 0xd0, 0x9e, 0xf3, 0x11, 0xD4,
    0x8b, 0x45, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)
let kIOUSBInterfaceUserClientTypeID_UUID = CFUUIDGetConstantUUIDWithBytes(nil,
    0x2d, 0x97, 0x86, 0xc6, 0x9e, 0xf3, 0x11, 0xD4,
    0xad, 0x51, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)
let kIOUSBInterfaceInterfaceID_UUID = CFUUIDGetConstantUUIDWithBytes(nil,
    0x73, 0xc9, 0x7a, 0xe8, 0x9e, 0xf3, 0x11, 0xD4,
    0xb1, 0xd0, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)

// ── Helper: Build ANT+ message ──
func antMessage(_ msgID: UInt8, _ data: [UInt8]) -> Data {
    var msg: [UInt8] = [SYNC, UInt8(data.count), msgID] + data
    msg.append(msg.reduce(0, ^))
    return Data(msg)
}

// ── Helper: Parse ANT+ message ──
func parseANT(_ buffer: inout Data) -> (id: UInt8, payload: Data)? {
    guard buffer.count >= 4 else { return nil }
    guard let syncIdx = buffer.firstIndex(of: SYNC) else { buffer.removeAll(); return nil }
    if syncIdx > buffer.startIndex { buffer.removeSubrange(buffer.startIndex..<syncIdx) }
    guard buffer.count >= 4 else { return nil }
    let len = Int(buffer[buffer.startIndex + 1])
    let total = len + 4
    guard buffer.count >= total else { return nil }
    let msgID = buffer[buffer.startIndex + 2]
    let payload = Data(buffer[(buffer.startIndex + 3)..<(buffer.startIndex + 3 + len)])
    let checksum = buffer[buffer.startIndex..<(buffer.startIndex + total - 1)].reduce(0, ^)
    let expected = buffer[buffer.startIndex + total - 1]
    guard checksum == expected else { buffer.removeFirst(); return nil }
    buffer.removeFirst(total)
    return (msgID, payload)
}

func hex(_ data: Data) -> String {
    data.map { String(format: "%02X", $0) }.joined(separator: " ")
}

// ══════════════════════════════════════════
//  MAIN
// ══════════════════════════════════════════

print("🔌 ANT+ USB Heart Rate Test")
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━")

// Step 1: Find ANT+ USB stick
print("\n1️⃣  Searching for ANT+ USB stick...")

var antService: io_service_t = 0
for pid in ANT_PRODUCT_IDS {
    guard let matchDict = IOServiceMatching(kIOUSBDeviceClassName) as? NSMutableDictionary else { continue }
    matchDict[kUSBVendorID] = ANT_VENDOR_ID
    matchDict[kUSBProductID] = pid
    let svc = IOServiceGetMatchingService(kIOMainPortDefault, matchDict as CFDictionary)
    if svc != 0 { antService = svc; break }
}

guard antService != 0 else {
    print("❌ No ANT+ USB stick found. Plug one in and retry.")
    exit(1)
}
let productName = IORegistryEntryCreateCFProperty(antService, "USB Product Name" as CFString, nil, 0)?
    .takeRetainedValue() as? String ?? "Unknown"
print("✅ Found: \(productName)")

// Step 2: Open USB device
print("\n2️⃣  Opening USB device...")

typealias PlugInPtr = UnsafeMutablePointer<IOCFPlugInInterface>?
var plugInOpt: PlugInPtr = nil
var score: Int32 = 0
let kr1 = withUnsafeMutablePointer(to: &plugInOpt) { (ptr: UnsafeMutablePointer<PlugInPtr>) -> kern_return_t in
    IOCreatePlugInInterfaceForService(antService, kIOUSBDeviceUserClientTypeID_UUID, kIOCFPlugInInterfaceID_UUID, ptr, &score)
}
IOObjectRelease(antService)
guard kr1 == KERN_SUCCESS, let plugIn = plugInOpt else { print("❌ Failed to create plugin: \(kr1)"); exit(1) }

var devPtr: UnsafeMutableRawPointer?
_ = withUnsafeMutablePointer(to: &devPtr) { plugIn.pointee.QueryInterface(plugIn, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID_UUID), $0) }
_ = plugIn.pointee.Release(plugIn)
guard let devPtr else { print("❌ Failed to get device interface"); exit(1) }

let dev = devPtr.assumingMemoryBound(to: UnsafeMutablePointer<IOUSBDeviceInterface>.self)
guard dev.pointee.pointee.USBDeviceOpen(dev) == KERN_SUCCESS else { print("❌ USBDeviceOpen failed"); exit(1) }

// Set config
var configDesc: IOUSBConfigurationDescriptorPtr?
if dev.pointee.pointee.GetConfigurationDescriptorPtr(dev, 0, &configDesc) == KERN_SUCCESS, let c = configDesc {
    dev.pointee.pointee.SetConfiguration(dev, c.pointee.bConfigurationValue)
}
print("✅ USB device opened")

// Step 3: Claim interface + find bulk endpoints
print("\n3️⃣  Claiming USB interface...")

var ifReq = IOUSBFindInterfaceRequest(
    bInterfaceClass: UInt16(kIOUSBFindInterfaceDontCare), bInterfaceSubClass: UInt16(kIOUSBFindInterfaceDontCare),
    bInterfaceProtocol: UInt16(kIOUSBFindInterfaceDontCare), bAlternateSetting: UInt16(kIOUSBFindInterfaceDontCare))
var iter: io_iterator_t = 0
dev.pointee.pointee.CreateInterfaceIterator(dev, &ifReq, &iter)
let ifSvc = IOIteratorNext(iter); IOObjectRelease(iter)
guard ifSvc != 0 else { print("❌ No interface"); exit(1) }

var ifPlugInOpt: UnsafeMutablePointer<IOCFPlugInInterface>? = nil
_ = withUnsafeMutablePointer(to: &ifPlugInOpt) { ptr in
    IOCreatePlugInInterfaceForService(ifSvc, kIOUSBInterfaceUserClientTypeID_UUID, kIOCFPlugInInterfaceID_UUID, ptr, &score)
}
IOObjectRelease(ifSvc)
guard let ifPlugIn = ifPlugInOpt else { print("❌ No interface plugin"); exit(1) }

var ifRaw: UnsafeMutableRawPointer?
_ = withUnsafeMutablePointer(to: &ifRaw) { ifPlugIn.pointee.QueryInterface(ifPlugIn, CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID_UUID), $0) }
_ = ifPlugIn.pointee.Release(ifPlugIn)
guard let ifRaw else { print("❌ No interface interface"); exit(1) }

let iface = ifRaw.assumingMemoryBound(to: UnsafeMutablePointer<IOUSBInterfaceInterface>.self)
guard iface.pointee.pointee.USBInterfaceOpen(iface) == KERN_SUCCESS else { print("❌ InterfaceOpen failed"); exit(1) }

var numEP: UInt8 = 0; iface.pointee.pointee.GetNumEndpoints(iface, &numEP)
var readPipe: UInt8 = 0, writePipe: UInt8 = 0
for i: UInt8 in 1...numEP {
    var dir: UInt8 = 0, num: UInt8 = 0, tt: UInt8 = 0, intv: UInt8 = 0; var mps: UInt16 = 0
    iface.pointee.pointee.GetPipeProperties(iface, i, &dir, &num, &tt, &mps, &intv)
    if tt == 2 { if dir == 1 { readPipe = i } else { writePipe = i } }
}
guard readPipe != 0 && writePipe != 0 else { print("❌ No bulk endpoints"); exit(1) }
print("✅ Interface opened (read=\(readPipe), write=\(writePipe))")

// ── USB Write/Read helpers ──
func usbWrite(_ data: Data) {
    data.withUnsafeBytes { buf in
        let p = UnsafeMutableRawPointer(mutating: buf.baseAddress!)
        var kr = iface.pointee.pointee.WritePipe(iface, writePipe, p, UInt32(data.count))
        if kr != KERN_SUCCESS {
            iface.pointee.pointee.ClearPipeStallBothEnds(iface, writePipe)
            kr = iface.pointee.pointee.WritePipe(iface, writePipe, p, UInt32(data.count))
        }
    }
}

func usbRead() -> Data? {
    var buf = [UInt8](repeating: 0, count: 64)
    var n: UInt32 = 64
    let kr = iface.pointee.pointee.ReadPipe(iface, readPipe, &buf, &n)
    guard kr == KERN_SUCCESS && n > 0 else { return nil }
    return Data(buf[0..<Int(n)])
}

// Step 4: ANT+ Init — exactly like WebANT's stick.open() + sensor.attach(0,0)
print("\n4️⃣  Initializing ANT+ (like WebANT)...")

// Reset
print("   → Reset")
usbWrite(antMessage(MSG_SYSTEM_RESET, [0x00]))

// Wait for startup
if let resp = usbRead() { print("   ← \(hex(resp))") }
sleep(1)

// Channel config (like ant-plus library does internally)
let configMsgs: [(String, Data)] = [
    ("Assign Channel",  antMessage(MSG_ASSIGN_CHANNEL, [0, 0x00, 0])),
    ("Set Channel ID",  antMessage(MSG_SET_CHANNEL_ID, [0, 0x00, 0x00, 0x78, 0x00])),
    ("Set RF Freq",     antMessage(MSG_SET_CHANNEL_FREQ, [0, 57])),
    ("Set Period",      antMessage(MSG_SET_CHANNEL_PERIOD, [0, 0x86, 0x1F])),
    ("Open Channel",    antMessage(MSG_OPEN_CHANNEL, [0])),
]

for (name, msg) in configMsgs {
    usbWrite(msg)
    usleep(50_000)
    if let resp = usbRead() {
        let code = resp.count >= 6 ? resp[resp.startIndex + 5] : 255
        print("   → \(name) ← code=\(code) \(code == 0 ? "✅" : "❌")")
    }
}

// Step 5: Listen for heart rate broadcasts
print("\n5️⃣  Listening for heart rate data...")
print("   (Wear chest strap with wet contacts)")
print("   Press Ctrl+C to stop\n")

var readBuffer = Data()
var lastHR = 0

signal(SIGINT) { _ in
    print("\n\n👋 Stopped.")
    exit(0)
}

while true {
    guard let data = usbRead() else {
        print("   ⚠️  Read error, retrying...")
        usleep(100_000)
        continue
    }

    readBuffer.append(data)

    while let msg = parseANT(&readBuffer) {
        switch msg.id {
        case MSG_BROADCAST_DATA:
            if msg.payload.count >= 8 {
                let hr = Int(msg.payload[msg.payload.startIndex + 7])
                if hr > 0 && hr != lastHR {
                    lastHR = hr
                    print("   ❤️  Heart Rate: \(hr) BPM")
                }
            }
        case MSG_CHANNEL_RESPONSE:
            if msg.payload.count >= 3 {
                let code = msg.payload[msg.payload.startIndex + 2]
                if code == 1 { print("   ⏳ Search timeout — no sensor yet") }
            }
        case MSG_STARTUP:
            print("   🔄 Stick startup")
        default:
            break
        }
    }
}
