#import "BetterPlayerHlsTokenStore.h"

@implementation BetterPlayerHlsTokenStore

static NSString *_hlsToken = nil;
static NSString *_hlsExp = nil;

+ (void)updateToken:(NSString *)token exp:(NSString *)exp {
    @synchronized(self) {
        _hlsToken = token;
        _hlsExp = exp;
    }
}

+ (NSString *)token {
    @synchronized(self) {
        return _hlsToken;
    }
}

+ (NSString *)exp {
    @synchronized(self) {
        return _hlsExp;
    }
}

+ (BOOL)hasToken {
    @synchronized(self) {
        return _hlsToken != nil && _hlsToken.length > 0 && _hlsExp != nil && _hlsExp.length > 0;
    }
}

@end
