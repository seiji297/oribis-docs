<!-- AUTO-DOC-GEN:STATUS-START -->
| 項目 | 値 |
|------|-----|
| ブランチ | `` |
| コミット | `` |
| 日時 |  |
| サマリー |  |
<!-- AUTO-DOC-GEN:STATUS-END -->

# Oribis 進捗管理

**最終更新**: 2026-05-29

---

## 運用ルール

- **全体フローが唯一の優先度管理面**。タスクの追加・完了・優先度変更はここで行う
- 下部の spec/issues テーブルは「何があるか」のレジストリ（ステータス列のみ更新）
- AIエージェントは**タスク着手前・完了後**に全体フローを確認・更新すること
- 全体フローに載っていないタスクを着手する場合は、まずここに追加してから着手

---

## 全体フロー

### 現在地
- **アクティブトラック**: 商用化準備（COM）— 残P0: リリースページ公開のみ
- **完了トラック**: 記憶システム（G1）、MCP Server（G9）、オーケストレーター、Web Remote P1/P2、商用化P1全件、chat-mode-plugin（Task 1〜6 全完了）
- **Phase 0（表情）**: 完了
- **Phase 1（記憶基盤）**: 完了
- **商用化P0-2/P1-1〜5**: 完了（2026-05-27）— Rust 1500 / TS 822 / E2E 22 全PASS
- **その他**: pending-tasks.md に移動済み。Producer指示があれば復帰

### 実装フロー（codex-adviser レビュー済 2026-05-07）

