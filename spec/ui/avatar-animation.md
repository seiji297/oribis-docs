# Avatar Animation

## Overview

# Feature Spec: Oribis アバターアニメーション/表情 抽象化

**カテゴリ**: oribis
**フィーチャー**: avatar-animation

---

## 概要

VRM/FBX/MMD の3フォーマットにわたるアバターのポーズ・アニメーション・表情を統一的に扱う抽象化レイヤーを追加・拡張する。

---

## 現状

| フォーマット | ポーズ制御 | 表情制御 | アニメーション |
|------------|----------|---------|--------------|
| VRM | 手続き骨ブレンド (IDLE/THINK/TALK) | expressionManager | なし（手続き） |
| MMD | VMD → MMDAnimationHelper | VMD モーフトラック (13種) | VMD 一体再生 |
| FBX | AnimationMixer | モーフトラック | 埋め込みクリップ |

既存コード:
- `src/types/avatar.ts` — AvatarModel インターフェース
- `src/adapters/VrmAvatarAdapter.ts` — VRM アダプター
- `src/adapters/MmdAvatarAdapter.ts` — MMD アダプター
- `src/adapters/FbxAvatarAdapter.ts` — FBX アダプター
- `src/adapters/boneMapping.ts` — 骨名マッピング (VRM camelCase 正規化)
- `src/adapters/expressionMapping.ts` — MMD 表情マッピング (13種実装済み)

---

## 変更1: 表情正規化セット拡張 (13種→18種)

### 追加する5種

- `neutral` — 通常表情
- `lookUp / lookDown / lookLeft / lookRight` — 視線方向

### MMD lookAt 設計方針

MMD モデルはモーフで視線を表現しないケースが多い。
`MMD_EXPRESSION_MAP` で `null` フォールバック設計を採用:

```typescript
lookUp: null,      // 対応モーフなし → setExpression でスキップ
lookDown: null,
lookLeft: null,
lookRight: null,
neutral: null,     // モデル依存（存在すれば設定可）
```

### AC

- AC-1: `setExpression("neutral", 1.0)` が VRM/FBX で正常動作する
- AC-2: `setExpression("lookUp", 1.0)` が VRM/FBX で正常動作する
- AC-3: MMD で lookAt 系を呼んでもクラッシュしない（null スキップ）
- AC-4: `listExpressions()` が18種すべてを列挙できる（VRM）
- AC-5: 既存13種の MMD 表情が変更後も正常動作する

---

## 変更2: FBX→VRM ランタイムリターゲット

### 方針

three-vrm 公式サンプルをベースに実装:
- `loadMixamoAnimation.js` (bone remapping + A/T pose correction)
- `mixamoVRMRigMap.js` (Mixamo → VRM 骨名変換表)
- `SkeletonUtils.retargetClip` (Three.js 公式)

### 処理フロー

```
FBX AnimationClip (Mixamo)
  1. トラック名リマップ: "mixamorig:Hips.quaternion" → "hips.quaternion"
     (mixamoVRMRigMap.js の MIXAMO_VRM_RIG_MAP を使用)
  2. A-pose/T-pose Δクォータニオン補正
     (各骨のレストポーズ差分を事前計算して適用)
  3. VRM AnimationMixer に投入
     (getNormalizedBoneNode() で VRM 骨オブジェクト取得)
```

### 制約

- Mixamo FBX のみ対応（Maya/Blender 等は別プロファイル）
- MMD には適用しない（VMD 経路を維持）

### AC

- AC-6: Mixamo FBX の walk アニメーションが VRM モデルで再生できる
- AC-7: リターゲット後の骨回転が T-pose 基準で正しい（腕が T 字に戻る）
- AC-8: FBX モデル自身への AnimationMixer 再生（既存）は非破壊
- AC-9: リターゲット処理が毎フレームではなくロード時1回実行される（GC 対策）

---

## 変更3: AvatarController 追加

### インターフェース

```typescript
interface AvatarController {
  playMotionState(state: "idle" | "thinking" | "talking"): void
  playClip(clip: THREE.AnimationClip): void
  setExpression(name: string, weight: number): void
  stopAll(): void
}
```

### レイヤー優先順位

```
クリップモーション > 手続きポーズ > lookAt > lip sync > 表情
```

### 設計制約

- raw bone 操作と normalized bone 操作の混在禁止
- AnimationClip はキャッシュ再利用（毎回再生成禁止）
- MMDAnimationHelper は分離維持（AvatarController に統合しない）

### AC

- AC-10: VRM で `playClip()` → `playMotionState()` 切り替えが正しく動作する
- AC-11: `stopAll()` でクリップと手続きポーズが両方停止する
- AC-12: MMD は従来の VMD 再生経路が維持される（AvatarController 非使用）

---

## 変更4: MMD morphMap per-model JSON 外出し

### 背景

現状の `MMD_EXPRESSION_MAP` はグローバル辞書だが、PMX モデルごとにモーフ名が異なる。
グローバル統一は不可能 → モデル別 JSON ファイルで管理する。

### 設計

```
assets/morph-maps/
  {modelId}.morph.json    // モデル固有のモーフ名辞書
  default.morph.json      // フォールバック（よくある名前を網羅）
```

