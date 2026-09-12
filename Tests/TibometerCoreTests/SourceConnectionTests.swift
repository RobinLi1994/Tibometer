import TibometerCore

struct SourceConnectionTests {
    func testSavingWaitsForTheCurrentSource() {
        var feedback = SourceConnectionFeedback()
        feedback.complete(revision: 0)
        expectNil(feedback.message)

        feedback.begin(revision: 1)
        feedback.complete(revision: 0)
        expectEqual(feedback.message, "source.saved")
        feedback.complete(revision: 0, error: "error.timeout")
        expectEqual(feedback.message, "source.saved")
        feedback.complete(revision: 1)
        expectEqual(feedback.message, "status.connected")
    }

    func testSourceSwitchAndRecoveryNeverUseOldResults() {
        var feedback = SourceConnectionFeedback()
        feedback.begin(revision: 1)
        feedback.complete(revision: 1)
        feedback.begin(revision: 2)
        feedback.complete(revision: 1, error: "error.server_exit")
        expectEqual(feedback.message, "source.saved")

        feedback.complete(revision: 2, error: "error.timeout")
        expectEqual(feedback.message, "error.timeout")
        feedback.complete(revision: 1)
        expectEqual(feedback.message, "error.timeout")
        feedback.complete(revision: 2)
        expectEqual(feedback.message, "status.connected")

        feedback.begin(revision: 2)
        expectEqual(feedback.message, "source.saved")
        feedback.complete(revision: 2, error: "error.login")
        expectEqual(feedback.message, "error.login")
    }

    func testInvalidPathFeedbackSurvivesAnInFlightRequest() {
        var feedback = SourceConnectionFeedback()
        feedback.begin(revision: 1)
        feedback.reject("error.home")
        feedback.complete(revision: 1)
        expectEqual(feedback.message, "error.home")
        feedback.complete(revision: 1, error: "error.timeout")
        expectEqual(feedback.message, "error.home")

        feedback.begin(revision: 2)
        feedback.complete(revision: 2)
        expectEqual(feedback.message, "status.connected")
    }
}
