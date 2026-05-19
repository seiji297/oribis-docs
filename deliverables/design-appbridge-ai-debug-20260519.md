# AppBridge AI Debug System — 設計書 v3

**作成日**: 2026-05-19
**最終更新**: 2026-05-20
**ステータス**: P0実装完了（全8タスク・1339テストPASS）
**ブランチ**: `sysdev-1/appbridge-debug`
**関連**: Horror-1 AIBridge, Oribis Orchestrator, Viewer Epic

## 1. 背景・目的

Horror-1ではAIBridge（TCP:9999）でGodot headlessをAI駆動デバッグしている。
この仕組みをOribisオーケストレーターに**エンジン非依存**で搭載し、任意の外部アプリケーション（Godot, Unity, ブラウザ, CLIツール等）をAI駆動でデバッグ・テスト可能にする。

### 設計原則
- **Godot特化しない**: GodotのAIBridgeは一実装に過ぎない
- **テキスト主体**: AIの主入力はJSON状態 + テキストログ。画像分析は補助
- **Horror-1互換**: 既存AIBridge（TCP:9999）を無改修で接続可能
- **MCP公開**: オーケストレーターのMCPツールとして外部エージェントから制御可能
- **セキュリティ第一**: 接続先・コマンドはプロファイル事前登録制。任意接続禁止

## 2. Horror-1 AIBridge仕様（現状）

### 通信プロトコル
- TCP:9999、改行(`\n`)区切りJSON双方向通信
- バッファサイズ: 65536 bytes
- 状態送信間隔: 100ms
- **単一クライアント制約**: TCP:9999は同時1接続のみ。Oribis接続時はai_player.py等の並行接続不可

### ゲーム状態JSON（Godot→AI）
```json
{
  "player_pos": [x, y],
  "player_hp": 100,
  "stamina": 1.0,
  "monsters": [{"id": 0, "pos": [x,y], "dist": 150.0, "state": "chase", "type": "normal"}],
  "nearby_interactables": ["door", "locker"],
  "room_id": "room_01",
  "game_over": false,
  "cleared": false,
  "dialogue_active": false,
  "current_scene": "res://scenes/ch1.tscn",
  "inventory_items": [],
  "fate_registry_snapshot": {}
}
```

### コマンドJSON（AI→Godot）
```json
{"action": "move", "dir": "right"}
{"action": "sprint", "value": true}
{"action": "interact"}
{"action": "hide"}
{"action": "use_item", "slot": 1}
{"action": "wait"}
{"action": "complete"}
```

### JSON Lines フレーミング仕様
- 最大行長: 65536 bytes（超過時は切り詰め + BridgeEvent::ProtocolError発火）
- 部分行処理: `\n`到達まで内部バッファに蓄積。タイムアウト5秒で部分行破棄
- UTF-8不正バイト: 該当行スキップ + ProtocolError発火
- 空行: 無視（heartbeat代替として許容）

### ログ出力
- Godot stdout: `ai_bridge_command_received: move` 等
- Python logging: `[Ch1Engine] library_girl接近 → interact` 等

## 3. 抽象化設計

### 3.1 BridgeEvent / AppCommand

```rust
/// アプリケーションからの受信イベント（型安全な列挙）
pub enum BridgeEvent {
    /// アプリケーション状態JSON
    State(serde_json::Value),
    /// ログメッセージ
    Log(String),
    /// 接続完了
    Connected,
    /// 切断（理由付き）
    Disconnected { reason: String },
    /// プロトコルエラー（不正JSON等）
    ProtocolError { message: String },
}

/// アプリケーションへの送信コマンド
pub enum AppCommand {
    /// JSON コマンド送信
    Json(serde_json::Value),
    /// 切断要求
    Disconnect,
}
```

### 3.2 BridgeHandle（チャネルベース設計）

