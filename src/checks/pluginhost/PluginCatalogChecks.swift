import Foundation

@testable import PorydawPluginHost

private let pluginCatalogID = "no-row/pluginhost/catalog"

private enum CatalogCheckError: Error {
    case missingExecutable
}

@MainActor
private final class CatalogCheckFixture {
    let root: URL
    let modules: URL
    let cache: URL
    let scanner: URL
    let fixtures: URL
    var launches: [String] = []
    var running: Set<Int32> = []
    var peakChildren = 0

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("plugin-catalog-\(UUID().uuidString)")
        modules = root.appendingPathComponent("modules")
        cache = root.appendingPathComponent("cache")
        guard let executableURL = Bundle.main.executableURL else { throw CatalogCheckError.missingExecutable }
        let executable = executableURL.deletingLastPathComponent()
        #if os(Windows)
            scanner = executable.appendingPathComponent("porydaw-vst3-host.exe")
        #else
            scanner = executable.appendingPathComponent("porydaw-vst3-host")
        #endif
        fixtures = executable.appendingPathComponent("vstfixtures")
        try FileManager.default.createDirectory(at: modules, withIntermediateDirectories: true)
    }

    func copy(_ name: String, into folder: String = "") throws -> URL {
        let directory = folder.isEmpty ? modules : modules.appendingPathComponent(folder)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("\(name).vst3").standardizedFileURL
        try FileManager.default.copyItem(at: fixtures.appendingPathComponent("\(name).vst3"), to: destination)
        return destination
    }

    func catalog(timeout: Duration = .seconds(1)) -> PluginCatalog {
        PluginCatalog(
            cacheDirectory: cache, scannerURL: scanner, standardRoots: [modules.path], timeout: timeout,
            childLaunched: { [weak self] (path: String, pid: Int32) in
                guard let self else { return }
                self.launches.append(path)
                self.running.insert(pid)
                self.peakChildren = max(self.peakChildren, self.running.count)
            },
            childTerminated: { [weak self] (_: String, pid: Int32) in self?.running.remove(pid) })
    }

    func cleanup(_ check: CheckReport.Scoped) {
        do { try FileManager.default.removeItem(at: root) } catch { check.fail("catalog fixture cleanup: \(error)") }
    }
}

