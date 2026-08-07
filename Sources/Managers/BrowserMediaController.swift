//
//  BrowserMediaController.swift
//  FunNotch
//
//  Reads what is playing in a browser tab — YouTube, YouTube Music, Spotify's
//  web player, SoundCloud and friends.
//
//  macOS 15.4 took system-wide Now Playing away from unentitled apps, so the
//  only way left is to ask the browser directly. Where the browser will run
//  JavaScript for us we read `navigator.mediaSession`, which is exactly the
//  metadata these sites already publish; where it will not, we fall back to
//  parsing the tab title, which still gets the track name right.
//
//  Running JavaScript needs the user to switch it on once:
//    Chrome  → View → Developer → Allow JavaScript from Apple Events
//    Safari  → Develop → Allow JavaScript from Apple Events
//

import AppKit
import Foundation

private let fieldSeparator = "|~|"

private struct BrowserTarget {
    let bundleIdentifier: String
    let applicationName: String
    /// Chrome-family browsers use `execute javascript`, Safari uses `do JavaScript`.
    let isChromeFamily: Bool
}

/// A media site we know how to read, and how to drive it.
private struct MediaSite {
    let host: String
    let name: String
    /// Suffix the site appends to its tab titles, stripped for the fallback.
    let titleSuffix: String
    /// What the tab is called while nothing is playing. An open tab sitting on
    /// its own landing page is not a track, and reporting it as one is how the
    /// notch ended up announcing "YouTube Music" by YouTube Music.
    let idleTitles: [String]
    let nextSelectors: [String]
    let previousSelectors: [String]

    func isIdle(title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return true }
        if trimmed.caseInsensitiveCompare(name) == .orderedSame { return true }
        return idleTitles.contains { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
    }
}

final class BrowserMediaController: MediaController {
    let type: MediaControllerType = .browser
    var onUpdate: ((TrackInfo) -> Void)?

    private var timer: Timer?
    private var current = TrackInfo()
    private var lastArtworkKey = ""
    /// Last logged "which browser, which path", so the log records changes only.
    private var lastReadMode = ""
    /// Where the media tab lives, so commands go to the right place.
    private var activeTab: (browser: BrowserTarget, window: Int, tab: Int)?
    /// False once a scan finds no media tab, so the app can fall back.
    private var foundMediaTab = true
    private var isScanning = false
    /// When every window was last walked, so a cached tab cannot go stale.
    private var lastFullScan = Date.distantPast

    private static let browsers: [BrowserTarget] = [
        BrowserTarget(bundleIdentifier: "com.google.Chrome", applicationName: "Google Chrome", isChromeFamily: true),
        BrowserTarget(bundleIdentifier: "com.brave.Browser", applicationName: "Brave Browser", isChromeFamily: true),
        BrowserTarget(bundleIdentifier: "com.microsoft.edgemac", applicationName: "Microsoft Edge", isChromeFamily: true),
        BrowserTarget(bundleIdentifier: "company.thebrowser.Browser", applicationName: "Arc", isChromeFamily: true),
        BrowserTarget(bundleIdentifier: "com.apple.Safari", applicationName: "Safari", isChromeFamily: false),
    ]

    private static let sites: [MediaSite] = [
        MediaSite(
            host: "music.youtube.com",
            name: "YouTube Music",
            titleSuffix: " - YouTube Music",
            idleTitles: ["YouTube Music"],
            nextSelectors: [".next-button", "tp-yt-paper-icon-button.next-button"],
            previousSelectors: [".previous-button", "tp-yt-paper-icon-button.previous-button"]
        ),
        MediaSite(
            host: "youtube.com",
            name: "YouTube",
            titleSuffix: " - YouTube",
            idleTitles: ["YouTube"],
            nextSelectors: [".ytp-next-button"],
            previousSelectors: [".ytp-prev-button"]
        ),
        MediaSite(
            host: "open.spotify.com",
            name: "Spotify",
            titleSuffix: " | Spotify",
            idleTitles: [
                "Spotify",
                "Web Player: Music for everyone",
                "Spotify - Web Player: Music for everyone",
                "Spotify – Web Player: Music for everyone",
            ],
            nextSelectors: ["[data-testid=control-button-skip-forward]"],
            previousSelectors: ["[data-testid=control-button-skip-back]"]
        ),
        MediaSite(
            host: "soundcloud.com",
            name: "SoundCloud",
            titleSuffix: " | Free Listening on SoundCloud",
            idleTitles: [
                "SoundCloud",
                "Stream and listen to music online for free with SoundCloud",
            ],
            nextSelectors: [".skipControl__next"],
            previousSelectors: [".skipControl__previous"]
        ),
        MediaSite(
            host: "music.apple.com",
            name: "Apple Music",
            titleSuffix: " - Apple Music",
            idleTitles: ["Apple Music", "Apple Music - Web Player"],
            nextSelectors: ["button.next"],
            previousSelectors: ["button.previous"]
        ),
        MediaSite(
            host: "bandcamp.com",
            name: "Bandcamp",
            titleSuffix: "",
            idleTitles: ["Bandcamp"],
            nextSelectors: [".nextbutton"],
            previousSelectors: [".prevbutton"]
        ),
        MediaSite(
            host: "twitch.tv",
            name: "Twitch",
            titleSuffix: " - Twitch",
            idleTitles: ["Twitch"],
            nextSelectors: [],
            previousSelectors: []
        ),
        MediaSite(
            host: "vimeo.com",
            name: "Vimeo",
            titleSuffix: " on Vimeo",
            idleTitles: ["Vimeo"],
            nextSelectors: [],
            previousSelectors: []
        ),
    ]

