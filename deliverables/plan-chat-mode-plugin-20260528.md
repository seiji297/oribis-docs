# チャットモードプラグイン 実施計画書 v2

**作成日**: 2026-05-28
**作成者**: SysDev-1 Worker
**ステータス**: CodexAdviser審査済み・修正反映

---

## 1. 概要

Oribisにチャットモードプラグインを追加する。3D表示やオーケストレーターPTY操作なしで、テキストチャットのみでAnimaおよび各部門Workerと対話できる機能。

**有料ビルド限定プラグイン。**

## 2. ユースケース

- 外出先でAnimaと対話（3D表示不要）
- CLIラッパー機能だけ欲しいユーザー
- オーケストレーターのPTY操作が面倒なユーザー
- カフェ等で3Dキャラ表示を避けたいユーザー
- 普段テキスト、たまに3D表示の二刀流

## 3. 機能構成

### 3.1 Animaチャット（メイン）
- **@なし**: Animaに対して送受信（anima_chatパイプライン経由）
- **@部門名**: その部門のWorkerに対して送受信（spawn_worker_with_task / anima_direct_dispatch経由）
- チャット履歴表示（プロジェクト別、バックエンド正本）
- TTS発話ON/OFF切替（既存ttsSpeak統合）

### 3.2 個別チャット（部門別）
- 各部門ごとに独立したチャットスレッド
- 部門リスト表示・切替
- Worker応答のストリーミング表示（PTY出力→イベント変換）
- dispatch id紐付けによるタスク実行状況のインライン表示

## 4. 技術設計

### 4.1 アーキテクチャ

```
ChatMode Plugin (iframe sandbox="allow-scripts")
  ↓ postMessage RPC (request_id付き)
HostAPI (oribis.ai / oribis.events / oribis.ui)
  ↓ globalBus → App.tsx subscription
App.tsx (anima_chat呼出 + state管理)
  ↓ invoke()
Tauri Backend (anima_chat / spawn_worker_with_task)
  ↓ app.emit("chat:response", {request_id, ...})
HostAPI → Plugin (イベント配送)
```

### 4.2 イベント相関設計

全チャットメッセージにrequest_idを付与:
```typescript
interface ChatRequest {
  request_id: string;      // UUID
  project_id: string;
  source_plugin_id: string; // "chat-mode" or "core"
  target: "anima" | string; // "anima" or department_id
  message: string;
}

interface ChatResponseEvent {
  request_id: string;
  project_id: string;
  source_plugin_id: string;
  status: "stream" | "end" | "error";
  content: string;
  metadata?: { affinity_delta?: number; worker_id?: string };
}
```

既存UIとの二重表示防止: source_plugin_id でフィルタリング。

### 4.3 チャット履歴

**正本: バックエンド（既存history機構）**
- プラグインisolated storageは使用しない
- `chat_mode_history(project_id, target)` コマンドで取得
- 本体チャット履歴と統合（同一project_id内で一貫）

### 4.4 TTS統合

- 既存 `ttsSpeak` を使用（プラグイン独自発話しない）
- プロジェクト別TTS設定を尊重
- lip sync / bubble表示は3D表示時のみ自動連動

### 4.5 部門Worker対応

- `spawn_worker_with_task`: 新規Worker PTY起動→タスク書き込み
- `anima_direct_dispatch`: 既存Workerへのdirect dispatch
- PTY出力をイベント変換: `worker:output:{dispatch_id}` イベント発火
- Worker pid/session ↔ dispatch_id紐付けでストリーミング表示
- 終了判定・キャンセル・複数同時dispatch識別

### 4.6 Web Remote対応

**追加必要な作業:**
1. Remote invoke dispatcher → backend command橋渡し（chat_mode_send等をallowlist追加）
2. Tauri event → WS broadcast_event 逆方向ブリッジ
3. send_chat の実際のanima_chat呼出実装
4. PTYストリーミングのWS経路確立

### 4.7 有料ビルド分離

1. manifest.yamlに `tier: "premium"` フィールド追加
2. PluginRegistryにentitlementチェック追加（scan時にtier確認）
3. 無料ビルドではpremiumプラグインのenable拒否
4. ビルドスクリプトでpremiumプラグイン同梱/除外分岐
5. UI表示制御（無料版でロックアイコン+アップグレード導線）

## 5. 前提条件（CodexAdviser指摘反映）

以下が未完成のため、チャットモード実装前に完成させる必要がある:

