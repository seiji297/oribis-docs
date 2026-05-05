# sysdev-5 設計計画書 — プラグイン・Worker・インフラ

> 作成: 2026-05-04
> ブランチ: `sysdev-5/plugin-worker`
> 対象: team-assignments.md §sysdev-5 担当コンポーネント

---

## 1. 現状概要

### 1.1 担当コンポーネント一覧

| # | コンポーネント | 行数 | テスト数 | 状態 |
|---|---|---|---|---|
| 1 | `src/plugin/types.ts` | 67 | — | ✅ 完成 |
| 2 | `src/plugin/PluginManager.ts` | 222 | 0 | ⚠️ テスト未追加(TASK-M) |
| 3 | `src/plugin/usePluginLoader.ts` | 80 | 0 | ✅ 完了 |
| 4 | `src/skill/types.ts` | 8 | — | ✅ 完成 |
| 5 | `src/skill/SkillPicker.tsx` | 47 | 0 | ✅ 完了 |
| 6 | `src/skill/useSkills.ts` | 30 | 0 | ✅ 完了 |
| 7 | `src/components/XtermTerminal.tsx` | 219 | 9(一部FAIL) | ⚠️ モック不整合 |
| 8 | `src-tauri/src/pty_commands.rs` | 548 | 8(unix) | ✅ 完成 |
| 9 | `src-tauri/src/plugin.rs` | 230 | 0 | ⚠️ テスト不足(TASK-M) |
| 10 | `src-tauri/src/skill.rs` | 125 | 0 | ⚠️ テスト不足 |
| 11 | `src-tauri/src/named_pipe.rs` | 220 | 0 | ⚠️ テスト不足 |
| 12 | `src-tauri/src/audio_playback.rs` | 116 | 6 | ✅ 完成 |
| 13 | `src-tauri/src/tts.rs` | 1400+ | 20+ | ✅ 完成 |
| 14 | `src-tauri/src/recording.rs` | 266 | 7 | ✅ 完成 |
| 15 | `src-tauri/src/json_log.rs` | 528 | 14 | ✅ 完成 |
| 16 | `src/utils/` | — | — | ❌ 未存在 |

### 1.2 コンポーネント間依存関係

```
tts.rs ──▶ audio_playback.rs (crate::audio_playback::play_wav_bytes_async)
plugin.rs ──▶ config.rs (crate::config::{load_config, default_config_path, PluginsConfig})
lib.rs ──▶ 全14モジュール (mod宣言 + Tauriコマンド登録)
```

### 1.3 既存の既知課題

- **Rust**: `AppConfig` に `plugins: Option<PluginsConfig>` 追加済み。テストの初期化39箇所に `plugins: None` 追加済み（355 PASS / 7 FAIL → 既存問題）
- **TS**: `XtermTerminal.test.tsx` のモックが `tauri-pty` を参照しているが、実装は直接 `invoke("pty_spawn")` を使用
- **TS**: `App.tsx` の型エラー32件はsysdev-4スコープ

---

## 2. 設計方針 — コンポーネント指向

### 2.1 原則

1. **1ディレクトリ = 1オーナー**: 他コンポーネントの内部実装に依存しない
2. **境界は型で定義**: `types.ts` / `pub struct` が公開API
3. **副作用の局所化**: 各コンポーネントの状態変更は自身のディレクトリ内で完結
4. **テストは対象ファイルに隣接**: `*.test.ts` / `mod tests` で同一ファイル内

### 2.2 コンポーネント境界の定義

```
src/plugin/          ← sysdev-5独占: プラグインFEシステム
src/skill/           ← sysdev-5独占: スキルFE
src/components/XtermTerminal.tsx ← sysdev-5独占: PTYターミナル
src/utils/           ← sysdev-5独占: 共有ユーティリティ（未作成）

src-tauri/src/pty_commands.rs ← sysdev-5独占: PTYバックエンド
src-tauri/src/plugin.rs       ← sysdev-5独占: プラグインバックエンド
src-tauri/src/skill.rs        ← sysdev-5独占: スキルバックエンド
src-tauri/src/named_pipe.rs   ← sysdev-5独占: IPC
src-tauri/src/audio_playback.rs ← sysdev-5独占: 音声再生
src-tauri/src/tts.rs          ← sysdev-5独占: TTS
src-tauri/src/recording.rs    ← sysdev-5独占: 録音
src-tauri/src/json_log.rs     ← sysdev-5独占: ログ
```

### 2.3 共有ファイルとの境界

| 共有ファイル | オーナー | sysdev-5との関係 |
|---|---|---|
| `src/types/` | sysdev-4 | 依存しない（plugin/types.tsで完結） |
| `src-tauri/src/lib.rs` | sysdev-3 | mod宣言のみ。コマンド実装は各ファイル |
| `src-tauri/src/config.rs` | sysdev-3 | `PluginsConfig` 型をplugin.rsが参照 |
| `Cargo.toml` | 共有 | 依存crate追加時は周知 |

