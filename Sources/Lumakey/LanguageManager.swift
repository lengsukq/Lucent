import AppKit
import Combine
import Foundation
import LumakeyCore
import SwiftUI

extension Notification.Name {
    static let lumakeyLanguageDidChange = Notification.Name("app.lumakey.languageDidChange")
}

@MainActor
final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    @Published private(set) var current: AppLanguageID
    let detectedSystemLanguage: AppLanguageID

    private init() {
        let sys = AppLanguageConfig.detectSystemLanguage()
        self.detectedSystemLanguage = sys
        let bootstrapped = AppLanguageConfig.loadOrBootstrap()
        L10n.setCurrent(bootstrapped.selectedLanguage)
        self.current = bootstrapped.selectedLanguage
        Self.syncAppleLanguagesPreference(bootstrapped.selectedLanguage)
    }

    var locale: Locale {
        current.locale
    }

    func apply(_ language: AppLanguageID, persist: Bool = true) {
        L10n.setCurrent(language)
        if current != language {
            current = language
        }
        if persist {
            AppLanguageConfig(selectedLanguage: language).save()
        }
        Self.syncAppleLanguagesPreference(language)
        NotificationCenter.default.post(name: .lumakeyLanguageDidChange, object: language)
    }

    @discardableResult
    func cycle() -> AppLanguageID {
        let next = current.next
        apply(next, persist: true)
        return next
    }

    func reloadFromDisk() {
        let loaded = L10n.reloadFromDisk()
        apply(loaded, persist: false)
    }

    private static func syncAppleLanguagesPreference(_ language: AppLanguageID) {
        UserDefaults.standard.set([language.localeIdentifier], forKey: "AppleLanguages")
    }
}

/// 挂载在每个 NSHostingView 根部的响应式多语言容器：切换语言时同步更新 SwiftUI `\.locale` 并驱动全子树实时重绘。
struct LocalizedRootContainer<Content: View>: View {
    @ObservedObject private var languageManager = LanguageManager.shared
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.locale, languageManager.locale)
            .id(languageManager.current)
    }
}
