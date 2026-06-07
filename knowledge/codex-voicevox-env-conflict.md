# Codex Backend × VOICEVOX CORE 環境変数競合

## 概要

VOICEVOX CORE 内蔵後、codex backend（Node.js ランタイム）が異常終了し、AI 応答が `“(no response)”` になる不具合。

## 症状

- WDIO E2E テスト `T-W-P3` で AI 応答が `“(no response)”`
- `projects.json` chatHistory に記録:
  - `“Error: codex app-server closed during initialize”`
  - `“Error: Project path is empty”`
- 手動で `codex exec` を実行すると正常に動作

## 根本原因（2重）

### 1. 設定不備（表面原因）

`projects.json` の `model` が `“claude-sonnet-4-6”`（Claude モデル）になっていた。

codex backend に Claude モデル名を渡すと、codex CLI が即座にエラー終了 → stdout 空 → `“(no response)”`。

### 2. ライブラリ競合（根本原因）

oribis バイナリが **VOICEVOX CORE のネイティブライブラリ（`libvoicevox_core.so` 等）と動的リンク**している。

子プロセス（codex = Node.js）を `std::process::Command` で起動すると、親プロセス（oribis）の環境変数・ライブラリパスが継承される。

結果:
- `LD_LIBRARY_PATH` に VOICEVOX CORE のパスが含まれる
- Node.js が誤った ONNX Runtime / OpenJTalk ライブラリを読み込む
- Node.js ランタイムがセグメンテーションフォルト or 無言終了

```
oribis (VOICEVOX COREリンク済)
  └─ spawn(codex app-server)
       └─ Node.js ← LD_LIBRARY_PATHから誤った.soを読み込む ← クラッシュ
```

## 影響範囲

| 項目 | 内容 |
|------|------|
| 発生条件 | VOICEVOX CORE 内蔵後 + codex backend 使用時 |
| 再現性 | 100%（環境変数が継承されるため） |
| 影響機能 | AI チャット（codex backend 経由）、TTS |
| 非影響 | claude backend、local backend |

## 対応

### 即時対応（設定修正）

`projects.json` の `model` を codex 有効モデルに変更:

```json
{
  "model": "gpt-5.4"
}
```

### 恒久対応（コード修正）

`src-tauri/src/lib.rs` の `run_codex_process` / `CodexAppServerProc::spawn_proc` で、子プロセス起動前に **環境変数を完全にクリア**:

```rust
// VOICEVOX CORE等のネイティブライブラリがcodex（Node.js）と競合するのを防ぐ
// oribis自体がVOICEVOX COREライブラリとリンクされているため、子プロセスに完全に隔離
cmd.env_clear();
if let Ok(home) = std::env::var("HOME") {
    cmd.env("HOME", home);
}
if let Ok(path) = std::env::var("PATH") {
    cmd.env("PATH", path);
}
```

最小限の環境変数（`HOME`, `PATH`）のみを引き継ぎ、競合するライブラリパスは隔離。

## 再発防止

1. **テスト自動化**: WDIO E2E で AI 応答が `“(no response)”` にならないことを検証
2. **モデル名検証**: 設定ファイル読み込み時に backend と model の組み合わせを検証
3. **子プロセス隔離原則**: ネイティブライブラリをリンクする親プロセスから、インタプリタ系子プロセスを起動する際は常に `env_clear()` を検討

## 関連ファイル

- `src-tauri/src/lib.rs` — `run_codex_process`, `CodexAppServerProc::spawn_proc`
- `e2e/wdio/tests/producer-tasks.spec.ts` — T-W-P3 テスト
- `~/Documents/oribis/projects.json` — プロジェクト設定

## 関連コミット

- `src-tauri/src/lib.rs` — 子プロセス環境隔離
- `e2e/wdio/tests/producer-tasks.spec.ts` — TTS 再生確認追加