```rust
/// Bridge接続ハンドル。&mut self不要でMutex競合を回避。
pub struct BridgeHandle {
    /// コマンド送信チャネル
    pub command_tx: mpsc::Sender<AppCommand>,
    /// イベント受信チャネル
    pub event_rx: mpsc::Receiver<BridgeEvent>,
    /// シャットダウンシグナル
    pub shutdown: CancellationToken,
    /// プロファイルID（監査用）
    pub profile_id: String,
}

impl BridgeHandle {
    /// コマンド送信（ノンブロッキング）
    pub async fn send(&self, cmd: AppCommand) -> Result<(), BridgeError> { ... }

    /// 次のイベント受信（ブロッキング）
    pub async fn recv(&mut self) -> Option<BridgeEvent> { ... }

    /// シャットダウン（graceful）
    pub fn shutdown(&self) { self.shutdown.cancel(); }

    /// 接続中か
    pub fn is_alive(&self) -> bool { !self.shutdown.is_cancelled() }
}
```

### 3.3 BridgeFactory trait

```rust
/// Bridge接続を生成するファクトリ trait
/// 接続生成と操作を分離し、テスト時のモック差し替えを容易にする
#[async_trait]
pub trait BridgeFactory: Send + Sync {
    /// プロファイル設定から BridgeHandle を生成・接続
    async fn connect(&self, profile: &BridgeProfile) -> Result<BridgeHandle, BridgeError>;
}
```

### 3.4 BridgeProfile（事前登録制）

```rust
/// 接続プロファイル（設定ファイルまたはMCPで事前登録）
/// MCP Toolからは profile_id のみ指定。raw host/portの直接指定は禁止。
pub struct BridgeProfile {
    pub id: String,              // "horror1-godot"
    pub name: String,            // "Horror-1 Godot AIBridge"
    pub transport: TransportConfig,
    pub allowed_commands: Option<Vec<String>>,  // コマンドホワイトリスト（None=全許可）
    pub max_sessions: u32,       // このプロファイルの最大同時セッション数
    pub redact_fields: Vec<String>,  // ログ出力時にマスクするJSONフィールド
}

pub enum TransportConfig {
    /// TCP JSON-line プロトコル（Horror-1互換）
    TcpJsonLine {
        host: String,       // "127.0.0.1"
        port: u16,          // 9999
        buffer_size: usize, // 65536
        max_line_length: usize, // 65536
    },
    /// WebSocket JSON プロトコル
    WebSocket {
        url: String,        // "ws://localhost:8080"
    },
    /// stdio JSON プロトコル（子プロセス起動）
    Stdio {
        command: String,    // 実行コマンド
        args: Vec<String>,
        working_dir: Option<String>,
    },
    /// HTTP REST プロトコル
    Http {
        base_url: String,       // "http://localhost:3000"
        state_endpoint: String, // "/api/state"
        command_endpoint: String, // "/api/command"
        poll_interval_ms: u64,  // 100（トランスポート固有ポーリング）
    },
}
```

### 3.5 Bridge実装

| 実装 | トランスポート | 対応アプリ | 優先度 |
|------|--------------|-----------|--------|
| TcpJsonLineBridge | TCP + `\n`区切りJSON | Godot (Horror-1), 汎用TCPサーバー | P0（初回） |
| WebSocketBridge | WebSocket + JSON | Unity, ブラウザ, Node.js | P1 |
| StdioBridge | stdin/stdout + `\n`区切りJSON | CLIツール, スクリプト | P1 |
| HttpBridge | HTTP polling + JSON | REST API, マイクロサービス | P2 |

### 3.6 DebugSession

```rust
pub struct DebugSession {
    id: String,
    profile_id: String,             // 監査・追跡用
    bridge: BridgeHandle,
    config: DebugSessionConfig,
    history: VecDeque<DebugTurn>,   // リングバッファ（最大max_history件）
    status: SessionStatus,
    start_time: Instant,
    owner_token: String,            // MCP認証トークン（操作権限の追跡）
}

pub struct DebugSessionConfig {
    /// AI分析に使用するモデル
    ai_model: String,           // "claude-sonnet-4-6"
    /// AI分析のシステムプロンプト（アプリ固有の指示）
    system_prompt: String,
    /// 最大ターン数（0=無制限）
    max_turns: u32,
    /// タイムアウト（秒）
    timeout_secs: u64,
    /// AI分析間隔（ms） — トランスポートpoll_intervalとは独立
    analysis_interval_ms: u64,  // 100
    /// 自動モード（true=AI自動判断、false=手動コマンド）
    auto_mode: bool,
    /// 履歴保持数（リングバッファサイズ）
    max_history: usize,         // 200
}

pub struct DebugTurn {
    turn_number: u32,
    timestamp: chrono::DateTime<chrono::Utc>,
    state: Option<serde_json::Value>,
    logs: Vec<String>,
    ai_analysis: Option<String>,
    command_sent: Option<serde_json::Value>,
}

/// セッション状態機械
/// Idle → Connecting → Observing → Analyzing → Acting → Observing → ... → Completed/Error
pub enum SessionStatus {
    Idle,
    Connecting,
    /// 状態受信待ち
    Observing,
    /// AI分析中
    Analyzing,
    /// コマンド送信中
    Acting,
    Completed { reason: String },
    Error { message: String },
}
```

