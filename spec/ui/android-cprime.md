# Android Cprime

## Overview

# Feature Spec: Oribis Android C-Prime Remote API

**カテゴリ**: oribis  
**フィーチャー**: android-cprime  
**ステータス**: 実装完了（feat/android-cprime、DA最終ゲートGO）  
**設計書**: `docs/deliverables/design-oribis-android-cprime-20260424.md`  
**計画書**: `docs/deliverables/plan-oribis-android-cprime-api-r9-20260425.md`  
**コミット**: `6cc57ca` / `852ce31` / `6609bde`（feat/android-cprime）

---

## 概要

Oribis（Tauriデスクトップアプリ）にaxumベースのREST APIサーバーを追加し、C-Prime Android端末からWi-Fi/Tailscale経由で操作できるようにする。

## 対象ファイル

- 新規: `src-tauri/src/remote_api.rs`
- 変更: `src-tauri/src/config.rs`（AppConfig, RemoteConfig追加）
- 変更: `src-tauri/src/lib.rs`（run()のsetup内でサーバー起動）
- 変更: `src-tauri/Cargo.toml`（axum等追加）

## エンドポイント一覧

| ID | Method | Path | 機能 |
|----|--------|------|------|
| API-01 | GET | /api/health | ヘルスチェック |
| API-02 | GET | /api/state | タブ・モデル状態取得 |
| API-03a | POST | /api/tabs/{tabId}/model | モデル変更 |
| API-03b | POST | /api/tabs/{tabId}/persona | ペルソナ変更 |
| API-04 | POST | /api/tabs/{tabId}/chat | チャット送信 |

## 設定（config.toml）

```toml
[remote]
enabled = false   # default: 無効
port = 7878
bind = "127.0.0.1"
token = ""        # optional: Bearer token認証
```

## セキュリティ要件

- CORS: Tailscale IPレンジ（100.64.0.0/10）のみ許可
- 認証: token設定時はAuthorizationヘッダー必須
- Rate limit: 60req/min/クライアント
- デフォルト無効（enabled=false）

## 追加クレート

- axum 0.7
- uuid 1 (v4 feature)
- dashmap 5
- scopeguard 1
- base64 0.22（画像添付）
- subtle 2（定数時間Bearer比較）

## バックログ（Phase 2候補）

- get_or_create → get に変更（handle_set_model のruntime state管理）
- structured error type（タイムアウト検出を文字列依存から脱却）
- .json.tmp 固定名 → プロセス固有tmpファイル名
- local-brain text-only チャット: 500 → 501/422 への改善
- 環境変数スコープ制限（全vars()→必要なキーのみ）
- IPv6対応（::1 ループバック許可）Phase 2

## Implementation Notes

# 作業ログ: android-cprime

## 2026-04-25

- 設計書 `design-oribis-android-cprime-20260424.md` を元に実装計画立案
- コードベース調査完了:
  - `config.rs`: AppConfig構造体確認、RemoteConfig未実装
  - `lib.rs`: run()のsetupパターン、ChatManagerState/ProjectChatState構造、claude_chat/run_codex_process呼び出し経路確認
  - `Cargo.toml`: 既存依存確認（axum未追加）
- 実装計画書作成: `plan-oribis-android-cprime-api-20260425.md`
- feature docs作成（spec/log/issues/knowledge）
> 状態: 設計完了 / 未解決0件 / 次: tdd-guide実装

## 2026-04-25 設計レビュー（ECCチェーン）

- 計画書R7〜R9作成（画像添付機能API-04拡張を統合）
- Codex設計レビュー: R1 FAIL（HIGH×3）→ R8作成 → R2 FAIL（HIGH×2）→ DA設計ゲート条件付きGO
- DA条件3件（ConnectInfo注入・504/500分類・AC-04-18）→ R9で充足
- 最終設計書: `plan-oribis-android-cprime-api-r9-20260425.md`
> 状態: 設計ゲートGO / 未解決0件 / 次: tdd-guide実装

## 2026-04-25 実装・コードレビュー（ECCチェーン）

- tdd-guide: Phase 1〜5全フェーズ実装完了
  - axum骨格(API-01)・状態API(API-02)・タブ操作(API-03)・セキュリティ(API-05)・画像添付チャット(API-04)
  - commit: `6cc57ca`（Phase 5画像添付実装）
- Codex コードレビュー R1 FAIL: Bearer非定数時間比較(HIGH)・タブ別backend未反映(HIGH)→修正 `852ce31`
- Codex コードレビュー R2 FAIL: backend=claude時codex CLIパス使用(HIGH)・冪等WARN未実装(MEDIUM)→修正 `6609bde`
- Codex コードレビュー R3: CLIタイムアウト → Claude代替 **PASS**（MEDIUM×1, LOW×2はバックログ）
- テスト: 284テスト PASS（214 lib + 70 integration）
- DA最終ゲート: **GO**（条件なし）
- knowledge.md昇格: 4件 / spec.md更新済み / issues.md更新済み
> 状態: 完了（全AC充足）/ バックログ4件 / 次: dir-report→CRD報告

## Known Issues / Backlog

# Issues: android-cprime

## OPEN

### BACKLOG-01: handle_set_model の get_or_create 使用
**重要度**: LOW  
**内容**: 404ガード後に `get_or_create` を使っているため実害なしだが、`get` に変更すべき。  
**対応**: Phase 2リファクタ。

### BACKLOG-02: structured error type
**重要度**: LOW  
**内容**: タイムアウト検出が `e.contains("timeout")` 等の文字列依存。エラー文字列変更で黙って壊れる。  
**対応**: Phase 2で `ChatError` enum 導入。

### BACKLOG-03: local-brain text-only チャット
**重要度**: LOW  
**内容**: local-brain バックエンドへのテキストのみチャットが chat_core で Err → HTTP 500。501 or 422 が適切。  
**対応**: Phase 2で local-brain 経路を明示的にエラーハンドリング。

## CLOSED

### ISSUE-01: ChatManagerState の可視性とaxumアクセス
**重要度**: HIGH  
**解決**: `remote_api.rs` は同クレート内（lib.rs と同ファイル）のため直接参照可能。`#[cfg(feature = "tauri-backend")]` で囲む設計で実装完了。

### ISSUE-02: API-04 でのpersistent proc不使用
**重要度**: MEDIUM  
**解決**: Phase 1として chat_core() 使用で実装完了。persistent proc は Phase 2 バックログ。

### ISSUE-03: bind="0.0.0.0" のセキュリティリスク
**重要度**: MEDIUM  
**解決**: `bind != "127.0.0.1" && token.is_empty()` 時にサーバー起動拒否＋ERROR ログ実装（AC-05-8）。

### ISSUE-04: active_tab_id の取得方法未定
**重要度**: LOW  
**解決**: `null` を返す実装で初期版完成（AC-02-6充足）。

### ISSUE-05: Bearer トークン非定数時間比較（Codex指摘）
**重要度**: HIGH  
**解決**: `subtle = "2"` クレート導入、`ct_eq()` で比較（commit: `852ce31`）。

### ISSUE-06: タブ別 backend が chat 実行に未反映（Codex指摘）
**重要度**: HIGH  
**解決**: `effective_backend`/`effective_model` をruntime state → tab config の優先順で解決し、`chat_core` の `backend_override`/`model_override` に渡す（commit: `852ce31`）。

### ISSUE-07: backend=claude 時に codex CLI パス使用（Codex指摘）
**重要度**: HIGH  
**解決**: `effective_backend` で cli_path を分岐（claude→CLAUDE_PATH、codex→CODEX_PATH）（commit: `6609bde`）。

