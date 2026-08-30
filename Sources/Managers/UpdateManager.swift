//
//  UpdateManager.swift
//  FunNotch
//
//  In-app updates, via Sparkle.
//
//  FunNotch is signed ad-hoc rather than with a Developer ID, so macOS itself
//  vouches for nothing. The EdDSA signature on each update is what makes this
//  safe: Sparkle refuses anything not signed with the private key that matches
//  `SUPublicEDKey` in Info.plist. A tampered download fails that check and is
//  discarded before it is ever unpacked.
//

import AppKit
import Combine
import Sparkle

@MainActor
final class UpdateManager: NSObject, ObservableObject {
    static let shared = UpdateManager()

    /// Mirrors the updater's own idea of whether a check is allowed right now,
    /// so the menu item and the button in Settings can grey themselves out
    /// instead of failing when pressed.
    @Published private(set) var canCheckForUpdates = false

    /// The version we last saw offered, kept so Settings can say something
    /// more useful than "up to date" immediately after an update is found.
    @Published private(set) var lastCheckedAt: Date?

    private var controller: SPUStandardUpdaterController?
    private var cancellables = Set<AnyCancellable>()

    private override init() {
        super.init()
    }

    func start() {
        // `startingUpdater: true` lets Sparkle schedule its own background
        // checks on the interval in Info.plist. Nothing is downloaded or
        // installed without the user agreeing in Sparkle's own dialog.
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        self.controller = controller

        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
            .store(in: &cancellables)

        lastCheckedAt = controller.updater.lastUpdateCheckDate
    }

    /// Explicit "Check for Updates…". Shows Sparkle's UI, including the "you're
    /// up to date" case, because a check that silently does nothing reads as
    /// broken.
    func checkForUpdates() {
        controller?.updater.checkForUpdates()
        lastCheckedAt = Date()
    }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? true }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}

extension UpdateManager: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        Task { @MainActor in
            self.lastCheckedAt = updater.lastUpdateCheckDate
        }
    }
}
