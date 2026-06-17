# Oribis: Anima オーケストレーターアーキテクチャ設計

> 策定日: 2026-05-03
> 最終更新: 2026-06-17
> ステータス: 一部実装済（P1/P2/P3完了・Action Platform初回リリース対象P1-P16ほぼ完了・shell/network/MCP-write/rollback executor/sidecar実spawn未解禁）

---

## 概要

現行oribisの「プロジェクトタブ = CLIプロセス」構成を刷新し、
**Animaを常駐オーケストレーター・Workerを実行エージェント**とする新アーキテクチャ。

Director（中間管理職）を排除し、Lead Worker パターンで自律運用する。

---

## 現行の課題

1. 起動のたびにCLIプロセスを立ち上げる → フットワークが重い
2. タスク分散時にプロジェクトタブを切り替える必要がある
3. 重い処理中は何も応答しない（ユーザーが暇になる）
4. プロジェクトごとに会話・記憶が分散する

---

## アーキテクチャ

### 役割体系

```
Producer（人間）
  ↓ 意図・指示
Anima（Orchestrator）─── 意図構造化・ルーティング・品質ゲート・ナレーション
  ↓ 構造化されたタスク
Worker（Lead）─── 設計→実装→テスト→レビュー（自律実行）
  └── [Team時] Sub Workers を自ら管理
```

**Director は存在しない。** Lead Worker が技術判断・進捗管理を兼ねる。

### 役割分担

| 役割 | 説明 |
|------|------|
| **Anima** | 常駐 Orchestrator。ユーザーとの会話窓口・Worker の指揮・ナレーション |
| **Worker** | 実タスクを実行する CLI エージェント。Anima の管理下で起動 |
| **Department** | Worker グループの設定単位（名前 + CLI + モデル + 制約 + スケジュール） |

### Anima（Orchestrator）

- **起動方式**: JSON stream（`--output-format stream-json`）
- **常駐**: アプリ起動中は常に起動済み（`animaMode: off` 時はプロセス未起動）
- **idle スリープ**: departments JSON の `idle_timeout` で制御。一定時間操作なしでプロセス休止
- **役割**:
  - ユーザーとの会話
  - 軽いタスクは自ら実行（下記「Anima 直接実行の権限境界」参照）
  - 重いタスク判断 → Worker へ委譲（LLM が自動判断）
  - Worker 作業中のナレーション
  - 品質ゲート（commit/push 確認・smoke test）
  - スケジュール実行（内蔵スケジューラ）
- **モデル**: ユーザーが選択（軽量モデル推奨ガイダンスつき）

#### Anima 直接実行の権限境界

Anima が Worker を介さず自ら実行してよい範囲:

| 許可 | 禁止（Worker 委譲必須） |
|------|------------------------|
| 質問への回答（知識ベース応答） | ファイル作成・編集 |
| 設定値の読み取り・表示 | git 操作（commit/push/branch） |
| Worker ステータス確認 | コード生成・変更 |
| スケジュール ON/OFF 切替 | テスト実行 |
| ナレーション生成 | 外部 API 呼び出し（destructive） |
| 部門設定の GUI 経由変更 | インフラ・デプロイ操作 |

**判定ルール**: 「ファイルシステムやリポジトリに副作用を与える操作」は全て Worker 委譲。Anima は read-only + 会話 + メタ操作のみ。

#### Internal Worker / Action Platform（初回リリース対象P1-P16実装済）

OpenCode代替内製化の最初の実用経路として、既存PTY Workerとは分離した **Internal Worker Job** を追加する。
この経路は「Animaが提案し、ユーザー承認後にread-only toolだけを実行し、結果をAnima説明へ戻す」閉ループである。

**実装済み（2026-06-17 / `integration/action-platform-foundation` commit `b30b2aa`）**:

| 領域 | 実装内容 |
|------|----------|
| Schema/Store | `InternalWorkerJob` / Event / Artifact / ToolCall。`state/internal-worker/jobs.jsonl` と `events/{job_id}.jsonl` にappend-only保存。破損JSONL skip、payload上限、large output artifact spill |
| Runtime | pending→running→completed/failed/cancelled/timeout。read-only built-in toolsのみ許可（echo/context_summary/workspace_search_readonly/file_read_excerpt/git_status_readonly） |
| Anima Dispatch | `anima_propose_dispatch` / `anima_approve_and_run_readonly_dispatch` / reject/list。proposal/job/correlation/approval metadataを追跡 |
| Context Selector | Job/Event/Artifactをbyte/priority上限つきで抽出。artifact excerpt取得対応 |
| Explanation | deterministic `anima_generate_explanation` と `anima_check_proposal_scope`。危険語・confirm/write/shell/network/secret系はscope checkで拒否 |
| Permission/Audit | internal worker Tauri commandsをAction Router評価に通す土台を追加。Anima intentをread-only capabilityへ分類し、FileRead/Audit/Ui以外を拒否 |
| Approval Decision | `approval_decisions.jsonl` に承認判断をappend-only保存。`policyDecision`/`idempotencyKey`必須、idempotency replay、expiry、deny終端化、proposal/workspace不一致key拒否 |
| UI | Jobsタブに `AnimaDispatchPanel` / `TaskJobView` / `ActionAuditPanel` を同居。提案カード→policy判定→承認→read-only実行→Job詳細/Event/Artifact→Anima説明を実GUIで確認 |
| Write Plan Store/API | `internal_worker_write_plan.rs` を追加。write proposal/operationをJSONL保存し、`proposalHash` / `requestFingerprint` / operation fingerprint / idempotency replay / pathScope検証 / secret-like path拒否 / symlink escape拒否を実装 |
| Write Proposal Preview | write適用前の表示専用UIとして `WriteProposalPreview` / `ApprovalBinding` を追加。unified diffを安全表示し、approval hash bindingを可視化する。実write/applyボタンは出さない |
| Write Diff Proposal UI | `internal_worker_create_write_diff_proposal` で実WritePlanを生成し、`WriteDiffProposalView` + `writePlanAdapter` でpreview/bindingへ配線する。`internal_worker_get_write_plan` で同一planをread-only再読込できる |
| Safe Apply | single-operation `createFile` / `updateFile` のみapply可能。approval binding、operationId keyed expected hash、構造化beforeHash/currentHash、TOCTOU再検証、secret/redacted/spilled拒否を必須にする |
| Rollback Proposal | rollback executorは作らず、Archived applied planから逆方向WritePlan proposalを生成し、通常のpreview/approval/apply境界へ戻す |
| Router Enforcement | `plugin_*` と `internal_worker_apply_write_plan` のdirect dangerous invokeをHostAPI経由で拒否し、危険操作をRouter/policy/audit境界へ寄せる |
| Self-Improvement Lite | Anima memory DBとは分離したSQLite storeにObservation/Evaluation/Suggestion/Decisionを保存。Worker JobからObservationを生成し、採否は記録のみで自動適用しない |

**安全境界**:

