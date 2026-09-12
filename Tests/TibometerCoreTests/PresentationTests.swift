import Foundation
import TibometerCore

final class PresentationTests {
    func testThanksLinkContainsOnlyTheEnglishDraft() throws {
        let previous = L10n.preference
        defer { L10n.preference = previous }
        for language in [AppLanguage.english, .chinese] {
            L10n.preference = language
            let components = try require(URLComponents(url: TiboThanks.composeURL, resolvingAgainstBaseURL: false))
            expectEqual(components.scheme, "https")
            expectEqual(components.host, "x.com")
            expectEqual(components.path, "/intent/tweet")
            let items = try require(components.queryItems)
            expectEqual(items.count, 1)
            expectEqual(items.first?.name, "text")
            expectEqual(items.first?.value, "Thanks @thsottiaux for resetting the Codex usage limits! Really appreciate it.")
        }
    }

    private func window(_ kind: QuotaWindow, used: Double? = 21) -> RateWindow {
        RateWindow(usedPercent: used, windowDurationMins: kind.rawValue, resetsAt: nil)
    }

    func testMissingWindowsAreHiddenEverywhere() {
        let weekly = RateBucket(primary: window(.weekly), secondary: nil)
        expectEqual(MenuBarPresentation.title(bucket: weekly), "7D 79%")
        expectEqual(MenuBarPresentation.visibleWindows(in: weekly), [.weekly])
        let five = RateBucket(primary: nil, secondary: window(.fiveHour, used: 0))
        expectEqual(MenuBarPresentation.title(bucket: five), "5H 100%")
        expectEqual(MenuBarPresentation.visibleWindows(in: five), [.fiveHour])
        let both = RateBucket(primary: window(.weekly), secondary: window(.fiveHour, used: 24))
        expectEqual(MenuBarPresentation.title(bucket: both), "5H 76% · 7D 79%")
        expectEqual(MenuBarPresentation.title(bucket: both, stale: true), "! 5H 76% · 7D 79%")
    }

    func testUnknownIsHiddenButExhaustedIsVisible() {
        for missing in [Double?.none, .nan, .infinity] {
            let bucket = RateBucket(primary: window(.fiveHour, used: missing), secondary: window(.weekly, used: 100))
            expectEqual(MenuBarPresentation.title(bucket: bucket), "7D 0%")
            expectEqual(MenuBarPresentation.visibleWindows(in: bucket), [.weekly])
        }
        expectEqual(MenuBarPresentation.title(bucket: nil), L10n.text("quota.empty"))
        expectEqual(MenuBarPresentation.title(bucket: RateBucket(primary: window(.fiveHour, used: nil), secondary: nil)), L10n.text("quota.empty"))
        expectEqual(MenuBarPresentation.visibleWindows(in: nil), [])
    }

    func testSystemDetectionAndManualOverride() {
        expectEqual(AppLanguage.system.resolved(preferredLanguages: ["zh-CN", "en-US"]), .chinese)
        expectEqual(AppLanguage.system.resolved(preferredLanguages: ["en-GB", "zh-Hans"]), .english)
        expectEqual(AppLanguage.system.resolved(preferredLanguages: ["zh_Hant_TW"]), .traditionalChinese)
        expectEqual(AppLanguage.system.resolved(preferredLanguages: ["fr-FR", "en-GB"]), .french)
        expectEqual(AppLanguage.system.resolved(preferredLanguages: ["de-DE"]), .german)
        expectEqual(AppLanguage.system.resolved(preferredLanguages: ["zh-HK"]), .traditionalChinese)
        expectEqual(AppLanguage.system.resolved(preferredLanguages: ["zh-MO"]), .traditionalChinese)
        expectEqual(AppLanguage.system.resolved(preferredLanguages: ["zh-Hans-TW"]), .chinese)
        expectEqual(AppLanguage.system.resolved(preferredLanguages: ["zh-SG"]), .chinese)
        expectEqual(AppLanguage.system.resolved(preferredLanguages: ["pt-PT"]), .portuguese)
        expectEqual(AppLanguage.system.resolved(preferredLanguages: ["es-MX"]), .spanish)
        expectEqual(AppLanguage.system.resolved(preferredLanguages: ["ar-SA", "ja-JP"]), .japanese)
        expectEqual(AppLanguage.system.resolved(preferredLanguages: ["ar-SA"]), .english)
        expectEqual(AppLanguage.system.resolved(preferredLanguages: []), .english)
        expectEqual(AppLanguage.english.resolved(preferredLanguages: ["zh-CN"]), .english)
        expectEqual(AppLanguage.chinese.resolved(preferredLanguages: ["en-US"]), .chinese)
    }

