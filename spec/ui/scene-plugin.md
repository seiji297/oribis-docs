# scene-plugin.md — Oribis Scene プラグイン仕様

最終更新: 2026-05-04（初版：セッション実装完了）

---

## 概要

oribis デスクトップアプリに背景アニメーション機能を `scene` 有償プラグインとして追加する機能。
コアアプリの PluginAPI に `registerBackground` / `onCliStateChange` / `three` を追加し、
プラグインが HTMLCanvasElement をアバター Canvas の背後に差し込む。

設計元文書: `docs/deliverables/plan-oribis-scene-plugin.md`

---

## 実装済み（2026-05-04 時点）

### コアアプリ側（oribis）

| ファイル | 変更内容 |
|---------|---------|
| `src/plugin/types.ts` | PluginAPI に `three`, `registerBackground`, `onCliStateChange` 追加。LoadedPlugin に `background` フィールド追加 |
| `src/plugin/PluginManager.ts` | background 単一 owner 管理、cliState コールバック Map、tier check (`get_plugin_tier`)、即時 currentCliState 通知 |
| `src/plugin/usePluginLoader.ts` | `backgroundCanvas: HTMLCanvasElement \| null` state を返すよう拡張 |
| `src/App.tsx` | `notifyCliStateChange` 呼び出し（cliState 変化時）、`scene-background-layer` div 追加、backgroundCanvas useEffect による DOM 挿入/削除 |
| `src/App.css` | `.scene-background-layer { position:absolute; inset:0; z-index:0 }` 追加、`.vrm-canvas-container { z-index:1 }` 追加、`.vrm-panel { background: transparent }` 変更、pane-bottom chat input transparent 化 |
| `src-tauri/src/config.rs` | `AppConfig` に `plugins: Option<PluginsConfig>` 追加。`PluginsConfig { scene_enabled: bool (default: false) }` |
| `src-tauri/src/plugin.rs` | `PAID_PLUGIN_IDS = ["scene"]`、`get_plugin_tier` コマンド追加、`save_plugin_data` / `load_plugin_data` コマンド追加 |
| `src-tauri/src/lib.rs` | `get_plugin_tier`, `save_plugin_data`, `load_plugin_data` handler 登録 |

### プラグイン側（oribis-plugins/scene）

| ファイル | 内容 |
|---------|------|
| `manifest.json` | `id="scene"`, `name="Scene"`, `version="0.1.0"`, `has_panel=true`, `entry="index.js"` |
| `index.js` (441行) | SceneBackground（vanilla Three.js WebGL）+ SceneEditorPanel（React.createElement）|

### SceneBackground 実装内容
- **描画オブジェクト**: InstancedMesh リング、LineSegments ライン、Points 光点、ShaderMaterial グロー（4 draw call）
- **30fps 制限**: requestAnimationFrame + delta 比較によるスキップ
- **CLI state 連携**: idle→1.0x / thinking→2.5x / responding→1.8x の intensityMultiplier lerp
- **ResizeObserver**: DOM 挿入後に自動リサイズ対応
- **Cleanup**: cancelAnimationFrame → ResizeObserver.disconnect → 全 dispose → renderer.dispose（順序厳守）
- **設定永続化**: `api.storage.save/load("scene_settings")` で config 保存復元

### SceneEditorPanel 実装内容
- リング個数（0〜8）、回転速度（0〜2.0）、透明度（0〜0.5）スライダー
- 光点数（0〜50）、サイズ（0.005〜0.05）スライダー
- ライン本数（0〜10）、ライン色（hex テキスト入力）
- グロー有効/無効チェックボックス

### Tier 管理
- config.toml に `[plugins]\nscene_enabled = true` を追加することで有効化
- デフォルト（未設定）は `false`（fail-close）
- config.toml パス（Windows）: `C:\Users\<user>\AppData\Roaming\oribis\config.toml`

---

## AC 検証状況

