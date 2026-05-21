# 商用I/Oチャネル設計: Discord有無両対応

**作成日**: 2026-05-21
**ステータス**: 方針確定
**関連**: design-oribis-commercial-20260520.md（商業化設計書v4）

## 背景

Oribis商用プロダクトとしてのI/Oチャネル設計。Discord Bot（discord-hubプラグイン）を含むマルチチャネル対応の方針を確定する。

### Producer指摘の課題
- Oribisデスクトップ: 3Dアバター・音声・記憶蓄積が強み。遅い・起動が面倒・小回り利かないのが弱み
- Discord CLI: 最速の指示方法。外出先では3D/音声不要
- 「Discordプラグイン使えば同じことできそうだが小回り利かない」
- 商用利用前提でDiscord有無両方対応が必要

## 確定方針

### I/Oチャネル階層

| チャネル | 位置づけ | 機能範囲 | 課金 | 規約制約 |
|---------|---------|---------|------|---------|
| Oribisデスクトップ | Primary | フル機能（3D/音声/Plugin/MCP/記憶） | Oribis側 | なし |
| Oribis WebUI/PWA | Primary（制限付き） | テキスト+記憶+軽量UI。OS統合/Plugin実行は制限 | Oribis側 | なし |
| Discord Bot | Secondary（オプション） | 通知+短文指示+テキスト応答のみ | なし（無料機能のみ） | Discord Developer Policy適用 |

### アーキテクチャ: 3層構成

```
Channel Adapter（Plugin V2として実装）
  - discord-hub（既存）
  - slack-hub（将来）
  - teams-hub（将来）
  - line-hub（将来）
  - web-chat（将来: WebUI/PWA用）

        ↓ InputEvent正規化

Oribis I/O Gateway（Rust Core内）
  - 認証・ユーザー識別
  - 同意状態確認
  - レート制限
  - 監査ログ
  - データ分類（短期処理/長期記憶/分析ログ）
  - 課金権限チェック
  - チャネル別ポリシー適用

        ↓

Oribis Core
  - Agent Runtime（Anima）
  - Memory（memory_db）
  - Plugin V2
  - MCP Broker
  - STT/TTS
  - Avatar State
```

### InputEvent正規化フォーマット

```
InputEvent {
  user_id: String,
  workspace_id: String,        // guild_id / tenant_id
  channel_type: ChannelType,   // Desktop / WebUI / Discord / Slack / ...
  channel_message_id: String,
  input_type: InputType,       // Text / Voice / Command / File / Reaction
  content: String,
  consent_state: ConsentState, // Granted / NotGranted / Revoked
  retention_policy: RetentionPolicy,
  allowed_capabilities: Vec<Capability>,
  source_metadata: JsonValue,
}
```

## Discord規約制約と対策

### 制約一覧

| # | 制約 | 対策 |
|---|------|------|
| 1 | メッセージ内容のAI/ML学習利用禁止 | 記憶蓄積はオプトイン明示同意+コマンド起点のみ。受動的読み取り禁止 |
| 2 | Bot有料機能はPremium Apps経由課金必須（手数料15〜30%） | Discord Bot側は無料機能のみ。有料機能はOribisアプリ側で課金 |
| 3 | プライバシーポリシー・データ削除機能必須 | /privacy, /forget_me, /export_data, /memory_off コマンド実装 |
| 4 | Message Content Intent: 100サーバー超で審査必要 | メンション/スラッシュコマンド/DM中心設計。Intent依存最小化 |
| 5 | APIデータの広告・ブローカー販売禁止 | 該当用途なし |

### Shapes.inc BAN事例（2025年5月）からの教訓

- 10万+AI Bot一斉BAN、3000万ユーザーに影響
- 違反理由: メッセージ内容AI学習利用、データ削除要求無視、トークン不正管理
- **最重要対策**: 「読めるものは全部読んでフィルタ」禁止 → 最初から取得範囲を狭める

## 記憶蓄積ポリシー

### データ分類

| 分類 | 用途 | 保存先 | Discord由来 |
|------|------|--------|------------|
| 短期処理 | 応答生成のための一時利用 | メモリ内（揮発） | 許可 |
| 長期記憶 | ユーザー同意に基づく永続保存 | memory_db | オプトイン同意時のみ |
| 分析ログ | 個人識別性除去の運用メトリクス | ログDB | 匿名化後のみ |
| 学習利用 | **禁止** | — | **禁止** |

### Discord由来データの保存ルール

**保存可能:**
- 同意済みユーザー本人がBotに送ったDM
- 同意済みユーザー本人がBotへのメンション/コマンドで送った内容
- Botの応答
- ユーザーが明示的に「これを記憶して」と指定した内容