```
Track 1: 記憶システム（G1） — memory.md v3.5
┌─────────────────────────────────────────────────────────────┐
│ Phase 1: 基盤 ✅ 完了                                        │
│   G1-a: SQLite基盤 + oribis-meta パーサー + migration       │
│   G1-b: CLAUDE.md oribis-meta出力指示反映                   │
│   G1-c: Level 1/2 trigger + scheduler配線                   │
│   G1-d: telemetry（meta欠落率監視）                         │
│                                                              │
│ Phase 2: 統合 + 想起                                         │
│   G1-e: L3 4ch検索 + ContextMode ✅ 完了                     │
│   G1-f: 忘却曲線 + recency decay ✅ 完了                     │
│     ※ G1-e直後に配置（ranking基準線確立のため）             │
│                                                              │
│ Phase 3: 深化 + 進化 + 意味検索                              │
│   G1-EL: 軽量エンティティリンク（§8.6） ✅ 完了             │
│     oribis-meta topics/entities → SQLiteエンコード           │
│   G1-g: Level 2 consolidation（LLM非同期・stub→実装）✅ 完了│
│   G1-h: relationship_model ✅ 完了                           │
│     L3注入 + 即時Boundary/Correction更新                    │
│   G1-SM: self_model（§6.5）✅ 完了                           │
│     evidence蓄積+L3注入+L1 decay/promotion                 │
│   G1-i: 記憶進化（A-MEM軽量版）✅ 完了                     │
│     L1でstrengthen/supersede/promote/no-op 4操作            │
│   G1-j: Operational Memory（worker_patterns）✅ 完了        │
│   G1-k: ハイブリッドベクトル検索 ✅ 完了                     │
│     fastembed(e5-small)+cosine+Phase3ランキング             │
└─────────────────────────────────────────────────────────────┘

Track 2: AnimaMode（G3） — anima.md §6  ✅ 完了
┌─────────────────────────────────────────────────────────────┐
│ バックエンド: 3分岐（Cache/Ai/Hybrid）✅                    │
│ UI↔backend モード名統一 ✅ cb9db93                          │
│   フロント: off/cache/hybrid/ai（Rust AnimaMode と一致）     │
│   Tauriコマンド: anima_mode パラメータ追加・不正値エラー返却 │
│   UIトグル: off→cache→hybrid 3段切替                        │
└─────────────────────────────────────────────────────────────┘

Track 3: オーケストレーター — anima-orchestrator-architecture.md
┌─────────────────────────────────────────────────────────────┐
│ P1 ✅ 完了（Epic: epic-oribis-orchestrator-p1-20260508）    │
│   types.ts 5型定義 + Rust Worker基盤(events/dept/worker_mgr)│
│   narration.rs + MCP tools/event_feed + Speech Queue        │
│   lib.rs 8 Tauriコマンド登録                                │
│   フロントエンド5コンポーネント(WorkerPanel/DrawerAnima/     │
│     DrawerDepartment/DrawerEventFeed/XtermTerminal拡張)     │
│   App.tsx 二重タブ再編 + PTYパネル統合                       │
│   テスト20件(前端) + 796件(Rust)中新規追加分全PASS          │
│   Onboarding Step3 Department改編                           │
│                                                              │
│ P1品質修正 ✅ 完了（2026-05-08）                             │
│   タスク1: Worker kill統合(Rust) — set_worker_pid/          │
│     get_worker_pid/pty_kill統合 + 15テストPASS              │
│   タスク2: WorkerPanel kill順序(TS) — forwardRef/           │
│     useImperativeHandle kill() + xtermRefs Map管理          │
│   タスク3: narration per-worker cursor —                    │
│     get_batch_for_worker/list_event_workers追加             │
│     fetch_and_process_batch_inをper-worker独立取得に変更    │
│   タスク4: MCP session identity —                           │
│     ClientInfoにworker_id/worker_session_id追加             │
│     handle_write_event_inで実worker_id→token_prefix fallback│
│   テスト: 812PASS/1FAIL(既存・無関係)                        │
│   ブランチ: sysdev-1/oribis-orch-p1-fix (4e5d6c8)           │
│   成果物: docs/deliverables/p1-fix-20260508/                │
│                                                              │
│ P2 ✅ 実装済（Epic: epic-oribis-orchestrator-p2-20260510）   │
│   CRUD API + PipelineView/DepartmentLane UI                  │
│   OrchestratorEditor タブUI（5タブ）                         │
│   PromptsTab セキュリティ（symlink/UUID/10MB制限）           │
│   Delete/Rename hasActiveWorker UI拒否                       │
│   vitest 563 PASS / cargo test 955 PASS（2026-05-11）        │
│                                                              │
│ P2追加実装 ✅（sysdev-1/oribis-orchestrator-p2, 2026-05-12） │
│   DrawerAnima 内部タブ実装（Status/Prompt/Memory/Console/    │
│     Settings）＋ CSS テーマ対応（CSS変数・クラス使用）        │
│   Prompt タブ: L1/L2/AnimaCache 全バックエンドに表示         │
│   Deep Reasoning delegation（DelegatingAdapter + threshold） │
│   GeneralTab Orchestrator対応 + DrawerAnima設定統合          │
│   vitest 568 PASS / cargo test 1036 PASS（2026-05-12）       │
│                                                              │
│ P3 ✅ 完了（sysdev-1/oribis-orchestrator-p2, 2026-05-12）   │
│   P3-A: scheduler engine（parse_interval/should_run_now/    │
│     start_scheduler_loop/update_schedule_item）6254a02      │
│   P3-B: DELEGATE_TO 自動ルーティング（マーカーパース→        │
│     target dept channel emit）f7ab1a7                       │
│                                                              │
│ セキュリティ修正 ✅ 完了（071e92b, 2026-05-12）              │
│   assetProtocol scope制限 + Plugin icon XSS対策             │
│   + filepath traversal修正                                  │
│                                                              │
│ 起動時Anima自動接続 ✅ 完了（b6f7e5a, 2026-05-12）           │
│   プロジェクト選択後1.2秒で時刻別挨拶を自動送信             │
│   （おはよう/こんにちは/こんばんは）                         │
│                                                              │
│ open_cli_terminal WSLフォールバック修正 ✅（b87f53d）        │
│   powershell.exeフルパス(/mnt/c/Windows/System32/...)追加   │
│                                                              │
│ GUI動作確認 ✅（WSLg + スクリーンショット確認, 2026-05-12）  │
│   自動挨拶「こんばんは、プロデューサー。何かありましたか。」  │
│   表示確認済                                                 │
└─────────────────────────────────────────────────────────────┘

Track 5: Web Remote — spec/ui/web-remote.md
┌─────────────────────────────────────────────────────────────┐
│ P1 ✅ 完了（sysdev-1/web-remote-p1, 2026-05-13）            │
│   axum HTTP+WSサーバー（standalone binary: web_remote_server)│
│   静的配信（ServeDir + SPA fallback）                        │
│   POST /api/invoke/:cmd（allowlist制）                       │
│   api-client.ts（isTauri切替）                               │
│   Bearer token認証 + CORS                                    │
│   /ws/events WS（Rust→WS broadcast）                        │
│   smoke E2E 5/5 PASS / cargo test 1016 PASS                 │
│                                                              │
│ P2 ✅ 完了（sysdev-1/web-remote-p2, 2026-05-14）            │
│   WS受信ディスパッチャ（WS→Rust dispatch_emit + callback）  │
│   AndroidタッチCSS（@media coarse / 44px / 100dvh）          │
│   Cargoワークスペース + oribis-web-remoteクレート分離        │
│   pnpmワークスペース + @oribis/web-remote外皮パッケージ      │
│   Tailscale+Android Chromeセットアップガイド                 │
│   cargo test 1022 PASS / pnpm test 360 PASS                 │
│                                                              │
│ P3 未着手                                                    │
│   WS ストリーミング/PTY/音声（WR-11〜15）                   │
│   HTTPS/WSS対応・PWA化・Android実機確認                      │
└─────────────────────────────────────────────────────────────┘

Track 4: MCP Server（G9） — mcp-server.md v3.1
┌─────────────────────────────────────────────────────────────┐
│ Phase 1-9: ✅ 完了（3c6e86b on sysdev-1/mcp-server）       │
│   Broker(Unix Socket) + Token管理 + 状態機械               │
│   Tools: memory_search/save, speak/set_expression/notify    │
│   Tools: set/get_anima_state, suppress/resume_narration     │
│   Resources: 6 URI（memories/RM/open_loops/affinity/state） │
│   Auth + Audit + Rate Limiting + DENIED_TOOLS enforcement   │
│   111テスト PASS（107 unit + 4 integration）                │
│                                                              │
│ Phase 10: GUI統合 ✅ 完了（ff8efea on sysdev-1/oribis-orchestrator-p2）│
│   P10-4: narration:speak subscription（useAnima.ts）✅       │
│   P10-5: Worker MCP自動注入（pty_spawn_with_env + ORIBIS_MCP_SOCKET/TOKEN）✅ │
│   P10-6: revoke_by_prefix + token lifecycle テスト追加 ✅    │
│   GUI: mcp_list_tokens / mcp_issue_token / mcp_revoke_token  │
│        + DrawerAnima Settings MCP セクション ✅             │
│   1054テスト PASS                                            │
└─────────────────────────────────────────────────────────────┘

推奨実行順:
  ① G1-e ✅ + G3(UI) ✅ 並列
  ② G1-f
  ③ G1-EL
  ④ G1-g ✅
  ⑤ G1-h ✅
  ⑥ G1-SM ✅
  ⑦ G1-i / G1-j ✅
  ⑧ G1-k ✅
  ⑨ Track 3 + Track 4 Phase 10
```

