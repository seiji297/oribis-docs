# sysdev-3 設計書 — Anima バックエンド

## 変更対象ファイル（独占コンポーネントのみ）

| ファイル | 変更種別 |
|---------|---------|
| `src-tauri/src/anima/pipeline.rs` | 修正 |
| `src-tauri/src/anima/throttle.rs` | 修正 |
| `src-tauri/src/anima/context.rs` | テスト修正 |

**触ってはいけないファイル**: config.rs, lib.rs, plugin.rs, skill.rs, その他anima/外のファイル

---

## 変更1: pipeline.rs — PipelineConfig に anima_mode 追加

### 現状
```rust
pub struct PipelineConfig {
    pub base_dir: PathBuf,
    pub project_id: String,
    pub backend: String,
}
```

### 変更後
```rust
use crate::anima::cache::AnimaMode;

pub struct PipelineConfig {
    pub base_dir: PathBuf,
    pub project_id: String,
    pub backend: String,
    pub anima_mode: AnimaMode,  // 追加
}
```

### PipelineConfig::new 修正
```rust
impl PipelineConfig {
    pub fn new(base_dir: impl Into<PathBuf>, project_id: impl Into<String>) -> Self {
        Self {
            base_dir: base_dir.into(),
            project_id: project_id.into(),
            backend: String::new(),
            anima_mode: AnimaMode::Hybrid,  // デフォルト
        }
    }

    pub fn with_backend(mut self, backend: impl Into<String>) -> Self {
        self.backend = backend.into();
        self
    }

    // 追加
    pub fn with_anima_mode(mut self, mode: AnimaMode) -> Self {
        self.anima_mode = mode;
        self
    }
}
```

---

## 変更2: pipeline.rs — execute_anima_pipeline の AnimaMode 3分岐

### 現状のフロー
```
throttleチェック → キャッシュ確認 → AI生成
```

### 変更後のフロー
```
throttle設定ロード(TOML) → 好感度取得 → AnimaMode分岐
  ├─ Cache: キャッシュのみ（フォールバック含む）
  ├─ Ai: throttleチェック → AI生成のみ
  └─ Hybrid: キャッシュ確認 → あればCacheHit / なければthrottleチェック → AI生成
```

### 具体的なコード変更

`execute_anima_pipeline` 関数を以下に書き換える:

```rust
async fn execute_anima_pipeline(
    config: &PipelineConfig,
    category: &AnimaCategory,
    adapter: &Arc<dyn CliAdapter>,
) -> Result<PipelineResponse> {
    let category_str = category.to_string();

    // throttle設定ロード（TOML → デフォルトフォールバック）
    let throttle_config = throttle::load_throttle_config_at(&config.base_dir);

    // 好感度取得 → tier決定
    let affinity_state = affinity::load_affinity_at(&config.base_dir)?;
    let cache_tier = to_cache_tier(affinity_state.tier());
    let cache_cat = to_cache_category(category);

    match config.anima_mode {
        AnimaMode::Cache => {
            // Cacheモード: キャッシュのみ返す（AI生成なし）
            let (phrase, _) = cache::extract_with_fallback(cache_cat, cache_tier, None);
            Ok(PipelineResponse::CacheHit { text: phrase.text })
        }
        AnimaMode::Ai => {
            // Aiモード: throttleチェック → 常にAI生成
            if !throttle::should_speak_at(&throttle_config, &category_str, &config.base_dir) {
                return Ok(PipelineResponse::Suppressed);
            }
            generate_ai_response(config, category, adapter, &affinity_state).await
        }
        AnimaMode::Hybrid => {
            // Hybridモード: キャッシュ → AIフォールバック
            if cache::cache_exists(cache_cat, cache_tier) {
                let (phrase, _) = cache::extract_with_fallback(cache_cat, cache_tier, None);
                Ok(PipelineResponse::CacheHit { text: phrase.text })
            } else {
                if !throttle::should_speak_at(&throttle_config, &category_str, &config.base_dir) {
                    return Ok(PipelineResponse::Suppressed);
                }
                generate_ai_response(config, category, adapter, &affinity_state).await
            }
        }
    }
}
```

### generate_ai_response 関数を分離（新規）

既存の `execute_anima_pipeline` 内の AI生成部分（`event_to_llm_input` 以降〜関数末尾）をそのまま抽出する。

```rust
async fn generate_ai_response(
    config: &PipelineConfig,
    category: &AnimaCategory,
    adapter: &Arc<dyn CliAdapter>,
    affinity_state: &affinity::AffinityState,
) -> Result<PipelineResponse> {
    // 既存コードをそのまま移動（event_to_llm_input〜関数末尾）
    // affinity_stateは引数から受け取る（再読み込みしない）
    let llm_input = event_to_llm_input(&InputEvent::AnimaState {
        category: category.clone(),
        context: None,
    });
    // ... 以降は既存コードそのまま
    // ただし affinity_state.value は引数のものを使用
}
```

**注意**: `generate_ai_response` 内で `affinity::load_affinity_at` を再度呼ばないこと。引数の `affinity_state` を使う。

---

## 変更3: throttle.rs — TOML ロード機能追加

### 追加する定数
```rust
const THROTTLE_CONFIG_FILE: &str = "throttle.toml";
```

### 追加する関数
```rust
fn throttle_config_path(base_dir: &Path) -> std::path::PathBuf {
    base_dir.join("oribis").join("nagiko").join(THROTTLE_CONFIG_FILE)
}
```

