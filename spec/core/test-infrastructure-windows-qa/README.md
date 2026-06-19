# Windows QA環境構築手順

## 目的

OribisのWindows実機QA環境を、次回以降できるだけ短時間で再構築するための手順と資材をまとめる。

対象は以下。

- Windows 10/11 実機
- Tailscale経由の疎通
- OpenSSH Serverによるリモート操作
- OribisのWindows実GUI/WDIO実行
- Babylon/VRMなどWebView2描画の実機確認

## 推奨構成

- Windows 10 22H2以上、またはWindows 11
- Tailscaleインストール済み
- OpenSSH Serverサービス有効
- Git / Node.js / pnpm / Rust / Visual Studio Build Tools C++ / tauri-driver
- Microsoft Edge WebView2 Runtime
- Edge/WebView2に合う `msedgedriver.exe`

Chromeは必須ではない。Tauri v2/WebView2のWDIOは `tauri-driver` と `msedgedriver.exe` を使う。

## ディレクトリ規約

QAマシン側は以下を標準にする。

```text
C:\oribis-qa\
  artifacts\
  tools\
    msedgedriver\
      msedgedriver.exe
  oribis\
    ...
```

WSL/開発機側の鍵は以下を推奨。

```text
~/.ssh/oribis_windows_qa
```

## 1. Tailscale確認

Windows QA側のPowerShellで確認。

```powershell
tailscale ip -4
tailscale status
```

開発機側から疎通確認。

```bash
ping <tailscale-ip>
```

SSHが未構成なら `ssh <user>@<tailscale-ip>` は失敗してよい。まずTailscale IPが見えることだけ確認する。

## 2. OpenSSH Server構築

Windows標準のOpenSSHで `sshd.exe エントリポイント BNInit が見つからない` が出る場合がある。
その場合、Windows optional capabilityの再追加だけでは直らないことがあるため、Win32-OpenSSHのインストーラ/zip版を使い、`C:\Program Files\OpenSSH` へ入れる方が安定する。

### 管理者PowerShellで実施

`scripts/setup-openssh-admin-key.ps1` を `C:\tmp\setup-openssh-admin-key.ps1` などに置き、管理者PowerShellから実行する。

```powershell
powershell -ExecutionPolicy Bypass -File C:\tmp\setup-openssh-admin-key.ps1 -PublicKey "ssh-ed25519 ... agent-shared"
```

管理者ユーザーでログインする場合、Windows OpenSSHは通常ユーザーの `~\.ssh\authorized_keys` ではなく、以下を参照する設定になっていることが多い。

```text
C:\ProgramData\ssh\administrators_authorized_keys
```

`sshd_config` に以下がある場合はこの挙動。

```text
Match Group administrators
       AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys
```

## 3. SSH接続確認

開発機側から確認。

```bash
ssh -i ~/.ssh/oribis_windows_qa -o IdentitiesOnly=yes admin@<tailscale-ip>
```

タイムアウトする場合は以下を確認する。

- `Get-Service sshd` が `Running`
- `netstat -ano | findstr ":22"` にLISTENが出る
- Windows FirewallにTCP 22許可ルールがある
- Tailscaleの対象端末がonline

## 4. Windows QAに必要なツール

最低限の確認コマンド。

```powershell
git --version
node --version
pnpm --version
rustc --version
cargo --version
tauri-driver --version
```

Visual Studio Build Tools C++が必要。Rust/TauriのWindowsビルドが通らない場合、まずC++ Build Toolsを確認する。

## 5. msedgedriver配置

Edge/WebView2のバージョンを確認する。

```powershell
(Get-Item "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe").VersionInfo.ProductVersion
```

対応する `msedgedriver.exe` を以下へ配置する。

```text
C:\oribis-qa\tools\msedgedriver\msedgedriver.exe
```

OribisのWDIO設定は以下の順で検出する。

1. `ORIBIS_MSEDGEDRIVER`
2. `C:\oribis-qa\tools\msedgedriver\msedgedriver.exe`
3. PATH上の `msedgedriver.exe`

## 6. Oribisソース配置

git cloneでもscp同期でもよい。

```text
C:\oribis-qa\oribis
```

`.git` がない転送スナップショットの場合、Windows smoke runnerは `-SkipGitUpdate` を付けて実行する。

## 7. Windows smoke / WDIO実行