    var isAvailable: Bool {
        guard Self.browsers.contains(where: { AppleScriptRunner.isRunning($0.bundleIdentifier) }) else {
            return false
        }
        return foundMediaTab
    }

    func start() {
        stop()
        refresh()
        scheduleNextPoll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// How long to wait before looking again.
    ///
    /// Every poll is Apple Events into another process, so an idle Mac should
    /// not pay what a playing one does. Nothing here changes how quickly a
    /// playing track updates.
    private var pollInterval: TimeInterval {
        if SystemActivityMonitor.isScreenIdle { return 30 }
        if current.isPlaying { return 2 }
        if activeTab != nil { return 5 }
        return 12
    }

    private func scheduleNextPoll() {
        timer?.invalidate()
        let timer = Timer(timeInterval: pollInterval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
                self?.scheduleNextPoll()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        guard !isScanning else { return }
        let running = Self.browsers.filter { AppleScriptRunner.isRunning($0.bundleIdentifier) }
        guard !running.isEmpty else {
            activeTab = nil
            clearIfNeeded()
            return
        }
        isScanning = true

        // A tab we already know about is re-read directly. Walking every window
        // of every browser to rediscover the same tab is the expensive part, so
        // it only happens when that tab stops being one we can read — or every
        // half minute, in case a better one has appeared since.
        if let active = activeTab,
           running.contains(where: { $0.bundleIdentifier == active.browser.bundleIdentifier }),
           Date().timeIntervalSince(lastFullScan) < 30 {
            let script = Self.singleTabScript(
                for: active.browser,
                window: active.window,
                tab: active.tab
            )
            AppleScriptRunner.shared.runForString(script) { [weak self] result in
                guard let self else { return }
                if let result, let hit = Self.parseTab(result) {
                    self.readTab(
                        browser: active.browser,
                        window: hit.window,
                        tab: hit.tab,
                        site: hit.site,
                        title: hit.title,
                        pageURL: hit.url
                    )
                    return
                }
                self.activeTab = nil
                self.scan(browsers: running, index: 0)
            }
            return
        }

        lastFullScan = Date()
        scan(browsers: running, index: 0)
    }

    /// Walks the running browsers until one of them yields a media tab.
    private func scan(browsers: [BrowserTarget], index: Int) {
        guard index < browsers.count else {
            isScanning = false
            foundMediaTab = false
            clearIfNeeded()
            return
        }

        let browser = browsers[index]
        AppleScriptRunner.shared.runForString(Self.tabListScript(for: browser)) { [weak self] result in
            guard let self else { return }
            guard let result, let hit = Self.firstMediaTab(in: result) else {
                self.scan(browsers: browsers, index: index + 1)
                return
            }

            self.activeTab = (browser, hit.window, hit.tab)
            self.foundMediaTab = true
            self.readTab(
                browser: browser,
                window: hit.window,
                tab: hit.tab,
                site: hit.site,
                title: hit.title,
                pageURL: hit.url
            )
        }
    }

    /// Asks the page itself what it is playing.
    private func readTab(
        browser: BrowserTarget,
        window: Int,
        tab: Int,
        site: MediaSite,
        title: String,
        pageURL: String
    ) {
        let script = Self.javaScriptScript(for: browser, window: window, tab: tab, body: Self.metadataJavaScript)

        AppleScriptRunner.shared.runForString(script) { [weak self] result in
            guard let self else { return }
            self.isScanning = false

            if let result, result.contains(fieldSeparator) {
                self.noteReadMode(scripted: true, browser: browser)
                self.apply(rawState: result, site: site, browser: browser, pageURL: pageURL)
            } else {
                // JavaScript is switched off; the tab title still names the track.
                self.noteReadMode(scripted: false, browser: browser)
                self.applyTitleOnly(title, site: site, browser: browser, pageURL: pageURL)
            }
        }
    }

    /// Says once, in the log, which of the two paths a browser is actually on.
    /// Falling back to the tab title is meant to be the rare case; when it was
    /// silently the only case for Chrome, nothing in the app said so.
    private func noteReadMode(scripted: Bool, browser: BrowserTarget) {
        BrowserReadModes.record(browser: browser.applicationName, scripted: scripted)
        let mode = scripted ? "page" : "title-only"
        guard lastReadMode != "\(browser.applicationName)/\(mode)" else { return }
        lastReadMode = "\(browser.applicationName)/\(mode)"
        DiagnosticLog.write("media", "reading \(browser.applicationName) via \(mode)")
    }

    private func apply(rawState: String, site: MediaSite, browser: BrowserTarget, pageURL: String) {
        let parts = rawState.components(separatedBy: fieldSeparator)
        guard parts.count >= 7 else { return }
        guard !site.isIdle(title: parts[0]) || !parts[1].isEmpty else {
            clearIfNeeded()
            return
        }

        var info = TrackInfo()
        info.title = parts[0].isEmpty ? site.name : parts[0]
        info.artist = parts[1].isEmpty ? site.name : parts[1]
        info.album = parts[2]
        info.duration = Double(parts[3]) ?? 0
        info.elapsed = Double(parts[4]) ?? 0
        info.isPlaying = parts[5] == "playing"
        info.bundleIdentifier = browser.bundleIdentifier
        info.timestamp = Date()
        info.artwork = current.artwork

        publish(info, artworkURL: parts[6], pageURL: pageURL)
    }

    /// Fallback when the browser will not run JavaScript for us.
    private func applyTitleOnly(
        _ rawTitle: String,
        site: MediaSite,
        browser: BrowserTarget,
        pageURL: String
    ) {
        let title = Self.cleanedTitle(rawTitle, for: site)

        // An idle tab is not a track. Reporting one produced the nonsense the
        // notch used to show: "YouTube Music" by "YouTube Music", with no time.
        guard !site.isIdle(title: title) else {
            clearIfNeeded()
            return
        }

        var info = TrackInfo()
        // "Track - Artist" is the common shape; keep the whole thing if not.
        let separators = [" - ", " • ", " · "]
        if let separator = separators.first(where: { title.contains($0) }) {
            let pieces = title.components(separatedBy: separator)
            info.title = pieces[0].trimmingCharacters(in: .whitespaces)
            info.artist = pieces.dropFirst().joined(separator: separator).trimmingCharacters(in: .whitespaces)
        } else {
            info.title = title
            info.artist = site.name
        }
        // Without JavaScript there is no way to know; assume it is playing,
        // since an idle tab rarely sits on a media page for long.
        info.isPlaying = true
        info.bundleIdentifier = browser.bundleIdentifier
        info.timestamp = Date()
        info.artwork = current.artwork

        publish(info, artworkURL: "", pageURL: pageURL)
    }

    private func publish(_ info: TrackInfo, artworkURL: String, pageURL: String) {
        var info = info
        let key = "\(info.title)|\(info.artist)"
        // YouTube publishes a thumbnail for every video at a predictable
        // address, so artwork works there even when the page itself is off
        // limits to us.
        let source = artworkURL.isEmpty ? (Self.thumbnailURL(forPageURL: pageURL) ?? "") : artworkURL

        if key != lastArtworkKey {
            lastArtworkKey = key
            info.artwork = nil
            current = info
            if !source.isEmpty {
                downloadArtwork(from: source, key: key)
            }
        } else {
            current = info
        }

        onUpdate?(current)
    }

    /// Strips the site's own branding off a tab title, leaving what the page is
    /// actually about.
    private static func cleanedTitle(_ rawTitle: String, for site: MediaSite) -> String {
        var title = rawTitle
        if !site.titleSuffix.isEmpty, title.hasSuffix(site.titleSuffix) {
            title.removeLast(site.titleSuffix.count)
        }
        // Sites often mark an unread count or playing state in the title.
        if title.hasPrefix("▶ ") { title.removeFirst(2) }
        return title.trimmingCharacters(in: .whitespaces)
    }

    /// Whether a tab is sitting on a media site without playing anything.
    nonisolated static func isIdleTab(url: String, title: String) -> Bool {
        guard let host = FocusManager.host(of: url),
              let site = sites.first(where: { host == $0.host || host.hasSuffix("." + $0.host) })
        else { return true }
        return site.isIdle(title: cleanedTitle(title, for: site))
    }

    /// `https://www.youtube.com/watch?v=ID` → the video's thumbnail.
    static func thumbnailURL(forPageURL urlString: String) -> String? {
        guard let host = FocusManager.host(of: urlString),
              host == "youtube.com" || host.hasSuffix(".youtube.com")
        else { return nil }
        guard let components = URLComponents(string: urlString),
              let identifier = components.queryItems?.first(where: { $0.name == "v" })?.value,
              !identifier.isEmpty
        else { return nil }
        return "https://img.youtube.com/vi/\(identifier)/mqdefault.jpg"
    }

    private func clearIfNeeded() {
        isScanning = false
        activeTab = nil
        guard !current.isEmpty || current.isPlaying else { return }
        current = TrackInfo()
        lastArtworkKey = ""
        onUpdate?(current)
    }

    private func downloadArtwork(from urlString: String, key: String) {
        guard let url = URL(string: urlString) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                guard key == self.lastArtworkKey else { return }
                self.current.artwork = image
                self.onUpdate?(self.current)
            }
        }.resume()
    }