| AC | 内容 | 状態 |
|----|------|------|
| A-1 | `registerBackground` 型定義 | ✅ |
| A-2 | `onCliStateChange` 型定義（戻り値 unsubscribe） | ✅ |
| A-3 | PluginManager.registerBackground 動作 | ✅ 実装済み / ⚠️ ユニットテスト未追加 |
| A-4 | notifyCliStateChange コールバック発火 | ✅ 実装済み / ⚠️ ユニットテスト未追加 |
| A-4b | 登録直後即時発火 | ✅ 実装済み / ⚠️ ユニットテスト未追加 |
| A-4c | unloadPlugin 後はコールバック不発火 | ✅ 実装済み / ⚠️ ユニットテスト未追加 |
| A-4d | A unload で B の background を消去しない | ✅ 実装済み / ⚠️ ユニットテスト未追加 |
| A-4e | background owner のみ unload で消去 | ✅ 実装済み / ⚠️ ユニットテスト未追加 |
| A-5 | backgroundCanvas を scene-background-layer に挿入（bgCutout 条件付き） | ✅ |
| A-6 | manifest.json 存在・内容 | ✅ |
| A-7 | index.js に 3 メソッド呼び出し | ✅ |
| A-8 | vanilla Three.js 使用 | ✅ |
| A-9 | 30fps 制限 | ✅ |
| A-10 | スライダー UI | ✅ |
| A-10b | グロー有効/無効チェックボックス | ✅ |
| A-11 | 設定永続化 | ✅ 実装済み（動作確認待ち） |
| A-12 | PluginsConfig パース | ✅ 実装済み / ⚠️ ユニットテスト未追加 |
| A-13 | get_plugin_tier コマンド | ✅ 実装済み / ⚠️ ユニットテスト未追加 |
| A-13b | fail-close 動作 | ✅ 実装済み / ⚠️ ユニットテスト未追加 |
| A-14 | tier false → isActive:false | ✅ |
| A-15 | antialias:false, pixelRatio:1 | ✅ |
| A-16 | cleanup 全 dispose | ✅ |
| A-17 | GPU 使用率 +10% 以内 | ❌ 未確認（手動確認） |
| A-18 | draw call 4以下/frame | ❌ 未確認（Spector.js 等） |
| A-19 | v1 既知制限（manifest 署名なし） | ✅ 設計文書明記済み |

---

## 未実装・残タスク

### SCENE-1: PluginManager ユニットテスト追加（必須）
- `src/plugin/PluginManager.test.ts` 新規作成
- A-3, A-4, A-4b, A-4c, A-4d, A-4e をカバー

### SCENE-2: Rust ユニットテスト追加（必須）
- `src-tauri/src/config.rs` に PluginsConfig パーステスト追加（A-12）
- `src-tauri/src/plugin.rs` に get_plugin_tier テスト追加（A-13, A-13b）

### SCENE-3: SceneEditorPanel 背景グラデーション色制御（v2 予定）
- 計画書 §6.1 の「背景グラデ開始色・終了色」コントロールは未実装
- 現在は div.scene-background-layer の CSS グラデーションは未追加

### SCENE-4: パフォーマンス確認（手動確認待ち）
- A-17: GPU 使用率 +10% 以内の確認
- A-18: draw call 4以下/frame の確認

### SCENE-5: Windows ビルド更新
- Windows 側 `C:\Users\admin\claude-projects\oribis` が `d89932c` で止まっており `api.three` 未実装
- `git fetch origin && git merge origin/fix/cherry-pick-for-prod` + `cargo build` が必要

---

## 既知の問題

### Scene プラグイン Error 表示（Windows）
- 原因: Windows ビルドが `api.three` 追加前のコミット（`d89932c`）でコンパイルされている
- `const THREE = api.three` → `undefined` → 分割代入で TypeError
- 修正: `fix/cherry-pick-for-prod` ブランチを pull して再ビルド（SCENE-5）

---

## コミット履歴（dev main）

| コミット | 内容 |
|---------|------|
| `a8e337c` | feat: add scene plugin files (sysdev) |
| `4abc578` | chore: update scene plugin icon to image-alt.svg |
| `17510af` | feat: add scene plugin core API (registerBackground, onCliStateChange, tier check) |
| `d297969` | fix: make pane-bottom chat input fully transparent |
| `356fc8c` | fix: make vrm-panel transparent so scene background canvas shows through |

## コミット履歴（production fix/cherry-pick-for-prod）

| コミット | 内容 |
|---------|------|
| `c995dd0` | fix: splash ghost window CSS |
| `e7761cc` | fix: splash transparent=false |
| `11b93e1` | feat: scene core API |
| `0c58fdd` | fix: chat input transparent |
| `021238d` | fix: vrm-panel transparent |