### 3.7 AI分析フロー（状態機械ベース）

```
Observing:
  1. bridge.recv() → BridgeEvent::State/Log を収集
  2. analysis_interval到達 → Analyzing へ遷移

Analyzing:
  3. LLM呼出:
     入力: system_prompt + 直近N turnの履歴 + 現在state + 現在logs
     出力スキーマ（必須検証）:
     {
       "analysis": string,     // 分析テキスト
       "command": object|null,  // 送信コマンド（nullなら送信しない）
       "should_stop": boolean   // trueなら終了
     }
  4. LLM出力JSONスキーマ検証 → 不正ならProtocolError + 再試行（最大2回）

Acting:
  5. command != null → bridge.send(AppCommand::Json(command))
  6. 履歴に記録（VecDeque、max_history超過時は先頭pop）
  7. should_stop=true → Completed、false → Observing へ遷移
```

## 4. セキュリティ設計

### 4.1 プロファイル事前登録

MCP Toolからの接続は `profile_id` のみ受け付ける。raw接続パラメータの直接指定は禁止。

```rust
/// プロファイルマネージャー（BrokerState内に保持）
pub struct ProfileManager {
    profiles: RwLock<HashMap<String, BridgeProfile>>,
}
```

プロファイル登録方法:
- 設定ファイル: `~/.config/oribis/bridge_profiles.toml`
- MCP Tool: `debug_profile_register`（管理者トークンのみ）

### 4.2 MCP認証・監査

既存MCP Broker認証基盤を完全に活用:
- **トークン認証**: 全debug_* toolはBroker認証トークン必須（既存のvalidate_token()）
- **監査ログ**: 全操作をmcp_audit_logテーブルに記録（既存のaudit::insert_audit_log()）
- **DENIED_TOOLS**: 必要に応じてdebug_*ツールをDENIED_TOOLSに追加可能
- **レート制限**: debug_send_command に 60 req/min 制限

### 4.3 コマンドホワイトリスト

BridgeProfile.allowed_commands が Some の場合、送信コマンドの `action` フィールドを検証。
ホワイトリスト外のコマンドは拒否（BridgeError::CommandDenied）。

### 4.4 情報秘匿

BridgeProfile.redact_fields で指定されたフィールドは:
- 監査ログ出力時に `"[REDACTED]"` に置換
- debug_get_history のレスポンスでは元値を返す（認証済みクライアントのみ）

## 5. MCP Tool公開

### ツール一覧

| ツール名 | 引数 | 説明 |
|---------|------|------|
| `debug_profile_list` | なし | 登録済みプロファイル一覧 |
| `debug_profile_register` | profile_json | プロファイル登録（管理者のみ） |
| `debug_session_start` | profile_id, session_config | デバッグセッション開始 |
| `debug_session_stop` | session_id | セッション停止 |
| `debug_session_status` | session_id? | セッション状態取得（省略時=全セッション） |
| `debug_send_command` | session_id, command_json | 手動コマンド送信（auto_mode=false時） |
| `debug_get_history` | session_id, last_n? | ターン履歴取得 |
| `debug_get_logs` | session_id, last_n? | ログ取得 |

### レスポンススキーマ

```json
// debug_session_start 成功時
{"session_id": "sess_xxx", "status": "observing", "profile_id": "horror1-godot"}

// debug_session_status
{"session_id": "sess_xxx", "status": "observing", "turn_count": 42, "uptime_secs": 120, "profile_id": "horror1-godot"}

// debug_get_history
{"turns": [{"turn_number": 1, "timestamp": "...", "state": {...}, "logs": [...], "analysis": "...", "command": {...}}]}

// エラー時（全ツール共通）
{"error": "session_not_found", "message": "Session sess_xxx does not exist"}
```