    // MARK: - Transport

    private func runJavaScript(_ body: String) {
        guard let tab = activeTab else { return }
        AppleScriptRunner.shared.execute(
            Self.javaScriptScript(for: tab.browser, window: tab.window, tab: tab.tab, body: body)
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    static let playPauseJavaScript =
        "(function(){var v=document.querySelector('video')||document.querySelector('audio');if(!v)return '';v.paused?v.play():v.pause();return 'ok';})()"

    func togglePlayPause() {
        runJavaScript(Self.playPauseJavaScript)
    }

    func play() {
        runJavaScript("(function(){var v=document.querySelector('video')||document.querySelector('audio');if(v)v.play();return 'ok';})()")
    }

    func pause() {
        runJavaScript("(function(){var v=document.querySelector('video')||document.querySelector('audio');if(v)v.pause();return 'ok';})()")
    }

    func nextTrack() {
        runJavaScript(Self.clickJavaScript(selectors: Self.allNextSelectors))
    }

    func previousTrack() {
        runJavaScript(Self.clickJavaScript(selectors: Self.allPreviousSelectors))
    }

    func seek(to time: TimeInterval) {
        runJavaScript("(function(){var v=document.querySelector('video')||document.querySelector('audio');if(v)v.currentTime=\(Int(time));return 'ok';})()")
    }

    private static var allNextSelectors: [String] {
        sites.flatMap(\.nextSelectors)
    }

    private static var allPreviousSelectors: [String] {
        sites.flatMap(\.previousSelectors)
    }

    private static func clickJavaScript(selectors: [String]) -> String {
        let list = selectors.map { "'\($0)'" }.joined(separator: ",")
        return "(function(){var s=[\(list)];for(var i=0;i<s.length;i++){var e=document.querySelector(s[i]);if(e){e.click();return 'ok';}}return '';})()"
    }

    // MARK: - Scripts

    /// Returns `window|~|tab|~|url|~|title` per line.
    ///
    /// The URLs and titles are pulled a whole window at a time. Asking for them
    /// tab by tab looks equivalent and is not: every `URL of tab t of window w`
    /// is its own Apple Event round trip to the browser, so a couple of windows
    /// of ordinary tabs cost sixty-odd events every poll. Profiling put 29% of
    /// this app's script thread inside `UASRemoteSend` because of it. Two
    /// events per window instead, and the joining loop below runs on local
    /// lists without talking to the browser at all.
    private static func tabListScript(for browser: BrowserTarget) -> String {
        let titleProperty = browser.isChromeFamily ? "title" : "name"
        return """
        tell application "\(browser.applicationName)"
            set out to ""
            try
                repeat with w from 1 to count of windows
                    try
                        set us to URL of tabs of window w
                        set ns to \(titleProperty) of tabs of window w
                        repeat with i from 1 to count of us
                            try
                                set out to out & w & "\(fieldSeparator)" & i & "\(fieldSeparator)" & (item i of us) & "\(fieldSeparator)" & (item i of ns) & linefeed
                            end try
                        end repeat
                    end try
                end repeat
            end try
            return out
        end tell
        """
    }

    /// Reads one known tab, for when a media tab has already been found. Saves
    /// walking every window on every poll.
    private static func singleTabScript(for browser: BrowserTarget, window: Int, tab: Int) -> String {
        let titleProperty = browser.isChromeFamily ? "title" : "name"
        return """
        tell application "\(browser.applicationName)"
            try
                set u to (URL of tab \(tab) of window \(window)) as string
                set n to (\(titleProperty) of tab \(tab) of window \(window)) as string
                return \(window) & "\(fieldSeparator)" & \(tab) & "\(fieldSeparator)" & u & "\(fieldSeparator)" & n
            on error
                return ""
            end try
        end tell
        """
    }

    private static func javaScriptScript(
        for browser: BrowserTarget,
        window: Int,
        tab: Int,
        body: String
    ) -> String {
        // The JavaScript itself uses single quotes only, so it drops into an
        // AppleScript string without any escaping.
        //
        // The two families disagree about word order, and getting it wrong is
        // silent: Chrome's `execute` takes the tab as its direct object and
        // `javascript` as a label, so `execute javascript "…" in tab 1` does
        // not compile at all and every Chrome read fell back to the tab title.
        let command = browser.isChromeFamily
            ? "execute tab \(tab) of window \(window) javascript \"\(body)\""
            : "do JavaScript \"\(body)\" in tab \(tab) of window \(window)"
        return """
        tell application "\(browser.applicationName)"
            try
                return \(command)
            on error
                return ""
            end try
        end tell
        """
    }

    /// Reads what the page publishes through the Media Session API, which is
    /// the same metadata macOS itself would have shown.
    private static let metadataJavaScript = """
    (function(){var m=(navigator.mediaSession&&navigator.mediaSession.metadata)||null;\
    var v=document.querySelector('video')||document.querySelector('audio');\
    var t=m&&m.title?m.title:document.title;var a=m&&m.artist?m.artist:'';\
    var b=m&&m.album?m.album:'';var art='';\
    if(m&&m.artwork&&m.artwork.length){art=m.artwork[m.artwork.length-1].src;}\
    var d=v&&isFinite(v.duration)?v.duration:0;var p=v?v.currentTime:0;\
    var s=v?(v.paused?'paused':'playing'):'paused';\
    return [t,a,b,d,p,s,art].join('|~|');})()
    """

    private typealias TabHit = (window: Int, tab: Int, site: MediaSite, title: String, url: String)

    /// Parses one `window|~|tab|~|url|~|title` line, if it names a site we can
    /// read. Shared by the full scan and the single-tab re-read.
    private static func parseTab(_ line: String) -> TabHit? {
        let parts = line.components(separatedBy: fieldSeparator)
        guard parts.count >= 4,
              let window = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let tab = Int(parts[1].trimmingCharacters(in: .whitespaces)),
              let host = FocusManager.host(of: parts[2])
        else { return nil }

        guard let site = sites.first(where: { host == $0.host || host.hasSuffix("." + $0.host) })
        else { return nil }

        // A bare youtube.com front page is not "playing something".
        if site.host == "youtube.com", !parts[2].contains("/watch") { return nil }

        return (window, tab, site, parts[3], parts[2])
    }

    private static func firstMediaTab(in rawTabs: String) -> TabHit? {
        for line in rawTabs.components(separatedBy: "\n") where !line.isEmpty {
            if let hit = parseTab(line) { return hit }
        }
        return nil
    }

    /// Whether a URL is one this controller knows how to read.
    nonisolated static func isMediaURL(_ urlString: String) -> Bool {
        guard let host = FocusManager.host(of: urlString) else { return false }
        guard let site = sites.first(where: { host == $0.host || host.hasSuffix("." + $0.host) })
        else { return false }
        if site.host == "youtube.com", !urlString.contains("/watch") { return false }
        return true
    }

    static var installedBrowsers: [String] {
        browsers
            .filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleIdentifier) != nil }
            .map(\.applicationName)
    }

    /// Browsers whose page-access switch `BrowserScriptAccess` knows how to
    /// find, in the order it should try them.
    static var scriptableBrowsers: [(name: String, bundleIdentifier: String, isChromeFamily: Bool)] {
        browsers.map { ($0.applicationName, $0.bundleIdentifier, $0.isChromeFamily) }
    }

    /// The real scripts, exposed so the self test can compile them. Word order
    /// differs between the two browser families and a mistake is silent at
    /// runtime — the read just quietly falls back to the tab title, which is
    /// exactly how Chrome went unnoticed.
    static func diagnosticScripts(forBrowserNamed name: String) -> [(label: String, source: String)]? {
        guard let browser = browsers.first(where: { $0.applicationName == name }) else { return nil }
        return [
            ("tab list", tabListScript(for: browser)),
            ("metadata read", javaScriptScript(for: browser, window: 1, tab: 1, body: metadataJavaScript)),
            ("play/pause", javaScriptScript(for: browser, window: 1, tab: 1, body: playPauseJavaScript)),
        ]
    }
}
