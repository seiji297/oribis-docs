# Discord Bot テスト証跡

作成日: 2026-05-20

## テスト実行結果

### TypeScript (vitest)

- 実行コマンド: `pnpm --filter @oribis/discord-bot test`
- テストファイル数: 13
- テスト数: 187
- 結果: 全PASS

```
 Test Files  13 passed (13)
      Tests  187 passed (187)
   Duration  2.14s
```

### TypeScript typecheck

- 実行コマンド: `pnpm --filter @oribis/discord-bot typecheck`
- 結果: 0 errors

### Rust (cargo test)

- 実行コマンド: `cd src-tauri && cargo test -- --test-threads=1 worker`
- workerテスト: PASS（46 passed, 1180 filtered out）
- 既存テスト: デグレなし

---

## AC照合マトリクス

| AC | テスト内容 | テストファイル | テスト件数 | 結果 |
|----|-----------|-------------|----------|------|
| AC-1 | Bot起動・コマンド登録・権限チェック | tests/bot.test.ts, tests/commands/index.test.ts | 28 | PASS |
| AC-2 | /start, /stop, /status コマンド | tests/commands/start.test.ts, tests/commands/stop.test.ts, tests/commands/status.test.ts | 26 | PASS |
| AC-3 | /say, /expression, /notify コマンド | tests/commands/say.test.ts, tests/commands/expression.test.ts, tests/commands/notify.test.ts | 34 | PASS |
| AC-4 | /memory search | tests/commands/memory.test.ts | 9 | PASS |
| AC-5 | /worker list | tests/commands/worker.test.ts + cargo test worker | 9+46 | PASS |
| AC-6 | MCP認証・ブローカー通信 | tests/broker-client.test.ts | 29 | PASS |
| AC-7 | プロセス管理（起動/停止/状態確認） | tests/process-manager.test.ts, src/lib/__tests__/process-manager.test.ts | 52 | PASS |
| AC-8 | 全テストPASS | CI (vitest + cargo test) | 187+46 | PASS |

---

## テストファイル詳細

### tests/process-manager.test.ts（16テスト）
re-export（src/process-manager.ts）経由のインテグレーションテスト。

- startOribis(): PIDファイルなし→spawn+PIDファイル書き込み
- startOribis(): 有効PIDファイル存在→AlreadyRunningError
- startOribis(): スタレPID（/proc存在せず）→起動成功
- startOribis(): spawn PID未返却→Error
- stopOribis(): SIGTERM送信→PIDファイル削除
- stopOribis(): PIDファイルなし→NotRunningError
- stopOribis(): スタレPID→NotRunningError
- stopOribis(): process.kill例外→クリーンアップして正常終了
- getStatus(): PIDファイルなし→{running:false}
- getStatus(): スタレPID→{running:false}
- getStatus(): 起動中→{running:true, pid, socketPath}
- getStatus(): 起動中+uptimeを計算
- getStatus(): ソケットなし+pgrepなし→{running:false, pid}
- isRunning(): 起動中→true
- isRunning(): 未起動→false
- isRunning(): スタレPID→false

### src/lib/__tests__/process-manager.test.ts（36テスト）
プロセス管理ユニットテスト（lib直接インポート）。

- readPidFile: 正常PID取得, 非数値→null, ファイル不在→null, pid<=0→null（4テスト）
- writePidFile: mode 0o600でPID文字列書き込み（1テスト）
- removePidFile: PID_FILE削除, 不在時もthrowなし（2テスト）
- isPidAlive: /proc/{pid}存在→true, 不在→false（2テスト）
- resolveSocketPath: /tmp/oribis-broker-{pid}.sock形式（1テスト）
- getStartScript: 環境変数優先, 未設定時はモジュール相対パス（2テスト）
- startOribis: spawn確認・PID書込み・ORIBIS_START_SCRIPT・AlreadyRunningError・スタレPID・spawn失敗・ガード2・ガード3（8テスト）
- stopOribis: SIGTERM+クリーンアップ・SIGKILLフォールバック・NotRunningError各種・kill例外・ソケット削除（7テスト）
- getStatus: 各状態パターン・uptime計算（8テスト）
- isRunning: running=true/false（2テスト）

### tests/commands/start.test.ts（9テスト）
/start コマンド。

