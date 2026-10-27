看见谁在烧你的 Mac，并把它降到能效核——不打断它的工作。

## 这个版本新增

- **中英双语**：跟随系统语言
- **规则表外置 JSON**：`~/Library/Application Support/HotPot/rules.json`
  首次启动自动生成，可自己加 agent、加白名单端口、改预警阈值。
  JSON 改坏不会让 app 崩，会自动备份成 `rules.broken-<时间戳>.json` 并回退默认。
- **右键菜单**：开机自启（默认关闭，从菜单开）、编辑规则、退出
- **连续满载预警**：会话连续 5 分钟超过 200% CPU，行内标红并显示已持续多久
- **残留 dev server**：终端关了但 `npm run dev` 还在占端口时，面板底部列出端口，可一键关闭

## 安装

```bash
brew tap luogao/tap
brew trust luogao/tap
brew install --cask hotpot
```

或手动：

```bash
curl -L -o HotPot.zip https://github.com/luogao/hotpot/releases/download/v0.2.0/HotPot-0.2.0.zip
ditto -x -k HotPot.zip .
cp -R HotPot.app /Applications/
xattr -d com.apple.quarantine /Applications/HotPot.app
open /Applications/HotPot.app
```

## 说明

- 包是 ad-hoc 签名，没有 Apple 开发者公证。首次打开若被拦，右键 →「打开」。
- 只支持 Apple Silicon + macOS 13+。
- 读温度用的是 IOHID 私有 API，不上 App Store，完全本地、不联网。
- 本机是 Mac mini（无刘海），所以刘海形态还没做。
