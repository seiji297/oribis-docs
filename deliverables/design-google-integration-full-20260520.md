# Oribis 外部連携 総合設計書（Google + Blender）

**作成日**: 2026-05-20
**ステータス**: DRAFT → Codex Review待ち
**ブランチ**: sysdev-1/google-integration

---

## 1. 概要

Oribisの外部連携機能の全体設計。Google連携（Phase 1-2）+ Blender連携（Phase 3）を包括する。

**スコープ外**: Google Fit, Google Maps, Google Contacts

---

## 2. アーキテクチャ全体図

```
┌─────────────────────────────────────┐
│  Frontend (React/TypeScript)         │
│  ┌──────────┐ ┌──────────────────┐  │
│  │DrawerAnima│ │  App.tsx         │  │
│  │Settings   │ │  gcal-upcoming   │  │
│  │Tab        │ │  event listener  │  │
│  └─────┬────┘ └────────┬─────────┘  │
│        │  invoke()      │ listen()   │
├────────┼───────────────┼────────────┤
│  Tauri Backend (Rust)   │            │
│  ┌─────┴────────────────┴─────────┐ │
│  │  google/commands.rs (Tauri Cmd) │ │
│  │  8 commands (auth/cal/tasks)    │ │
│  └─────────┬──────────────────────┘ │
│            │                         │
│  ┌─────────┴──────────────────────┐ │
│  │  google/client.rs (GoogleClient)│ │
│  │  Bearer auth + 401 auto-retry   │ │
│  │  get / post / patch / delete*   │ │
│  └─────────┬──────────────────────┘ │
│            │                         │
│  ┌─────────┴───────┐ ┌───────────┐ │
│  │google/calendar.rs│ │google/    │ │
│  │google/tasks.rs   │ │gmail.rs*  │ │
│  │google/youtube.rs*│ │drive.rs*  │ │
│  └─────────────────┘ └───────────┘ │
│                                      │
│  ┌──────────────────────────────┐   │
│  │  google/token_store.rs        │   │
│  │  SQLite google.db             │   │
│  │  google_tokens table          │   │
│  │  google_identity table*       │   │
│  └──────────────────────────────┘   │
│                                      │
│  ┌──────────────────────────────┐   │
│  │  google/oauth.rs              │   │
│  │  PKCE + openid scope*         │   │
│  │  id_token JWT verification*   │   │
│  └──────────────────────────────┘   │
│                                      │
│  ┌──────────────────────────────┐   │
│  │  google/scheduler.rs          │   │
│  │  5min interval polling        │   │
│  │  + morning schedule readout*  │   │
│  └──────────────────────────────┘   │
│                                      │
│  ┌──────────────────────────────┐   │
│  │  mcp/tools/google.rs          │   │
│  │  MCP tool definitions         │   │
│  └──────────────────────────────┘   │
└──────────────────────────────────────┘

* = Phase 2 新規/拡張
```

---

## 3. Phase 1: 既存実装（完了済み）

### 3.1 OAuth2 認証 (`google/oauth.rs`)

- **方式**: Authorization Code + PKCE (S256)
- **スコープ**: `calendar` + `tasks`
- **コールバック**: ローカルTCPサーバー（OS割当ポート）で受信
- **state検証**: ランダムnonce比較（CSRF防止）
- **トークン交換**: `oauth2.googleapis.com/token`
- **リフレッシュ**: `refresh_access_token()` — 期限切れ時に自動更新
- **revoke**: `oauth2.googleapis.com/revoke`
- **メール取得**: userinfo v2エンドポイント（ベストエフォート）
- **クレデンシャル**: `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` はコンパイル時env var（`option_env!`）

### 3.2 トークン永続化 (`google/token_store.rs`)

- **DB**: `google.db` (SQLite, `ORIBIS_DATA_DIR/oribis/` or `dirs::data_dir()/oribis/`)
- **テーブル**: `google_tokens`

| カラム | 型 | 説明 |
|--------|-----|------|
| id | INTEGER PK | 固定値1（単一ユーザー） |
| access_token | TEXT NOT NULL | アクセストークン |
| refresh_token | TEXT | リフレッシュトークン |
| expires_at | INTEGER NOT NULL | Unix秒 |
| scopes | TEXT NOT NULL | 認可スコープ |
| email | TEXT | Googleメールアドレス |
| created_at | TEXT | 初回認証日時 |
| updated_at | TEXT | 最終更新日時 |

