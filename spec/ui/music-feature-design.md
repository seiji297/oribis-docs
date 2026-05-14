# Music機能 設計書（凍結アーカイブ）

> **ステータス**: 凍結（2026-05-15）
> **凍結理由**: YouTube Terms of Service 違反（自動操作・スクレイピングによるコンテンツ再生がToS Section 5に抵触）
> **対象ブランチ**: `sysdev-1/music-browser`

---

## 1. 機能概要

OribisアプリケーションのサイドバーにMusic タブを設け、YouTube/YouTube Musicの楽曲をCDP（Chrome DevTools Protocol）経由で検索・再生する機能。

Tauriバックエンドからヘッドレスブラウザを起動し、CDPでYouTubeページを操作する方式を採用していた。

---

## 2. UI設計

### 2.1 コンポーネント構成

| コンポーネント | ファイル | 役割 |
|---|---|---|
| `YouTubeMusicPanel` | `src/components/YouTubeMusicPanel.tsx` | Music機能の全UI |
| サイドバータブ | `src/App.tsx` (L505, L541, L703, L917) | ♪アイコンのタブ切替 |

### 2.2 UIレイアウト

```
┌─────────────────────────────────┐
│ [Search YouTube Music...] [Search] │
│ [x] Auto / [ ] Manual              │
├─────────────────────────────────┤
│ [Error message (if any)]            │
├─────────────────────────────────┤
│ [Thumbnail] Title                   │
│              Artist                 │
│              42s / 200s (or LIVE)   │
├─────────────────────────────────┤
│ [⏸/▶] [⏭] [✕]                     │
├─────────────────────────────────┤
│ Volume [=========>------] 75        │
└─────────────────────────────────┘
```

### 2.3 主要UI要素

- **検索フォーム**: テキスト入力 + Searchボタン
- **Auto/Manual切替**: チェックボックス。Auto=検索後自動再生、Manual=検索結果のみ表示
- **再生情報表示**: サムネイル画像、タイトル、アーティスト名、再生時間（LIVE対応: duration < 0 で「LIVE」表示）
- **再生コントロール**: Play/Pause、Next、Close
- **Volume スライダー**: 0-100 range input

### 2.4 状態管理

- `query: string` — 検索クエリ
- `state: PlaybackState | null` — 再生状態（Tauriイベント `youtube:state-changed` で受信）
- `error: string | null` — エラーメッセージ
- `autoSelect: boolean` — Auto/Manual切替（デフォルト: true）

### 2.5 サイドバー統合

`App.tsx` の `sidebarTab` 型定義に `"music"` を含め、♪（`&#9834;`）アイコンのタブボタンを配置。タブ選択時に `<YouTubeMusicPanel />` をレンダリング。

---

## 3. Tauriコマンド仕様

全7コマンド。すべて `#[cfg(feature = "tauri-backend")]` ガード付き。

### 3.1 youtube_search_and_play

```
引数: query: String, auto_select: Option<bool>
戻値: Result<(), String>
動作: 未初期化時はブラウザ自動起動。クエリをURLエンコードしてYouTube検索。
      auto_select=true: 最初の動画を自動クリック→再生
      auto_select=false: 検索結果ページ表示のみ
イベント発火: youtube:browser-ready (初回), youtube:state-changed, youtube:error
```

### 3.2 youtube_play

```
引数: なし
戻値: Result<(), String>
動作: video要素の.play()実行
イベント発火: youtube:state-changed, youtube:error
```

### 3.3 youtube_pause

```
引数: なし
戻値: Result<(), String>
動作: video要素の.pause()実行
イベント発火: youtube:state-changed, youtube:error
```

### 3.4 youtube_next

```
引数: なし
戻値: Result<(), String>
動作: 次の曲ボタン(.ytp-next-button)クリック
イベント発火: youtube:state-changed, youtube:error
```

### 3.5 youtube_set_volume

```
引数: volume: u8 (0-100)
戻値: Result<(), String>
動作: video要素のvolume設定 (0.0-1.0に変換)
バリデーション: volume > 100 → Err
イベント発火: youtube:state-changed, youtube:error
```

### 3.6 youtube_get_state

```
引数: なし
戻値: Result<PlaybackState, String>
動作: video要素から現在の再生状態を取得
```

### 3.7 youtube_close

```
引数: なし
戻値: Result<(), String>
動作: ブラウザプロセスを終了し、managerをNoneに戻す
```

