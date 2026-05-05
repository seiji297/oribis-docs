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
