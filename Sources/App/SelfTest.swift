//
//  SelfTest.swift
//  FunNotch
//
//  Development aid: `FunNotch --self-test` drives the real window manager,
//  managers and pointer routing, prints what it found, and exits non-zero if
//  anything essential is broken. Handy on a machine without Xcode.
//

import AppKit
import AVFoundation
import Foundation

@MainActor
enum SelfTest {
    static var isRequested: Bool {
        CommandLine.arguments.contains("--self-test")
    }

    /// `FunNotch --diagnostics` prints the same report the Diagnostics pane
    /// shows, so "is it broken or is it a permission?" can be answered from a
    /// terminal without opening a window.
    static var diagnosticsRequested: Bool {
        CommandLine.arguments.contains("--diagnostics")
    }

    static func printDiagnostics() {
        let report = DiagnosticsReport.shared
        report.refresh()
        print(report.plainText)
        // Returning here would only fall back into `NSApplication.run()`, and
        // an accessory app with no windows never comes back out of it.
        exit(0)
    }

    /// `--check-file <path>` reports exactly what the app can see of a file, so
    /// a silent rejection in the shelf can be traced to file access.
    static var fileToCheck: String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--check-file"), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }

    static func checkFile(_ path: String) {
        let url = URL(fileURLWithPath: path)
        print("=== file access check ===")
        print("path: \(path)")
        print("fileExists: \(FileManager.default.fileExists(atPath: path))")
        print("isReadableFile: \(FileManager.default.isReadableFile(atPath: path))")

        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
            print("size: \(values.fileSize ?? -1)")
            print("type: \(values.contentType?.identifier ?? "unknown")")
        } catch {
            print("resourceValues failed: \(error.localizedDescription)")
        }

        do {
            let handle = try FileHandle(forReadingFrom: url)
            let head = try handle.read(upToCount: 8)
            try handle.close()
            print("first bytes readable: \(head?.count ?? 0)")
        } catch {
            print("open for reading failed: \(error.localizedDescription)")
        }

        print("startAccessingSecurityScopedResource: \(url.startAccessingSecurityScopedResource())")

        do {
            _ = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            print("security-scoped bookmark: ok")
        } catch {
            print("security-scoped bookmark failed: \(error.localizedDescription)")
        }

        do {
            _ = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            print("plain bookmark: ok")
        } catch {
            print("plain bookmark failed: \(error.localizedDescription)")
        }

