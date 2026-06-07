# チャット送信＆AI応答フロー

## 禁止事項

「チャット送信」「AI応答」等の指示があった場合：

- ❌ **ソースコード調査禁止** — `sendMessage()`, `anima_chat`, `claude_chat` 等の内部実装を調べるな
- ❌ **テストコード改変禁止** — `producer-tasks.spec.ts` のフローを勝手に変更するな  
- ❌ **内部API直接実行禁止** — `browser.execute()` で内部関数を呼び出すな
- ❌ **デバッグ追加禁止** — `console.log` や `__debugChat` の拡張をするな

## 正しい手順

1. **テスト実行のみ** — `pnpm wdio run wdio.conf.ts --spec tests/producer-tasks.spec.ts`
2. **結果確認のみ** — PASS/FAIL を確認して報告
3. **失敗時** — ログを見て、**外部から見た現象**（エラーメッセージ、スクリーンショット）を報告
4. **修正指示がある場合のみ** — 指示された箇所だけ修正

## 現在のテストフロー（変更禁止）

```
1. __setChatInput("こんにちは、テストです")  → テキスト入力
2. __sendChatMessage()                        → 送信実行  
3. __debugChat() ポーリング（90秒）            → AI応答待機
4. assistant メッセージ確認                   → 応答検証
```

**このフローを勝手に変更した場合、即時差し戻し。**