**並行作業**: バグ修正（TASK-G等）・FBXリターゲット（Producer実施中）はトラックと独立して進行可。

---

### 機能追加

| 優先度 | ID | 内容 | 関連spec | 状態 | 備考 |
|--------|-----|------|----------|------|------|
| HIGH | G5 | compute_sub_context スマートキャッシュ選択 | anima.md §8 | 実装済 | cache.rs + pipeline.rs 接続完了 |
| HIGH | G1 | 4レイヤー記憶システム + 自己進化 | memory.md v3.5 | 実装済 | Phase 1-3完了。G1-a〜G1-k 全タスク完了 |
| HIGH | G1-a | └ SQLite基盤 + oribis-meta パーサー + migration | memory.md §9/§13 | 実装済 | e110c74 (2026-05-05) |
| HIGH | G1-b | └ CLAUDE.md oribis-meta出力指示反映 | memory.md §9.7 | 実装済 | L1(ANIMA.md)+L2(l2.md)に指示追加済 (2026-05-05) |
| HIGH | G1-c | └ Level 1/2 trigger + scheduler配線 | memory.md §7.3 | 実装済 | 8a3c264 (2026-05-06) consolidation.rs+pipeline+scheduler+exit flush |
| MEDIUM | G1-d | └ telemetry（meta欠落率監視）+ テスト | memory.md §9.6 | 実装済 | 0096799 (2026-05-06) MetaStats+3状態パース+22テストPASS |
| HIGH | G1-e | └ L3 4チャネル検索 + ContextMode（context.rs 改修） | memory.md §8 / prompt-layers.md §4 | 実装済 | ContextMode(StatefulSession/StatelessRequest) + SQLite L3 retrieval。codex-adviser PASS (2026-05-07) |
| HIGH | G1-f | └ 忘却曲線 + recency decay | memory.md §4.3/§8.2 | 実装済 | compute_current_strength + on_memory_recalled + recall reinforcement。codex-adviser PASS (2026-05-07) |
| MEDIUM | G1-EL | └ 軽量エンティティリンク | memory.md §8.6 | 実装済 | entity_link.rs + pipeline/consolidation接続。codex-adviser PASS (2026-05-07) |
| HIGH | G1-g | └ Level 2 consolidation | memory.md §7.2 | 実装済 | LLM-based companion + rule-based worker_ops。codex-adviser PASS (2026-05-07) |
| MEDIUM | G1-h | └ relationship_model L3注入 | memory.md §6.2-§6.4 | 実装済 | RM→ProfileItem変換+統合ランキング+即時Boundary/Correction。codex-adviser PASS (2026-05-07) |
| MEDIUM | G1-SM | └ self_model | memory.md §6.5 | 実装済 | b9aaf6d (2026-05-07) evidence蓄積+L3注入+L1 decay/promotion。codex-adviser PASS |
| HIGH | G1-i | └ A-MEM 軽量記憶進化 | memory.md §7.1 | 実装済 | L1でstrengthen/supersede/promote/no-op。codex-adviser PASS (2026-05-07) |
| HIGH | G1-j | └ Operational Memory | memory.md §11 | 実装済 | worker_patterns L1/L2。codex-adviser PASS (2026-05-07) |
| HIGH | G1-k | └ ハイブリッドベクトル検索 | memory.md §10.3 | 実装済 | 423a668。fastembed e5-small 384d + cosine + Phase3ランキング。113テストPASS。codex-adviser PASS (2026-05-07) |
| MEDIUM | G3 | AnimaMode UI↔backend統一 | anima.md §6 | 実装済 | cb9db93 (2026-05-07) フロント off/cache/hybrid/ai → Rust Cache/Ai/Hybrid。codex-reviewer 3回PASS |
| HIGH | G9 | MCP Server（外部Worker/Client接続基盤） | mcp-server.md v3.1 | 一部実装済 | Phase 1-9完了（3c6e86b）。111テストPASS。Phase 10（GUI統合）一部実装（P1 write_event+events/feed） |
| HIGH | WR-P1 | web-remote P1（axum HTTP+WS / api-client.ts / Bearer認証）| spec/ui/web-remote.md | 実装済 | sysdev-1/web-remote-p1。smoke 5/5 PASS / cargo test 1016 PASS（2026-05-13） |
| HIGH | WR-P2 | web-remote P2（WS双方向 / Android CSS / クレート分離）| spec/ui/web-remote.md | 実装済 | sysdev-1/web-remote-p2。cargo test 1022 PASS / pnpm 360 PASS（2026-05-14） |
| MEDIUM | WR-P3 | web-remote P3（HTTPS/WS ストリーミング / PTY / PWA）| spec/ui/web-remote.md | 未着手 | Producer指示待ち |
| HIGH | ORCH-P1 | オーケストレーター P1 | anima-orchestrator-architecture.md | 実装済 | 9タスク完了。types.ts/Rust基盤/narration/MCP統合/Tauriコマンド/フロントエンド5コンポ/App.tsx統合/テスト/Onboarding |
| HIGH | ORCH-P2 | オーケストレーター P2 | anima-orchestrator-architecture.md | 実装済 | 12タスク完了+追加実装。CRUD API/PipelineView+DepartmentLane/OrchestratorEditor 5タブ/PromptsTabセキュリティ/Delete&Rename制御 + DrawerAnima内部タブ(Status/Prompt/Memory/Console/Settings) + Deep Reasoning delegation。vitest 568/cargo test 1036 PASS（2026-05-12） |
| HIGH | ORCH-P3 | オーケストレーター P3 | anima-orchestrator-architecture.md | 実装済 | P3-A: scheduler engine / P3-B: DELEGATE_TO自動ルーティング。commits 6254a02, f7ab1a7（2026-05-12） |
| LOW | G8 | AI応答の軽重モード（一言/詳細 切替） | anima.md | 未着手 | 現状はモデル選択で軽量化のみ。応答自体の簡潔さ制御なし。Producer判断で優先度変更 |

