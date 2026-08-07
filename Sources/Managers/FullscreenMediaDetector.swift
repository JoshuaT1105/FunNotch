//
//  FullscreenMediaDetector.swift
//  FunNotch
//
//  Gets the notch out of the way when an app takes over a display. Detected by
//  watching whether the menu bar still reserves space on that screen, which
//  needs no extra permissions.
//

import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class FullscreenMediaDetector: ObservableObject {
    static let shared = FullscreenMediaDetector()

    /// Screen identifiers currently running a fullscreen app.
    @Published private(set) var fullscreenScreens: Set<String> = []

    private var timer: Timer?

    private init() {}

    func start() {
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        evaluate()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func evaluate() {
        var fullscreen: Set<String> = []
        for screen in NSScreen.screens {
            // In fullscreen the menu bar auto-hides, so the visible frame
            // reaches all the way to the top of the display.
            let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
            if menuBarHeight < 1 {
                fullscreen.insert(screen.displayIdentifier)
            }
        }

        if fullscreen != fullscreenScreens {
            fullscreenScreens = fullscreen
        }

        let option = Settings.shared.hideNotchOption
        let musicPlaying = MusicManager.shared.isPlaying
        for viewModel in NotchWindowManager.shared.viewModels {
            let isFullscreen = fullscreen.contains(viewModel.screenIdentifier)

            let shouldHide: Bool
            switch option {
            case .never:
                shouldHide = false
            case .always:
                shouldHide = isFullscreen
            case .nowPlayingOnly:
                shouldHide = isFullscreen && musicPlaying
            }

            if viewModel.hiddenForFullscreen != shouldHide {
                if shouldHide { viewModel.close() }
                viewModel.hiddenForFullscreen = shouldHide
            }
        }
    }
}
