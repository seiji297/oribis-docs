# plugin-api.md — Oribis プラグイン API 仕様

最終更新: 2026-05-04（初版）

---

## 概要

oribis プラグインシステムの API 仕様。外部 JS プラグインが `api` オブジェクト経由でコアアプリと連携する。

---

## プラグインの構造

```
oribis-plugins/<plugin-id>/
  manifest.json    # メタデータ
  index.js         # エントリポイント（api オブジェクトを受け取る関数）
```

### manifest.json

```json
{
  "id": "plugin-id",
  "name": "Plugin Name",
  "version": "1.0.0",
  "apiVersion": "1",
  "icon": "<svg .../>",
  "has_panel": false,
  "entry": "index.js"
}
```

---

## PluginAPI インターフェース

### 基本

| メソッド | 型 | 説明 |
|---------|------|------|
| `id` | `string` | プラグイン ID |
| `apiVersion` | `string` | API バージョン |
| `React` | `typeof React` | React ライブラリ参照 |
| `three` | `typeof THREE` | Three.js ライブラリ参照 |

### ストレージ

| メソッド | 型 | 説明 |
|---------|------|------|
| `storage.save(key, value)` | `Promise<void>` | キー・バリュー保存 |
| `storage.load(key)` | `Promise<any>` | キー・バリュー読み込み |

### メッセージ / トークン

| メソッド | 説明 |
|---------|------|
| `onTokenReceived(cb)` | トークン受信時コールバック |
| `onMessage(cb)` | メッセージ受信時コールバック |
| `sendToAnima(text)` | Anima にメッセージ送信 |

### UI 登録

| メソッド | 説明 |
|---------|------|
| `registerPanel(component)` | パネルコンポーネント登録 |
| `registerDockPanel(options)` | ドックパネル登録（タブ・セクション構成） |
| `registerOverlayWidget(component)` | オーバーレイウィジェット登録 |
| `setTitlebarBadge(text)` | タイトルバーバッジ設定 |
| `setOverlayInfo(text)` | オーバーレイ情報テキスト設定 |

### アニメーション

| メソッド | 説明 |
|---------|------|
| `registerAnimationClip(stateName, boneData, options)` | アニメーションクリップ登録 |
| `setAnimationState(stateName)` | アニメーションステート切替 |
| `registerCustomState(stateName, options)` | カスタムステート登録 |
| `onAnimationStateChange(cb)` | アニメーションステート変更通知 |
| `getAnimationStates()` | 利用可能なステート一覧 |
| `getAvatarBones()` | アバターのボーン名一覧 |

### 背景 / CLI ステート

| メソッド | 説明 |
|---------|------|
| `registerBackground(canvas, cleanup)` | 背景 Canvas 登録（単一オーナー制） |
| `onCliStateChange(cb)` | CLI ステート変更通知（idle/thinking/responding） |

### 汎用 State Pub/Sub（2026-05-04 追加）

アプリの内部 state をプラグインから参照・変更するためのチャンネルベースの Pub/Sub システム。

| メソッド | 型 | 説明 |
|---------|------|------|
| `getState(channel)` | `unknown` | チャンネルの現在値を取得（shallow copy） |
| `setState(channel, value)` | `void` | チャンネルに値をセット（App.tsx の setter 経由） |
| `subscribe(channel, cb)` | `() => void` | チャンネルの変更を購読（unsubscribe 関数を返す） |

#### 利用可能チャンネル

| チャンネル名 | 型 | R/W | 説明 |
|-------------|------|-----|------|
| `camera` | `CameraParams` | R/W | カメラパラメータ（fov, rotH, rotV, dist, panX, panY） |
| `expressions` | `{ overrides, available }` | R/W | 表情オーバーライド + 利用可能表情一覧 |
| `lookAt` | `string` | R/W | LookAt ターゲット |
| `boneOverrides` | `{ values, enabled }` | R/W | ボーンオーバーライド値 + 有効フラグ |
| `perfSettings` | `PerfSettings` | R/W | パフォーマンス設定 |
| `testAnimation` | `string \| null` | R/W | テストアニメーション状態 |
| `animaInfo` | `AnimaInfo` | R | Anima 情報（state, presence, lewdGuard, mode） |
| `wristPosition` | `WristPos \| null` | R | 手首位置（VR 入力） |

#### ブリッジパターン

```
App.tsx (state owner)
  ↓ registerStateChannel(channel, setter)   — setter 登録
  ↓ notifyStateChange(channel, value)        — useEffect で値変更通知
PluginManager.ts (中継 Map)
  ↓ api.getState(channel) / api.setState(channel, value) / api.subscribe(channel, cb)
Plugin (外部 JS)
```

---

## ドックパネルシステム

### DockPanelOptions

```typescript
interface DockPanelOptions {
  icon: string;        // SVG アイコン
  label: string;       // パネルラベル
  tabs: DockTab[];     // タブ配列
  defaultWidth?: number;
}

interface DockTab {
  id: string;
  label: string;
  sections: DockSection[];
}

interface DockSection {
  id: string;
  label: string;
  icon?: string;
  component: React.ComponentType;
}
```

### 自動スタイリング

ドックパネル内の要素は CSS 変数でテーマ対応。プラグイン側で明示的なスタイル指定不要:
- `.overlay-dock-panel` — パネル全体
- `.overlay-dock-tab` — タブボタン
- `.dock-section` — セクション
- `.dock-slider` — スライダーコントロール
- `.dock-btn` / `.dock-btn-danger` — ボタン

---

## 実装ファイル

| ファイル | 内容 |
|---------|------|
| `src/plugin/types.ts` | PluginAPI, PluginInfo, LoadedPlugin, DockPanelOptions 型定義 |
| `src/plugin/PluginManager.ts` | プラグインライフサイクル管理、state pub/sub ブリッジ、各種コールバック管理 |
| `src/plugin/usePluginLoader.ts` | プラグイン読み込み React Hook |
| `src/App.tsx` | state channel 登録・通知の useEffect 群 |
| `src-tauri/src/plugin.rs` | Rust 側プラグインコマンド（load_plugin_code, save/load_plugin_data, get_plugin_tier） |
