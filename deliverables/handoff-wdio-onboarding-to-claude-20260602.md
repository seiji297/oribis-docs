# 引き継ぎドキュメント: WDIO オンボーディング自動化テスト

**作成日時**: 2026-06-02
**引き継ぎ元**: sysdev-1 (OpenCode)
**引き継ぎ先**: Claude
**状態**: 中断・引き継ぎ

---

## 背景

OribisプロジェクトのWDIO（実機GUI自動化テスト）に関する一連の修正・テスト作業中。

### 既存の修正（完了済み・push済み）

1. **エラーメッセージ可視化** (`src-tauri/src/lib.rs`, `src/App.tsx`)
   - `anima_chat`: backend_type空時 → Configエラー「バックエンドが設定されていません。オンボーディングを完了してください。」
   - `run_claude_process`: claude_path空時 → NotFoundエラー「claude CLI not found in PATH」
   - `App.tsx`: `get_tts_settings` nullチェック追加

2. **WDIO WSLg GPU対応** (`scripts/run-wdio-tests.sh`, `e2e/wdio/wdio.conf.ts`)
   - `SKIP_XVFB=1` でXvfbスキップ、WSLg GPU使用可能
   - `WEBKIT_DISABLE_COMPOSITING_MODE` を条件付き化
   - テスト実行: `SKIP_XVFB=1 bash scripts/run-wdio-tests.sh`

3. **run-wdio-tests.sh にテスト設定自動注入**（最新コミット）
   - `--clean` 後のテスト用に `/tmp/oribis-test-home-$$` を自動作成
   - `config.toml`, `projects.json`, `home.toml` を生成
   - ただし不完全でアプリが正常初期化しない

---

## 現在の問題

### 重大: チャット送信後にAI推論が返ってこない（固まる）

**症状**: 
- `--clean` 後、オンボーディング完了 → チャット送信 → ずっとローディング状態
- AI応答が返ってこない
- これは **デグレ（回帰バグ）** の可能性あり

**原因（推測）**:
- `anima_chat` コマンド内の `resolve_project_backend` が空文字を返す
- 空文字の backend_type で `ChatCoreAdapter::new()` が呼ばれる
- `run_claude_process` 内で claude CLI が見つからない/失敗
- エラーが適切に返されていないか、フロントでキャッチされていない

**関連ファイル**:
- `src-tauri/src/lib.rs:6826` - `resolve_project_backend(&project_id)` で空文字チェック追加済み
- `src-tauri/src/lib.rs:1317` - `run_claude_process` で claude_path 空チェック（NotFound返却）
- `src-tauri/src/error.rs` - Internal/Command エラーシリアライズ（変更なし・原本維持）

---

## 残タスク

### タスク1: チャット固まりバグの原因特定・修正（優先度: P0）

**問題**: チャット送信後、AI推論が返ってこず固まる

**調査対象**:
1. `src-tauri/src/lib.rs:6799` `anima_chat` 関数
   - `backend_type` が空でも早期リターンするが、その後のフローで問題がある可能性
   - `execute_pipeline` の戻り値処理
   - `PipelineResponse::Error` や `Err(e)` のハンドリング

2. `src-tauri/src/anima/pipeline.rs:481` `execute_chat_pipeline`
   - `adapter.send_message(prompt).await` のエラーハンドリング
   - `Err(e)` → `PipelineResponse::Error(e.to_string())` に変換されるが、
     その後の処理でフロントに正しく届かない可能性

3. `src-tauri/src/cli_adapters.rs:476` `ChatCoreAdapter::send_message`
   - `run_claude_process` のエラー: `anyhow::anyhow!(e)` でラップ
   - `pipeline.rs:641` で `Err(e) => Ok(PipelineResponse::Error(e.to_string()))`
   - これが `anima_chat` の `Err(e) => Err(OribisError::Command(e.to_string()))` で返る

4. `src/App.tsx` フロントエンド側
   - `anima_chat` のエラーハンドリング
   - エラー時にローディング状態を解除していない可能性

**確認すべきこと**:
- `backend_type` が空の場合、早期リターンは動作しているか
- 空でない場合、`ChatCoreAdapter` の処理でどこで止まるか
- エラーがフロントに届いているか、それとも無限待ちになっているか

### タスク2: WDIO オンボーディング自動化テスト実装（優先度: P1）

**要件**:
- `--clean` 後の純粋な状態からWDIOテストを開始
- オンボーディング画面を自動操作して完了させる
- オンボーディング完了後、チャット送信→AI応答→TTS再生をテスト

**変更対象ファイル**:
- `e2e/wdio/tests/tts-chat-e2e.spec.ts`（修正）
- `e2e/wdio/tests/onboarding.spec.ts`（新規・任意）