- 実writeはsingle-operation `createFile` / `updateFile` に限定する。shell / network / MCP write / multi-operation applyは実行しない
- rollbackはexecutorではなく逆方向WritePlan proposalとして生成し、同じpreview / approval / apply境界を通す
- 既存PTY Worker / TaskQueue / `list_tasks` / `cancel_task` とは混ぜない
- `workerProviderMode` は `useAnima` をデフォルトにし、オンボード済みAnima ProviderをWorker側でも参照できる
- credentialRefやsecret値はJob/Event/Artifact/UIに平文保存・表示しない
- UIはbackend生errorを表示せず、汎用エラー文言に丸める
- backendは `policyDecision` 未指定を拒否し、UI fail-closedをTauri直呼びで迂回できないようにする
- deny/expiredはproposalを終端状態にし、同じproposalの後続承認を防ぐ
- idempotency replayは同一proposal + 同一workspaceの既存approved decisionに限定し、異なるproposal/workspaceでは拒否する
- write plan idempotency replayは同一request fingerprint / operation fingerprintに限定し、同じkeyでも内容が異なる場合は拒否する
- write planのpathScopeはworkspace配下に正規化し、absolute path、`..`、scope外path、secret-like path、既存symlink escapeを拒否する
- write diff proposal生成UIは `internal_worker_create_write_diff_proposal` と `internal_worker_get_write_plan` のみ呼び出す。apply/write/execute/commitボタンやinvokeは置かない
- approval hash bindingは表示専用。write適用を有効化する前にapproval decisionと`proposalHash`/`requestFingerprint`のbinding、apply直前TOCTOU再検証、operation種別別検証、承認後append禁止またはrevision hash設計が必要
- Event/Artifactのapproval snapshotにはpolicyDecision/riskLevel/idempotencyKey/expiresAt/approvalDecisionIdを含め、Job metadataと監査情報を揃える
- Self-Improvementは観測・評価・提案・採否記録まで。Oribis本体コード、prompt、権限、Worker policyの自動適用は禁止
- WDIO実行時、別worktreeのVite dev serverを誤再利用しないよう `scripts/run-wdio-tests.sh` でport所有プロセスのcwdを確認する

**テスト結果（初回リリース対象仕上げ / 2026-06-17）**:

- `pnpm run typecheck`: PASS
- `pnpm vitest run`: 1153 PASS / 3 skipped
- `cargo test --manifest-path src-tauri/Cargo.toml internal_worker_write_plan`: 91 PASS
- `cargo check --manifest-path src-tauri/Cargo.toml --no-default-features --features tauri-backend`: PASS
- WDIO: `app-launch` 5 PASS、`write-plan-apply` 3 PASS、`write-diff-proposal` 3 PASS、`action-platform` 5 PASS。`sidecar-preflight` はspec PASSだが1 skipped（マウント条件未成立）

**未実装（後続Phase）**:

- fs write / git write / shell exec / MCP write
- rollback executor
- sidecar/WASM plugin runtimeの実起動
- exe hash/署名検証、OS sandbox
- artifact integrityの本番運用強化

### Worker

- **起動方式**: **PTY（ConPTY on Windows）** ← 重要
- **表示**: 下部パネル（トグル表示/非表示）に xterm.js で表示
- **双方向**: ユーザーが xterm.js から直接入力可能
- **フォルダ**: departments JSON の `working_dir` から決定
- **複数起動**: 部門ごとに `max_workers` 数まで並列起動可能
- **実行モード**:
  - **Parallel Solo**: 複数の独立タスクを別々の Worker が同時実行（デフォルト）
  - **Lead Team**: 1 つの大タスクを Lead Worker が分割し、サブ Worker に委譲して並列実行
- **品質パイプライン（Workflow）**: タイプ別に異なる（下記「Worker 内部品質パイプライン」参照）

### Worker 並列モデル

部門ごとに最大 `max_workers` 台の Worker を同時稼働させられる。

#### Parallel Solo（独立並列）

```
Anima
  ├── Task A → SysDev Worker #1 (Solo)
  ├── Task B → SysDev Worker #2 (Solo)
  └── Task C → SysDev Worker #3 (Solo)  ← max_workers: 3 が上限
```

- **発動条件**: Anima が同一部門に複数タスクをルーティングした場合
- **各 Worker は独立**: 互いの成果物に干渉しない（別ブランチ or 別ディレクトリ）
- **完了順不同**: 先に終わった Worker から順に品質ゲートへ進む

#### Lead Team（協調並列）

```
Anima
  └── Big Task → SysDev Worker #1 (Lead)
                    ├── Sub-task X → SysDev Worker #2 (worktree: .worktrees/task-x)
                    └── Sub-task Y → SysDev Worker #3 (worktree: .worktrees/task-y)
```

- **発動条件**: Anima が「大規模タスク」と判断し `mode: "lead"` で起動した場合
- **Lead Worker が指揮**: タスク分割・サブ Worker spawn・結果統合を自ら行う
- **Anima は Lead にのみ通信**: サブ Worker の管理は Lead の責務

#### ワークスペース隔離戦略

並列 Worker が同一リポジトリで作業する場合の衝突防止:

| モード | 隔離方式 | ブランチ命名 |
|--------|---------|-------------|
| Parallel Solo | `git worktree add` で Worker ごとに独立 worktree | `worker/{dept}-{worker-id}/{task-slug}` |
| Lead Team | Lead = メイン worktree、サブ = `git worktree add` | `worker/{dept}-lead/{task-slug}`, `worker/{dept}-sub-{n}/{sub-task-slug}` |

**規約**:
- Worker spawn 時に Oribis が自動で worktree 作成（`{working_dir}/.worktrees/{worker-id}/`）
- Worker 完了時に Lead（または Anima）がマージ判断 → fast-forward or squash merge
- マージ競合発生時: Lead が解決を試行 → 失敗なら Anima 経由でユーザーに通知
- Worker 異常終了時: worktree をそのまま保持（デバッグ用）。ユーザーが手動削除 or GUI から cleanup
- `max_workers: 1` の部門は worktree 不要（メイン worktree で直接作業）

#### Worker スロット管理

| 状態 | 意味 |
|------|------|
| `idle` | 空きスロット（新タスク受付可能） |
| `running` | タスク実行中 |
| `waiting` | 品質ゲート待ち / ユーザー確認待ち |

Anima のルーティング判断:
1. タスク受信 → 部門選定（capabilities + priority）
2. 選定部門の Worker スロット確認
3. **空きあり** → 新 Worker spawn（PTY 起動）
4. **空きなし** → キューに追加（FIFO）。先行 Worker 完了時に自動 dequeue
5. **Lead 判定**: タスクサイズ大 + `mode: "lead"` 設定 → Lead Worker として起動し残りスロットをサブ用に確保

#### キュー溢れ時の挙動

```
max_workers: 3 で全スロット使用中 → 4つ目のタスクはキュー待ち
  → Worker #2 完了 → キューから dequeue → Worker #2 スロットに新タスク spawn
```

- キュー上限: 部門ごとに `max_queue`（デフォルト 10、将来スキーマ追加）
- キュー溢れ: Anima がユーザーに「部門が混雑中」と通知

### Worker 内部品質パイプライン（Workflow）

エージェントチェーン（AC: Agent Chain）。Worker が内部的に従う品質工程。
各フェーズは内部サブエージェント（`roles/worker/agents/` で定義）が担当する:

| タイプ | フェーズ（担当エージェント） |
|--------|---------|
| feature | planner（設計） → DA（設計ゲート） → tdd-guide（実装） → code-reviewer（レビュー） → DA（最終ゲート） |
| bugfix | planner（原因分析） → tdd-guide（実装） → code-reviewer（レビュー） → DA（最終ゲート） |
| refactor | architect（設計） → DA（設計ゲート） → tdd-guide（実装） → code-reviewer（レビュー） → DA（最終ゲート） |
| security | security-reviewer（事前監査） → architect（設計） → DA（設計ゲート） → tdd-guide（実装） → security-reviewer（事後監査） → DA（最終ゲート） |

