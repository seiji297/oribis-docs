# 1mb Warning

## Overview

# Oribis 1MB Warning Feature Spec

## 概要
Claude CLI の累積出力が800KBを超えた時点でフロントエンドに `context-size-warning` Tauri イベントをemitし、警告バナーを表示する。

## 実装箇所
- `src-tauri/src/lib.rs`: SessionAccumulator, check_and_emit_warning, claude_chat統合
- `src-tauri/src/bin/fake_claude.rs`: warn_response(850KB), large_response(1.1MB) モード
- `src-tauri/tests/autotest.rs`: TASK-4-1MB 6件テスト
- `src/App.tsx`: listen/unlisten, contextSizeWarning state, 警告バナーUI
- `src/App.test.tsx`: vitest 3件テスト

## 設計ポイント
- SessionAccumulator: AtomicUsize、スレッドセーフ累積カウンタ
- コールバック注入パターン: cargo test でapp_handleなしにemit発火を検証可能
- ORIBIS_WARN_THRESHOLD_KB: 環境変数で閾値上書き（デフォルト800KB）
- 一方向遷移: 1セッション1回のみ警告発火（prev < threshold <= new_total）
- saturating_add/saturating_mul: オーバーフロー安全

## AC
- AC-1: 800KB超でコールバック発火
- AC-2: 1MB超でErr返却（既存動作維持）
- AC-3: context-size-warning受信→警告バナー表示
- AC-4: 累積カウンタ永続・メッセージごと加算
- AC-5: ORIBIS_WARN_THRESHOLD_KB で閾値変更可能
- AC-6: cargo test 35件PASS、vitest 7件PASS
- AC-7: tsc クリーン

## バックログ
- セッション境界でのreset（UX設計が必要）
- >=vs>境界の厳密化（実用上影響なし）
- claude_chat直接統合テスト（Tauri runtime制約）
- vitest act()警告修正

## Implementation Notes

# 1MB Warning Feature Log

## 2026-04-21 TASK-4-1MB 完了

- Agent Chain: planner(opus) → codex-reviewer(design) x6 → DA-design-gate → tdd-guide → codex-reviewer(code) x4 → DA-final-gate
- commit: ce207d5 on feature/task-4-1mb (seiji297/oribis.git)
- cargo test: 35件PASS（既存21件 + 新規14件）
- vitest: 7件PASS（既存4件 + 新規3件）
- DA最終ゲート: PASS
- 未merge（mainへのmergeはProducer指示待ち）

### 設計ハイライト
- コールバック注入パターンでTauri runtimeなしのcargo testを実現
- SessionAccumulatorはAtomicUsizeでスレッドセーフ
- env var ORIBIS_WARN_THRESHOLD_KB で閾値上書き可能
- serial_testクレートでenv var テスト競合回避

## Known Issues / Backlog

# 1MB Warning Issues

## バックログ（TASK-4-1MBスコープ外）

| # | 概要 | 優先度 | 出典 |
|---|------|--------|------|
| BL-1 | セッション境界でAccumulatorをリセットする機能（UX設計必要） | LOW | Codex r4 HIGH |
| BL-2 | 閾値判定を>=から>に変更（"800KB超"厳密化） | LOWEST | Codex r4 MEDIUM |
| BL-3 | claude_chatコマンド直接統合テスト（Tauri runtime制約回避） | LOW | Codex r4 LOW |
| BL-4 | vitest act()警告修正（非同期state更新のact外発生） | LOW | DA懸念 |

