# Regression Index

このファイルは、`test-matrix.md` の `Regression Scope` を人間が確認しやすい形に並べたビュー。  
一次情報は `test-matrix.md` に置く。ここには「どの機能追加で、どの既存機能を再確認するか」を残す。

## Critical Regression

| test_id | Area | 再発防止対象 |
|---|---|---|
| `ORB-SIT-001` | Worker Chat | DOMチャット送信、Anima terminal、Worker terminal、Chat output、Chat input clear |
| `ORB-SIT-002` | Discord Relay | チャンネルID固定、AI推論に頼らない送信、queue滞留なし、即時配送 |
| `ORB-ST-001` | Startup/GPU | Render Error、黒画面、残留Oribisウィンドウ、Xvfb/CPU代替禁止 |
| `ORB-ST-002` | Onboarding | 初回3DView単体、Anima表示、Terminal/Workbench/debug UI非表示 |
| `ORB-ST-003` | Scene App | Stage 3D、Anima正位置、terminal正位置、アスペクト比、Studio/物理/重力UI非表示 |
| `ORB-ST-004` | Workbench | Unity風dock/tab、Scene右、Anima左上、Workers左下、Console下 |
| `ORB-AT-001` | AI-native App Operation | 自然言語からApp tool catalog/schema経由で実行。固定語録ルーター復活禁止 |

## Required Regression

| test_id | Area | 再発防止対象 |
|---|---|---|
| `ORB-STATIC-001` | Build | TypeScript/Rust/Vite build break、起動不能入口 |
| `ORB-STATIC-002` | Test Harness | direct/mock/test-only route混入、セッション/ログ未リセット |
| `ORB-STATIC-003` | AI-native | 固定語録ルーター、negation語録、schema外args許容 |
| `ORB-IT-004` | App Manifest / Permission / Catalog | manifest schema、capability discovery、permission、tool catalog |
| `ORB-IT-006` | App Runtime / Sandbox / Sidecar / Package | scan/install/enable、sandbox、package、sidecar、storage/fs/net |
| `ORB-IT-005` | External Service Apps | Discord/Google/GitHub/Blender/Work Report Appのmanifest/allowlist/permission境界 |
| `ORB-SIT-003` | WebViewer Connection | Web接続、入力、クリック、結果取得、証跡保存 |
| `ORB-SIT-005` | Agent Server / Collaboration | AgentRole/InvocationKind/Placement、常駐Agent間conversation/inbox |
| `ORB-SIT-006` | Remote / Web Remote / Auth | Remote無効時の非露出、有効時の認証/権限/レート制限 |
| `ORB-SIT-007` | Anima Memory / Retrieval | Anima 4層記憶、永続化、検索、注入、削除 |
| `ORB-SIT-009` | Prompt / Skills / Templates | prompt、skill、template、task解決 |
| `ORB-SIT-008` | Auth / License / Subscription | token/secret非表示、認証状態遷移、期限切れ/失効 |
| `ORB-SIT-010` | Recording / Scheduler | 録画、スケジュール、重複実行、再起動後状態 |
| `ORB-ST-005` | Console/Log | Console/Log統合、不要なJobs/Tasks/Queue分散UI削減 |
| `ORB-ST-006` | WebViewer UI | Oribis App windowとしてのWebViewer表示、不自然な白window禁止 |
| `ORB-AT-002` | Settings/Anima UX | 猫でもわかるオンボード設定、カード型、LLM/Anima基本設定 |
| `ORB-AT-003` | Worker UX | Workerが考えていることが分かるterminal/進捗/結果 |
| `ORB-AT-004` | WebViewer UX | リアルタイムWeb構築/操作体験 |
| `ORB-AT-005` | Audio/TTS UX | 音声破綻、速度/ピッチ/音量/抑揚設定反映 |

## Supporting Regression

| test_id | Area | 再発防止対象 |
|---|---|---|
| `ORB-UT-001` | App Runtime | schema/tool/policy単体 |
| `ORB-UT-002` | Worker Core | protocol/session/store/permission/redaction |
| `ORB-UT-003` | Scene Runtime | terminal layout、projection、runtime client |
| `ORB-UT-004` | Anima/TTS | TTS設定、読み上げ整形、Rust側TTS |
| `ORB-IT-001` | RootShell/App | App起動、window状態、dock/tab、RootShell配線 |
| `ORB-IT-002` | Settings/Anima App | Settings/Anima UI保存・表示 |
| `ORB-IT-003` | AI-native UI | UI上のApp action catalog表示/配線 |
| `ORB-SIT-004` | Tauri/Rust bridge | Tauri command、Worker server、app runtime境界 |

## Diagnostic Only

| test_id | Area | 用途 |
|---|---|---|
| `ORB-DIAG-001` | Local Windows DevUrl | local-windowsの1420黒画面切り分け。AT/ST/Release Gateの代替にしない |
