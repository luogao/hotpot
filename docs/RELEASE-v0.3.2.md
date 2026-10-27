## 这版改了什么

**项目名集中配置**
`AppInfo.name` 是唯一来源：窗口标题、菜单、tooltip、copyright、GitHub 链接、配置目录全部从它派生。后面想改名只改这一行（外加 `Info.plist` 的 `CFBundleName`）。

**copyright 换成项目名**
面板和设置页页脚现在是 `© 2026 HotPot`。

**品牌图标**
agent 列表和面板行改用 [lobehub/icons](https://lobehub.com/icons) 的单色 SVG，预渲染成 PNG 后走 template mode + 线性渐变填充（浅灰 → 中灰），不再是系统符号。

覆盖：Claude Code / Codex / Cursor / Gemini CLI / Copilot CLI / Ollama / Pi。
lobehub 没有对应图的（Aider、LM Studio、Xcode Build、ffmpeg、Docker）保留 SF Symbols 线条图，视觉重量已经对齐。

**Pi 的 logo** 用 lobehub 的 Pi 图标（方块 P）。