    func testStylePreferenceSurvivesReloadAndPreservesExistingSettings() throws {
        let suite = "app.tibometer.tests.menu-style.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let existingSettings = Data(#"{"refreshInterval":60,"webhookEnabled":true}"#.utf8)
        defaults.set(existingSettings, forKey: "settings")
        defaults.set("zh-Hans", forKey: "appearance.language")
        expectEqual(MenuBarStyle.load(from: defaults), .percentage)
        for style in MenuBarStyle.allCases {
            style.save(to: defaults)
            let reopened = try require(UserDefaults(suiteName: suite))
            expectEqual(MenuBarStyle.load(from: reopened), style)
        }
        for legacy in ["text", "stacked"] {
            defaults.set(legacy, forKey: "appearance.menuBarStyle")
            expectEqual(MenuBarStyle.load(from: defaults), .percentage)
        }
        defaults.set("unknown-future-style", forKey: "appearance.menuBarStyle")
        expectEqual(MenuBarStyle.load(from: defaults), .percentage)
        expectEqual(defaults.data(forKey: "settings"), existingSettings)
        expectEqual(defaults.string(forKey: "appearance.language"), "zh-Hans")
    }

    func testGraphicItemsUseRemainingValuesAndHideUnavailableWindows() throws {
        let both = RateBucket(primary: window(.weekly, used: 100), secondary: window(.fiveHour, used: 99.6))
        let items = MenuBarPresentation.items(in: both)
        expectEqual(items.map(\.window), [.fiveHour, .weekly])
        let first = try require(items.first)
        expect(abs(first.remainingPercent - 0.4) < 0.0001)
        expectEqual(first.text, "5H <1%")
        expectEqual(items.last?.remainingPercent, 0)
        expectEqual(items.last?.text, "7D 0%")
        let weekly = RateBucket(primary: window(.fiveHour, used: .nan), secondary: window(.weekly, used: 0))
        expectEqual(MenuBarPresentation.items(in: weekly).map(\.text), ["7D 100%"])
        expectEqual(MenuBarPresentation.items(in: weekly).map(\.remainingPercent), [100])
        expect(MenuBarPresentation.items(in: nil).isEmpty)
        let other = RateBucket(limitId: "other", primary: window(.fiveHour), secondary: window(.weekly))
        expect(MenuBarPresentation.items(in: other).isEmpty)
    }

    func testMenuBarScopeShowsOnlySelectedAvailableWindows() {
        let both = RateBucket(primary: window(.weekly), secondary: window(.fiveHour, used: 24))
        expectEqual(MenuBarPresentation.items(in: both, scope: .fiveHour).map(\.text), ["5H 76%"])
        expectEqual(MenuBarPresentation.items(in: both, scope: .weekly).map(\.text), ["7D 79%"])
        expectEqual(MenuBarPresentation.items(in: both, scope: .both).map(\.window), [.fiveHour, .weekly])
        expectEqual(MenuBarPresentation.title(bucket: both, stale: true, scope: .weekly), "! 7D 79%")
        let weekly = RateBucket(primary: window(.weekly, used: 100), secondary: nil)
        expect(MenuBarPresentation.items(in: weekly, scope: .fiveHour).isEmpty)
        expectEqual(MenuBarPresentation.title(bucket: weekly, scope: .fiveHour), L10n.text("quota.empty"))
        expectEqual(MenuBarPresentation.title(bucket: weekly, scope: .weekly), "7D 0%")
        expectEqual(MenuBarPresentation.title(bucket: weekly, scope: .both), "7D 0%")
        expectEqual(MenuBarPresentation.visibleWindows(in: both), [.fiveHour, .weekly])
        for scope in MenuBarScope.allCases {
            expect(MenuBarPresentation.items(in: nil, scope: scope).isEmpty)
        }
    }

