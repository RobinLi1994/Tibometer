import Foundation

public struct ThreadReference: Codable, Sendable {
    public var id: String
    public var model: String?
    public var updatedAt: Int64
}

struct ThreadListResponse: Decodable {
    var data: [ThreadReference]
}

struct AccountThreadUsageResponse: Decodable {
    var threadUsage: ThreadUsage?
}

public struct ThreadUsage: Codable, Sendable {
    public var threadId: String
    public var estimatedUsageCreditsMicros: Int64
    public var estimatedUsageUsdMicros: Int64?
    public var groups: [ThreadUsageGroup]
}

public struct ThreadUsageGroup: Codable, Sendable {
    public var model: String?
    public var reasoningEffort: String?
    public var speed: String?
    public var inputTokens: Int64?
    public var cachedInputTokens: Int64?
    public var netNewInputTokens: Int64?
    public var outputTokens: Int64?
    public var totalTokens: Int64?
    public var estimatedUsageCreditsMicros: Int64
}
