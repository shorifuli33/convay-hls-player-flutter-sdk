#import "BetterPlayerPlugin.h"
#if __has_include(<convay_hls_player/convay_hls_player-Swift.h>)
#import <convay_hls_player/convay_hls_player-Swift.h>
#else
#import "convay_hls_player-Swift.h"
#endif

@implementation BetterPlayerPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftBetterPlayerPlugin registerWithRegistrar:registrar];
}
@end