@MainActor
private func checkCatalogDiscovery(_ report: CheckReport) async {
    let check = report.scoped(cppID: pluginCatalogID)
    do {
        let fixture = try CatalogCheckFixture()
        defer { fixture.cleanup(check) }
        let module = try fixture.copy("porydawtestgen")
        let catalog = fixture.catalog(timeout: .seconds(10))
        var scanningStates: [Bool] = []
        var progressive = false
        catalog.onChanged = { () -> Void in
            scanningStates.append(catalog.isScanning)
            if catalog.isScanning, catalog.entries.count == 4 { progressive = true }
        }
        defer { catalog.onChanged = nil }
        let moduleAlias = module.deletingLastPathComponent().path + "//./" + module.lastPathComponent
        await catalog.scan(folders: [fixture.modules.path, module.path, moduleAlias])
        check.expect(catalog.error == nil, message: "real fixture scanner succeeds")
        check.expectEqual(
            expected: 1, actual: fixture.launches.count, what: "overlapping roots probe a module only once")
        check.expectEqual(
            expected: 4, actual: catalog.entries.count, what: "scanner publishes all four fixture classes")
        let producers = catalog.entries.filter { (entry: PluginCatalogEntry) in entry.isMidiProducer }
        check.expectEqual(
            expected: ["TestGen", "TestGenAudio", "TestGenRealtimeOnly"], actual: producers.map(\.name),
            what: "panel path has exactly three MIDI producers in deterministic name order")
        let audio = catalog.entries.first { (entry: PluginCatalogEntry) in entry.name == "TestAudioOnly" }
        check.expect(
            audio?.isMidiProducer == false && audio?.blockedReason == nil,
            message: "audio-only class is scanned but hidden by panel filter")
        check.expect(
            catalog.entries.allSatisfy { (entry: PluginCatalogEntry) in entry.classUID.count == 16 },
            message: "class UIDs decode to sixteen bytes")
        if let producer = producers.first {
            check.expectEqual(
                expected: producer, actual: catalog.entry(modulePath: module.path, classUID: producer.classUID),
                what: "class lookup preserves module and UID identity")
            check.expectEqual(
                expected: producer, actual: catalog.entry(modulePath: moduleAlias, classUID: producer.classUID),
                what: "lookup standardizes equivalent module paths without changing class identity")
        }
        check.expect(
            catalog.entry(modulePath: module.path, classUID: []) == nil, message: "lookup never aliases an unknown UID")
        check.expect(
            progressive && scanningStates.first == true && scanningStates.last == false,
            message: "entries publish while scanning and the final notification clears isScanning")
        check.expect(fixture.running.isEmpty, message: "scan completion reaps every real child")

        await catalog.scan(folders: [])
        check.expectEqual(
            expected: 1, actual: fixture.launches.count, what: "unchanged second scan launches no children")
        let restored = fixture.catalog(timeout: .seconds(10))
        check.expectEqual(
            expected: catalog.entries, actual: restored.entries, what: "success entries reload from PluginCatalog.json")
        await restored.scan(folders: [])
        check.expectEqual(
            expected: 1, actual: fixture.launches.count, what: "disk success cache prevents child launches")

        let added = try fixture.copy("porydawtestgen", into: "added")
        await catalog.scan(folders: [])
        check.expectEqual(
            expected: [module.path, added.path], actual: fixture.launches,
            what: "adding one module launches exactly one additional child")
        check.expectEqual(
            expected: 8, actual: catalog.entries.count, what: "new module joins the existing usable entries")
        let attributes = try FileManager.default.attributesOfItem(atPath: added.path)
        guard let modificationDate = attributes[.modificationDate] as? Date else {
            check.fail("module fixture has a modification date")
            return
        }
        try FileManager.default.setAttributes(
            [.modificationDate: modificationDate.addingTimeInterval(2)], ofItemAtPath: added.path)
        await catalog.scan(folders: [])
        check.expectEqual(
            expected: [module.path, added.path, added.path], actual: fixture.launches,
            what: "changed module metadata re-probes only that module")
        try FileManager.default.removeItem(at: added)
        await catalog.scan(folders: [])
        check.expectEqual(
            expected: 4, actual: catalog.entries.count, what: "removed module entries disappear on every enumeration")
        check.expect(
            catalog.entries.allSatisfy { (entry: PluginCatalogEntry) in entry.modulePath == module.path },
            message: "removal retains only the surviving module")
        check.expectEqual(expected: 3, actual: fixture.launches.count, what: "removal alone launches no children")
        await catalog.scan(folders: [], force: true)
        check.expectEqual(expected: 4, actual: fixture.launches.count, what: "force re-probes a cached success")

        let nested = module.appendingPathComponent("must-not-enumerate.vst3")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        await catalog.scan(folders: [])
        check.expect(!fixture.launches.contains(nested.path), message: "enumeration never enters a VST3 bundle")
        let removedCache = fixture.catalog(timeout: .seconds(10))
        check.expectEqual(
            expected: catalog.entries, actual: removedCache.entries,
            what: "disk cache persists removal and latest success")
    } catch {
        check.fail("catalog discovery fixture: \(error)")
    }
}