- **UPSERT**: id=1固定、ON CONFLICT DO UPDATE
- **認証判定**: `is_authenticated()` — 期限内 or refresh_token存在
- **トークン自動更新**: `get_valid_access_token()` — 60秒バッファで期限チェック

### 3.3 HTTPクライアント (`google/client.rs`)

- `GoogleClient` — `reqwest::Client` + `TokenStore`
- `get()` / `post()` / `patch()` — Bearer auth付与、401時に1回リトライ
- トークン取得失敗 → エラー伝播

### 3.4 Calendar API (`google/calendar.rs`)

- **CalendarEvent**: id, summary, start/end (EventDateTime), status, htmlLink
- **EventDateTime**: dateTime (RFC3339) or date (終日), timeZone
- `list_events(date)` — 指定日イベント一覧（maxResults=50, singleEvents=true）
- `list_events_range(time_min, time_max)` — 時間範囲指定
- `create_event(summary, start, end)` — イベント作成

### 3.5 Tasks API (`google/tasks.rs`)

- **GoogleTask**: id, title, notes, status, due, completed
- `list_tasks()` — @default リスト、未完了のみ
- `complete_task(task_id)` — PATCH status=completed
- `create_task(title, notes?, due?)` — タスク作成

### 3.6 スケジューラー (`google/scheduler.rs`)

- **ポーリング間隔**: 5分 (`tokio::time::interval(300s)`)
- **検出範囲**: 現在〜30分後のイベント
- **重複防止**: `HashSet<String>` — event_id管理、日付変更でクリア
- **通知**: `app_handle.emit("gcal-upcoming-event", payload)` → フロントエンド
- **未認証時**: サイレントスキップ

### 3.7 Tauriコマンド (`google/commands.rs`)

| コマンド | 引数 | 戻り値 |
|---------|------|--------|
| `gcal_auth_start` | AppHandle | String (email) |
| `gcal_auth_status` | — | `{ authenticated, email }` |
| `gcal_auth_revoke` | — | () |
| `gcal_list_events` | date? | Vec\<CalendarEvent\> |
| `gcal_create_event` | summary, start, end | CalendarEvent |
| `gtasks_list` | — | Vec\<GoogleTask\> |
| `gtasks_complete` | task_id | GoogleTask |
| `gtasks_create` | title, notes?, due? | GoogleTask |

### 3.8 MCPツール (`mcp/tools/google.rs`)

| ツール名 | 説明 |
|---------|------|
| `google_calendar_list` | 日付指定でカレンダー一覧 |
| `google_calendar_create` | イベント作成 |
| `google_tasks_list` | 未完了タスク一覧 |
| `google_tasks_complete` | タスク完了 |

- 未認証時: `{ success: false, error: "not_authenticated" }`

### 3.9 フロントエンドUI (`DrawerAnima.tsx`)

- Settings タブ内「Google Account」セクション
- 状態: `gcal_auth_status` をマウント時に取得
- 連携ボタン → `gcal_auth_start` → ブラウザ起動 → コールバック → 状態更新
- 解除ボタン → confirm → `gcal_auth_revoke`
- 表示: Connected: {email} / 未連携時: 連携ボタン

### 3.10 通知→Anima発話 (`App.tsx`)

- `gcal-upcoming-event` リスナー
- `{summary}が{minutes_until}分後に始まるよ` → `control-avatar` イベント発火
- AvatarViewer/useAnima が speech として処理

---

## 4. Phase 2: 新規追加

### 4.1 id_token JWT アンチフォージェリ（連携日記録）

**目的**: Googleアカウント連携日（first_linked_at）を偽造不可能な形で記録。

**方式**: OAuth2認証時にGoogleが署名した `id_token` (JWT) の `iat` (issued at) を保存。

#### 4.1.1 OAuth スコープ変更

```
// 現在
"https://www.googleapis.com/auth/calendar https://www.googleapis.com/auth/tasks"

// 変更後
"openid https://www.googleapis.com/auth/calendar https://www.googleapis.com/auth/tasks https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/drive.readonly https://www.googleapis.com/auth/youtube.readonly"
```

`openid` スコープ追加 → token endpointが `id_token` (JWT) を返す。

#### 4.1.2 DB スキーマ追加

`google_identity` テーブル（新規）:

