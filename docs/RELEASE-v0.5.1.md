## 补测试 + 修一个误识别

### 修复：Claude 桌面端被当成 Claude Code

排除规则之前只比对「可执行名 + 参数」，而 `Claude.app` 的包名只在完整路径里，
进程名是 `Claude`、参数为空 —— 于是 Claude 桌面端会被算进 Claude Code 的会话里。

现在排除规则比对完整路径。测试直接抓到的这个问题。

### 测试

- `swift test` — 14 个用例，覆盖 agent 识别（精确 bin、噪声排除、IDE 排除）、会话聚合（父子归并、排序）、看板存储（CPU 秒累加、窗口期、rollup、端口计数）
- `HotPot --e2e` — 无窗口无权限自检：进程扫描、会话聚合、SQLite 读写、面板/设置页/看板三个视图能不能建
- `./scripts/check.sh` — 编译 + 单测 + e2e，一条命令
- GitHub Actions 跑同样三步

```bash
brew update && brew upgrade --cask hotpot
```
