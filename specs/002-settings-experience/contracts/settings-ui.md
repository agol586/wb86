# Contract: 设置窗口与普通鼠标/键盘操作

## Pages

- “常用”：初始语言/简繁/全半角/标点，四码唯一、五码首选、自动调频，混输、编码提示、
  分号/单引号快捷选择。
- “按键”：语言切换固定提供 Shift、Control、Caps Lock、禁用；简繁/全半角提供各自预设，
  以及五组独立翻页键、键盘布局和恢复默认。
- 复用既有外观页；普通视觉显示、鼠标和键盘操作保持一致。

## Interaction

- 所有交互控件有稳定的产品内标识和普通键盘焦点顺序。
- 窗口始终区分已保存值和未保存 draft；Save、Cancel 和 Restore Default 均可纯键盘完成。
- Save 成功、失败和 future-schema 只读状态提供可见反馈；校验失败把键盘焦点移到第一个相关控件，
  同时保留其余 draft 便于修正。
- Restore Default 显示确认，明确说明只重置设置；取消不改变控件、快照或其他数据域。

## Unsupported assistive technology

- 不发布 VoiceOver/屏幕阅读器专用 label、value、help、候选元素树、朗读公告或辅助焦点。
- 不承诺旁白实用工具、Accessibility Inspector、辅助选择或设置辅助导航。
- 系统开启辅助技术时仍必须保持一般故障安全，但这不是辅助技术验收通过的声明。

## Lifecycle

- 窗口打开/重新聚焦时读取协调器的最新已保存代次，不直接读写零散 UserDefaults。
- 成功保存后才刷新 saved baseline；持久化失败继续显示 draft 与错误，不假装设置已生效。
- 窗口关闭不隐式保存。
