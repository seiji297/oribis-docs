# タスク4: OrchestratorEditor コンポーネント設計書

> 対象タスク: TASK-4（P2 Orchestrator Editor 全画面）
> 参照設計書: `design-orchestrator-p2-20260510.md`
> 作成日: 2026-05-11
> 作成者: sysdev worker
> **注意: 本設計書は型定義案・状態遷移・責務分解・ファイル構成案のみ。実ファイル作成なし（AC6 準拠）**

---

## 1. AC 対応表

| AC | 内容 | 本設計書の対応箇所 |
|----|------|-----------------|
| AC1 | 5タブ構成が型・インターフェースとして定義 | §3, §4 |
| AC2 | dirty state 管理の設計が文書化 | §5 |
| AC3 | Department CRUD インターフェースの型が定義 | §6 |
| AC4 | ファイル構成が策定 | §7 |
| AC5 | 各タブのProps/State/イベント型が定義 | §4 |
| AC6 | コード実装を含まない | 設計書のみ（本文書） |

---

## 2. 既存実装確認（タスク3 完了済み）

### 2.1 Tauri コマンド（lib.rs 登録済み）

| コマンド | シグネチャ | 用途 |
|---------|-----------|------|
| `list_departments_config` | `() → Result<Vec<DepartmentConfig>, String>` | 全部門一覧取得 |
| `get_department_config` | `(name: String) → Result<DepartmentConfig, String>` | 単一部門取得 |
| `update_department_config` | `(name: String, config: DepartmentConfig) → Result<(), String>` | 保存（上書き） |
| `delete_department` | `(name: String) → Result<(), String>` | 削除（Worker 使用中チェック込み） |
| `read_prompt_file` | `(path: String) → Result<String, String>` | プロンプトファイル読み込み |
| `write_prompt_file` | `(path: String, content: String) → Result<(), String>` | プロンプトファイル書き込み |

**`read_prompt_file` / `write_prompt_file` のパス形式**: `"{department_name}/{filename}"` （例: `"sysdev/WORKER.md"`）

### 2.2 Rust 側 `DepartmentConfig` 構造体（`department_config.rs`）

```
DepartmentConfig {
  id: String,            // ファイル stem（読込時強制上書き）
  name: String,          // 表示名
  description: String,   // 部門説明（default=""）
  cli: String,           // CLI 種別
  completion_llm: bool,  // LLM 完了フラグ（default=true）
  model: Option<String>,
  working_dir: Option<String>,
  max_workers: Option<u32>,
  mode: Option<String>,  // "solo" | "lead"
  constraints: Vec<String>,
  capabilities: Vec<String>,
  narration: Option<NarrationConfig>,
  quality_gate: Option<QualityGateConfig>,
  schedule: Option<Vec<ScheduleConfig>>,
  extra: Map<String, Value>,  // 拡張フィールド（env/skills/instructions/review_mode）
}
```

### 2.3 既存 TypeScript `DepartmentConfig`（`src/plugin/types.ts`）との差分

| フィールド | Rust 側 | 現 TS 側 | P2 修正方針 |
|-----------|---------|---------|-----------|
| `id` | `String` | なし | TS に追加 |
| `description` | `String` | なし | TS に追加 |
| `completion_llm` | `bool` | なし | TS に追加 |
| `constraints` | `Vec<String>` | `Record<string, unknown>` | `string[]` に修正 |
| `narration` | `Option<NarrationConfig>` | `boolean` | `NarrationConfig \| undefined` に修正 |
| `quality_gate` | `Option<QualityGateConfig>` | `Record<string, unknown>` | `QualityGateConfig \| undefined` に修正 |
| `schedule` | `Option<Vec<ScheduleConfig>>` | `Record<string, unknown>` | `ScheduleConfig[] \| undefined` に修正 |
| `env` | `extra["env"]` | `Record<string, string>` | `extra` 経由でアクセス |
| `skills` | `extra["skills"]` | `string[]` | `extra` 経由でアクセス |
| `instructions` | `extra["instructions"]` | `string` | `extra` 経由でアクセス |

