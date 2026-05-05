# Motion Anim Assign

## Overview

# 仕様書: motion-anim-assign

## 概要
- **名前**: モーション・アニメーション割り当て
- **カテゴリ**: oribis
- **目的**: idle/thinking/talking等の各モーション状態およびexpression(surprised/laugh等)に対し、FBX(Unity/Mixamo)またはVMDアニメーションファイルをUIから割り当てて再生できるようにする

## 依存フィーチャー
- `unity-fbx-retarget`: `retargetFbxToVrm()` 実装済み（未コミット）
- `anim-only-fbx`: アニメーション専用FBXロード機能（本フィーチャーで同時実装）

## 仕様

### アニメーション割り当て対象

| キー | 種別 | 説明 |
|------|------|------|
| `idle` | MotionState | 待機アニメーション（ループ） |
| `thinking` | MotionState | 思考中アニメーション（ループ） |
| `talking` | MotionState | 発話中アニメーション（ループ） |
| `typing` | MotionState | タイピング中アニメーション（ループ） |
| `surprised` | Expression | 驚きリアクション（一回再生後idle復帰） |
| `laugh` | Expression | 笑いリアクション（一回再生後idle復帰） |

### ファイルフォーマット対応

| 拡張子 | 対応モデル | パイプライン |
|--------|-----------|------------|
| `.fbx` | VRM / FBX | `loadFbxAnimationClips()` → `retargetFbxToVrm()` → `controller.registerMotionAnimation()` |
| `.vmd` | MMD | `MmdAvatarAdapter.loadVmdForState()` |

### 型定義

```typescript
// DA条件1(HIGH): typing を MotionState に追加（AvatarController interface との統一）
type MotionState = "idle" | "thinking" | "talking" | "typing";
type ExpressionKey = "surprised" | "laugh";
type AnimationKey = MotionState | ExpressionKey;
```

### 新規API（実装対象）

#### `loadFbxAnimationClips(filePath: string): Promise<THREE.AnimationClip[]>`
- `src/loaders/animationLoader.ts` に追加
- FBXLoaderでメッシュなしFBXをロード → `root.animations` を返す
- `animations.length === 0` または有効トラック0件の場合 `AnimationLoadError` をthrow

#### `AvatarController` インターフェース拡張（DA条件3 MEDIUM）
- `registerMotionAnimation(key: AnimationKey, clip: THREE.AnimationClip): void` を `AvatarController` インターフェースに追加
- 既存 `AvatarControllerImpl` で実装
- 内部Mapに保存。上書き可能。

#### `AvatarControllerImpl.registerMotionAnimation(key: AnimationKey, clip: THREE.AnimationClip): void`
- `AnimationKey = MotionState | "surprised" | "laugh"`
- 内部Mapに保存。上書き可能。

#### `AvatarControllerImpl.playMotionState(state: MotionState | ExpressionKey)` の変更
- 登録済みclipがあればclipAction再生 → なければ既存procedural poseフォールバック
- ループ制御: MotionState → `THREE.LoopRepeat`, Expression → `THREE.LoopOnce`
- **DA条件2(HIGH): Expression idle復帰実装方針**: LoopOnce完了後に `playMotionState("idle")` を呼び出す。実装は `mixer.addEventListener('finished', (e) => { if (e.action === currentAction) { playMotionState('idle'); } })` パターンを使用。アクション終了イベントで確実にidle復帰を保証する。

#### `MmdAvatarAdapter.setMotionVmd(key: AnimationKey, vmdUrl: string): void`
- MMDモデル用。VmdをロードしてMMDAnimationHelperに登録

### UI

#### AnimationAssignPanel（新規コンポーネント）
- 場所: `src/components/AnimationAssignPanel.tsx`
- AvatarViewerのアバター表示パネル内またはサイドバー設定欄に配置
- 各 `AnimationKey` に対して:
  - 現在の割り当てファイル名（未割り当ては「—」）
  - 「Browse」ボタン → `openDialog({ filters: [{ name: "Animation", extensions: ["fbx", "vmd"] }] })`
  - ファイル選択後: ロード → リターゲット → 登録 → UI更新
  - ロードエラー時: インラインエラーメッセージ表示

#### AvatarViewer.tsx の変更
- `AnimationAssignPanel` をレンダリング
- `controllerRef` または `mmdAdapterRef` を Panel に渡す

## 受入条件 (AC)

