# 環境分離設計: AI駆動開発PC(Linux) + 人間操作PC(Windows)

**作成日**: 2026-05-21
**更新日**: 2026-05-21
**ステータス**: 方針確定（移行未実施）

## 背景

現状、1台のPC（Windows + WSL2）でAI駆動開発（Claude Code常駐・ECC自走）と人間操作（クリエイティブ作業・Unity等）が同居。リソース競合・用途混在の課題あり。2台目PC（GPU搭載）を活用し、役割分離する。

## 確定構成

### 2台目PC → AI駆動開発専用機

| 項目 | 内容 |
|------|------|
| OS | Ubuntu（ネイティブLinux） |
| 主用途 | AI駆動開発（Claude Code常駐・ECC自走） |
| 常駐プロセス | tmux + Claude Code（SysDev/AFD Worker）、Discord Relay Bot |
| Oribis | 開発専用（cargo build/test, pnpm tauri dev, typecheck） |
| GPU用途 | Oribis開発時描画、ローカルLLM（将来） |
| 人間操作頻度 | 低（設定変更・緊急対応時のみ） |

### 現PC → 人間操作メイン

| 項目 | 内容 |
|------|------|
| OS | Windows（WSL2は当面残す。2台目完全安定後に削除） |
| 主用途 | Unity + クリエイティブ + Oribisビルド版運用 |
| Oribisビルド | git pull → pnpm tauri build → .msi/.exe生成（Node/Rust/pnpm残す） |
| GPU用途 | Unity Editor、ゲームプレイ、クリエイティブツール |
| Unity | AFD開発用Unity Editor（Windows） |

## データ同期

| 対象 | 方法 |
|------|------|
| ソースコード | git（GitHub）経由 |
| 大容量アセット | Shareフォルダ（ファイルサーバー） |
| Oribisビルド成果物 | 現PCで直接ビルド（git pull → pnpm tauri build） |

## 移行フロー

### 役割分担

| 担当 | 作業内容 |
|------|----------|
| **Producer（物理/認証）** | Ubuntuインストール、GPUドライバ、ネットワーク接続、Shareフォルダ物理設定、GitHub SSH key登録（ブラウザ）、Claude Code初回認証、Discord Bot Token入力 |
| **Claude（自動化）** | apt基盤パッケージ、rustup/Node/pnpm、Tauri依存、tmux/Claude Code環境、SSH key生成、リポジトリclone、Oribisビルド確認、Discord Relay Bot設定、ECC自走構築、systemdサービス |

### Phase 0: 棚卸し（現PC・WSL2内）

**担当: Claude（自動実行可能）**
- 全リポジトリ git status確認（未commit/未push洗い出し）
- Secrets一覧化: SSH keys, GPG keys, GitHub token, Discord Bot token, .env各種, Claude Code設定
- 常駐プロセス一覧: tmuxセッション構成, Discord Relay Bot, supporter-watch等
- rustup / node / pnpm バージョン記録
- cargo install済みツール一覧記録

**担当: Producer**
- WSL export取得（wsl --export Ubuntu backup.tar）→ 外部保存

### Phase 1: 2台目PC構築

**担当: Producer（30分〜1時間）**
1. Ubuntu ネイティブインストール（USB起動メディア→インストール）
2. GPU ドライバインストール（NVIDIA: `ubuntu-drivers autoinstall`）
3. ネットワーク接続（LAN/Wi-Fi設定）
4. Claude Code初回認証（API key入力）

**担当: Claude（自動・2〜3時間）**
5. apt基盤パッケージ一括インストール（build-essential, git, curl, pkg-config等）
6. rustup + Rust toolchainインストール
7. Node.js + pnpmインストール
8. Tauri v2 Linux依存パッケージ（libwebkit2gtk-4.1-dev, libgtk-3-dev, libayatana-appindicator3-dev等）
9. tmux環境構築
10. SSH key生成（ssh-keygen）→ 公開鍵をProducerに渡す

**担当: Producer（10分）**
11. GitHub SSH key登録（ブラウザでSettings → SSH keys → 公開鍵追加）
12. Discord Bot Token入力（環境変数設定）

