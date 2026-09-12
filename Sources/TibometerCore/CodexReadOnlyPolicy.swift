import Foundation

public enum CodexReadOnlyPolicy {
    public static func permits(method: String, params: [String: Any]? = nil) -> Bool {
        switch method {
        case "initialize", "initialized", "account/rateLimits/read":
            return true
        case "account/read":
            return params?["refreshToken"] as? Bool == false
        case "thread/list":
            // Database-only reads avoid rollout repairs.
            return params?["useStateDbOnly"] as? Bool == true
        case "account/usage/read":
            return true
        default:
            return false
        }
    }
}
