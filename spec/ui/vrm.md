# Vrm

## Overview

# oribis/vrm — spec

## 概要
OribisにVRMアバター表示機能を追加。チャット画面にAnima.vrmを初期モデルとして表示する。

## AC一覧（ORIBIS-VRM-AVATAR）
- AC-1: 起動時にAnima.vrmが画面に表示される
- AC-2: チャットUIと共存するレイアウト（左VRM + 右チャット or VRM背景+オーバーレイ）
- AC-3: VRMファイル不在時にフォールバック表示（エラー表示or代替）
- AC-4: cargo test + frontend unit test PASS
- AC-5: cargo tauri dev で正常起動・VRMレンダリング確認済み
- AC-6: 既存チャット機能（RunGuard/stream-json）非破壊

## アーキテクチャ
- Frontend: React/Vite + @pixiv/three-vrm + Three.js
- Backend: Tauri fs::read（VRMバイナリ読み込み）またはURL経由
- VRMパス: C:\Users\admin\Documents\VRoidStudio\Anima.vrm

## 制約
- 初期実装はVRM表示のみ（アニメーション・リップシンク等は将来フェーズ）
- 既存チャット機能を壊さないこと

## Implementation Notes

# oribis/vrm — 実装ログ

## 2026-04-21: ORIBIS-VRM-AVATAR 完了

### ECCチェーン

| フェーズ | エージェント | 結果 |
|---------|------------|------|
| 設計 | planner | plan-oribis-vrm-20260421.md 作成 |
| 設計レビュー | codex-reviewer | PASS（指摘なし） |
| 設計ゲート | DA | 条件付きGO（HIGH-1 CSP / HIGH-2 パストラバーサル 指摘） |
| 実装 | tdd-guide | commit 24a8da6 / vitest 4 PASS / cargo test 33 PASS |
| コードレビュー | codex-reviewer | CONDITIONAL PASS（HIGH-1 SSOT違反 指摘） |
| HIGH-1 fix | tdd-guide | commit bdfa29b / SSOT解決（check_vrm_file→Option<String>返却） |
| 最終ゲート | DA | PASS |

### 最終コミット

- `24a8da6`: feat(vrm): add VRM avatar display with Anima.vrm
- `bdfa29b`: fix(vrm): return VRM path from backend to eliminate frontend hardcode (SSOT)

### 実装概要

- VRM表示: @pixiv/three-vrm v3.5.2 + @react-three/fiber + Three.js
- Tauri asset protocol でローカルVRMファイル読み込み
- 2カラムレイアウト（左VRM 40% / 右チャット flex:1）
- VRM不在時フォールバック表示（「Avatar model not found」）
- check_vrm_file: 引数なし / Result<Option<String>> 返却 / パスはRust側一元管理（SSOT）

## Known Issues / Backlog

# oribis/vrm — issues

## OPEN（バックログ）

| # | Severity | 内容 | 由来 |
|---|----------|------|------|
| VRM-BL-1 | MEDIUM | VRMロード失敗時フォールバック欠如（console.errorのみ） | Codex MEDIUM-1 |
| VRM-BL-2 | MEDIUM | ロードプログレス表示なし（数十MB対応） | Codex MEDIUM-2 |
| VRM-BL-3 | MEDIUM | Canvas alpha=true のCSS背景意図確認 | Codex MEDIUM-3 |
| VRM-BL-4 | LOW | Suspenseフォールバックテスト未検証 | Codex LOW-1 |
| VRM-BL-5 | LOW | URL変更時のdispose競合リスク | Codex LOW-2 |
| VRM-BL-6 | INFO | assetProtocol.scope ハードコード（配布時に設定化必要） | DA INFO-1 |

## CLOSED

| # | 内容 | 解決方法 | commit |
|---|------|---------|--------|
| DA-HIGH-1 | CSP connect-src 漏れ | tauri.conf.json修正 | 24a8da6 |
| DA-HIGH-2 | check_vrm_file パストラバーサル | Rust側ハードコード化（引数排除） | 24a8da6 |
| Codex-HIGH-1 | フロントVRMパスハードコード（SSOT違反） | check_vrm_file→Option<String>返却方式 | bdfa29b |

