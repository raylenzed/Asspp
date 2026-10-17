#import <Foundation/Foundation.h>

// Keep NSError explicit in Swift: callers inspect it before accepting a signature.
NSData * _Nullable AssppSignAppleAction(
    NSData * _Nonnull data,
    NSError * _Nullable * _Nullable error
) __attribute__((swift_error(none)));
