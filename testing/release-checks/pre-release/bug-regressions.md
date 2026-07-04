# Bug Regressions

この台帳は、Producer/QAが実画面または実運用で見つけた重要不具合を、正本の `test-matrix.md` へ接続するための回帰台帳。

これは独立したRegressionフェーズではない。  
各不具合は必ず `linked_test_ids` で正本の保証項目へ紐づけ、Release Gateでは `release_blocking=true` の項目がすべて `verified` になっていることを確認する。

## 判定ルール

- `release_blocking=true` かつ `status != verified` はRelease Gateを通さない。
- `severity=critical` は原則 `release_blocking=true`。
- `severity=high` はRelease Ownerの明示的なdefer承認がない限り `release_blocking=true`。
- `linked_test_ids` が空の不具合は未整理扱い。
- `fix_commit` があっても `evidence_paths` がなければ `fixed_pending_verification` のまま。
- `verified` には、その不具合自身の再現条件に対する正規証跡と、この台帳の証跡が必要。紐づく `test_id` 全体が `PASS_WITH_LIMITATION` または `NOT_RUN` の場合でも、バグ固有条件が再発しないことを十分に確認できるならバグは `verified` にできる。ただし正本 `test_id` の未達はRelease Gate上で別途残す。
- `waived` / `deferred` / `wontfix` は理由、影響範囲、承認者、期限または修正予定versionを必須にする。
- `requires_test_matrix_update=true` なのに `test_matrix_update_summary` が空の不具合はRelease Gate未達扱い。
- AI/automationが確認した不具合は、確認できた範囲と確認できなかった範囲を `limitations` に残す。

## Status

| status | 意味 |
|---|---|
| `open` | 未修正または修正方針未確定 |
| `fixed_pending_verification` | 修正済みだが正規証跡未完了 |
| `verified` | 正規証跡で再発なし確認済み |
| `reopened` | 再発または証跡不備で再オープン |
| `waived` | 明示承認つきで一時免除 |
| `deferred` | 明示承認つきで延期 |
| `wontfix` | 明示承認つきで非対応 |

## 必須フィールド

| field | 内容 |
|---|---|
| `bug_id` | 一意ID |
| `title` | 不具合名 |
| `severity` | `critical` / `high` / `medium` / `low` |
| `source` | `Producer` / `QA` / `CI` / `Support` |
| `reported_at` | 指摘日 |
| `affected_area` | 影響領域 |
| `description` | 指摘内容 |
| `expected_behavior` | 期待挙動 |
| `actual_behavior` | 実際の挙動 |
| `linked_test_ids` | 正本 `test-matrix.md` の該当ID |
| `root_cause_summary` | 原因要約 |
| `regression_risk` | 再発リスク |
| `requires_test_matrix_update` | 正本の保証項目へ反映が必要か |
| `test_matrix_update_summary` | どのAcceptance Criteria / Required Evidence / Regression Scopeへ反映したか |
| `fix_commit` | 修正commit。未確定なら空 |
| `verification_runner` | `WindowsQA Server` / `WDIO` / `Vitest` / `Cargo` / `manual review` |
| `verification_env` | 検証環境 |
| `evidence_paths` | 証跡パス |
| `verification_evidence` | 再確認可能な証跡の要約 |
| `limitations` | AI/automation/human reviewが確認できなかった範囲 |
| `status` | 上記Status |
| `release_blocking` | Release Gateを止めるか |
| `verified_at` | 確認日時 |
| `verified_by` | 確認者 |
| `notes` | 補足 |

## Required Detail Records

`Current Bug Regression Items` は人間向けの要約表。Release Gateで使う必須フィールドはこの詳細表と `manifest.json` の `bugRegressions` を正とする。

