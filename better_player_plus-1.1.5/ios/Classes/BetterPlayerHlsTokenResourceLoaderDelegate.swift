import AVFoundation
import Foundation

final class BetterPlayerHlsTokenResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate {
    static let tokenScheme = "hls-token"

    private let originalScheme: String
    private let initialToken: String?
    private let initialExp: String?
    private let session: URLSession

    init(originalScheme: String, token: String?, exp: String?) {
        self.originalScheme = originalScheme
        self.initialToken = token
        self.initialExp = exp
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 10.0
        self.session = URLSession(configuration: config)
        super.init()
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let requestUrl = loadingRequest.request.url,
              let scheme = requestUrl.scheme,
              scheme == Self.tokenScheme else {
            return false
        }

        guard let resolvedUrl = resolvedUrl(for: requestUrl) else {
            return false
        }

        let now = Int(Date().timeIntervalSince1970)
        let currentToken = BetterPlayerHlsTokenStore.token() ?? initialToken ?? ""
        let currentExp = BetterPlayerHlsTokenStore.exp() ?? initialExp ?? ""
        // if !currentToken.isEmpty && !currentExp.isEmpty {
        //     NSLog(
        //         "BetterPlayer HLS request: now=%d exp=%@ token=%@ url=%@",
        //         now,
        //         currentExp,
        //         currentToken,
        //         resolvedUrl.absoluteString
        //     )
        // }

        let pathExt = resolvedUrl.pathExtension.lowercased()
        let isPlaylist = pathExt == "m3u8"

        // Handle both playlists and segments directly via URLSession so
        // every request uses the latest token without redirects.

        var request = URLRequest(url: resolvedUrl)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 10.0

        if let dataRequest = loadingRequest.dataRequest {
            let requestedOffset = dataRequest.requestedOffset
            let requestedLength = dataRequest.requestedLength
            if requestedOffset > 0 || requestedLength > 0 {
                let rangeHeader: String
                if requestedLength > 0 {
                    let endOffset = requestedOffset + Int64(requestedLength) - 1
                    rangeHeader = "bytes=\(requestedOffset)-\(endOffset)"
                } else {
                    rangeHeader = "bytes=\(requestedOffset)-"
                }
                request.setValue(rangeHeader, forHTTPHeaderField: "Range")
            }
        }

        var didFinish = false
        let finishLock = NSLock()
        func finishOnce(error: Error? = nil) {
            finishLock.lock()
            defer { finishLock.unlock() }
            if didFinish { return }
            didFinish = true
            if loadingRequest.isCancelled { return }
            if let error {
                loadingRequest.finishLoading(with: error)
            } else {
                loadingRequest.finishLoading()
            }
        }

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                NSLog("BetterPlayer HLS fetch failed: %@ url=%@", error.localizedDescription, resolvedUrl.absoluteString)
                finishOnce(error: error)
                return
            }
            if let httpResponse = response as? HTTPURLResponse {
                // NSLog(
                //     "BetterPlayer HLS fetch response: status=%d url=%@",
                //     httpResponse.statusCode,
                //     resolvedUrl.absoluteString
                // )
            }
            var responseData = data
            if let data = responseData,
               let playlist = String(data: data, encoding: .utf8),
               let self = self {
                let rewritten = self.rewritePlaylist(playlist, baseUrl: resolvedUrl)
                responseData = rewritten.data(using: .utf8)
            }
            if loadingRequest.isCancelled {
                finishOnce()
                return
            }
            if let httpResponse = response as? HTTPURLResponse {
                loadingRequest.response = httpResponse
            }
            if let response = response, let infoRequest = loadingRequest.contentInformationRequest {
                var contentType = response.mimeType
                if isPlaylist {
                    contentType = "application/vnd.apple.mpegurl"
                }
                infoRequest.contentType = contentType
                let expectedLength = (response as? HTTPURLResponse)?.expectedContentLength ?? -1
                if expectedLength > 0 {
                    infoRequest.contentLength = expectedLength
                } else {
                    infoRequest.contentLength = Int64(responseData?.count ?? 0)
                }
                infoRequest.isByteRangeAccessSupported = true
            }
            if let responseData = responseData, let dataRequest = loadingRequest.dataRequest {
                var requestedOffset = dataRequest.requestedOffset
                let requestedLength = dataRequest.requestedLength
                if requestedOffset < 0 { requestedOffset = 0 }
                var availableLength = responseData.count - Int(requestedOffset)
                if availableLength < 0 { availableLength = 0 }
                var bytesToRespond = availableLength
                if requestedLength > 0 && requestedLength < Int64(bytesToRespond) {
                    bytesToRespond = Int(requestedLength)
                }
                if loadingRequest.isCancelled {
                    finishOnce()
                    return
                }
                if bytesToRespond > 0,
                   Int(requestedOffset) + bytesToRespond <= responseData.count {
                    let chunk = responseData.subdata(in: Int(requestedOffset)..<Int(requestedOffset + Int64(bytesToRespond)))
                    dataRequest.respond(with: chunk)
                }
            }
            finishOnce()
        }
        task.resume()
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForRenewalOfRequestedResource renewalRequest: AVAssetResourceRenewalRequest) -> Bool {
        return self.resourceLoader(resourceLoader, shouldWaitForLoadingOfRequestedResource: renewalRequest)
    }

    private func resolvedUrl(for url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = originalScheme
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { item in
            item.name == "token" || item.name == "exp"
        }
        let token = BetterPlayerHlsTokenStore.token() ?? initialToken
        let exp = BetterPlayerHlsTokenStore.exp() ?? initialExp
        if let token, !token.isEmpty, let exp, !exp.isEmpty {
            queryItems.append(URLQueryItem(name: "token", value: token))
            queryItems.append(URLQueryItem(name: "exp", value: exp))
        }
        components.queryItems = queryItems
        return components.url
    }

    private func rewritePlaylist(_ playlist: String, baseUrl: URL) -> String {
        let token = BetterPlayerHlsTokenStore.token() ?? initialToken
        let exp = BetterPlayerHlsTokenStore.exp() ?? initialExp
        if token?.isEmpty ?? true || exp?.isEmpty ?? true {
            return playlist
        }
        let lines = playlist.components(separatedBy: .newlines)
        var output: [String] = []
        output.reserveCapacity(lines.count)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                output.append(line)
                continue
            }
            if trimmed.hasPrefix("#") {
                output.append(rewriteTagLine(line, baseUrl: baseUrl) ?? line)
                continue
            }
            guard let url = resolveUrl(from: trimmed, baseUrl: baseUrl) else {
                output.append(line)
                continue
            }
            let isPlaylist = url.pathExtension.lowercased() == "m3u8"
            let updatedUrl = urlByApplyingToken(url, useCustomScheme: isPlaylist)
            output.append(updatedUrl.absoluteString)
        }
        return output.joined(separator: "\n")
    }

    private func resolveUrl(from value: String, baseUrl: URL) -> URL? {
        if let url = URL(string: value), url.scheme != nil {
            return url
        }
        return URL(string: value, relativeTo: baseUrl)?.absoluteURL
    }

    private func urlByApplyingToken(_ url: URL, useCustomScheme: Bool) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { item in
            item.name == "token" || item.name == "exp"
        }
        let token = BetterPlayerHlsTokenStore.token() ?? initialToken
        let exp = BetterPlayerHlsTokenStore.exp() ?? initialExp
        if let token, !token.isEmpty, let exp, !exp.isEmpty {
            queryItems.append(URLQueryItem(name: "token", value: token))
            queryItems.append(URLQueryItem(name: "exp", value: exp))
        }
        components.queryItems = queryItems
        if useCustomScheme {
            components.scheme = Self.tokenScheme
        } else if components.scheme == Self.tokenScheme {
            components.scheme = originalScheme
        }
        return components.url ?? url
    }

    private func rewriteTagLine(_ line: String, baseUrl: URL) -> String? {
        let quoteCandidates = ["\"", "'"]
        var range: Range<String.Index>? = nil
        var quote: String? = nil
        for candidate in quoteCandidates {
            if let uriRange = line.range(of: "URI=\(candidate)") {
                range = uriRange
                quote = candidate
                break
            }
        }
        guard let uriRange = range, let quote = quote else {
            return nil
        }
        let startIndex = uriRange.upperBound
        guard let endRange = line.range(of: quote, range: startIndex..<line.endIndex) else {
            return nil
        }
        let uriValue = String(line[startIndex..<endRange.lowerBound])
        guard let url = resolveUrl(from: uriValue, baseUrl: baseUrl) else {
            return nil
        }
        let isPlaylist = url.pathExtension.lowercased() == "m3u8"
        let updatedUrl = urlByApplyingToken(url, useCustomScheme: isPlaylist)
        var updated = line
        updated.replaceSubrange(startIndex..<endRange.lowerBound, with: updatedUrl.absoluteString)
        return updated
    }
}
