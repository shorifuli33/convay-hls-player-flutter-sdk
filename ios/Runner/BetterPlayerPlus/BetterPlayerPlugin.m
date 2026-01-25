#import "BetterPlayerPlugin.h"
#if __has_include("Runner-Swift.h")
#import "Runner-Swift.h"
#else
#import <Runner/Runner-Swift.h>
#endif

@implementation BetterPlayerPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftBetterPlayerPlugin registerWithRegistrar:registrar];
}
@end