| bug_id | root_cause_summary | regression_risk | requires_test_matrix_update | test_matrix_update_summary | verification_evidence | limitations |
|---|---|---|---|---|---|---|
| ORB-BUG-001 | React hook import漏れでScene/Avatar初期描画がRender Error化 | critical | true | ORB-ST-001/003にRender Error不在とAnima VRM loadを明記 | onboarding scene PNG/JSON | desktop-wide screenshot warnはST側に残る |
| ORB-BUG-002 | Stage初期表示がAnima VRMでなく仮placeholderを出す | critical | true | ORB-ST-001/002/003にplaceholder禁止とVRM表示を明記 | onboarding scene PNG/JSON | default startup pathのみ |
| ORB-BUG-003 | OnboardingでWorkbench/terminal/debug UIが混入 | critical | true | ORB-ST-002にScene-only表示を明記 | onboarding scene PNG/JSON | Workbench layoutはORB-ST-004で別管理 |
| ORB-BUG-004 | 初期アニメーション状態がidleへ安定せずT-poseが見える | high | true | ORB-ST-002/003にidle pose証跡を明記 | onboarding scene PNG/JSON | 全animation transitionは対象外 |
| ORB-BUG-005 | Pane resize時にcanvas/drawingBuffer同期が崩れる | high | true | ORB-ST-003/004にresize後aspect metricsを明記 | resize PNG/metrics JSON | 代表pane resizeのみ |
| ORB-BUG-006 | Scene App化で旧3D Viewer必須UIの移植漏れ | high | true | ORB-ST-003/004にchat/attach/mic/send/tabs/LLM overlayを明記 | default layout PNG/summary JSON | presence確認で各操作は別項目 |
| ORB-BUG-007 | Scene chat inputの配置がログや右側UIへ重なる | high | true | ORB-ST-003/004にbottom centered inputとoverlap禁止を明記 | default layout PNG/summary JSON | default viewportのみ |
| ORB-BUG-008 | App選択状態が閉じるバッテンに見える | medium | true | ORB-ST-004にclose/delete誤認UI禁止を明記 | default layout PNG/summary JSON | default active tabsのみ |
| ORB-BUG-009 | WebViewerが前回/謎ページを初期表示する | high | true | ORB-ST-006/AT-004にmanual open empty-stateを明記 | WebViewer empty PNG/JSON | 実Web操作はSIT-003/AT-004で別管理 |
| ORB-BUG-010 | Settings/App画面にテーマ不一致の白パネルが残る | high | true | ORB-AT-002/ST-004にtheme-consistent panelsを明記 | settings/apps PNG/theme JSON | representative screensのみ |
| ORB-BUG-011 | Settings Generalへ設定が過密配置 | medium | true | ORB-AT-002にfocused tabs構成を明記 | settings/apps PNG/theme JSON | 個別設定値全件は対象外 |
| ORB-BUG-012 | Prompt/files/cache/AnimaCacheが重複タブ化 | medium | true | ORB-AT-002/SIT-007/009にPrompts統合を明記 | prompts state JSON/PNG | backend memory/promptはSITで別管理 |
| ORB-BUG-013 | Onboarding default nameがIdea | medium | true | ORB-ST-002/AT-002にdefault anima名を明記 | onboarding PNG/saved-state JSON | default onboarding stateのみ |
| ORB-BUG-014 | User name defaultがUserでない | medium | true | ORB-ST-002/AT-002にdefault User名を明記 | onboarding PNG/saved-state JSON | default onboarding stateのみ |
| ORB-BUG-015 | Worker Chatがqueued/completedだけ返し本文がない | critical | true | ORB-SIT-001/AT-003にWorker terminal/chat output本文を明記 | planned WindowsQA worker-chat | local Vitestのみ完了、officialはSSH timeout |
| ORB-BUG-016 | Worker Chat画面にAnima入力欄が重なる | high | true | ORB-SIT-001/AT-003にWorker input overlap禁止とclearを明記 | planned WindowsQA worker-chat | local checksのみ完了、officialはSSH timeout |
| ORB-BUG-017 | Anima内部メタ情報がチャット/音声へ漏れる | high | true | ORB-AT-002/005に内部メタ非表示/非読み上げを明記 | chat regression PNG/JSON | chat表示は確認済み、実音声はAT-005に残る |
| ORB-BUG-018 | AI-native App操作が固定語録ルーター化 | critical | true | ORB-STATIC-003/AT-001にschema/tool catalog routingと固定語録禁止を明記 | route acceptance JSON/PNG, local catalog prompt tests | 固定ルーター再発はverified、real LLM品質はAT-001 limitation |
| ORB-BUG-019 | Discord Relayが滞留/遅延/不達になる | critical | true | ORB-SIT-002にsystem-routed immediate delivery/queue metricsを明記 | local surface closure result, planned real relay evidence | 実Discord送受信/queue metrics未完了 |
| ORB-BUG-020 | Startup時に残留Oribis/ロード途中windowが残る | critical | true | ORB-ST-001にprocess/window inventoryを明記 | process guard JSON/summary ZIP | desktop screenshot warningはST側 |
| ORB-BUG-021 | StageにStudio用物理/重力/キューブ落下が混入 | high | true | ORB-ST-003にStage deny-by-defaultを明記 | stage guard JSON/summary ZIP | Studio全操作は対象外 |
| ORB-BUG-022 | WebViewerの実Web接続/自動操作が未完了 | high | true | ORB-SIT-003/AT-004にreal web connection and automationを明記 | WebViewer automation PNG/JSON | localhost代表ページのみ |

