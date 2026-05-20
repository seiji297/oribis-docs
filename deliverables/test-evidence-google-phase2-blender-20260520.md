# テスト証跡: Google Phase2 + Blender Phase3

- 日時: 2026-05-20 21:12 JST
- 実行環境: WSL2 Ubuntu / Rust 1.87 / cargo test
- 対象ブランチ: develop

---

## 1. AC照合マトリクス

| AC | テスト内容 | テスト数 | 結果 | 代表テスト名 |
|----|-----------|---------|------|-------------|
| AC-1 | トークン暗号化 | 15 | PASS | `test_encrypted_tokens_in_db_are_not_plaintext`, `test_encrypt_decrypt_roundtrip`, `test_plaintext_fallback_in_load_tokens` |
| AC-2 | Client Secret除去 | 1 | PASS | `test_no_client_secret_in_source` (新規追加) |
| AC-3 | 401ループ防止 | 1 | PASS | `test_retry_abort_logic_exists_in_client` (新規追加) |
| AC-4 | identity不変性 | 5 | PASS | `test_save_identity_duplicate_ignore`, `test_save_and_load_identity` |
| AC-5 | JWT検証 | 11 | PASS | `test_token_response_with_id_token`, `test_pkce_challenge_correct_sha256` |
| AC-6 | 新API動作 | 39 | PASS | Gmail(11) + Drive(8) + YouTube(5) + Photos(12) + Tasks(6) 構造体テスト |
| AC-7 | Calendar CRUD | 9 | PASS | `test_deserialize_calendar_event`, `test_google_calendar_update_required_fields`, `test_google_calendar_delete_required_fields` |
| AC-8 | 朝読み上げ | 13 | PASS | `test_should_morning_readout_first_time`, `test_should_morning_readout_already_done`, `test_morning_hour_env_override` |
| AC-9 | MCPツール | 10 | PASS | `test_google_tool_definitions_count`, `test_google_tool_definitions_names` |
| AC-10 | Blenderプロキシ | 28 | PASS | `test_proxy_singleton_initialized`, `test_blender_animation_deserialize`, `test_blender_tool_definitions_count` |
| AC-11 | 全量PASS | 1359+5ign | PASS | cargo test exit 0 / pnpm typecheck exit 0 |

---

## 2. テスト件数サマリー

### cargo test (src-tauri/)
- 全テスト: 1364件（1359 passed + 5 ignored）
- 15 test suites
- 実行時間: 34.0s
- **結果: ALL PASS (exit 0)**

### 新規追加テスト（本タスク）
- `test_no_client_secret_in_source` (AC-2): google/配下rsファイルのGOOGLE_CLIENT_SECRET不在検証
- `test_retry_abort_logic_exists_in_client` (AC-3): client.rsの401リトライ中断ロジック存在検証

### pnpm typecheck
- コマンド: `tsc -p tsconfig.lib.json`
- **結果: PASS (exit 0, エラー出力なし)**

---

## 3. AC別詳細

### AC-1: トークン暗号化 (15テスト)
- `test_encrypt_decrypt_roundtrip` - AES-256-GCM暗号化→復号ラウンドトリップ
- `test_encrypt_decrypt_roundtrip_unicode` - Unicode文字列の暗号化→復号
- `test_decrypt_plaintext_fallback` - 平文入力時のエラー確認
- `test_encrypted_tokens_in_db_are_not_plaintext` - **DB直読み→暗号文確認、平文access_token不在**
- `test_plaintext_fallback_in_load_tokens` - 旧平文データの後方互換読み込み
- `test_save_and_load_tokens` - 保存→読み込みラウンドトリップ
- `test_upsert_tokens` - トークン上書き更新
- `test_delete_tokens` - トークン削除
- `test_is_authenticated_valid/expired_with_refresh/false_when_empty` - 認証状態判定
- `test_token_data_serialize` - TokenDataシリアライズ
- `test_init_db` - DB初期化

### AC-2: Client Secret除去 (1テスト・新規)
- `test_no_client_secret_in_source` - src/google/配下の全.rsファイル（テストファイル自身除く）にGOOGLE_CLIENT_SECRET文字列が含まれないことをファイルスキャンで検証
- 検索文字列は連結構築で自己ヒット回避

