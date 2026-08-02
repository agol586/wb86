import AppKit
import XCTest
@testable import MacWubi

@MainActor
final class SettingsAccessibilityTests: XCTestCase {
    func testSaveCancelFeedbackAndFailureKeepDraftAndFocus() throws {
        var writes = [InputSettings]()
        let controller = SettingsWindowController(settings: .default) { writes.append($0) }
        controller.loadWindow()
        controller.updateDraft { $0.candidatePageSize = 9 }
        controller.cancelDraft()
        XCTAssertTrue(writes.isEmpty)
        XCTAssertEqual(controller.draftSettings, controller.savedSettings)

        controller.updateDraft { $0.candidatePageSize = 9 }
        XCTAssertTrue(controller.saveDraft())
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(controller.savedSettings.candidatePageSize, 9)
        XCTAssertEqual(controller.lastValidationAnnouncement, "设置已保存。")

        let failing = SettingsWindowController(settings: .default) { _ in
            throw SaveError.failed
        }
        failing.loadWindow()
        failing.updateDraft { $0.candidatePageSize = 8 }
        XCTAssertFalse(failing.saveDraft())
        XCTAssertEqual(failing.savedSettings, .default)
        XCTAssertEqual(failing.draftSettings.candidatePageSize, 8)
        XCTAssertEqual(failing.lastValidationAnnouncement, "保存失败，最后有效设置保持不变。")
        XCTAssertEqual(failing.lastFocusedControlLabel, "初始语言")
    }

    func testKeyboardTraversalValuesFocusOrderAndValidationAnnouncement() {
        let controller = SettingsWindowController.makeForTesting()
        controller.loadWindow()
        XCTAssertFalse(controller.focusOrderLabels.isEmpty)
        XCTAssertEqual(controller.focusOrderLabels, controller.accessibleControls.compactMap {
            $0.accessibilityLabel()
        })
        XCTAssertTrue(controller.accessibleControls.allSatisfy(\.acceptsFirstResponder))
        XCTAssertTrue(controller.accessibleControls.allSatisfy {
            $0.accessibilityValue() != nil || $0 is NSButton
        })
        XCTAssertTrue(controller.accessibleControls.allSatisfy {
            !($0.accessibilityHelp() ?? "").isEmpty
        })

        var invalid = InputSettings.default
        invalid.candidatePageSize = 99
        XCTAssertFalse(controller.validateAndApply(invalid))
        XCTAssertEqual(controller.lastValidationAnnouncement, "设置无效：候选数量必须为 5 至 9。")
        XCTAssertEqual(controller.lastFocusedControlLabel, "每页候选数量 5 至 9")
        XCTAssertTrue(controller.confirmationMessage(for: .deleteAllPersonalization).contains("基础词库"))
    }

    func testEveryEnhancedSettingHasOneNamedKeyboardAccessibleControl() {
        let controller = SettingsWindowController.makeForTesting()
        controller.loadWindow()
        let requiredLabels = [
            "初始语言", "初始简繁体", "初始全半角", "中文模式标点",
            "四码唯一时直接上屏", "第五码将首选词上屏", "五笔自动调频",
            "五笔拼音混合输入", "开启编码提示", "分号和单引号候选快捷键",
            "中英文切换", "简繁切换", "全半角切换", "键盘布局",
            "逗号句号翻页", "减号等号翻页", "中括号翻页",
            "Tab/Shift-Tab 翻页", "上下方向键翻页",
            "候选布局", "每页候选数量 5 至 9", "候选字号缩放",
            "恢复默认…", "取消", "保存"
        ]
        let labels = controller.accessibleControls.compactMap { $0.accessibilityLabel() }

        for label in requiredLabels {
            XCTAssertEqual(labels.filter { $0 == label }.count, 1,
                           "\(label) must identify exactly one control")
            let control = controller.accessibleControls.first { $0.accessibilityLabel() == label }
            XCTAssertEqual(control?.acceptsFirstResponder, true)
            XCTAssertFalse(control?.accessibilityHelp()?.isEmpty ?? true)
        }
    }

    func testKeyBindingPopupsExposeCurrentChoiceWithoutDuplicateTraversalStops() {
        let controller = SettingsWindowController.makeForTesting()
        controller.loadWindow()
        let keyLabels = ["中英文切换", "简繁切换", "全半角切换", "键盘布局"]
        let popups = controller.accessibleControls.compactMap { $0 as? NSPopUpButton }
            .filter { keyLabels.contains($0.accessibilityLabel() ?? "") }

        XCTAssertEqual(popups.count, keyLabels.count)
        XCTAssertEqual(popups.map { $0.accessibilityLabel() ?? "" }, keyLabels)
        XCTAssertEqual(popups.map { $0.accessibilityValue() as? String },
                       ["Shift", "Control-Shift-F", "禁用", "美国 ANSI"])
    }
}

private enum SaveError: Error { case failed }