departments JSON の `quality_gate` で各ゲートの有効/無効を部門ごとに制御。
`design_gate: false` の場合、DA設計ゲートフェーズをスキップ。`final_gate: false` の場合、DA最終ゲートをスキップ。

---

## 設定ファイル構成（`~/.oribis/`）

全設定・データを `~/.oribis/` に一元化する（XDG `~/.config/oribis/` は廃止予定）。
`dirs::home_dir().join(".oribis")` でクロスプラットフォーム対応（Linux/macOS/Windows）。

```
~/.oribis/
  departments/                  ← インスタンス定義（JSON）— Single Source of Truth
    _schema.json                   JSON Schema（バリデーション + GUI ツールチップ）
    anima.json                     Orchestrator 設定
    sysdev.json                    部門: System Development
    afd.json                       部門: Game Development
    advisor.json                   部門: Advisor（レビュー専門）
    research.json                  部門: Research（調査専門）
  roles/                        ← 役割テンプレート（Markdown）— AI 向け行動ルール
    _common/
      prompts/
        l2.md                      ★ L2: 全ロール共通の毎ターン注入（実装済み）
      skills/                      全ロール共通スキル
    orchestrator/
      rulebook.md                  Orchestrator 行動ルール
      prompts/
        ANIMA.md                   ★ L1: Animaシステムプロンプト（実装済み）
      skills/                      Orchestrator 固有スキル
    worker/
      rulebook.md                  Worker 行動ルール
      prompts/
        WORKER.md                  L1: Worker システムプロンプト（将来）
      workflows/                   品質パイプライン定義（feature/bugfix/refactor/security）
      agents/                      サブエージェント定義（planner/architect/tdd-guide/code-reviewer/security-reviewer/da）
      skills/                      Worker 固有スキル
  logs/                           ← セッションログ（実装済み）
  state/                          ← ランタイム状態（将来移行予定）
    anima/                        memories.json, affinity.json, event_counters.json, etc.
    projects/                      session ID, anima-cache
  config/                         ← アプリ設定（将来移行予定）
    projects.json                  プロジェクト定義
    config.toml                    アプリ設定
    project-templates.json         テンプレート
  plugins/                        ← プラグイン（将来移行予定）
```

### 移行状況

| 項目 | 旧パス | 新パス | 状態 |
|------|--------|--------|------|
| L1 (Anima) | `{project.path}/.charactor/CHARACTOR.md` | `~/.oribis/roles/orchestrator/prompts/ANIMA.md` | ★ 実装済み |
| L2 (共通) | `~/.config/oribis/projects/{id}/l2_prompt.txt` | `~/.oribis/roles/orchestrator/prompts/l2.md` | ★ 実装済み |
| ログ | — | `~/.oribis/logs/` | 実装済み（元々ここ） |
| anima状態 | `~/.config/oribis/anima/` | `~/.oribis/state/anima/` | 未移行 |
| projects.json | `~/.config/oribis/projects.json` | — | 移行不要（新規departments/で運用開始） |
| plugins | `~/.config/oribis/plugins/` | `~/.oribis/plugins/` | 未移行 |
| session ID | `~/.config/oribis/projects/{id}/.last_*` | `~/.oribis/state/projects/{id}/` | 未移行 |

### departments と roles の責務分離