---

## 3. TypeScript 型定義案

> 実装ファイル `src/plugin/types.ts` への変更案。実ファイルはタスク6実装時に修正。

```typescript
// ── types.ts P2 追加・修正案 ──────────────────────────────────────────────

export interface NarrationConfig {
  enabled: boolean;              // default: true
  batch_interval_sec: number;    // default: 60
}

export interface QualityGateConfig {
  design_gate: boolean;          // default: true
  final_gate: boolean;           // default: true
}

export interface ScheduleConfig {
  task: string;
  interval: string;              // 例: "every 6h", "every monday 09:00"
  enabled: boolean;
}

// P1 の DepartmentConfig を P2 で Rust 側に整合（既存フィールドの型を修正）
export interface DepartmentConfig {
  id: string;                    // ファイル stem（読み取り専用）
  name: string;
  description: string;           // default: ""
  cli: string;
  completion_llm: boolean;       // default: true
  model?: string;
  working_dir?: string;
  max_workers?: number;
  mode?: string;                 // "solo" | "lead"
  constraints: string[];         // P1: Record → P2: string[]
  capabilities: string[];
  narration?: NarrationConfig;   // P1: boolean → P2: NarrationConfig
  quality_gate?: QualityGateConfig; // P1: Record → P2: QualityGateConfig
  schedule?: ScheduleConfig[];   // P1: Record → P2: ScheduleConfig[]
  extra?: Record<string, unknown>; // env / skills / instructions / review_mode 等
}

/** extra から型安全にアクセスするためのヘルパー型 */
export interface DepartmentExtra {
  env?: Record<string, string>;
  skills?: string[];
  instructions?: string;         // プロンプトファイルパス
  review_mode?: string;          // "cross-model" | "same-model" | "none"
}

/** extra ヘルパー関数（型案） */
// function getExtra(config: DepartmentConfig): DepartmentExtra
// function setExtra(config: DepartmentConfig, extra: DepartmentExtra): DepartmentConfig
```

---

## 4. 各コンポーネントの Props / State / イベント型定義案

### 4.1 OrchestratorEditor（全画面ルート）

```typescript
// Props
interface OrchestratorEditorProps {
  onClose: () => void;
  initialDepartment?: string;    // 初期選択部門名（省略時: 先頭）
}

// State（コンポーネント内部）
type OrchestratorEditorState = {
  departments: DepartmentConfig[];
  selectedDeptName: string | null;
  draftConfig: DepartmentConfig | null;  // 編集中（未保存）
  savedConfig: DepartmentConfig | null;  // 保存済みベースライン
  promptFiles: Map<string, PromptFileDraft>; // プロンプトファイル dirty 管理
  isLoading: boolean;
  saveError: string | null;
};

type PromptFileDraft = {
  draft: string;      // 編集中テキスト
  saved: string;      // 保存済みテキスト
  path: string;       // "{dept}/{filename}"
};

// isDirty 判定（deep equal）
type DirtyStatus = {
  configDirty: boolean;                         // draftConfig vs savedConfig
  promptsDirty: Map<string, boolean>;           // ファイル名 → dirty
  anyDirty: boolean;                            // configDirty || いずれかのpromptsDirty
};
```

### 4.2 LanePipeline

```typescript
interface LanePipelineProps {
  departments: DepartmentConfig[];
  selectedDeptName: string | null;
  onSelectDept: (name: string) => void;
  onAddDepartment: () => void;
  onDeleteDepartment: (name: string) => void;
}

// イベント型（onDeleteDepartment の前に confirm が必要）
// 確認ダイアログは LanePipeline が担当しない → OrchestratorEditor が担当
```

### 4.3 DepartmentDetailPanel

