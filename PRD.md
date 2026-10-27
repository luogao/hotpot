# HotPot · 开源版「谁在烧我的 Mac」需求文档

> 工作名 **HotPot**（火锅，双关 hot / cooking），可改。
> 目标：复刻 whoiscooking.site 的全部核心功能，开源、免费、可自编译。
> 状态：**POC 已验证通过**（2026-10-27，Mac mini M4，macOS 26.5.2）

---

## 0. 一句话

一个住在菜单栏 / 刘海的小工具：**告诉你哪个 AI agent 正在把 Mac 烤热，并把它挪到能效核降温，而不打断它的工作。**

---

## 1. 可行性结论

**能复刻，且核心技术已在本机跑通。** 原产品没有黑魔法，四个技术点全部是公开能力：

| # | 能力 | 原产品做法 | 我们的做法 | POC 状态 |
|---|------|-----------|-----------|---------|
| 1 | 读芯片温度 | 私有 IOHID API | `IOHIDEventSystemClient`（dlopen 私有符号） | ✅ 免 sudo 读到 24 个传感器 |
| 2 | 找到是哪个 agent | 进程树归并 | libproc 全表扫描 + ppid/pgid 归并 + argv 指纹 | ✅ 8 个满载子进程正确压成 1 行 785% |
| 3 | 降温 | 改线程 QoS | `taskpolicy -b -p PID` | ✅ 温度 58.1→49.1℃，任务不中断 |
| 4 | 恢复 | — | `taskpolicy -B -p PID` | ✅ 完全恢复到 55.6℃ / 778% |
| 5 | 住进刘海 | NSPanel 贴刘海 | `NSScreen.safeAreaInsets` + 无边框 NSPanel | ⚠️ 本机是 Mac mini 无刘海，走菜单栏形态 |

**唯一真正的限制**：第 1 条用了私有 API，因此**不能上 Mac App Store**，只能 GitHub 发布 + 用户自编译或下载签名包。开源项目本来就不走 App Store，这点不构成障碍。

---

## 2. POC 实测数据

### 2.1 温度读取（免 sudo）

```
$ .build/debug/WhoCooking --dump
=== 温度 ===
  芯片最高: 43.1℃ (PMU tdie11)
    PMU2 tcal  51.8℃      ← 校准参考值，需排除
    PMU tdie12  42.9℃
    PMU tdie11  42.9℃
```

- 传感器总数 24 个，命名形如 `PMU tdieN` / `PMU2 tdieN` / `PMU tcal`
- `tcal` 是校准基准（恒为 51.8℃），**必须排除**，否则读数永远是 51.8
- 全程不需要 root、不需要 entitlement

### 2.2 进程归因

构造一个假 agent 会话（1 个父 shell + 8 个 `yes` 满载子进程），结果：

```
=== Agent 会话 ===
  进程总数: 883
  🟠 Claude Code  775.1%  10 进程  running: yes, yes, yes
       子进程: yes 98% | yes 98% | yes 97% | yes 97%
  🟠 Claude Code    0.5%  6 进程  idle
  🟠 Claude Code    0.3%  26 进程  idle
```

- 10 个进程（父 + 8 个 yes + sleep）被正确压成 **一行**，CPU 正确累加到 775%
- 扫描 883 个进程 + 读 argv 耗时约 **0.8 秒**

### 2.3 降温效果（端到端，走产品代码）

| 阶段 | 芯片最高温 | agent CPU | 进程状态 |
|------|-----------|-----------|---------|
| 降温前 | 58.1℃ | 791% | 10 进程满载 |
| 降 QoS 后 25s | **49.1℃ (-9.0℃)** | 528% (-33%) | **10 进程全部存活** |
| 恢复全速 20s | 55.6℃ | 778% | 恢复满载 |

> 另一组更极端的实验（8 个进程压满 40 秒）：70.6℃ → 44.9℃（**-25.7℃**）。
> 温差取决于负载是否超订能效核数量：M4 有 4P + 6E，8 个满载线程才会被"挤"到 E 核。

**关键认知**：降温的指标是**温度/功耗**，不是 CPU%。单线程任务降到 E 核后 CPU% 仍是 100%，但芯片温度显著下降。UI 上不能拿 CPU% 当降温效果的证明。