---

## 4. PlaybackState型定義

### Rust (src-tauri/src/youtube_music.rs)

```rust
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct PlaybackState {
    pub is_playing: bool,
    pub title: String,
    pub artist: String,
    pub thumbnail_url: String,
    pub current_time: f64,
    pub duration: f64,     // LIVE時は -1.0
    pub volume: u8,        // 0-100
}
```

### TypeScript (src/types/music.ts)

```typescript
export interface PlaybackState {
  is_playing: boolean;
  title: string;
  artist: string;
  thumbnail_url: string;
  current_time: number;
  duration: number;       // LIVE時は負値
  volume: number;         // 0-100
}
```

---

## 5. CDPブラウザ連携アーキテクチャ

```
┌─────────────┐      Tauri Command      ┌──────────────────┐
│  Frontend   │ ───────────────────────> │  youtube_music   │
│  (React)    │                          │  (7 commands)    │
│             │ <─── youtube:state-changed │                │
└─────────────┘      (Tauri Event)       └────────┬─────────┘
                                                  │
                                         YoutubeMusicManager
                                                  │
                                         ┌────────▼─────────┐
                                         │  cdp_browser.rs  │
                                         │  (CDP Controller)│
                                         └────────┬─────────┘
                                                  │ CDP WebSocket
                                         ┌────────▼─────────┐
                                         │  Headless Chrome  │
                                         │  (YouTube page)   │
                                         └──────────────────┘
```

- `YoutubeMusicManager`: CDPブラウザコントローラーをラップし、YouTube固有のJS実行を提供
- `CdpBrowserController` (`cdp_browser.rs`): 汎用CDPブラウザ操作。navigate/eval_js/close
- AppState: `youtube_music: Mutex<Option<YoutubeMusicManager>>` — 初回search_and_play時にlazy初期化
- JS実行: DOMセレクタベースでvideo要素を直接操作（`.querySelector('video')`）

---

## 6. 凍結範囲

### 削除対象
- `src/components/YouTubeMusicPanel.tsx` — UIコンポーネント
- `src/types/music.ts` — PlaybackState型（フロントエンド）
- `src-tauri/src/lib.rs` 内の youtube_music 参照（mod宣言、AppStateフィールド、invoke_handler登録）
- `src/App.tsx` 内の music タブUI

### 残存ファイル
- `src-tauri/src/youtube_music.rs` — mod宣言を外しコンパイルから除外。設計参照用に保持
- `src-tauri/src/cdp_browser.rs` — 汎用ブラウザ操作機能として継続利用

---

## 7. 将来の再実装方針

### 7.1 YouTube Data API v3 + IFrame Player API

公式APIを使用する合法的アプローチ。

- **YouTube Data API v3**: 楽曲検索（`search.list`エンドポイント）
- **IFrame Player API**: 埋め込みプレーヤーによる再生（ToS準拠）
- **制約**: API quota（10,000 units/day デフォルト）、IFrame埋め込みの制約

### 7.2 Spotify Web API

代替音楽サービスとしてSpotifyを使用。

- **Spotify Web API**: 楽曲検索・メタデータ取得
- **Spotify Web Playback SDK**: ブラウザ内再生（Premium必須）
- **利点**: 公式SDK提供、ToS準拠が明確

### 7.3 BYOK（Bring Your Own Key）パターン

ユーザーが自身のAPIキーを提供する方式。

- アプリはAPIキーを同梱せず、ユーザーがSettings画面で入力
- ユーザー個人のquotaを使用 → アプリ提供者のquota問題を回避
- APIキーはローカルストレージ（暗号化推奨）に保存
- 初期設定のハードルはあるが、ToS・quota両方の問題を解決

---

## 8. 参照ファイル一覧

| ファイル | 状態 | 備考 |
|---|---|---|
| `src/components/YouTubeMusicPanel.tsx` | 削除 | UIコンポーネント |
| `src/types/music.ts` | 削除 | TS型定義 |
| `src-tauri/src/youtube_music.rs` | 残存（コンパイル除外） | Rust実装 |
| `src-tauri/src/cdp_browser.rs` | 残存（継続利用） | CDP汎用操作 |
| `src-tauri/src/lib.rs` | 修正 | youtube_music参照除去 |
| `src/App.tsx` | 修正 | musicタブUI除去 |
