# WDIO E2Eテスト実行ルール

## 絶対原則

WDIOテストを実行せよと言われたら、**テストを実行するだけ**。

## 禁止事項

- ❌ **内部ソース調査禁止** — `App.tsx`, `sendMessage()`, `anima_chat`, `claude_chat` 等の実装を調べるな
- ❌ **ソース改変禁止** — テストを通すために内部コードを修正するな
- ❌ **テストコード改変禁止** — `producer-tasks.spec.ts` のフローを勝手に変更するな
- ❌ **デバッグ追加禁止** — `console.log` や補助関数の追加・拡張をするな
- ❌ **理由調査禁止** — なぜ失敗するかを調べるな。失敗ログを貼れ。

## 正しい手順

```bash
cd oribis/e2e/wdio
pnpm wdio run wdio.conf.ts --spec tests/producer-tasks.spec.ts
```

結果をそのまま報告。PASSならOK。FAILならエラーログを貼れ。

## 例外

`__setChatInput` / `__sendChatMessage` / `__debugChat` は `App.tsx` に既存。これらは**改変禁止**（追加も削除もするな）。
