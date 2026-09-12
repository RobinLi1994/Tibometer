public struct SourceConnectionFeedback: Equatable {
    public private(set) var message: LocalizedMessage?
    private var sourceRevision: Int?

    public init() {}

    public mutating func begin(revision: Int) {
        sourceRevision = revision
        message = "source.saved"
    }

    public mutating func complete(revision: Int, error: LocalizedMessage? = nil) {
        guard sourceRevision == revision else { return }
        message = error ?? "status.connected"
    }

    public mutating func reject(_ error: LocalizedMessage) {
        sourceRevision = nil
        message = error
    }
}
