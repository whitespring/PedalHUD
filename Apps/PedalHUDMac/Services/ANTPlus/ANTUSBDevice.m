#import "ANTUSBDevice.h"
#import <IOKit/IOKitLib.h>
#import <IOKit/usb/IOUSBLib.h>
#import <IOKit/IOCFPlugIn.h>
#import <IOKit/usb/USB.h>
#import <os/log.h>

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
        service, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID,
        &plugInInterface, &score
    );
    if (kr != KERN_SUCCESS || !plugInInterface) {
        os_log_error(antLog(), "Failed to create plugin interface: kr=%d", kr);
        return NO;
    }

    HRESULT result = (*plugInInterface)->QueryInterface(
        plugInInterface, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID),
        (LPVOID *)&_deviceInterface
    );
    (*plugInInterface)->Release(plugInInterface);
    if (result != S_OK || !_deviceInterface) {
        os_log_error(antLog(), "Failed to get device interface");
        return NO;
    }

    kr = (*_deviceInterface)->USBDeviceOpen(_deviceInterface);
    if (kr != KERN_SUCCESS) {
        os_log_error(antLog(), "USBDeviceOpen failed: kr=%d (0x%x)", kr, kr);
        (*_deviceInterface)->Release(_deviceInterface);
        _deviceInterface = NULL;
        return NO;
    }
    os_log(antLog(), "USB device opened OK");

    IOUSBConfigurationDescriptorPtr configDesc;
    if ((*_deviceInterface)->GetConfigurationDescriptorPtr(_deviceInterface, 0, &configDesc) == KERN_SUCCESS) {
        (*_deviceInterface)->SetConfiguration(_deviceInterface, configDesc->bConfigurationValue);
    }

    if (![self findAndClaimInterface]) {
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
    IOUSBFindInterfaceRequest request = {
        kIOUSBFindInterfaceDontCare, kIOUSBFindInterfaceDontCare,
        kIOUSBFindInterfaceDontCare, kIOUSBFindInterfaceDontCare
    };
    io_iterator_t iterator;
    (*_deviceInterface)->CreateInterfaceIterator(_deviceInterface, &request, &iterator);

    io_service_t usbRef = IOIteratorNext(iterator);
    if (!usbRef) { IOObjectRelease(iterator); return NO; }

    IOCFPlugInInterface **plugIn = NULL;
    SInt32 score = 0;
    IOCreatePlugInInterfaceForService(usbRef, kIOUSBInterfaceUserClientTypeID, kIOCFPlugInInterfaceID, &plugIn, &score);
    IOObjectRelease(usbRef);
    IOObjectRelease(iterator);
    if (!plugIn) return NO;

    HRESULT result = (*plugIn)->QueryInterface(plugIn, CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID), (LPVOID *)&_interfaceInterface);
    (*plugIn)->Release(plugIn);
    if (result != S_OK || !_interfaceInterface) return NO;

    kern_return_t kr = (*_interfaceInterface)->USBInterfaceOpen(_interfaceInterface);
    if (kr != KERN_SUCCESS) {
        os_log_error(antLog(), "USBInterfaceOpen failed: %d", kr);
        return NO;
    }

    UInt8 numEndpoints = 0;
    (*_interfaceInterface)->GetNumEndpoints(_interfaceInterface, &numEndpoints);

    for (UInt8 i = 1; i <= numEndpoints; i++) {
        UInt8 direction, number, transferType, interval;
        UInt16 maxPacketSize;
        (*_interfaceInterface)->GetPipeProperties(_interfaceInterface, i, &direction, &number, &transferType, &maxPacketSize, &interval);
        if (transferType == kUSBBulk) {
            if (direction == kUSBIn)  _readPipeRef = i;
            if (direction == kUSBOut) _writePipeRef = i;
        }
    }
    return (_readPipeRef != 0 && _writePipeRef != 0);
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
}

- (BOOL)writeData:(NSData *)data {
    if (!_interfaceInterface || _writePipeRef == 0) return NO;

    kern_return_t kr = (*_interfaceInterface)->WritePipe(
        _interfaceInterface, _writePipeRef, (void *)data.bytes, (UInt32)data.length
    );
    if (kr != KERN_SUCCESS) {
        (*_interfaceInterface)->ClearPipeStallBothEnds(_interfaceInterface, _writePipeRef);
        kr = (*_interfaceInterface)->WritePipe(
            _interfaceInterface, _writePipeRef, (void *)data.bytes, (UInt32)data.length
        );
        if (kr != KERN_SUCCESS) {
            os_log_error(antLog(), "WritePipe failed after retry: %d", kr);
            return NO;
        }
    }
    os_log(antLog(), "Wrote %lu bytes OK", (unsigned long)data.length);
    return YES;
}

/// Blocking read — returns when data arrives. Call abortRead to unblock.
- (nullable NSData *)readDataWithMaxLength:(NSUInteger)maxLength {
    if (!_interfaceInterface || _readPipeRef == 0) return nil;

    UInt8 *buffer = calloc(maxLength, 1);
    if (!buffer) return nil;

    UInt32 bytesRead = (UInt32)maxLength;

    kern_return_t kr = (*_interfaceInterface)->ReadPipe(
        _interfaceInterface,
        _readPipeRef,
        buffer,
        &bytesRead
    );

    if (kr == KERN_SUCCESS && bytesRead > 0) {
        NSData *result = [NSData dataWithBytes:buffer length:bytesRead];
        free(buffer);
        os_log(antLog(), "Read %d bytes OK", bytesRead);
        return result;
    }

    free(buffer);

    if (kr == kIOReturnAborted) {
        // abortRead was called — normal shutdown
        return nil;
    }

    os_log_error(antLog(), "ReadPipe error: kr=%d (0x%x)", kr, kr);
    return nil;
}

/// Abort a blocking ReadPipe call from another thread
- (void)abortRead {
    if (_interfaceInterface && _readPipeRef != 0) {
        (*_interfaceInterface)->AbortPipe(_interfaceInterface, _readPipeRef);
        os_log(antLog(), "Read pipe aborted");
    }
}

- (void)dealloc {
    [self closeDevice];
}

@end
