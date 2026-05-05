# プラットフォーム知見

## Android対応 — ペンディング課題

現状: `#[cfg(not(target_os = "android"))]` Rust条件コンパイル + `isMobile` フロントエンド分岐 実装済み（`ui-fix-2`）。

**ペンディング（次回 Android リリースタイミングで対応）:**
- [ ] Android SDK / NDK セットアップ
- [ ] `npx tauri android init`
- [ ] `npx tauri android build --apk`
- [ ] 縦長 UI レイアウト修正
- [ ] Android向けタッチUI調整

**方針（2026-05-01）:** main 開発はデスクトップ専用。大きなリリースごとに Android 対応パス実施。将来 C-Prime方式（PC=サーバー、Android=クライアント）移行検討。

---

## WSLg 環境注意事項

### ウィンドウ位置（Wayland問題）

WSLg は `WAYLAND_DISPLAY=wayland-0` を設定 → GTK が Wayland バックエンドで起動 → Wayland ではクライアントがウィンドウ位置指定不可 → `window.center()` 無視される。

**症状**: 毎回ウィンドウが画面上部（0,0付近）に出現。

**対処**: `run()` 先頭で `GDK_BACKEND=x11` 設定 → XWayland（X11）モードで起動 → `center()` 機能する。

```rust
#[cfg(target_os = "linux")]
if std::env::var("GDK_BACKEND").unwrap_or_default().is_empty() {
    std::env::set_var("GDK_BACKEND", "x11");
}
```

`tauri.conf.json` の `"center": true` + setup の `window.center()` はこの設定があって初めて機能する。

---

## ビルド注意事項

- TypeScript strict mode: `string | null` を input の `value` に渡すと型エラー → `?? ""` で null 合体
- `settings.json` trailing comma は JSON パースエラーになる → 追加後は `python3 -c "import json; json.load(open(...))"` で確認
