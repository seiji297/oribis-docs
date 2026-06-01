# Embedded TTS Engine

## Overview

Oribisに組み込まれたローカルTTS（Text-to-Speech）エンジン。外部プロセスやHTTP APIに依存せず、Rustプロセス内で直接音声合成を実行する。

## 構成

```
src-tauri/src/tts/
├── mod.rs              # TTSモジュール統合
├── types.rs            # 共有型定義（TtsLanguage, TtsEngineChoice, etc.）
├── router.rs           # 言語判定→エンジン選択→音声合成
├── voicevox_core.rs    # VOICEVOX Core 0.16.4 FFI実装（日本語）
├── kokoro.rs           # Kokoro ONNX 自前実装（英語）
└── voice_defs.rs       # 音声スタイル定義（9種）

src-tauri/resources/
└── voicevox-core/
    └── n0.vvm          # VOICEVOX Nemoモデル（69.7MB）

models/kokoro/
├── model.onnx          # Kokoro ONNXモデル（310MB）
└── voices/
    ├── af_heart.bin    # 音声スタイルファイル（複数）
    └── ...
```

## アーキテクチャ

```
[Tauri Command: tts_generate]
  → TtsRouter::synthesize(request)
    → detect_language(text) → TtsLanguage
    → language_to_engine(lang) → TtsEngineChoice
    ├── Japanese/Unknown → voicevox_core::synthesize(text, style_id)
    │   └── VOICEVOX Core 0.16.4 (libvoicevox_core.so)
    │       ├── ONNX Runtime 初期化
    │       ├── OpenJTalk辞書読み込み
    │       ├── Synthesizer構築
    │       ├── n0.vvmモデル読み込み
    │       └── voicevox_synthesizer_tts() → WAV bytes
    └── English → kokoro::KokoroEngine::synthesize(text)
        └── ort Session (model.onnx)
            ├── テキスト→音素変換
            ├── トークン化
            ├── ONNX推論
            └── f32 samples → WAV bytes
```

## エンジン詳細

### VOICEVOX Core（日本語）

**実装方式**: `libloading` で `libvoicevox_core.so` を動的ロードし、新C APIを直接呼び出す。

**初期化フロー**:
1. `voicevox_make_default_load_onnxruntime_options()`
2. `voicevox_onnxruntime_load_once()` — ONNX Runtime読み込み
3. `voicevox_open_jtalk_rc_new()` — 辞書ディレクトリ指定
4. `voicevox_synthesizer_new()` — Synthesizer構築
5. `voicevox_voice_model_file_open()` — n0.vvmオープン
6. `voicevox_synthesizer_load_voice_model()` — モデル読み込み

**音声合成**:
- `voicevox_synthesizer_tts(synthesizer, text, style_id, options, &wav_len, &wav_ptr)`
- 出力: WAVフォーマット（PCM 16bit, 24kHz, mono）

**スレッド安全性**: `Mutex<VoicevoxRuntime>` で直列化。同時合成は排他。

### Kokoro（英語）

**実装方式**: `ort` crateでONNXモデルを直接推論。`kokoro-en` crateは不使用。

**モデル形式**:
- Input: `tokens` (i64[1, seq_len]), `style` (f32[1, 256]), `speed` (f32[1])
- Output: `audio` (f32[audio_length])

**音声合成フロー**:
1. テキスト→音素変換（簡易実装）
2. 音素→トークンID（vocabマッピング）
3. スタイルベクトル選択（voice packから）
4. ONNX Session推論
5. f32 samples → WAV 16bit PCM変換

**スレッド安全性**: `Arc<Mutex<Option<KokoroRuntime>>>` で排他。

## 音声スタイル

### VOICEVOX Nemo（9種）

| ID | 名前 | 性別 |
|----|------|------|
| 10005 | 女声1 | Female |
| 10007 | 女声2 | Female |
| 10004 | 女声3 | Female |
| 10003 | 女声4 | Female |
| 10008 | 女声5 | Female |
| 10006 | 女声6 | Female（デフォルト）|
| 10001 | 男声1 | Male |
| 10000 | 男声2 | Male |
| 10002 | 男声3 | Male |

