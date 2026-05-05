# oribis Windows版インストーラー設計（案）

## 概要

一般Windowsユーザー向けの配布インストーラー。ネイティブTauriビルド（.msi）。

---

## インストーラーフロー

1. **oribis本体インストール**
2. **AIバックエンド選択**（後述）
3. **VOICEVOX インストール**（任意チェックボックス）
4. **完了 → oribis起動**

---

## AIバックエンド選択肢

| 選択肢 | 推奨度 | 課金 | 備考 |
|--------|--------|------|------|
| Codex CLI | ★ 推奨 | ChatGPT Pro定額 | デフォルトチェック |
| Bonsai 9B（llama.cpp） | 無料・オフライン | なし | GPU前提 |
| Claude CLI | ⚠ 非推奨 | Claude Max定額 | デフォルト未チェック |

### Claude CLI注意書き（案）
> ⚠️ **Claude CLI** *(非推奨)*
> 利用規約の都合上、予告なく制限される場合があります。
> ご理解のうえ自己責任でご利用ください。

---

## 初回起動時セットアップ

- CLI未認証チェック → 未認証なら誘導画面表示
- Codex: `codex login --device-auth` → ブラウザOAuth
- Claude: 同様のOAuthフロー
- Bonsai: llama-serverパス・モデルパス設定画面

---

## STT（音声入力）

- **Windows版**: `Windows.Media.SpeechRecognition` WinRT API（UI非表示・プログラム制御）
- **Linux版**: faster-whisper継続
- `#[cfg(target_os = "windows")]` でビルド時切り替え

---

## TTS

- VOICEVOX（任意インストール）
- デフォルトキャラ: 東北きりたん（speaker_id: 108）
- VOICEVOX本体に標準同梱 → 別途キャラDL不要

---

## 未解決課題

- llama-serverパスのハードコード問題 → 設定ファイル化が必要（Windows配布前）
- Bonsai 9Bモデルファイル（GBクラス）→ インストーラー内包不可、別途DL誘導

---

## 未実装

- インストーラー本体（NSIS/WiX）
- WinRT STT実装
- 初回起動セットアップ画面
