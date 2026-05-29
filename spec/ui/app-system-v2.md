# Oribis App System v2 — 設計書

最終更新: 2026-05-15 / 2026-05-29（scrollable-list/message/markdown-text 追加）

---

## 概要

Oribis App System v2は、旧JSプラグインシステム（v1: `new Function`実行方式）を完全に置き換える新しいアプリ拡張基盤。iframe sandboxによる安全な実行環境、capability-basedパーミッション、宣言的UIスキーマ、11 namespace Host APIを提供する。

**設計原則**
- Security First: iframe sandbox (`allow-scripts` only) + capability permission
- Declarative UI: プラグインはJSON schemaを返し、Oribis本体がReactでレンダリング
- Host API Only: `oribis.*` namespace経由でのみOribis機能にアクセス
- Scoped Everything: storage/events/fsは全てapp_id単位で隔離

---

## アーキテクチャ

```
┌─────────────────────────────────────────────────┐
│  Oribis App (React + Tauri)                     │
│                                                 │
│  ┌──────────┐  ┌──────────┐  ┌──────────────┐  │
│  │ App.tsx  │  │UIRenderer│  │  EventBus    │  │
│  │(管理UI) │  │(宣言的UI)│  │(global/scoped)│ │
│  └────┬─────┘  └────┬─────┘  └──────┬───────┘  │
│       │              │               │          │
│  ┌────┴──────────────┴───────────────┴───────┐  │
│  │              HostAPI (RPC Handler)         │  │
│  │  ┌─────────────────────────────────────┐  │  │
│  │  │         CAPABILITY_MAP              │  │  │
│  │  │  namespace.method → Capability      │  │  │
│  │  └─────────────────────────────────────┘  │  │
│  └────────────────────┬──────────────────────┘  │
│                       │ postMessage RPC         │
│  ┌────────────────────┴──────────────────────┐  │
│  │         AppSandbox (iframe)               │  │
│  │  sandbox="allow-scripts"                  │  │
│  │  ┌─────────────────────────────────────┐  │  │
│  │  │  oribis.* runtime (injected)        │  │  │
│  │  │  ┌────────┐ ┌────────┐ ┌────────┐  │  │  │
│  │  │  │storage │ │events  │ │ui      │  │  │  │
│  │  │  │character│ │render  │ │vrm     │  │  │  │
│  │  │  │audio   │ │ai      │ │fs/net  │  │  │  │
│  │  │  └────────┘ └────────┘ └────────┘  │  │  │
│  │  └─────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────┘  │
│                                                 │
│  ┌──────────────────────────────────────────┐   │
│  │  Tauri Backend (Rust)                    │   │
│  │  AppRegistry / AppStorage / FS API       │   │
│  │  ManifestV2 validator / Package (.oripkg)│   │
│  └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

---

## Manifest v2

### フォーマット

YAML（推奨）またはJSON。ファイル名: `manifest.yaml` or `manifest.json`

```yaml
manifest_version: 2
id: my-app
name: My App
version: 1.0.0
oribis_api_version: 1.0.0
description: "An Oribis app"
capabilities:
  - storage
  - events
  - uiDockPanel
extension_points:
  - appLifecycle
  - uiSidebarPanel
