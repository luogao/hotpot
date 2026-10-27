# AGENTS.md

给接手的 AI agent / 协作者：这个仓库是什么、怎么跑、别踩哪些坑。

## 项目

**HotPot** —— macOS 菜单栏小工具。显示哪个 AI agent（Claude Code / Codex / Cursor…）正在占满 CPU 并烤热机器，并把它降到能效核降温，不中断任务。

灵感来自 [WhoIsCooking](https://whoiscooking.site)，独立实现，MIT。当前状态：POC 跑通，M1（可用版）未开始。

## 目录

```
Package.swift                     SPM 定义，单 executableTarget，macOS 13+
Sources/HotPot/
├── main.swift                    入口；--dump / --cool-test / --render / --demo 自检分支
├── TemperatureReader.swift       IOHID 私有 API 读芯片温度（免 sudo）
├── ProcessScanner.swift          libproc 全表扫描 + rusage 差分算 CPU%
├── AgentRegistry.swift           agent 指纹表 + 会话聚合（ppid 链 / pgid 兜底）
├── Cooler.swift                  taskpolicy 降级 / 恢复
├── AppModel.swift                状态与 2s 轮询
├── AppDelegate.swift             NSStatusItem + NSPopover
└── PanelView.swift               SwiftUI 面板
PRD.md                            需求文档（可行性 / 功能清单 / 架构 / 风险 / 里程碑）
docs/POC-REPORT.md                实测数据与实验方法
docs/ui/                          设计稿三方案 + 四种状态的渲染截图
```

## 构建与自检

```bash
swift build
.build/debug/HotPot --dump        # 温度 + agent 会话 + Top CPU（先跑这个）
.build/debug/HotPot --cool-test   # 对最烫的 agent 降温 25s 再恢复，打印温度变化
.build/debug/HotPot --render      # 离屏渲染面板 PNG，不依赖屏幕录制权限
.build/debug/HotPot --demo        # 启动 GUI 并自动展开面板
```

改完代码先跑 `--dump`，确认数据层没坏，再看 UI。

## 代码约定

- **Core 层不 import SwiftUI**：`TemperatureReader` / `ProcessScanner` / `AgentRegistry` / `Cooler` 必须能脱离 UI 单测。
- 轮询在后台队列，UI 更新回 main；不要在 `scan()` 里碰 UI。
- 新增 agent 只需改 `AgentRegistry.all`，不要改聚合逻辑。
- 注释写「为什么」，尤其系统 API 的坑（见下）。
- 文档引用源码要给 `文件:行号`，改代码后同步更新 PRD。

## 三条必踩的系统 API 坑

1. `proc_listallpids` 返回**个数**不是字节数（`ProcessScanner.swift:37-38`）。按字节除会少算 4 倍。
2. `proc_pid_rusage` 的 `ri_*_time` 是 **mach absolute time**，不是纳秒（`ProcessScanner.swift:69-70`）。必须乘 `numer/denom`，否则 CPU% 小 41.67 倍。
3. `pbi_comm` 只有 15 字节，`browser_crashpad_handler` 会被截成 `browser_crashpa`（`AgentRegistry.swift:48-51`）。噪音过滤用 `crash` 不用 `crashpad`。

## 验证「降温」时看温度，不看 CPU%

单线程降到 Background QoS 后仍然显示 100% CPU，只是跑在能效核上。要证明效果：升温 40s、降温 25s 再读数。
参考数据：8 线程满载 58.1℃ → 49.1℃（25s），进程数不变。

## 造测试负载

不要拿真实 agent 试。用 `/tmp/claude` 这样的假会话脚本（脚本名就是被测指纹）：

```sh
#!/bin/sh
yes > /dev/null &
yes > /dev/null &
sleep 600        # 不要用 exec sleep，exec 会替换 shell 丢掉 argv 指纹
```

起停走 Python `start_new_session=True` + `os.killpg`，确保子进程一起清掉。

## 待办（按优先级）

1. **性能**：现在全表扫描 ~0.8s / 2s 轮询 = 40% 单核。目标 <0.15s：只对 CPU>1% 的进程读 argv、缓存 pid 表、空闲降到 5s。
2. 刘海形态（`safeAreaInsets.top > 0` 时贴边，否则菜单栏）。
3. 异常提醒（agent 连续 5 分钟 >80%）+ 残留进程提醒。
4. 规则表外置成 JSON。
5. 打包脚本（`.app` bundle + ad-hoc 签名 + Homebrew Cask）。

## 提交规范

`type: 简述`，type ∈ {feat, fix, perf, docs, chore}。
示例：`fix: 修正 rusage 时间单位换算`、`docs: 补 POC 实测数据`。

## 不要做

- 不要引入需要付费账号的依赖
- 不要联网、不要加埋点（README 承诺了纯本地）
- 不要用私有 API 之外的方式读温度导致需要 sudo（会毁掉零权限体验）