WSL/開発機側から一発実行する場合は `scripts/qa/invoke-windows-qa.sh` を使う。
このラッパーは実行前にローカルの `run-windows-smoke.ps1` をWindows側へ同期するため、`.git` がない転送スナップショット環境でもrunnerだけは最新化できる。

```bash
cd /home/mnadmin/agent-projects/sysdev/sysdev-1/oribis
scripts/qa/invoke-windows-qa.sh \
  --host admin@<tailscale-ip> \
  --identity-file ~/.ssh/oribis_windows_qa \
  --skip-git-update \
  --skip-install \
  --skip-frontend-build \
  --skip-screenshot \
  --wdio-spec e2e/wdio/tests/babylon-renderer.spec.ts \
  --pull-artifacts /tmp/oribis-windows-qa-latest
```

`--pull-artifacts` を指定すると以下を開発機側へ回収する。

```text
latest-summary.json
latest-windows-smoke.zip
```

ZIPには `windows-smoke.log`, `summary.json`, `system.json`, `diagnostics/` が含まれる。
`diagnostics/` にはプロセス一覧、netstat、tasklist、GPU情報、Tailscale状態などが保存される。

代表例。

```powershell
powershell -ExecutionPolicy Bypass -File C:\oribis-qa\oribis\scripts\qa\run-windows-smoke.ps1 `
  -RepoRoot C:\oribis-qa\oribis `
  -ArtifactRoot C:\oribis-qa\artifacts `
  -SkipGitUpdate `
  -SkipInstall `
  -SkipFrontendBuild `
  -SkipScreenshot `
  -WdioSpec e2e/wdio/tests/babylon-renderer.spec.ts
```

注意点。

- Tauri debug exeは `devUrl=http://localhost:1420` を読むため、WDIO前にVite dev serverが必要。
- `run-windows-smoke.ps1` はWDIO実行時にViteを起動し、完了時に停止する。
- WDIO依存がない場合は `e2e\wdio` 配下で `pnpm install --frozen-lockfile --ignore-workspace --ignore-scripts` を実行する。
- pnpm v11のbuild script approvalで詰まるため、WDIOサブプロジェクトでは `--ignore-scripts` を使う。

## 8. 対話デスクトップでの実GUI実行

SSH経由で直接GUIを起動すると非対話セッションになり、実画面確認に失敗しやすい。
Windows実デスクトップでのGUI確認はタスクスケジューラの `/IT` を使う。

同梱資材。

- `scripts/run-oribis-visible.vbs`
- `scripts/interactive-capture.ps1`
- `scripts/run-interactive-capture-hidden.vbs`
- `scripts/register-interactive-tasks.ps1`

タスク作成例。

```powershell
powershell -ExecutionPolicy Bypass -File C:\oribis-qa\oribis\__incoming__\register-interactive-tasks.ps1
```

実行例。

```powershell
schtasks /Run /TN OribisLaunchVisible
Start-Sleep -Seconds 8
schtasks /Run /TN OribisInteractiveCaptureHidden
```

キャプチャ出力。

```text
C:\oribis-qa\artifacts\interactive-capture.png
```

開発機側へ取得。

```bash
scp -i ~/.ssh/oribis_windows_qa -o IdentitiesOnly=yes admin@<tailscale-ip>:'C:/oribis-qa/artifacts/interactive-capture.png' /tmp/oribis-win10.png
```

## 9. 今回詰まった点と対策

## 9. OpenCode QA Agent

Windows QAマシン上で、修正権限を持たない調査専用Agentを動かす場合は `opencode` を使う。
現時点の想定は OpenCode + Kimi Code OAuth 2.7。

開発機側から配置する。

```bash
cd /home/mnadmin/agent-projects/sysdev/sysdev-1/oribis
scripts/qa/setup-windows-opencode-qa-agent.sh \
  --host admin@<tailscale-ip> \
  --identity-file ~/.ssh/oribis_windows_qa
```

Windows側に以下が作成される。

```text
C:\oribis-qa\qa-agent\start-qa-opencode.ps1
C:\oribis-qa\qa-agent\check-qa-agent.ps1
C:\oribis-qa\qa-agent\guard-bin\git.cmd
C:\oribis-qa\oribis\AGENTS.md
```