---

## 3. 実装計画

### Phase 1: テスト追加（既存コードの変更不要）

#### 3.1 `src-tauri/src/plugin.rs` — ユニットテスト追加（TASK-M対応）

**対象関数**:
- `version_gt(a, b)` — semver比較（純粋関数）
- `get_plugin_tier(plugin_id)` — free/paid判定
- `scan_plugins()` — ディレクトリスキャン（tempdir使用）
- `copy_dir_recursive(src, dst)` — ディレクトリコピー

**テストケース**:
```
version_gt:
  - "2.0.0" > "1.0.0" → true
  - "1.1.0" > "1.0.0" → true
  - "1.0.1" > "1.0.0" → true
  - "1.0.0" > "1.0.0" → false
  - "0.9.0" > "1.0.0" → false

get_plugin_tier:
  - "scene" + scene_enabled=true → Ok(true)
  - "scene" + scene_enabled=false → Ok(false)
  - "unknown" → Ok(true) (free plugin)
  - config.toml不存在 → Err

scan_plugins:
  - 空ディレクトリ → []
  - 有効なmanifest.json → [PluginInfo]
  - 無効なmanifest.json → スキップ
```

#### 3.2 `src-tauri/src/skill.rs` — ユニットテスト追加

**対象関数**:
- `builtin_skills()` — 組み込みスキル一覧
- `scan_skills()` — スキャン（tempdir使用）
- `save_user_skill(manifest_json)` — 保存
- `delete_skill(skill_id)` — 削除

**テストケース**:
```
builtin_skills:
  - 2件返す (skill-creator, plugin-creator)
  - 両方 builtin=true

scan_skills:
  - builtin + userスキルが混在
  - 空ディレクトリ → builtinのみ

save_user_skill:
  - 有効なJSON → skill.json作成
  - 無効なJSON → Err

delete_skill:
  - 存在するスキル → ディレクトリ削除
  - 存在しないスキル → 正常終了(no-op)
```

#### 3.3 `src-tauri/src/named_pipe.rs` — ユニットテスト追加

**対象関数**:
- `get_pipe_name()` — env変数取得
- `PipeConfig::from_env()` — 環境設定

**テストケース** (non-Windowsスタブのみ):
```
get_pipe_name:
  - ORIBIS_PIPE_NAME未設定 → DEFAULT_PIPE_NAME
  - ORIBIS_PIPE_NAME設定 → その値
  - ORIBIS_PIPE_NAME空文字 → DEFAULT_PIPE_NAME + warn
  - Windows形式でない値(non-Windows) → その値そのまま
```

#### 3.4 `src/plugin/PluginManager.ts` — ユニットテスト追加（TASK-M対応）

**テストファイル**: `src/plugin/PluginManager.test.ts` 新規作成

**テストケース** (TASK-M A-3〜A-4e):
```
registerBackground:
  - A-3: 呼び出し後に background.canvas 取得可能
  - A-4d: A unload で B の background を消去しない
  - A-4e: background owner のみ unload で消去

notifyCliStateChange:
  - A-4: コールバック発火
  - A-4b: 登録直後に即時発火
  - A-4c: unloadPlugin 後はコールバック不発火
```

#### 3.5 `src/utils/` — ディレクトリ作成

空ディレクトリ + `.gitkeep` を作成。将来の共通ユーティリティ配置用。

### Phase 2: XtermTerminalテスト修正

`XtermTerminal.test.tsx` のモックを `tauri-pty` → `@tauri-apps/api/core` の `invoke` に変更。

### Phase 3: 結合確認

- `cargo test --lib` 全PASS（sysdev-5スコープ39件追加）
- `npx vitest run` XtermTerminal 9件全PASS

---

## 4. 完了条件（team-assignments.md準拠）

| 条件 | 検証方法 |
|---|---|
| WorkerタブでCLIエージェントを起動・表示 | `XtermTerminal.tsx` + `pty_commands.rs` テストPASS |
| プラグインのロード/アンロードが正常動作 | `PluginManager.ts` + `plugin.rs` テストPASS |
| 音声再生・TTS・録音が動作 | `audio_playback.rs` + `tts.rs` + `recording.rs` テストPASS |
| 全テストPASS | `cargo test --lib` + `npx vitest run` |

---

## 5. 作業順序

```
1. src/utils/.gitkeep 作成
2. src-tauri/src/plugin.rs テスト追加
3. src-tauri/src/skill.rs テスト追加
4. src-tauri/src/named_pipe.rs テスト追加
5. src/plugin/PluginManager.test.ts 新規作成
6. XtermTerminal.test.tsx モック修正
7. cargo test --lib 実行
8. npx vitest run 実行
```