**保存禁止:**
- 同意していないユーザーの発言
- チャンネルの周辺文脈
- サーバー全体の会話ログ
- Botが受動的に読んだメッセージ内容
- 第三者に関する情報（同意済みユーザーAの会話内でも、未同意ユーザーBに言及する内容）

### 同意管理要件

- Discord由来データに `source=discord` タグ必須
- 同意日時・バージョン・文面を監査ログ保存
- 撤回機能 + 撤回後の新規保存即時停止
- DM/サーバー/スレッド/チャンネルごとに保存対象を制御可能
- サーバー管理者の同意と個々のユーザーの同意を混同しない

### Kill Switch

- インシデント時にDiscord由来データの保存を即時停止する機能
- 管理コマンド or 環境変数で即時切替可能にする

## 課金経路の分離

### Discord Botで許可する機能

- 無料の通知受信
- 簡易テキスト指示送信
- Oribis本体を開くための案内
- 記憶のオン/オフ確認
- ヘルプ・ステータス確認
- /privacy, /forget_me, /export_data, /memory_off

### Discord Botで提供しない機能

- 有料プラン限定のAI実行
- 有料プラン限定の長文生成
- 有料プラン限定のPlugin/MCP実行
- 有料プラン限定のファイル処理
- 外部決済への強い誘導

### 設計原則
- Bot自体に課金機能を持たせない
- Bot利用可否をOribisサブスク状態に連動させない
- 有料機能の成果物をBot経由で受け取れないようにする

## discord-hub Plugin V2 現状と拡張方針

### 現状（v1.0.0）
- Bot token設定ウィザード（4ステップ）
- guild/channel選択
- メッセージ送信（Bot API + Webhook）
- capabilities: tauriInvoke, storage, uiSidebarPanel, events

### 商用向け拡張（将来）
- 記憶蓄積オプトイン同意UI
- /privacy, /forget_me, /export_data スラッシュコマンド
- チャネル別記憶ポリシー設定
- Message Content Intent依存の最小化（スラッシュコマンド中心）
- サーバー管理者向けデータ利用設定UI

## WebUI/PWAの制約（Codex Adviser指摘）

Oribisデスクトップと同等の「制約なし」ではない:
- ブラウザ制約: マイク権限、バックグラウンド動作、ローカルファイルアクセスにOS/ブラウザ差
- SQLiteローカル永続化はTauriほど自由でない
- Plugin V2/MCP BrokerのWeb利用 → サンドボックス・CORS・認証境界の設計が必要
- DB同期 → クラウド同期・暗号化・削除・データ移行の問題

## チャネル別規約差サマリー

| チャネル | 主要制約 |
|---------|---------|
| Discord | 課金・ML学習利用・Message Content Intent |
| Slack | ワークスペース管理者権限、Enterprise Grid、データ保持ポリシー |
| Teams | Microsoft Entra ID、組織テナント、監査・DLP |
| LINE | アカウント連携・同意・メッセージ課金 |
| WebUI | 認証・セッション・CSRF・XSS |
| Desktop | Plugin/MCP実行権限の境界 |

## Codex Adviser指摘事項

### 高優先度
1. WebUI/PWAは「制約なし」ではない → 機能階層を正確に定義
2. オプトイン同意だけでは不十分 → 第三者発言保存禁止・データ分類・撤回機能必須
3. 課金分離の落とし穴 → Bot経由有料機能実行はグレーゾーン
4. Shapes.inc対策 → 取得範囲を最初から狭める設計

### 中優先度
5. チャネルごとの規約差をCoreに漏らさずPolicy Engineで吸収
6. Bot審査前にデータフロー図+保存ポリシー文書化
7. 100サーバー到達前にMessage Content Intent審査対応
8. 法務レビュー推奨（本番投入前にDiscord最新規約+個人情報保護法確認）

## Producer原文
- 「そんで、Oribis使うより、Discord（tmux）でCLIに指示送るのが一番簡単問題の解決策」
- 「Oribis使うメリット→記憶データ構築。ボイスで指示、３Dアバター表示演出、読み上げ→外出先とかではいらない」
- 「デメリット→遅い。アプリ開くのだるい。Discordプラグイン使えば今と同じように可能なきはするが、やっぱ小回り利かない」
- 「商用化として問題ないか。Discord商用利用→規約違反など。」
- 「Discord使わない場合も考えて」
- 「2代目→ふざけるな　商用利用前提で考えろ。Discordあり無しどっちも使う想定。なしは現状で問題ない気がするが??」
- 「Oribisプラグインの機能っていう前提だが合ってる?　違うならそうして　あとはよろしく」
