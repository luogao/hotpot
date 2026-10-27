# POC 实测报告

所有数据在本机实测，非估算。环境：**Mac mini M4（4P + 6E），macOS 26.5.2，Swift 6.3.3**。
日期：2026-10-27。

---

## 实验一：免 sudo 读芯片温度

方法：`IOHIDEventSystemClient` 私有符号（dlopen），遍历所有 HID 服务，取 `Product` 属性和 type=15 的浮点值。

结果：**24 个传感器可读，无需 root / entitlement**。

```
PMU2 tcal  51.8℃      ← 校准基准，恒定值，必须排除
PMU tcal   51.8℃
PMU tdie11 42.9℃
PMU tdie12 42.9℃
PMU tdie8  41.5℃
```

结论：
- 命名形如 `PMU tdieN` / `PMU2 tdieN`（CPU 裸片）、`PMU tdevN`（电压域）、`NAND CH0 temp`
- `tcal` 恒为 51.8℃，不排除会导致读数永远是 51.8
- 芯片最高温取 `PMU* tdie*` 的最大值

---

## 实验二：降 QoS 对进程树的影响

方法：1 个父进程 + 3 个 CPU-bound 子进程，分四阶段采样瞬时 CPU%。

| 阶段 | 总 CPU% |
|------|---------|
| 基线 | 107% |
| 只降父进程 `taskpolicy -b -p <parent>` | 102% |
| 整棵树逐个降 | 83% |
| 逐个 `-B` 恢复 | 107% |

结论：
- **降级不继承**：父进程降了，已存在的子进程不受影响 → 必须遍历整棵树
- 恢复可完全回到基线
- 单线程进程降级后仍接近 100%（E 核跑满），CPU% 不是有效指标

---

## 实验三：8 线程满载 40 秒的温度曲线

方法：8 个 CPU-bound 进程（超订 6 个能效核），40s 升温 → 整组降 QoS → 40s → 恢复 → 20s。
温度取 `PMU tdie*` 最大值，每核占用用 `psutil.cpu_percent(percpu=True)`。

| 阶段 | 芯片最高温 | 每核占用（10 逻辑核） |
|------|-----------|---------------------|
| 空闲 | 41.6℃ | 28 21 16 9 7 5 5 3 5 3 |
| 满载 40s | **70.6℃** | 91 90 87 79 52 53 100 100 100 100 |
| 降 QoS 后 40s | **44.9℃** | 100 100 100 100 100 100 5 4 3 3 |
| 恢复后 20s | 70.6℃ | 87 85 82 78 52 49 100 100 100 100 |

**关键结果：-25.7℃，任务全程存活。**

注：降级后前 6 个逻辑核 100%、后 4 个空闲，说明降级后的线程全部落在 6 个能效核上，4 个性能核空转。

---

## 实验四：端到端（走产品代码）

方法：假 agent 会话 = `/tmp/claude`（shell，名字即指纹）+ 8 个 `yes` 子进程。
用 `WhoCooking --cool-test`：识别 → 归并 → 降温 → 25s 后读数 → 恢复。

```
=== 降温前 ===
  [before] 最高温 58.1℃ | Claude Code 791% (10 进程)
  已降级 10/10 个进程
=== 降级后 25s ===
  [cooled] 最高温 49.1℃ | Claude Code 528% (10 进程)
=== 已恢复全速 ===
  [restored] 最高温 55.6℃ | Claude Code 778% (10 进程)
```

| 指标 | 前 | 后 | 变化 |
|------|----|----|------|
| 芯片温度 | 58.1℃ | 49.1℃ | **-9.0℃** |
| agent CPU | 791% | 528% | -33% |
| 进程数 | 10 | 10 | 0（全部存活） |
| 恢复后 | — | 55.6℃ / 778% | 回到基线 |

25 秒内 -9℃，低于实验三的 -25.7℃，因为降温时间更短（实验三是 40s）且起始温度更低。

---

## 实验五：归因正确性

真实环境（883 个进程）下：

```
🟠 Claude Code  775.1%  10 进程  running: yes, yes, yes
     子进程: yes 98% | yes 98% | yes 97% | yes 97%
🟠 Claude Code    0.5%   6 进程  idle
🟠 Claude Code    0.3%  26 进程  idle
🎬 ffmpeg         0.0%   1 进程  idle
```

- 10 个进程正确压成一行，CPU 累加准确
- 误报清理过程：初版把 `Codex.app/Contents/Frameworks/.../browser_crashpad_handler` 识别成 Codex CLI（6 个假阳性），加噪音词后清零

### 误报根因

`proc_bsdinfo.pbi_comm` 只有 **15 字节**，`browser_crashpad_handler` 被截断成 `browser_crashpa` —— 用 `crashpad` 做过滤词匹配不上，必须用 `crash`。

---

## 性能实测

| 项 | 数值 |
|----|------|
| 全表扫描 883 进程 | ~0.8 s |
| 单次 `--dump` 总耗时 | 1.86 s（含 1s 采样间隔） |

**0.8s / 2s 轮询 = 约 40% 单核占用，不可接受。** 优化方向见 PRD §4.3。

---

## 复现命令

```bash
swift build
.build/debug/HotPot --dump
.build/debug/HotPot --cool-test
```

造负载（Python，避免 shell 后台限制）：

```python
p = subprocess.Popen(["/tmp/claude"], start_new_session=True)
os.killpg(p.pid, signal.SIGKILL)   # 清理时连子进程一起
```
