# DSH Menu Bar

[简体中文](README.zh-CN.md)

A native macOS menu bar app for starting and managing the DeepSeek Harness (DSH) web service.

🐋 Menu bar whale · one-click start/stop · managed DSH Runtime · local hostname · launch at login

## Features

- **One-click start / stop** — a single menu action follows the service state.
- **Managed DSH Runtime** — on the first start, the app visibly downloads and installs DSH into Application Support. Later starts run that local copy directly, without waiting for npx to download it again.
- **DSH Runtime updates** — the menu shows the installed version, checks npm for an update, and installs a new DSH version independently of app releases.
- **Proxy settings** — use macOS system HTTP proxy, direct connections, or a custom local HTTP(S) proxy. Proxy environment variables are passed to both DSH and the runtime installer.
- **Local hostname** — opens `http://deepseek.harness.localhost:3080`.
- **Trusted API host** — starts DSH with `--trusted-host deepseek.harness.localhost:3080` to prevent `/api` host-trust 403 errors.
- **Browser opening** — opens the local URL once the service is ready.
- **Port reuse** — reuses a service already listening on port 3080.
- **Launch at login** — install or remove a launchd login item from the menu.
- **Native app updates** — Sparkle checks signed GitHub Releases; updates can be checked manually from the menu.

## Build

Requires macOS 13+, Xcode Command Line Tools, and Node.js/npm for the managed DSH runtime. Releases support macOS 26 and 27.

```bash
scripts/bundle-node.sh    # optional: bundle Node only as an npx compatibility fallback
scripts/build-app.sh      # build the app bundle
open DSHMenuBar.app       # open it
```

`DSHMenuBar.app` is a menu-bar-only application: it has no Dock icon or main window. Look for the whale in the right side of the menu bar.

## Menu

| Item | Description |
|---|---|
| Start Harness / Stop Harness | One-click service control |
| Open Harness | Opens the local hostname in a browser |
| DSH Runtime | Shows its version, installation progress, and available updates |
| Configure launch command… | Use a custom DSH launch command |
| Network proxy… | Use system proxy, direct networking, or a custom HTTP(S) proxy |
| Check for updates… | Check GitHub Releases for a signed app update |
| Launch at login | Install/remove the launchd login item |

## Runtime lifecycle

On first launch, the app uses the local `npm` to download official `@deepseek-ai/dsh` into:

```text
~/Library/Application Support/DSHMenuBar/runtime
```

The menu explicitly shows that download/install state. Once installed, the app launches that local DSH copy with local `node`, so ordinary starts do not require network access or npx package downloads. Updates are downloaded to a staging directory and become active only after the download completes successfully.

This path requires a working local Node.js/npm installation (for example, Homebrew Node). The app's bundled Node is retained only as a legacy npx compatibility fallback and is not used to execute DSH native dependencies.

## Logs

- `~/Library/Logs/DSHMenuBar.log` — DSH service output
- `~/Library/Logs/DSHMenuBar-diag.log` — app diagnostics
- `~/Library/Logs/DSHMenuBar-crash.log` — crash records
- `~/Library/Logs/DSHMenuBar-runtime-install.log` — runtime download/install output

## Local hostname

DSH's DNS-rebinding protection rejects untrusted API hosts. The app declares its only local hostname with the official `--trusted-host deepseek.harness.localhost:3080` argument. Under RFC 6761, `.localhost` always resolves to the local machine.

## License

MIT. The whale icon is derived from the official DeepSeek logo ([DeepSeek-V2](https://github.com/deepseek-ai/DeepSeek-V2)) and is used only as the menu-bar icon.
