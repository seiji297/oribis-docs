# ARP → VRM リターゲット: 経緯・現状・TODO

## 対象ファイル
`src/adapters/retargetMixamoToVrm.ts` — `retargetArpToVrm()` 関数

---

## 確定済み: 数式

```
Q_vrm = R * inv(f0) * fN * inv(R)
```

- `R` = Z-up → Y-up 変換 = quaternion(-0.70710678, 0, 0, 0.70710678)（X軸 -90°回転）
- `f0` = ARP ボーンの bind pose local quaternion（Z-up 座標系）
- `fN` = FBX アニメーション frame N の local quaternion（Z-up 座標系）
- **M = R（全ボーン共通）**。親の armature-space は分子分母でキャンセルされる。

### 導出（Python TEST3 で数値検証済み）
```
ARP_bone_T_yup = R * (parent_world * f0) * inv(R)
ARP_bone_N_yup = R * (parent_world * fN) * inv(R)
Q_vrm = inv(ARP_bone_T_yup) * ARP_bone_N_yup
      = R * inv(f0) * fN * inv(R)   ← parent_world がキャンセル
```

---

## f0 ソースの優先順位

```typescript
const f0 = vrmName === "hips"
  ? identity
  : ARP_BONE_REST[vrmName]?.restSelfArmature   // (1) 体幹ボーン: Blender export
  : computedRestSA.get(vrmName)                 // (2) 手指ボーン: inv(parent) * child
  ?? frame0Map.get(vrmName);                    // (3) frame 0 fallback
```

### restSelfArmature の定義（2026-05-08 判明）

```
restSelfArmature[bone] = inv(restLocal[parent]) * restLocal[bone]
```

- `restLocal` = bone.quaternion（T-pose時のローカル回転）
- `restSelfArmature` = 親の restLocal を打ち消した後の子の回転（≠累積ワールド回転）
- `ARP_BONE_REST` は `tools/export_arp_bone_rest.py` で Blender から取得
- 手指ボーンは `ARP_BONE_REST` 未登録 → `restPoseCache`（GLBシーンの bone.quaternion）から動的に計算

---

## 完了

| ボーン群 | 状態 | 備考 |
|---------|------|------|
| 腕全般 (upperArm/lowerArm/shoulder) | ✅ 修正済み | M=R に変更。`leftUpperArm Q_vrm[0]=(18.0,28.3,-70.4)` 確認 |
| leftHand / rightHand | 🔧 修正中 | restSelfArmature 空間不一致バグ修正（GLBシーンから動的計算に変更）。視覚テスト待ち |
| 指全般 (finger bones) | 🔧 修正中 | hand と同じ computedRestSA で対応。視覚テスト待ち |
| 脊椎 (hips/spine/chest/upperChest/neck/head) | 動作中（詳細未検証） | |
| 脚 (upperLeg/lowerLeg) | ✅ baseline 復元 | ARP_BONE_REST から脚4本を削除。frame0 fallback 使用 |

## sysdev-2 handoff（2026-05-07, commit 28f352b, branch sysdev-2/fbx）

**到達点**: ARP リターゲット安定 baseline 復元。app 起動可能、全身立位。

**今回確定した修正**:
1. `ARP_BONE_REST` から脚4本削除（leftUpperLeg/leftLowerLeg/rightUpperLeg/rightLowerLeg）
2. `ARP_FRAME0_DELTA_BONES` に脚4本を復帰
3. non-hips position cut 維持、arm/neck の direct conjugation + frame0 delta + post offset 系は維持

**重要な学び（禁止事項）**:
- `animationLoader.ts` に `node:fs/promises` / `node:url` を混ぜると **app 起動不能** → Node 依存は本体コードに入れてはいけない
- runtime finger basis / palm-plane 補正は見た目を明確に劣化させた → **不採用**
- 全身経路をまとめて触ってはいけない

**検証済み**: `pnpm tsc --noEmit` PASS、`pnpm vitest run src/adapters/retargetMixamoToVrm.test.ts` PASS

---

## 未解決・要調査

### 1. 手の甲の向き・指の打鍵方向 — ~~hand/finger retarget 軸問題~~ f0 空間不一致バグ
- **根本原因特定済み（2026-05-08）**: `restSelfArmature = inv(parent_restLocal) * bone_restLocal` だが、hand/finger は `restPoseCache`（= `restLocal`）をそのまま f0 に使用していた。空間不一致。
- **修正**: `computedRestSA` マップを追加。ARP_BONE_REST 未登録ボーンは `inv(parent_restLocal) * bone_restLocal` を restPoseCache から動的計算
- **状態**: 修正コード済み、38テストPASS、**視覚テスト待ち**
- **制約**: `retargetMixamoToVrm.ts` 以外へ波及させない。全身 baseline を壊さない前提で局所修正のみ

### 2. 脚 — ~~クロスレッグ座り~~ baseline 復元で解消
- ARP_BONE_REST から脚4本を削除、ARP_FRAME0_DELTA_BONES に復帰で解消（28f352b）
  - ARP_BONE_REST 値が正しいかどうか未検証
- **確認方法**: Blender で元 FBX を開き Typing アニメのポーズを確認

### 3. デバッグログ削除 — 後で
- `[retargetArpToVrm] === All tracks in clip ===` など大量ログあり
- 全骨格の動作確認後に削除

---

## ARP_BONE_REST 欠損リスト

| VRM名 | ARP bone | 状態 |
|-------|---------|------|
| leftHand | handl | Blender export 空 → 削除済み |
| rightHand | handr | Blender export 空 → 削除済み |
| leftFoot/rightFoot | footl/footr | 未確認 |
| leftToes/rightToes | toes_01l/r | 未確認 |
| 全指ボーン | c_thumb1l 等 | ARP_BONE_REST 未登録 |

---

## 次のアクション（優先順）

1. **視覚テスト**: pnpm tauri dev → タイピングアニメGLB読み込み → 手指の向き確認
2. 結果に応じた追加修正（必要なら）
3. 全ボーン OK 確認後 → デバッグログ削除
4. commit & merge

**やってはいけないこと**:
- `animationLoader.ts` に Node 専用 import を戻す
- finger basis を palm-plane から runtime 再構築する系を再投入する
- 全身経路をまとめて触る

---

## sysdev-2 進捗（2026-05-08, branch sysdev-2/retarget-test）

**到達点**: f0 空間不一致バグ特定・修正コード済み。視覚テスト待ち。

**今回の修正**:
1. GLB（GLTF）ロード時も `extractBoneRestPoses()` + `setFbxRestPoses()` を実行（commit dd845d5）
2. `computedRestSA` マップ追加: ARP_BONE_REST 未登録ボーン（hand/finger/foot/toes）の f0 を `inv(parent_restLocal) * bone_restLocal` で動的計算
3. f0 優先順位変更: ARP_BONE_REST → computedRestSA → frame0Map

**重要な知見**:
- `restSelfArmature` は累積ワールド回転ではなく `inv(parent_restLocal) * bone_restLocal`
- 以前の restPoseCache は `restLocal` そのものだったため、body bones（restSelfArmature）と空間が一致していなかった

---

## 関連ファイル

| ファイル | 説明 |
|---------|------|
| `src/adapters/retargetMixamoToVrm.ts` | リターゲット実装本体 |
| `src/loaders/animationLoader.ts` | アニメーションローダー（extractBoneRestPoses） |
| `tools/export_arp_bone_rest.py` | Blender スクリプト: ARP rest pose 取得 |
| `C:\Users\admin\Downloads\arp_bone_rest_arp.json` | Blender export 結果（handl/handr は空） |
