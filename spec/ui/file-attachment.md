# File Attachment

## Overview

# FEAT-②: ファイル添付機能 (File Attachment)

作成: 2026-04-24 / Producer指示

## 概要

チャット入力欄からファイルを添付し、CLIに読み込ませる機能。

## ユーザー操作フロー

1. クリップアイコン押下 or ファイルドラッグ&ドロップ
2. ファイル選択ダイアログ（複数可）
3. 添付ファイル名がチャット入力欄にバッジ表示
4. 送信時、ファイルパスがメッセージに自動付加
5. CLIがファイル内容を読み込んで返答

## 技術設計方針

- `openDialog`（Tauri plugin-dialog）はすでにApp.tsxでimport済み → 追加依存なし
- メッセージへの付加フォーマット: `@/path/to/file.txt` (Claude Code標準)
- 複数ファイル対応
- 添付ファイルのプレビュー表示（ファイル名 + サイズ）

## 受け入れ条件 (AC)

- AC-1: クリップアイコンからファイル選択できる
- AC-2: 選択ファイル名が入力欄に表示される
- AC-3: 送信時にファイルパスがメッセージに含まれる
- AC-4: CLIがファイル内容を参照して返答する
- AC-5: 添付をキャンセルできる

## 優先度
MEDIUM（①完了後）

## ステータス
**COMPLETE** (2026-04-24) — ブランチ: `feat/file-attachment-clean`

## 既知の制限（バックログ）
- 空白含みパスは未対応（MVP制約）。将来的にクォート形式対応予定
- Unicode/記号含みパスは未対応

## Implementation Notes

# FEAT-②: ファイル添付機能 実装ログ

## 2026-04-24 完了

### 実装フロー
- planner → codex設計(FAIL x1) → DA設計ゲート(CONDITIONAL_PASS) → tdd-guide → codex-reviewer(R1〜R6) → DA最終ゲート(GO)

### 主要決定事項
- `attachedFilesByProject: Record<string, string[]>` — inputByProjectと同パターン
- `@path` 形式 — Claude Code標準。stream-json経由でJSON文字列として送信
- 空白含みパス: MVP制約として拒否（`/[\x00-\x1f\x7f ]/`）
- クリア: invoke成功後のみ（失敗時は保持→再送可）
- handleAttachFiles: projectId早期束縛（ダイアログ中切替対策）

### Codexレビュー変遷
- R1: 制御文字バリデーション追加
- R2: try/catch追加
- R3: DualSession混入検出 → クリーンブランチ作成
- R4: 空白拒否・invoke後clear・T16/T18/T19
- R5: projectId早期束縛・T20
- R6: PASS

### テスト
- T1〜T20（20件）全PASS
- 全テスト: 220 PASS

### コミット（feat/file-attachment-clean）
- `e218ed6`: FEAT-2 初期実装
- `ca3455b`: R4対処
- `4857e03`: R5対処
- push: origin/feat/file-attachment-clean

