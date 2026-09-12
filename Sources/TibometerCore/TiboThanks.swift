import Foundation

public enum TiboThanks {
    public static let message = "Thanks @thsottiaux for resetting the Codex usage limits! Really appreciate it."

    public static let composeURL: URL = {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "x.com"
        components.path = "/intent/tweet"
        components.queryItems = [URLQueryItem(name: "text", value: message)]
        return components.url!
    }()
}