### 使用例: Horror-1 Godotデバッグ

```json
// プロファイル登録（初回のみ）
{"tool": "debug_profile_register", "args": {
  "profile": {
    "id": "horror1-godot",
    "name": "Horror-1 Godot AIBridge",
    "transport": {"type": "tcp_json_line", "host": "127.0.0.1", "port": 9999, "buffer_size": 65536, "max_line_length": 65536},
    "allowed_commands": ["move", "sprint", "crouch", "interact", "hide", "use_item", "wait", "complete"],
    "max_sessions": 1,
    "redact_fields": []
  }
}}

// セッション開始（profile_idのみ指定）
{"tool": "debug_session_start", "args": {
  "profile_id": "horror1-godot",
  "session_config": {
    "ai_model": "claude-sonnet-4-6",
    "system_prompt": "Godot Horror ゲームのAIデバッガー。状態JSONからバグを検出し修正コマンドを送信せよ。",
    "max_turns": 100,
    "timeout_secs": 300,
    "auto_mode": true,
    "max_history": 200
  }
}}

// 手動コマンド（auto_mode=false時）
{"tool": "debug_send_command", "args": {
  "session_id": "sess_123",
  "command_json": {"action": "move", "dir": "right"}
}}
```

## 6. ファイル構成

```
src-tauri/src/
├── appbridge/
│   ├── mod.rs           // BridgeEvent, AppCommand, BridgeHandle, BridgeFactory, BridgeError (247行, 11テスト)
│   ├── profile.rs       // ProfileManager, BridgeProfile, TransportConfig (277行, 13テスト)
│   └── tcp_json_line.rs // TcpJsonLineBridgeFactory（Horror-1互換）(814行, 14テスト)
├── debug_session/
│   ├── mod.rs           // DebugSession, DebugSessionConfig, SessionStatus状態機械 (495行, 15テスト)
│   ├── manager.rs       // SessionManager（RwLock+HashMap, CRUD+上限管理）(439行, 13テスト)
│   └── ai_analyzer.rs   // AiAnalyzer（LLM HTTP呼出・スキーマ検証・再試行）(651行, 20テスト)
├── mcp/
│   └── tools/
│       ├── debug.rs     // MCP Toolハンドラ 8ツール + レート制限 + ホワイトリスト + redact (1187行, 50テスト)
│       └── mod.rs       // ツール登録（debug_tool_definitions追加）
├── lib.rs               // モジュール登録（appbridge, debug_session）
└── tests/
    └── appbridge_integration.rs  // 結合テスト AC-1〜AC-10 MockTCP+MockLLM (891行, 15テスト)

合計: 5001行（テスト含む）, 151テスト
```

**未実装（P1/P2）:**
- `appbridge/websocket.rs` — WebSocketBridge（P1）
- `appbridge/stdio.rs` — StdioBridge（P1）
- `appbridge/http.rs` — HttpBridge（P2）

## 7. Horror-1側の変更

**変更なし。**

- 既存AIBridge（TCP:9999、改行区切りJSON）はそのまま
- OribisのTcpJsonLineBridgeが接続するだけ
- **注意**: TCP:9999は単一クライアント。Oribis接続中はai_player.py（Python）を停止すること

## 8. 実装順序（Codex指摘反映: セキュリティ境界→コア→AI）

| Phase | 内容 | 依存 | 状態 |
|-------|------|------|------|
| P0-1 | BridgeEvent/AppCommand/BridgeHandle/BridgeError型定義 | なし | ✅ 完了 |
| P0-2 | BridgeProfile + ProfileManager + TransportConfig | P0-1 | ✅ 完了 |
| P0-3 | BridgeFactory trait + TcpJsonLineBridge実装 | P0-1, P0-2 | ✅ 完了 |
| P0-4 | MCP Tool: debug_profile_list/register + 認証・監査統合 | P0-2 | ✅ 完了 |
| P0-5 | DebugSession + SessionManager（状態機械・リングバッファ） | P0-3 | ✅ 完了 |
| P0-6 | MCP Tool: debug_session_*/send_command/get_history/get_logs | P0-4, P0-5 | ✅ 完了 |
| P0-7 | AI Analyzer（LLM呼出・出力スキーマ検証） | P0-5 | ✅ 完了 |
| P0-8 | 結合テスト（AC-1〜AC-10, MockTCP+MockLLM） | P0-6, P0-7 | ✅ 完了 |
| P1-1 | WebSocketBridge | P0-1 | 未着手 |
| P1-2 | StdioBridge | P0-1 | 未着手 |
| P2-1 | HttpBridge | P0-1 | 未着手 |

