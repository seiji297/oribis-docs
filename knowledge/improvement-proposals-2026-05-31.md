# Oribis 改善案メモ（2026-05-31）

調査対象: `sysdev-1/oribis/`
調査者: SysDev DIR

---

## 1. パフォーマンス

### WebGL コンテキスト最適化
- Three.js レンダラーに `powerPreference: "high-performance"` を明示設定
- 未使用 VRM テクスチャの即時解放（メモリリーク防止）

### Anima キャッシュ圧縮
- `fastembed` ベクトルキャッシュを `bincode` + `zstd` で圧縮
- SSD 書き込み量削減、起動時間短縮

### Tauri WebView メモリ
- `src/App.tsx`（263KB）の不要イベントリスナー整理
- `data-tauri-drag-region` 外のリスナーが増殖している可能性

---

## 2. DX（開発者体験）

### App.tsx 分割（最重要・P0）
- 現状: 263KB の単一ファイル
- 影響: 可読性・テスト・HMR 全てに悪影響
- 案: チャット / ターミナル / アバター / 設定 をページ単位でコード分割

### Rust 側構造体化（P0）
- `too_many_arguments` 抑制が 5 箇所以上（`lib.rs`, `pty_commands.rs` 等）
- CLI 引数・PTY 起動パラメータを構造体に集約

### 非同期 Mutex 移行
- `await_holding_lock` 抑制箇所を `tokio::sync::Mutex` へ移行
- 対象: `lib.rs`, `tts.rs`, `json_log.rs`

---

## 3. アーキテクチャ

### ローカル LLM 統合準備
- `src-tauri/src/lib.rs:1629` に `dead_code` のローカル LLM モジュールあり
- `llama.cpp` または `ollama` 連携を有効化

### リズム機能の方針決定
- `src/components/AvatarViewer.tsx:572`「リズム機能一時無効化（コード保持）」
- 復帰 or 削除の明確な方針が必要

### MCP サーバーの引数整理
- `src-tauri/src/mcp/server.rs:313`
- `AuditEntry` 直接受け渡しへのリファクタリング

---

## 4. 品質・テスト

### E2E 自動化強化
- `wdio` テストにアバター表示・音声再生の smoke を追加

### Rust テスト拡充
- `cargo-tarpaulin` 導入でカバレッジ可視化

### TypeScript 厳格化
- `tsconfig` `strict: true` + `noImplicitAny` の残対応

---

## 5. 機能拡張

### Discord Bot パッケージ統合
- `packages/discord-bot` と `src-tauri/src/discord/` の重複整理

### macOS 対応加速
- README に「予定」のまま
- `raw-window-handle` + `winit` の macOS ビルド検証を開始

---

## 優先度まとめ

| 優先度 | 項目 | 根拠 |
|--------|------|------|
| **P0** | `App.tsx` 分割 | 263KB は保守不可能 |
| **P0** | Rust 構造体化 | `too_many_arguments` = 設計臭 |
| **P1** | Anima キャッシュ圧縮 | SSD 寿命・起動時間直結 |
| **P1** | 非同期 Mutex 移行 | デッドリスク軽減 |
| **P2** | ローカル LLM 統合 | 差別化要素 |
| **P2** | macOS 対応 | 市場拡大 |

---

## 関連ファイル

- `src/App.tsx`（263KB・肥大化）
- `src/components/AvatarViewer.tsx:572`（リズム機能）
- `src-tauri/src/lib.rs`（TODO 多数）
- `src-tauri/src/tts.rs`
- `src-tauri/src/mcp/server.rs:313`
- `src-tauri/src/pty_commands.rs`
- `packages/discord-bot/`

---

## 備考

- 現在の TODO/FIXME 総数: TypeScript 側 18 件、Rust 側 26 件
- `onboarding-fixes.md` との整合: オンボード関連は既に `develop` ブランチで対応済み（`e557eef`）
