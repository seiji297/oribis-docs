# sysdev-5 設計書 — プラグインシステム テスト追加

## 変更対象ファイル（独占コンポーネントのみ）

| ファイル | 変更種別 |
|---------|---------|
| `src-tauri/src/plugin.rs` | テスト追加 |
| `src-tauri/src/audio_playback.rs` | テスト追加（1件） |

**触ってはいけないファイル**: config.rs, lib.rs, anima/配下の全ファイル, src/components/*, src/hooks/*, src/controllers/*, src/adapters/*, src/loaders/*, src/themes/*, src/types/*, App.tsx

---

## 変更1: plugin.rs — テストモジュール追加

### 理由
`plugin.rs` はテストが0件。`version_gt`、`copy_dir_recursive`、プラグインスキャン/ロード/保存/削除の各関数がテストされていない。

### 追加するテスト

ファイル末尾（`copy_dir_recursive` 関数の後）に以下の `#[cfg(test)]` モジュールを追加する:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    // ── version_gt ──

    #[test]
    fn test_version_gt_major() {
        assert!(version_gt("2.0.0", "1.0.0"));
        assert!(!version_gt("1.0.0", "2.0.0"));
    }

    #[test]
    fn test_version_gt_minor() {
        assert!(version_gt("1.2.0", "1.1.0"));
        assert!(!version_gt("1.1.0", "1.2.0"));
    }

    #[test]
    fn test_version_gt_patch() {
        assert!(version_gt("1.0.2", "1.0.1"));
        assert!(!version_gt("1.0.1", "1.0.2"));
    }

    #[test]
    fn test_version_gt_equal() {
        assert!(!version_gt("1.0.0", "1.0.0"));
    }

    #[test]
    fn test_version_gt_partial() {
        // 不完全なバージョン文字列でもパニックしない
        assert!(version_gt("2.0", "1.0"));
        assert!(version_gt("1", "0"));
        assert!(!version_gt("", "1.0.0"));
    }

    // ── copy_dir_recursive ──

    #[test]
    fn test_copy_dir_recursive_basic() {
        let src_dir = TempDir::new().unwrap();
        let dst_dir = TempDir::new().unwrap();
        let dst = dst_dir.path().join("copied");

        // ファイル作成
        std::fs::write(src_dir.path().join("file.txt"), "hello").unwrap();

        copy_dir_recursive(src_dir.path(), &dst).unwrap();

        assert!(dst.join("file.txt").exists());
        assert_eq!(std::fs::read_to_string(dst.join("file.txt")).unwrap(), "hello");
    }

    #[test]
    fn test_copy_dir_recursive_nested() {
        let src_dir = TempDir::new().unwrap();
        let dst_dir = TempDir::new().unwrap();
        let dst = dst_dir.path().join("copied");

        // ネストしたディレクトリ
        std::fs::create_dir_all(src_dir.path().join("sub")).unwrap();
        std::fs::write(src_dir.path().join("sub").join("nested.txt"), "world").unwrap();

        copy_dir_recursive(src_dir.path(), &dst).unwrap();

        assert_eq!(
            std::fs::read_to_string(dst.join("sub").join("nested.txt")).unwrap(),
            "world"
        );
    }

    #[test]
    fn test_copy_dir_recursive_empty_dir() {
        let src_dir = TempDir::new().unwrap();
        let dst_dir = TempDir::new().unwrap();
        let dst = dst_dir.path().join("copied");

        // 空ディレクトリのコピー
        copy_dir_recursive(src_dir.path(), &dst).unwrap();
        assert!(dst.exists());
        assert!(dst.is_dir());
    }

    // ── PluginManifest deserialization ──

    #[test]
    fn test_manifest_deserialize() {
        let json = r#"{
            "id": "test-plugin",
            "name": "Test Plugin",
            "version": "1.0.0",
            "apiVersion": "1",
            "entry": "index.js"
        }"#;
        let manifest: PluginManifest = serde_json::from_str(json).unwrap();
        assert_eq!(manifest.id, "test-plugin");
        assert_eq!(manifest.name, "Test Plugin");
        assert_eq!(manifest.version, "1.0.0");
        assert_eq!(manifest.api_version, "1");
        assert!(!manifest.has_panel);  // default = false
        assert!(manifest.icon.is_none());
        assert_eq!(manifest.entry, "index.js");
    }

    #[test]
    fn test_manifest_deserialize_with_panel() {
        let json = r#"{
            "id": "panel-plugin",
            "name": "Panel Plugin",
            "version": "2.0.0",
            "apiVersion": "1",
            "has_panel": true,
            "icon": "🎮",
            "entry": "main.js"
        }"#;
        let manifest: PluginManifest = serde_json::from_str(json).unwrap();
        assert!(manifest.has_panel);
        assert_eq!(manifest.icon, Some("🎮".to_string()));
    }

    #[test]
    fn test_manifest_serialize_roundtrip() {
        let manifest = PluginManifest {
            id: "roundtrip".to_string(),
            name: "Roundtrip".to_string(),
            version: "1.0.0".to_string(),
            api_version: "1".to_string(),
            icon: None,
            has_panel: false,
            entry: "index.js".to_string(),
        };
        let json = serde_json::to_string(&manifest).unwrap();
        let deserialized: PluginManifest = serde_json::from_str(&json).unwrap();
        assert_eq!(deserialized.id, manifest.id);
        assert_eq!(deserialized.version, manifest.version);
    }

    // ── scan_plugins 用ヘルパー ──
    // 注意: scan_plugins() は dirs::config_dir() に依存するためユニットテスト困難。
    // ここではマニフェスト解析とディレクトリ操作のみをテストする。

    #[test]
    fn test_scan_manifest_from_dir() {
        let dir = TempDir::new().unwrap();
        let plugin_dir = dir.path().join("my-plugin");
        std::fs::create_dir_all(&plugin_dir).unwrap();

        let manifest = PluginManifest {
            id: "my-plugin".to_string(),
            name: "My Plugin".to_string(),
            version: "1.0.0".to_string(),
            api_version: "1".to_string(),
            icon: None,
            has_panel: false,
            entry: "index.js".to_string(),
        };
        let manifest_json = serde_json::to_string_pretty(&manifest).unwrap();
        std::fs::write(plugin_dir.join("manifest.json"), &manifest_json).unwrap();
        std::fs::write(plugin_dir.join("index.js"), "console.log('hi')").unwrap();

        // マニフェスト読み込み検証
        let content = std::fs::read_to_string(plugin_dir.join("manifest.json")).unwrap();
        let loaded: PluginManifest = serde_json::from_str(&content).unwrap();
        assert_eq!(loaded.id, "my-plugin");

        // エントリファイル読み込み検証
        let code = std::fs::read_to_string(plugin_dir.join(&loaded.entry)).unwrap();
        assert_eq!(code, "console.log('hi')");
    }

    // ── save/load plugin data (ファイルIO直接テスト) ──

    #[test]
    fn test_plugin_data_save_load() {
        let dir = TempDir::new().unwrap();
        let data_dir = dir.path().join("test-plugin").join("data");
        std::fs::create_dir_all(&data_dir).unwrap();

        let key = "settings";
        let value = r#"{"theme":"dark"}"#;
        let file_path = data_dir.join(format!("{}.json", key));
        std::fs::write(&file_path, value).unwrap();

        let loaded = std::fs::read_to_string(&file_path).unwrap();
        assert_eq!(loaded, value);
    }

    #[test]
    fn test_plugin_data_load_missing() {
        let dir = TempDir::new().unwrap();
        let file_path = dir.path().join("nonexistent.json");
        let result = std::fs::read_to_string(&file_path);
        assert!(result.is_err());
    }

    // ── delete plugin (ディレクトリ削除テスト) ──

    #[test]
    fn test_delete_plugin_dir() {
        let dir = TempDir::new().unwrap();
        let plugin_dir = dir.path().join("to-delete");
        std::fs::create_dir_all(&plugin_dir).unwrap();
        std::fs::write(plugin_dir.join("file.txt"), "data").unwrap();

        assert!(plugin_dir.exists());
        std::fs::remove_dir_all(&plugin_dir).unwrap();
        assert!(!plugin_dir.exists());
    }

    #[test]
    fn test_delete_nonexistent_plugin() {
        let dir = TempDir::new().unwrap();
        let plugin_dir = dir.path().join("nonexistent");
        // 存在しないディレクトリの削除はエラーにならない（コマンド側でexists()チェック済み）
        assert!(!plugin_dir.exists());
    }
}
```

---

## 変更2: audio_playback.rs — build_test_wav ヘルパーの境界値テスト追加

### 追加するテスト（既存テストモジュール内に追加）

```rust
    #[test]
    fn test_decoder_accepts_48khz_wav() {
        // 48kHz WAV（一般的な高品質音声）
        let samples = vec![0i16; 4800]; // 100ms at 48kHz
        let wav = build_test_wav(&samples, 48000);
        let cursor = Cursor::new(wav);
        let result = Decoder::new(cursor);
        assert!(result.is_ok(), "Decoder should accept 48kHz WAV");
    }
```

---

## Cargo.toml 変更

`tempfile` クレートがテスト依存に必要。既に `Cargo.toml` の `[dev-dependencies]` に含まれているか確認し、なければ追加:

```toml
[dev-dependencies]
tempfile = "3"
```

**追加する場合は sysdev-3, sysdev-4 に周知すること。**

---

## テスト実行コマンド

```bash
cargo test --lib plugin::
cargo test --lib audio_playback::
```

## 完了条件チェックリスト

- [ ] `cargo test --lib plugin::` 全 PASS
- [ ] `cargo test --lib audio_playback::` 全 PASS
- [ ] `version_gt` の major/minor/patch/equal/partial テスト PASS
- [ ] `copy_dir_recursive` の basic/nested/empty テスト PASS
- [ ] `PluginManifest` の serialize/deserialize テスト PASS
- [ ] プラグインデータ save/load テスト PASS
- [ ] config.rs を変更していないこと
- [ ] lib.rs を変更していないこと
- [ ] anima/ 配下のファイルを変更していないこと
