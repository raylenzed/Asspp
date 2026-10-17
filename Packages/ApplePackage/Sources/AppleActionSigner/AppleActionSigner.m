// Adapted from ipatool-sapfix 2.3.2-sapfix.2 (MIT); see LICENSE.ipatool.
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>

@interface AssppCKSigningSession : NSObject
- (instancetype)initWithStoreClient:(id)storeClient;
- (void)openSessionWithCompletionHandler:(void (^)(void))completionHandler;
- (NSData *)signData:(NSData *)data error:(NSError **)error;
- (void)closeSession;
- (BOOL)isSessionOpen;
@end

#import "AppleActionSigner.h"

NSData *AssppSignAppleAction(NSData *data, NSError **error) {
    if (error) { *error = nil; }
    @autoreleasepool {
        static void *handle;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            handle = dlopen("/System/Library/PrivateFrameworks/CommerceKit.framework/CommerceKit", RTLD_LAZY | RTLD_LOCAL);
        });
        NSString *message = nil;
        Class cls = handle ? NSClassFromString(@"CKSigningSession") : Nil;
        SEL initializer = @selector(initWithStoreClient:);
        if (!cls || ![cls instancesRespondToSelector:initializer]) {
            message = @"CommerceKit SAP signing is unavailable on this Mac.";
        } else {
            AssppCKSigningSession *session = [(id)[cls alloc] initWithStoreClient:nil];
            if (!session || ![session respondsToSelector:@selector(openSessionWithCompletionHandler:)] ||
                ![session respondsToSelector:@selector(signData:error:)] ||
                ![session respondsToSelector:@selector(closeSession)]) {
                message = @"CommerceKit SAP signing session is unavailable.";
            } else {
                dispatch_semaphore_t opened = dispatch_semaphore_create(0);
                [session openSessionWithCompletionHandler:^{ dispatch_semaphore_signal(opened); }];
                if (dispatch_semaphore_wait(opened, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC)) != 0) {
                    message = @"Timed out opening the Apple SAP signing session.";
                } else if ([session respondsToSelector:@selector(isSessionOpen)] && ![session isSessionOpen]) {
                    message = @"Apple SAP signing session did not open.";
                } else {
                    NSData *signature = [session signData:data error:error];
                    [session closeSession];
                    if (signature.length > 0) { return [signature copy]; }
                    if (error && *error) { return nil; }
                    message = @"CommerceKit returned an empty SAP signature.";
                    session = nil;
                }
                if (session) { [session closeSession]; }
            }
        }
        if (error) {
            *error = [NSError errorWithDomain:@"wiki.qaq.Asspp.AppleActionSigner" code:1
                                    userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return nil;
    }
}