@MainActor
private func checkCatalogContainment(_ report: CheckReport) async {
    let check = report.scoped(cppID: pluginCatalogID)
    do {
        let fixture = try CatalogCheckFixture()
        defer { fixture.cleanup(check) }
        _ = try fixture.copy("porydawtestgen")
        let crash = try fixture.copy("porydawtestcrash")
        let hang = try fixture.copy("porydawtesthang")
        let catalog = fixture.catalog()
        let started = ContinuousClock.now
        await catalog.scan(folders: [])
        check.expect(
            started.duration(to: .now) < .seconds(10),
            message: "injected hang timeout completes before the production ten-second deadline")
        check.expectEqual(
            expected: "Porydaw's plugin scanner crashed while loading this plugin.",
            actual: catalog.entries.first { (entry: PluginCatalogEntry) in entry.modulePath == crash.path }?
                .blockedReason,
            what: "crashing fixture is contained with the exact crash reason")
        check.expectEqual(
            expected: "Loading this plugin took longer than 10 seconds.",
            actual: catalog.entries.first { (entry: PluginCatalogEntry) in entry.modulePath == hang.path }?
                .blockedReason,
            what: "hanging fixture is terminated with the exact timeout reason")
        check.expectEqual(
            expected: 3, actual: fixture.launches.count, what: "each success or blocked module owns one child")
        check.expect(
            fixture.running.isEmpty, message: "timeout terminates and reaps the hanging child before returning")
        let restored = fixture.catalog()
        check.expectEqual(
            expected: catalog.entries, actual: restored.entries,
            what: "successful and blocked entries both survive disk reload")
        let crashAttributes = try FileManager.default.attributesOfItem(atPath: crash.path)
        guard let crashDate = crashAttributes[.modificationDate] as? Date else {
            check.fail("crash fixture has a modification date")
            return
        }
        try FileManager.default.setAttributes(
            [.modificationDate: crashDate.addingTimeInterval(2)], ofItemAtPath: crash.path)
        await restored.scan(folders: [])
        check.expectEqual(
            expected: 3, actual: fixture.launches.count,
            what: "cached blocks are not retried even when metadata changes")
        let crashAlias = crash.deletingLastPathComponent().path + "//./" + crash.lastPathComponent
        restored.retry(modulePath: crashAlias)
        check.expect(
            !restored.entries.contains { (entry: PluginCatalogEntry) in entry.modulePath == crash.path },
            message: "retry clears only the requested module block")
        check.expect(
            restored.entries.contains { (entry: PluginCatalogEntry) in
                entry.modulePath == hang.path && entry.blockedReason != nil
            }, message: "retry preserves other module blocks")
        await restored.scan(folders: [])
        check.expectEqual(
            expected: 4, actual: fixture.launches.count, what: "retry launches exactly the cleared blocked module")
        restored.retryAll()
        check.expectEqual(
            expected: 4, actual: restored.entries.count, what: "retryAll clears blocks but retains successful classes")
        let cleared = fixture.catalog()
        check.expectEqual(
            expected: restored.entries, actual: cleared.entries, what: "retry block clearing is persisted to disk")
        await restored.scan(folders: [])
        check.expectEqual(
            expected: 6, actual: fixture.launches.count, what: "retryAll re-probes both blocked modules only")
        await restored.scan(folders: [], force: true)
        check.expectEqual(
            expected: 9, actual: fixture.launches.count, what: "force re-probes successes and blocked modules together")
        let visible = restored.entries.filter { (entry: PluginCatalogEntry) in
            entry.isMidiProducer || entry.blockedReason != nil
        }
        check.expectEqual(
            expected: 5, actual: visible.count,
            what: "panel list includes three producers and two capability-unknown blocks")
    } catch {
        check.fail("catalog containment fixture: \(error)")
    }
}

@MainActor
private func checkCatalogParallelAndCancel(_ report: CheckReport) async {
    let check = report.scoped(cppID: pluginCatalogID)
    do {
        let fixture = try CatalogCheckFixture()
        defer { fixture.cleanup(check) }
        for index in 0..<7 { _ = try fixture.copy("porydawtestgen", into: "module-\(index)") }
        let catalog = fixture.catalog(timeout: .seconds(10))
        var sawPartialEntries = false
        catalog.onChanged = { () -> Void in
            if catalog.isScanning, !catalog.entries.isEmpty, catalog.entries.count < 28 { sawPartialEntries = true }
        }
        await catalog.scan(folders: [])
        catalog.onChanged = nil
        let limit = max(1, min(4, ProcessInfo.processInfo.activeProcessorCount))
        check.expectEqual(
            expected: limit, actual: fixture.peakChildren,
            what: "real children fill but never exceed min(4, activeProcessorCount)")
        check.expectEqual(
            expected: 7, actual: fixture.launches.count, what: "bounded scheduler launches every module once")
        check.expect(sawPartialEntries, message: "catalog is usable before all module children have completed")
        let sorted = catalog.entries.sorted { (left: PluginCatalogEntry, right: PluginCatalogEntry) in
            if left.name != right.name { return left.name < right.name }
            if left.modulePath != right.modulePath { return left.modulePath < right.modulePath }
            return left.classUID.lexicographicallyPrecedes(right.classUID)
        }
        check.expectEqual(
            expected: sorted, actual: catalog.entries,
            what: "completion order cannot perturb deterministic name and identity sorting")

        let preserved = catalog.entries
        let cancelledEnumeration = fixture.catalog(timeout: .seconds(10))
        cancelledEnumeration.onChanged = { [weak cancelledEnumeration] () -> Void in
            guard let cancelledEnumeration, cancelledEnumeration.isScanning else { return }
            cancelledEnumeration.cancelScan()
        }
        await cancelledEnumeration.scan(folders: [], force: true)
        cancelledEnumeration.onChanged = nil
        check.expectEqual(
            expected: preserved, actual: cancelledEnumeration.entries,
            what: "cancelling enumeration never prunes the previously usable catalog")
        check.expectEqual(
            expected: 7, actual: fixture.launches.count, what: "cancelling enumeration launches no children")
        var cancelledLaunches = 0
        var active: Set<Int32> = []
        var cancelling: PluginCatalog?
        let cancelCatalog = PluginCatalog(
            cacheDirectory: fixture.cache, scannerURL: fixture.scanner, standardRoots: [fixture.modules.path],
            childLaunched: { (_: String, pid: Int32) in
                cancelledLaunches += 1
                active.insert(pid)
                cancelling?.cancelScan()
            },
            childTerminated: { (_: String, pid: Int32) in active.remove(pid) })
        cancelling = cancelCatalog
        await cancelCatalog.scan(folders: [], force: true)
        cancelling = nil
        check.expectEqual(expected: 1, actual: cancelledLaunches, what: "cancelScan prevents all queued child launches")
        check.expect(
            active.isEmpty && !cancelCatalog.isScanning,
            message: "cancelScan terminates children before clearing isScanning")
        check.expectEqual(
            expected: preserved, actual: cancelCatalog.entries,
            what: "cancelled probes preserve cached successes rather than introducing blocks")
        let reloaded = fixture.catalog(timeout: .seconds(10))
        check.expectEqual(
            expected: preserved, actual: reloaded.entries, what: "cancelled probes do not poison the disk cache")
        await reloaded.scan(folders: [])
        check.expectEqual(
            expected: 7, actual: fixture.launches.count, what: "catalog remains reusable after cancellation")
    } catch {
        check.fail("catalog parallel and cancellation fixture: \(error)")
    }
}

