# Web Remote

# Feature Spec: Oribis Web Remote UI

**カテゴリ**: oribis
**フィーチャー**: web-remote
**ステータス**: 設計中
**前提**: axum未実装（ゼロから構築）

---

## 概要

Oribis（Tauriデスクトップアプリ）に axum HTTPサーバーを組み込み、ReactフロントエンドをWebブラウザ配信する。Android端末のChromeからOribisの全UIを操作可能にする。

## 目的

- PC上のOribisを、AndroidブラウザからフルUI操作
- Tailscale経由で `http://100.x.x.x:7878` にアクセスするだけ
- Android側のインストール・コード変更ゼロ

---

## アーキテクチャ

```
┌─────────────────────────────────────────────────┐
│ PC (Oribis Tauri App)                           │
│                                                 │
│  ┌──────────────┐     ┌──────────────────────┐  │
│  │ Tauri WebView │     │ axum server :7878    │  │
│  │(デスクトップ版)│     │                      │  │
│  │ invoke() IPC  │     │ GET /  → dist/ 配信  │  │
│  └──────┬────────┘     │ POST /api/invoke/:cmd│  │
│         │              │ WS /ws/chat/:tabId   │  │
│         │              │ WS /ws/pty/:tabId    │  │
│         ▼              └──────────┬───────────┘  │
│  ┌────────────────────────────────┘              │
│  │ Rust Backend (共有)                           │
│  │ - ChatManager (LLMパイプライン)               │
│  │ - Anima (好感度・記憶・表現)                   │
│  │ - CLI Adapters (Claude/Codex/Local)           │
│  │ - Audio (cpal録音 / rodio再生)                │
│  │ - TTS (VOICEVOX/Irodori HTTP)                 │
│  │ - PTY (portable-pty)                          │
│  │ - Plugin System                               │
│  │ - SQLite (rusqlite)                           │
│  └───────────────────────────────────────────────┘
└─────────────────────────────────────────────────┘
         ▲
         │ Tailscale (100.x.x.x:7878)
         │
┌────────┴────────┐
│ Android Chrome  │
│ React SPA       │
│ fetch("/api/…") │
│ Three.js / VRM  │
└─────────────────┘
```

## 動作モード

| モード | 接続方式 | 用途 |
|--------|---------|------|
| Desktop | `invoke()` Tauri IPC | PC画面直接操作 |
| Web Remote | `fetch()` + WebSocket | ブラウザから遠隔操作 |

両モード共存。同時接続可。

---

## 現状のTauri API使用箇所（変更対象）

| ファイル | 使用API | Web化対応 |
|---------|---------|-----------|
| `App.tsx` | invoke, convertFileSrc, listen, emit, getCurrentWindow, openDialog | invoke→fetch, listen→WS, convertFileSrc→HTTP URL |
| `SplashApp.tsx` | invoke, getVersion | invoke→fetch |
| `hooks/useTTS.ts` | invoke, listen | invoke→fetch, listen→WS |
| `hooks/useVoiceInput.ts` | invoke | invoke→fetch |
| `hooks/useAnima.ts` | invoke, listen | invoke→fetch, listen→WS |
| `loaders/avatarLoader.ts` | invoke | invoke→fetch |
| `skill/useSkills.ts` | invoke | invoke→fetch |
| `plugin/PluginManager.ts` | invoke | invoke→fetch |
| `plugin/usePluginLoader.ts` | invoke | invoke→fetch |
| `components/Onboarding.tsx` | invoke, listen, openDialog, path | invoke→fetch, ファイル選択→input[type=file] |
| `components/AnimationAssignPanel.tsx` | openDialog | input[type=file] |
| `components/XtermTerminal.tsx` | invoke | invoke→fetch + WS |

---

## 実装スコープ

### Phase 1: axumサーバー + 静的配信 + APIブリッジ（MVP）

ブラウザでUIが表示され、チャット送受信ができる最小構成。

| ID | 内容 | 詳細 |
|----|------|------|
| WR-01 | axum サーバー組み込み | `setup()` 内で `tauri::async_runtime::spawn` 起動 |
| WR-02 | 静的ファイル配信 | `tower-http::ServeDir` で `dist/` 配信。SPA fallback |
| WR-03 | 設定追加 | config.toml `[remote]` セクション（port/bind/token/enabled） |
| WR-04 | invoke ディスパッチャ | `POST /api/invoke/:cmd` → Tauri command 相当のRust関数呼出 |
| WR-05 | フロント APIアダプター | `src/lib/api-client.ts` — `__TAURI__` 有無で自動切替 |
| WR-06 | import 差替え | 全12ファイルの `invoke` importを api-client 経由に変更 |
| WR-07 | イベント→WebSocket | `listen/emit` を `/ws/events` WebSocket に変換 |
| WR-08 | Bearer認証 | token設定時はAuthorizationヘッダー必須 |
| WR-09 | CORS | Tailscale IPレンジ (100.64.0.0/10) 許可 |
| WR-10 | アセット配信 | VRM/画像を `/assets/*` で HTTP配信（convertFileSrc代替） |