| カラム | 型 | 説明 |
|--------|-----|------|
| id | INTEGER PK | 固定値1 |
| google_sub | TEXT NOT NULL | Google ユーザーID（JWT sub claim） |
| initial_id_token | TEXT NOT NULL | 初回認証時のid_token原文（改変不可） |
| first_linked_at | INTEGER NOT NULL | JWT iat claim（Unix秒） |
| jwks_cache | TEXT | Google JWKS公開鍵キャッシュ（JSON） |
| jwks_cached_at | INTEGER | キャッシュ取得日時（Unix秒） |
| created_at | TEXT | レコード作成日時 |

#### 4.1.3 JWT検証フロー

```
1. exchange_code() → TokenResponse に id_token フィールド追加
2. id_tokenをBase64デコード → header.kid 取得
3. Google JWKS エンドポイント (googleapis.com/oauth2/v3/certs) から公開鍵取得
4. RS256署名検証 (jsonwebtoken crate)
5. iss = "accounts.google.com" 検証
6. aud = CLIENT_ID 検証
7. exp: オフライン検証時は無視（初回保存時のみ有効期限内であればOK）
8. iat → first_linked_at として保存
9. sub → google_sub として保存
10. initial_id_token → 原文保存（2回目以降の認証では上書き禁止）
```

#### 4.1.4 Codex Adviser 指摘への対応

| 必須条件 | 対応 |
|---------|------|
| JWKS鍵永続化（オフライン検証） | `jwks_cache` + `jwks_cached_at` カラム、24時間TTL |
| initial_id_token不変性 | INSERT時のみ、google_identity.id=1が既存なら上書き禁止 |
| exp無効化（オフライン検証） | `jsonwebtoken::Validation` で `validate_exp = false` |
| id_token不在フォールバック | openidスコープ欠如時は従来通りemail取得のみ、identity未作成 |

#### 4.1.5 Cargo依存追加

```toml
jsonwebtoken = "9"
```

#### 4.1.6 新規ファイル

- `google/identity.rs` — JWT検証、JWKS取得/キャッシュ、google_identity CRUD

#### 4.1.7 Tauriコマンド追加

| コマンド | 戻り値 |
|---------|--------|
| `gcal_identity_info` | `{ google_sub, first_linked_at, email }` or null |

### 4.2 Calendar 拡張（編集・削除）

#### 4.2.1 新規API関数 (`google/calendar.rs`)

```rust
/// イベントを更新（PATCH）。部分更新対応。
pub async fn update_event(
    client: &GoogleClient,
    event_id: &str,
    summary: Option<&str>,
    start: Option<&str>,
    end: Option<&str>,
) -> Result<CalendarEvent, String>

/// イベントを削除（DELETE）。
pub async fn delete_event(
    client: &GoogleClient,
    event_id: &str,
) -> Result<(), String>
```

#### 4.2.2 GoogleClient拡張

```rust
/// DELETE リクエスト。
pub async fn delete(&self, url: &str) -> Result<(), String>
```

#### 4.2.3 Tauriコマンド追加

| コマンド | 引数 | 戻り値 |
|---------|------|--------|
| `gcal_update_event` | event_id, summary?, start?, end? | CalendarEvent |
| `gcal_delete_event` | event_id | () |

#### 4.2.4 MCPツール追加

| ツール名 | 説明 |
|---------|------|
| `google_calendar_update` | イベント更新 |
| `google_calendar_delete` | イベント削除 |

### 4.3 朝のスケジュール自動読み上げ

#### 4.3.1 概要

起動時（または設定時刻）に当日のカレンダーイベント一覧をAnimaが読み上げる。

#### 4.3.2 実装方針

`google/scheduler.rs` に追加:

```rust
/// 起動時に当日スケジュールを読み上げる。
/// 1日1回のみ実行（last_morning_date で管理）。
pub async fn morning_schedule_readout(app_handle: &tauri::AppHandle) {
    // 1. last_morning_date チェック（今日済みならスキップ）
    // 2. list_events(today) で当日イベント取得
    // 3. イベント要約テキスト生成
    // 4. app_handle.emit("gcal-morning-schedule", payload) → Anima発話
}
```

#### 4.3.3 フロントエンド

- `App.tsx` に `gcal-morning-schedule` リスナー追加
- `control-avatar` イベントで読み上げ発火
- テキスト例: 「おはようございます。今日の予定は3件です。10時から朝会、14時からレビュー、16時からMTG。」

#### 4.3.4 設定