| MEDIUM | — | motion-anim-assign ランタイムマウント | motion-anim-assign.md | 不要 | Animation Editorプラグインで実現済・revert 2b727d4 |

### バグ修正・技術的負債

| 優先度 | ID | 内容 | 関連 | 状態 | 備考 |
|--------|-----|------|------|------|------|
| HIGH | TASK-G | 音声入力 Codex R3 指摘対応 | voice-input.md | 一時停止中 | HIGH×2, MEDIUM×3, LOW×1 |
| MEDIUM | — | ARP→VRM FBXアニメーションリターゲット | issues/fbx/ | 実施中 | 腕完了、脊椎動作中、Producer作業中 |
| MEDIUM | TASK-K | 入力欄に謎テキスト挿入バグ | — | 調査中 | 再現手順の特定待ち |
| LOW | TASK-B | useVoiceInput/useTTS テストTSエラー | voice-input.md | 要確認 | エラー未検出・タスク自体が古い可能性 |
| LOW | TASK-C | PoseDebugUI.tsx リファクタ検討 | — | 要確認 | App.tsxでimport使用中・削除不可 |
| LOW | TASK-E | VrmViewer expression detection 堅牢化 | vrm.md | 未着手 | |
| LOW | TASK-F | カメラ spherical↔OrbitControls 同期 | — | 未着手 | |
| LOW | TASK-J | 左ドロワー push レイアウト | — | 休止中 | R3F ResizeObserver問題 |
| HIGH | — | Force-close後チャット入力スタック | lib.rs, App.tsx | 修正済 | bbd0ec2。session IDクリア+orphan検知+state reset |
| MEDIUM | — | L1/L2プロンプトパス不一致 | context.rs, lib.rs | 修正済 | 786fd8b。_common→orchestrator統一 |

