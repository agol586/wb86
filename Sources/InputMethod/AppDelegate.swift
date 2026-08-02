import AppKit
import Darwin
import InputMethodKit

@main
enum MacWubiApplication {
    @MainActor
    static func main() {
        if CommandLine.arguments.dropFirst() == ["--memory-probe"] {
            PerformanceMemoryProbe.run()
            return
        }
        if CommandLine.arguments.count == 3,
           CommandLine.arguments[1] == "--monthly-volume-probe",
           let target = UInt64(CommandLine.arguments[2]),
           target > 0, target <= 10_000_000 {
            PerformanceStressProbe.run(targetCommittedCharacters: target)
            return
        }
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
}

private enum PerformanceMemoryProbe {
    @MainActor
    static func run() {
        _ = NSApplication.shared
        guard let context = PerformanceProbeContext.make() else { exit(66) }
        let coordinator = context.coordinator
        let converter = context.converter
        var settings = InputSettings.newInstallDefault
        settings.candidatePageSize = 9
        settings.candidateLayout = .horizontal
        settings.candidateFontScale = 2
        settings.autoCommitFirstAtFive = true
        settings.automaticFrequency = true
        settings.candidate2And3ShortcutsEnabled = true
        settings.defaultMode = InputMode(language: .chinese, punctuation: .chinese,
                                         width: .full, script: .traditional)
        settings.keyBindings.pageKeyGroups = Set(CandidatePageKeyGroup.allCases)
        let policy = CandidateRankingPolicy(settingsGeneration: 1,
                                            pageSize: settings.candidatePageSize,
                                            automaticFrequency: true)
        for raw in ["a", "nihao", "shi"] {
            guard let sequence = CompositionKeySequence(raw) else { exit(65) }
            for pageIndex in 0...1 {
                _ = try? coordinator.page(
                    for: sequence, pageIndex: pageIndex, policy: policy,
                    mode: settings.defaultMode, mixedPinyinEnabled: true,
                    scriptConverter: converter
                )
            }
        }
        // Two independent engines model normal multi-client session ownership while sharing the
        // coordinator's one read-only WB86/MWPY mapping.
        let engines = (0..<2).map { _ in
            InputEngine(sequencePolicyQuery: { sequence, pageIndex, frozenPolicy, mode, mixed in
                try coordinator.page(for: sequence, pageIndex: pageIndex,
                                     policy: frozenPolicy, mode: mode,
                                     mixedPinyinEnabled: mixed,
                                     scriptConverter: converter)
            })
        }
        for engine in engines {
            engine.initializeMode(from: settings.defaultMode)
            engine.apply(settings: settings, generation: 1)
            for letter in ["n", "i", "h", "a", "o"] { _ = engine.process(.letter(letter)) }
            _ = engine.process(.pageNext)
            _ = engine.process(.cancel)
        }
        RunLoop.current.run()
    }
}

private struct PerformanceProbeContext {
    let coordinator: PersonalizationCoordinator
    let converter: ScriptConverter

    static func make(bundle: Bundle = .main) -> PerformanceProbeContext? {
        guard let wb86URL = bundle.url(forResource: "wb86", withExtension: "bin"),
              let pinyinURL = bundle.url(forResource: "pinyin-simp", withExtension: "bin"),
              let conversionURL = bundle.url(forResource: "script-conversion",
                                             withExtension: "bin"),
              let wb86 = try? DictionaryLoader.load(from: wb86URL),
              let pinyin = try? PinyinDictionaryLoader.load(from: pinyinURL,
                                                            wb86Image: wb86),
              let converter = try? ScriptConverter(
                data: Data(contentsOf: conversionURL, options: .mappedIfSafe)
              ) else { return nil }
        return PerformanceProbeContext(
            coordinator: PersonalizationCoordinator(
                index: DictionaryIndex(image: wb86),
                pinyinIndex: PinyinDictionaryIndex(image: pinyin),
                userStore: nil,
                learningStore: nil
            ),
            converter: converter
        )
    }
}

private enum PerformanceStressProbe {
    private static let logicalDayCount = 30
    private static let sessionCount = 8

