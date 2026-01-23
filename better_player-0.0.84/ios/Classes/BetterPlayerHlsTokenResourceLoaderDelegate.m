#import "BetterPlayerHlsTokenResourceLoaderDelegate.h"
#import "BetterPlayerHlsTokenStore.h"

static NSString *const kHlsTokenScheme = @"hls-token";
static NSString *const kHlsTokenQueryName = @"token";
static NSString *const kHlsExpQueryName = @"exp";

@interface BetterPlayerHlsTokenResourceLoaderDelegate ()
@property(nonatomic, copy) NSString *originalScheme;
@property(nonatomic, copy, nullable) NSString *initialToken;
@property(nonatomic, copy, nullable) NSString *initialExp;
@property(nonatomic, strong) NSURLSession *session;
@end

@implementation BetterPlayerHlsTokenResourceLoaderDelegate

- (instancetype)initWithOriginalScheme:(NSString *)scheme
                                 token:(NSString *)token
                                   exp:(NSString *)exp {
    self = [super init];
    if (self) {
        _originalScheme = [scheme copy];
        _initialToken = [token copy];
        _initialExp = [exp copy];
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        config.requestCachePolicy = NSURLRequestReloadIgnoringLocalAndRemoteCacheData;
        config.URLCache = nil;
        config.timeoutIntervalForRequest = 10.0;
        _session = [NSURLSession sessionWithConfiguration:config];
    }
    return self;
}

- (BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader
shouldWaitForLoadingOfRequestedResource:(AVAssetResourceLoadingRequest *)loadingRequest {
    NSURL *requestUrl = loadingRequest.request.URL;
    if (requestUrl == nil || requestUrl.scheme == nil) {
        return NO;
    }
    if (![requestUrl.scheme isEqualToString:kHlsTokenScheme]) {
        return NO;
    }

    NSURL *resolvedUrl = [self resolvedUrlForRequestUrl:requestUrl];
    if (resolvedUrl == nil) {
        return NO;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:resolvedUrl];
    request.cachePolicy = NSURLRequestReloadIgnoringLocalAndRemoteCacheData;
    request.timeoutInterval = 10.0;
    AVAssetResourceLoadingDataRequest *dataRequest = loadingRequest.dataRequest;
    if (dataRequest != nil) {
        long long requestedOffset = dataRequest.requestedOffset;
        long long requestedLength = dataRequest.requestedLength;
        if (requestedOffset > 0 || requestedLength > 0) {
            NSString *rangeHeader = nil;
            if (requestedLength > 0) {
                rangeHeader = [NSString stringWithFormat:@"bytes=%lld-%lld",
                               requestedOffset, requestedOffset + requestedLength - 1];
            } else {
                rangeHeader = [NSString stringWithFormat:@"bytes=%lld-", requestedOffset];
            }
            [request setValue:rangeHeader forHTTPHeaderField:@"Range"];
        }
    }

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error != nil) {
            [loadingRequest finishLoadingWithError:error];
            return;
        }
        NSData *responseData = data;
        NSString *pathExt = resolvedUrl.pathExtension.lowercaseString;
        BOOL isPlaylist = [pathExt isEqualToString:@"m3u8"];
        if (responseData != nil && isPlaylist) {
            NSString *playlist = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
            if (playlist != nil) {
                NSString *rewritten = [self rewritePlaylist:playlist baseUrl:resolvedUrl];
                if (rewritten != nil) {
                    responseData = [rewritten dataUsingEncoding:NSUTF8StringEncoding];
                }
            }
        }
        if (response != nil && loadingRequest.contentInformationRequest != nil) {
            NSString *contentType = response.MIMEType;
            if (isPlaylist) {
                contentType = @"application/vnd.apple.mpegurl";
            }
            loadingRequest.contentInformationRequest.contentType = contentType;
            loadingRequest.contentInformationRequest.contentLength =
                responseData.length;
            loadingRequest.contentInformationRequest.byteRangeAccessSupported = YES;
        }
        if (responseData != nil && loadingRequest.dataRequest != nil) {
            AVAssetResourceLoadingDataRequest *dataRequest = loadingRequest.dataRequest;
            long long requestedOffset = dataRequest.requestedOffset;
            long long requestedLength = dataRequest.requestedLength;
            if (requestedOffset < 0) {
                requestedOffset = 0;
            }
            long long availableLength = responseData.length - requestedOffset;
            if (availableLength < 0) {
                availableLength = 0;
            }
            long long bytesToRespond = availableLength;
            if (requestedLength > 0 && requestedLength < bytesToRespond) {
                bytesToRespond = requestedLength;
            }
            if (bytesToRespond > 0 && requestedOffset + bytesToRespond <= responseData.length) {
                NSData *chunk = [responseData subdataWithRange:NSMakeRange((NSUInteger)requestedOffset,
                                                                          (NSUInteger)bytesToRespond)];
                [dataRequest respondWithData:chunk];
            }
        }
        [loadingRequest finishLoading];
    }];
    [task resume];
    return YES;
}

