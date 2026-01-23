#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BetterPlayerHlsTokenStore : NSObject
+ (void)updateToken:(nullable NSString *)token exp:(nullable NSString *)exp;
+ (nullable NSString *)token;
+ (nullable NSString *)exp;
+ (BOOL)hasToken;
@end

NS_ASSUME_NONNULL_END
