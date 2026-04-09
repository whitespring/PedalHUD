#import "ANTUSBDevice.h"
#import <IOKit/IOKitLib.h>
#import <IOKit/usb/IOUSBLib.h>
#import <IOKit/IOCFPlugIn.h>
#import <IOKit/usb/USB.h>
#import <os/log.h>

#ifndef kIOUSBTransactionTimeout
#define kIOUSBTransactionTimeout kIOReturnTimeout
#endif

static os_log_t antLog(void) {
    static os_log_t log;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        log = os_log_create("com.whitespring.MacAnt", "USBDevice");
    });
    return log;
}

@implementation ANTUSBDevice {
    IOUSBDeviceInterface **_deviceInterface;
    IOUSBInterfaceInterface **_interfaceInterface;
    UInt8 _readPipeRef;
    UInt8 _writePipeRef;
}

- (BOOL)openDeviceWithService:(io_service_t)service {
    os_log(antLog(), "openDeviceWithService called, service=%u", service);

    IOCFPlugInInterface **plugInInterface = NULL;
    SInt32 score = 0;

    kern_return_t kr = IOCreatePlugInInterfaceForService(
        service,
        kIOUSBDeviceUserClientTypeID,
        kIOCFPlugInInterfaceID,
        &plugInInterface,
        &score
    );

    if (kr != KERN_SUCCESS || !plugInInterface) {
        os_log_error(antLog(), "Failed to create plugin interface: kr=%d", kr);
        return NO;
    }
    os_log(antLog(), "Plugin interface created OK");

    HRESULT result = (*plugInInterface)->QueryInterface(
        plugInInterface,
        CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID),
        (LPVOID *)&_deviceInterface
    );
    (*plugInInterface)->Release(plugInInterface);

    if (result != S_OK || !_deviceInterface) {
        os_log_error(antLog(), "Failed to get device interface: result=%d", (int)result);
        return NO;
    }
    os_log(antLog(), "Device interface obtained OK");

    kr = (*_deviceInterface)->USBDeviceOpen(_deviceInterface);
    if (kr != KERN_SUCCESS) {
        os_log_error(antLog(), "USBDeviceOpen failed: kr=%d (0x%x)", kr, kr);
        (*_deviceInterface)->Release(_deviceInterface);
        _deviceInterface = NULL;
        return NO;
    }
    os_log(antLog(), "USB device opened OK");

    IOUSBConfigurationDescriptorPtr configDesc;
    kr = (*_deviceInterface)->GetConfigurationDescriptorPtr(_deviceInterface, 0, &configDesc);
    if (kr == KERN_SUCCESS) {
        kr = (*_deviceInterface)->SetConfiguration(_deviceInterface, configDesc->bConfigurationValue);
        os_log(antLog(), "Configuration set to %d, kr=%d", configDesc->bConfigurationValue, kr);
    } else {
        os_log_error(antLog(), "GetConfigurationDescriptorPtr failed: kr=%d", kr);
    }

    if (![self findAndClaimInterface]) {
        os_log_error(antLog(), "Failed to claim interface");
        (*_deviceInterface)->USBDeviceClose(_deviceInterface);
        (*_deviceInterface)->Release(_deviceInterface);
        _deviceInterface = NULL;
        return NO;
    }

    _isOpen = YES;
    os_log(antLog(), "Device fully opened: readPipe=%d, writePipe=%d", _readPipeRef, _writePipeRef);
    return YES;
}

