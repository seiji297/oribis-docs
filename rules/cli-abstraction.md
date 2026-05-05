# CLI抽象化ルール

## CLI機能抽象化必須（全新機能共通・例外なし）

**CLIに関係する全機能は Claude CLI / Codex / OpenClaw の3バックエンドで動作すること。**

### ルール

1. Tauri command 名にバックエンド名を含めない
   - ❌ `cancel_claude_chat` / ❌ `codex_cancel`
   - ✅ `cancel_chat` / ✅ `send_message`

2. バックエンド分岐は `match backend_type {}` のみ許容。重複実装禁止。

3. 新規 Tauri command 設計時のチェックリスト:
   - [ ] Claude CLI で動作するか
   - [ ] Codex で同等動作するか
   - [ ] OpenClaw で同等動作するか（未実装なら stub で OK、但し設計に明記）

4. `ProjectChatState` への直接バックエンド依存コード追加禁止。
   共通メソッド（例: `cancel_current_generation()`）として実装すること。

### 参照

- 詳細設計: `spec/core/pipeline.md §13`
- 原則: `spec/core/overview.md §2.6`

---

## cancel_chat（生成中断）

- **Rust**: `cancel_chat(project_id)` → `ProjectChatState.cancel_current_generation()` → SIGINT送信
- **Frontend**: `cliState === 'thinking'|'responding'` 時のみストップボタン表示。新規送信時も自動キャンセル先行。
- **詳細**: `spec/core/pipeline.md §13`
