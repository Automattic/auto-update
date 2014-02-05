//
//  AUUpdater.m
//  AutoUpdate
//
//  Created by Marco on 05/01/2013.
//  Copyright (c) 2014 Automattic, Inc. All rights reserved.
//

#import "AUUpdater.h"
#import "NSFileManager+DirectoryLocations.h"

@implementation AUUpdater

/**
 * Creates an updater object
 *
 * @public
 */

+ (AUUpdater *)updaterWithBundle:(NSBundle *)theBundle host:(NSString *)theHost channel:(NSString *)theChannel percentile:(NSInteger)thePercentile {
    
    AUUpdater *updater = [[AUUpdater alloc] initWithBundle:theBundle host:theHost channel:theChannel percentile:thePercentile];

    return updater;
}

/**
 * Updater constructor
 *
 * @private
 */

- (AUUpdater *)initWithBundle:(NSBundle *)theBundle host:(NSString *)theHost channel:(NSString *)theChannel percentile:(NSInteger)thePercentile {
    
    self = [super init];

    if (self) {
        _state = AUUpdaterStateIdle;
        if ([_delegate respondsToSelector:@selector(updater:didChangeState:)]) {
            [_delegate updater:self didChangeState:_state];
        }
        
        _bundle = theBundle;
        _host = theHost;
        _channel = theChannel;
        _percentile = thePercentile;
        _interval = 1 * 60 * 60; // 1 hour default interval
        
        _destination = [NSString stringWithFormat:@"%@/auto-update.tar.gz", [[NSFileManager defaultManager] applicationSupportDirectory]];
        
        _semaphore = dispatch_semaphore_create(1);
        _queue = dispatch_queue_create("com.automattic.AutoUpdate.UpdateQueue", NULL);
                
        [self detectVersion];
    }
    
    return self;
}

/**
 * Release resources
 *
 * @private
 */

- (void)dealloc {
    dispatch_release(_semaphore);
    dispatch_release(_queue);
}

/**
 * Detects the current OS X version.
 *
 * @private
 */

- (void)detectVersion {
    // TODO: Add a future-proof OS X version check
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    Gestalt(gestaltSystemVersionMajor, &_osxMajorVersion);
    Gestalt(gestaltSystemVersionMinor, &_osxMinorVersion);
    Gestalt(gestaltSystemVersionBugFix, &_osxPatchVersion);
#pragma clang diagnostic pop
    _osxVersion = [NSString stringWithFormat:@"%i.%i.%i", _osxMajorVersion, _osxMinorVersion, _osxPatchVersion];
    _architecture = @"x86-64";
}

/**
 * Returns the priority of the updater task
 *
 * @private
 */

- (long)updaterPriority {
    if ((_osxMajorVersion == 10 && _osxMinorVersion >= 7) || (_osxMajorVersion > 10)) {
        return DISPATCH_QUEUE_PRIORITY_BACKGROUND;
    } else {
        return DISPATCH_QUEUE_PRIORITY_LOW;
    }
}

/**
 * Performs the update check in the background
 * 
 * @public
 */

- (void)checkForUpdates {
    
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    if (_state != AUUpdaterStateIdle) {
        dispatch_semaphore_signal(_semaphore);
        return;
    }
    _state = AUUpdaterStateDownloading;
    _totalBytes = 0;
    _downloadedBytes = 0;
    dispatch_semaphore_signal(_semaphore);
    if ([_delegate respondsToSelector:@selector(updater:didChangeState:)]) {
        [_delegate updater:self didChangeState:_state];
    }
    
    dispatch_async(_queue, ^{
        
        // Build Download URL
        NSDictionary *bundleInfo = _bundle.infoDictionary;
        NSString *path = [NSString stringWithFormat:@"%@/update?architecture=%@&os=osx&osversion=%@&app=%@&appversion=%@-%@&channel=%@&percentile=%d", _host, _architecture, _osxVersion, bundleInfo[@"CFBundleName"], bundleInfo[@"CFBundleShortVersionString"], bundleInfo[@"CFBundleVersion"], _channel, (int)_percentile];
        NSURL *url = [NSURL URLWithString:path];
        
        // Start Download
        NSURLRequest *request = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData timeoutInterval:15.0];
        NSURLDownload *download = [[NSURLDownload alloc] initWithRequest:request delegate:self];
        [download setDestination:_destination allowOverwrite:YES];
        
        // Enter run loop so that we can catch the download events
        while (self.state == AUUpdaterStateDownloading) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
        }
        
    });

}