- コマンドメタデータ: name='start', Administrator権限, オプションなし（3テスト）
- isRunning=true→既に起動中Embed(黄)
- 正常起動→deferReply+startOribis→成功Embed(緑)
- BrokerClient connect/authenticate呼び出し確認
- タイムアウト→タイムアウトEmbed(赤)
- startOribis例外→エラーEmbed(赤), クラッシュなし
- finally: broker.disconnect呼び出し確認

### tests/commands/stop.test.ts（7テスト）
/stop コマンド。

- コマンドメタデータ: name='stop', Administrator権限（2テスト）
- 正常停止→成功Embed(緑)
- NotRunningError→未起動Embed(黄)
- その他例外→エラーEmbed(赤)
- stopOribis呼び出し確認
- 権限なし→403応答

### tests/commands/status.test.ts（10テスト）
/status コマンド。

- コマンドメタデータ（2テスト）
- 起動中→実行中Embed(緑)+pid/socketPath/uptime
- 未起動→停止Embed(赤)
- uptime表示フォーマット確認
- socketPathなし→表示省略
- getStatus例外→エラーEmbed
- 各種フィールド表示確認

### tests/commands/say.test.ts（13テスト）
/say コマンド。

- コマンドメタデータ（2テスト）
- 正常発話→成功Embed
- 空文字列→バリデーションエラー
- BrokerClient経由toolCall確認
- 未起動時→NotRunningError対応
- エラーハンドリング各種

### tests/commands/expression.test.ts（10テスト）
/expression コマンド。

- コマンドメタデータ（2テスト）
- 正常表情変更→成功Embed
- 未知表情→エラー
- BrokerClient経由toolCall確認
- エラーハンドリング各種

### tests/commands/notify.test.ts（11テスト）
/notify コマンド。

- コマンドメタデータ（2テスト）
- 正常通知→成功Embed
- 各通知タイプ（info/warning/error）確認
- BrokerClient経由toolCall確認
- エラーハンドリング各種

### tests/commands/memory.test.ts（9テスト）
/memory コマンド。

- コマンドメタデータ（2テスト）
- memory search→結果Embed
- 結果なし→空Embed
- BrokerClient経由toolCall確認
- エラーハンドリング各種

### tests/commands/worker.test.ts（9テスト）
/worker コマンド。

- コマンドメタデータ（2テスト）
- worker list→一覧Embed
- ワーカーなし→空Embed
- BrokerClient経由toolCall確認
- エラーハンドリング各種

### tests/commands/index.test.ts（19テスト）
コマンドレジストリ・ルーター・権限チェック。

- 全コマンド登録確認
- 未知コマンド→無視
- 権限不足→403応答
- インタラクションルーティング確認
- 各コマンドexecute呼び出し確認

### tests/bot.test.ts（9テスト）
Bot初期化・ライフサイクル。

- Bot作成・Discord.jsクライアント初期化
- ready イベント処理
- interactionCreate イベント処理
- エラーハンドリング

### tests/broker-client.test.ts（29テスト）
MCP BrokerClient + NdjsonBuffer。

- NdjsonBuffer: 完全行返却・不完全チャンクバッファ・複数行・空行無視・clear（6テスト）
- connect(): authenticate送信・ready状態・PIDファイルエラー・auth_error・既接続・タイムアウト（6テスト）
- heartbeat(): 送受信・重複スキップ・非ready時エラー（3テスト）
- auto heartbeat: 定期発火・disconnect後停止（2テスト）
- toolCall(): tool_result解決・エラー応答・非ready・disconnect時reject（4テスト）
- listTools(): tools_array返却（1テスト）
- resourceRead(): resource_result返却（1テスト）
- disconnect(): closed遷移・冪等性（2テスト）
- auto-reconnect: 再認証・explicit disconnect後非reconnect・max retry後error・unexpected close時reject・タイムアウトpending cleanup（5テスト）

---

## 検証コマンド

```bash
# TypeScript全テスト
pnpm --filter @oribis/discord-bot test

# typecheck
pnpm --filter @oribis/discord-bot typecheck

# Rustワーカーテスト
cd /home/mnadmin/agent-projects/sysdev/sysdev-1/oribis/src-tauri
cargo test -- --test-threads=1 worker
```