        let added = ShelfManager.shared.add(url: url)
        print("ShelfManager.add: \(added), shelf now holds \(ShelfManager.shared.items.count)")
        if added, let item = ShelfManager.shared.items.first(where: { $0.url == url }) {
            ShelfManager.shared.remove(id: item.id)
        }
        exit(0)
    }

    private static var failures: [String] = []
    /// Puts back any preference the test changed.
    private static var restoreSettings: (() -> Void)?

    private static func check(_ name: String, _ condition: Bool, detail: String = "") {
        let mark = condition ? "PASS" : "FAIL"
        let suffix = detail.isEmpty ? "" : "  (\(detail))"
        print("[\(mark)] \(name)\(suffix)")
        if !condition { failures.append(name) }
    }

    private static func info(_ name: String, _ value: String) {
        print("[INFO] \(name): \(value)")
    }

    static func run() {
        // Unbuffered, so a crash mid-test still shows how far it got.
        setvbuf(stdout, nil, _IONBF, 0)
        print("=== Fun Notch self test ===")
        info("launched by LaunchServices", "\(getppid() == 1)")

        // MARK: Geometry
        guard let screen = NSScreen.main else {
            print("[FAIL] no main screen")
            exit(1)
        }
        info("display", "\(screen.localizedName) \(Int(screen.frame.width))x\(Int(screen.frame.height))")
        info("has physical notch", "\(screen.hasPhysicalNotch)")

        let notch = measureClosedNotch(for: screen)
        info("measured notch", "\(Int(notch.width)) x \(Int(notch.height))")
        check("notch measurement is plausible", notch.width > 100 && notch.height > 10)

        // MARK: Managers
        MusicManager.shared.start()
        BatteryManager.shared.start()
        CalendarManager.shared.start()
        ScreenshotWatcher.shared.start()
        ClipboardManager.shared.start()

        // Touching IOBluetooth is a hard TCC kill unless the *responsible*
        // process carries the usage string. Launched through LaunchServices
        // that is this app; exec'd straight from a shell it is the shell, which
        // has no such key. The Info.plist checks below are what actually guard
        // against the missing-key regression.
        // Reparented to launchd means LaunchServices started us; a shell
        // parent means the shell is TCC-responsible and Bluetooth would abort.
        let launchedByLaunchServices = getppid() == 1
        if launchedByLaunchServices {
            BluetoothMonitor.shared.start()
        } else {
            info("Bluetooth", "skipped — run from a shell, so this process is not TCC-responsible")
        }

        NotchWindowManager.shared.start()

        let manager = NotchWindowManager.shared
        check("a notch panel was created", !manager.controllers.isEmpty)
        guard let controller = manager.controllers.first else {
            finish()
            return
        }

        let panel = controller.panel
        info("panel frame", "\(panel.frame)")
        check("panel is on screen", panel.isVisible)
        info("panel level", "\(panel.level.rawValue)")
        check("panel sits above the menu bar", panel.level.rawValue > NSWindow.Level.mainMenu.rawValue)
        check(
            "panel is not at an unusable level for drags",
            panel.level.rawValue < NSWindow.Level.screenSaver.rawValue
        )
        check(
            "panel is horizontally centred",
            abs(panel.frame.midX - screen.frame.midX) < 1,
            detail: "panel \(panel.frame.midX) vs screen \(screen.frame.midX)"
        )
        check(
            "panel is flush with the top of the display",
            abs(panel.frame.maxY - screen.frame.maxY) < 1
        )

        checkDragPlumbing(panel, notchHeight: notch.height, phase: "immediately")

        let requiredUsageKeys = [
            "NSBluetoothAlwaysUsageDescription": "Bluetooth",
            "NSCameraUsageDescription": "the camera mirror",
            "NSCalendarsUsageDescription": "the calendar",
            "NSRemindersUsageDescription": "reminders",
            "NSAppleEventsUsageDescription": "controlling Music, Spotify and browsers",
        ]
        for (key, purpose) in requiredUsageKeys.sorted(by: { $0.key < $1.key }) {
            let value = Bundle.main.object(forInfoDictionaryKey: key) as? String
            check(
                "Info.plist explains \(purpose)",
                !(value ?? "").isEmpty,
                detail: key
            )
        }

        // MARK: System state
        info("battery", "\(BatteryManager.shared.percentageText), plugged in: \(BatteryManager.shared.isPluggedIn)")

        // A Mac mini, Studio or Pro has no battery, and neither does a CI
        // runner. Asserting one exists made the suite fail on perfectly healthy
        // desktops. What actually matters is that the manager agrees with
        // itself: if it says there is a battery, it has to report a level.
        if BatteryManager.shared.hasBattery {
            check(
                "battery level is readable",
                (0 ... 1).contains(BatteryManager.shared.level),
                detail: BatteryManager.shared.percentageText
            )
        } else {
            info("battery", "none on this Mac — desktop or VM, battery checks skipped")
        }


        info("Now Playing deprecated on this OS", "\(MusicManager.shared.isNowPlayingDeprecated)")
        info("selected media backend", Settings.shared.mediaController.rawValue)
        info("active media backend", MusicManager.shared.activeControllerType?.rawValue ?? "none")
        info("Music running", "\(AppleScriptRunner.isRunning("com.apple.Music"))")
        info("Spotify running", "\(AppleScriptRunner.isRunning("com.spotify.client"))")

        for type in MediaControllerType.allCases where type != .nowPlaying {
            info("\(type.rawValue) installed", "\(ScriptedMediaController.isInstalled(type))")
        }
        for result in ScriptedMediaController.validateScripts() {
            check(
                "\(result.type.rawValue) AppleScript compiles",
                result.error == nil,
                detail: result.error ?? ""
            )
        }

        info("camera permission", "\(AVCaptureDevice.authorizationStatus(for: .video).rawValue)")

        // MARK: Shelf round trip
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("funnotch-selftest.txt")
        try? "shelf round trip".write(to: scratch, atomically: true, encoding: .utf8)
        let before = ShelfManager.shared.items.count
        let added = ShelfManager.shared.add(url: scratch)
        check("a file can be added to the shelf", added && ShelfManager.shared.items.count == before + 1)
        if let item = ShelfManager.shared.items.first(where: { $0.url == scratch }) {
            ShelfManager.shared.remove(id: item.id)
        }
        check("a file can be removed from the shelf", ShelfManager.shared.items.count == before)
        try? FileManager.default.removeItem(at: scratch)

        // MARK: Focus mode
        check(
            "blocklist matches the host itself",
            FocusManager.isBlocked(host: "youtube.com", by: ["youtube.com"])
        )
        check(
            "blocklist matches subdomains",
            FocusManager.isBlocked(host: "m.youtube.com", by: ["youtube.com"])
        )
        check(
            "blocklist ignores a www prefix in the entry",
            FocusManager.isBlocked(host: "reddit.com", by: ["www.reddit.com"])
        )
        check(
            "blocklist does not match unrelated hosts",
            !FocusManager.isBlocked(host: "notyoutube.com", by: ["youtube.com"])
        )
        check(
            "blocklist does not match a suffix that is not a subdomain",
            !FocusManager.isBlocked(host: "evilyoutube.com", by: ["youtube.com"])
        )
        check(
            "host is parsed out of a full URL",
            FocusManager.host(of: "https://www.YouTube.com/watch?v=1") == "youtube.com",
            detail: FocusManager.host(of: "https://www.YouTube.com/watch?v=1") ?? "nil"
        )
        info("browsers Focus can police", FocusManager.supportedInstalledBrowsers.joined(separator: ", "))

        let savedBlocking = Settings.shared.focusBlockWebsites
        Settings.shared.focusBlockWebsites = false
        FocusManager.shared.start(minutes: 25)
        check("a focus session starts", FocusManager.shared.isActive)
        check(
            "the session reports time remaining",
            FocusManager.shared.remaining > 24 * 60,
            detail: FocusManager.shared.remainingText
        )
        FocusManager.shared.extend(byMinutes: 5)
        check("a session can be extended", FocusManager.shared.remaining > 29 * 60)
        FocusManager.shared.stop()
        check("a focus session stops", !FocusManager.shared.isActive)
        Settings.shared.focusBlockWebsites = savedBlocking

        // MARK: Notes
        //
        // The whole point of the notes tab is that it lands as a real file on
        // the Desktop, so the round trip is worth asserting rather than
        // assuming: the folder can be missing, or Desktop access unGranted.
        let notes = NotesManager.shared
        info("notes file", notes.fileURL.path)
        let notesBefore = notes.text
        notes.text = "self test note \(UUID().uuidString)"
        notes.saveNow()
        if let error = notes.saveError {
            check("the note saved to the Desktop", false, detail: error)
        } else {
            let readBack = try? String(contentsOf: notes.fileURL, encoding: .utf8)
            check(
                "the note saved to the Desktop",
                readBack == notes.text,
                detail: notes.fileURL.deletingLastPathComponent().lastPathComponent + "/Notes.txt"
            )
        }
        // The backup exists precisely so the Desktop copy can be lost, so it is
        // worth asserting separately rather than trusting one write.
        let backup = try? String(contentsOf: notes.backupURL(for: notes.day), encoding: .utf8)
        check("the note is mirrored inside the app", backup == notes.text,
              detail: notes.backupFolder.lastPathComponent)

        notes.text = notesBefore
        notes.saveNow()

        // MARK: Screenshots, clipboard, Bluetooth
        let shots = ScreenshotWatcher.screenshotDirectory()
        info("screenshot folder", shots.path)
        check(
            "the screenshot folder exists",
            FileManager.default.fileExists(atPath: shots.path),
            detail: shots.path
        )

        let clipboard = ClipboardManager.shared
        let clipBefore = clipboard.entries.count
        let probe = NSPasteboard(name: .init("funnotch.selftest.clip"))
        probe.clearContents()
        probe.setString("self test clipboard entry", forType: .string)
        check("a pasteboard round trip preserves text", probe.string(forType: .string) == "self test clipboard entry")
        clipboard.injectPreviewEntries([(.text("self test entry"), "SelfTest")])
        check("clipboard history accepts entries", clipboard.entries.count == 1)
        if let entry = clipboard.entries.first {
            check("a clipboard entry previews as its text", entry.preview == "self test entry")
            clipboard.remove(entry)
        }
        check("a clipboard entry can be removed", clipboard.entries.isEmpty)
        info("clipboard entries before the test", "\(clipBefore)")

        info("paired Bluetooth devices", "\(BluetoothMonitor.shared.devices.count)")
        for device in BluetoothMonitor.shared.devices.prefix(4) {
            info("  \(device.name)", "\(device.isConnected ? "connected" : "idle") symbol=\(device.symbol)")
        }

        // MARK: Notch widgets
        let settings = Settings.shared
        let savedWidgets = (
            idle: settings.idleWidgetsEnabled,
            idleLeft: settings.idleLeftWidgets,
            idleRight: settings.idleRightWidgets
        )

        let widgetModel = controller.viewModel
        widgetModel.expandingView = SneakPeek()
        widgetModel.sneakPeek = SneakPeek()
        widgetModel.dragDetectorTargeting = false
        widgetModel.setPreviewMusicActivity(false)

        settings.idleWidgetsEnabled = false
        let bareWidth = widgetModel.contentSize.width
        check("with widgets off the notch is just the cutout", abs(bareWidth - notch.width) < 1)

        settings.idleWidgetsEnabled = true
        settings.idleLeftWidgets = [.clock]
        settings.idleRightWidgets = [.battery]
        check("widgets are shown when enabled", widgetModel.isShowingWidgets)
        check(
            "widgets widen the collapsed notch",
            widgetModel.contentSize.width > bareWidth,
            detail: "\(Int(bareWidth)) → \(Int(widgetModel.contentSize.width))"
        )

        settings.idleRightWidgets = []
        check(
            "a side set to Nothing takes no room",
            widgetModel.closedActivityInsets.trailing == 0
        )
        settings.idleRightWidgets = [.battery]

        // Who gets the row while music plays is the user's call.
        let savedMediaDisplay = settings.closedMediaDisplay
        let widgetsOnlyWidth = widgetModel.contentSize.width

        widgetModel.setPreviewMusicActivity(true)
        settings.closedMediaDisplay = .mediaOnly
        check("by default music takes the row from the widgets", !widgetModel.isShowingWidgets)
        check("and the artwork and spectrum are drawn", widgetModel.showsClosedMediaActivity)
        let mediaOnlyWidth = widgetModel.contentSize.width

        settings.closedMediaDisplay = .mediaAndWidgets
        check("sharing shows both", widgetModel.isShowingWidgets && widgetModel.showsClosedMediaActivity)
        check(
            "sharing needs more room than either alone",
            widgetModel.contentSize.width > max(mediaOnlyWidth, widgetsOnlyWidth),
            detail: "\(Int(mediaOnlyWidth)) / \(Int(widgetsOnlyWidth)) → \(Int(widgetModel.contentSize.width))"
        )

        settings.closedMediaDisplay = .widgetsOnly
        check("handing the row over hides the media", !widgetModel.showsClosedMediaActivity)
        check("and leaves the widgets on their own", widgetModel.isShowingWidgets)
        check(
            "which is the same width as when nothing is playing",
            abs(widgetModel.contentSize.width - widgetsOnlyWidth) < 1
        )

        // A focus countdown still wins outright, whatever the media setting.
        settings.closedMediaDisplay = .mediaAndWidgets
        widgetModel.setPreviewFocusActivity(true)
        check("a focus countdown still takes the row", !widgetModel.isShowingWidgets)
        widgetModel.setPreviewFocusActivity(false)

        settings.closedMediaDisplay = savedMediaDisplay
        widgetModel.setPreviewMusicActivity(false)

        // Measured widths must beat the declared estimate, or locales with
        // longer clock formats would clip.
        widgetModel.updateMeasuredWidgetWidths([.leading: 240, .trailing: 90])
        check(
            "a measured width overrides the declared one",
            widgetModel.closedActivityInsets.leading == 240,
            detail: "\(widgetModel.closedActivityInsets.leading)"
        )
        widgetModel.setPreviewMusicActivity(false)
        widgetModel.updateMeasuredWidgetWidths([:])
        settings.idleWidgetsEnabled = savedWidgets.idle
        settings.idleLeftWidgets = savedWidgets.idleLeft
        settings.idleRightWidgets = savedWidgets.idleRight

        // MARK: New widgets and their click targets
        info("CPU / memory / disk", "\(SystemStatsManager.shared.cpuText) / \(SystemStatsManager.shared.memoryText) / \(SystemStatsManager.shared.diskFreeText)")
        SystemStatsManager.shared.refresh()
        check(
            "system stats read back in range",
            SystemStatsManager.shared.memoryUsage > 0 && SystemStatsManager.shared.memoryUsage <= 1,
            detail: SystemStatsManager.shared.memoryText
        )
        check("disk free space is known", SystemStatsManager.shared.diskFreeBytes > 0)
        info("moon phase", "\(MoonPhase.name()) \(Int(MoonPhase.fraction() * 100))%")
        check(
            "moon phase stays in range",
            (0 ... 1).contains(MoonPhase.fraction())
        )
        check(
            "every widget declares a width",
            NotchWidget.allCases.allSatisfy { $0.estimatedWidth > 0 }
        )
        info("location permission", "\(WeatherManager.shared.authorization.rawValue)")

        // MARK: Meeting links
        check(
            "a Zoom link is found in event notes",
            MeetingLinkFinder.find(in: ["Dial in at https://us02web.zoom.us/j/123456789 please"])?.host == "us02web.zoom.us"
        )
        check(
            "a Meet link is found in the location field",
            MeetingLinkFinder.find(in: [nil, "https://meet.google.com/abc-defg-hij"])?.host == "meet.google.com"
        )
        check(
            "a Teams link is recognised",
            MeetingLinkFinder.find(in: ["https://teams.microsoft.com/l/meetup-join/x"]) != nil
        )
        check(
            "an ordinary link is not mistaken for a meeting",
            MeetingLinkFinder.find(in: ["See https://example.com/agenda"]) == nil
        )

        // MARK: Browser media
        info("browsers Fun Notch can read", BrowserMediaController.installedBrowsers.joined(separator: ", "))
        check(
            "a YouTube watch page counts as media",
            BrowserMediaController.isMediaURL("https://www.youtube.com/watch?v=abc")
        )
        check(
            "the YouTube front page does not",
            !BrowserMediaController.isMediaURL("https://www.youtube.com/")
        )
        check(
            "YouTube Music counts as media",
            BrowserMediaController.isMediaURL("https://music.youtube.com/watch?v=abc")
        )
        check(
            "the Spotify web player counts as media",
            BrowserMediaController.isMediaURL("https://open.spotify.com/track/xyz")
        )
        check(
            "an unrelated site does not",
            !BrowserMediaController.isMediaURL("https://example.com/watch")
        )
        check(
            "Browser is offered as a media backend",
            MediaControllerType.allCases.contains(.browser)
        )
        check(
            "a YouTube Music tab with nothing playing is not a track",
            BrowserMediaController.isIdleTab(
                url: "https://music.youtube.com/",
                title: "YouTube Music"
            )
        )
        check(
            "an idle Spotify web player is not a track",
            BrowserMediaController.isIdleTab(
                url: "https://open.spotify.com/",
                title: "Spotify - Web Player: Music for everyone"
            )
        )
        check(
            "a playing tab is still a track",
            !BrowserMediaController.isIdleTab(
                url: "https://music.youtube.com/watch?v=abc",
                title: "Bohemian Rhapsody - Queen - YouTube Music"
            )
        )
        check(
            "artwork is derived from the YouTube video id",
            BrowserMediaController.thumbnailURL(
                forPageURL: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42"
            ) == "https://img.youtube.com/vi/dQw4w9WgXcQ/mqdefault.jpg"
        )
        check(
            "YouTube Music artwork uses the same thumbnail",
            BrowserMediaController.thumbnailURL(
                forPageURL: "https://music.youtube.com/watch?v=abc123"
            ) == "https://img.youtube.com/vi/abc123/mqdefault.jpg"
        )
        check(
            "no thumbnail is invented for other sites",
            BrowserMediaController.thumbnailURL(forPageURL: "https://open.spotify.com/track/xyz") == nil
        )

        // MARK: HUD, sharing and the menu bar
        info("display brightness control", DisplayBrightness.isAvailable ? "available" : "not exposed")
        info("keyboard backlight control", KeyboardBacklight.isAvailable ? "available" : "not exposed")
        info("system volume", SystemAudio.volume.map { "\(Int($0 * 100))%" } ?? "unreadable")
        check("volume is readable through CoreAudio", SystemAudio.volume != nil)
        check("AirDrop is offered by macOS", ShelfManager.canAirDrop)

        // The HUD ships switched on, so "is it off by default" is no longer the
        // property worth asserting. This is: it must never intercept a key
        // before Accessibility has been granted, whatever the setting says.
        check(
            "the HUD never intercepts without Accessibility",
            AXIsProcessTrusted() || !HUDManager.shared.isIntercepting
        )
        check(
            "every HUD category can be switched independently",
            [\Settings.hudShowsVolume, \Settings.hudShowsBrightness, \Settings.hudShowsBacklight]
                .allSatisfy { Settings.shared[keyPath: $0] }
        )
        // Driving the strip must not need the hardware.
        HUDManager.shared.injectPreview(.volume, value: 0.42)
        check("a HUD reading reaches the notch", HUDManager.shared.showing == .volume)
        check("and carries its value", abs(HUDManager.shared.value - 0.42) < 0.001)
        HUDManager.shared.clearPreview()
        check("and clears again", HUDManager.shared.showing == nil)

        check(
            "the menu bar can be given a readout",
            MenuBarReadout.allCases.count >= 5 && MenuBarGlyph.allCases.contains(.none)
        )

        // MARK: Sample agenda
        //
        // The dangerous failure here is not a missing placeholder, it is a
        // placeholder that displaces or impersonates something real.
        let sampleDay = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 12))!
        let samples = CalendarManager.sampleItems(for: sampleDay, includeReminders: true)
        check("the sample agenda has something in it", !samples.isEmpty, detail: "\(samples.count) rows")
        check("every sample row is flagged as one", samples.allSatisfy(\.isSample))
        check(
            "sample times land on the day being viewed",
            samples.compactMap(\.start).allSatisfy { Calendar.current.isDate($0, inSameDayAs: sampleDay) }
        )
        check(
            "sample reminders follow the reminders setting",
            CalendarManager.sampleItems(for: sampleDay, includeReminders: false)
                .allSatisfy { !$0.isReminder }
        )

        let realItem = AgendaItem(
            id: "real", title: "Standup", start: sampleDay, end: nil, isAllDay: false,
            calendarColor: .blue, calendarTitle: "Work", kind: .event,
            location: nil, externalIdentifier: nil, meetingURL: nil
        )
        check(
            "a day with a real event is left alone",
            CalendarManager.fillingIfEmpty([realItem], enabled: true, day: sampleDay, includeReminders: true)
                == [realItem]
        )
        check(
            "an empty day is only filled when the setting is on",
            CalendarManager.fillingIfEmpty([], enabled: false, day: sampleDay, includeReminders: true).isEmpty
        )
        check(
            "samples never become your next event",
            CalendarManager.next(in: samples, now: sampleDay) == nil
        )
        check(
            "but a real event still does",
            CalendarManager.next(in: samples + [realItem], now: sampleDay)?.id == "real"
        )
        // Toggling the setting has to rebuild the agenda. Without this the
        // switch appears to do nothing until the next minute tick.
        check(
            "toggling the setting rebuilds the agenda",
            CalendarManager.reloadTriggeringKeys.contains("showSampleAgenda")
        )

        // Sharing falls back to the whole shelf when nothing is ticked.
        ShelfManager.shared.selection.removeAll()
        check(
            "sharing with no selection means the whole shelf",
            ShelfManager.shared.shareURLs.count == ShelfManager.shared.items.count
        )

        // MARK: Diagnostics
        // Every row queries a different permission API, so building the report
        // at all is the check that none of them trap on a fresh machine.
        let report = DiagnosticsReport.shared
        report.refresh()
        check("the diagnostics report has every section", report.sections.count == 5)
        // The bug that hid for the whole project was an AppleScript error that
        // nothing recorded, so check the recording works.
        ScriptErrors.record(
            source: "tell application \"Google Chrome\"\nreturn 1\nend tell",
            message: "test failure"
        )
        check(
            "a script failure is attributed to the app that refused it",
            ScriptErrors.current.contains { $0.application == "Google Chrome" && $0.message == "test failure" }
        )
        ScriptErrors.clear(application: "Google Chrome")
        check(
            "and cleared once it works again",
            !ScriptErrors.current.contains { $0.application == "Google Chrome" }
        )
        check(
            "an Automation refusal says where to fix it",
            DiagnosticsReport.shared.sections.count == 5
        )
        check("every row says something", report.sections.allSatisfy { section in
            !section.rows.isEmpty && section.rows.allSatisfy { !$0.verdict.text.isEmpty }
        })
        check(
            "the report can be copied as text",
            report.plainText.contains("Fun Notch diagnostics") && report.plainText.count > 200
        )
        info("diagnostics rows", "\(report.sections.reduce(0) { $0 + $1.rows.count })")

        // MARK: Turning on page access
        check(
            "the page-access helper knows the browsers",
            BrowserMediaController.scriptableBrowsers.contains { $0.name == "Google Chrome" }
                && BrowserMediaController.scriptableBrowsers.contains { $0.name == "Safari" }
        )
        // Compile every script the browser backend actually sends. Chrome and
        // Safari disagree about word order — Chrome takes the tab as the direct
        // object, Safari locates it with `in` — and getting it wrong fails
        // silently: the read just falls back to the tab title, which looks like
        // a missing permission rather than a broken script. Only installed
        // browsers can be compiled against; the rest have no dictionary here.
        func compiles(_ source: String) -> Bool {
            var errorInfo: NSDictionary?
            _ = NSAppleScript(source: source)?.compileAndReturnError(&errorInfo)
            return errorInfo == nil
        }

        let installed = BrowserMediaController.installedBrowsers
        for browser in BrowserMediaController.scriptableBrowsers where installed.contains(browser.name) {
            check(
                "the \(browser.name) page-access probe compiles",
                compiles(
                    BrowserScriptAccess.probeScript(
                        browser: browser.name,
                        isChromeFamily: browser.isChromeFamily
                    )
                )
            )
            for script in BrowserMediaController.diagnosticScripts(forBrowserNamed: browser.name) ?? [] {
                check("the \(browser.name) \(script.label) script compiles", compiles(script.source))
            }
        }
        let outcomes: [BrowserScriptAccess.Outcome] = [
            .alreadyOn("Safari"), .turnedOn("Safari"), .needsAccessibility,
            .needsSafariDevelopMenu, .noBrowser, .noWindows("Safari"), .failed("x"),
        ]
        check("every page-access outcome explains itself", outcomes.allSatisfy { !$0.message.isEmpty })
        check(
            "only success reads as success",
            outcomes.filter(\.isGood).count == 2
        )
        info(
            "accessibility (needed for the page-access button)",
            BrowserScriptAccess.shared.isTrustedForAccessibility ? "granted" : "not granted"
        )
        let hintDefault = Settings.shared.showPageAccessHint
        Settings.shared.showPageAccessHint = false
        check("the page-access hint can be switched off", !Settings.shared.showPageAccessHint)
        Settings.shared.showPageAccessHint = hintDefault

        // MARK: Themes
        check("built-in themes are available", NotchTheme.builtIns.count >= 5)
        let roundTrip = NotchTheme.decode(NotchTheme.encode(.red))
        check(
            "theme colours survive a round trip",
            NSColor(roundTrip).isApproximately(NSColor(.red), tolerance: 0.01)
        )

        // MARK: Game
        // Exercising the game writes a high score, so put the real one back
        // afterwards — an earlier version of this test left 104 on the board
        // before anyone had played a round.
        let savedHighScore = Settings.shared.gameHighScore
        let game = BreakoutGame.shared
        let boardSize = CGSize(width: 640, height: 140)
        var clock = Date()

        game.advance(to: clock, size: boardSize)
        check("the board fills with bricks", game.bricks.count == BreakoutGame.columns * 4)
        check("the ball waits on the paddle", game.balls.count == 1)
        check("a fresh run has three lives", game.lives == 3)

        // The paddle is driven by the global pointer, mapped in through the
        // board's on-screen rectangle. Nothing about this needs the keyboard,
        // which is the point: the notch panel never becomes key.
        game.boardScreenFrame = CGRect(x: 100, y: 900, width: 640, height: 140)
        game.pointerMoved(to: CGPoint(x: 580, y: 950))
        clock += 1.0 / 60
        game.advance(to: clock, size: boardSize)
        check("the paddle follows the pointer", abs(game.paddleCenterX - 480) < 1)

        game.pointerMoved(to: CGPoint(x: 10_000, y: 950))
        clock += 1.0 / 60
        game.advance(to: clock, size: boardSize)
        check(
            "the paddle stays on the board",
            game.paddleCenterX <= boardSize.width - game.paddleWidth / 2 + 0.01
        )

        // Five seconds of play, with the paddle parked under wherever the ball
        // happens to be, so the rally keeps going.
        for _ in 0 ..< 300 {
            if let ball = game.balls.first {
                game.pointerMoved(to: CGPoint(x: 100 + ball.position.x, y: 950))
            }
            clock += 1.0 / 60
            game.advance(to: clock, size: boardSize)
        }
        check("bricks break when the ball reaches them", game.bricks.count < BreakoutGame.columns * 4)
        check("play scores", game.score > 0)
        check(
            "every ball stays inside the board",
            game.balls.allSatisfy { $0.position.x >= 0 && $0.position.x <= boardSize.width }
        )
        check("the high score follows the score", game.highScore >= game.score)

        game.primaryAction()
        check("clicking a live game pauses it", game.isPaused)
        game.primaryAction()
        check("clicking again resumes", !game.isPaused)

        Settings.shared.gameHighScore = savedHighScore

        // MARK: Drag-to-notch drop zone
        // Clear anything the focus checks left on screen so the sizes compare cleanly.
        controller.viewModel.expandingView = SneakPeek()
        controller.viewModel.sneakPeek = SneakPeek()
        let idleWidth = controller.viewModel.contentSize.width
        controller.viewModel.dragDetectorTargeting = true
        let dragSize = controller.viewModel.contentSize
        check(
            "a live drag widens the notch into a drop zone",
            dragSize.width > idleWidth,
            detail: "\(Int(idleWidth)) → \(Int(dragSize.width))"
        )
        check(
            "the drop zone is taller than the collapsed notch",
            dragSize.height > notch.height
        )
        check(
            "the drop target grows with it",
            controller.hoverRect.width >= dragSize.width - 1
        )
        controller.viewModel.dragDetectorTargeting = false
        check(
            "the notch shrinks back when the drag ends",
            abs(controller.viewModel.contentSize.width - idleWidth) < 1
        )
        check(
            "the pasteboard filter ignores empty content",
            !MouseTracker.pasteboardHasAcceptableContent(NSPasteboard(name: .init("funnotch.selftest.empty")))
        )

        // MARK: Pointer routing → open / close
        let viewModel = controller.viewModel
        let hoverRect = controller.hoverRect
        info("hover rect", "\(hoverRect)")
        check("hover rect covers the notch", hoverRect.width >= notch.width - 1)

        // Remember the user's real preferences; the test overrides a few.
        let saved = (
            hover: Settings.shared.openNotchOnHover,
            delay: Settings.shared.minimumHoverDuration
        )
        restoreSettings = {
            Settings.shared.openNotchOnHover = saved.hover
            Settings.shared.minimumHoverDuration = saved.delay
        }

        Settings.shared.openNotchOnHover = true
        Settings.shared.minimumHoverDuration = 0.05

        let inside = CGPoint(x: hoverRect.midX, y: hoverRect.midY)
        let outside = CGPoint(x: screen.frame.midX, y: screen.frame.midY)

        // Detach the real monitors first. They stay live during the test, and a
        // physical pointer sitting outside the notch would report "not hovering"
        // in between the synthetic move and the hover delay firing, cancelling
        // the very thing being measured. The callback itself is untouched, so
        // this still exercises the real routing.
        MouseTracker.shared.stop()

        // Drive the exact callback the global mouse monitor uses.
        MouseTracker.shared.onMove?(inside)
        check("pointer inside the notch registers as hovering", viewModel.isHovering)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            check("hovering opens the notch", viewModel.notchState == .open)
            let openRect = controller.hoverRect
            check(
                "the open notch grows to its full size",
                abs(openRect.width - openNotchSize.width) < 1,
                detail: "\(openRect.width)"
            )

            MouseTracker.shared.onMove?(outside)
            check("pointer leaving clears hover", !viewModel.isHovering)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                check("leaving closes the notch", viewModel.notchState == .closed)

                // MARK: HUD path

                // Give the media backend time to answer before reporting.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    checkDragPlumbing(panel, notchHeight: notch.height, phase: "settled")
                    checkDropPath(controller)
                    let track = MusicManager.shared.track
                    if track.isEmpty {
                        info("now playing", "nothing reported (no player running, or automation access not yet granted)")
                    } else {
                        info("now playing", "\(track.title) — \(track.artist) [\(track.isPlaying ? "playing" : "paused")]")
                        info("track duration", "\(Int(track.duration))s")
                        info("artwork", track.artwork == nil ? "none" : "loaded")
                    }
                    finish()
                }
            }
        }
    }


    /// Walks the panel looking for a view that accepts dragged types, and
    /// checks that hit testing can actually reach SwiftUI's content.
    private static func checkDragPlumbing(_ panel: NSWindow, notchHeight: CGFloat, phase: String) {
        guard let contentView = panel.contentView else { return }

        var registered: [(String, [String])] = []
        func walk(_ view: NSView) {
            let types = view.registeredDraggedTypes.map(\.rawValue)
            if !types.isEmpty { registered.append(("\(type(of: view))", types)) }
            view.subviews.forEach(walk)
        }
        walk(contentView)

        info("[\(phase)] views registered for drags", "\(registered.count)")
        for entry in registered {
            info("[\(phase)]   \(entry.0)", entry.1.prefix(6).joined(separator: ", "))
        }

        let notchCentre = NSPoint(x: windowSize.width / 2, y: windowSize.height - notchHeight / 2)
        let hit = contentView.hitTest(notchCentre)
        info("[\(phase)] hit test at the notch centre", hit.map { "\(type(of: $0))" } ?? "nil")

        if phase == "settled" {
            check(
                "the content view accepts file drags",
                contentView.registeredDraggedTypes.contains(.fileURL)
            )
            check("hit testing reaches the notch", hit != nil)
        }
    }

    /// Drives the real drop path with a pasteboard shaped like a Finder drag.
    private static func checkDropPath(_ controller: NotchWindowController) {
        guard let contentView = controller.panel.contentView as? PassthroughContentView else {
            check("the content view is the drag destination", false)
            return
        }
        check("the content view is the drag destination", true)

        // While a drag is in flight the catch area covers the top of the window,
        // so the drop does not have to be aimed at the collapsed notch.
        controller.viewModel.dragDetectorTargeting = false
        let idleBelow = contentView.hitTest(NSPoint(x: windowSize.width / 2, y: windowSize.height - 90))
        controller.viewModel.dragDetectorTargeting = true
        let dragBelow = contentView.hitTest(NSPoint(x: windowSize.width / 2, y: windowSize.height - 90))
        check("idle, the notch ignores points well below it", idleBelow == nil)
        check("mid-drag, the catch area extends below the notch", dragBelow != nil)

        let farLeft = contentView.hitTest(NSPoint(x: 20, y: windowSize.height - 40))
        check("mid-drag, the catch area spans the window width", farLeft != nil)

        // The shadow paints outside the notch's silhouette, onto whatever
        // window happens to be under it, so it is opt-in. Check what a fresh
        // install gets, not what this Mac has stored — a deliberate "yes" from
        // the user must not read as a failure.
        let store = UserDefaults.standard
        let storedShadow = store.object(forKey: "enableShadow")
        store.removeObject(forKey: "enableShadow")
        check("out of the box the drop shadow is off", !Settings.shared.enableShadow)
        store.set(storedShadow, forKey: "enableShadow")
        check(
            "the window leaves room for the shadow on every side",
            windowSize.width - openNotchSize.width == shadowPadding * 2
                && windowSize.height - openNotchSize.height == shadowPadding,
            detail: "\(Int(windowSize.width))×\(Int(windowSize.height)) around \(Int(openNotchSize.width))×\(Int(openNotchSize.height))"
        )
        controller.viewModel.dragDetectorTargeting = false
        controller.viewModel.previewOpen()
        let openRect = NotchWindowController.liveRect(for: controller.viewModel)
        check(
            "the open notch stays centred in it",
            abs(openRect.midX - windowSize.width / 2) < 0.01,
            detail: "\(openRect.midX) vs \(windowSize.width / 2)"
        )
        check(
            "with the shadow margin clear on both sides",
            openRect.minX >= shadowPadding - 0.01 && openRect.maxX <= windowSize.width - shadowPadding + 0.01,
            detail: "\(Int(openRect.minX)) … \(Int(windowSize.width - openRect.maxX))"
        )
        controller.viewModel.close()
        controller.viewModel.dragDetectorTargeting = false

        // A file URL on a pasteboard is exactly what Finder hands over.
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("funnotch-drop-test.txt")
        try? "dropped".write(to: file, atomically: true, encoding: .utf8)

        let pasteboard = NSPasteboard(name: .init("funnotch.selftest.drop"))
        pasteboard.clearContents()
        pasteboard.writeObjects([file as NSURL])

        let before = ShelfManager.shared.items.count
        let accepted = controller.dragDidDrop(pasteboard)
        check("a dropped file is accepted", accepted)
        check(
            "the dropped file lands on the shelf",
            ShelfManager.shared.items.count == before + 1,
            detail: "\(before) → \(ShelfManager.shared.items.count)"
        )
        check("the drop switches to the shelf tab", controller.viewModel.currentTab == .shelf)

        if let item = ShelfManager.shared.items.first(where: { $0.url == file }) {
            check("the shelf kept the right file", item.name == "funnotch-drop-test.txt")
            ShelfManager.shared.remove(id: item.id)
        } else {
            check("the shelf kept the right file", false)
        }
        try? FileManager.default.removeItem(at: file)

        // Text drags should become a file too, so they can be dragged back out.
        let textBoard = NSPasteboard(name: .init("funnotch.selftest.text"))
        textBoard.clearContents()
        textBoard.setString("hello from a drag", forType: .string)
        let textBefore = ShelfManager.shared.items.count
        check("dropped text is accepted", controller.dragDidDrop(textBoard))
        check("dropped text becomes a shelf file", ShelfManager.shared.items.count == textBefore + 1)
        if let item = ShelfManager.shared.items.first {
            ShelfManager.shared.remove(id: item.id)
        }

        controller.viewModel.currentTab = .home
        controller.viewModel.pinnedOpen = false
    }

    private static func finish() {
        restoreSettings?()
        print("=== \(failures.isEmpty ? "all checks passed" : "\(failures.count) check(s) failed") ===")
        for failure in failures {
            print("  - \(failure)")
        }
        exit(failures.isEmpty ? 0 : 1)
    }
}