### 5.1 App System v2 実行基盤
- usePluginSystem.ts: settingsPanels/sidebarPanels/dockPanels/overlayWidgets が空配列固定
- PluginSandbox起動 → HostAPI接続 → UIRenderer schema反映 → イベントハンドラ配送の一連の経路
- UIRendererにチャット用コンポーネント追加（scrollable list、messageコンポーネント、markdown表示）

### 5.2 HostAPI ai.sendToAnima の実動経路
- globalBus.emit("ai:sendToAnima") のApp側購読処理
- anima_chat呼出 → 応答 → イベント返却の完全な経路確立

## 6. 実装タスク分解（修正版）

### Phase 0: 前提基盤補強（3タスク）
1. **App System v2 実行経路確立** — PluginSandbox起動、HostAPI接続、UIRenderer schema反映、イベントハンドラ配送を実動させる
2. **UIRenderer チャット用コンポーネント追加** — scrollable-list、message、markdown-text コンポーネント追加
3. **ai.sendToAnima 実動経路確立** — globalBus購読→anima_chat呼出→応答Promise返却

### Phase 1: バックエンドイベント基盤（3タスク）
4. **chat:response イベント設計+実装** — request_id付き相関イベント、anima_chatパイプライン完了時に発火
5. **Worker PTY出力イベント変換** — worker:output:{dispatch_id}イベント発火、終了判定、キャンセル
6. **chat_mode_send / chat_mode_history コマンド** — 統合送信（Anima/部門）+プロジェクト別履歴取得

### Phase 2: HostAPI拡張（2タスク）
7. **sendToAnima応答受信 + sendToDepartment新規** — Promise返却、部門指定送信、イベント購読
8. **有料entitlementチェック** — manifest tier、PluginRegistry entitlement、無料版enable拒否

### Phase 3: プラグイン本体（3タスク）
9. **manifest.yaml + プラグイン骨格** — oribis-apps/chat-mode/、capability宣言
10. **Animaチャット画面** — メッセージリスト+入力+@mention解析+TTS切替
11. **個別チャット画面** — 部門セレクタ+独立スレッド+ストリーミング表示

### Phase 4: Web Remote + テスト（2タスク）
12. **Web Remote チャット対応** — allowlist追加、逆方向ブリッジ、send_chat実装
13. **E2Eテスト** — Playwright + headless + Web Remote経由テスト

## 7. 制約・リスク

- **宣言的UIの表現力**: Phase 0-2でscrollable list等を追加するが、仮想化（大量メッセージ）はP1スコープ外
- **ストリーミング応答**: PTY出力→イベント変換の粒度とパフォーマンス
- **プラグインsandbox制約**: iframe sandbox内からの直接DOM操作不可、全てRPC経由
- **有料ビルド署名検証**: P1では簡易entitlement、本格署名検証はP2以降

## 8. 依存関係

- App System v2 プラグイン基盤（**Phase 0で補強必要**）
- HostAPI aiネームスペース（**Phase 0で実動化必要**）
- Web Remote Phase 1+2（実装済み、**Phase 4で拡張必要**）
- anima_chatパイプライン（実装済み）
- spawn_worker_with_task / anima_direct_dispatch（実装済み）

## 9. 見積り

- Phase 0: 3タスク（前提基盤補強）
- Phase 1: 3タスク（バックエンドイベント基盤）
- Phase 2: 2タスク（HostAPI拡張）
- Phase 3: 3タスク（プラグイン本体）
- Phase 4: 2タスク（Web Remote + テスト）
- **合計: 13タスク**

## 10. CodexAdviser指摘と対処

| # | 指摘 | 対処 |
|---|------|------|
| 1 | App System v2実行基盤未完成 | Phase 0 タスク1で対応 |
| 2 | sendToAnima購読処理なし | Phase 0 タスク3で対応 |
| 3 | UIRendererにチャット用コンポーネント不足 | Phase 0 タスク2で対応 |
| 4 | イベント相関設計なし | §4.2で設計追加 |
| 5 | dispatch_to_department存在しない | §4.5でspawn_worker_with_task/direct_dispatch使用に修正 |
| 6 | Web Remote対応楽観的 | §4.6で追加作業明記、Phase 4で対応 |
| 7 | 有料ビルド分離不十分 | §4.7で詳細化、Phase 2 タスク8で対応 |
| 8 | チャット履歴正本未定義 | §4.3でバックエンド正本に決定 |
| 9 | TTS統合未設計 | §4.4で既存ttsSpeak使用に決定 |
