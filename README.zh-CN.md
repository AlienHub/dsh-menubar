# DSH Menu Bar

[English](README.md)

原生 macOS 菜单栏应用，用于一键托管运行 DeepSeek Harness（DSH）Web 服务。

🐋 菜单栏鲸鱼图标 · 一键启动/停止 · 自动下载/更新 DSH Runtime · 自动打开本地域名 · 开机自启

## 功能

- **一键启动 / 停止** Harness（单个按钮随状态切换）
- **DSH Runtime 管理** —— 首次启动清晰显示下载/安装过程，安装到 App Support；后续以本机 Node 直接运行，不再等待 npx 下载
- **DSH Runtime 更新** —— 菜单显示已安装版本，可检查并下载安装新版 DSH，不需要等待 App 发版
- **网络代理** —— 可跟随 macOS 系统 HTTP 代理、直连或配置本地 HTTP(S) 代理；自动注入 DSH 标准代理变量
- **本地域名访问** —— 自动打开 `http://deepseek.harness.localhost:3080`
- **API Host 信任** —— 默认通过 DSH 的 `--trusted-host` 声明本地域名，避免 `/api` 请求被 403 拒绝
- **自动打开浏览器** —— 服务就绪后自动打开
- **端口复用** —— 已有实例时自动复用，不重复启动
- **登录时自动启动**（菜单勾选，基于 launchd）
- **原生自动更新** —— 使用 Sparkle 检查 GitHub Releases，菜单中可手动检查更新

## 构建

要求 macOS 13+、Xcode Command Line Tools，以及用于托管 DSH Runtime 的 Node.js/npm；发布版支持 macOS 26/27。

```bash
scripts/bundle-node.sh    # 可选：仅作为 npx 兼容回退而内置 Node.js
scripts/build-app.sh      # 构建 App
open DSHMenuBar.app       # 打开
```

构建产物 `DSHMenuBar.app` 为纯菜单栏应用（无 Dock 图标、无窗口），启动后看屏幕右上角菜单栏的鲸鱼图标。

## 菜单

| 菜单项 | 说明 |
|---|---|
| 启动 Harness / 停止 Harness | 一键控制服务 |
| 打开 Harness | 浏览器打开本地域名 |
| DSH Runtime | 显示当前版本、下载/安装状态和可用更新 |
| 配置启动命令… | 自定义 DSH 启动命令 |
| 网络代理… | 跟随系统代理、直连或配置本地 HTTP(S) 代理 |
| 检查更新… | 从 GitHub Releases 检查已签名的新版 App |
| 登录时自动启动 | 安装/卸载 launchd 登录项 |

## Runtime 生命周期

首次启动时，App 使用本机的 `npm` 下载官方 `@deepseek-ai/dsh` 到：

```text
~/Library/Application Support/DSHMenuBar/runtime
```

菜单会明确显示“正在下载并安装”。安装完成后，App 用本机 `node` 直接执行该副本；常规启动不需要网络，也不会再通过 npx 拉取包。更新会先下载到临时目录，只有成功完成后才切换到新版本。

这要求本机安装可用的 Node.js/npm（例如 Homebrew 的 Node）。App 内保留 Node 仅作旧版 npx 兼容回退，不用来执行 DSH 原生依赖。

## 日志

- `~/Library/Logs/DSHMenuBar.log` —— DSH 服务日志
- `~/Library/Logs/DSHMenuBar-diag.log` —— App 诊断日志
- `~/Library/Logs/DSHMenuBar-crash.log` —— 崩溃记录
- `~/Library/Logs/DSHMenuBar-runtime-install.log` —— DSH 下载/安装日志

## 本地域名

DSH 的 DNS rebinding 防护会拒绝未知 API 域名。App 默认以 DSH 官方的 `--trusted-host deepseek.harness.localhost:3080` 参数声明唯一使用的本地域名；依据 RFC 6761，`.localhost` 永远只解析到本机。

## 许可

MIT。鲸鱼图标源自 DeepSeek 官方 logo（[DeepSeek-V2](https://github.com/deepseek-ai/DeepSeek-V2)），仅用于菜单栏图标展示。