QA Agentはコード修正・commit・pushを禁止する。
`start-qa-opencode.ps1` は `guard-bin\git.cmd` をPATH先頭に置くため、通常の `git commit` / `git push` はブロックされる。
`.git` が存在する環境では `pre-commit` / `pre-push` hookも配置される。

確認例。

```powershell
powershell -ExecutionPolicy Bypass -File C:\oribis-qa\qa-agent\check-qa-agent.ps1
$env:Path = "C:\oribis-qa\qa-agent\guard-bin;$env:Path"
git commit --allow-empty -m qa-guard-test
git push
```

期待値。

```text
QA Agent git guard blocked: git commit is forbidden in Windows QA environment.
QA Agent git guard blocked: git push is forbidden in Windows QA environment.
```

起動例。

```powershell
powershell -ExecutionPolicy Bypass -File C:\oribis-qa\qa-agent\start-qa-opencode.ps1
```

Kimi Code OAuthの認証が未完了の場合は、Windows実デスクトップ上でOpenCodeの認証フローを完了してから使う。

## 10. 今回詰まった点と対策

### SSH接続タイムアウト

原因候補。

- sshdサービス未起動
- Firewall未許可
- Tailscale上の別IPを見ている
- OpenSSH Server capabilityはあるがサービス設定/鍵/ACLが壊れている

対策。

- `Get-Service sshd`
- `netstat -ano | findstr ":22"`
- `Get-WinEvent -LogName System` でService Control Managerエラー確認

### sshdが1053で起動しない

`sshd.exe -d` でも無反応、または `BNInit` エラーが出る場合、Windows標準OpenSSHの破損/不整合を疑う。

対策。

- Win32-OpenSSHを `C:\Program Files\OpenSSH` に入れ直す
- `install-sshd.ps1` を `-ExecutionPolicy Bypass` で実行
- その後 `Set-Service sshd -StartupType Automatic` と `Start-Service sshd`

### 管理者ユーザーの公開鍵が効かない

原因。

- `Match Group administrators` により `C:\ProgramData\ssh\administrators_authorized_keys` を参照している。
- ACLが厳密でないとOpenSSHが鍵を拒否する。

対策。

- `scripts/setup-openssh-admin-key.ps1` を使う。

### パスが壊れる

チャット/Relayで `C:\tmp\test.ps1` が制御文字化することがある。

対策。

- PowerShellでは `Join-Path` を使う。
- コマンド貼り付けではなく `.ps1` ファイルに保存して実行する。
- パスは引用符で囲む。

### SSHからのスクリーンショットが失敗する

原因。

- SSHは非対話セッションで、`CopyFromScreen` が有効なデスクトップハンドルを取れない。

対策。

- タスクスケジューラ `/IT` で対話セッション上にキャプチャタスクを起動する。
- PowerShell窓が写り込む場合は `wscript.exe` 経由で非表示実行する。

### Tauri画面が `localhost 接続拒否` になる

原因。

- debugビルドのTauri exeは `tauri.conf.json` の `devUrl=http://localhost:1420` を読む。
- WDIO前にVite dev serverが起動していない。

対策。

- Windows smoke runnerでWDIO前に `pnpm exec vite --port 1420` を起動する。
- `http://localhost:1420/` がreadyになってからWDIOを起動する。

### msedgedriverが見つからない/バージョン不一致

原因。

- Tauri WebView2 WDIOはChromeではなくEdge/WebView2側のdriverが必要。

対策。

- Edge/WebView2のversionに合う `msedgedriver.exe` を `C:\oribis-qa\tools\msedgedriver\` に置く。

## 11. 最短チェックリスト

- [ ] Tailscale IPがonline
- [ ] `sshd` Running
- [ ] `netstat :22` LISTEN
- [ ] 開発機からSSH接続可
- [ ] Git/Node/pnpm/Rust/Build Tools/tauri-driverあり
- [ ] `msedgedriver.exe` 配置済み
- [ ] `C:\oribis-qa\oribis` にソース配置済み
- [ ] `pnpm install` 済み
- [ ] `cargo build --manifest-path src-tauri/Cargo.toml --bin oribis` PASS
- [ ] Windows smoke runnerでWDIO PASS
- [ ] 対話キャプチャで実画面確認
- [ ] OpenCode QA Agentのhealth check PASS
- [ ] QA Agentのgit commit/pushガード確認済み
