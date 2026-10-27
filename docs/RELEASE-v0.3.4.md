## 面板拆成两个 tab

Agent 和端口分开，列表再也不会因为端口多而变长：

- 温度读数下方加切换栏 `Agent 3` / `端口 3`，选中的一项有琥珀下划线
- Agent tab：会话列表 + 展开明细
- 端口 tab：端口 / 命令 / 运行时长 / 残留标记，底部可一键关掉残留服务
- 页头页脚仍然固定，各自内部滚动

```bash
brew update && brew upgrade --cask hotpot
```