### テスト・品質

| 優先度 | ID | 内容 | 関連 | 状態 | 備考 |
|--------|-----|------|------|------|------|
| MEDIUM | TASK-M | scene プラグイン ユニットテスト追加 | scene-plugin.md | 未着手 | |
| MEDIUM | TASK-N | scene プラグイン Windowsビルド更新 | scene-plugin.md | Producer作業待ち | |
| LOW | TASK-O | scene プラグイン パフォーマンス確認 | scene-plugin.md | 未着手 | TASK-N後 |
| LOW | TASK-P | scene プラグイン 背景グラデーション色制御UI | scene-plugin.md | v2予定 | |
| LOW | TASK-D | FullBodyDebugUI 表情タブのデフォルト値 | — | 未着手 | 任意 |

### 完了済み（直近）

| ID | 内容 | 完了日 |
|----|------|--------|
| G1-a | SQLite記憶基盤 + oribis-meta���ーサー + migration（memory_db.rs, events.rs, parser.rs, pipeline.rs） | 2026-05-05 |
| G5 | compute_sub_context スマートキャッシュ選択（cache.rs + pipeline接続） | 2026-05-05 |
| G0 | CLI adapter 実装（cli_adapters.rs） | 2026-05 |
| G7 | Tauri コマンド公開（anima_chat/anima_state + useAnima接続） | 2026-05 |
| G6 | イベントカウンタ トリガー接続（pipeline increment + context注入） | 2026-05 |
| G2 | ThrottleConfig toml ロード | 2026-05 |
| G4 | Anima pipeline memory_saves 処理 | 2026-05 |
| TASK-H | 会話ログ保存 + タスクペンディング | a67e021〜c8412c5 |
| G1-e | L3 4ch検索 + ContextMode（retrieval/context/pipeline/lib） | 2026-05-07 |
| G1-f | 忘却曲線 + recency decay（compute_current_strength + on_memory_recalled） | 2026-05-07 |
| G1-EL | 軽量エンティティリンク（entity_link.rs + pipeline/consolidation接続） | 2026-05-07 |
| G1-g | Level 2 consolidation（LLM companion + rule-based worker_ops） | 2026-05-07 |
| G1-h | relationship_model L3注入 + 即時Boundary/Correction更新 | 2026-05-07 |
| G1-SM | self_model — AI自己理解 (evidence蓄積+L3 Ch4注入+L1 decay/promotion) | 2026-05-07 |
| G1-i | A-MEM 軽量記憶進化（L1: strengthen/supersede/promote/no-op） | 2026-05-07 |
| G1-j | Operational Memory（worker_patterns L1/L2） | 2026-05-07 |
| G1-k | ハイブリッドベクトル検索（fastembed e5-small + cosine + Phase 3ランキング）423a668 | 2026-05-07 |
| G9 | MCP Server Phase 1-9（Broker+Tools+Resources+Auth+Audit+StateMachine。111テストPASS） | 2026-05-07 |
| G3 | AnimaMode UI↔backend統一（FromStr impl + Tauriコマンド anima_mode配線 + UIトグル3段切替） | 2026-05-07 |
| — | L1/L2プロンプトパス統一（_common→orchestrator + oribis_prompts_dir + テストbase_dir対応）786fd8b | 2026-05-07 |
| — | Force-close後チャット入力スタック修正（session IDクリア + orphan検知 + state reset）bbd0ec2 | 2026-05-07 |
| — | コンテキストテストhome fallback修正（setup_prompts_dir追加）11cf7dc | 2026-05-07 |
| — | GUIテスト全項目PASS（AnimaMode, Prompt編集, Memory E2E, ベクトル検索）393テスト+スクショ確認 | 2026-05-07 |
| ORCH-P1 | オーケストレーターP1 Epic全9タスク完了（types/Rust基盤/narration/MCP統合/Tauri cmd/フロントエンド/App.tsx統合/テスト/Onboarding） | 2026-05-08 |
| ORCH-P2 | オーケストレーターP2 Epic全12タスク完了（CRUD API/PipelineView/DepartmentLane/OrchestratorEditor 5タブ/PromptsTabセキュリティ/Delete&Rename制御。vitest 563/cargo test 955 PASS） | 2026-05-11 |
| ORCH-P2追加 | DrawerAnima内部タブ実装（Status/Prompt/Memory/Console/Settings）+ CSSテーマ対応 + Deep Reasoning delegation + GeneralTab統合。vitest 568/cargo test 1036 PASS（commits c7f224e〜0432867） | 2026-05-12 |
| ORCH-P3 | P3-A scheduler engine + P3-B DELEGATE_TO自動ルーティング（6254a02, f7ab1a7） | 2026-05-12 |
| — | セキュリティ修正: assetProtocol scope/Plugin icon XSS/filepath traversal（071e92b） | 2026-05-12 |
| — | 起動時Anima自動接続: プロジェクト選択後1.2秒で時刻別挨拶自動送信（b6f7e5a） | 2026-05-12 |
| — | open_cli_terminal WSL修正: powershell.exeフルパスフォールバック追加（b87f53d） | 2026-05-12 |
| G9-P10 | MCP Phase 10 GUI統合: Worker token injection + GUI token UI + revoke_by_prefix（ff8efea）| 2026-05-12 |
| WR-P1 | web-remote P1: axum HTTP+WSサーバー / api-client.ts / Bearer認証 / SPA fallback / smoke 5/5 PASS（sysdev-1/web-remote-p1） | 2026-05-13 |
| WR-P2 | web-remote P2: WS双方向dispatch / AndroidタッチCSS / Cargoワークスペース / pnpmワークスペース / Tailscaleガイド（sysdev-1/web-remote-p2, ab5ab99） | 2026-05-14 |
| E2E-FW | シナリオ駆動型E2Eテストフレームワーク（engine 22ファイル + scenarios 6 JSON + bone regression） | 2026-05-08 |
| COM-P0-2 | 配布物クリーン環境テストCI: release.yml artifact validation + smoke-install.yml（Windows MSI/Linux DEB/AppImage）| 2026-05-27 |
| COM-P1-1 | VOICEVOXクレジット表示: About画面にVOICEVOX利用表記+ライセンスリンク追加 | 2026-05-27 |
| COM-P1-2 | コスト警告Settings UI: 閾値カスタマイズUI実装 | 2026-05-27 |
| COM-P1-3 | 自動アップデート軽量版: GitHub Releases API起動時チェック+toast通知（update_check.rs） | 2026-05-27 |
| COM-P1-4 | エラーメッセージi18n: OribisError Serialize→i18nキー化（error.io/internal/network/command/database） | 2026-05-27 |
| COM-P1-5 | ネットワークエラーUX: useNetworkStatus hook + ErrorRetryBanner + invokeWithTimeout | 2026-05-27 |
| chat-mode T1 | App System v2 実行経路確立: usePluginSystem互換/PluginSandbox統合/App.tsxレンダリング/HostAPI堅牢化/テスト792PASS | 2026-05-29 |
| chat-mode T2 | UIRenderer チャット用コンポーネント追加: scrollable-list/message/markdown-text + autoScrollBottom + 7テスト追加/テスト799PASS | 2026-05-29 |
| chat-mode T3 | ai.sendToAnima/sendToDepartment 実動経路確立: Promise/timeout/PTY収集/ai:response単一登録/テスト805PASS | 2026-05-29 |
| chat-mode T4 | チャットモードプラグイン骨格+Animaチャット画面: Enter送信安定化/data-testid対応/TTS表示改善/テスト807PASS | 2026-05-29 |
| chat-mode FIX | builtin plugin discovery fix: plugin_v2_scan結果にBUILTINマニフェストをマージ、enable/disableをローカルstate+storageで永続化 | 2026-05-29 |