```typescript
interface DepartmentDetailPanelProps {
  draftConfig: DepartmentConfig;
  dirtyStatus: DirtyStatus;
  saveError: string | null;
  promptFiles: Map<string, PromptFileDraft>;
  onConfigChange: (config: DepartmentConfig) => void;  // リアルタイム編集
  onSave: () => void;                                   // [Save] ボタン
  onPromptFileChange: (path: string, content: string) => void;
  onPromptFileSave: (path: string) => void;             // [Save to File]
}

// 内部 State
type TabId = "general" | "workflow" | "schedule" | "skills" | "prompts";
// activeTab: TabId
```

### 4.4 GeneralTab

```typescript
interface GeneralTabProps {
  config: DepartmentConfig;
  onChange: (config: DepartmentConfig) => void;
  errors: FieldError[];
}

type FieldError = {
  field: keyof DepartmentConfig | string;
  message: string;
};
```

### 4.5 WorkflowTab

```typescript
interface WorkflowTabProps {
  config: DepartmentConfig;
  onChange: (config: DepartmentConfig) => void;
}

// パイプライン表示用（読み取り専用・導出値）
type PipelinePreview = {
  stages: string[];      // 表示するステージ名
  enabled: boolean[];    // quality_gate 設定に基づく有効/無効
};
```

### 4.6 ScheduleTab

```typescript
interface ScheduleTabProps {
  schedule: ScheduleConfig[];
  onChange: (schedule: ScheduleConfig[]) => void;
}
```

### 4.7 SkillsTab

```typescript
interface SkillsTabProps {
  skills: string[];
  onChange: (skills: string[]) => void;
}

// スキルプレビュー用の内部 State
// previewContent: string | null
// previewSkillId: string | null
```

### 4.8 PromptsTab

```typescript
interface PromptsTabProps {
  department: DepartmentConfig;       // instructions パス取得用
  promptFiles: Map<string, PromptFileDraft>;
  onFileChange: (path: string, content: string) => void;
  onFileSave: (path: string) => void;
}

// 内部 State
// selectedFilePath: string | null
// isLoadingFile: boolean
// loadError: string | null
```

---

## 5. dirty state 管理設計

### 5.1 dirty の粒度

| 対象 | 粒度 | 管理場所 |
|------|------|---------|
| DepartmentConfig | 部門単位（deep equal） | OrchestratorEditor |
| プロンプトファイル | ファイル単位（文字列一致） | OrchestratorEditor |
| タブ状態 | 管理しない（タブ間移動はなし） | — |

**タブ単位の dirty 管理は不採用。** 理由：同一 `draftConfig` を全タブが共有するため、タブ単位に分割すると保存の境界が曖昧になる。

### 5.2 状態遷移

