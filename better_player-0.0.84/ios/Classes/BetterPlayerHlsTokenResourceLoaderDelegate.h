#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BetterPlayerHlsTokenResourceLoaderDelegate : NSObject <AVAssetResourceLoaderDelegate>
- (instancetype)initWithOriginalScheme:(NSString *)scheme
                                 token:(nullable NSString *)token
                                   exp:(nullable NSString *)exp;
@end

NS_ASSUME_NONNULL_END