    func testScopePreferenceSurvivesReloadAndPreservesStyle() throws {
        let suite = "app.tibometer.tests.menu-scope.\(UUID().uuidString)"
        let defaults = try require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        MenuBarStyle.ringsPercentage.save(to: defaults)
        let existing = Data(#"{"refreshInterval":60}"#.utf8)
        defaults.set(existing, forKey: "settings")
        expectEqual(MenuBarScope.load(from: defaults), .both)
        for scope in MenuBarScope.allCases {
            scope.save(to: defaults)
            let reopened = try require(UserDefaults(suiteName: suite))
            expectEqual(MenuBarScope.load(from: reopened), scope)
            expectEqual(MenuBarStyle.load(from: reopened), .ringsPercentage)
        }
        defaults.set("future-scope", forKey: "appearance.menuBarScope")
        expectEqual(MenuBarScope.load(from: defaults), .both)
        expectEqual(defaults.data(forKey: "settings"), existing)
    }

    func testOneAvailableWindowKeepsSizeAndCenters() throws {
        let dualBucket = RateBucket(primary: window(.weekly), secondary: window(.fiveHour), planType: "pro")
        for style in MenuBarStyle.allCases {
            let dual = try require(MenuBarLayout(itemCount: MenuBarPresentation.items(in: dualBucket).count, style: style))
            if [.percentage, .bars, .barsPercentage].contains(style) {
                expectEqual(dual.rowCount, 2)
                expectEqual(dual.rowHeight * 2, dual.height)
                expect(dual.centerY(forItem: 0) > dual.centerY(forItem: 1))
            }
            for kind in QuotaWindow.allCases {
                let bucket = RateBucket(primary: window(kind), secondary: nil, planType: "pro")
                let single = try require(MenuBarLayout(itemCount: MenuBarPresentation.items(in: bucket).count, style: style))
                expectEqual(single.rowCount, 1)
                expectEqual(single.height, dual.height)
                expectEqual(single.centerY(forItem: 0), single.height / 2)
                expectEqual(single.fontSize, dual.fontSize)
                expectEqual(single.barHeight, dual.barHeight)
                expectEqual(single.ringDiameter, dual.ringDiameter)
                expectEqual(single.ringLineWidth, dual.ringLineWidth)
            }
            expectNil(MenuBarLayout(itemCount: MenuBarPresentation.items(in: nil).count, style: style))
        }
    }

    func testProgressRingsAlignHorizontallyAndStayCentered() throws {
        for style in [MenuBarStyle.rings, .ringsPercentage] {
            let dual = try require(MenuBarLayout(itemCount: 2, style: style))
            let valueWidth = 24.0
            let extra = style == .ringsPercentage ? dual.ringPercentageSpacing + valueWidth : 0
            expectEqual(dual.rowCount, 1)
            expectEqual(dual.centerY(forItem: 0), dual.centerY(forItem: 1))
            expectEqual(dual.centerY(forItem: 0), dual.height / 2)
            expectEqual(dual.centerX(forRing: 0, percentageWidth: valueWidth) - dual.ringDiameter / 2, 0)
            let secondCenter = dual.centerX(forRing: 1, percentageWidth: valueWidth)
            expectEqual(secondCenter + dual.ringDiameter / 2 + extra, dual.ringsWidth(percentageWidth: valueWidth))
            expectEqual(secondCenter - dual.centerX(forRing: 0) - dual.ringDiameter - extra, dual.ringSpacing)
            expect(dual.ringSpacing > 0)
            expect(dual.ringDiameter <= dual.height)
            let single = try require(MenuBarLayout(itemCount: 1, style: style))
            expectEqual(single.ringsWidth(percentageWidth: valueWidth), dual.ringDiameter + extra)
            expectEqual(single.fontSize, dual.fontSize)
            if style == .rings { expectEqual(single.centerX(forRing: 0), single.ringsWidth() / 2) }
        }
    }

    func testCatalogsCoverTheSameKeysAndPlaceholders() throws {
        let english = L10n.table(for: .english)
        expect(english.count > 100, "English resources must be included in the package")
        let expression = try NSRegularExpression(pattern: #"\{\d+\}"#)
        func placeholders(_ value: String) -> [String] {
            expression.matches(in: value, range: NSRange(value.startIndex..., in: value)).map {
                (value as NSString).substring(with: $0.range)
            }.sorted()
        }
        for language in AppLanguage.allCases where language != .system {
            let table = L10n.table(for: language)
            expectEqual(Set(table.keys), Set(english.keys))
            for (key, value) in english {
                let translated = try require(table[key])
                expectFalse(translated.isEmpty, "\(language.rawValue): \(key)")
                expectEqual(placeholders(value), placeholders(translated))
            }
            expectEqual(table["app.tagline"], "A tiny Codex usage monitor")
            expectEqual(table["dashboard.subtitle"], "A tiny Codex usage monitor")
        }
        expectEqual(L10n.text("language.title", language: .english), "Language")
        expectEqual(L10n.text("language.title", language: .chinese), "语言")
        for style in MenuBarStyle.allCases {
            expectNotNil(english["menu_style.\(style.rawValue)"])
        }
        for scope in MenuBarScope.allCases { expectNotNil(english["menu_scope.\(scope.rawValue)"]) }
        expectEqual(L10n.text("reset.title", "quota/{1}", "5H", language: .english),
                    "quota/{1} · 5H reset")
    }

    func testLiveLanguageChangesErrorsNotificationsDatesAndMenu() throws {
        let previous = UserDefaults.standard.object(forKey: "appearance.language")
        defer { UserDefaults.standard.set(previous, forKey: "appearance.language") }
        let event = ResetEvent.testEvent(now: Date(timeIntervalSince1970: 1800000000))
        let error = TibometerError.rpc("account/read", -32000)
        let stored = try JSONDecoder().decode(LocalizedMessage.self, from: JSONEncoder().encode(LocalizedMessage("webhook.retrying", "2")))
        let bucket = RateBucket(primary: window(.weekly), secondary: nil)
        L10n.preference = .english
        expectEqual(UserDefaults.standard.string(forKey: "appearance.language"), "en")
        expectEqual(event.title, "Codex · 5-hour limit reset")
        expectEqual(stored.localized, "Delivery failed; retry pending (2/3)")
        expect(error.localizedDescription.contains("Codex request failed"))
        expectEqual(L10n.countdown(event.observedAt.addingTimeInterval(3660), now: event.observedAt), "Resets in 1h 1m")
        let englishDate = L10n.date(event.observedAt)
        expectEqual(WebhookPayload(reset: event, isTest: true).message, "Tibometer webhook test.")
        expectEqual(MenuBarPresentation.title(bucket: bucket), "7D 79%")
        L10n.preference = .chinese
        expectEqual(UserDefaults.standard.string(forKey: "appearance.language"), "zh-Hans")
        expectEqual(event.title, "Codex · 5 小时额度已重置")
        expectEqual(stored.localized, "投递失败，等待重试（2/3）")
        expect(error.localizedDescription.contains("Codex 请求失败"))
        expectEqual(L10n.countdown(event.observedAt.addingTimeInterval(3660), now: event.observedAt), "1 小时 1 分后重置")
        expect(englishDate != L10n.date(event.observedAt))
        expectEqual(WebhookPayload(reset: event, isTest: true).message, "Tibometer Webhook 测试。")
        expectEqual(MenuBarPresentation.title(bucket: bucket), "7D 79%")
    }

    func testAllLanguagesPersistAndUpdateRuntimeMessages() throws {
        let previous = UserDefaults.standard.object(forKey: "appearance.language")
        defer { UserDefaults.standard.set(previous, forKey: "appearance.language") }
        let languages = AppLanguage.allCases.filter { $0 != .system }
        expectEqual(languages.count, 16)
        expectEqual(Set(languages.map(\.websitePath)).count, languages.count)
        expectEqual(AppLanguage.chinese.websitePath, "/zh/")
        expectEqual(AppLanguage.traditionalChinese.websitePath, "/zh-Hant/")
        let event = ResetEvent.testEvent(now: Date(timeIntervalSince1970: 1800000000))
        let stored = LocalizedMessage("webhook.retrying", "2")
        for language in languages {
            L10n.preference = language
            expectEqual(L10n.preference, language)
            expectEqual(L10n.language, language)
            expectEqual(AppLanguage.system.resolved(preferredLanguages: [language.rawValue]), language)
            expectEqual(language.resolved(preferredLanguages: ["en-US"]), language)
            expectEqual(try JSONDecoder().decode(AppLanguage.self, from: JSONEncoder().encode(language)), language)
            expectFalse(L10n.date(event.observedAt).isEmpty)
            expectEqual(event.notificationTitle, L10n.table(for: language)["reset.headline"])
            expect(event.message.contains("100"))
            expect(stored.localized.contains("2/3"))
            expectFalse(stored.localized.contains("{0}"))
            expectFalse(L10n.countdown(event.observedAt.addingTimeInterval(3660), now: event.observedAt).contains("{1}"))
            if language != .english {
                expect(L10n.text("common.settings") != L10n.text("common.settings", language: .english))
                expect(event.message != L10n.text("reset.full", language: .english))
            }
        }
    }

    func testLegacyDeliveryHistoryStillDecodesAndLocalizes() throws {
        let examples: [(String, LocalizedMessage)] = [
            ("通知已提交", "notification.submitted"),
            ("Webhook 未启用", "webhook.disabled"),
            ("投递失败，等待重试（2/3）", .init("webhook.retrying", "2")),
            ("投递失败：Webhook 返回 HTTP 503。", .init("error.webhook_http", "503")),
            ("unknown legacy value", "unknown legacy value")
        ]
        for (legacy, expected) in examples {
            let decoded = try JSONDecoder().decode(LocalizedMessage.self, from: JSONEncoder().encode(legacy))
            expectEqual(decoded, expected)
            expectEqual(try JSONDecoder().decode(LocalizedMessage.self, from: JSONEncoder().encode(decoded)), expected)
        }
    }
}