---

## 3. 产品需求

### 3.1 目标用户

1. **AI agent 重度用户**：同时开 Claude Code / Codex / Cursor，机器发烫、风扇狂转、续航崩
2. **想看清楚"到底是谁在跑"的人**：80 个 node 进程里分不清哪个是 build、哪个是 dev server
3. **Mac mini / iMac / 外接屏用户**：原产品只做刘海，这部分人被排除，是我们的差异点

### 3.2 功能清单

#### P0（MVP 必须有）

| ID | 功能 | 验收标准 |
|----|------|---------|
| F1 | 菜单栏常驻 + 实时温度 | 显示 `62°`，颜色随温度分档（<55 绿 / <70 黄 / <85 橙 / ≥85 红），2 秒刷新 |
| F2 | 点击展开面板 | 面板显示温度、分档、传感器名、agent 列表 |
| F3 | Agent 会话归并 | 一个 agent + 它启动的所有子进程 = 一行；显示 CPU% / 进程数 / 正在跑的子进程名 |
| F4 | 单 agent 降温/恢复 | 点雪花图标 → 整棵进程树降 QoS；再点恢复 |
| F5 | 全部降温/恢复 | 顶部主按钮 |
| F6 | 权限识别 | 别的用户（sudo/root）启动的进程标记为不可降温并说明原因 |

#### P1（对齐原产品）

| ID | 功能 | 验收标准 |
|----|------|---------|
| F7 | 刘海形态 | 检测到刘海时贴刘海显示；hover 展开；无刘海自动降级为菜单栏 |
| F8 | 异常提醒 | agent 连续 5 分钟 CPU > 80% 时系统通知 |
| F9 | 残留进程提醒 | agent 主进程退出后，其子进程（dev server / 构建）仍在跑 → 提醒并提供"一并结束" |
| F10 | 支持列表 | Claude Code、Codex CLI、Gemini CLI、Cursor、Aider、Copilot CLI、Ollama、LM Studio、Xcode build、ffmpeg、Docker、浏览器 |
| F11 | 中英双语 | 跟随系统语言 |

#### P2（差异化，可选）

| ID | 功能 | 说明 |
|----|------|------|
| F12 | 温度/功耗曲线 | 记录 24 小时，看"什么时候最烫" |
| F13 | 按项目分组 | 从 cwd 推断项目名，显示"是 `/repo/foo` 在烤" |
| F14 | 降温白名单 | 指定 agent 永不降温（比如正在跑 CI） |
| F15 | 能耗排行周报 | 统计每个 agent 的累计 CPU 时间 |

### 3.3 交互稿（文字）

```
┌─────────────────────────────────┐
│  62°C  [温热]        [全部降温]  │   ← 温度主视觉 + 主操作
│  芯片最高温 · PMU tdie8          │
├─────────────────────────────────┤
│  🟠 Claude Code        785%  ❄  │
│     running: yes, yes · 10 进程 │
│  🟠 Claude Code          0%  ❄  │
│     idle · 6 进程               │
├─────────────────────────────────┤
│  882 个进程 · 0 个已降温      ⏻  │
└─────────────────────────────────┘
```

- 点雪花 = 该 agent 降温；已降温时图标变青色实心，再点恢复
- 不可降温的行整行降透明度 + 禁用点击 + tooltip 说明原因

---

## 4. 技术方案

### 4.1 架构

```
HotPot.app
├── Core（无 UI 依赖，可单测）
│   ├── TemperatureReader   读 IOHID 传感器 → 芯片最高温
│   ├── ProcessScanner      libproc 全表扫描 + rusage 差分算 CPU%
│   ├── AgentRegistry       指纹表：进程 → 是哪个 agent
│   ├── SessionAggregator   ppid 链 + pgid 兜底 → 会话归并
│   └── Cooler              调 taskpolicy 降级/恢复
└── UI
    ├── NotchPanel          贴刘海的 NSPanel（无刘海则用 NSStatusItem）
    └── PanelView           SwiftUI 面板
```

技术栈：**Swift + SwiftUI + AppKit**，Swift Package Manager 构建（不依赖 .xcodeproj，方便开源协作）。
最低支持 macOS 13（Ventura），Apple Silicon 优先。

