## 去掉面板顶部的三角箭头

那个三角不是我们画的，是 `NSPopover` 系统的锚点箭头，没有 API 能关掉。

改成 borderless `NSPanel`：

- 没有箭头，没有系统圆角，圆角和边框全由 PanelView 自己画
- 贴在菜单栏图标正下方，左右钳进屏幕可见区
- 点面板外或按 Esc 收起（原来 popover 的 transient 行为）
- 点状态栏图标不重复开关

顺带修了 NSPanel 初始化时被 `NSHostingController` 压成 0×0 的问题（内容尺寸现在显式给定）。

## 渐隐更明显

底部遮罩从「渐变到纯底色」改成「半透明 veil」：内容被压暗到 12% 亮度但仍然隐约可见，一眼能看出下面还有东西。

```bash
brew update && brew upgrade --cask hotpot
```