### Phase 2: ストリーミング + ターミナル

| ID | 内容 | 詳細 |
|----|------|------|
| WR-11 | チャットストリーミングWS | `/ws/chat/:tabId` — LLM応答のトークン単位配信 |
| WR-12 | PTY WebSocket中継 | `/ws/pty/:tabId` — xterm.js ↔ portable-pty 双方向 |
| WR-13 | Anima状態push | 好感度変化・表情変化をWSでリアルタイム通知 |
| WR-14 | 音声入力 (Web版) | ブラウザ MediaRecorder → PCに送信 → 既存STT処理 |
| WR-15 | TTS再生 (Web版) | PC側で合成 → WAVをHTTPで返す → ブラウザ Audio再生 |

### Phase 3: モバイルUI最適化

| ID | 内容 | 詳細 |
|----|------|------|
| WR-16 | レスポンシブレイアウト | チャット/アバター/ターミナルのタブ切替 |
| WR-17 | タッチ操作 | 3Dビューのピンチズーム・パンジェスチャー |
| WR-18 | Three.js軽量化 | モバイル検出時: シャドウ無効・30fps制限・テクスチャ縮小 |
| WR-19 | ファイル選択代替 | openDialog → `<input type="file">` + multipart upload |

---

## 技術詳細

### WR-01: axum サーバー組み込み

```rust
// src-tauri/src/remote_api.rs (新規)
use axum::{Router, routing::{get, post}, extract::*};
use tower_http::services::ServeDir;
use tower_http::cors::CorsLayer;

pub async fn start_server(state: AppState, config: RemoteConfig) {
    let app = Router::new()
        .route("/api/health", get(health))
        .route("/api/invoke/{cmd}", post(handle_invoke))
        .nest("/ws", ws_routes())
        .nest("/assets", asset_routes())
        .layer(cors_layer(&config))
        .layer(auth_layer(&config))
        .fallback_service(
            ServeDir::new(&config.dist_path)
                .append_index_html_on_directories(true)
                .fallback(ServeFile::new(format!("{}/index.html", &config.dist_path)))
        )
        .with_state(state);

    let addr = format!("{}:{}", config.bind, config.port);
    let listener = tokio::net::TcpListener::bind(&addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
```

```rust
// src-tauri/src/lib.rs — setup() 内に追加
if app_config.remote.enabled {
    let state = AppState { /* ChatManager等を共有 */ };
    tauri::async_runtime::spawn(remote_api::start_server(state, app_config.remote));
}
```

### WR-05: フロント APIアダプター

```typescript
// src/lib/api-client.ts (新規)
const isTauri = typeof window !== 'undefined' && '__TAURI__' in window;

export async function invoke<T>(cmd: string, args?: Record<string, unknown>): Promise<T> {
  if (isTauri) {
    const { invoke: tauriInvoke } = await import('@tauri-apps/api/core');
    return tauriInvoke(cmd, args);
  }
  const res = await fetch(`/api/invoke/${cmd}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(getToken() ? { 'Authorization': `Bearer ${getToken()}` } : {}),
    },
    body: JSON.stringify(args ?? {}),
  });
  if (!res.ok) throw new Error(`API ${res.status}: ${await res.text()}`);
  return res.json();
}

export function convertFileSrc(path: string): string {
  if (isTauri) {
    return (window as any).__TAURI__.core.convertFileSrc(path);
  }
  return `/assets/${encodeURIComponent(path)}`;
}