| 項目 | departments/*.json | roles/*.md |
|------|-------------------|-----------|
| 役割 | ランタイム設定（何をどう起動するか） | 行動原則（起動後どう振る舞うか） |
| 形式 | JSON（GUI + AI が読み書き） | Markdown（AI が読む） |
| 正 | constraints / skills / model 等の設定値はここが正 | 具体的設定値を書かない |
| 編集 | GUI + AI | AI のみ（原則変更時） |

### プロンプトレイヤー

| レイヤー | 内容 | 格納場所 |
|---------|------|---------|
| L1 | システムプロンプト（キャラクター定義） | `roles/orchestrator/prompts/ANIMA.md`（Anima用）/ `roles/worker/prompts/WORKER.md`（Worker用） |
| L2 | 毎ターン固定注入（マーカールール等） | `roles/orchestrator/prompts/l2.md` |
| L3 | 動的注入（好感度・時刻・タスク・記憶） | ランタイム生成（context.rs） |

### スケジューラ

- **Oribis 内蔵**（Tauri + tokio::time）。OS 非依存（Windows 対応）。Linux cron 不使用。
- departments JSON の `schedule` フィールドで定義
- 間隔指定: `"every 6h"`, `"every 1d at 09:00"`, `"every monday 09:00"`
- GUI からトグル ON/OFF 可能

---

## UI 設計

### 全体レイアウト

3D Avatar 全面表示を維持しつつ、左ドロワー + 下部 PTY パネルで操作する構成。

```
[PTY非表示時（デフォルト）]
┌──────────────┬───────────────────────────┐
│ 左ドロワー    │  3D Avatar（全面）         │
│ （監視・操作） │  + Anima吹き出し overlay  │
│              │                            │
│ Anima ●idle  │                            │
│ ├ History    │                            │
│ ├ Prompt     │                            │
│ └ Memory     │                            │
│              │                            │
│ Dept: SysDev │                            │
│ ├ Worker#1 ● │                            │
│ ├ Worker#2 ○ │ [チャット入力]     [Send][🎤]│
│ └ [+]        │                            │
│              │                            │
│ Event Feed   │                            │
│ 14:23 SysDev#1│                            │
│  test 23/23 ✓│                            │
│ 14:22 AFD#1  │                            │
│  build error!│                            │
│ [Edit]→全画面│ ⚙Settings  [▲PTY]         │
└──────────────┴───────────────────────────┘

[PTY表示時]
┌──────────────┬───────────────────────────┐
│ 左ドロワー    │  3D Avatar + Anima（上部） │
│              │  （縮小するが常時表示）     │
│ Anima ●idle  ├───────────────────────────┤
│ ├ History    │  Worker PTY（下部パネル）   │
│ ├ Prompt     │  [#1 ●][#2 ●][#3 ○] [▼]   │
│ └ Memory     │  $ pnpm test               │
│              │  PASS 23/23 █             │
│ Dept: SysDev │  ↕ 高さドラッグ調整        │
│ ├ Worker#1 ● │                            │
│ ├ Worker#2 ○ │ [チャット入力]     [Send][🎤]│
│ └ [+]        │                            │
│              │                            │
│ Event Feed   │                            │
│ 14:23 SysDev#1│                            │
│  test 23/23 ✓│                            │
│ [Edit]→全画面│ ⚙Settings                 │
└──────────────┴───────────────────────────┘
```

### 左ドロワー（監視・ナビゲーション用）

現行の6タブ（Project / Log / Console / Tasks / Memory / Prompt）を廃止し、
エンティティベースの構成に再編。コンパクトな監視・操作パネル。

#### Anima セクション

| 項目 | 内容 |
|------|------|
| ステータス | モデル名・状態（idle/active）表示 |
| History | Anima との会話履歴閲覧 |
| Prompt | ANIMA.md / l2.md / AnimaCache 編集 |
| Memory | Anima の記憶ビューア |

#### Department / Worker セクション

| 項目 | 内容 |
|------|------|
| Department ドロップダウン | 部門切替 |
| Worker 一覧 | 状態アイコン（●実行中 / ○idle / ✕終了 / ⏳キュー待ち） |
| Worker 選択 | クリックで下部 PTY パネルに反映 |
| Worker 内 Prompt | Worker 固有プロンプト編集 |
| Worker 内 Memory | Worker 固有記憶ビューア |
| [+] ボタン | Worker 手動 spawn |
| [Edit] ボタン | Orchestrator Editor（全画面）起動 |

### 下部 PTY パネル

Worker の PTY（xterm.js）を表示するパネル。VS Code のターミナルパネルと同じ操作感。

| 項目 | 内容 |
|------|------|
| 表示/非表示 | トグルボタンまたはキーボードショートカット（例: Ctrl+`）で切替 |
| デフォルト | 非表示（3D Avatar 全面表示） |
| 幅 | メインエリアのフル幅（80列以上確保） |
| 高さ | ドラッグで調整可能。最小化で 3D 全面復帰 |
| Worker 切替 | タブクリックで即切替（display:none 方式、再接続不要） |
| 双方向入力 | ユーザーが PTY から直接入力可能 |
| 独立動作 | **Orchestrator 未起動でも PTY 操作・切替可能** |

#### PTY 切替の実装方式

- 各 Worker の xterm.js インスタンスは DOM に保持（`display:none` 切替）
- Worker タブクリックで即座に表示切替（PTY プロセスは常時 alive）
- キーボードショートカット対応（例: Ctrl+1/2/3 で Worker 切替）

### 3D + Anima（上部メインエリア）

| 項目 | 内容 |
|------|------|
| 3D Avatar | 常時表示（PTY 表示中も上部に残る・縮小するが消えない） |
| Anima 吹き出し | オーバーレイ方式維持（右ペイン分割しない） |
| Debug/Perf UI | 現行維持（左サイドバー折りたたみ） |

### Settings（歯車ボタン）

現行の Settings 画面をそのまま維持（別パネル表示）。アプリ全体設定用。

### 現行タブからの移行マッピング

| 現行タブ | 移行先 |
|----------|--------|
| Project | 廃止 → Department/Worker 管理に置換 |
| Log | 廃止 → Worker PTY 出力に統合 |
| Console | 廃止 → Worker PTY に置換（読み取り専用 → 双方向化） |
| Tasks | Workers 内のキュー表示に統合 |
| Memory | Anima/Worker 各エンティティ内に移動 |
| Prompt | Anima/Worker 各エンティティ内に移動 |

---

## Orchestrator エディター UI

部門管理・パイプライン可視化・スケジュール管理を行う**全画面専用画面**。
左ドロワーの [Edit] ボタンから起動。現行 Settings と同じ方式で表示（メイン画面を非表示）。

### レイアウト: レーンパイプライン

```
┌─────────────────────────────────────────────────────┐
│  Anima (Orchestrator)                               │
│  ┌────────────────────────────────────────────────┐ │
│  │ model: haiku │ status: idle │ [Configure]      │ │
│  └────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────┤
│  Workers                                            │
│                                                     │
│  SysDev  ━[Design]━━[Impl]━━[Review]━━[DA]━━ ✓     │
│  AFD     ━[Design]━━[Impl]━━[Review]━━[DA]━━ ✓     │
│  Advisor ━━━━━━━━━━━[Review]━━━━━━━━━━━━━━━━ ✓     │
│  Research ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ ✓     │
│                                                     │
│  [+ Add Department]                                 │
├─────────────────────────────────────────────────────┤
│  ▼ SysDev (selected)                               │
│                                                     │
│  [General] [Workflow] [Schedule] [Skills] [Prompts] │
│                                                     │
│  Model: claude-sonnet-4-6       Mode: Solo / Lead   │
│  Review: cross-model (opus)     Smoke: pnpm tsc..   │
│  Constraints: 3 rules                    [Edit]     │
└─────────────────────────────────────────────────────┘
```

### UI 構成要素

| エリア | 内容 |
|--------|------|
| 上部 | Anima ステータス + 設定リンク |
| 中央 | 部門レーン（横パイプライン）— 各部門のワークフローステージと現在地を可視化 |
| 下部 | 選択部門の詳細パネル（タブ切替: General / Workflow / Schedule / Skills / Prompts） |

### 詳細パネル タブ

| タブ | 表示・編集内容 |
|------|--------------|
| General | model, cli, working_dir, mode, max_workers, constraints, env, tags |
| Workflow | quality_gate 設定、review mode、パイプラインステージ ON/OFF |
| Schedule | 定期実行タスク一覧、enabled トグル、last_run/last_result 表示、新規追加 |
| Skills | 有効スキル一覧、スキル追加/削除、スキル実体プレビュー |
| Prompts | instructions 一覧、プロンプトファイルプレビュー/編集 |

### 設計判断

- **全画面専用画面**: 420px ドロワーでは Department 設定の編集が困難。フル幅でレーンパイプライン表示・直感的な編集を実現
- **ドロワーとの分離**: ドロワーは監視・ナビゲーション用（コンパクト）、エディターは設定用（フル幅）
- **ノードエディタは不採用**: トポロジーが固定（Input → Orchestrator → Worker → Gate → Done）のため自由接続は不要。レーンパイプラインで十分
- **全設定 GUI 編集可能**: departments JSON が Single Source of Truth、GUI が直接読み書き
- **AI 編集対応**: `_schema.json` を参照させれば AI も正確に JSON を編集できる。コメント消失問題なし（JSON 形式）
- **将来拡張**: ノードエディタは Lead Mode のタスク分割フロー設計時にサブビューとして追加可能

---

## Worker 増減の操作フロー

| 操作 | トリガー | 結果 |
|------|---------|------|
| 自動 spawn | Anima がタスクをルーティング | 空きスロットに新 Worker タブ出現 |
| 手動 spawn | ユーザーが「Worker追加して」or UI の [+] ボタン | 新 Worker タブ出現（タスク未割当） |
| 自動終了 | Worker がタスク完了 + 品質ゲート PASS | タブが ✕ 表示 → 一定時間後に自動削除 |
| 手動停止 | ユーザーがタブの [×] or 「止めて」 | Worker に SIGTERM → タブ削除 |
| Lead 展開 | Lead Worker がサブ spawn | サブ Worker タブが追加出現（Lead のインデント付き表示） |

---

## イベントフィード + Animaナレーション

### 概要

Worker の全活動イベントを **イベントフィード** としてUIに時系列表示する。
Anima はフィードを定期的にバッチ取得し、**重要な情報を選別して読み上げる**。
（仕組みとしては AITuber のコメント読み上げに近いが、選別基準は「重要度」。）

### イベントフィード（全件表示）

全 Worker のフックイベントを時系列で UI に表示するログストリーム。
読み上げ有無にかかわらず **全イベントを表示** する。

#### イベント種別

| イベント | 発火条件 | 優先度 |
|---------|---------|--------|
| `session_start` | Worker 起動時 | MEDIUM |
| `session_stop` (success) | Worker 正常完了時 | HIGH |
| `session_stop` (error) | Worker 異常終了時 | HIGH |
| `post_tool_use` (error) | ツール失敗時 | HIGH |
| `test_result` | テスト完了時 | MEDIUM |
| `pre_tool_use` (bash/edit/write) | ツール実行直前 | LOW |
| `file_change` | ファイル作成・編集時 | LOW |
| `git_operation` | commit/push/branch 等 | MEDIUM |

#### イベント形式（JSONL）

各 Worker のフックスクリプトが JSONL ファイルに書き出す。**1 Worker = 1 ファイル**（atomic append の OS 依存を回避）。
Oribis がファイル監視で各ファイルを読み取り、マージしてイベントフィードに統合する。

**ファイルパス**: `~/.oribis/state/events/{department}-{worker-id}.jsonl`

**スキーマ**:

| フィールド | 型 | 必須 | 説明 |
|-----------|---|------|------|
| `id` | string (ULID) | ✅ | グローバル一意ID（重複排除用） |
| `seq` | u64 | ✅ | Worker 内連番（順序保証用） |
| `ts` | ISO 8601 | ✅ | タイムスタンプ |
| `department` | string | ✅ | 部門名 |
| `worker` | string | ✅ | Worker ID（例: `SysDev#1`） |
| `session_id` | string | ✅ | Worker セッション ID |
| `event` | string | ✅ | イベント種別（上表参照） |
| `summary` | string | ✅ | 人間可読な要約テキスト |
| `priority` | "high"/"medium"/"low" | ✅ | 優先度 |
| `source_cli` | string | ✅ | CLI 種別（`claude`/`codex`/`openclaw`/`opencode`） |
| `dedupe_key` | string | ❌ | 重複排除キー（同種イベントの集約用。例: `test_result:cargo` ） |
| `payload` | object | ❌ | イベント固有の詳細データ |

```jsonl
{"id":"01J5X...","seq":1,"ts":"2026-05-07T14:23:01Z","department":"SysDev","worker":"SysDev#1","session_id":"abc123","event":"test_result","summary":"cargo test: 23/23 PASS","priority":"medium","source_cli":"claude","dedupe_key":"test_result:cargo","payload":{"passed":23,"failed":0}}
{"id":"01J5X...","seq":5,"ts":"2026-05-07T14:23:15Z","department":"SysDev","worker":"SysDev#2","session_id":"def456","event":"post_tool_use","summary":"pnpm build failed: ENOENT","priority":"high","source_cli":"claude","payload":{"tool":"bash","exit_code":1}}
{"id":"01J5X...","seq":12,"ts":"2026-05-07T14:24:00Z","department":"AFD","worker":"AFD#1","session_id":"ghi789","event":"session_stop","summary":"FEAT-12 実装完了","priority":"high","source_cli":"codex"}
```

#### UI 表示位置

左ドロワーに **Event Feed** セクションとして表示（Worker 一覧の下）。
スクロール可能なタイムラインで、優先度に応じた色分け表示。

| 優先度 | 表示 |
|--------|------|
| HIGH | 赤/オレンジ強調 + アイコン |
| MEDIUM | 通常表示 |
| LOW | グレー・コンパクト表示 |

### Anima ナレーション（選別読み上げ）

Anima がイベントフィードを定期的にバッチ取得し、読み上げるイベントを **自ら選別** する。

#### 動作フロー

```
Worker hooks → 1 Worker 1 JSONL ファイル書き出し
  → Oribis ファイル監視 → マージ → イベントフィード（UI 全件表示）
  → narration.rs がバッチ取得（既読カーソル管理）
  → coalescing + dedupe → LLM が「何を話すか」を選別
  → Speech Queue → TTS 再生
```

#### バッチ処理（既読カーソル管理）

narration.rs が `batch_interval_sec` ごとにイベントフィードを取得する。
**既読位置を永続化** し、再起動時に未処理イベントから再開する。

| 項目 | 仕様 |
|------|------|
| カーソル形式 | `last_event_id`（ULID。各 Worker の最終処理済みイベント ID） |
| 永続化先 | `~/.oribis/state/narration_cursor.json` |
| バッチ範囲 | カーソル以降の全未処理イベント（バッチサイズ上限: 100件） |
| 再起動時 | カーソルファイルから復元 → 未処理分から再開 |
| カーソル不在時 | 直近 5 分間のイベントのみ取得（古いイベントは無視） |

#### 選別ルール（coalescing + dedupe）

バッチ取得後、LLM に渡す前に **前処理** で圧縮する。

**Coalescing（同種イベント集約）**:
- 同一 `dedupe_key` のイベントは1件に集約（例: `test_result:cargo` × 10件 → 「cargo test 10回実行、全PASS」）
- 同一 Worker の同種 error は1件にまとめ（例: `pnpm build failed` × 3回 → 「SysDev#2 で pnpm build が3回連続失敗」）
- 集約後のサマリーをLLMに渡す

**LLM 選別**:

| 優先度 | Anima の扱い |
|--------|-------------|
| HIGH（完了・エラー） | **必ず読む**（スキップ不可。ただし coalescing 後の集約済み1件として） |
| MEDIUM（テスト・git） | 余裕があれば読む（Anima の裁量） |
| LOW（ファイル編集等） | 基本スキップ（重要な文脈がある場合のみ） |

**HIGH 同時多発時**: coalescing で件数を圧縮した上で、freshness（新しい順）で上位 N 件を選別。残りは次バッチに繰り越し。

#### 複数 Worker 同時稼働時

- **「Anima の口は1つ」原則**: ナレーションキューは Anima 全体で1本（Worker 横断）
- Anima は複数 Worker のイベントを横断的に把握し、要約できる
  - 例:「SysDev のテスト通ったけど、AFD 側でビルドエラー出てるみたい」

#### Speech Queue（TTS キュー管理）

backend 側（narration.rs）に **単一 Speech Queue** を配置。
既存 useAnima.ts の greeting/tool/error/lewd 発話も同じキューに統合し、発話競合を防止する。

| 項目 | 仕様 |
|------|------|
| キュー方式 | 優先度付きキュー（priority queue） |
| 最大キュー長 | 5 件 |
| 溢れ時の処理 | LOW → 先に破棄、MEDIUM → coalesce して1件に圧縮、HIGH → 予約スロット確保（常に1枠をHIGH専用に確保） |
| 再生方式 | キューから1件ずつ TTS 再生（再生中の新規は待機） |
| 有効期限 | キュー内イベントは 120秒 で expire（古いイベントは自動破棄） |
| 既存発話との統合 | greeting/tool_start/error/lewd → 同一 Speech Queue に HIGH として投入 |

#### ナレーション発話制御

- `animaMode="off"` 時: ナレーション停止（イベントフィードUI表示は継続）
- departments JSON `narration.enabled`: 部門ごとの読み上げ ON/OFF
- departments JSON `narration.batch_interval_sec`: バッチ取得間隔（デフォルト 30秒）
- Settings `workerNarration: boolean`: グローバルトグル（デフォルト ON）

---

## MCP サーバー統合（Worker 協調 + ナレーション）

既存の Oribis MCP サーバー（Phase 1-9 実装済み・111テスト PASS、spec: `spec/core/mcp-server.md`）との統合。
MCP は **制御チャネル（Anima 状態操作）** と **Worker 間協調バス（イベント読み取り・協調イベント書き込み）** の2軸で活用する。

### 設計原則

- **MCP = 制御 + 協調**: 既存ツール（suppress/resume/state）は制御面。新規の events/feed リソースは Worker 間協調バス
- **書き込みはデュアルパス**: 協調イベント（work_claim, test_result 等）は MCP `write_event` 推奨。網羅的なログは CLI hooks → JSONL
- **読み取りは MCP コアパス**: `oribis://events/feed` は P1 コア。Worker が他 Worker のイベントを pull で取得
- **narration.rs は Rust 直呼び**: 同一プロセス内の event_feed.rs を直接呼ぶ（MCP 不経由）
- **Worker 直接発話（speak）は凍結**: ナレーションに一本化

### 統合アーキテクチャ

```
Worker (Claude Code / Codex / OpenCode)
  │
  ├─[協調イベント]─→ MCP write_event → event_feed.rs ─┐
  │                                                     ├→ Event Feed（統合ストア）
  └─[網羅ログ]─→ CLI hooks → JSONL → event_feed.rs ───┘        │
                                                          ├→ UI（Tauri event → DrawerEventFeed.tsx）
                                                          ├→ narration.rs（Rust 直呼び → LLM 選別 → Speech Queue → TTS）
                                                          └→ MCP resource oribis://events/feed（Worker 間協調読み取り）
```

### 既存 MCP ツール変更（P1 で修正）

| ツール | 現行動作 | P1 変更 |
|--------|---------|---------|
| `speak` (avatar.rs) | Tauri event 直接発火 | **P1 では凍結**（ナレーション一本化） |
| `suppress_narration` (anima.rs) | BrokerState に suppressed フラグ設定 | **変更なし**（narration.rs が BrokerState を参照） |
| `resume_narration` (anima.rs) | BrokerState の suppressed フラグ解除 | **変更なし** |

### MCP ツール（P1 で追加）

| ツール | パラメータ | 説明 |
|--------|----------|------|
| `write_event` | `event: string, summary: string, priority?: string, files?: string[], payload?: object` | **協調イベントの構造化書き込み**。`department`, `worker`, `session_id`, `source_cli` は MCP セッション情報から自動付与。event_feed.rs に直接投入。監査ログ記録 |

### MCP リソース（P1 で追加）

| URI | 説明 |
|-----|------|
| `oribis://events/feed?limit=N&since=ID&types=T&department=D&exclude_self=bool` | **Worker 間協調バス（P1 コアパス）**。Worker が他 Worker のイベントを pull で取得。`limit` デフォルト 50、`since` で既読カーソル指定、`types` でイベント型フィルタ、`exclude_self=true`（デフォルト）で自己イベント除外 |

### Worker 協調モデル

#### シングル / マルチ切替（読み取り側のみ）

**書き込みは常に全イベント型を出力**（モード切替の複雑さを回避）。切替は読み取り側だけ:

| モード | 条件 | 書き込み | 読み取り |
|--------|------|---------|---------|
| **シングル** | 稼働 Worker = 1 | 全イベント型を書く | Worker は events/feed を pull しない（不要）。narration.rs は常時読み取り |
| **マルチ** | 稼働 Worker ≥ 2 | 全イベント型を書く | Worker が events/feed を pull して協調。narration.rs も常時読み取り |

**途中参加対応**: Worker B が途中参加しても、Worker A の過去の work_claim が全て残っているため、ファイル競合を即座に検知可能。書き込み側の切替が不要なので状態遷移の問題なし

書き込みコスト: Worker 1台でも協調イベントが JSONL に数行追加されるだけ（微小）

#### 協調イベント型（P1 スコープ）

| イベント型 | 内容 | 主な用途 |
|-----------|------|---------|
| `work_claim` | 「このファイル/領域を作業中」宣言 | **ファイル競合回避**（最重要） |
| `work_release` | claim 解放 | 作業完了通知 |
| `file_change` | 変更したファイル一覧 | 他 Worker の変更把握 |
| `test_result` | テスト実行結果（pass/fail/scope） | 重複テスト回避・ナレーション |
| `build_result` | ビルド結果（success/fail/error） | ビルド状況共有・ナレーション |
| `error_signature` | エラーフィンガープリント | 同一エラー再発防止 |
| `session_progress` | started / blocked / completed | 進捗可視化・ナレーション |
| `handoff` | Lead ↔ Sub Worker 引継ぎ | チーム制御 |

※全 tool call の詳細や生ログは協調イベントに含めない。低レベル情報は JSONL hooks で網羅

#### 読み取りモデル（pull 方式）

Worker は `oribis://events/feed?since=<cursor>` で定期 pull:

| Worker 種別 | pull タイミング | 推奨間隔 |
|------------|----------------|---------|
| Lead Worker | 高頻度 | 10-30秒 |
| Sub Worker | タスク境界（編集前・テスト前・完了時） | オンデマンド |
| Solo Worker | 並列作業時のみ | 30-60秒 |

※シングルモード時は協調目的の pull 自体が不要（ナレーション用は narration.rs が Rust 直呼びで取得）

#### リスク緩和

| リスク | 対策 |
|-------|------|
| ノイズ（全員の全イベントで埋もれる） | `types` フィルタ + `department` フィルタ + `since` カーソル |
| 自己参照ループ（自分のイベントで判断が汚れる） | `exclude_self=true` デフォルト |
| 協調スラッシング（互いに反応しすぎる） | `work_claim` を最重要、他は参考情報 |
| 古い情報で誤判断 | claim TTL（デフォルト 600秒）+ heartbeat 更新 |

### narration.rs と Event Feed の連携

narration.rs のバッチ処理ループ:

```
1. batch_interval_sec 経過
2. BrokerState.narration_suppressed をチェック
   → suppressed なら今回のバッチをスキップ（イベントはカーソル進めず保持）
3. event_feed.rs から直接バッチ取得（Rust 関数呼び出し、MCP 不経由）
   → MCP write_event + JSONL hooks 両方の統合フィード
4. coalescing + dedupe
5. LLM 選別（重要な情報を抽出） → Speech Queue 投入
```

### デュアル書き込みパス

| 経路 | 位置づけ | 対象 |
|------|---------|------|
| **MCP `write_event`** | **協調イベント用** | work_claim, test_result, error_signature 等の構造化イベント。型安全・セッション情報自動付与・Worker 間で意味のあるイベント |
| **JSONL hooks** | **網羅ログ用** | CLI hooks が捕捉する全イベント。MCP 非対応 CLI でも動作。Worker 停止時も記録が残る |
| **event_feed.rs** | **統合ハブ** | MCP 直接投入 + JSONL 取り込みを統合し、単一 Event Feed として UI・narration.rs・MCP リソースに提供 |

**両パス常時稼働**: MCP 接続済み Worker でも JSONL hooks は停止しない。協調イベントは `write_event`、網羅ログは JSONL の役割分担。event_feed.rs が両方を統合

**dedupe_key 生成規約**: MCP 側・JSONL 側ともに同一フォーマットで生成。
- 形式: `{event_type}:{tool_or_target}`（例: `test_result:cargo`, `work_claim:src/main.rs`, `session_progress:completed`）
- event_feed.rs のマージ処理で、同一 `dedupe_key` + 同一 `worker` + 60秒以内のイベントを1件に集約

---

## Worker 情報取得（各 CLI 対応）

| CLI | PTY 表示 | イベントフィード | 方法 |
|-----|---------|-----------------|------|
| Claude CLI | ✅ | ✅ | MCP `write_event`（協調）+ JSONL hooks（網羅） |
| OpenClaw CLI | ✅ | ✅ | MCP `write_event`（協調）+ JSONL hooks（網羅） |
| OpenCode CLI | ✅ | ✅ | MCP `write_event`（協調）+ JSONL hooks（網羅） |
| Codex CLI | ✅ | ✅ (部分的) | MCP `write_event`（協調）+ JSONL hooks（網羅） |

**Codex 制約**: unified_exec・WebSearch 等一部ツールは hooks 対象外。
**共通パターン**: 協調イベント → MCP `write_event`、網羅ログ → JSONL hooks。event_feed.rs が統合ハブとして両パスを単一 Event Feed にマージ

---

## オンボーディング（初回起動時）

既存の `Onboarding.tsx`（3ステップウィザード）を流用。

1. **Oribis Home Folder** 設定
2. **Anima 設定**（CLI タイプ / モデル / アバター選択）
3. **最初の Department 作成**（名前 + CLI + モデル + working_dir）

全設定は Orchestrator エディターから後で変更可能。

---

## 既存コード資産

| コンポーネント | 状態 | 流用方針 |
|---------------|------|---------|
| `Onboarding.tsx` | 実装済み（3ステップウィザード） | Step 3 を Department 設定に微修正して流用 |
| `pty_commands.rs` (portable-pty) | Rust 側実装済み（spawn/read/write/kill） | Worker PTY バックエンドとして流用 |
| `XtermTerminal.tsx` | ファイル存在・import 済みだが App.tsx:4975 でコメントアウト（封印中）。テストファイル2つ存在 | コメントアウト解除 + 複数 Worker 対応に拡張 |
| `useAnima.ts` | 実装済み | Anima セクションで継続使用 |
| `expressionSystem.ts` | 実装済み | 3D + Anima 表示で継続使用 |

---

## 実装ロードマップ

| Phase | 内容 | 規模 | 前提 |
|-------|------|------|------|
| 完了 | `~/.oribis/` 設定ファイル構造定義 | 小 | — |
| 完了 | L1/L2 プロンプトの `~/.oribis/roles/` 移行 | 小 | — |
| **P1** ✅ | **ドロワー再編 + 下部 PTY パネル + Worker 手動管理 + イベントフィード + ナレーション + Worker 協調（MCP）** | 大 | 完了 5c8b0f8（品質修正エピック進行中） |
| **P2** | **Orchestrator Editor 全画面（レーンパイプライン + Department 設定）** | 中 | P1 |
| **P3** | **Anima 常駐 + 自動ルーティング + スケジューラ** | 中 | P1 + P2 |
| **ACT-P2** ✅ | **Action Platform / Internal Worker read-only closed loop + write diff proposal preview** | 大 | Anima Provider分離 + Worker CLI維持 |
| 将来 | Lead Mode（複数 Worker 並列）+ ノードエディタサブビュー | 大 | P3 |

各 Phase は独立して動作する設計:
- P1 完了 ✅: Worker の手動 spawn/管理/PTY 操作 + イベントフィード表示 + Anima ナレーション（重要情報選別読み上げ）が稼働。コミット `5c8b0f8`。品質修正エピック（kill統合/per-worker cursor/MCP session identity）進行中
- P2 完了時点: Department の GUI 設定・パイプライン可視化が可能
- P3 完了時点: Anima による自動タスクルーティング・スケジューラが稼働
- ACT-P2 完了時点: Anima提案→policy/audit評価→ユーザー承認→承認判断永続化→read-only Internal Worker Job実行→Job詳細/Event/Artifact→Anima説明の閉ループと、write diff proposalの実WritePlan生成・preview表示・approval hash binding表示が稼働。write/shell/MCP-writeは未開放

---

## P1 実装仕様（ドロワー再編 + 下部 PTY パネル + Worker 手動管理 + ナレーション + Worker 協調）

### 修正対象ファイル一覧

#### 既存ファイル修正（13件）

| # | ファイル | 修正内容 |
|---|---------|---------|
| 1 | `src/App.tsx` | **二重タブ再編**: (A) 左ドロワー `sidebarTab`（L678, 6タブ: project/log/console/tasks/memory/prompt, 描画 L3237）→ Anima/Department/EventFeed セクションに再編。(B) メインエリア `activeTab`（L542, 6タブ: chat/log/console/tasks/memory/prompt, 描画 L4394）→ chat のみ残し他5タブ廃止（機能は左ドロワー or PTYパネルに移行）。下部 pane-bottom → PTY パネル（トグル表示/非表示 + Worker タブバー + xterm.js）。高さドラッグ調整（splitter）追加。**Speech Queue 経路変更**: `onSpeak` コールバックを Speech Queue consumer に再定義（useAnima.ts 側変更との整合） |
| 2 | `src/App.css` | `.pane-bottom` 刷新（フル幅 PTY パネル）。`.v2-menu-drawer` セクション再編。新規クラス: `.pty-panel-tabbar`, `.pty-panel-resize-handle`, `.xterm-container`, `.worker-item`, `.department-dropdown`, `.event-feed-item-high`, `.event-feed-item-medium`, `.event-feed-item-low` |
| 3 | `src/components/XtermTerminal.tsx` | コメントアウト解除 + 複数 Worker 対応に拡張。props に `workerId` 追加。複数インスタンス同時管理（display:none 切替）対応。※現行は App.tsx:4975 でコメントアウト済み（封印中）、import 文は存在 |
| 4 | `src/components/Onboarding.tsx` | Step 3「CLI backend」→「Department 設定」に改編（部門名 + CLI + モデル + working_dir） |
| 5 | `src/plugin/types.ts` | `WorkerInfo`, `DepartmentConfig`, `EventFeedItem`, `SpeechQueueItem`, `NarrationCursor` 型定義追加 |
| 6 | `src-tauri/src/pty_commands.rs` | 既存コマンド維持。オプション: `list_pty_sessions()`, `get_pty_status()` 追加 |
| 7 | `src-tauri/src/lib.rs` | Worker/Department/EventFeed/Narration 用 Tauri コマンド登録（`list_workers`, `spawn_worker`, `kill_worker`, `get_event_feed`, `get_department_config`, `update_department_config`, `get_narration_status`, `set_narration_enabled` 等） |
| 8 | `src-tauri/src/anima/events.rs` | `EventFeedItem` Rust 型定義のみ追加（JSONL 書き込みは event_feed.rs に一本化。events.rs は型と変換トレイトのみ） |
| 9 | `src/hooks/useAnima.ts` | **Speech Queue 統合（影響大）**: 既存の即時発話（greeting/tool_start/error/lewd）を廃止し、全発話を単一 Speech Queue 経由に変更。影響範囲: (A) `speak()` 関数 → キュー投入に変更（即時再生→キュー経由）。(B) App.tsx の `onSpeak` コールバック → Speech Queue の consumer として再定義。(C) TTS 起動経路: backend `narration.rs` → Tauri event `narration:speak` → useAnima.ts が受信 → Speech Queue 投入 → キューから順次 TTS 再生。(D) 既存トリガー（greeting 等）も同一キューに HIGH 投入（即時性は priority で保証） |
| 10 | `src-tauri/src/anima/pipeline.rs` | `InputEvent` にナレーショントリガー追加。narration.rs からのバッチ選別結果を受け取り TTS パイプラインに投入 |
| 11 | `src-tauri/src/mcp/tools/avatar.rs` | `speak` ツール **P1 凍結**: ツール定義は残すが呼び出し時に「ナレーション一本化のため凍結中。write_event でログに書いてください」エラーを返す。将来解凍時に Speech Queue 経由に変更予定 |
| 12 | `src-tauri/src/mcp/server.rs` | `write_event` ツールのディスパッチ追加。`oribis://events/feed` リソースハンドラ追加 |
| 13 | `src-tauri/src/mcp/resources.rs` | `oribis://events/feed?limit=N&since=ID&types=T&department=D&exclude_self=bool` リソース追加（Worker 間協調バス — P1 コアパス） |

#### 新規ファイル（9件）

| # | ファイル | 役割 |
|---|---------|------|
| 14 | `src/components/WorkerPanel.tsx` | 下部 PTY パネル（Worker タブバー + xterm.js コンテナ + resize splitter） |
| 15 | `src/components/DrawerAnima.tsx` | 左ドロワー Anima セクション（History / Prompt / Memory） |
| 16 | `src/components/DrawerDepartment.tsx` | 左ドロワー Department/Worker セクション（ドロップダウン + Worker 一覧 + [+] ボタン） |
| 17 | `src/components/DrawerEventFeed.tsx` | 左ドロワー Event Feed セクション（イベントタイムライン表示、優先度色分け、スクロール） |
| 18 | `src-tauri/src/worker_manager.rs` | Worker ライフサイクル管理（spawn/kill/track + WorkerInfo 保持） |
| 19 | `src-tauri/src/event_feed.rs` | **EventFeed 責務一本化**: JSONL 書き込み・ファイル監視・読み取り・マージ・カーソル管理（`~/.oribis/state/events/`）。narration.rs へのバッチ取得 API 提供。MCP `write_event` からの直接投入も受け付け。events.rs は型定義のみ、実処理はすべてここに集約 |
| 20 | `src-tauri/src/department_config.rs` | Department JSON 読み書き（`~/.oribis/departments/*.json` + Schema バリデーション） |
| 21 | `src-tauri/src/narration.rs` | ナレーションエンジン: バッチ取得（既読カーソル管理）→ BrokerState.narration_suppressed チェック → coalescing + dedupe → LLM選別 → Speech Queue 投入。`narration_cursor.json` 永続化 |
| 22 | `src-tauri/src/mcp/tools/event_feed.rs` | MCP `write_event` ツールハンドラ。セッション情報から department/worker/session_id を自動付与し event_feed.rs に直接投入。協調イベント（work_claim, test_result 等）の構造化書き込み経路 |

#### テストファイル更新（既存 + 新規）

| # | ファイル | 更新内容 |
|---|---------|---------|
| 23 | `src/App.terminal.test.tsx` | 複数 Worker PTY テスト追加。コメントアウト解除後のテスト更新 |
| 24 | `src/components/XtermTerminal.test.tsx` | `workerId` props 追加に伴うテスト更新。複数インスタンステスト追加 |
| 25 | `src-tauri/src/narration.rs` テスト | バッチ取得・カーソル管理・coalescing・dedupe・Speech Queue投入・BrokerState suppressed チェックのユニットテスト（`#[cfg(test)]` モジュール内） |
| 26 | `src-tauri/src/mcp/tools/event_feed.rs` テスト | `write_event` ツールのバリデーション・セッション情報自動付与・event_feed.rs 投入のユニットテスト |

#### 変更不要（確認済み）

| ファイル | 理由 |
|---------|------|
| `src/plugin/PluginManager.ts` | P1 スコープ外 |
| `tauri.conf.json` | PTY plugin 登録済み |
| `package.json` | xterm.js 依存済み |

### 実装順序（推奨）

1. **型定義 + Speech Queue API 契約** (#5): `WorkerInfo` / `DepartmentConfig` / `EventFeedItem` / `SpeechQueueItem` / `NarrationCursor` の型定義。**Speech Queue のインターフェース（投入・消費・優先度・expire）を先行定義**し、backend（narration.rs）と frontend（useAnima.ts）の契約を確定させる
2. **Rust バックエンド（Worker基盤）** (#18→#20→#19→#6→#8): worker_manager → department_config → event_feed（JSONL書き込み+監視+読み取り+カーソル+MCP直接投入一本化）→ pty_commands → events.rs（型定義のみ）
3. **Rust バックエンド（ナレーション）** (#21): narration.rs（event_feed.rs のバッチ取得API利用 → BrokerState.narration_suppressed チェック → coalescing + dedupe → LLM選別 → Tauri event `narration:speak` 発火）
4. **MCP + Speech Queue 統合（セット実装）** (#11→#22→#12→#13→#9→#10): avatar.rs speak **凍結**（エラー返却に変更）→ MCP event_feed.rs ツールハンドラ → server.rs → resources.rs。**同ステップ内で** useAnima.ts Speech Queue consumer 実装 + pipeline.rs ナレーショントリガー統合 + App.tsx `onSpeak` 経路変更（※ narration.rs → Speech Queue → frontend consumer は同時に実装しないと経路が宙に浮くため）
5. **lib.rs コマンド登録** (#7): 全 Tauri コマンド一括登録
6. **フロントエンド コンポーネント** (#3→#14→#15→#16→#17): XtermTerminal 拡張 → WorkerPanel → DrawerAnima → DrawerDepartment → DrawerEventFeed
7. **統合** (#1→#2): App.tsx レイアウト再編 + App.css
8. **テスト** (#23→#24→#25→#26): App.terminal.test.tsx + XtermTerminal.test.tsx + narration.rs テスト + MCP event_feed.rs テスト
9. **オンボーディング** (#4): Step 3 改編

### Speech Queue API 契約（backend ↔ frontend）

ナレーション統合の核となるインターフェース。Step 1 で先行定義し、backend/frontend 双方がこの契約に従う。

#### Tauri Event（backend → frontend）

| イベント名 | ペイロード | 発火元 |
|-----------|----------|--------|
| `narration:speak` | `SpeechQueueItem { id, text, priority, source, expires_at }` | narration.rs（LLM選別後） |
| `narration:status` | `{ enabled, queue_length, last_event_id }` | narration.rs（ステータス変更時） |

#### Tauri Command（frontend → backend）

| コマンド | 引数 | 戻り値 | 用途 |
|---------|------|--------|------|
| `get_narration_status` | — | `NarrationStatus` | ナレーション状態取得 |
| `set_narration_enabled` | `enabled: bool` | — | ナレーション ON/OFF |

#### Speech Queue（frontend 側・useAnima.ts 内）

| 操作 | 説明 |
|------|------|
| `enqueue(item: SpeechQueueItem)` | キューに投入。priority に基づきソート。最大5件、溢れ時は LOW から破棄 |
| `dequeue(): SpeechQueueItem?` | 最高優先度の未再生アイテムを取得。expire 済みは自動スキップ |
| `cancel(id)` | 特定アイテムをキューから除去 |
| `flush()` | 全アイテム破棄（animaMode=off 切替時等） |

#### 発話経路の統一

```
[既存] greeting/tool/error/lewd → speak() → 即時TTS
[新規] narration:speak event → useAnima.ts listener → enqueue()

↓ 統一後

[全発話] → enqueue(SpeechQueueItem) → Speech Queue → dequeue() → TTS 再生
  - greeting/tool/error/lewd: priority=HIGH, source="system"
  - narration 選別結果: priority=item.priority, source="narration"
  - App.tsx onSpeak: Speech Queue の consumer（dequeue → TTS 呼び出し）に変更
  ※ MCP speak は P1 凍結（将来解凍時に source="mcp" として統合予定）
```

---

## 技術メモ

- **ConPTY**: Windows 10 1809以降で利用可能。TauriでのPTY実装に使用。
- **VSCode実績**: xterm.js + ConPTYの組み合わせはVSCode統合ターミナルで実績あり。
- **Anima JSON stream**: TTS・好感度・inner_thoughtなど構造化データが必要なため、WorkerのPTYとは別にJSON stream継続。
- **Codex app-server**: 完全なイベント統合が必要な場合はapp-server（JSON-RPC）も選択肢。
- **スケジューラ**: tokio::time ベース。Oribis プロセス常駐中のみ動作。OS スケジューラ（cron/Task Scheduler）非依存。
- **JSON Schema**: `_schema.json` で departments JSON をバリデーション。GUI ツールチップ生成にも使用。
- **クロスツール互換**: `~/.oribis/roles/` を Claude Code / Codex / OpenCode の instructions から参照可能。