    private struct LatencyWindow {
        var sum: UInt64 = 0
        var count: UInt64 = 0
        mutating func add(_ value: UInt64) { sum += value; count += 1 }
        var average: UInt64 { count == 0 ? 0 : sum / count }
    }

    @MainActor
    static func run(targetCommittedCharacters: UInt64) {
        _ = NSApplication.shared
        guard let context = PerformanceProbeContext.make() else { exit(66) }
        let coordinator = context.coordinator
        let converter = context.converter
        let makeEngines = {
            (0..<sessionCount).map { _ in
                InputEngine(sequencePolicyQuery: { sequence, pageIndex, policy, mode, mixed in
                    try coordinator.page(for: sequence, pageIndex: pageIndex,
                                         policy: policy, mode: mode,
                                         mixedPinyinEnabled: mixed,
                                         scriptConverter: converter)
                })
            }
        }
        let warmupEngines = makeEngines()
        for warmupIteration in 0..<64 {
            for (sessionIndex, engine) in warmupEngines.enumerated() {
                let settings = settings(iteration: UInt64(warmupIteration))
                engine.initializeMode(from: settings.defaultMode)
                engine.apply(settings: settings, generation: UInt64(warmupIteration + 1))
                for key in keys(iteration: warmupIteration, sessionIndex: sessionIndex) {
                    _ = engine.process(.letter(key))
                }
                _ = engine.process(.pageNext)
                _ = engine.process(.pagePrevious)
                _ = engine.process(.selectFirst)
                _ = engine.process(.cancel)
            }
        }
        FileHandle.standardOutput.write(Data("MACWUBI_MONTHLY_VOLUME_READY\n".utf8))
        var maximumLatency: UInt64 = 0
        var firstWindow = LatencyWindow()
        var lastWindow = LatencyWindow()
        var footprints = [UInt64]()
        var iterations: UInt64 = 0
        var committedCharacters: UInt64 = 0
        var learningDeltas: UInt64 = 0
        let start = DispatchTime.now().uptimeNanoseconds
        footprints.append(physicalFootprintBytes())

        for logicalDay in 1...logicalDayCount {
            let engines = makeEngines()
            let dayTarget = (targetCommittedCharacters * UInt64(logicalDay)
                             + UInt64(logicalDayCount - 1)) / UInt64(logicalDayCount)
            while committedCharacters < dayTarget {
                autoreleasepool {
                    for (sessionIndex, engine) in engines.enumerated() {
                        let currentSettings = settings(iteration: iterations)
                        engine.initializeMode(from: currentSettings.defaultMode)
                        engine.apply(settings: currentSettings, generation: iterations + 1)

                        for key in keys(iteration: Int(iterations), sessionIndex: sessionIndex) {
                            let before = DispatchTime.now().uptimeNanoseconds
                            let result = engine.process(.letter(key))
                            let latency = DispatchTime.now().uptimeNanoseconds - before
                            maximumLatency = max(maximumLatency, latency)
                            addLatency(latency, progress: committedCharacters,
                                       target: targetCommittedCharacters,
                                       first: &firstWindow, last: &lastWindow)
                            committedCharacters += chineseCharacterCount(in: result)
                            if result.learningDelta != nil { learningDeltas += 1 }
                        }
                        committedCharacters += chineseCharacterCount(in: engine.process(.pageNext))
                        committedCharacters += chineseCharacterCount(in: engine.process(.pagePrevious))
                        let selected = engine.process(.selectFirst)
                        committedCharacters += chineseCharacterCount(in: selected)
                        if selected.learningDelta != nil { learningDeltas += 1 }
                        committedCharacters += chineseCharacterCount(in: engine.process(.cancel))
                        iterations += 1
                    }
                }
            }
            footprints.append(physicalFootprintBytes())
        }

        let steady = footprints.dropFirst(max(1, footprints.count / 4))
        let windowSize = max(1, steady.count / 4)
        let firstBytes = average(steady.prefix(windowSize))
        let lastBytes = average(steady.suffix(windowSize))
        let maximumBytes = footprints.max() ?? 0
        let durationSeconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
        let report = "MACWUBI_MONTHLY_VOLUME_REPORT targetCommittedCharacters=\(targetCommittedCharacters) "
            + "committedCharacters=\(committedCharacters) logicalDays=\(logicalDayCount) "
            + "sessionsPerDay=\(sessionCount) iterations=\(iterations) "
            + "learningDeltas=\(learningDeltas) durationSeconds=\(durationSeconds) "
            + "firstAverageLatencyNs=\(firstWindow.average) "
            + "lastAverageLatencyNs=\(lastWindow.average) "
            + "maximumLatencyNs=\(maximumLatency) "
            + "firstSteadyBytes=\(firstBytes) lastSteadyBytes=\(lastBytes) "
            + "maximumBytes=\(maximumBytes)\n"
        FileHandle.standardOutput.write(Data(report.utf8))
    }

