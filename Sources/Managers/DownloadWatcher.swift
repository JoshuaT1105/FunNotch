//
//  DownloadWatcher.swift
//  FunNotch
//
//  Announces finished downloads in the notch. Browsers write to a temporary
//  name while a download is in flight (`.download`, `.crdownload`, `.part`),
//  so "finished" means the real file has appeared and stopped growing.
//

import AppKit
import Combine
import Foundation

@MainActor
final class DownloadWatcher: ObservableObject {
    static let shared = DownloadWatcher()

    @Published private(set) var lastDownload: URL?

    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var seen: Set<String> = []
    private var startedAt = Date()
    private var cancellables = Set<AnyCancellable>()
    private var rescanWork: DispatchWorkItem?

    /// Extensions that mean "still downloading".
    private static let inProgressExtensions: Set<String> = [
        "download", "crdownload", "part", "partial", "opdownload", "tmp",
    ]

    private init() {}

    func start() {
        NotificationCenter.default.publisher(for: .settingsChanged)
            .compactMap { $0.object as? String }
            .filter { $0 == "catchDownloads" }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.restart() }
            .store(in: &cancellables)

        restart()
    }

    func restart() {
        stop()
        guard Settings.shared.catchDownloads else { return }

        let directory = FileManager.default.standardDirectory(.downloadsDirectory, fallback: "Downloads")
        seen = Set((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
        startedAt = Date()

        descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else {
            DiagnosticLog.write("downloads", "could not watch \(directory.path)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleScan(in: directory) }
        }
        source.setCancelHandler { [weak self] in
            guard let self, self.descriptor >= 0 else { return }
            close(self.descriptor)
            self.descriptor = -1
        }
        source.resume()
        self.source = source

        DiagnosticLog.write("downloads", "watching \(directory.path)")
    }

    func stop() {
        rescanWork?.cancel()
        rescanWork = nil
        source?.cancel()
        source = nil
    }

    private func scheduleScan(in directory: URL) {
        rescanWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scan(in: directory) }
        rescanWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func scan(in directory: URL) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let fresh = names.filter { !seen.contains($0) }
        seen.formUnion(names)

        for name in fresh {
            guard !name.hasPrefix(".") else { continue }
            let url = directory.appendingPathComponent(name)

            // Skip the placeholder files browsers use while downloading; the
            // finished file lands under its real name a moment later.
            guard !Self.inProgressExtensions.contains(url.pathExtension.lowercased()) else { continue }

            let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
            guard let created, created >= startedAt.addingTimeInterval(-2) else { continue }

            waitUntilStable(url)
        }
    }

    private func waitUntilStable(_ url: URL, attempt: Int = 0) {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            let now = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            if now == size {
                self.announce(url)
            } else if attempt < 600 {
                self.waitUntilStable(url, attempt: attempt + 1)
            }
        }
    }

    private func announce(_ url: URL) {
        lastDownload = url
        DiagnosticLog.write("downloads", "finished \(url.lastPathComponent)")

        if Settings.shared.downloadsToShelf {
            ShelfManager.shared.add(url: url)
        }

        NotchWindowManager.shared.broadcast { viewModel in
            viewModel.showExpandingView(
                type: .download,
                value: 1,
                icon: "arrow.down.circle.fill",
                duration: 3.0
            )
        }
    }
}
