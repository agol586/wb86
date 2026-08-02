import AppKit
import InputMethodKit

@main
enum MacWubiApplication {
    @MainActor
    static func main() {
        if CommandLine.arguments.dropFirst() == ["--memory-probe"] {
            PerformanceMemoryProbe.run()
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
        guard let conversionURL = Bundle.main.url(forResource: "script-conversion",
                                                  withExtension: "bin"),
              let converter = try? ScriptConverter(
                data: Data(contentsOf: conversionURL, options: .mappedIfSafe)
              ) else { exit(66) }
        let coordinator = PersonalizationCoordinator.shared
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