/**
 * Called when the NSURLDownload receives an HTTP Response from the server
 *
 * @private
 */

- (void)download:(NSURLDownload *)download didReceiveResponse:(NSURLResponse *)response {
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSString *contentDisposition = [httpResponse allHeaderFields][@"Content-Disposition"];
        if (contentDisposition) {
            _critical = [contentDisposition rangeOfString:@"critical"].location != NSNotFound;
        } else {
            _critical = NO;
        }
        _totalBytes = [response expectedContentLength];
        _downloadedBytes = 0;
        if ([_delegate respondsToSelector:@selector(updater:didChangeProgress:)]) {
            [_delegate updater:self didChangeProgress:[self progress]];
        }
    }
}

/**
 * Called when the NSURLDownload receives data from the server
 *
 * @private
 */

- (void)download:(NSURLDownload *)download didReceiveDataOfLength:(NSUInteger)length {
    _downloadedBytes += length;
    
    if ([_delegate respondsToSelector:@selector(updater:didChangeProgress:)]) {
        [_delegate updater:self didChangeProgress:[self progress]];
    }
}

/**
 * Called to determine the encodings NSURLDownload can decode. We always return NO, to avoid producing invalid download progress
 * percentages, and using extra disk space.
 *
 * @private
 */

- (BOOL)download:(NSURLDownload *)download shouldDecodeSourceDataOfMIMEType:(NSString *)encodingType
{
    return NO;
}

/**
 * Called when the NSURLDownload finishes successfully
 *
 * @private
 */

- (void)downloadDidFinish:(NSURLDownload *)download {
    self.state = AUUpdaterStateReady;
    __block dispatch_semaphore_t semaphore = dispatch_semaphore_create(1);
    while (self.state == AUUpdaterStateReady) {
        // notify the main thread every ten seconds about the update
        __block BOOL responded = NO;
        dispatch_async(dispatch_get_main_queue(), ^{
            [_delegate updater:self wantsToInstallUpdateWithCriticalStatus:_critical];
            dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
            responded = YES;
            dispatch_semaphore_signal(semaphore);
        });
        sleep(10);
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
        // if the main thread is blocked, force the update
        if (!responded) {
            [self installUpdate];
        }
        dispatch_semaphore_signal(semaphore);
    }
    dispatch_release(semaphore);
}

/**
 * Called when the NSURLDownload fails
 *
 * @private
 */

- (void)download:(NSURLDownload *)download didFailWithError:(NSError *)error {
    
    _totalBytes = 0;
    _downloadedBytes = 0;
    self.state = AUUpdaterStateIdle;
    
    // Try again after interval
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, _interval * NSEC_PER_SEC), dispatch_get_current_queue(), ^{
        [self checkForUpdates];
    });
}

/**
 * Installs the downloaded update
 *
 * @public
 */

- (void) installUpdate {
    
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    if (_state != AUUpdaterStateReady) {
        dispatch_semaphore_signal(_semaphore);
        return;
    }
    _state = AUUpdaterStateInstalling;
    _totalBytes = 0;
    _downloadedBytes = 0;
    dispatch_semaphore_signal(_semaphore);
    if ([_delegate respondsToSelector:@selector(updater:didChangeState:)]) {
        [_delegate updater:self didChangeState:_state];
    }
    
    
    NSBundle *updaterBundle = [NSBundle bundleForClass:[self class]];
    NSTask *task = [[NSTask alloc] init];
    
    task.launchPath = [updaterBundle pathForResource:@"install-update" ofType:@"sh"];
    task.arguments = @[_destination, _bundle.bundlePath];
    task.environment = [[NSProcessInfo processInfo].environment dictionaryWithValuesForKeys:@[@"PATH", @"USER", @"HOME", @"SHELL"]];
    
    [task launch];
    
    exit(0);
}

/**
 * Retrieve the state in a thread safe manner
 *
 * @public
 */

- (AUUpdaterState) state {
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    AUUpdaterState temp = _state;
    dispatch_semaphore_signal(_semaphore);
    return temp;
}

/**
 * Set the state in a thread safe manner
 *
 * @private
 */

- (void) setState:(AUUpdaterState) state {
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    _state = state;
    dispatch_semaphore_signal(_semaphore);
    if ([_delegate respondsToSelector:@selector(updater:didChangeState:)]) {
        [_delegate updater:self didChangeState:state];
    }
}

/**
 * Returns the progress of the update download
 *
 * @private
 */

- (double) progress {
    return (double)_downloadedBytes / (double)_totalBytes;
}

@end