- `localStorage("oribis_gcal_morning_enabled")` — true/false
- DrawerAnima Settings に「朝のスケジュール読み上げ」トグル追加

### 4.4 Gmail連携

#### 4.4.1 スコープ

`https://www.googleapis.com/auth/gmail.readonly` — 読み取り専用

#### 4.4.2 新規ファイル

`google/gmail.rs`:

```rust
/// Gmail メッセージ（簡略）
pub struct GmailMessage {
    pub id: String,
    pub thread_id: String,
    pub from: String,
    pub subject: String,
    pub snippet: String,
    pub date: String,         // RFC2822
    pub is_unread: bool,
}

/// 未読メッセージ一覧（最新N件）
pub async fn list_unread(client: &GoogleClient, max_results: u32) -> Result<Vec<GmailMessage>, String>

/// メッセージ詳細取得
pub async fn get_message(client: &GoogleClient, message_id: &str) -> Result<GmailMessage, String>

/// 未読件数取得
pub async fn unread_count(client: &GoogleClient) -> Result<u32, String>
```

**API**: `GET gmail/v1/users/me/messages?q=is:unread&maxResults=N`
メッセージ詳細: `GET gmail/v1/users/me/messages/{id}?format=metadata&metadataHeaders=From,Subject,Date`

#### 4.4.3 Tauriコマンド

| コマンド | 引数 | 戻り値 |
|---------|------|--------|
| `gmail_unread_list` | max_results? (default 10) | Vec\<GmailMessage\> |
| `gmail_unread_count` | — | u32 |
| `gmail_get_message` | message_id | GmailMessage |

#### 4.4.4 MCPツール

| ツール名 | 説明 |
|---------|------|
| `google_gmail_unread` | 未読メール一覧 |
| `google_gmail_count` | 未読件数 |

#### 4.4.5 スケジューラー通知

`scheduler.rs` に追加:
- 5分間隔で未読件数チェック
- 前回チェック時から増加 → `gmail-new-mail` イベント emit
- フロントエンド: Anima発話「新しいメールが{N}件届いてるよ」

#### 4.4.6 セキュリティ

- **readonly**: メール送信・削除・変更は不可
- **メール本文は取得しない**: metadataのみ（From, Subject, Date, snippet）
- **snippet**: Googleが自動生成する先頭100文字程度のプレビュー

### 4.5 Google Drive連携

#### 4.5.1 スコープ

`https://www.googleapis.com/auth/drive.readonly` — 読み取り専用

#### 4.5.2 新規ファイル

`google/drive.rs`:

```rust
/// Drive ファイル情報
pub struct DriveFile {
    pub id: String,
    pub name: String,
    pub mime_type: String,
    pub modified_time: String,   // RFC3339
    pub web_view_link: Option<String>,
    pub size: Option<u64>,       // bytes
}

/// 最近変更されたファイル一覧
pub async fn list_recent(client: &GoogleClient, max_results: u32) -> Result<Vec<DriveFile>, String>

/// ファイル検索
pub async fn search_files(client: &GoogleClient, query: &str, max_results: u32) -> Result<Vec<DriveFile>, String>

/// ファイルメタデータ取得
pub async fn get_file(client: &GoogleClient, file_id: &str) -> Result<DriveFile, String>
```

**API**:
- `GET drive/v3/files?orderBy=modifiedTime desc&pageSize=N&fields=files(id,name,mimeType,modifiedTime,webViewLink,size)`
- 検索: `q=name contains '{query}'`

#### 4.5.3 Tauriコマンド

| コマンド | 引数 | 戻り値 |
|---------|------|--------|
| `gdrive_list_recent` | max_results? (default 10) | Vec\<DriveFile\> |
| `gdrive_search` | query, max_results? | Vec\<DriveFile\> |

#### 4.5.4 MCPツール

| ツール名 | 説明 |
|---------|------|
| `google_drive_recent` | 最近のファイル一覧 |
| `google_drive_search` | ファイル検索 |

#### 4.5.5 セキュリティ

- **readonly**: ファイルアップロード・削除・変更は不可
- **ファイル内容ダウンロード**: Phase 2では実装しない（メタデータのみ）

### 4.6 YouTube連携

#### 4.6.1 スコープ

`https://www.googleapis.com/auth/youtube.readonly` — 読み取り専用

#### 4.6.2 新規ファイル

`google/youtube.rs`:

