# 開発パターン知見

## codex-reviewer — 大差分で毎ラウンド新指摘（3ラウンド上限でDA移行）

差分規模が大きいと codex-reviewer は毎ラウンド別の懸念を発見する。3ラウンドFAIL後はDAに最終ゲート移行。codex が指摘する「構造的懸念」はコンテキスト理解不足の誤検出あり。DA判定で整理すること。

---

## React useEffect — try内のreturnでもfinallyは実行される

JavaScriptの `try { return; } finally { ... }` は `return` しても `finally` が実行される。ガードフラグを `finally` で立てる場合、早期 `return` 条件を **try の外** に置かないとガードが無効化される。

```typescript
// NG: null時でも finally が走りガードが外れる
try {
  if (condition === null) return;
} finally {
  guard.current = true;
}

// OK: null なら try に入らないので finally も実行されない
if (condition === null) return;
try {
  // ...
} finally {
  guard.current = true;
}
```

---

## SQLite json_each() — JSON配列カラムの安全な検索パターン

`topics TEXT NOT NULL` に `["tea","food"]` のようなJSON配列を格納する場合、LIKE検索はSQL injection リスクあり。`json_each()` + パラメータ化 IN 句で安全に検索する。

```rust
// NG: format!() でユーザー文字列を直接埋め込み
format!("topics LIKE '%\"{}\"'", user_input)

// OK: json_each() + parameterized IN
let sql = format!(
    "SELECT DISTINCT me.* FROM memory_events me, json_each(me.topics) je
     WHERE je.value IN ({}) LIMIT ?{}",
    placeholders.join(","),  // ?1, ?2, ...
    topics.len() + 1
);
```

---

## oribis-meta — LLM構造化出力のパースパターン

LLM応答末尾の `<oribis-meta>JSON</oribis-meta>` ブロックを正規表現で抽出し、serde_json でパース。失敗時は None（graceful fallback）。永続化は fire-and-forget（log::warn のみ、パイプライン非中断��。

```rust
// persist で raw_text / metadata の使い分け:
raw_text: format!("[{}] {}", event_type, topics.join(", ")),  // 人間可読
metadata: serde_json::to_value(meta).ok(),                     // 構造化データ
```

---

## Rust テスト — `dirs::home_dir()` 固定パスを base_dir 対応にする

`dirs::home_dir()` を直接使う関数は tmpdir ベースのテストが機能しない（テスト用ファイルではなく実ホームを参照する）。`base_dir` を受け取る設計にし、テスト時は base_dir 配下にディレクトリ構造を作成する。

**パターン**: 「base_dir にターゲット構造が存在すればそれを使い、なければ `dirs::home_dir()` ベースを使う」分岐ヘルパー。

```rust
fn oribis_prompts_dir(base_dir: &Path) -> PathBuf {
    let candidate = base_dir.join("roles").join("orchestrator").join("prompts");
    if candidate.exists() {
        return candidate;  // テスト: tmpdir 内の構造を使用
    }
    dirs::home_dir()       // 本番: ~/.oribis/...
        .unwrap_or_else(|| PathBuf::from("/tmp"))
        .join(".oribis").join("roles").join("orchestrator").join("prompts")
}
```

テスト側では `setup_prompts_dir()` で構造を作成してからファイルを配置する。

**注意**: 「ファイルが存在しない」テストでも `setup_prompts_dir()` は必要。ディレクトリ構造がないと `oribis_prompts_dir` が実ホームにフォールバックし、実ファイルが存在すればテストが失敗する。

---

## WSLg GUI テスト — PowerShell WinAPI + コード一時変更パターン

WSLg 環境での Tauri GUI テストは xdotool/wtype 等が座標変換やWayland制限で機能しない。有効な手法:

1. **PowerShell WinAPI**: `SetCursorPos` + `mouse_event` でWindowsネイティブ座標からクリック可能だが、DPI スケーリング不一致（X11: 3000x1920 vs Windows: 1920x1080）で精密な操作は困難
2. **コード一時変更 + HMR**: `useState` 初期値を変更してHMRリロード→スクリーンショット確認→revert。最も確実
3. **PowerShell EnumWindows**: 他ウィンドウを最小化して対象を最前面化

```bash
# スクリーンショット撮影
powershell.exe -Command "... CopyFromScreen ... Save ..."
# Readツールで画像確認
```

---

## Orchestrator P1 — codex-adviser レビュー指摘バックログ (2026-05-08)

P1 Epic完了後の総合レビューで指摘された技術的負債。WorkerInfo型不整合は即対処済み。
P1品質修正エピック(2026-05-08)でHIGH指摘3件全解消。

### ~~P2 対処予定 (HIGH)~~ → ✅ 全解消済
| # | 指摘 | 対応 | 完了 |
|---|------|------|------|
| 1 | narration cursor重複処理 — `compute_global_since()` が全workerの最小ULIDを返すため遅いworkerがいると既読イベント再取得 | ✅ per-worker incremental取得に実装済。`get_batch_for_worker`/`list_event_workers`追加。`compute_global_since()`にdeprecate注釈 | 2026-05-08 |
| 2 | kill_workerが論理削除のみ — in-memory解除だけでPTY/子プロセスが残る | ✅ PTY kill統合実装済。`lib.rs`の`kill_worker`コマンドが`pty_kill_core`→`kill_worker(deregister)`順序実行。`set_worker_pid`/`get_worker_pid`追加 | 2026-05-08 |
| 3 | write_event session auto-attach仮値 — worker/session_id両方にtoken_prefix | ✅ `ClientInfo`に`worker_id`/`worker_session_id`フィールド追加。`handle_write_event_in`で実worker_id→token_prefix fallback | 2026-05-08 |

### P2 対処予定 (MEDIUM)
| # | 指摘 | 対象 | 理由 |
|---|------|------|------|
| 4 | Speech Queue TTS完了推定 — text.length×80msでエンジン差無視 | useAnima.ts:303 | P2 TTS completion callback実装で対応 |
| 5 | event_feed.rs毎回全JSONL再走査+sync_all() | event_feed.rs:48,135 | P1規模では問題なし。P2でインクリメンタル読み取り検討 |
| 6 | spawn_workerがdepartment existence/max_workers未チェック | lib.rs, department_config.rs | P2 Department CRUD永続化で接続 |

### 即対処済み
| # | 指摘 | 対応 |
|---|------|------|
| 1 | WorkerInfo Rust/TS/UI型不整合 | Rust側にname/pid追加、TS側にsession_id/created_at統一、UI pid null-safe化。cargo test 11 PASS |
