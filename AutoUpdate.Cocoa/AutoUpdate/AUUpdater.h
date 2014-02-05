//
//  AUUpdater.h
//  AutoUpdate
//
//  Created by Marco on 05/01/2013.
//  Copyright (c) 2014 Automattic, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum {
    AUUpdaterStateIdle,
    AUUpdaterStateDownloading,
    AUUpdaterStateReady,
    AUUpdaterStateInstalling
} AUUpdaterState;

@class AUUpdater;

@protocol AUUpdaterDelegate <NSObject>
@required
- (void) updater:(AUUpdater *)updater wantsToInstallUpdateWithCriticalStatus:(BOOL)critical;
@optional
- (void) updater:(AUUpdater *)updater didChangeState:(AUUpdaterState)state;
- (void) updater:(AUUpdater *)updater didChangeProgress:(double)progress;
@end

@interface AUUpdater : NSObject<NSURLDownloadDelegate> {
    SInt32 _osxMajorVersion;
    SInt32 _osxMinorVersion;
    SInt32 _osxPatchVersion;
    NSString *_destination;
    NSString *_osxVersion;
    NSString *_architecture;
    id <AUUpdaterDelegate> _delegate;
    AUUpdaterState _state;
    dispatch_semaphore_t _semaphore;
    dispatch_queue_t _queue;
    BOOL _critical;
}

+ (AUUpdater *)updaterWithBundle:(NSBundle *)theBundle host:(NSString *)theHost channel:(NSString *)theChannel percentile:(NSInteger)thePercentile;
- (void)checkForUpdates;
- (void)installUpdate;

@property (readonly) NSBundle *bundle;
@property (readonly) NSString *host;
@property (readonly) NSString *channel;
@property (readonly) NSInteger percentile;
@property (readwrite) NSTimeInterval interval;
@property (readonly) AUUpdaterState state;
@property (readwrite) id <AUUpdaterDelegate> delegate;
@property (readonly) long long totalBytes;
@property (readonly) long long downloadedBytes;
@property (readonly) double progress;

@end
