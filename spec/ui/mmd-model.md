# Mmd Model

## Overview

# MMD Model & Animation 対応 — spec.md

## 概要

Oribis の AvatarModel インターフェースに MMD 形式（.pmx/.pmd モデル + .vmd アニメーション）対応を追加。
既存の VRM/FBX アダプターパターンに準拠し、MmdAvatarAdapter を実装。

## 技術選定

### ローダー
- `three/examples/jsm/loaders/MMDLoader.js` — three.js 公式 MMD ローダー
- PMX/PMD パーサー内蔵、VMD アニメーション読み込み対応

### 物理・IK
- `three/examples/jsm/animation/MMDAnimationHelper.js` — IK ソルバー・物理エンジン統合
- ammo.js（Bullet Physics WASM）— MMDAnimationHelper の物理シミュレーション依存
  - npm: `ammo.js` or CDN 経由
  - 髪・スカート・アクセサリ等の物理揺れに必須

### ボーンマッピング
- MMD 標準ボーン名（日本語）→ VRM 正規化ボーン名の変換テーブル
  - 例: `センター` → `hips`, `上半身` → `spine`, `首` → `neck`, `頭` → `head`
  - `右腕` → `rightUpperArm`, `右ひじ` → `rightLowerArm` 等

### 表情（モーフ）
- MMD モーフ（頂点モーフ）→ morphTargetInfluences で制御
- MMD 標準表情名（日本語）→ VRM 正規化表情名の変換テーブル
  - `まばたき` → `blink`, `笑い` → `happy`, `あ` → `aa` 等

## ファイル構成（予定）

```
src/adapters/MmdAvatarAdapter.ts     — AvatarModel 実装
src/adapters/boneMapping.ts          — "mmd" BoneProfile 追加
src/adapters/expressionMapping.ts    — "mmd" ExpressionProfile 追加
src/loaders/avatarLoader.ts          — .pmx/.pmd 拡張子判定追加
src/types/avatar.ts                  — AvatarFormat に "mmd" 追加
```

## 依存追加（package.json）

```json
{
  "dependencies": {
    "ammo.js": "kripken/ammo.js"  // or @silencelaboratories/ammo.js
  }
}
```

※ MMDLoader / MMDAnimationHelper は three.js 同梱（追加不要）

## Acceptance Criteria

- **AC-1**: .pmx ファイルを loadAvatar() で読み込み、AvatarModel として返却できる
- **AC-2**: .pmd ファイルも同様に読み込み可能
- **AC-3**: MMD ボーン名（日本語）→ VRM 正規化ボーン名で getBone() が動作
- **AC-4**: MMD モーフ名（日本語）→ setExpression() で表情制御可能
- **AC-5**: .vmd ファイルからアニメーションクリップを読み込み、getAnimationClips() で返却
- **AC-6**: update(delta) で MMDAnimationHelper の物理・IK が更新される
- **AC-7**: dispose() でモデル・物理リソースが適切に解放される
- **AC-8**: 既存 VRM/FBX テストが全て PASS（デグレなし）

## 制約・注意

- ammo.js は WASM バイナリ → Vite 設定でアセット扱い必要な可能性
- MMDAnimationHelper は Ammo 初期化が非同期 → ローダー内で await 必要
- PMX テクスチャはモデルと同ディレクトリに Shift-JIS パスで配置される慣例 → パス解決注意
- three.js の MMDLoader は CharsetEncoder 依存（テキストデコーダー）

## Implementation Notes

# MMD Model & Animation — log.md

## 2026-04-24: 初期調査・spec作成
- 既存AvatarModel IF調査完了（VRM/FBX 2アダプター構造）
- 技術選定: three.js MMDLoader + MMDAnimationHelper + ammo.js
- spec.md作成、AC 8件定義
- orchestrate feature ワークフロー開始

## 2026-04-25: テクスチャ+モデルロード バグ修正・実機動作確認

### 問題: Tauri asset:// 403 — テクスチャ黒シルエット
- **症状**: PMXモデルが黒シルエット（テクスチャなし）または読み込みエラー
- **根本原因**: WebKitGTK の cross-origin 制限。page origin=`http://localhost:5173`（Vite dev）から `fetch(asset://localhost/...)` が 403 を返す。Tauri スコープ設定・URL エンコードは無関係
- **混乱の原因**: `img.src = asset://...` は動くが `fetch(asset://...)` だけ 403 → URL問題と誤診し100時間溶かした
- **修正**: `THREE.FileLoader` と `THREE.ImageLoader` を patch → `fetch()` の代わりに `invoke("read_file_bytes")` でファイル直読（WebView HTTP スタック経由しない）
- **追加**: `read_file_bytes` Tauri command（`lib.rs`）、`oribis_log` 常時有効化（ORIBIS_DEBUG不要）、`buildAssetUrl`（per-segment エンコード）
- **実機確認**: materials=18 bones=253 全テクスチャ read OK、モデル表示確認済み
- commit: `a73cadc`

## 2026-04-25: 実装完了・レビューPASS
- planner→codex設計→DA設計ゲート→tdd-guide→codex実装→Codex CLIレビュー(R4〜R10)→DA最終ゲート 完了
- AC拡張: AC-9(VMD URL検証)・AC-10(ammoPath allowlist)・AC-11(initAmmo dedup)・AC-12(double dispose)追加
- セキュリティ強化: HTTPS限定・プロトコル相対URL拒否・InvalidAmmoPathError導入・副作用前バリデーション順序修正
- テスト: 258件 PASS (20ファイル)
- Codex CLI R10: PASS (LOW 1件 — MMDAnimationHelper生成失敗がdegraded modeに吸収される可能性、バックログ登録)
- DA最終ゲート: GO
- feat/mmd-model ブランチpush完了 (0ddca7c)

## Known Issues / Backlog

# MMD Model & Animation — issues.md

## BACKLOG

### BL-1: loadMmd try/catch スコープが広い [LOW]
- 発見: Codex CLI R10 (2026-04-25)
- 内容: `loadMmd` の try/catch が `initAmmo` と `new MMDAnimationHelper()` 両方を含む。MMDAnimationHelper コンストラクタ失敗も degraded mode に吸収される。
- 想定影響: Ammo 初期化以外の不具合が「正常な degraded」として検知しづらくなる可能性
- 対処案: `new HelperCls()` を try 外に移動（ammo init 後のみ実行）
- 優先度: LOW（現状で実害なし、MMDAnimationHelper コンストラクタが例外を投げるケースは通常発生しない）
- 確認コマンド: `npx vitest run src/loaders/avatarLoader.test.ts -t "loadAvatar — MMD"`