### Kokoro Voices

| ファイル | 名前 | 言語 |
|----------|------|------|
| af_heart.bin | af_heart | American Female（デフォルト）|
| am_adam.bin | am_adam | American Male |
| bf_emma.bin | bf_emma | British Female |
| bm_george.bin | bm_george | British Male |
| ... | ... | ... |

## API

### Tauri Commands

- `tts_generate(request: TtsSynthesisRequest) -> Result<TtsSynthesisResponse, String>`
- `get_available_voices() -> Vec<VoiceDefinition>`
- `get_default_voice_id() -> u32`

### Rust Public API

```rust
// voicevox_core.rs
pub fn initialize() -> Result<(), OribisError>;
pub fn synthesize(text: &str, speaker_id: u32) -> Result<Vec<u8>, OribisError>;
pub fn is_initialized() -> bool;

// kokoro.rs
impl KokoroEngine {
    pub fn new() -> Self;
    pub async fn synthesize(&self, text: &str) -> Result<Vec<u8>, OribisError>;
}
```

## テスト

### 単体テスト

```bash
cargo test --lib tts
# 68 passed, 17 ignored
```

### 手動統合テスト

```bash
cargo test --test tts_manual -- --ignored --nocapture
```

生成ファイル:
- `/tmp/test_japanese.wav` — VOICEVOX日本語合成（104.5KB）
- `/tmp/test_english.wav` — Kokoro英語合成（164KB）
- `/tmp/test_voice_*.wav` — 9音声スタイル個別合成

## 依存関係

### Cargo.toml

```toml
libloading = "0.8"      # VOICEVOX Core動的ロード
ort = "2.0.0-rc.12"     # Kokoro ONNX推論
ndarray = "0.17"        # テンソル操作
hound = "..."           # WAV出力（既存）
```

### 削除したcrate

- `voicevox-dyn = "0.3.0"` — 古いVOICEVOX Core APIを使用していたため廃止
- `kokoro-en = "0.1.3"` — モデル形式非互合のため廃止

### システム依存

- `libvoicevox_core.so` — VOICEVOX Core 0.16.4ライブラリ
- `libvoicevox_onnxruntime.so.1.17.3` — ONNX Runtime
- `open_jtalk_dic_utf_8-1.11/` — OpenJTalk辞書

## 配布・リソース配置

### Tauri Resource

`src-tauri/resources/voicevox-core/n0.vvm` — Tauriの`ResourcePaths`でバンドル

### 実行時パス解決

```rust
let exe_path = std::env::current_exe()?;
let base_dir = exe_path.parent()?;
// Linux: target/debug/deps/c_api/lib/libvoicevox_core.so
//        target/debug/deps/onnxruntime/lib/libvoicevox_onnxruntime.so.1.17.3
//        target/debug/deps/dict/open_jtalk_dic_utf_8-1.11/
```

### モデルダウンロード

Kokoroモデル（310MB）は初回セットアップ時にダウンロード:
- `https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.onnx`
- `https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files/voices.bin`

## 既知の制約

1. **VOICEVOX Core**: Linuxのみ動作確認。Windows/macOSはライブラリ名/パス解決が未対応。
2. **Kokoro**: 英語のみ。日本語等の多言語には非対応。
3. **音素変換**: Kokoroは簡易的な英語音素変換を使用。espeak-ng未インストール環境では精度が低下。
4. **GPU**: 現状CPU推論のみ。CUDA EPは未検証。
5. **メモリ**: VOICEVOX Core初期化時に数百MBのメモリを消費。

## 変更履歴

| 日付 | 変更内容 |
|------|----------|
| 2026-06-01 | 初版作成。VOICEVOX Core 0.16.4カスタムFFI + Kokoro自前実装を統合 |
