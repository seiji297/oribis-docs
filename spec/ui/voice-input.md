# Voice Input

## Overview

# oribis/voice-input — spec

## 概要
Oribisのチャット入力欄に音声入力（STT）機能を追加。Ctrl+Dキーで録音→faster-whisper-tinyによる音声認識→認識結果をinput valueに挿入する。

## アーキテクチャ

```
[React: Ctrl+D onKeyDown]
  → isRecording=true, UIインジケータ表示
  → invoke("start_recording")
      → Rust: arecord -D pulse -f S16_LE -r 16000 -c 1 /tmp/oribis_rec_{pid}.wav をspawn
[React: Ctrl+D onKeyUp / 再Ctrl+D]
  → invoke("stop_recording")
      → Rust: arecordプロセスをkill → WAVファイル読み取り
      → reqwest POST http://127.0.0.1:50033/transcribe (WAVバイト列)
      → stt_server.py: soundfile.read → faster-whisper-tiny → {"text": "..."} 返却
  → 認識テキストをchat input valueに追加
```

### コンポーネント構成
- **stt_server.py** (~60行): aiohttp HTTPサーバー (port 50033)、faster-whisper-tiny CPU/int8
- **Rust: start_recording / stop_recording**: Tauriコマンド、arecordプロセス管理
- **React: useVoiceInput hook**: Ctrl+Dハンドリング、invoke呼び出し、UIステート管理

### ポート割当
- 50033: stt_server.py（既存: 50021=VOICEVOX, 50032=Irodori-TTS と非衝突）

### 既存インフラ流用
- faster-whisper==1.1.1: discord-vc-supporter sources/.venv（インストール済み）
- モデル: ~/.cache/huggingface/hub/models--Systran--faster-whisper-tiny（キャッシュ済み）
- soundfile, numpy, aiohttp: 同venv

## AC一覧（ORIBIS-VOICE-INPUT）

- AC-1: Ctrl+D押下でarecord録音が開始され、再Ctrl+D押下で停止する（トグル方式。keyupは無視）
- AC-2: 録音停止後にstt_server.pyへWAV送信→認識テキストがchat入力欄に挿入される
- AC-3: 録音中にUIインジケータ（"Recording..." 等）が表示される
- AC-4: stt_server.py がPOST /transcribeでWAV受信→faster-whisper-tiny CPU/int8で認識→JSON返却する
- AC-5: start.sh にstt_server.py起動行が追加され、Oribis起動時に自動起動する
- AC-6: 既存チャット機能（送信、VRM表示、TTS、コンソール等）に影響がない
- AC-7: cargo test + pnpm test PASS
- AC-8: cargo tauri dev で起動後、Ctrl+D→音声入力→テキスト挿入が動作する（手動確認）
- AC-9: stt_server.py未起動時はエラーメッセージ表示（サイレント失敗ではなく明示通知）
- AC-10: IME入力中（isComposing=true）はCtrl+Dを無視する

## 制約
- 録音はarecordコマンドに委任（Rustでcpal/hound不使用）
- Rust追加dep: なし（reqwest/serde_json/tokio既存）
- 配布ビルド対応はスコープ外（dev環境動作のみ）
- STTモデル: faster-whisper-tiny CPU/int8 固定（discord-vc-supporter .venv流用）

## Implementation Notes

# oribis/voice-input — 活動ログ

## 2026-04-22 (一時停止中)

### ECC進捗

| フェーズ | 状態 |
|---------|------|
| research | DONE (research-oribis-voice-input-20260421.md) |
| planner | DONE (plan-oribis-voice-input-20260422.md) |
| tdd-guide (初回実装) | DONE — feat: 589c58c |
| codex-reviewer R1 | FAIL → 対応済み (ead5aeb) |
| codex-reviewer R2 | FAIL → 対応済み (56d4582) |
| codex-reviewer R3 | **FAIL — 未対応・一時停止** |
| DA 最終ゲート | 未着手 |

### ブランチ状態
- ブランチ: `feature/voice-input` (oribis repo)
- 最新コミット: `56d4582` fix(voice-input): Codex R2指摘対応 - keydown auto-repeat抑止
- origin push: 未実施

### 実装コミット一覧 (voice-input関連)
- `589c58c` feat(voice-input): Ctrl+D STT via arecord+stt_server.py
- `ead5aeb` fix(voice-input): Codex R1指摘対応 - useVoiceInput React hooks化 + SIGTERM WAV修正
- `56d4582` fix(voice-input): Codex R2指摘対応 - keydown auto-repeat抑止

### 実装済み内容
- `stt_server.py`: faster-whisper-tiny, port 50033, POST /transcribe
- `src-tauri/src/lib.rs`: start_recording / stop_recording Tauri commands
- `src/hooks/useVoiceInput.ts`: React hook, Ctrl+Dトグル
- `src/hooks/useVoiceInput.test.ts`: フック単体テスト
- `src/App.tsx` / `src/App.css`: voice-input UI統合
- `start.sh`: stt_server.py 自動起動行追加

## Known Issues / Backlog

# oribis/voice-input — 未解決 Issues

## OPEN: Codex R3 FAIL（一時停止理由）

### HIGH-1: 一時ファイル安全性
- 問題: `/tmp/oribis_rec_<pid>.wav` が固定予測可能パス、`O_CREAT|O_EXCL` なし
- 対応方針: Rustで `create_new(true)` による排他ファイル作成 or ランダムnonce付与
- ファイル: `src-tauri/src/lib.rs` (start_recording)

### HIGH-2: pkill -f 範囲広すぎ
- 問題: `pkill -f "stt_server.py"` が同名スクリプト全プロセスを巻き込む
- 対応方針: PIDファイル方式 (`/tmp/oribis-stt.pid`) で自プロセスのみkill
- ファイル: `start.sh`

### MEDIUM-3: venvパス ハードコード
- 問題: `start.sh` の `STT_VENV` が絶対パス固定
- 対応方針: 環境変数フォールバック `STT_VENV="${STT_VENV:-/home/.../venv}"`
- ファイル: `start.sh`

### MEDIUM-4: request.read() サイズ制限なし
- 問題: `stt_server.py` の POST ボディ読み込みに上限なし
- 対応方針: `MAX_BODY_SIZE = 10 * 1024 * 1024` (10MB) チェック追加
- ファイル: `stt_server.py`

### MEDIUM-5: App.tsx スコープ外 UI 変更混在
- 問題: Pose Debug / Motion Test / Chat タブ化等の変更が同差分に混入
- 対応方針: 要確認。スコープ外変更を別コミット分離 or 回帰テストで AC-6 担保
- ファイル: `src/App.tsx`, `src/App.css`

### LOW-6: App統合テスト不足
- 問題: useVoiceInput.test.ts はフック単体のみ。AC-9/AC-10 の画面統合未検証
- 対応方針: App レベルで voiceError 表示 / isComposing 無視 の統合テスト追加
- ファイル: `src/hooks/useVoiceInput.test.ts` or 新規テストファイル

---

## 参照

- Codex R3レポート: `docs/deliverables/codex-code-review-oribis-voice-input-r3-20260422.md`
- 実装計画: `docs/deliverables/plan-oribis-voice-input-20260422.md`
- spec: `docs/features/oribis/voice-input/spec.md`