```rust
/// YouTube チャンネル情報
pub struct YouTubeChannel {
    pub id: String,
    pub title: String,
    pub subscriber_count: u64,
    pub video_count: u64,
    pub view_count: u64,
}

/// YouTube 動画情報
pub struct YouTubeVideo {
    pub id: String,
    pub title: String,
    pub published_at: String,
    pub view_count: u64,
    pub like_count: u64,
    pub comment_count: u64,
    pub duration: String,        // ISO 8601 duration
}

/// 自分のチャンネル情報取得
pub async fn my_channel(client: &GoogleClient) -> Result<YouTubeChannel, String>

/// 自分の動画一覧（最新N件）
pub async fn my_videos(client: &GoogleClient, max_results: u32) -> Result<Vec<YouTubeVideo>, String>

/// 動画の統計情報取得
pub async fn video_stats(client: &GoogleClient, video_id: &str) -> Result<YouTubeVideo, String>
```

**API**:
- `GET youtube/v3/channels?part=statistics,snippet&mine=true`
- `GET youtube/v3/search?part=snippet&forMine=true&type=video&order=date&maxResults=N`
- `GET youtube/v3/videos?part=statistics,contentDetails,snippet&id={id}`

#### 4.6.3 Tauriコマンド

| コマンド | 引数 | 戻り値 |
|---------|------|--------|
| `youtube_my_channel` | — | YouTubeChannel |
| `youtube_my_videos` | max_results? (default 10) | Vec\<YouTubeVideo\> |
| `youtube_video_stats` | video_id | YouTubeVideo |

#### 4.6.4 MCPツール

| ツール名 | 説明 |
|---------|------|
| `google_youtube_channel` | 自分のチャンネル情報 |
| `google_youtube_videos` | 自分の動画一覧 |

### 4.7 Google Keep連携

#### 4.7.1 制約

Google Keep APIは2025年時点でパブリックAPI未公開。
**方式**: Google Tasks APIで代替（既存実装）。

Keep固有のラベル・色分け機能は取得不可のため、Phase 2ではスコープ外。
将来Keep API公開時に再検討。

→ **結論: 実装対象外。Tasks APIで代替済み。**

### 4.8 Google Photos連携

#### 4.8.1 スコープ

`https://www.googleapis.com/auth/photoslibrary.readonly` — 読み取り専用

#### 4.8.2 新規ファイル

`google/photos.rs`:

```rust
/// 写真メタデータ
pub struct GooglePhoto {
    pub id: String,
    pub filename: String,
    pub mime_type: String,
    pub creation_time: String,    // RFC3339
    pub width: u64,
    pub height: u64,
    pub base_url: String,         // 画像URL（1時間有効）
}

/// 最近の写真一覧
pub async fn list_recent(client: &GoogleClient, max_results: u32) -> Result<Vec<GooglePhoto>, String>

/// 日付範囲で写真検索
pub async fn search_by_date(client: &GoogleClient, start_date: &str, end_date: &str) -> Result<Vec<GooglePhoto>, String>
```

**API**:
- `POST photoslibrary/v1/mediaItems:search` (body: `{ pageSize, filters: { dateFilter } }`)
- `GET photoslibrary/v1/mediaItems?pageSize=N`

#### 4.8.3 Tauriコマンド

| コマンド | 引数 | 戻り値 |
|---------|------|--------|
| `gphotos_list_recent` | max_results? (default 20) | Vec\<GooglePhoto\> |
| `gphotos_search_date` | start_date, end_date | Vec\<GooglePhoto\> |

#### 4.8.4 MCPツール

| ツール名 | 説明 |
|---------|------|
| `google_photos_recent` | 最近の写真 |
| `google_photos_search` | 日付範囲検索 |

#### 4.8.5 セキュリティ

- **readonly**: アップロード・削除不可
- **base_url**: 1時間で期限切れ。キャッシュ不可

---

## 5. OAuthスコープ統合

### 5.1 全スコープ一覧

```
openid
https://www.googleapis.com/auth/calendar
https://www.googleapis.com/auth/tasks
https://www.googleapis.com/auth/gmail.readonly
https://www.googleapis.com/auth/drive.readonly
https://www.googleapis.com/auth/youtube.readonly
https://www.googleapis.com/auth/photoslibrary.readonly
```

### 5.2 スコープ変更時の再認証

- 既存認証済みユーザーがスコープ拡張を必要とする場合
- `prompt=consent` で再認証を要求（既存動作: 常にconsent）
- refresh_token は新しいスコープで再取得
- `google_tokens.scopes` カラムで保存スコープを管理