// Tauri event → WebSocket 抽象化
export function listen<T>(event: string, handler: (payload: T) => void): () => void {
  if (isTauri) { /* Tauri listen */ }
  // Web: WebSocket接続してイベント振り分け
  const ws = getEventSocket();
  ws.addEventListener('message', (e) => {
    const msg = JSON.parse(e.data);
    if (msg.event === event) handler(msg.payload);
  });
  return () => { /* cleanup */ };
}
```

### WR-04: invoke ディスパッチャ（Rust側）

```rust
// 全Tauri commandを列挙してディスパッチ
async fn handle_invoke(
    Path(cmd): Path<String>,
    State(state): State<AppState>,
    Json(args): Json<serde_json::Value>,
) -> Result<Json<serde_json::Value>, AppError> {
    match cmd.as_str() {
        "get_config" => Ok(Json(serde_json::to_value(state.get_config())?)),
        "send_chat" => {
            let req: SendChatRequest = serde_json::from_value(args)?;
            let result = state.chat_manager.send(req).await?;
            Ok(Json(serde_json::to_value(result)?))
        },
        "get_anima_state" => /* ... */,
        "start_recording" => /* ... */,
        "stop_recording" => /* ... */,
        "speak_tts" => /* ... */,
        "pty_write" => /* ... */,
        "pty_resize" => /* ... */,
        // ... 全command列挙
        _ => Err(AppError::NotFound(format!("unknown command: {cmd}"))),
    }
}
```

---

## 設定

```toml
# ~/.config/oribis/config.toml
[remote]
enabled = false          # デフォルト無効
port = 7878
bind = "0.0.0.0"         # Tailscale用。127.0.0.1ならローカルのみ
token = ""               # 空=認証なし（Tailscale内なら許容）
dist_path = ""           # 空=バイナリ隣接 ./dist/ を自動検出
```

---

## セキュリティ

| 対策 | 内容 |
|------|------|
| ネットワーク | Tailscale（WireGuard暗号化+デバイス認証） |
| 認証 | Bearer token（オプション）。Tailscale内なら省略可 |
| CORS | Tailscale IPレンジのみ許可 |
| Rate limit | 60 req/min/client |
| bind保護 | `bind != "127.0.0.1" && token.is_empty()` → 起動拒否+ERRORログ |
| WebSocket認証 | クエリパラメータ or 初回メッセージでtoken検証 |

---

## 追加クレート (Cargo.toml)

```toml
# [dependencies] に追加
axum = { version = "0.8", features = ["ws"] }
tower-http = { version = "0.6", features = ["fs", "cors"] }
tower = "0.5"
subtle = "2"             # 定数時間Bearer比較
dashmap = "6"            # WebSocket接続管理
```

既存依存で流用可能: `tokio` (full), `serde_json`, `uuid`, `base64`

---

## 対象ファイル

| 区分 | ファイル | 内容 |
|------|---------|------|
| 新規 | `src-tauri/src/remote_api.rs` | axumサーバー・ルーティング・ハンドラ全体 |
| 新規 | `src/lib/api-client.ts` | invoke/listen/convertFileSrc 抽象化 |
| 変更 | `src-tauri/src/lib.rs` | setup() にサーバー起動追加 |
| 変更 | `src-tauri/src/config.rs` | RemoteConfig 構造体追加 |
| 変更 | `src-tauri/Cargo.toml` | axum, tower-http等追加 |
| 変更 | `src/App.tsx` | import先変更 (api-client) |
| 変更 | `src/hooks/useTTS.ts` | 同上 |
| 変更 | `src/hooks/useVoiceInput.ts` | 同上 |
| 変更 | `src/hooks/useAnima.ts` | 同上 |
| 変更 | `src/loaders/avatarLoader.ts` | 同上 |
| 変更 | `src/skill/useSkills.ts` | 同上 |
| 変更 | `src/plugin/PluginManager.ts` | 同上 |
| 変更 | `src/plugin/usePluginLoader.ts` | 同上 |
| 変更 | `src/components/Onboarding.tsx` | 同上 + ファイル選択代替 |
| 変更 | `src/components/XtermTerminal.tsx` | WS接続に変更 |
| 変更 | `src/SplashApp.tsx` | 同上 |
| 新規 | `scripts/build-web.sh` | pnpm build + dist配置 |

---

## 実装優先度

| 順位 | Phase | 到達状態 | 見積 |
|------|-------|---------|------|
| 1 | Phase 1 (WR-01〜10) | ブラウザでUI表示+チャット送受信 | 5-7日 |
| 2 | Phase 2 (WR-11〜15) | ストリーミング応答+ターミナル+音声 | 5-7日 |
| 3 | Phase 3 (WR-16〜19) | モバイルタッチ操作+パフォーマンス最適化 | 1週間 |

---

## 制約・注意事項

- デスクトップ版（Tauri WebView）は一切壊さない。api-client.ts の `isTauri` 分岐で完全互換
- `openDialog`（ファイル選択）はWeb版では `<input type="file">` に差し替え
- `getCurrentWindow`（タイトルバー操作）はWeb版では非表示/不要
- VRMモデルのHTTP配信はファイルサイズ大（10-50MB）。初回ロード時間に注意
- Tailscale未接続時はLAN内 `192.168.x.x:7878` でもアクセス可

---

## Implementation Notes

（実装開始後に記録）

## Known Issues / Backlog

（実装開始後に記録）