    private static func addLatency(_ latency: UInt64, progress: UInt64, target: UInt64,
                                   first: inout LatencyWindow, last: inout LatencyWindow) {
        if progress <= target / 4 {
            first.add(latency)
        } else if progress >= target * 3 / 4 {
            last.add(latency)
        }
    }

    private static func chineseCharacterCount(in result: InputProcessingResult) -> UInt64 {
        UInt64(result.clientActions.actions.reduce(into: 0) { count, action in
            guard case let .commitText(text) = action else { return }
            count += text.reduce(into: 0) { characterCount, character in
                if character.unicodeScalars.contains(where: isHanScalar) { characterCount += 1 }
            }
        })
    }

    private static func isHanScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0x20000...0x2EBEF,
             0x30000...0x323AF:
            return true
        default:
            return false
        }
    }

    private static func physicalFootprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size)
            / mach_msg_type_number_t(MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    private static func average<S: Collection>(_ samples: S) -> UInt64
    where S.Element == UInt64 {
        samples.isEmpty ? 0 : samples.reduce(0, +) / UInt64(samples.count)
    }

    private static func settings(iteration: UInt64) -> InputSettings {
        var settings = InputSettings.newInstallDefault
        settings.candidatePageSize = 5 + Int(iteration % 5)
        settings.candidateLayout = iteration.isMultiple(of: 2) ? .vertical : .horizontal
        settings.candidateFontScale = iteration.isMultiple(of: 3) ? 1 : 1.6
        settings.autoCommitAtFour = iteration.isMultiple(of: 2)
        settings.autoCommitFirstAtFive = iteration.isMultiple(of: 3)
        settings.automaticFrequency = true
        settings.mixedPinyinEnabled = true
        settings.codeHintEnabled = true
        settings.candidate2And3ShortcutsEnabled = true
        settings.defaultMode.script = iteration.isMultiple(of: 2) ? .simplified : .traditional
        settings.keyBindings.pageKeyGroups = Set(CandidatePageKeyGroup.allCases)
        return settings
    }

    private static func keys(iteration: Int, sessionIndex: Int) -> [String] {
        switch (iteration + sessionIndex) % 3 {
        case 0: return ["w", "q", "v", "b"]
        case 1: return ["n", "i", "h", "a", "o"]
        default: return ["s", "h", "i"]
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var inputMethodServer: IMKServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let connectionName = Bundle.main.object(
            forInfoDictionaryKey: "InputMethodConnectionName"
        ) as? String,
        !connectionName.isEmpty,
        let bundleIdentifier = Bundle.main.bundleIdentifier else {
            NSApplication.shared.terminate(nil)
            return
        }
        inputMethodServer = IMKServer(
            name: connectionName,
            bundleIdentifier: bundleIdentifier
        )
    }
}