### 5.3 Google Cloud Console設定

- OAuth同意画面に全スコープを登録
- アプリ審査: `gmail.readonly`, `drive.readonly`, `photoslibrary.readonly` は制限スコープ → OAuth検証必要
- 開発中は「テスト」モードで動作（テストユーザー登録必要）

---

## 6. ファイル構成（Phase 2完了後）

```
src-tauri/src/google/
├── mod.rs              // モジュール宣言
├── oauth.rs            // OAuth2 PKCE + openid
├── token_store.rs      // SQLite トークン永続化
├── identity.rs         // [NEW] JWT検証・identity管理
├── client.rs           // HTTP クライアント + delete()
├── calendar.rs         // Calendar API (CRUD)
├── tasks.rs            // Tasks API
├── gmail.rs            // [NEW] Gmail readonly
├── drive.rs            // [NEW] Drive readonly
├── youtube.rs          // [NEW] YouTube readonly
├── photos.rs           // [NEW] Photos readonly
├── scheduler.rs        // スケジューラー + morning readout
└── commands.rs         // Tauri コマンド（全API）

src-tauri/src/mcp/tools/
└── google.rs           // MCP ツール定義（拡張）
```

---

## 7. DBスキーマ（Phase 2完了後）

### google.db

```sql
-- 既存
CREATE TABLE google_tokens (
    id INTEGER PRIMARY KEY DEFAULT 1,
    access_token TEXT NOT NULL,
    refresh_token TEXT,
    expires_at INTEGER NOT NULL,
    scopes TEXT NOT NULL,
    email TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Phase 2追加
CREATE TABLE google_identity (
    id INTEGER PRIMARY KEY DEFAULT 1,
    google_sub TEXT NOT NULL,
    initial_id_token TEXT NOT NULL,
    first_linked_at INTEGER NOT NULL,
    jwks_cache TEXT,
    jwks_cached_at INTEGER,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

---

## 8. Cargo依存追加（Phase 2）

```toml
jsonwebtoken = "9"    # JWT検証（id_token）
```

既存依存で対応可能:
- `reqwest` — HTTP
- `serde` / `serde_json` — シリアライズ
- `chrono` — 日時
- `rusqlite` — SQLite
- `base64` — Base64デコード

---

## 9. 実装順序（Phase 2）

```
1. oauth.rs スコープ拡張（openid + 4スコープ追加）
2. identity.rs — JWT検証 + google_identity テーブル
3. client.rs — delete() メソッド追加
4. calendar.rs — update_event / delete_event
5. gmail.rs — 未読一覧/件数
6. drive.rs — 最近のファイル/検索
7. youtube.rs — チャンネル/動画情報
8. photos.rs — 最近の写真/日付検索
9. scheduler.rs — morning readout + gmail通知
10. commands.rs — 全Tauriコマンド追加
11. mcp/tools/google.rs — 全MCPツール追加
12. フロントエンドUI拡張（各機能の表示/操作）
```

---

## 10. テスト方針

- 各APIモジュール: デシリアライズ単体テスト（既存パターン準拠）
- identity.rs: JWTデコード/検証のモックテスト
- client.rs: delete()のパターンテスト
- commands.rs: `#[cfg(feature = "tauri-backend")]` ゲートのためcargo test対象外（コンパイル確認のみ）
- MCP tools: ツール定義・必須フィールド・未認証レスポンスのテスト
- `cargo test` 全PASS + `pnpm typecheck` 0 errors

---

## 11. セキュリティ考慮事項

- **全スコープreadonly**: 書き込み権限はCalendar/Tasksのみ（既存）
- **トークン保存**: ローカルSQLite（暗号化なし → 将来的にOS Keychain移行を検討）
- **PKCE**: Man-in-the-middle対策
- **state nonce**: CSRF対策
- **JWT id_token**: Google署名による改ざん不可。偽造不可能な連携日証明
- **JWKS鍵キャッシュ**: 24時間TTL。オフライン検証可能
- **Client ID/Secret**: コンパイル時環境変数（バイナリに埋込）
- **Gmail**: メタデータのみ（本文取得なし）
- **Drive**: メタデータのみ（ファイルダウンロードなし）
- **Photos**: base_url 1時間期限、キャッシュ不可

---

## 12. Phase 3: 外部ツール連携