@MainActor
private func checkCatalogRunningCancellation(_ report: CheckReport) async {
    let check = report.scoped(cppID: pluginCatalogID)
    do {
        let fixture = try CatalogCheckFixture()
        defer { fixture.cleanup(check) }
        let limit = max(1, min(4, ProcessInfo.processInfo.activeProcessorCount))
        for index in 0..<(limit + 2) { _ = try fixture.copy("porydawtesthang", into: "hang-\(index)") }
        for cancelTask in [false, true] {
            var launches = 0
            var running: Set<Int32> = []
            var scanningDuringReap = true
            var scanTask: Task<Void, Never>?
            var cancelling: PluginCatalog?
            let catalog = PluginCatalog(
                cacheDirectory: fixture.cache, scannerURL: fixture.scanner, standardRoots: [fixture.modules.path],
                childLaunched: { (_: String, pid: Int32) in
                    launches += 1
                    running.insert(pid)
                    if launches == limit {
                        if cancelTask { scanTask?.cancel() } else { cancelling?.cancelScan() }
                    }
                },
                childTerminated: { (_: String, pid: Int32) in
                    running.remove(pid)
                    if cancelling?.isScanning != true { scanningDuringReap = false }
                })
            cancelling = catalog
            let started = ContinuousClock.now
            let operation = Task { @MainActor in await catalog.scan(folders: []) }
            scanTask = operation
            await operation.value
            scanTask = nil
            cancelling = nil
            let mode = cancelTask ? "task cancellation" : "cancelScan"
            check.expectEqual(
                expected: limit, actual: launches, what: "\(mode) stops queued modules with all child slots active")
            check.expect(
                running.isEmpty && scanningDuringReap && !catalog.isScanning,
                message: "\(mode) reaps every running child before ending scanning")
            check.expect(
                started.duration(to: .now) < .seconds(10),
                message: "\(mode) does not wait for the hanging modules' production deadlines")
            check.expect(
                catalog.entries.isEmpty && catalog.error == nil,
                message: "\(mode) does not publish cancellation as a plugin block or installation error")
        }
    } catch {
        check.fail("catalog running-child cancellation fixture: \(error)")
    }
}

private func scannerFailureLine(scannerURL: URL, module: URL) throws -> String {
    let child = Process()
    child.executableURL = scannerURL
    child.arguments = ["scan", module.path]
    child.standardInput = FileHandle.nullDevice
    child.standardOutput = FileHandle.nullDevice
    let stderr = Pipe()
    child.standardError = stderr
    try child.run()
    let bytes = stderr.fileHandleForReading.readDataToEndOfFile()
    child.waitUntilExit()
    return String(decoding: bytes, as: UTF8.self).split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
}

