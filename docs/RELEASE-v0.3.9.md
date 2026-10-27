## 端口行可以展开看详情

点任意一行展开：

- **目录** — 进程的工作目录（`~` 缩写，只显示最后两级），一眼知道是哪个项目
- **命令** — 完整命令行（`node .../vite/bin/vite.js --port 5273`）
- **进程** — PID + 父进程（`pnpm (77241)` / `launchd (1)`）
- **监听** — `127.0.0.1:3000` / `::1:5173`，能看出是不是只绑了本机

## 能认出端口是干嘛的

行内右侧直接标服务类型，探测方式：

1. HTTP 打一次 `127.0.0.1`（`::1` 的走 IPv6 回环，vite 默认只在 IPv6 上），1 秒超时
2. 看 `Server` / `X-Powered-By` 头：Vite、Next.js、Express、Uvicorn、Flask、Gunicorn、nginx、Caddy…
3. 头是空的就翻 HTML：`/@vite/client`、`/_next/` 这些特征
4. 都没有就显示页面 `<title>`（"Video Studio"、"Netflav 数据浏览器"）
5. 错误页 / 目录列表的标题直接丢掉，不显示噪音

实测本机 6 个端口全部认出来了。

```bash
brew update && brew upgrade --cask hotpot
```
