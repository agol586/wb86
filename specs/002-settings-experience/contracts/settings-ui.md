# Contract: 设置窗口与无障碍

## Pages

- “常用”：初始语言/简繁/全半角/标点，四码唯一、五码首选、自动调频，混输、编码提示、
  分号/单引号快捷选择。
- “按键”：语言/简繁/全半角切换预设，五组独立翻页键，键盘布局，恢复默认。
- 复用既有外观页；新增行为不得降低其可访问性。

## Interaction

- 所有控件有稳定 label、value、help/description 和键盘焦点顺序；分组标题可由辅助技术识别。
- 窗口始终区分已保存值和未保存 draft；Save、Cancel 和 Restore Default 均可纯键盘完成。
- Save 成功、失败和 future-schema 只读状态提供可访问反馈；校验失败把焦点移到第一个相关控件，
  同时保留其余 draft 便于修正。
- Restore Default 显示确认，明确说明只重置设置；取消不改变控件、快照或其他数据域。

## Lifecycle

- 窗口打开/重新聚焦时读取协调器的最新已保存代次，不直接读写零散 UserDefaults。
- 成功保存后才刷新 saved baseline；持久化失败继续显示 draft 与错误，不假装设置已生效。
- 窗口关闭不隐式保存。
