# Namedpipe

## Overview

# Oribis Windows Named Pipe IPC (TASK-6-NAMEDPIPE)

## 概要
外部プロセスからOribisへJSON形式でメッセージを送るための Windows Named Pipe IPCチャネル。

## 実装済み機能
- Windows: `\\.\pipe\oribis` サーバー起動（`#[cfg(windows)]`ガード）
- 非Windows: no-opスタブ（API surface統一）
- `ORIBIS_PIPE_NAME` env varでパイプ名変更可能
- 受信メッセージ: NDJSON形式（改行区切りJSON）
- `PipeMessage { msg_type, payload }` 型
- `first_pipe_instance(true)` でシングルサーバー保証

## ファイル構成
- `src-tauri/src/named_pipe.rs` - Named Pipe IPC実装
- `src-tauri/src/lib.rs` - setup()フックでパイプサーバー起動
- `src-tauri/Cargo.toml` - tauri-backend featureをoptional化
- `src-tauri/build.rs` - feature gated tauri_build::build()
- `src-tauri/src/main.rs` - feature guard追加

## API
```rust
pub const DEFAULT_PIPE_NAME: &str = r"\\.\pipe\oribis";
pub struct PipeConfig { pub pipe_name: String }
pub struct PipeMessage { pub msg_type: String, pub payload: serde_json::Value }
pub fn get_pipe_name() -> String  // env var or default
pub async fn start_pipe_server(config: &PipeConfig) -> Result<(), String>
pub async fn start_pipe_server_with_tx(config: &PipeConfig, tx: Sender<PipeMessage>) -> Result<(), String>
pub async fn pipe_client_send(pipe_name: &str, message: &PipeMessage) -> Result<(), String>
```

## テスト
- cargo test --no-default-features: 48 PASS（うちTASK-6: 8件）
- Windows専用: test_6_w1_pipe_round_trip（#[cfg(windows)]）

## バックログ（TASK-7）
1. build.rs CARGO_FEATURE_*コメント追加（Rust公式doc参照）
2. setup() startup success通知（oneshot channel）
3. test_6_w1 sleep(100ms) → readiness channel（Windows CI）

## Implementation Notes

# TASK-6-NAMEDPIPE 作業ログ

## 2026-04-21

### ECCフロー完了
- planner → codex-reviewer(design) r6 PASS → DA設計ゲート条件付きPASS
- tdd-guide → codex-reviewer(code) r1-r9 → DA最終ゲート GO
- oribis main commit: 521a33c（feature/task-6-namedpipe merge）

### コミット履歴（oribis）
- f86a048: feat(named-pipe): initial implementation
- 41361e6: fix(build): tauri optional feature
- 6654517: test: fix env var race condition
- 168ad1a: fix: r1 findings
- 4a7f222: fix: r2 findings
- b4c81b5: fix: r3 findings (first_pipe_instance + w1 test)
- 3b4e02a: fix: r4 LOW-4 I/O error logging
- b0fa1b7: fix: r5 HIGH-1 empty pipe name validation
- 3d74e4d: fix: r6 HIGH-2 PID-based pipe name + MEDIUM-4 prefix check
- 815d5d7: fix: r7 MEDIUM-2 fallback on invalid prefix
- 3fdc00b: fix: r8 MEDIUM-2 env var save/restore + LOW-3 doc

### run-codex-reviewer.sh fix
codeモードのBASE_BRANCH..HEAD diff取得を修正（unstaged-onlyから branch diff へ）

### 主な知見
- `#[cfg(feature)]` はbuild scriptでも有効（Rust仕様通り）
- tauri-backend optional依存 → `CARGO_FEATURE_*` env var方式は使用不可（コンパイルエラー）
- setup() fire-and-forget は設計上の判断（Tauri hookが同期的のため）

## Known Issues / Backlog

# TASK-6-NAMEDPIPE 既知課題・バックログ

## バックログ（TASK-7行き）

### B-1: build.rs Rustドキュメント参照コメント追加
- 経緯: Codex r4-r9で`#[cfg(feature)]`の有効性について繰り返し指摘
- 対応: Rust公式ドキュメントへの参照コメントをbuild.rsに追加して誤解を防ぐ
- 優先度: LOW

### B-2: setup() startup success通知
- 経緯: Codex r5-r9で指摘。pipe server起動失敗がアプリ起動失敗にならない
- 対応: oneshot channelで起動成功/失敗をsetup hookに通知する仕組みを追加
- 優先度: MEDIUM

### B-3: test_6_w1のsleep(100ms)をreadiness channelに置き換え
- 経緯: Codex r5-r9で指摘。CI/低速環境でflaky
- 対応: Windows CI環境でのみ対応可能。serverがready後にシグナルを送るoneshot channel
- 優先度: MEDIUM（Windows CI導入時）

## スコープ外（設計時除外）
- Unix/macOSソケット実装（FUTURE-CROSS-PLATFORM）
- Tauri→クライアント方向push（FUTURE-BIDIRECTIONAL）
- Claude CLI daemon化（FUTURE-DAEMON）
- パイプアクセス権限設定（Security Descriptor）

