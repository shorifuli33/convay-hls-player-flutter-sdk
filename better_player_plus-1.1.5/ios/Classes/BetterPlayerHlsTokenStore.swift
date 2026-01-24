import Foundation

enum BetterPlayerHlsTokenStore {
    private static let lock = NSLock()
    private static var tokenValue: String?
    private static var expValue: String?

    static func update(token: String?, exp: String?) {
        lock.lock()
        tokenValue = token
        expValue = exp
        lock.unlock()
    }

    static func token() -> String? {
        lock.lock()
        let value = tokenValue
        lock.unlock()
        return value
    }

    static func exp() -> String? {
        lock.lock()
        let value = expValue
        lock.unlock()
        return value
    }

    static func hasToken() -> Bool {
        guard let token = token(), !token.isEmpty,
              let exp = exp(), !exp.isEmpty else {
            return false
        }
        return true
    }
}
