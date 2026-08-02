# Contract: Settings and Ordinary Interaction

> 2026-08-02 scope amendment: VoiceOver, VoiceOver Utility, Accessibility Inspector, and
> screen-reader-specific speech, focus, selection, actions, and settings navigation are unsupported.

## Entry and lifecycle

设置窗口由输入法菜单中的“设置…”打开，按需存在，不启动额外常驻进程。关闭窗口不得停止
活动输入会话；正在组合时修改输入行为设置，只能从下一次空闲状态生效。

## Settings groups

- Input：自动上屏、中文/英文默认状态、中英文标点、全半角、简繁输出。
- Keys：模式切换键与三组翻页键；冲突或系统保留组合必须被拒绝并解释。
- Candidates：每页 5...9 项、横向/纵向、字号和实时无文本内容预览。
- Learning：总开关、显式私密模式、清除词频。
- User Lexicon：搜索、添加、编辑、删除、导入和导出。
- Privacy：三个数据域的用途、占用、删除入口和“无网络”承诺。

恢复默认设置不得清除 UserLexicon 或 Learning；清除数据必须是独立、明确确认的操作。

## Candidate ordinary interaction

- 候选顺序、数字选择顺序、鼠标选择顺序和视觉顺序必须一致。
- 浅色、深色、高对比度、系统减少动态效果和多显示器缩放变化不得隐藏焦点或选中状态。
- 候选窗口不得夺取客户端键盘焦点；鼠标选择必须转换为相同核心选择事件。

## Settings ordinary interaction

- 所有控件具有可见标题、当前值、错误说明和普通键盘焦点顺序。
- 全部功能可由键盘访问，不依赖悬停、颜色或手势作为唯一信息。
- 删除、重置、导入覆盖等破坏性操作必须说明影响的数据域并要求确认。

不得发布或测试专用屏幕阅读器候选树、朗读公告、辅助焦点、辅助操作或设置辅助导航。
系统开启辅助技术时仍适用一般故障安全要求，但不构成辅助技术支持承诺。

## Validation matrix

至少覆盖普通鼠标/键盘、浅色、深色、高对比度、减少动态效果、不同缩放和多显示器。核心输入
与设置流程必须在不查看生产输入正文日志的前提下验收。