### 4.2 关键实现与已验证的坑

#### ① 温度：IOHIDEventSystemClient

`Sources/WhoCooking/TemperatureReader.swift:30-62`

```
IOHIDEventSystemClientCreate() → CopyServices() → 遍历
  → CopyProperty(svc, "Product")      取传感器名
  → CopyEvent(svc, 15, 0, 0)          15 = kIOHIDEventTypeTemperature
  → GetFloatValue(ev, 15 << 16)       取值
```

**坑**：
- `tcal` 是校准值恒 51.8℃，必须按名字过滤，只取 `PMU tdie*` / `SOC MCPU`
- 私有符号用 `dlopen` + `dlsym` 拿，不要硬链接（符号可能被移除）
- macOS 大版本升级传感器命名会变，需要"找不到就退化到全传感器最大值"

#### ② 进程扫描：libproc

`Sources/WhoCooking/ProcessScanner.swift:35-96`

```
proc_listallpids(&pids, size)          // 全表
proc_pidinfo(PID, PROC_PIDTBSDINFO)    // ppid / pgid / uid / comm
proc_pidpath(pid, buf, 4096)           // 完整路径（comm 只有 15 字节）
proc_pid_rusage(pid, RUSAGE_INFO_V4)   // CPU 时间
sysctl(KERN_PROCARGS2)                 // argv（同用户免 root）
```

**三个实测踩到的坑**：

1. **`proc_listallpids` 返回的是个数，不是字节数**（`ProcessScanner.swift:37-38`）。按字节数除会少算 4 倍，导致只扫到 274 个进程。
2. **`rusage` 的时间单位不是纳秒，是 mach absolute time**（`ProcessScanner.swift:69-70`）。Apple Silicon 上 timebase = 125/3，直接当 ns 用会让 CPU% 小 41.67 倍（实测 300% 显示成 7.1%）。
3. **`pbi_comm` 只有 15 字节**，`browser_crashpad_handler` 会被截成 `browser_crashpa`。用整串 `crashpad` 做噪音过滤会漏，必须用 `crash`（`AgentRegistry.swift:48-51`）。

#### ③ 归因：三层兜底

`Sources/WhoCooking/AgentRegistry.swift:44-60` + `SessionAggregator.build`

1. **指纹匹配**：basename + argv 里出现 `claude` / `codex` / `cursor-agent` …
2. **去噪**：命中 `crash` / `helper` / `framework` / `xpcservice` 的直接丢弃（否则 Codex 桌面版的崩溃上报进程会被当成 Codex CLI）
3. **树归并**：先按 ppid 向上找最近的 agent 根；找不到再用 pgid 兜底（有些 agent 的子进程会被 reparent 到 launchd，ppid 断链）

#### ④ 降温：taskpolicy

`Sources/WhoCooking/Cooler.swift:22-40`

```
/usr/sbin/taskpolicy -b -p <pid>    # 降到 Background QoS → 只跑 E 核
/usr/sbin/taskpolicy -B -p <pid>    # 恢复
```

**坑**：
- 必须**逐个 pid** 调用，taskpolicy 一次只处理一个
- 只对**同 uid** 的进程有效；sudo 起的 docker / 构建会返回失败，UI 要提前标记
- 降级不继承：父进程降了，已存在的子进程不会跟着降 → 必须遍历整棵树
- QoS 是 per-thread 的，agent 后续新起的线程可能回到默认档 → 需要监听进程数变化，新 pid 自动补降（P1）

#### ⑤ 刘海

```swift
NSScreen.screens.first?.safeAreaInsets.top > 0   // 有刘海
NSScreen.auxiliaryTopLeftArea / auxiliaryTopRightArea  // 刘海的左右可用区
```
无边框 `NSPanel` + `.nonactivatingPanel` + `.statusBar` window level，贴 `screen.frame.maxY`。
**本机是 Mac mini（safeAreaInsets.top = 0），这条只能代码审查 + 找一台 MacBook 验证。**

### 4.3 性能预算