```json
// anima.morph.json の例
{
  "happy": ["笑い", "にこり"],
  "sad": ["悲しい"],
  "angry": ["怒り"],
  "blink": ["まばたき"],
  "aa": ["あ"],
  "oh": ["お"],
  "neutral": [],
  "lookUp": null,
  "lookDown": null,
  "lookLeft": null,
  "lookRight": null
}
```

モデルロード時に `{modelId}.morph.json` を読み込み、なければ `default.morph.json` にフォールバック。

### AC

- AC-13: モデル別 JSON が存在する場合、そのモーフ辞書で表情制御される
- AC-14: JSON が存在しない場合、default.morph.json にフォールバックする
- AC-15: `null` 値のエントリは `setExpression()` でスキップされる（クラッシュなし）

---

## 実装優先度

| 優先度 | 変更 | 工数 |
|--------|------|------|
| P1 | 表情18種拡張 | 小 |
| P2 | FBX→VRM リターゲット | 中 |
| P3 | AvatarController | 中 |
| P4 | MMD morphMap per-model JSON | 小〜中 |

---

## 除外事項

- VRMA 形式の採用（オフライン変換ワークフロー不採用）
- MMD VMD リターゲット
- Mixamo 以外の FBX リターゲット（Phase 2）
- lookAt 系 VRM lookAt システムとの統合（Phase 2）

## Implementation Notes

# avatar-animation — 実装ログ

## Log

### 2026-04-25 設計フェーズ
- WEB調査: VRM/FBX/MMD アニメーション抽象化パターン調査
- codex-sysdev-1 見解取得: SkeletonUtils.retargetClip/loadMixamoAnimation.js 確認
- sysdev-1 調整: expressionMapping.ts 13種実装済み確認、lookAt null フォールバック合意
- spec.md 草案確定
> 状態: AC 12件定義 / バグ 0 / 次: planner→AC開始

### 2026-04-25 実装フェーズ（P1〜P4 + codex修正3ラウンド）
- P1(e72a2ea): expressionMapping.ts 13→18種拡張（neutral/lookUp/lookDown/lookLeft/lookRight追加）、MMD null フォールバック修正
- P2(16f8651): retargetMixamoToVrm.ts — Mixamo FBX→VRM リターゲット（55ボーンマップ）実装
- P3(81a45e0): AvatarController.ts 追加・AvatarViewer.tsx 統合（controllerRef生成/破棄）
- P4(b7543f8): morphMapLoader.ts static import方式・MmdAvatarAdapter static async factory
- R1修正(0203ad7): AC-13 modelId URL抽出・AC-7 VRM inverse rest Q実装・AC-10/11配線
- R2修正(e41096b): AvatarController interface update()追加・playMotionState毎フレーム→変化時のみ
- R3修正(1ca4520): retargetトラック名 vrmBoneName→boneNode.name・URL query/hash除去
- テスト: 340件全PASS（23ファイル）
- 設計ゲート: 条件付きGO（C-1/C-2/C-3）
- 最終ゲート: **GO**（DA: da-gate-final-oribis-avatar-animation-20260425.md）
- バックログ: AC-7 rest pose完全補正（Mixamo FBX rest poseデータ構造的取得不可）・targetVrmAdapter VRM不一致(LOW)・playClip UIトリガー未実装
- knowledge.md昇格: 3件 / index.md作成済み
> 状態: AC-1〜6,8〜15 PASS / AC-7 部分実装（バックログ）/ 次: Producerマージ指示待ち（未マージ）

## Known Issues / Backlog

# avatar-animation — Issues

## Open

- [バグ #B001] AC-7 rest pose補正不完全: applyRestPoseCorrection() はVRM inverse rest Qのみ。Mixamo FBX A-poseデータがランタイムで取得不可（構造的制約）→ FBX解析ライブラリ導入時に対応予定
- [バグ #B002] targetVrmAdapter VRM不一致(LOW): loadAvatar()でtargetVrmAdapterに渡すretargetクリップが現ロードVRMの補正で生成されている。異VRMモデル間流用時に姿勢ズレの恐れ
- [判断] playClip()外部呼び出しUIトリガー未実装: AvatarControllerのplayClip()はAPIとして実装済みだが、AvatarViewer内にUIトリガーなし。将来の再生ボタン等で呼ぶ想定

## Closed

- [バグ] AC-13 modelId常にdefault固定 → URL basename抽出してcreate()第4引数に渡す（0203ad7）
- [バグ] AC-7 applyRestPoseCorrection() がstub → VRM inverse rest Q premultiply実装（0203ad7）
- [バグ] AC-10/11 playMotionState/update/stopAll未配線 → AvatarViewer useFrame/dispose配線（0203ad7）
- [バグ] AvatarController interface update()欠落 → stopAll()後に追加（e41096b）
- [バグ] playMotionState()毎フレーム呼び出し → prevSafeStateRefで変化時のみ呼ぶ（e41096b）
- [バグ] retargetトラック名 vrmBoneName → boneNode.name使用に変更（Three.js PropertyBinding対応）（1ca4520）
- [バグ] URL query/hash非除去でmodelId汚染 → pathname = url.split('?')[0].split('#')[0]（1ca4520）