@MainActor
private func checkCatalogFailureAndUserRoots(_ report: CheckReport) async {
    let check = report.scoped(cppID: pluginCatalogID)
    do {
        let fixture = try CatalogCheckFixture()
        defer { fixture.cleanup(check) }
        let module = try fixture.copy("porydawtestgen", into: "user")
        let catalog = PluginCatalog(cacheDirectory: fixture.cache, scannerURL: fixture.scanner, standardRoots: [])
        await catalog.scan(folders: [module.deletingLastPathComponent().path])
        check.expectEqual(
            expected: 4, actual: catalog.entries.count, what: "user roots are enumerated without platform roots")
        await catalog.scan(folders: [])
        check.expect(catalog.entries.isEmpty, message: "removing a user root drops its modules")
        let invalid = fixture.modules.appendingPathComponent("invalid.vst3")
        try Data("not a plugin".utf8).write(to: invalid)
        await catalog.scan(folders: [invalid.path])
        let reason = catalog.entries.first?.blockedReason ?? ""
        let stderrLine = try scannerFailureLine(scannerURL: fixture.scanner, module: invalid)
        check.expect(!stderrLine.isEmpty, message: "real scanner supplies its one-line loader reason")
        check.expectEqual(
            expected: "The plugin could not be loaded: \(stderrLine)", actual: reason,
            what: "load failure preserves the exact load prefix and real scanner stderr line")
        check.expect(!reason.contains("\n"), message: "load failure includes only one stderr line")
        let missing = PluginCatalog(
            cacheDirectory: fixture.root.appendingPathComponent("missing-cache"),
            scannerURL: fixture.root.appendingPathComponent("missing-scanner"), standardRoots: [])
        var resetsError = false
        missing.onChanged = { () -> Void in
            if missing.isScanning, missing.error == nil { resetsError = true }
        }
        await missing.scan(folders: [fixture.modules.path])
        check.expectEqual(
            expected: "Plugin scanner is missing from this installation.", actual: missing.error,
            what: "missing scanner gives the exact installation error")
        check.expect(
            !missing.isScanning && missing.entries.isEmpty,
            message: "missing scanner fails without fallback or false plugin blocks")
        resetsError = false
        await missing.scan(folders: [])
        missing.onChanged = nil
        check.expect(
            resetsError, message: "each scan resets the previous installation error before reporting its outcome")
    } catch {
        check.fail("catalog failure and user-root fixture: \(error)")
    }
}

@MainActor
private func checkCatalogCacheRecovery(_ report: CheckReport) async {
    let check = report.scoped(cppID: pluginCatalogID)
    do {
        let fixture = try CatalogCheckFixture()
        defer { fixture.cleanup(check) }
        _ = try fixture.copy("porydawtestgen")
        try Data("not a cache directory".utf8).write(to: fixture.cache)
        let catalog = fixture.catalog(timeout: .seconds(10))
        await catalog.scan(folders: [])
        check.expect(catalog.error != nil, message: "an unwritable cache reports its write failure")
        check.expectEqual(
            expected: 4, actual: catalog.entries.count, what: "a cache write failure keeps scanned entries usable")
        try FileManager.default.removeItem(at: fixture.cache)
        await catalog.scan(folders: [])
        check.expect(catalog.error == nil, message: "an unchanged scan retries the failed cache write")
        check.expectEqual(
            expected: 1, actual: fixture.launches.count, what: "retrying the cache write launches no children")
        check.expectEqual(
            expected: catalog.entries, actual: fixture.catalog().entries,
            what: "the retried write persists the unchanged scan results")
        let cacheFile = fixture.cache.appendingPathComponent("PluginCatalog.json")
        try FileManager.default.removeItem(at: cacheFile)
        await catalog.scan(folders: [])
        check.expectEqual(
            expected: catalog.entries, actual: fixture.catalog().entries,
            what: "an unchanged scan recreates a deleted cache file")

        try Data("{".utf8).write(to: cacheFile)
        let repaired = fixture.catalog(timeout: .seconds(10))
        check.expect(repaired.entries.isEmpty, message: "a malformed cache restores no entries")
        await repaired.scan(folders: [])
        check.expectEqual(
            expected: 2, actual: fixture.launches.count, what: "a malformed cache re-probes its modules")
        check.expectEqual(
            expected: catalog.entries, actual: fixture.catalog().entries,
            what: "the next scan replaces a malformed cache")
    } catch {
        check.fail("catalog cache recovery fixture: \(error)")
    }
}

/// Runs the catalog's real scanner/fixture checks through the shared main-actor runner.
@MainActor
public func runPluginCatalogChecks(_ report: CheckReport) {
    let cases: [@MainActor (CheckReport) async -> Void] = [
        checkCatalogDiscovery, checkCatalogContainment, checkCatalogParallelAndCancel,
        checkCatalogRunningCancellation, checkCatalogFailureAndUserRoots, checkCatalogCacheRecovery,
    ]
    do {
        for operation in cases {
            try runBlocking { await operation(report) }
        }
    } catch {
        report.fail(pluginCatalogID, "real scanner catalog checks: \(error)")
    }
}