---

## spec レジストリ

### spec/core/ — コアシステム

| spec | 概要 | ステータス |
|------|------|-----------|
| overview.md | 概要・設計原則・フェーズ計画 | 設計確定 |
| pipeline.md | 統一応答パイプライン + CLI Adapter | 実装済 |
| anima.md | Anima + AnimaMode + throttle + キャッシュ | 一部実装済 |
| anima-plan.md | 開発計画（GAP管理） | — |
| anima-state.md | AnimaState一覧・カテゴリ | 実装済 |
| anima-orchestrator-architecture.md | オーケストレーター + Worker PTY | 実装済（P1/P2/P3完了） |
| affinity.md | 好感度システム | 実装済 |
| memory.md | 4レイヤー記憶 + 自己進化 + entity linking + self_model | 実装済（Phase 1-3完了、v3.5） |
| event-counter.md | イベントカウンタ | 実装済 |
| session-data.md | 統合履歴 + タスク管理 | 実装済 |
| data-storage.md | データストレージ（db.rs） | 実装済 |
| markers.md | マーカー方式統一仕様 | 実装済 |
| prompt-layers.md | プロンプト三層構造（L1/L2/L3） | 実装済（v1.4: L1/L2正規パス統一） |
| expression-system.md | 表情反映システム | 実装済 |
| cache-generation-prompts.md | キャッシュ生成プロンプト集 | 設計確定 |
| mcp-server.md | MCP Server（外部Worker/Client接続） | 実装済（Phase 1-10完了） |
| architecture-diagrams.md | アーキテクチャ図集 | — |
| test-requirements.md | テスト要件 | — |

