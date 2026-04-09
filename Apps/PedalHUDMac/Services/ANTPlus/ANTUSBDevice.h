#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Objective-C wrapper for IOKit USB bulk transfer communication with ANT+ sticks
@interface ANTUSBDevice : NSObject

@property (nonatomic, readonly) BOOL isOpen;

/// Open a USB device by IOService reference
- (BOOL)openDeviceWithService:(io_service_t)service;

/// Close the device and release all resources
- (void)closeDevice;

/// Write data to the USB bulk OUT endpoint
- (BOOL)writeData:(NSData *)data;

/// Read data from the USB bulk IN endpoint with timeout
/// Returns nil on error, empty data on timeout
- (nullable NSData *)readDataWithMaxLength:(NSUInteger)maxLength timeout:(UInt32)timeoutMs;

@end

NS_ASSUME_NONNULL_END