- (BOOL)findAndClaimInterface {
    IOUSBFindInterfaceRequest request;
    request.bInterfaceClass = kIOUSBFindInterfaceDontCare;
    request.bInterfaceSubClass = kIOUSBFindInterfaceDontCare;
    request.bInterfaceProtocol = kIOUSBFindInterfaceDontCare;
    request.bAlternateSetting = kIOUSBFindInterfaceDontCare;

    io_iterator_t iterator;
    (*_deviceInterface)->CreateInterfaceIterator(_deviceInterface, &request, &iterator);

    io_service_t usbRef = IOIteratorNext(iterator);
    if (!usbRef) {
        os_log_error(antLog(), "No USB interfaces found");
        IOObjectRelease(iterator);
        return NO;
    }
    os_log(antLog(), "Found USB interface service: %u", usbRef);

    IOCFPlugInInterface **plugInInterface = NULL;
    SInt32 score = 0;
    IOCreatePlugInInterfaceForService(
        usbRef,
        kIOUSBInterfaceUserClientTypeID,
        kIOCFPlugInInterfaceID,
        &plugInInterface,
        &score
    );
    IOObjectRelease(usbRef);
    IOObjectRelease(iterator);

    if (!plugInInterface) {
        os_log_error(antLog(), "Failed to create interface plugin");
        return NO;
    }

    HRESULT result = (*plugInInterface)->QueryInterface(
        plugInInterface,
        CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID),
        (LPVOID *)&_interfaceInterface
    );
    (*plugInInterface)->Release(plugInInterface);

    if (result != S_OK || !_interfaceInterface) {
        os_log_error(antLog(), "Failed to get interface interface");
        return NO;
    }

    kern_return_t kr = (*_interfaceInterface)->USBInterfaceOpen(_interfaceInterface);
    if (kr != KERN_SUCCESS) {
        os_log_error(antLog(), "USBInterfaceOpen failed: kr=%d (0x%x)", kr, kr);
        return NO;
    }
    os_log(antLog(), "USB interface opened OK");

    UInt8 numEndpoints = 0;
    (*_interfaceInterface)->GetNumEndpoints(_interfaceInterface, &numEndpoints);
    os_log(antLog(), "Interface has %d endpoints", numEndpoints);

    for (UInt8 i = 1; i <= numEndpoints; i++) {
        UInt8 direction, number, transferType, interval;
        UInt16 maxPacketSize;

        (*_interfaceInterface)->GetPipeProperties(
            _interfaceInterface, i,
            &direction, &number, &transferType, &maxPacketSize, &interval
        );
        os_log(antLog(), "Endpoint %d: direction=%d number=%d transferType=%d maxPacket=%d", i, direction, number, transferType, maxPacketSize);

        if (transferType == kUSBBulk) {
            if (direction == kUSBIn) {
                _readPipeRef = i;
            } else if (direction == kUSBOut) {
                _writePipeRef = i;
            }
        }
    }

    BOOL success = (_readPipeRef != 0 && _writePipeRef != 0);
    os_log(antLog(), "Endpoint discovery: read=%d write=%d success=%d", _readPipeRef, _writePipeRef, success);
    return success;
}

- (void)closeDevice {
    if (_interfaceInterface) {
        (*_interfaceInterface)->USBInterfaceClose(_interfaceInterface);
        (*_interfaceInterface)->Release(_interfaceInterface);
        _interfaceInterface = NULL;
    }
    if (_deviceInterface) {
        (*_deviceInterface)->USBDeviceClose(_deviceInterface);
        (*_deviceInterface)->Release(_deviceInterface);
        _deviceInterface = NULL;
    }
    _readPipeRef = 0;
    _writePipeRef = 0;
    _isOpen = NO;
    os_log(antLog(), "Device closed");
}

- (BOOL)writeData:(NSData *)data {
    if (!_interfaceInterface || _writePipeRef == 0) {
        os_log_error(antLog(), "writeData: no interface or write pipe");
        return NO;
    }

    kern_return_t kr = (*_interfaceInterface)->WritePipe(
        _interfaceInterface,
        _writePipeRef,
        (void *)data.bytes,
        (UInt32)data.length
    );

    if (kr != KERN_SUCCESS) {
        os_log_error(antLog(), "WritePipe failed: kr=%d (0x%x), clearing pipe stall", kr, kr);
        // Clear pipe stall and retry once
        (*_interfaceInterface)->ClearPipeStallBothEnds(_interfaceInterface, _writePipeRef);
        kr = (*_interfaceInterface)->WritePipe(
            _interfaceInterface,
            _writePipeRef,
            (void *)data.bytes,
            (UInt32)data.length
        );
        if (kr != KERN_SUCCESS) {
            os_log_error(antLog(), "WritePipe retry also failed: kr=%d", kr);
            return NO;
        }
    }
    os_log(antLog(), "Wrote %lu bytes OK", (unsigned long)data.length);
    return YES;
}

- (nullable NSData *)readDataWithMaxLength:(NSUInteger)maxLength timeout:(UInt32)timeoutMs {
    if (!_interfaceInterface || _readPipeRef == 0) return nil;

    UInt8 *buffer = malloc(maxLength);
    if (!buffer) return nil;

    UInt32 bytesRead = (UInt32)maxLength;

    // Use ReadPipeTO with timeout to avoid blocking forever
    os_log(antLog(), "ReadPipeTO called, timeout=%dms", timeoutMs);
    kern_return_t kr = (*_interfaceInterface)->ReadPipeTO(
        _interfaceInterface,
        _readPipeRef,
        buffer,
        &bytesRead,
        timeoutMs,  // noDataTimeout
        timeoutMs   // completionTimeout
    );

    os_log_debug(antLog(), "ReadPipeTO kr=%d bytesRead=%d", kr, bytesRead);

    // Return data if we got any, regardless of error code
    // (kIOUSBTransactionTimeout often returns with valid data)
    if (bytesRead > 0) {
        NSData *result = [NSData dataWithBytes:buffer length:bytesRead];
        free(buffer);
        return result;
    }

    free(buffer);

    // Timeout with no data is normal
    if (kr == kIOUSBTransactionTimeout || kr == (int)0xe0004051 || kr == kIOReturnTimeout) {
        return [NSData data];
    }

    if (kr != KERN_SUCCESS) {
        os_log_error(antLog(), "ReadPipeTO error: kr=%d (0x%x)", kr, kr);
        return nil;
    }
    return [NSData data];
}

- (void)dealloc {
    [self closeDevice];
}

@end