## Current Bug Regression Items

| bug_id | title | severity | source | reported_at | affected_area | linked_test_ids | status | release_blocking | evidence_paths | notes |
|---|---|---|---|---|---|---|---|---|---|---|
| ORB-BUG-001 | BabylonAvatarViewer useCallback未定義Render Error | critical | Producer | 2026-07-03 | Startup / Scene / Avatar | ORB-ST-001, ORB-ST-003 | verified | true | `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-onboarding-scene-camera2-20260704-002011\extracted\wdio-evidence\onboarding-scene-only.png`, `...\onboarding-scene-only.json` | WindowsQA official / commit `7ad8bc0747156b3371fcfa1980249581ab235f2b`。Render Errorなし、`avatarLoadState=loaded`。 |
| ORB-BUG-002 | 起動/オンボード時にAnimaではなく白い棒人間シーンが出る | critical | Producer | 2026-07-03 | Startup / Onboarding / Scene | ORB-ST-001, ORB-ST-002, ORB-ST-003 | verified | true | `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-onboarding-scene-camera2-20260704-002011\extracted\wdio-evidence\onboarding-scene-only.png`, `...\onboarding-scene-only.json` | WindowsQA official / commit `7ad8bc0747156b3371fcfa1980249581ab235f2b`。右側にAnima VRM表示、`stageAnimaModel=vrm`。 |
| ORB-BUG-003 | Onboardingで3D View単体ではなくWorkbench/Terminal/debug UIが混ざる | critical | Producer | 2026-07-03 | Onboarding | ORB-ST-002 | verified | true | `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-onboarding-scene-camera2-20260704-002011\extracted\wdio-evidence\onboarding-scene-only.png`, `...\onboarding-scene-only.json` | WindowsQA official / commit `7ad8bc0747156b3371fcfa1980249581ab235f2b`。`workbenchVisible=false`, `terminalToggleVisible=false`, `leakedDebugText=false`。 |
| ORB-BUG-004 | キャラクターが毎回Tポーズから始まる | high | Producer | 2026-07-03 | Avatar / Onboarding / Scene | ORB-ST-002, ORB-ST-003 | verified | true | `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-onboarding-scene-camera2-20260704-002011\extracted\wdio-evidence\onboarding-scene-only.png`, `...\onboarding-scene-only.json` | WindowsQA official / commit `7ad8bc0747156b3371fcfa1980249581ab235f2b`。`avatarAnimationState=idle`, `poseRetargetStatus=ok`, `idlePoseBones=1`。 |
| ORB-BUG-005 | 3Dビューのリサイズでアスペクト比が崩れる | high | Producer | 2026-07-03 | Scene App / 3D View | ORB-ST-003, ORB-ST-004 | verified | true | `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-core-workbench-scene-input-20260704-005006\extracted\wdio-evidence\core-app-workbench-after-resize.png`, `...\core-app-workbench-scene-canvas-metrics-after-resize.json` | WindowsQA official / commit `b10263d49f1bff02e0539173ef36e44923d0bbb4`。Pane resize後もcanvas/drawingBuffer/viewer/sceneの比率が一致。 |
| ORB-BUG-006 | Scene App化で旧3D Viewerの必須UIが欠ける | high | Producer | 2026-07-03 | Scene App | ORB-ST-003, ORB-ST-004 | verified | true | `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-core-workbench-scene-input-20260704-005006\extracted\wdio-evidence\core-app-workbench-default-layout.png`, `...\summary.json` | WindowsQA official / commit `b10263d49f1bff02e0539173ef36e44923d0bbb4`。Scene Appにchat panel/input/attach/mic/send/tabsとLLM overlayあり。 |
| ORB-BUG-007 | Scene Appのチャット入力欄がログ/右側に被る | high | Producer | 2026-07-03 | Scene App / Chat UI | ORB-ST-003, ORB-ST-004 | verified | true | `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-core-workbench-scene-input-20260704-005006\extracted\wdio-evidence\core-app-workbench-default-layout.png`, `...\summary.json` | WindowsQA official / commit `b10263d49f1bff02e0539173ef36e44923d0bbb4`。`sceneChatInputCentered=true`, attach/mic/sendあり、旧`.pane-bottom`入力なし。 |
| ORB-BUG-008 | App選択時にタブUIがバッテン表示になる | medium | Producer | 2026-07-03 | Workbench / App Window | ORB-ST-004 | verified | true | `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-core-workbench-scene-input-20260704-005006\extracted\wdio-evidence\core-app-workbench-default-layout.png`, `...\summary.json` | WindowsQA official / commit `b10263d49f1bff02e0539173ef36e44923d0bbb4`。`tabCloseButtonCount=0`、App選択状態に閉じるUIなし。 |
| ORB-BUG-009 | WebViewerを押すと最初から謎ページ/前回内容が出る | high | Producer | 2026-07-03 | WebViewer | ORB-ST-006, ORB-AT-004 | verified | true | `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-core-workbench-scene-input-20260704-005006\extracted\wdio-evidence\core-app-workbench-web-viewer-empty.png`, `...\core-app-workbench-web-viewer-manual.json` | WindowsQA official / commit `b10263d49f1bff02e0539173ef36e44923d0bbb4`。手動Open時 `empty=true`, `iframe=false`, `inputValue=""`。 |
| ORB-BUG-010 | Settings/App画面に白いパネルが残る | high | Producer | 2026-07-03 | Settings / Apps UI | ORB-AT-002, ORB-ST-004 | verified | true | `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-core-workbench-scene-input-20260704-005006\extracted\wdio-evidence\core-app-workbench-settings-apps.png`, `...\core-app-workbench-settings-apps-theme.json` | WindowsQA official / commit `b10263d49f1bff02e0539173ef36e44923d0bbb4`。`hasWhitePanel=false`。 |
| ORB-BUG-011 | Generalに設定が詰まりすぎている | medium | Producer | 2026-07-03 | Settings / Anima UX | ORB-AT-002 | verified | true | `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-settings-onboarding-regression-20260704-010303-core\extracted\wdio-evidence\core-app-workbench-settings-apps.png`, `...\core-app-workbench-settings-apps-theme.json` | WindowsQA official / commit `544504b302aa6b38cdb3747707dd15fd4c1ba40c`。Settingsは`Appearance/Input/Scene/TTS/Project/Remote/Apps`へ分割、`generalTab=false`。 |
| ORB-BUG-012 | Prompt/files/cache/AnimaCacheのタブ重複 | medium | Producer | 2026-07-03 | Anima / Prompt / Memory | ORB-AT-002, ORB-SIT-007, ORB-SIT-009 | verified | true | `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-settings-onboarding-regression-20260704-010303-core\extracted\wdio-evidence\core-app-workbench-default-layout.png`, `...\core-app-workbench-anima-prompts-state.json` | WindowsQA official / commit `544504b302aa6b38cdb3747707dd15fd4c1ba40c`。Anima Appは`Prompts`タブ1つに統合し、Core/File/Anima Memory Cacheを同一画面内に表示。 |
| ORB-BUG-013 | Onboardingデフォルト名がIdeaになっている | medium | Producer | 2026-07-03 | Onboarding / Anima | ORB-ST-002, ORB-AT-002 | verified | true | `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-settings-onboarding-regression-20260704-010303-onboarding\extracted\wdio-evidence\onboarding-anima-visual-main-ui.png`, `...\onboarding-anima-visual-saved-state.json` | WindowsQA official / commit `544504b302aa6b38cdb3747707dd15fd4c1ba40c`。保存値 `characterName=anima`、`Idea` ではない。 |
| ORB-BUG-014 | ユーザー名のデフォルトがUserでない | medium | Producer | 2026-07-03 | Onboarding / Settings | ORB-ST-002, ORB-AT-002 | verified | true | `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-settings-onboarding-regression-20260704-010303-onboarding\extracted\wdio-evidence\onboarding-anima-visual-main-ui.png`, `...\onboarding-anima-visual-saved-state.json` | WindowsQA official / commit `544504b302aa6b38cdb3747707dd15fd4c1ba40c`。保存値 `userName=User`。 |
| ORB-BUG-015 | Worker Chatがqueued/completedだけで回答本文を返さない | critical | Producer | 2026-07-03 | Worker Chat | ORB-SIT-001, ORB-AT-003 | fixed_pending_verification | true | `planned: tests/worker-chat.spec.ts on WindowsQA official` | 新実装のlocal VitestはPASS。最新QA ref `e9c0307fc10b6d7f9fb401c89a391418bc88c09e` でWindowsQA official再実行が必要。 |
| ORB-BUG-016 | Worker Chat画面にAnima入力欄が重なる | high | Producer | 2026-07-03 | Worker Chat / Chat UI | ORB-SIT-001, ORB-AT-003 | fixed_pending_verification | true | `planned: tests/worker-chat.spec.ts on WindowsQA official` | 新実装のlocal checksはPASS。最新QA ref `e9c0307fc10b6d7f9fb401c89a391418bc88c09e` でWindowsQA official再実行が必要。 |
| ORB-BUG-017 | Anima応答で好感度メタがチャットに漏れる | high | Producer | 2026-07-03 | Anima Chat / TTS | ORB-AT-002, ORB-AT-005 | verified | true | `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-anima-chat-affinity-meta-20260704-022840\extracted\wdio-evidence\anima-chat-regression\anima-chat-affinity-meta.png`, `...\anima-chat-affinity-meta.json`, `...\latest-summary.json` | WindowsQA official / commit `6f08c523c045d82afc8c7a9d45305883e9dcf8ae`。実チャット送信経路で表示本文から好感度メタが消えることを確認。TTS側はfrontend/Rust双方にマーカー除去を追加しlocal supporting test PASS。実音声出力確認は `ORB-AT-005` 側に残す。 |
| ORB-BUG-018 | AI-native App操作が固定語録ルーター化する | critical | Producer | 2026-07-03 | AI-native App Operation | ORB-STATIC-003, ORB-AT-001 | verified | true | `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-app-ai-native-route-acceptance-20260704-0250\latest-summary.json`, `...\extracted\wdio-evidence\app-ai-native-route-acceptance\app-ai-native-route-acceptance.json`, `...\app-ai-native-route-acceptance.png` | WindowsQA official / commit `5d5589780b0e571bc2c3038bacef76adbe60b7d4`。実チャット送信から決定的mock Anima応答でApp tool invoke 30件PASS。固定語録ルーターではなくschema/tool catalog経路を確認。実LLM自然言語品質評価は別途quality signal。 |
| ORB-BUG-019 | Discord Relayが滞留/遅延/不達になる | critical | Producer | 2026-07-03 | Discord Relay | ORB-SIT-002 | fixed_pending_verification | true | `evidence/ORB-BUG-019/result.json` | 旧Worker Core Discord outbox queue導線をDeveloper Console/CommandRegistry/TypingScript DSL/RootShellから削除し、Agent Discord route/deliveryを正規経路として維持。実Discord送受信/queue metricsのWindowsQA証跡は `ORB-SIT-002` に残す。 |
| ORB-BUG-020 | Startup時に残留Oribis/ロード途中ウィンドウが残る | critical | Producer | 2026-07-03 | Startup / Process / Window | ORB-ST-001 | verified | true | `evidence/ORB-BUG-020/result.json`, `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-startup-stage-guards-20260704-0345\latest-summary.json`, `...\20260704-034448.zip` | WindowsQA official / commit `d37b7b02184b227f595bbf01af913d0b48dec4cd`。`official=true`, `sourceMode=git`, cleanChecks PASS, processChecks pre/post PASS, skippedStepsなし。 |
| ORB-BUG-021 | StageにStudio用物理/重力/キューブ落下など不要機能が混ざる | high | Producer | 2026-07-03 | Stage / Scene App | ORB-ST-003 | verified | true | `evidence/ORB-BUG-021/result.json`, `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-startup-stage-guards-20260704-0345\latest-summary.json`, `...\20260704-034448.zip` | WindowsQA official / commit `d37b7b02184b227f595bbf01af913d0b48dec4cd`。Stage projection deny-by-default、Studio cube非投影、terminal同期、オンボードScene単体表示を実アプリ経路で確認。 |
| ORB-BUG-022 | WebViewerの実Web接続/自動操作がリリース価値として未完了 | high | Producer | 2026-07-03 | WebViewer / AI Operation | ORB-SIT-003, ORB-AT-004 | verified | true | `C:\Users\admin\Pictures\agante-projects\sysdev\oribis-webviewer-app-ai-native-evidence-20260704-021712\extracted\wdio-evidence\app-ai-native-chat\web-viewer-ai-native.png`, `...\web-viewer-ai-native-state.json`, `...\latest-summary.json` | WindowsQA official / commit `96f5943445452f5988fc7ee7cacc4eef88681150`。チャット送信経路からWebViewer URL設定、localhost実ページ表示、`waitForText` automation結果取得までPASS。 |