| 项 | 现状 | 目标 |
|----|------|------|
| 单次全表扫描 | ~0.8s（883 进程） | < 0.15s |
| 轮询频率 | 2s | 2s（空闲）/ 1s（面板打开时） |
| 自身 CPU 占用 | 未测 | < 1% |
| 自身内存 | 未测 | < 60MB |

**优化路径（P0 之后必做）**：0.8 秒/2 秒 = 40% 的单核占用，绝不能这样发版。方案：
1. 只对 **CPU > 1% 的进程**读 argv（大多数进程不需要）
2. 用 `proc_listpids(PROC_ALL_PIDS)` 缓存 pid 表，增量对比
3. argv 读取移到后台队列，UI 用上一帧数据
4. 空闲时降到 5 秒轮询

---

## 5. 风险与对策

| 风险 | 影响 | 对策 |
|------|------|------|
| 私有 API 被 macOS 大版本移除 | 温度读不到 | 抽象成 provider，退化到 `powermetrics`（需 sudo）或隐藏温度只显示 agent；社区可快速修 |
| 不能上架 App Store | 分发受限 | 开源 + GitHub Release + Homebrew Cask，本来就不打算上架 |
| 用户不敢装 | 采纳率低 | 全开源、可自编译、Release 提供公证签名版；README 明确说明不联网、不上传数据 |
| 归因误报 | 体验崩 | 规则表外置成 JSON，用户可自定义；提供"这不是 agent"反馈入口 |
| 降温被误解为"变卡" | 差评 | UI 明确写"任务继续跑，只是慢一点"，提供一键恢复；默认不自动降温 |
| 无刘海机型 | 功能缺失 | 菜单栏形态做成一等公民，刘海只是锦上添花 |
| 与原产品同名/抄袭争议 | 法务 | 换名（HotPot）、独立实现、README 注明灵感来源、MIT 协议 |

---

## 6. 里程碑

| 阶段 | 内容 | 工作量（单人） |
|------|------|--------------|
| **M0 · POC** | 温度 + 归因 + 降温 + 面板渲染 | ✅ 已完成（约 3 小时） |
| **M1 · 可用版** | 修性能（<0.15s/次）、菜单栏常驻、面板交互、开机自启、偏好设置 | 2 天 |
| **M2 · 对齐原产品** | 刘海形态、异常提醒、残留进程提醒、支持列表补全 | 2 天 |
| **M3 · 发布** | 图标、README、GitHub Actions 构建、Homebrew Cask、公证脚本 | 1 天 |
| **M4 · 差异化** | 温度曲线、按项目分组、周报 | 2 天 |

M1 结束即可自用；M3 结束可发布。

---

## 7. 开源与分发

- **协议**：MIT
- **仓库结构**：`Sources/`（代码）+ `docs/`（本文件）+ `scripts/`（打包/公证）+ `README.md`
- **构建**：`swift build -c release`，`scripts/bundle.sh` 组装 `.app`（Info.plist + icon + ad-hoc 签名）
- **分发**：GitHub Release 提供通用二进制（arm64 + x86_64），Homebrew Cask 一行安装
- **隐私**：纯本地，不联网，不上报任何数据（README 首屏声明）
- **命名**：不要叫 WhoIsCooking（避免商标冲突），README 里写 "inspired by WhoIsCooking"

---

## 8. 与原产品的差异

| 维度 | 原产品 | HotPot |
|------|--------|--------|
| 价格 | $5 买断 | 免费开源 |
| 刘海 | 只支持刘海机型 | 刘海 + 菜单栏双形态，Mac mini/iMac 可用 |
| 扩展性 | 固定支持列表 | 规则表可编辑，用户可加自己的 agent |
| 透明度 | 闭源 | 全开源，可审计 |
| 数据 | 未知 | 明确不联网 |

---

## 9. 待决问题

1. 刘海面板的 hover 触发：轮询鼠标位置（60Hz）还是 `NSTrackingArea`？前者稳但费电，需实测。
2. 是否要 privileged helper 来降温 sudo 起的进程？（要多一次授权弹窗，可能不值）
3. 提醒的阈值：5 分钟 / 80% 是原产品的设定，是否可调？
4. 是否支持 Intel Mac？（温度传感器完全不同，建议首版只支持 Apple Silicon）
