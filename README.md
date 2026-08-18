# DSH Menu Bar

原生 macOS 菜单栏应用，用于一键托管运行 DeepSeek Harness（DSH）Web 服务。

🐋 菜单栏鲸鱼图标 · 一键启动/停止 · 内置 Node.js 运行时 · 自动打开本地域名 · 开机自启

## 功能

- **一键启动 / 停止** Harness（单个按钮随状态切换）
- **优先本机 Node.js** —— 若登录 shell 中的 `node`/`npx` 可用则优先使用；否则自动回退内置运行时
- **网络代理** —— 可跟随 macOS 系统 HTTP 代理、直连或配置本地 HTTP(S) 代理；自动注入 DSH 标准代理变量
- **本地域名访问** —— 自动打开 http://deepseek.harness.localhost:3080
- **自动打开浏览器** —— 服务就绪后自动打开
- **端口复用** —— 已有实例时自动复用，不重复启动
- **登录时自动启动**（菜单勾选，基于 launchd）
- **原生自动更新** —— 使用 Sparkle 检查 GitHub Releases，菜单中可手动检查更新
- **进程树清理** —— 停止时递归终止 npx→node 整个进程树

## 构建

要求 macOS 13+ 与 Xcode Command Line Tools；发布版支持 macOS 26/27。

```bash
scripts/bundle-node.sh    # 下载并内置 Node.js 运行时（可选，跳过则回退系统 npx）
scripts/build-app.sh      # 构建 App
open DSHMenuBar.app       # 打开
```

构建产物 DSHMenuBar.app 为纯菜单栏应用（无 Dock 图标、无窗口），启动后看屏幕右上角菜单栏的鲸鱼图标。

## 使用

| 菜单项 | 说明 |
|---|---|
| ▶️ 启动 Harness / ⏹ 停止 Harness | 随状态切换的一键开关 |
| 打开 Harness | 浏览器打开本地域名 |
| 配置启动命令… | 自定义 DSH 启动命令 |
| 网络代理… | 跟随系统代理、直连或配置本地 HTTP(S) 代理；重启 Harness 后生效 |
| 检查更新… | 从 GitHub Releases 检查并安装已签名的新版 App |
| 登录时自动启动 | 安装/卸载 launchd 登录项 |
| 退出 | 停止服务并退出 |

日志：
- ~/Library/Logs/DSHMenuBar.log —— DSH 服务日志
- ~/Library/Logs/DSHMenuBar-diag.log —— App 诊断日志
- ~/Library/Logs/DSHMenuBar-crash.log —— 崩溃记录

## 工作原理

### 内置 Node 运行时

App 内打包官方 Node.js 二进制（Contents/Resources/node-runtime/），启动 DSH 时优先用内置 Node 执行 npx-cli.js，用户无需装 Node。若未打包则回退系统 npx。

### *.localhost 域名

DSH 的 /api 信任围栏（防 DNS rebinding）默认只信任 localhost / 127.x.x.x / [::1]，会拒绝 *.localhost 子域。App 启动时自动应用幂等补丁（scripts/patch-trust.sh），把 isLoopbackHostname 扩展为也接受 *.localhost。依据 RFC 6761，.localhost 永远只解析到本机，攻击者无法伪造，不引入新攻击面。DSH 升级后下次启动自动重打。

## 目录结构

```
.
├── Package.swift                  # SwiftPM 清单
├── Sources/DSHMenuBar/main.swift  # 全部 App 逻辑
├── Resources/
│   ├── deepseek-whale.png         # 菜单栏鲸鱼图标
│   └── deepseek-logo.svg          # 图标来源（DeepSeek 官方 logo）
├── scripts/
│   ├── build-app.sh               # 构建 .app bundle
│   ├── bundle-node.sh             # 下载/内置 Node 运行时
│   ├── patch-trust.sh             # *.localhost 信任补丁
│   ├── sign-sparkle-framework.sh  # 发布签名 Sparkle 更新框架
│   └── render-icon.swift          # 从 logo 生成鲸鱼 PNG
└── LICENSE / README.md
```

## 许可

MIT。鲸鱼图标源自 DeepSeek 官方 logo（[DeepSeek-V2](https://github.com/deepseek-ai/DeepSeek-V2)），仅用于菜单栏图标展示。