icon: "🎯"
signature: "base64-encoded-signature"
```

### バリデーション

| フィールド | ルール |
|-----------|--------|
| manifest_version | `== 2` 必須 |
| id | `^[a-z0-9][a-z0-9._-]{2,63}$` |
| name | 空文字禁止 |
| version | semver準拠 |
| oribis_api_version | semver準拠 |
| capabilities | Capability enum値のみ |
| extension_points | ExtensionPoint enum値のみ + capability整合性チェック |

### Capability（17種）

| Capability | 用途 |
|-----------|------|
| storage | app-scoped KV store |
| events | EventBus購読/発行 |
| uiSettingsPanel | 設定パネルUI |
| uiSidebarPanel | サイドバーパネルUI |
| uiDockPanel | ドックパネルUI |
| uiOverlay | オーバーレイウィジェット |
| characterExpression | 表情制御 |
| characterMotion | モーション制御 |
| renderBackground | 背景描画 |
| renderPostprocess | ポストプロセス |
| renderOverlay3d | 3Dオーバーレイ |
| renderTick | フレーム毎hookf |
| audioTts | TTS音声再生 |
| aiTool | AI tool登録 |
| fsRead | ファイル読み取り |
| fsWrite | ファイル書き込み |
| netFetch | HTTPリクエスト |

### ExtensionPoint（12種）

| ExtensionPoint | 必須Capability |
|---------------|----------------|
| appLifecycle | なし |
| uiSettingsPanel | uiSettingsPanel |
| uiSidebarPanel | uiSidebarPanel |
| uiCommand | なし |
| characterBehavior | なし |
| characterMotionProvider | characterMotion |
| renderBackgroundProvider | renderBackground |
| renderPostProcess | renderPostprocess |
| renderOverlay3d | renderOverlay3d |
| renderTick | renderTick |
| audioTtsProvider | audioTts |
| aiTool | aiTool |

---

## Host API（11 Namespace）

### oribis.storage

```typescript
storage.get(key: string): Promise<unknown | null>
storage.set(key: string, value: unknown): Promise<void>
storage.delete(key: string): Promise<boolean>
storage.listKeys(): Promise<string[]>
```

- Capability: `storage`
- バックエンド: Tauri `app_v2_storage_*` コマンド
- 制限: value 1MB、key数 1000、key名 `^[a-zA-Z0-9_-]{1,64}$`
- 保存先: `{config_dir}/oribis/apps-v2/{app_id}/data/{key}.json`

### oribis.events

```typescript
events.emit(event: string, payload?: unknown): Promise<void>
events.on(event: string, handler: (payload) => void): () => void
events.off(event: string, handler: (payload) => void): void
```

- Capability: `events`
- 実装: ScopedEventBus（appId prefix自動付与、システムイベントはprefix除外）

### oribis.ui

```typescript
ui.render(node: ComponentNode): void
ui.clear(): void
```

- Capability: UI系capability（settingsPanel/sidebarPanel/dockPanel/overlay）
- UIレンダリングはHost側のUIRendererが担当（宣言的UIスキーマ方式）

### oribis.app

```typescript
app.getVersion(): Promise<string>
app.getPluginInfo(): Promise<{ id: string; name: string; version: string }>
```

- Capability: なし（全アプリ利用可）

### oribis.character

```typescript
character.setExpression(expression: string): Promise<void>
character.playMotion(motion: string): Promise<void>
character.speak(text: string): Promise<void>
character.setLookAt(target: string): Promise<void>
character.setEmotion(emotion: string): Promise<void>
character.getState(): Promise<unknown>
```

- Capability: `characterExpression` / `characterMotion`
- 実装: EventBus emit → Reactコンポーネントがlisten

### oribis.vrm

```typescript
vrm.getBoneNames(): Promise<string[]>
vrm.setBoneRotation(boneName: string, rotation: {x,y,z,w}): Promise<void>
vrm.getMetadata(): Promise<unknown>
```

- Capability: `characterMotion`
- 実装: EventBus emit

### oribis.render

```typescript
render.setBackground(url: string): Promise<void>
render.addPostprocess(name: string, options?: Record<string, unknown>): Promise<void>
render.removePostprocess(name: string): Promise<void>
render.addOverlay3D(config: unknown): Promise<void>
render.removeOverlay3D(name: string): Promise<void>
render.onTick(callback: (dt: number) => void): () => void
```

- Capability: `renderBackground` / `renderPostprocess` / `renderOverlay3d` / `renderTick`
- 実装: EventBus emit

### oribis.audio

```typescript
audio.speak(text: string, options?: Record<string, unknown>): Promise<void>
audio.stop(): Promise<void>
```

- Capability: `audioTts`
- speak: Tauri `tts_speak` コマンド呼び出し
- stop: EventBus emit

### oribis.ai

```typescript
ai.registerTool(name: string, description: string, handler: (args) => Promise<unknown>): void
ai.unregisterTool(name: string): void
ai.sendToAnima(text: string): Promise<string>
ai.sendToDepartment(dept: string, text: string): Promise<string>
```

- Capability: `aiTool`
- `sendToAnima`: `request_id` 付き Promise 管理 → App.tsx で `invoke("anima_chat")` → `ai:response` で返却。30秒タイムアウト（`TIMEOUT`）。
- `sendToDepartment`: `request_id` 付き Promise 管理 → App.tsx で `invoke("spawn_worker_with_task")` → PTY 出力収集（`pty:data` / `pty:close`）→ `ai:response` で返却。30秒タイムアウト（`TIMEOUT`）、出力上限 100KB（`WORKER_OUTPUT_TOO_LARGE`）、3秒無出力フォールバック完了。
- エラー種別: `ANIMA_ERROR`, `WORKER_ERROR`, `TIMEOUT`, `WORKER_OUTPUT_TOO_LARGE`

### oribis.fs

```typescript
fs.readFile(path: string): Promise<string>
fs.writeFile(path: string, content: string): Promise<void>
fs.exists(path: string): Promise<boolean>
```

- Capability: `fsRead` / `fsWrite`
- バックエンド: Tauri `app_v2_fs_*` コマンド
- サンドボックス: `apps-v2/{app_id}/data/{relative_path}`
- パストラバーサル防止: セグメント単位 `^[a-zA-Z0-9_.-]{1,255}$`、`..` / `.` 禁止
- ファイルサイズ: 5MB上限

### oribis.net

```typescript
net.fetch(url: string, options?: RequestInit): Promise<Response>
```

- Capability: `netFetch`
- 実装: `window.fetch` proxy（ドメイン制限は将来Rust側で実装予定）

---

## iframe Sandbox

### セキュリティモデル

- `sandbox="allow-scripts"` のみ（`allow-same-origin` 禁止）
- Host DOM、localStorage、cookie、ネットワークへの直接アクセス不可
- 全てのOribis機能は `oribis.*` API経由のpostMessage RPCで通信

### RPCプロトコル

**App → Host（リクエスト）**
```json
{ "type": "rpc-call", "id": "uuid", "namespace": "storage", "method": "get", "args": ["key1"] }
```

**Host → App（レスポンス）**
```json
{ "type": "rpc-response", "id": "uuid", "result": {"key": "value"} }
// or
{ "type": "rpc-response", "id": "uuid", "error": "PermissionDeniedError: capability 'storage' not declared" }
```

**Host → App（イベント配信）**
```json
{ "type": "host-event", "event": "app:enabled", "payload": {} }
```

- RPCタイムアウト: 10秒
- Capability未宣言のAPI呼び出し → `PermissionDeniedError`

---

## 宣言的UI

### ComponentNode構造

```typescript
interface ComponentNode {
  type: string;       // コンポーネントタイプ
  props?: Props;      // プロパティ
  children?: ComponentNode[];  // 子ノード
  on?: Record<string, EventHandler>;  // イベントハンドラ
}
```

### 対応コンポーネント（20種）

| type | 主要props | イベント |
|------|----------|---------|
| text | value | — |
| heading | value, level(1-6) | — |
| button | label, variant, disabled | onClick |
| input | type, placeholder, value | onChange |
| textarea | rows, placeholder, value | onChange |
| slider | min, max, step, value, label | onChange |
| toggle | label, checked | onChange |
| select | options[], value, label | onChange |
| checkbox | label, checked | onChange |
| list | items[] | — |
| status | label, color | — |
| progress | value, max, label | — |
| divider | — | — |
| spacer | height | — |
| group | direction(vertical/horizontal), gap | — |
| tabs | tabs[], activeIndex | onTabChange |
| form | — | onSubmit |
| scrollable-list | maxHeight, gap, autoScrollBottom | — |
| message | role(user/assistant/system/error), timestamp, status | — |
| markdown-text | text | — |

### レンダリングフロー

```
App (oribis.ui.render(schema))
  → postMessage RPC → HostAPI
  → onUiRender callback → React state更新
  → UIRenderer.renderNode(schema) → React DOM
  → ユーザー操作 → onEvent(handlerId, payload) → postMessage → App callback