- AC-1: Given VRM + Mixamo FBX選択、When idle割り当て、Then アバターがFBXアニメーションでループ再生する
- AC-2: Given VRM + Unity(ARP)FBX選択、When talking割り当て、Then Unity HumanBodyBonesが正しくリターゲットされて再生される
- AC-3: Given MMD + VMD選択、When thinking割り当て、Then MMDモデルでVMDアニメーションが再生される（MMD経路非破壊）
- AC-4: Given FBX割り当て後に別のFBX選択、When 上書き割り当て、Then 新しいアニメーションに切り替わる
- AC-5: Given surprised割り当て済み + AI expression=surprised発火、When 再生、Then 一回再生して自動的にidleに戻る
- AC-6: Given animations.length===0のFBX選択、When ロード、Then UIにエラー表示・割り当ては変更されない
- AC-7: Given アバター未ロード状態、When Browseボタン押下、Then ボタンがdisabledまたはロード後に割り当てを適用する
- AC-8: Given unity-fbx-retarget AC-1〜5（既存）、Then 全て引き続きPASS（非破壊）
- AC-9（DA条件4 MEDIUM）: Given VRMモデルロード済み + VMDファイル選択、When 割り当て、Then UIにエラー表示「VMDはMMDモデル専用です」・割り当ては変更されない

## anim-only-fbx サブ仕様

### `loadFbxAnimationClips(filePath: string): Promise<THREE.AnimationClip[]>`
- `src/loaders/animationLoader.ts`（新規）
- FBXLoader.loadAsync → `(root as { animations?: THREE.AnimationClip[] }).animations ?? []`
- バリデーション: `clips.length === 0` → throw `new AnimationLoadError("No animation clips found in FBX")`
- export: `AnimationLoadError` クラスも export

## 既存パターン参照
- **ファイルピッカー**: `App.tsx:1385` の `openDialog()` パターン
- **AvatarController**: `src/controllers/AvatarController.ts`
- **retargetFbxToVrm**: `src/adapters/retargetMixamoToVrm.ts`
- **FBXLoader**: `src/adapters/FbxAvatarAdapter.ts` 参照

## 除外事項
- VRMA形式（別フィーチャー）
- アニメーション割り当てのlocalStorage永続化（初期はセッション内のみ）
- root motion / 足IK補正
- 複数FBXクリップのブレンド

## Implementation Notes

# motion-anim-assign — 実装ログ

## Log

### 2026-04-25 設計
- Producerアーキテクチャ確定: loadAvatar/loadAnimationSet分離、animationLoader+retargetFbxToVrm+controller.registerMotionAnimation
- Codex設計相談FAIL（汎用的回答） → Producer設計が確定版
- unity-fbx-retargetコード実装済み（retargetFbxToVrm/retargetUnityToVrm/detectFbxRigType）未コミット・Unityテスト未作成
- spec.md作成（AC-1〜8）
> 状態: AC未着手 / バグ0 / 次: DA設計ゲート → tdd-guide実装

### 2026-04-25 実装完了
- DA条件4件をspec.mdに追記（typing型統一、idle復帰、interface拡張、AC-9）
- tdd-guide: 実装完了 366テスト PASS (commit ddf7745)
- codex-reviewer R1: FAIL 6件指摘
  - HIGH: vrmRef未渡し(AC-2)、MMD/VMD経路未接続(AC-3)、テスト不足
  - MEDIUM: エラー時fileName上書き(AC-6)、typing型アサーション
  - LOW: finishedリスナー未解放
- 全指摘修正 → 374テスト PASS (commit bd81743)
- self-review R2: PASS (AC-1〜9全件確認)
- DA最終ゲート: GO
> 状態: 実装完了 / バグ0 / 次: feat/avatar-animationブランチ マージ待ち

## Known Issues / Backlog

# motion-anim-assign — Issues

<!-- 
タグ: [バグ] [つまづき] [判断]
バグ番号: #B001, #B002, ...
-->

## Open

## Closed

### #B001 [バグ] vrmRef未渡し → retargetFbxToVrm未実行 (codex R1 HIGH-1)
- 修正: VrmAvatarAdapter.getVrmLike()追加、onControllerReadyコールバック拡張、vrmRefをAnimationAssignPanelへ渡す

### #B002 [バグ] MMD/VMD経路未接続 ("future integration") (codex R1 HIGH-2)
- 修正: MmdAvatarAdapter.setMotionVmd()実装、AnimationAssignPanelで呼び出し

### #B003 [バグ] エラー時fileNameをnullで上書き (codex R1 MEDIUM-3)
- 修正: prev[key].fileName 維持に変更

### #B004 [バグ] typing型アサーション (codex R1 MEDIUM-4)
- 修正: _motionState型をMotionStateKeyに統一、型アサーション削除

### #B005 [つまづき] finishedリスナー残留 (codex R1 LOW-5)
- 修正: _activeFinishedListener フィールド追加、stopAll/playMotionState/playClipで削除