### spec/ui/ — UI・フロントエンド機能

| spec | 概要 | ステータス |
|------|------|-----------|
| vrm.md | VRMアバター表示 | 実装済 |
| mmd-model.md | MMDモデル対応 | 実装済 |
| avatar-animation.md | 表情拡張/FBXリターゲット/morphMap | 一部実装済 |
| motion-anim-assign.md | モーション状態別アニメ割り当てUI | 一部実装済 |
| anima-ui.md | Anima統合UI（parser/adapter/cache等） | 実装済 |
| dual-session.md | デュアルセッション（Theater Mode） | 実装済 |
| cli-status-pane.md | CLIステータスペイン | 実装済 |
| output-viewer.md | 出力ビューア | 未着手 |
| scene-plugin.md | シーンプラグイン | 実装済 |
| plugin-api.md | プラグインAPI（v1廃止） | 廃止 |
| app-system-v2.md | App System v2（iframe sandbox + Host API + 宣言的UI） | 一部実装済 |
| theme-system.md | テーマシステム | 実装済 |
| voice-input.md | 音声入力（push-to-talk） | 実装済 |
| web-remote.md | Webリモート（axum + browser UI） | 実装済（P1/P2完了、P3未着手） |
| namedpipe.md | 名前付きパイプ通信 | 実装済 |
| file-attachment.md | ファイル添付 | 実装済 |
| 1mb-warning.md | 1MBコンテキスト警告 | 実装済 |
| autotest.md | 自動テスト | 実装済 |
| android-cprime.md | Android C-prime API | 実装済 |
| unity-fbx-retarget.md | ARP Unity FBX→VRM リターゲット | 一部実装済 |
| windows-installer.md | Windowsインストーラー | 未実装 |
| wsl-build-setup.md | WSLビルド環境セットアップ | — |

### issues/

| issue | 概要 | ステータス |
|-------|------|-----------|
| fbx/retarget-arp-to-vrm.md | ARP→VRM FBXリターゲット修正 | 一部対応済 |

---

## ステータス凡例

| 値 | 意味 |
|----|------|
| 未実装 | 設計書はあるが、コードが一切ない |
| 設計確定 | 設計完了、実装着手前 |
| 一部実装済 | コードはあるが未完成（stub含む、GAP残存） |
| 実装済 | 仕様どおりに動作する。バックログ（LOW）は許容 |
| 廃止 | 仕様が不要になった・別specに統合された |
| — | 進捗管理対象外（リファレンス・計画書等） |