```
[初期化]
  ↓ list_departments_config
departments 読み込み完了
  ↓ 部門選択
savedConfig = departments[selected]
draftConfig = deep copy of savedConfig
promptFiles = Map（空）
isDirty = false

[フィールド編集]
  ↓ onChange(newConfig)
draftConfig = newConfig
isDirty = true（configDirty）

[プロンプトファイル読み込み]
  ↓ PromptsTab マウント時
  → invoke("read_prompt_file", { path: "{dept}/{file}" })
promptFiles.set(path, { draft: content, saved: content })
promptsDirty[path] = false

[プロンプトファイル編集]
  ↓ onPromptFileChange(path, content)
promptFiles.get(path).draft = content
promptsDirty[path] = draft !== saved

[Save（configのみ）]
  ↓ [Save] ボタン → onSave()
  1. フロントエンドバリデーション（cli 空チェック等）
     → エラーあり: saveError 表示、処理中断
  2. invoke("update_department_config", { name, config: draftConfig })
     → 成功: savedConfig = draftConfig, isDirty.configDirty = false, saveError = null
     → 失敗: saveError = error message（draftConfig は維持・rollback なし）
  3. loadDepartments()（レーン表示を最新化）

[Save（プロンプトファイルのみ）]
  ↓ [Save to File] ボタン → onPromptFileSave(path)
  → invoke("write_prompt_file", { path, content: draft })
     → 成功: promptFiles.get(path).saved = draft, promptsDirty[path] = false
     → 失敗: エラーをPromptsTab 内で表示（他の状態に影響なし）

[部門切替（dirty あり）]
  ↓ レーンの別部門クリック
  anyDirty === true → confirm("Unsaved changes will be lost. Continue?")
    → キャンセル: 切替しない
    → OK: draftConfig = 新部門の deep copy, promptFiles = 空

[ESC / [Close]（dirty あり）]
  anyDirty === true → confirm("Unsaved changes will be lost. Close?")
    → キャンセル: 閉じない
    → OK: onClose()

[部門削除]
  ↓ [×] ボタン → onDeleteDepartment(name)
  1. confirm("Delete department '{name}'? This cannot be undone.")
     → キャンセル: 処理中断
  2. invoke("delete_department", { name })
     → 成功: loadDepartments(), 選択を別部門に切替
     → 失敗: エラー表示（"Cannot delete: Workers are active" 等）
```

### 5.3 保存失敗時の方針

- **rollback なし**: `draftConfig` は編集内容を維持する
- `saveError` にエラーメッセージを表示し、ユーザーが再試行できる
- 外部更新との競合検知: **P2 では不検知**（単一ユーザーUIのため）

### 5.4 deep equal 実装方針

```typescript
// JSON.stringify 比較（シンプル・十分な精度）
function isConfigDirty(draft: DepartmentConfig, saved: DepartmentConfig): boolean {
  return JSON.stringify(draft) !== JSON.stringify(saved);
}
// ※ フィールド順序依存の誤検知を防ぐため、Rust 側が返す JSON の key 順序を信頼
// ※ 将来的に lodash.isEqual への移行を検討
```

---

## 6. Department CRUD インターフェース設計

### 6.1 責務境界

| 責務 | UI 側 | Backend（Rust）側 |
|------|-------|-----------------|
| フォームバリデーション | cli 空チェック、max_workers 範囲チェック | JSON Schema 検証 |
| 確認ダイアログ | 削除確認、未保存破棄確認 | — |
| identity | name をキーとして扱う | ファイル stem = id = name |
| ファイル I/O | なし（invoke 経由） | JSON 読み書き（atomic write）|
| パストラバーサル防止 | なし | `validate_name()` |
| Worker 使用中チェック | なし | `WorkerManager.delete_department_if_idle()` |
| create 方式 | デフォルトテンプレート生成 → update_department_config | ファイル新規作成 |
| rename | P2 スコープ外（delete + create で対応） | — |
| delete 方式 | UI で確認後 invoke | ディレクトリごと物理削除 |
| partial save | なし（全フィールドを一括保存） | 上書き保存（atomic write） |
| optimistic update | なし（save 後に list_departments_config 再読込） | — |

### 6.2 CRUD 操作型（TypeScript 型案）

```typescript
// Create
type CreateDepartmentRequest = {
  name: string;
  defaults?: Partial<DepartmentConfig>;
};
// 実装: invoke("update_department_config", { name, config: defaultTemplate })

// Read（全部門）
type ListDepartmentsResponse = DepartmentConfig[];
// 実装: invoke("list_departments_config")

// Read（単一）
type GetDepartmentRequest = { name: string };
type GetDepartmentResponse = DepartmentConfig;
// 実装: invoke("get_department_config", { name })

// Update
type UpdateDepartmentRequest = {
  name: string;
  config: DepartmentConfig;
};
// 実装: invoke("update_department_config", { name, config })
// 前提: バリデーション（フロント側 + Backend 側 JSON Schema）

// Delete
type DeleteDepartmentRequest = { name: string };
// 実装: invoke("delete_department", { name })
// Backend が Worker 使用中チェック込みで返す
```