```

---

## Lifecycle管理

### 状態遷移

```
[install] → discovered → [enable] → enabled → [disable] → disabled
                                         ↑                    ↓
                                         └────[enable]────────┘

enabled/disabled → [uninstall] → 削除
discovered → [error検知] → error
```

### AppRegistry（Rust）

| メソッド | 説明 |
|---------|------|
| scan() | apps-v2/ディレクトリ走査、manifest検証、state.json照合 |
| install(src_path) | tmp dir → manifest検証 → atomic rename |
| uninstall(id) | canonicalize → security check → remove_dir_all |
| enable(id) | state.json更新（enabled=true） |
| disable(id) | state.json更新（enabled=false） |

### state.json

```json
{
  "apps": {
    "my-app": { "enabled": true, "installed_at": "2026-05-15T00:00:00+09:00" }
  }
}
```

- Atomic write: tmpファイル → rename
- 破損復旧: state.json.bak から自動復元

---

## パッケージ管理 (.oripkg)

### フォーマット

`.oripkg` = ZIPアーカイブ

```
my-app/
  manifest.yaml
  index.ts
  signature.sig  (optional)
```

### install_package フロー

1. ZIP展開 → tmpディレクトリ
2. manifest探索（ルート or サブディレクトリ）
3. manifest検証（validate_manifest）
4. signature.sig検知（将来の署名検証用）
5. 既存ディレクトリがあれば削除
6. atomic rename → apps-v2/{plugin_id}/

### export_package フロー

1. apps-v2/{plugin_id}/ → ZIP化
2. 全ファイルを再帰的にZIP追加
3. `{plugin_id}/` prefixつき

### セキュリティ

- ZIP内パストラバーサル防止（`..` を含むエントリ拒否）
- ファイルのみ展開（ディレクトリは構造保持のみ）

---

## ディレクトリ構成

### データディレクトリ

```
{config_dir}/oribis/apps-v2/
  state.json              # 全アプリの有効/無効状態
  state.json.bak          # バックアップ
  {app-id}/
    manifest.yaml         # マニフェスト
    index.ts              # エントリポイント
    signature.sig         # 署名（optional）
    data/
      {key}.json          # storage KV
      {relative_path}     # fs API ファイル