### 追加する TOML デシリアライズ構造体
```rust
#[derive(Debug, Clone, serde::Deserialize)]
struct TomlThrottleConfig {
    min_interval_secs: Option<u64>,
    category: Option<std::collections::HashMap<String, TomlCategoryThrottle>>,
}

#[derive(Debug, Clone, serde::Deserialize)]
struct TomlCategoryThrottle {
    cooldown_secs: u64,
    probability: f64,
}
```

### 追加する変換実装
```rust
impl From<TomlThrottleConfig> for ThrottleConfig {
    fn from(toml: TomlThrottleConfig) -> Self {
        let mut category_settings = HashMap::new();
        if let Some(cats) = toml.category {
            for (name, cfg) in cats {
                category_settings.insert(name, CategoryThrottle {
                    cooldown_secs: cfg.cooldown_secs,
                    probability: cfg.probability,
                });
            }
        }
        ThrottleConfig {
            min_interval_secs: toml.min_interval_secs.unwrap_or(60),
            category_settings,
        }
    }
}
```

### 追加する Default 実装
```rust
impl Default for ThrottleConfig {
    fn default() -> Self {
        Self {
            min_interval_secs: 60,
            category_settings: HashMap::new(),
        }
    }
}
```

### 追加する pub 関数
```rust
/// throttle.toml から ThrottleConfig をロードする
/// ファイルが存在しない場合はデフォルト設定を返す
pub fn load_throttle_config_at(base_dir: &Path) -> ThrottleConfig {
    let path = throttle_config_path(base_dir);
    match std::fs::read_to_string(&path) {
        Ok(content) => {
            match toml::from_str::<TomlThrottleConfig>(&content) {
                Ok(toml_cfg) => toml_cfg.into(),
                Err(e) => {
                    log::warn!("failed to parse throttle.toml: {}, using defaults", e);
                    ThrottleConfig::default()
                }
            }
        }
        Err(_) => ThrottleConfig::default(),
    }
}
```

### 追加するテスト
```rust
#[test]
fn test_load_throttle_config_missing_file() {
    let dir = tempdir().unwrap();
    let config = load_throttle_config_at(dir.path());
    assert_eq!(config.min_interval_secs, 60);
    assert!(config.category_settings.is_empty());
}

#[test]
fn test_load_throttle_config_valid_toml() {
    let dir = tempdir().unwrap();
    let nagiko_dir = dir.path().join("oribis").join("nagiko");
    std::fs::create_dir_all(&nagiko_dir).unwrap();
    std::fs::write(nagiko_dir.join("throttle.toml"), r#"
min_interval_secs = 30

[category.greeting]
cooldown_secs = 0
probability = 1.0

[category.idle]
cooldown_secs = 120
probability = 0.5
"#).unwrap();
    let config = load_throttle_config_at(dir.path());
    assert_eq!(config.min_interval_secs, 30);
    assert_eq!(config.category_settings.len(), 2);
    assert_eq!(config.category_settings["greeting"].probability, 1.0);
    assert_eq!(config.category_settings["idle"].cooldown_secs, 120);
}

#[test]
fn test_load_throttle_config_invalid_toml() {
    let dir = tempdir().unwrap();
    let nagiko_dir = dir.path().join("oribis").join("nagiko");
    std::fs::create_dir_all(&nagiko_dir).unwrap();
    std::fs::write(nagiko_dir.join("throttle.toml"), "invalid toml {{{}").unwrap();
    let config = load_throttle_config_at(dir.path());
    // 不正TOMLはデフォルト値にフォールバック
    assert_eq!(config.min_interval_secs, 60);
}
```

---

## 変更4: context.rs — テスト期待値修正

### 理由
`AffinityTier::from_value(50)` は `Neutral`（40-59範囲）を返す。テストコメントと期待値が `Close=良好` になっているのは誤り。

### 修正箇所（2箇所）

```rust
// 修正前
// dynamic contains L3 parts (no affinity file → default +50 Close=良好)
assert!(ctx.dynamic.contains("[好感度: +50（良好）]"));

// 修正後
// dynamic contains L3 parts (no affinity file → default +50 Neutral=中立)
assert!(ctx.dynamic.contains("[好感度: +50（中立）]"));
```

```rust
// 修正前
// affinity file なし → default +50 Close=良好
assert_eq!(result, "[好感度: +50（良好）]\n");

// 修正後
// affinity file なし → default +50 Neutral=中立
assert_eq!(result, "[好感度: +50（中立）]\n");
```

---

## Cargo.toml 変更

`toml` クレートが依存に必要。既に `Cargo.toml` に含まれているか確認し、なければ追加が必要。**追加する場合は sysdev-4, sysdev-5 に周知すること。**

---

## テスト実行コマンド

```bash
cargo test --lib anima::
```

## 完了条件チェックリスト

- [ ] `cargo test` 全 PASS
- [ ] `PipelineConfig` に `anima_mode: AnimaMode` フィールドが存在
- [ ] `execute_anima_pipeline` が Cache/Ai/Hybrid で正しく分岐
- [ ] `load_throttle_config_at` がTOMLから正しくロード
- [ ] TOMLファイルなし時にデフォルト設定にフォールバック
- [ ] context.rs テスト期待値が value=50 → Neutral で正しい
- [ ] config.rs, lib.rs を変更していないこと