### 12.1 Blender連携（公式MCPサーバー前提）

#### 12.1.1 概要

Blender公式MCPサーバー（blender.org/lab/mcp-server）を活用し、OribisからBlenderの3Dアセットパイプラインを制御。
自前Flask addonは不要。公式MCPサーバーが提供するツール（execute_blender_code等）経由でbpy API操作。

**参考**: [Blender公式MCPサーバー](https://www.blender.org/lab/mcp-server/) / [ahujasid/blender-mcp](https://github.com/ahujasid/blender-mcp)

#### 12.1.2 アーキテクチャ

```
Oribis (Tauri)                     Blender MCP Server        Blender
┌──────────────┐                   ┌──────────────┐         ┌────────────┐
│ MCP Broker   │ ← stdio/TCP →    │ MCP Server   │ ← TCP → │ MCP Addon  │
│ (既存)       │   JSON-RPC       │ (blender-mcp)│  :9876   │ (bpy API)  │
├──────────────┤                   └──────────────┘         ├────────────┤
│ Tauri Cmd    │                                            │ シーン操作  │
│ blender_*    │                                            │ アニメーション│
├──────────────┤                                            │ VRMエクスポート│
│ Plugin V2    │                                            │ シェイプキー │
│ blender-hub  │                                            └────────────┘
└──────────────┘
```

**通信方式**: MCP標準プロトコル（JSON-RPC over stdio/TCP）
- Blender側: 公式MCPアドオン（Blender内TCPソケットサーバー :9876）
- MCP Server: `blender-mcp`（PyPI: `uvx blender-mcp`）— MCP↔Blenderブリッジ
- Oribis側: 既存MCP Brokerから外部MCPサーバーとして接続

**起動方式**:
- Blender起動 + MCPアドオン有効化（Edit > Preferences > Add-ons）
- MCP Server: Oribis起動時にspawn（`uvx blender-mcp`）またはユーザー手動起動

#### 12.1.3 Blender MCPサーバーの提供ツール

公式/ahujasid版MCPサーバーが提供するツール:

| ツール名 | 説明 |
|---------|------|
| `get_scene_info` | シーン情報取得（オブジェクト・マテリアル・メッシュ統計） |
| `execute_blender_code` | 任意のPythonコード実行（bpy API直接操作） |
| `get_viewport_screenshot` | ビューポートスクリーンショット取得 |
| `list_animations` | アクション一覧 |
| `get_polyhaven_*` | Poly Havenアセット取得（HDRI・テクスチャ・モデル） |

**`execute_blender_code`が中核**: Oribis側は必要なbpyスクリプトをこのツール経由で実行:
- アニメーションベイク → FBXエクスポート
- VRMエクスポート（VRMアドオン経由）
- シェイプキー操作
- レンダリング・サムネイル生成

#### 12.1.4 Oribis側 統合設計

既存MCP Brokerに外部MCPサーバー接続機能を追加:

```rust
// blender/client.rs — BlenderMCPProxy
pub struct BlenderMcpProxy {
    /// MCP Broker経由でBlender MCPサーバーのツールを呼ぶ
    broker: Arc<BrokerState>,
}

impl BlenderMcpProxy {
    /// Blender MCPサーバー稼働確認（get_scene_info呼び出し）
    pub async fn is_alive(&self) -> bool

    /// シーン情報取得
    pub async fn get_scene_info(&self) -> Result<BlenderSceneInfo, String>

    /// bpyコード実行（execute_blender_code経由）
    pub async fn execute_code(&self, code: &str) -> Result<serde_json::Value, String>

    /// ビューポートスクリーンショット
    pub async fn get_screenshot(&self) -> Result<Vec<u8>, String>

    // --- 高レベルラッパー（内部でexecute_codeにbpyスクリプトを渡す） ---

    /// アニメーション一覧
    pub async fn list_animations(&self) -> Result<Vec<BlenderAnimation>, String>

    /// アニメーションベイク→FBXエクスポート
    pub async fn bake_animation(&self, action_name: &str, output_path: &str) -> Result<String, String>

    /// VRMエクスポート
    pub async fn export_vrm(&self, output_path: &str) -> Result<String, String>

    /// シェイプキー一覧
    pub async fn list_shapekeys(&self) -> Result<Vec<ShapeKey>, String>

    /// シェイプキー値設定
    pub async fn set_shapekey(&self, name: &str, value: f32) -> Result<(), String>

    /// サムネイル生成
    pub async fn render_thumbnail(&self, width: u32, height: u32) -> Result<Vec<u8>, String>
}
```

**bpyスクリプトテンプレート**: `src-tauri/src/blender/scripts/` にPythonスクリプト埋込
- `bake_animation.py` — アクションベイク + FBXエクスポート
- `export_vrm.py` — VRM Addon呼び出し
- `list_shapekeys.py` — シェイプキー列挙
- `set_shapekey.py` — シェイプキー値設定

#### 12.1.5 Tauriコマンド

| コマンド | 引数 | 戻り値 |
|---------|------|--------|
| `blender_status` | — | `{ alive: bool }` |
| `blender_scene_info` | — | BlenderSceneInfo |
| `blender_execute_code` | code: String | serde_json::Value |
| `blender_list_animations` | — | Vec\<BlenderAnimation\> |
| `blender_bake_animation` | action_name, output_path | String (path) |
| `blender_export_vrm` | output_path | String (path) |
| `blender_list_shapekeys` | — | Vec\<ShapeKey\> |
| `blender_set_shapekey` | name, value | () |
| `blender_screenshot` | — | Vec\<u8\> (PNG) |

#### 12.1.6 Oribis MCPツール（Anima操作用）

| ツール名 | 説明 |
|---------|------|
| `blender_status` | Blender MCPサーバー稼働確認 |
| `blender_scene_info` | シーン情報取得 |
| `blender_execute_code` | bpyコード実行 |
| `blender_list_animations` | アニメーション一覧 |
| `blender_bake_animation` | アニメーションベイク→FBX |
| `blender_export_vrm` | VRMエクスポート |

#### 12.1.7 既存連携ポイント

- `retargetMixamoToVrm.ts`: Blender出力FBX → VRMリターゲットパイプライン **既存実装済み**
- `avatarLoader.ts`: VRMファイルローディング **既存実装済み**
- `VrmViewer.tsx`: VRM描画・アニメーション再生 **既存実装済み**
- 連携フロー: Blender bake (MCP execute_code) → FBX → retarget → VRM animate

#### 12.1.8 Plugin V2連携

```yaml
# apps-v2/blender-hub/manifest.yaml
manifest_version: 2
name: blender-hub
capabilities: [characterMotion, uiSidebarPanel, events, netFetch]
extension_points: [uiSidebarPanel, characterMotionProvider]
```

- `characterMotionProvider`: Blenderからベイクしたアニメーションをモーションソースとして提供
- UIパネル: Blender接続状態・シーン情報・アニメーション一覧・ベイクボタン・スクリーンショット表示

#### 12.1.9 セキュリティ

- **execute_blender_code**: 任意Python実行可能 → Oribis側でスクリプトテンプレートのみ実行（ユーザー入力の直接注入禁止）
- **ローカル通信のみ**: localhost:9876 TCP。外部通信なし
- **Blender未起動時**: `is_alive()` false → UI側で「Blender未接続」表示。エラーにしない

---

## 13. Phase 3 ファイル構成

```
src-tauri/src/blender/
├── mod.rs
├── client.rs        // BlenderMcpProxy（MCP Broker経由）
├── commands.rs      // Tauriコマンド
├── types.rs         // 型定義
└── scripts/         // bpyスクリプトテンプレート（include_str!埋込）
    ├── bake_animation.py
    ├── export_vrm.py
    ├── list_shapekeys.py
    └── set_shapekey.py

src-tauri/src/mcp/tools/
└── blender.rs      // [NEW] Anima操作用MCPツール

apps-v2/blender-hub/
├── manifest.yaml
└── index.ts
```

---

## 14. Phase 3 実装順序

```
1. MCP Broker外部サーバー接続機能（blender-mcpプロセスspawn + 接続）
2. blender/client.rs + types.rs — BlenderMcpProxy
3. blender/scripts/ — bpyスクリプトテンプレート
4. blender/commands.rs — Tauriコマンド
5. mcp/tools/blender.rs — Anima操作用MCPツール
6. Plugin V2: blender-hub — UIパネル
```

---

## 15. 全体実装ロードマップ

```
Phase 1 [完了]: OAuth2 + Calendar + Tasks + Scheduler + MCP + UI
Phase 2 [次]: セキュリティ必須条件解消 → Gmail + Drive + YouTube + Photos + JWT identity
Phase 3 [後]: Blender連携（公式MCPサーバー前提）
```