```

### ソースコード構成

```
src/plugin-v2/                    # TypeScript側
  types.ts                        # 型定義（Capability, ExtensionPoint, ManifestV2, AppInstance等）
  HostAPI.ts                      # Host API RPC handler
  AppSandbox.ts                   # iframe sandbox管理
  AppSystem.ts                    # システムインターフェース（stub）
  useAppSystem.ts                 # React Hook（Tauri invoke wrapper）
  EventBus.ts                     # EventBus + ScopedEventBus
  UIRenderer.tsx                  # 宣言的UIレンダラー
  sdk/
    oribis-plugin-sdk.d.ts        # SDK型定義（IDE補完用）
    template/                     # テンプレートアプリ
      manifest.yaml
      index.ts
  debug-plugin/                   # Debug Panel v2 アプリ
    manifest.yaml
    index.ts
  __tests__/                      # テストスイート

src-tauri/src/plugin_v2/          # Rust側
  mod.rs                          # モジュール定義 + AppInfoDto
  manifest.rs                     # ManifestV2 + Capability + ExtensionPoint + validator
  lifecycle.rs                    # AppRegistry + state管理
  error.rs                        # AppV2Error
  storage.rs                      # AppStorage (KV store) + Tauri commands
  fs.rs                           # FS API + path traversal防止 + Tauri commands
  package.rs                      # .oripkg install/export + Tauri commands
```

---

## Tauriコマンド一覧

| コマンド | 引数 | 戻り値 | 説明 |
|---------|------|--------|------|
| app_v2_scan | — | AppInfoDto[] | 全アプリスキャン |
| app_v2_install | source_path | AppInfoDto | インストール |
| app_v2_uninstall | id | — | アンインストール |
| app_v2_enable | id | — | 有効化 |
| app_v2_disable | id | — | 無効化 |
| app_v2_get_manifest | id | ManifestV2Dto | マニフェスト取得 |
| app_v2_storage_get | app_id, key | Value? | ストレージ読取 |
| app_v2_storage_set | app_id, key, value | — | ストレージ書込 |
| app_v2_storage_delete | app_id, key | bool | ストレージ削除 |
| app_v2_storage_list_keys | app_id | String[] | キー一覧 |
| app_v2_fs_read | app_id, path | String | ファイル読取 |
| app_v2_fs_write | app_id, path, content | — | ファイル書込 |
| app_v2_fs_exists | app_id, path | bool | ファイル存在確認 |
| app_v2_install_package | oripkg_path | (id, has_sig) | .oripkgインストール |
| app_v2_export_package | app_id, dest_path | — | .oripkgエクスポート |

---

## テスト構成

| スイート | テスト数 | 対象 |
|---------|---------|------|
| Rust cargo test | 1121 | manifest検証、lifecycle、storage、fs、package |
| vitest plugin-v2 | 113 | HostAPI、AppSandbox、EventBus、UIRenderer、useAppSystem、SDK、E2E（chat-mode含む） |

---

## v1からの移行

| v1（廃止） | v2（新） |
|-----------|---------|
| `new Function` 実行 | iframe sandbox |
| `api` オブジェクト直渡し | `oribis.*` postMessage RPC |
| React/Three.js 直参照 | Host APIのみ |
| manifest.json (apiVersion: "1") | manifest.yaml (manifest_version: 2) |
| PluginManager.ts | AppSandbox.ts + HostAPI.ts |
| usePluginLoader.ts | useAppSystem.ts |
| State Pub/Sub (channel) | EventBus (scoped) |
| registerPanel() | oribis.ui.render(schema) 宣言的UI |
| 無制限DOM/API | capability-based permission |

v1の5プラグイン（XP/ポモドーロ/シーン/デバッグ/アニメーションエディタ）は全て廃止。Debug Panel v2のみ移植済み。