**担当: Claude（自動・続き）**
13. agent-projects/ 全リポジトリclone（GitHub経由）
14. Oribis動作確認: cargo build → cargo test → pnpm install → pnpm typecheck → pnpm tauri dev
15. Discord Relay Bot設定・起動確認
16. ECC自走フロー動作確認（テストエピック実行）
17. tmux自動起動設定（systemd service）

### Phase 2: Shareフォルダ設定

**担当: Producer**
1. ファイルサーバーにShare設定（物理/権限）

**担当: Claude**
2. 2台目PCからShareフォルダマウント設定（/etc/fstab or systemd mount）
3. 両PCからアクセス確認
4. 大容量アセット同期運用ルール決定

### Phase 3: 並行運用（数日〜1週間）

**担当: Claude**
1. 2台目でOribis開発・AI自走を実運用
2. 安定性モニタリング（常駐プロセス死活、ビルド成功率）

**担当: Producer**
3. 現PCでgit pull → pnpm tauri build → ビルド版動作確認
4. 問題報告（問題発生時は現PC WSL2にフォールバック可能）

### Phase 4: 現PC WSL2削除（完全安定後・急がない）

**担当: Claude**
1. Secrets再発行リスト作成

**担当: Producer**
2. Secrets再発行実行（GitHub token, Bot token等）→ 旧環境分は失効
3. WSL2削除（`wsl --unregister Ubuntu`）
4. 現PCにOribisビルド版インストール・動作確認

## 準備チェックリスト

### 2台目PC側
- [ ] Ubuntu ネイティブインストール済み
- [ ] GPU ドライバ（ネイティブLinux用）
- [ ] ネットワーク接続（GitHub/npm/crates.io アクセス可）
- [ ] Shareフォルダへのアクセス確認

### 現PC側（棚卸し）
- [ ] 全リポジトリ git push 完了（未push差分ゼロ）
- [ ] WSL export バックアップ取得
- [ ] Secrets一覧メモ（SSH key, GPG key, GitHub PAT, Discord Bot Token, Claude Code API key, .env各種）
- [ ] tmuxセッション構成メモ
- [ ] rustup / node / pnpm バージョンメモ
- [ ] cargo install済みツール一覧

### アカウント・サービス側
- [ ] GitHub SSH key追加（2台目用に新key）
- [ ] Claude Code ライセンス/API key（2台目用）
- [ ] Discord Bot Token（同一token共用 or 再発行判断）

### ファイルサーバー側
- [ ] Shareフォルダ作成・権限設定
- [ ] 両PCからの読み書きテスト

## Codex Adviser指摘事項

### 高優先度
1. Windows実行環境差分 — WebView2/GPUドライバ/VC++ Runtime差分 → 現PCでビルドするため軽減済み
2. Tauriビルド再現性 — Node/Rust/pnpmバージョン固定必要
3. Secrets/APIキー管理 — 移行時に旧WSL内秘匿情報残存リスク → Phase 4でSecrets再発行・旧環境失効
4. 大容量アセット — Shareフォルダ(ファイルサーバー)で対応
5. Unity配置 — 現PC(Windows)で確定

### 中優先度
6. WSL2削除前バックアップ — WSL export + Secrets一覧化で対応
7. 現PCからの緊急修正 — Node/Rust残すため軽微修正は可能
8. Discord Relay/ECC常駐の運用 — 2台目集約、監視・自動復旧検討
9. Git運用衝突 — ブランチ戦略維持（既存フロー踏襲）
10. GPU搭載PCのWSL2制約 — ネイティブLinuxのため該当なし

## Producer原文
- 「Oribisの開発環境（現状SYSDEV相当）のみ別環境移行、でいい気がする」
- 「今の環境はWLS削除してWindows1本化。OribisもWindows運用（ビルド版）」
- 「UnityはWindows。ファイル移送→Shareフォルダ（ファイルサーバー）」
- 「Oribisビルド→おすすめの方法」→ C案採用（現PCでgit pull → pnpm tauri build）
- 「WLS２削除は追々でいい。完全に安定してから」
- 「2台目は基本Linux想定」