- (BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader
shouldWaitForRenewalOfRequestedResource:(AVAssetResourceRenewalRequest *)renewalRequest {
    return [self resourceLoader:resourceLoader shouldWaitForLoadingOfRequestedResource:renewalRequest];
}

- (NSURL *)resolvedUrlForRequestUrl:(NSURL *)url {
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if (components == nil) {
        return nil;
    }
    components.scheme = self.originalScheme;

    NSMutableArray<NSURLQueryItem *> *queryItems =
        components.queryItems ? [components.queryItems mutableCopy] : [NSMutableArray array];
    NSIndexSet *indicesToRemove = [queryItems indexesOfObjectsPassingTest:^BOOL(NSURLQueryItem *item, NSUInteger idx, BOOL *stop) {
        return [item.name isEqualToString:kHlsTokenQueryName] || [item.name isEqualToString:kHlsExpQueryName];
    }];
    if (indicesToRemove.count > 0) {
        [queryItems removeObjectsAtIndexes:indicesToRemove];
    }

    NSString *token = [BetterPlayerHlsTokenStore token] ?: self.initialToken;
    NSString *exp = [BetterPlayerHlsTokenStore exp] ?: self.initialExp;
    if (token.length > 0 && exp.length > 0) {
        [queryItems addObject:[NSURLQueryItem queryItemWithName:kHlsTokenQueryName value:token]];
        [queryItems addObject:[NSURLQueryItem queryItemWithName:kHlsExpQueryName value:exp]];
    }
    components.queryItems = queryItems;
    return components.URL;
}

- (NSString *)rewritePlaylist:(NSString *)playlist baseUrl:(NSURL *)baseUrl {
    NSString *token = [BetterPlayerHlsTokenStore token] ?: self.initialToken;
    NSString *exp = [BetterPlayerHlsTokenStore exp] ?: self.initialExp;
    if (token.length == 0 || exp.length == 0) {
        return playlist;
    }
    NSArray<NSString *> *lines = [playlist componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSMutableArray<NSString *> *output = [NSMutableArray arrayWithCapacity:lines.count];
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length == 0) {
            [output addObject:line];
            continue;
        }
        if ([trimmed hasPrefix:@"#"]) {
            NSString *updatedTag = [self rewriteTagLine:line baseUrl:baseUrl];
            [output addObject:updatedTag ?: line];
            continue;
        }
        NSURL *url = [self resolveUrlFromString:trimmed baseUrl:baseUrl];
        if (url == nil) {
            [output addObject:line];
            continue;
        }
        BOOL isPlaylist = [[url.pathExtension lowercaseString] isEqualToString:@"m3u8"];
        NSURL *updatedUrl = [self urlByApplyingToken:url useCustomScheme:isPlaylist];
        [output addObject:updatedUrl.absoluteString ?: line];
    }
    return [output componentsJoinedByString:@"\n"];
}

- (NSURL *)resolveUrlFromString:(NSString *)value baseUrl:(NSURL *)baseUrl {
    NSURL *url = [NSURL URLWithString:value];
    if (url == nil || url.scheme == nil) {
        return [NSURL URLWithString:value relativeToURL:baseUrl].absoluteURL;
    }
    return url;
}

- (NSURL *)urlByApplyingToken:(NSURL *)url useCustomScheme:(BOOL)useCustomScheme {
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if (components == nil) {
        return url;
    }
    NSMutableArray<NSURLQueryItem *> *queryItems =
        components.queryItems ? [components.queryItems mutableCopy] : [NSMutableArray array];
    NSIndexSet *indicesToRemove = [queryItems indexesOfObjectsPassingTest:^BOOL(NSURLQueryItem *item, NSUInteger idx, BOOL *stop) {
        return [item.name isEqualToString:kHlsTokenQueryName] || [item.name isEqualToString:kHlsExpQueryName];
    }];
    if (indicesToRemove.count > 0) {
        [queryItems removeObjectsAtIndexes:indicesToRemove];
    }
    NSString *token = [BetterPlayerHlsTokenStore token] ?: self.initialToken;
    NSString *exp = [BetterPlayerHlsTokenStore exp] ?: self.initialExp;
    if (token.length > 0 && exp.length > 0) {
        [queryItems addObject:[NSURLQueryItem queryItemWithName:kHlsTokenQueryName value:token]];
        [queryItems addObject:[NSURLQueryItem queryItemWithName:kHlsExpQueryName value:exp]];
    }
    components.queryItems = queryItems;
    if (useCustomScheme) {
        components.scheme = kHlsTokenScheme;
    }
    return components.URL ?: url;
}

- (NSString *)rewriteTagLine:(NSString *)line baseUrl:(NSURL *)baseUrl {
    NSRange uriRange = [line rangeOfString:@"URI=\""];
    NSString *quote = @"\"";
    if (uriRange.location == NSNotFound) {
        uriRange = [line rangeOfString:@"URI='"];
        quote = @"'";
    }
    if (uriRange.location == NSNotFound) {
        return line;
    }
    NSUInteger start = uriRange.location + uriRange.length;
    NSRange searchRange = NSMakeRange(start, line.length - start);
    NSRange endRange = [line rangeOfString:quote options:0 range:searchRange];
    if (endRange.location == NSNotFound || endRange.location <= start) {
        return line;
    }
    NSString *uriValue = [line substringWithRange:NSMakeRange(start, endRange.location - start)];
    NSURL *url = [self resolveUrlFromString:uriValue baseUrl:baseUrl];
    if (url == nil) {
        return line;
    }
    BOOL isPlaylist = [[url.pathExtension lowercaseString] isEqualToString:@"m3u8"];
    NSURL *updatedUrl = [self urlByApplyingToken:url useCustomScheme:isPlaylist];
    if (updatedUrl.absoluteString == nil) {
        return line;
    }
    NSString *updatedLine = [line stringByReplacingCharactersInRange:NSMakeRange(start, endRange.location - start)
                                                          withString:updatedUrl.absoluteString];
    return updatedLine;
}

@end