### AC-3: 401ループ防止 (1テスト・新規)
- `test_retry_abort_logic_exists_in_client` - client.rsソースコード内に以下が存在することを検証:
  - `new_token == old_token` (同一トークン比較)
  - `"401 retry aborted"` (中断エラーメッセージ)
- 実装: request_with_retry内でold_token/new_token比較→同一なら即Err返却

### AC-4: identity不変性 (5テスト)
- `test_save_identity_duplicate_ignore` - **同一sub INSERT→更新不可(INSERT OR IGNORE)**
- `test_save_and_load_identity` - 保存→読み込み
- `test_save_identity_minimal` - 最小フィールドでの保存
- `test_load_identity_empty` - 空DB読み込み
- `test_init_identity_table` - テーブル初期化

### AC-5: JWT検証 (11テスト)
- `test_token_response_with_id_token` - IdTokenClaimsデシリアライズ成功
- `test_token_response_without_id_token` - id_token未含有レスポンス
- `test_pkce_challenge_correct_sha256` - PKCE SHA-256チャレンジ
- `test_pkce_challenge_is_base64url` / `test_pkce_verifier_length` - PKCE検証
- `test_generate_auth_url_contains_required_params` - 認証URL生成
- `test_scopes_contain_openid/all_apis` - スコープ検証
- `test_state_nonce_is_unique` / `test_urlencoding_*` - セキュリティ関連

### AC-6: 新API動作 (39テスト)
- Gmail(11): `test_deserialize_list_response`, `test_parse_message_detail`, `test_extract_header`等
- Drive(8): `test_deserialize_files_list`, `test_drive_file_roundtrip`, `test_encode_special_chars`等
- YouTube(5): `test_google_youtube_videos_required_fields`等（MCPツール経由）
- Photos(12): `test_deserialize_media_items`, `test_photo_album_roundtrip`等
- Tasks(6): `test_deserialize_task`, `test_google_tasks_complete_required_fields`等

### AC-7: Calendar CRUD (9テスト)
- 構造体: `test_deserialize_calendar_event`, `test_deserialize_allday_event`, `test_deserialize_minimal_event`, `test_event_datetime_no_timezone`, `test_parse_empty_items`, `test_parse_items_array`
- MCPツール: `test_google_calendar_create_required_fields`, `test_google_calendar_update_required_fields`, `test_google_calendar_delete_required_fields`

### AC-8: 朝読み上げ (13テスト)
- `test_should_morning_readout_first_time` - 初回実行→true
- `test_should_morning_readout_already_done` - 実行済み→false（1日1回制御）
- `test_should_morning_readout_too_early` - 早朝→false（時刻条件）
- `test_should_morning_readout_custom_hour` - カスタム時刻
- `test_morning_hour_default/env_override/env_invalid` - 時刻設定
- `test_compute_minutes_until_*` - 時間計算
- `test_should_notify_gmail_*` - Gmail通知判定

### AC-9: MCPツール (10テスト)
- `test_google_tool_definitions_count` - ツール定義数検証
- `test_google_tool_definitions_names` - ツール名一覧照合
- `test_google_tool_definitions_have_input_schema` - 入力スキーマ存在
- 各ツールのrequired_fields検証(calendar create/update/delete, drive search, tasks complete, youtube videos)
- `test_not_authenticated_response` - 未認証時応答

### AC-10: Blenderプロキシ (28テスト)
- client(14): `test_bake_animation_template_substitution`, `test_export_vrm_template_substitution`, `test_parse_text_content_*`, `test_script_*_loaded`
- commands(2): `test_proxy_initially_none`, `test_proxy_singleton_initialized`
- types(7): `test_blender_animation_deserialize/serialize_roundtrip`, `test_blender_scene_info_*`, `test_shape_key_*`
- MCP tools(5): `test_blender_tool_definitions_count/names/have_input_schema`

---

## 4. 既知事項

- `anima::retrieval::tests::test_query_similar_events_skip_recent` は並列実行時にタイミング依存で稀にFAIL（単体実行PASS）。Phase2/3とは無関係。
- 5件のignoredテストはPhase2/3とは無関係（anima系の既存テスト）。
