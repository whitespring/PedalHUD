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

/// Blocking read from USB bulk IN endpoint. Returns actual bytes read.
/// Returns nil on error. Call abortRead to unblock from another thread.
- (nullable NSData *)readDataWithMaxLength:(NSUInteger)maxLength;

/// Abort a blocking read (call from another thread to stop the read loop)
- (void)abortRead;

@end

NS_ASSUME_NONNULL_END