## 9. テスト戦略

**実績: 1339テスト PASS / 5 ignored（全16スイート）**

| カテゴリ | テスト内容 | テスト数 |
|---------|-----------|---------|
| appbridge::mod | BridgeHandle チャネル送受信・シャットダウン・BridgeEvent/AppCommand serde | 11 |
| appbridge::profile | ProfileManager CRUD・重複ID拒否・TransportConfig serde | 13 |
| appbridge::tcp_json_line | JSON Linesパース・部分行timeout・超長行同期回復・不正UTF-8・MockTCP | 14 |
| debug_session::mod | SessionStatus状態機械・遷移検証・リングバッファ・serde roundtrip | 15 |
| debug_session::manager | SessionManager CRUD・上限チェック・active_count・stop | 13 |
| debug_session::ai_analyzer | スキーマ検証・再試行・markdown抽出・mockito HTTP統合テスト | 20 |
| mcp::tools::debug | 8ツールハンドラ・レート制限・ホワイトリスト・redact・認証 | 50 |
| tests::appbridge_integration | 結合テスト AC-1〜AC-10・MockTCP+MockLLM・E2Eシナリオ | 15 |

- **E2Eテスト（Horror-1実機）**: 未実施（Godot headless環境未構築）。MockTCPによるプロトコル互換テストで代替

## 10. 実装サマリ（v3追記）

### P0完了日: 2026-05-19
### ブランチ: `sysdev-1/appbridge-debug`（8コミット）

**モジュール別メトリクス:**

| モジュール | ファイル | 行数 | テスト数 | 主要機能 |
|-----------|---------|------|---------|---------|
| appbridge | mod.rs | 247 | 11 | BridgeEvent(5)/AppCommand(2)/BridgeError(5)/BridgeHandle(channel) |
| appbridge | profile.rs | 277 | 13 | ProfileManager(CRUD)/BridgeProfile/TransportConfig |
| appbridge | tcp_json_line.rs | 814 | 14 | TcpJsonLineBridgeFactory/JSON Lines framing/部分行・超長行処理 |
| debug_session | mod.rs | 495 | 15 | SessionStatus(7状態)/try_transition/DebugSession/DebugTurn/リングバッファ |
| debug_session | manager.rs | 439 | 13 | SessionManager(RwLock)/CRUD/active_count/上限管理 |
| debug_session | ai_analyzer.rs | 651 | 20 | AiAnalyzer/LLM HTTP/スキーマ検証/再試行(max2)/markdown抽出 |
| mcp::tools | debug.rs | 1187 | 50 | 8 MCPツール/レート制限(60/min)/ホワイトリスト/redact |
| tests | appbridge_integration.rs | 891 | 15 | 結合テスト AC-1〜AC-10/MockTCP/MockLLM |
| **合計** | **8ファイル** | **5001** | **151** | |

**既存モジュール（本エピック対象外・連携先）:**

| モジュール | ファイル | 行数 | 概要 |
|-----------|---------|------|------|
| mcp::tools | orchestrator.rs | 1253 | DAGワークフロー実行エンジン7ツール |
| execution_engine | execution_engine.rs | 362 | execute_graph/execute_node/topological_sort |
| mcp | server.rs | 1535 | MCP JSON-RPCサーバー・ディスパッチ |
| mcp | broker.rs | 494 | Unix socket Broker・トークン認証・監査ログ |

**設計上の特記事項:**
- BridgeHandle: mpsc channel設計。command(32) + event(256)バッファ。CancellationTokenでシャットダウン
- AiAnalyzer: system_promptは外部入力（MCP経由）。ハードコードされた秘密ロジックなし。配管（plumbing）コード
- TcpJsonLineBridge: Phase1（無期限待機）+ Phase2（deadline制御）の2段階read。drain_until_newlineで同期回復
- SessionManager: RwLock<HashMap>。terminal状態セッションはactive_countから除外