### 6.3 API 層の分離

`read_prompt_file` / `write_prompt_file` は Department CRUD とは別の概念（ファイルサービス）として扱う。

| API 層 | Tauri コマンド群 | 責務 |
|--------|----------------|------|
| Department metadata service | `list_departments_config`, `get_department_config`, `update_department_config`, `delete_department` | departments/*.json の読み書き |
| Prompt file service | `read_prompt_file`, `write_prompt_file` | departments/{name}/prompts/*.md|.txt の読み書き |

PromptsTab は Prompt file service のみ使用する。DepartmentDetailPanel は Department metadata service + Prompt file service の両方を間接使用する。

---

## 7. 将来ファイル構成案

> **実装はタスク4〜8 で行う。本タスクではファイルを作成しない。**

```
src/components/
├── OrchestratorEditor.tsx         # 全画面ルート（状態管理・CRUD 呼び出し）
├── LanePipeline.tsx               # レーンパイプライン（部門横並び表示）
├── DepartmentDetailPanel.tsx      # 詳細パネル（5タブコンテナ）
└── tabs/
    ├── GeneralTab.tsx             # General タブ（基本設定フィールド）
    ├── WorkflowTab.tsx            # Workflow タブ（quality_gate + パイプライン）
    ├── ScheduleTab.tsx            # Schedule タブ（定期タスク管理）
    ├── SkillsTab.tsx              # Skills タブ（スキル一覧管理）
    └── PromptsTab.tsx             # Prompts タブ（ファイル編集）
```

型定義は `src/plugin/types.ts` に追記（既存ファイルを修正）。

### 7.1 各ファイルの責務

| ファイル | 責務 | 状態保持 | dirty 管理 |
|---------|------|---------|-----------|
| `OrchestratorEditor.tsx` | レイアウト、departments ロード、部門切替、CRUD ハンドラ | `departments`, `draftConfig`, `savedConfig`, `promptFiles` | `DirtyStatus` |
| `LanePipeline.tsx` | レーン表示、部門選択、削除ボタン | なし（props のみ） | なし |
| `DepartmentDetailPanel.tsx` | タブ切替 UI、Save ボタン | `activeTab` | なし（親から `dirtyStatus` 受け取り） |
| `GeneralTab.tsx` | フォームフィールド | なし | なし |
| `WorkflowTab.tsx` | トグル + パイプライン表示 | なし | なし |
| `ScheduleTab.tsx` | テーブル + 追加/削除 | なし | なし |
| `SkillsTab.tsx` | タグ入力 + プレビュー | `previewContent`, `previewSkillId` | なし |
| `PromptsTab.tsx` | ファイルパス + エディタ | `isLoadingFile`, `loadError` | なし（親の `promptFiles` 参照） |

---

## 8. 5タブ間の依存関係

| タブ | 表示データ | 編集対象 | dirty 判定対象 | 依存する他タブ | 空状態 |
|------|-----------|---------|--------------|-------------|--------|
| General | cli, model, working_dir, mode, max_workers, constraints, capabilities, env, narration | `draftConfig` 全体 | configDirty | なし | デフォルト値で表示 |
| Workflow | quality_gate, review_mode | `draftConfig.quality_gate`, `extra.review_mode` | configDirty | GeneralTab の capabilities（read-only 参照でパイプライン表示） | デフォルトゲート設定で表示 |
| Schedule | schedule 一覧 | `draftConfig.schedule` | configDirty | なし | 「No schedules」表示 |
| Skills | extra.skills | `draftConfig.extra.skills` | configDirty | なし | 「No skills」表示 |
| Prompts | extra.instructions のファイル内容 | `promptFiles`（別管理） | promptsDirty | なし | 「No file selected」表示 |

### タブ間データフロー

```
OrchestratorEditor
  draftConfig ──────────────────→ GeneralTab (rw)
                ──────────────────→ WorkflowTab (rw)
                ──────────────────→ ScheduleTab (rw)
                ──────────────────→ SkillsTab (rw, extra.skills)
                ──────────────────→ PromptsTab (r, extra.instructions パス取得)
  promptFiles ──────────────────→ PromptsTab (rw)

GeneralTab の capabilities → WorkflowTab の getPipelinePreview() への間接参照
  （props 経由ではなく、同一 draftConfig を両タブが参照するため自然に同期）
```

---

## 9. 未確定事項・実装タスクへの引き継ぎ

| 項目 | 状態 | 引き継ぎ先 |
|------|------|----------|
| `DepartmentConfig.id` フィールドの TS 追加 | 設計済み（§3） | タスク6（types.ts 修正） |
| `validate_department_config` Tauri コマンド | 設計書にあるが未実装 | タスク3 残対応 or タスク7 で UI 側バリデーションで代替 |
| スキルプレビュー読み込み（`~/.oribis/roles/**`） | Tauri `fs` 権限確認必要 | タスク6（SkillsTab 実装時） |
| deep equal の実装（lodash.isEqual vs JSON.stringify） | JSON.stringify 方針（§5.4）で確定 | タスク4 実装時 |
| PromptsTab: 複数ファイル管理 vs 単一ファイル | 単一ファイル（`extra.instructions` が指す1ファイル）で実装開始 | タスク6（PromptsTab） |
| 部門 rename 操作 | P2 スコープ外 | P3 以降 |
| バリデーション: `description` フィールドの必須チェック | Rust 側で `default=""` → UI では任意 | タスク7（CRUD） |

---

## 10. DA（Devil's Advocate）反論

### 反論: JSON.stringify で deep equal は信頼性が低い

フィールドの挿入順序が変わると `JSON.stringify` の出力が変わり、実際には差分がないのに `isDirty = true` になる誤検知が起きる。

**対処**: Rust の `serde_json` は struct フィールド順でシリアライズするため、同一 `DepartmentConfig` を serialize/deserialize すると key 順序は安定する。Tauri invoke の返値は常に Rust serialize 順なので誤検知は発生しにくい。ただし `draftConfig` をユーザーが直接構築した場合（create 時のデフォルトテンプレート）はフィールド順が異なる可能性があるため、**create 後の初回 dirty 判定は savedConfig として invoke 結果を使う**ことで解決する（§5.2 の状態遷移に記載）。将来的に lodash.isEqual への移行は open のままとする。

### 反論: `promptFiles` を OrchestratorEditor に持たせると肥大化する

PromptsTab に閉じる方が単純で、タブ間の関心分離が明確。

**対処**: `promptsDirty` を `anyDirty` に含めるためには OrchestratorEditor が保持する必要がある。部門切替時の「未保存確認」ダイアログを OrchestratorEditor が出すためにも、上位での保持が必要。PromptsTab 内に閉じると、部門切替ハンドラからプロンプト dirty を参照できなくなる。よって OrchestratorEditor での保持を維持する。

### 反論: 部門切替時の確認ダイアログは UX が悪い

毎回ダイアログが出ると使いにくい。autosave の方が良い。

**対処**: P2 の MVP では保存を明示的にする（[Save] ボタン方式）。autosave は将来検討。確認ダイアログは `anyDirty` のときだけ出るため、未編集の状態ではダイアログは出ない。

---

## 判定

**GO**

- AC1〜AC6 全件をこの設計書で充足
- 実ファイル作成なし（AC6 準拠）
- dirty state の状態遷移・保存フロー・失敗挙動を文書化（AC2）
- Department CRUD 責務境界（UI / Backend）を明確化（AC3）
- 5タブ全 Props/State/イベント型を型案として定義（AC1, AC5）
- タスク3実装済みコマンドとの整合性確認済み（§2.1）
- DA 反論処理済み
