# Autotest

## Overview

# oribis/autotest — spec

## 概要
Oribis (Tauri v2 Rust backend) の `chat_core` 関数を対象にした自動テスト群。
AC-2/E-1〜E-4 の受入条件を CI 1発 PASS で検証可能にする。

## AC一覧
- AC-2: fake_claude(ok) → chat_core が Ok("pong"含む) を返す
- E-1: 存在しないCLIパス → Err（spawn失敗 or CLI不在）
- E-2: ORIBIS_TIMEOUT_MS=100 + 10秒sleep fake_claude → Err("timeout"含む)
- E-3: fake_claude exit 1 → Err("status" or "exited"含む)
- E-4: AtomicBool compare_exchange — 2回目は Err を返す

## アーキテクチャ
- `src-tauri/src/lib.rs`: `chat_core` を `pub async fn` として抽出（Tauri State 非依存）
- `src-tauri/src/bin/fake_claude.rs`: フェイク Claude CLI（FAKE_CLAUDE_MODE env: ok/slow/fail）
- `src-tauri/tests/autotest.rs`: integration tests 5件

## 実行環境
- Windows MSVC cargo.exe（WSL2上からクロス実行）
- Linux cargo は webkit2gtk/libgtk-3-dev 不足で Tauri コンパイル不可

## CLIフラグ仕様（BL-8検証結果）
- `build_claude_command` は `-p`, `--verbose`, `--input-format stream-json`, `--output-format stream-json` を使用
  - `-p` なしでは `--input-format`/`--output-format` が無効化される（Claude CLI v2.1.63仕様）
  - `--verbose` は `-p` + `--output-format stream-json` の組み合わせで必須（なしだとexit 1）
- system prompt注入: **CliFlag（`--system-prompt`）が唯一有効な方式**
  - StreamJsonLine（stdin system行注入）: tool定義を認識しないためtool_use不発火
  - `--system-prompt` フラグが正しい（`--system` は誤り）

## バックログ（Phase 2）
- B-16 (P1): claude_chat Tauri State 経由排他制御テスト（mock_builder 必要）
- B-17 (P2): RunGuard RAII 解除テスト
- B-18 (P3): fake_claude stdin 堅牢化（read_to_string → BufRead::lines）
- B-19 (P3): chat_core envs API 整理（allowlist型など）

## Implementation Notes

# oribis/autotest — 実装ログ

## 2026-04-20: ORIBIS-AUTOTEST-IMPL

### 実装内容
- `chat_core` を `pub async fn` として抽出（envs: HashMap param追加）
- `src/bin/fake_claude.rs` 新規作成（ok/slow/fail モード）
- `tests/autotest.rs` 5テスト追加
- Codex r1 MEDIUM: ChatState.running を非公開に戻した

### テスト結果
```
running 5 tests
test test_e4_concurrent_exclusion ... ok
test test_e1_cli_not_found ... ok
test test_e3_nonzero_exit ... ok
test test_ac2_chat_success ... ok
test test_e2_timeout ... ok
test result: ok. 5 passed; 0 failed; 0 ignored
```

### DA最終ゲート
- 判定: 条件付きGO
- MEDIUM #1/B-16: claude_chat 排他制御 E2E → Phase 2 P1
- MEDIUM #2/B-17: RunGuard RAII テスト → Phase 2 P2
- LOW #3/B-18: fake_claude stdin 堅牢化 → Phase 2 P3
- LOW #4/B-19: envs API 整理 → Phase 2 P3

### commit
- oribis repo: 357c5bd (feat(autotest): AC-2/E-1〜E-4 自動テスト実装)

## 2026-04-20: ORIBIS-BL8-REAL-CLI-VERIFY

### 実装内容
- `build_claude_command`: `-p`/`--verbose` 追加（必須フラグ）、`--system` → `--system-prompt` 修正
- `tests/autotest.rs`: TEST-A6cアサーション修正 + BL8テスト4件追加（計29テスト）

### 重要発見
- StreamJsonLine（stdin system行注入）: Claude CLI v2.1.63ではtool定義認識不可 → tool_use不発火
- CliFlag（`--system-prompt`）: tool_use発火確認 → **Oribisのデフォルト注入方式はCliFlag推奨**
- `-p` + `--output-format stream-json` には `--verbose` も必須（なしだとexit 1）

### テスト結果
```
回帰: 29件全PASS (既存25 + BL8ユニット4)
実CLI (REAL_CLAUDE_BIN=C:\Users\admin\.local\bin\claude.exe):
  BL8-3 (StreamJsonLine): PASS (tool_use不発火 = 期待動作)
  BL8-4 (CliFlag): PASS (tool_use発火確認)
```

### DA最終ゲート
- 判定: 条件付きGO
- MEDIUM/B-20: BL8-4に validate_control_avatar_payload アサーション追加 → Phase 2 P2
- LOW/B-21: --verbose 設計文書反映 → Phase 2 P3

### commit
- oribis repo: a8f462e (fix(bl8): add -p/--verbose flags and --system-prompt, add real CLI integration tests)

## Known Issues / Backlog

# oribis/autotest — issues

## OPEN（Phase 2 バックログ）

### B-16 (P1) — claude_chat Tauri State 経由排他制御テスト
- 現状: E-4 が AtomicBool 単体テストのみ。claude_chat 経由の排他制御未検証
- 対処: Tauri mock_builder 利用が必要。Phase 2 最初のスプリントで消化
- Codex r2 MEDIUM #1

### B-17 (P2) — RunGuard RAII 解除テスト
- 現状: RunGuard による AtomicBool reset が panic 時も動作することを検証していない
- 対処: std::panic::catch_unwind + RunGuard 組み合わせテスト。Phase 2
- Codex r2 MEDIUM #2

### B-18 (P3) — fake_claude stdin 堅牢化
- 現状: read_to_string でブロック。parent が stdin を閉じない異常系でデッドロックリスク
- 対処: BufRead::lines に変更してタイムアウト対応。Phase 2
- Codex r1 LOW #1

### B-19 (P3) — chat_core envs API 整理
- 現状: HashMap<String,String> が任意env変数を全て受け入れる（意図しない注入リスク）
- 対処: allowlist 型または特定フィールド struct に変更。Phase 2
- Codex r2 LOW #4

### B-20 (P2) — BL8-AC4: BL8-4テストにvalidate_control_avatar_payload通過アサーション追加
- 現状: BL8-4（CliFlag実CLIテスト）でtool_use発火確認済みだが、validate_control_avatar_payload呼び出しアサーションがない
- 対処: BL8-4テストに `validate_control_avatar_payload(input).is_ok()` アサーション追加
- 出典: Codex code review MEDIUM #1 / DA最終ゲート条件

### B-21 (P3) — --verbose フラグの設計文書反映
- 現状: `-p` + `--output-format stream-json` には `--verbose` も必須（CLI v2.1.63固有）だが設計書に未記載
- 対処: plan-oribis-bl8.md・spec.md に `--verbose` 必須の旨を追記
- 出典: Codex code review LOW #2 / DA最終ゲート条件

## CLOSED

### MEDIUM #1 (r1) — ChatState.running pub 公開 → FIXED
- tdd-guide が pub にした。Codex r1 指摘で即修正（非公開に戻した）

