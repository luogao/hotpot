## 资源看板

面板页脚新增图表按钮（右键菜单也有「资源看板…」），打开 640×760 的独立窗口。

四个窗口期：1h / 24h / 7d / 30d，默认 24h。

- **数字卡** — CPU 总时长 / 峰值温度 / 活跃 agent
- **CPU 时间分布** — 前 6 个 agent 的横向条形，按累计 CPU 秒排序
- **温度曲线** — 和上面共用时间轴，带 55/70/85 档位参考线
- **端口占用** — 窗口内出现过的端口，按累计时长排序

### 数据怎么来的

面板开着 5 秒采一次，关着 30 秒一次，写进本地 SQLite：
`~/Library/Application Support/HotPot/metrics.sqlite`

CPU 记的是**累计秒数**不是瞬时百分比——一次 build 跑 8 秒就消失，两秒采样会漏；累计值可以精确 SUM 出「今天 Claude Code 烧了 3.2 小时 CPU」。

原始数据留 48 小时，按小时聚合留 90 天，端口快照留 7 天。全部本地，不上传。

设计说明和取舍记录见 `docs/DASHBOARD.md`。

```bash
brew update && brew upgrade --cask hotpot
```
