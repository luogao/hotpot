# 资源看板（Dashboard）

记录「哪个 agent / 进程 / 端口在烧这台机器」，回答 Activity Monitor 回答不了的问题：过去 24 小时是谁把温度拉起来的。

- 状态：v1 已实现（0.5.0）
- 入口：设置齿轮旁的数据图标 → 独立窗口 640×760
- 存储：`~/Library/Application Support/HotPot/metrics.sqlite`

## 一、非目标

明确不做的，避免后面反复讨论：

1. **不做全量进程统计**。每秒几百个进程写库会写放大，而且 99% 是噪音。只记 agent 会话维度。
2. **不做实时秒级曲线**。面板本身已经是实时的，看板的价值在历史。
3. **不上报**。数据库纯本地，没有任何网络请求。
4. **不做自定义指标**。指标集合固定，不开放配置。

## 二、数据模型

三张表 + 一张元信息表。SQLite 用系统自带 `libsqlite3`，不引入依赖。

```sql
-- 每次采样，每个活跃 agent 一行
CREATE TABLE samples (
  ts          INTEGER NOT NULL,   -- unix 秒
  agent       TEXT    NOT NULL,   -- AgentDef.id，如 "claude"
  cpu_seconds REAL    NOT NULL,   -- 本采样区间内消耗的 CPU 秒
  mem_mb      REAL    NOT NULL,   -- 采样时刻常驻内存
  procs       INTEGER NOT NULL    -- 会话内进程数
);
CREATE INDEX idx_samples_ts    ON samples(ts);
CREATE INDEX idx_samples_agent ON samples(agent, ts);

-- 全局温度，一次采样一行（不按 agent 重复）
CREATE TABLE temps (
  ts      INTEGER PRIMARY KEY,
  celsius REAL NOT NULL
);

-- 端口快照，跟随端口扫描（60 秒一次）
CREATE TABLE ports (
  ts      INTEGER NOT NULL,
  port    INTEGER NOT NULL,
  command TEXT    NOT NULL,
  pid     INTEGER NOT NULL,
  cwd     TEXT
);
CREATE INDEX idx_ports_ts ON ports(ts);

-- 小时聚合：2 天前的原始数据 rollup 进来，原始行随后删除
CREATE TABLE samples_hourly (
  hour        INTEGER NOT NULL,   -- 该小时的起点 unix 秒
  agent       TEXT    NOT NULL,
  cpu_seconds REAL    NOT NULL,
  procs_peak  INTEGER NOT NULL,
  PRIMARY KEY (hour, agent)
);

CREATE TABLE meta (k TEXT PRIMARY KEY, v TEXT NOT NULL);
```

### 为什么 CPU 存「秒」不存「百分比」

瞬时百分比是相对值：一次 build 跑 8 秒就消失，两秒采样很可能漏掉，而它实际吃满了 8 秒 8 核。

采样时按 `cpuPercent / 100 × interval` 折算成 CPU 秒累加，查询时直接 `SUM()` 就是「今天 Claude Code 烧了 3.2 小时 CPU」。这个值单调、可加、可跨窗口期聚合，百分比做不到。

代价：`cpuPercent` 本身是两次 scan 的瞬时值，折算有误差。采样越密误差越小（5 秒档约 ±10%，30 秒档约 ±25%）。看板看的是量级和排序，不追求精确计费。

## 三、采样策略

| 状态 | 间隔 | 触发点 |
|---|---|---|
| 面板打开 | 5 秒 | `AppModel.tick()` 的 `needScan` |
| 面板关闭 | 30 秒 | 同上，`tickCount % 15` |
| 端口 | 60 秒 | `needPorts` |

一天写入量估算（面板关着为主）：

- samples：4 个 agent × 2880 次 ≈ 11.5k 行
- temps：2880 行
- ports：1440 行

一天不到 2 万行，SQLite 无压力，文件约 2–4 MB/月。

写入放在后台串行队列，和扫描同一个 `queue`，不阻塞主线程。批量提交（一次采样一个事务）。

## 四、窗口期与聚合

四档，默认 **24 小时**。

| 窗口 | 时间粒度 | 用途 |
|---|---|---|
| 1 小时 | 原始采样 | 刚才谁在跑 |
| 24 小时 | 原始采样 | 今天谁烧得多（默认） |
| 7 天 | 按小时 rollup | 本周模式 |
| 30 天 | 按小时 rollup | 长期趋势 |

rollup 由 `MetricsStore.rollup()` 在启动时和每天 03:00 执行：把 2 天前的原始数据按小时聚合进 `samples_hourly`，然后删除原始行。

保留期：原始 48 小时，小时聚合 90 天。

因为 `cpu_seconds` 可加，rollup 就是 `GROUP BY strftime('%Y-%m-%d %H', ts), agent` 求和，没有精度损失。

## 五、UI 结构

独立窗口 640×760，和设置页同尺寸、同色板（`Theme.bg` / `Theme.ink`）。

```
┌ 资源看板                                    1h  24h  7d  30d ┐
│                                                              │
│  6.4 小时          74℃            7 个                       │
│  CPU 总时长        峰值温度        活跃 agent                 │
│                                                              │
│  CPU 时间分布                                                │
│  claude   ████████████████████████  3.2h                     │
│  codex    ████████████              1.6h                     │
│  ffmpeg   ██████                    0.8h                     │
│                                                              │
│  温度                                                         │
│  ╭─────────────────────────────────────────────────╮         │
│  │        ╱╲      ╱╲                               │         │
│  │   ╱╲  ╱  ╲    ╱  ╲    ╱╲                        │         │
│  ╰─────────────────────────────────────────────────╯         │
│   00:00        08:00        16:00        24:00               │
│                                                              │
│  端口                                                         │
│  :5173  vite        38 分钟                                   │
│  :3000  node        2 小时 14 分                              │
└──────────────────────────────────────────────────────────────┘
```

三块内容：

1. **数字卡** — CPU 总时长 / 峰值温度 / 活跃 agent 数
2. **CPU 时间分布** — 前 6 个 agent 的横向条形，长度按窗口内累计 CPU 秒排序
3. **温度曲线** — 窗口内温度折线，与上图的横向时间轴对齐
4. **端口** — 窗口内出现过的端口，按累计占用时长排序

图表不用 Swift Charts：默认样式（白底、网格、系统蓝）和现有极简风格冲突，手绘 `Path` + `Rectangle` 更省事，也避免 macOS 版本差异。

## 六、隐私

- 只写本机文件，路径在 `Application Support` 下
- 端口记录 `cwd` 用于识别项目，只存路径字符串，不读文件内容
- 没有任何出网请求（`ServiceProbe` 只打 `127.0.0.1` / `[::1]`）
- 删除：退出 app 不删数据；设置页提供「清除历史」

## 七、取舍记录

| 决策 | 选择 | 为什么 |
|---|---|---|
| 存储 | SQLite | 系统自带；`SUM`/`GROUP BY` 直接算聚合；JSON 追加日志查询要全量扫 |
| 粒度 | agent 会话 | 进程级噪音大；用户的问题是「谁在烧」，不是「第 4231 号进程在烧」 |
| 指标 | CPU 秒 | 可加、可跨窗口聚合；百分比不可加 |
| 图表 | 手绘 | 和控制面板视觉统一，避免引入 Swift Charts 的系统观感 |
| 入口 | 独立窗口 | 340 宽放不下 3 张图 + 明细 |
| 默认窗口 | 24 小时 | 1 小时看不出模式，7 天数据太稀 |
