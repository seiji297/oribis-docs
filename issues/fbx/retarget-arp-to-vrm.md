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
const f0 = ARP_BONE_REST[vrmName]?.restLocal
         ?? frame0Map.get(vrmName);   // FBX frame 0 (= Blender bind pose)
```

`ARP_BONE_REST` は `tools/export_arp_bone_rest.py` で Blender から取得した `bone.matrix_local`（XYZWフォーマット）。

---

## 完了

| ボーン群 | 状態 | 備考 |
|---------|------|------|
| 腕全般 (upperArm/lowerArm/shoulder) | ✅ 修正済み | M=R に変更。`leftUpperArm Q_vrm[0]=(18.0,28.3,-70.4)` 確認 |
| leftHand / rightHand | ✅ 修正済み（要確認） | ARP_BONE_REST から削除 → frame0Map fallback。Blender export で `handl/handr` が空だったため。 |
| 脊椎 (hips/spine/chest/upperChest/neck/head) | 動作中（詳細未検証） | |

---

## 未解決・要調査

### 1. 手 (leftHand / rightHand) — 視覚確認待ち
- 修正内容: restLocal `[0,0,-0.707,0.707]`（推定値）を削除、FBX frame0 を f0 として使用
- **Tauri 再起動後に Typing アニメで手の向きを確認**
- ARP_DEBUG に leftHand Q_vrm を追加してログ確認が必要

### 2. 脚のクロスレッグ座り — 原因未特定
- Typing アニメ表示時に脚がクロスレッグ座りになっている
- 原因候補 A: Typing FBX 自体がクロスレッグ座りアニメ（Blender で確認必要）
- 原因候補 B: 脚ボーン (leftUpperLeg/leftLowerLeg) のリターゲット誤り
  - `leftUpperLeg.restLocal = [-0.825, 0.006, -0.565, 0.009]` ≈ euler(167.7°, 68.7°, 0°) と大きい
  - ARP_BONE_REST 値が正しいかどうか未検証
- **確認方法**: Blender で元 FBX を開き Typing アニメのポーズを確認

### 3. 指ボーン — 未実装
- ARP_BONE_REST に指のデータなし
- 指は全て frame0Map fallback → 精度未検証
- Typing アニメで指が曲がるはずだが視覚確認できていない

### 4. デバッグログ削除 — 後で
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

1. **Tauri 再起動 → Typing アニメで手の向き確認**（視覚 or leftHand Q_vrm ログ）
2. **Blender で Typing FBX 原本確認** → クロスレッグ座りが仕様か否か
3. 脚ボーン問題であれば → `export_arp_bone_rest.py` 再実行して足含む全ボーン再取得
4. 全ボーン OK 確認後 → デバッグログ削除
5. commit & merge

---

## 関連ファイル

| ファイル | 説明 |
|---------|------|
| `src/adapters/retargetMixamoToVrm.ts` | リターゲット実装本体 |
| `tools/export_arp_bone_rest.py` | Blender スクリプト: ARP rest pose 取得 |
| `C:\Users\admin\Downloads\arp_bone_rest_arp.json` | Blender export 結果（handl/handr は空） |