**実装方針（案）**:
1. オンボーディング自動化:
   - スプラッシュ画面が表示される → `close_splashscreen` invoke
   - オンボーディング画面（ホームフォルダ入力）→ テスト用パス入力
   - 「次へ」クリック → CLI選択 → 「完了」クリック
   - **注意**: CLI認証ダイアログはモックまたはスキップが必要

2. 代替案: テスト前にセットアップ完了させる
   - `run-wdio-tests.sh` でテスト用設定を完全に作成
   - `projects.json` に `backend`, `path`, `model` を正しく設定
   - オンボーディングをスキップしてメイン画面からテスト開始

3. チャット→TTSフロー:
   - チャットテキストエリアを特定（セレクタ: `textarea`, `[placeholder*="message"]` 等）
   - テキスト入力 → 送信ボタンクリック
   - AI応答メッセージ表示確認（セレクタ: `.v2-msg.v2-msg-ai` 等）
   - TTSイベント発火確認（`tts-start-*`, `tts-end-*`）

**既存テストファイルの問題**:
- `tts-voice-playback.spec.ts` - TypeScriptコンパイルエラー（`unknown` 型）
- これは事前存在の問題、今回の修正とは無関係

---

## 既知のファイル変更（最新コミットまで）

### oribis リポジトリ（developブランチ）

1. `src-tauri/src/lib.rs` - anima_chatの空backendチェック、run_claude_processエラー修正
2. `src/App.tsx` - TTS settings nullチェック
3. `src-tauri/src/error.rs` - 変更なし（原本維持）
4. `scripts/run-wdio-tests.sh` - SKIP_XVFB対応、テスト設定自動注入
5. `e2e/wdio/wdio.conf.ts` - WEBKIT_DISABLE_COMPOSITING_MODE条件付き化

### テスト実行コマンド

```bash
cd ~/agent-projects/sysdev/sysdev-1/oribis

# WSLg GPUでWDIOテスト実行
SKIP_XVFB=1 bash scripts/run-wdio-tests.sh

# 通常の開発サーバ起動
bash start.sh

# --clean後に起動
bash start.sh --clean
```

---

## 技術的メモ

### Anima Chat フロー

```
App.tsx (invoke "anima_chat")
  → src-tauri/src/lib.rs::anima_chat()
    → resolve_project_backend(project_id) → backend_type
    → if backend_type.is_empty() → Err(Config("バックエンドが設定されていません..."))
    → match backend_type:
      "local" → OpenClawChatAdapter
      "codex" → CodexChatAdapter
      "opencode" → OpenCodeChatAdapter
      _ → ChatCoreAdapter::new()  ← 空文字の場合ここに落ちる（現在は早期リターンで防いでいる）
    → execute_pipeline(config, event, adapter)
      → src-tauri/src/anima/pipeline.rs::execute_chat_pipeline()
        → adapter.send_message(prompt)
          → ChatCoreAdapter::send_message()
            → run_claude_process()  ← ここで固まる可能性
```

### TTS フロー

```
App.tsx (invoke "tts_speak")
  → src-tauri/src/lib.rs::tts_speak()
    → tts::fetch_and_play_chunks_with_preset()
      → tts::fetch_tts_wav_for_preset()
      → tts::play_audio_subprocess() / play_audio_subprocess_inner()
        → WSL: play_audio_wsl_inner() (powershell.exe SoundPlayer)
        → Linux: rodio → ffplay fallback
```

### エラーハンドリング

- `OribisError::Internal` → フロントに "内部エラーが発生しました"（詳細隠蔽）
- `OribisError::Config` → フロントに実メッセージ表示（"バックエンドが設定されていません..."）
- `OribisError::NotFound` → フロントに実メッセージ表示（"claude CLI not found..."）
- `OribisError::Command` → フロントに "コマンド実行中にエラーが発生しました"（詳細隠蔽）

---

## 次のアクション（Claudeへの依頼）

1. **P0**: チャット固まりバグの原因特定と修正
   - `anima_chat` → `execute_pipeline` → `ChatCoreAdapter` → `run_claude_process` のフローを追跡
   - どこで無限待ち/エラー隠蔽が起こっているか特定
   - 最小限の修正で解決

2. **P1**: WDIOテストの完成
   - `--clean` 後の状態でテストが動作するようにする
   - オンボーディング自動化またはセットアップ完了
   - チャット送信 → AI応答 → TTS再生 のE2Eフロー完成

3. **テスト確認**:
   - `cargo test --lib` で Rust テスト PASS
   - `pnpm test --run` で vitest PASS
   - `SKIP_XVFB=1 bash scripts/run-wdio-tests.sh` で WDIO テスト PASS

---

## 連絡先

- Producer: Discord #sysdev-relay (1485222475317907557)
- このドキュメントに関する質問はProducer経由で

---

**補足**: この引き継ぎ時点で、oribisリポジトリは develop ブランチにあり、すべての変更は push 済みです。
