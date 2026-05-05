# Anima

## Overview

# AnimaState 仕様書

## AnimaState 一覧

| State | トリガー条件 | expression | intensity | motion | gaze |
|-------|------------|------------|-----------|--------|------|
| `idle` | 待機中（デフォルト） | neutral | 0 | none | none |
| `working` | ツール呼び出し中 | thinking | 0.5 | think | down |
| `done` | タスク完了 | neutral | 0 | none | none |
| `error` | エラー発生 | sad | 0.6 | none | camera |
| `greeting` | セッション開始 | neutral | 0 | none | camera |
| `idle_long` | 長時間待機後 | neutral | 0.2 | none | away |
| `resume` | コンテキスト圧縮復帰後 | neutral | 0 | none | camera |
| `lewd` | 不適切操作検出時 | sad | 0.8 | shake | away |

## モーション一覧（現在使用中）

| motion | 説明 |
|--------|------|
| `none` | モーションなし |
| `think` | 思考モーション（working状態） |
| `shake` | 拒否モーション（lewd状態） |

## フレーズカテゴリ

| カテゴリ | フレーズ数 | 対応 AnimaState / イベント |
|---------|-----------|--------------------------|
| `greeting` | 20 | greeting |
| `idle` | 20 | idle |
| `idle_long` | 30 | idle_long |
| `resume` | 10 | resume |
| `tool.bash` | 5 | working（bash/computer） |
| `tool.edit` | 5 | working（str_replace_editor） |
| `tool.write` | 5 | working（write_file） |
| `tool.read` | 5 | working（read_file/list_files） |
| `tool.search` | 5 | working（web_search/glob/grep） |
| `success` | 5 | done |
| `error` | 5 | error |
| `thinking` | 10 | working（思考フェーズ） |
| `lewd` | 10 | lewd |

## TOOL_TO_KEY マッピング

| ツール名 | フレーズキー |
|---------|------------|
| bash | tool.bash |
| str_replace_editor | tool.edit |
| write_file | tool.write |
| read_file | tool.read |
| web_search | tool.search |
| list_files | tool.read |
| glob | tool.search |
| grep | tool.search |
| computer | tool.bash |

## 型定義

```typescript
type AnimaState = "idle" | "working" | "done" | "error" | "greeting" | "idle_long" | "resume" | "lewd";

interface ControlAvatarPayload {
  expression: string;  // "neutral" | "thinking" | "sad" | ...
  intensity: number;   // 0.0 - 1.0
  motion: string;      // "none" | "think" | "shake" | ...
  gaze: string;        // "none" | "camera" | "down" | "away" | ...
}
```

## 実装ファイル

- `src/hooks/useAnima.ts` — AnimaState管理・フレーズ選択・STATE_AVATARマッピング

