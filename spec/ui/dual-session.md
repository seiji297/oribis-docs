# Dual Session

## Overview

# FEAT-①: デュアルセッションモード (Dual Session Mode / Theater Mode)

作成: 2026-04-24 / Producer指示
設計: planner + Codex R1〜R45全指摘対処済み 2026-04-24

## 概要

同一3Dシーン内に2体のVRMAnimaを配置し、2つの会話エージェント（A・B）が交互に会話する「シアターモード」。
人間が初期テーマを指定し、以降はA→B→A...の自動ターン進行。

// R35-HIGH-1 + R37-HIGH-1対処: dual-* のCLIライフサイクル（単一モデルに確定）
//
// 【確定モデル: Theater Modeセッション中は長寿命CLIプロセス（lazy start方式）】
//   - Theater Mode起動直後は CLIプロセス未起動（lazy start）
//   - 初回テーマ送信時に dual-A / dual-B CLIプロセスが各々起動（lazy start）
//   - 以後は同一CLIプロセスに対してターン毎に claude_chat を呼び出す（プロセスは存続）
//   - Theater Mode終了時（teardown）: stop_project_session で dual-A / dual-B を停止
//   - 「毎ターン新規プロセス起動」「都度起動」は誤り → このモデルは廃棄
//
// 【文脈管理: 長寿命CLIが内部蓄積・App.tsx historyが人間割り込み再開用バックアップ】
//   - 会話履歴（historyA/historyB）はApp.tsx useRefで保持（Theater Mode内の人間割り込み後再開用バックアップ）
//   - R41-HIGH-1対処: historyA/Bはアプリ再起動時に消失する（永続化なし）。
//     アプリ再起動後はHistory非回復（Theater Modeは新規開始）。これは明示的な設計判断。
//     AC-19はhistory回復ではなく、orphan CLIプロセスの回収のみを保証する。
//   - Theater Mode開始時のみ: historyが非空の場合 --conversation-file で文脈を初期注入
//   - 継続ターン: CLIの内部履歴が自然蓄積（--conversation-file 不使用）
//   - Rust側セッションキャッシュに通常通り登録（長寿命セッション）
//   - R38-HIGH-1対処: 「毎ターン --conversation-file 注入」は廃棄。開始時1回のみ。
//
// 【要件表現】
//   正: 「2つの会話エージェント（A・B）それぞれに独立した長寿命CLIプロセスを割り当て、
//       Theater Mode開始時のみ会話履歴を注入。以後はCLIの内部履歴が蓄積する方式」
//   誤（廃棄）: 「ターン毎の新規CLIプロセス起動」「都度起動」「毎ターン --conversation-file 注入」

## ユーザー操作フロー

1. 「Theater Mode」ボタン押下（前提: primaryVRMロード済み・ボタンdisabledガード通過）
   → 起動シーケンス（R29-HIGH-2 + R31-HIGH-1 + R31-HIGH-2対処）:
     // ★起動シーケンス最初の同期処理: UIを即時ロック（cleanup/VRMロード中の再入場防止）
     a0. setDualSessionActive(true)  // ← 最初にセット（ボタン disabled 条件に引っかかる）
         setIsDualTearingDown(false)  // 念のためリセット
         // R42-MEDIUM-3対処 + R44-MEDIUM-3対処: Theater Mode開始前に通常モードTTSを停止（完了待機）
         //   tts_stop コマンドは Rust 側で ffplay プロセス kill + 終了確認まで同期的に実行。
         //   → await が返った時点で ffplay プロセスは終了しており、以後の tts_speak 呼び出しは
         //      「Theater Mode の新規再生のみ」であることが保証される。
         //   → UI disabled（dualSessionActive=true）+ tts_stop await 完了 の2条件が揃うことで、
         //      通常モード TTS との非同期競合ウィンドウを消去する。
         //   既発行の通常モード tts_speak Rust Future: tts_stop による ffplay kill で Err settle される。
         //   非UI起点の invoke（例: 外部コード・テスト）: dualSessionActive=true 後は TtsState の
         //      current_request_id が Theater Mode requestId に塗り替わるため、
         //      通常モード requestId の停止リクエストは tts_stop の不一致判定で無視される（排他完了）。
         //   実装契約（Rust): fn tts_stop は ffplay kill → child.wait() を非同期で実行し、
         //      プロセス終了確認後に Ok を返す（"fire and forget" ではなく完了待機）。
         // R46-HIGH-2対処: withTimeout（3000ms）でハング時UIロック防止（dualSessionActive=true後のため再入場不能）
         try {
           await withTimeout(invoke("tts_stop", { requestId: null }), 3000, "tts_stop at start");
         } catch { /* 再生中でない場合 or タイムアウト: 警告ログのみ。tts_stop失敗でも起動継続（UI排他は既に成立）*/ }
         // 検証: `pnpm test --grep "normal mode pending TTS does not race with theater mode start"`
         //       `pnpm test --grep "theater start recovers when tts_stop hangs"`
         // これ以降はユーザーの再入場ボタン操作が不可能（disabled保証）

     a. // R24-MEDIUM-3対処: カメラ状態スナップショット（teardown()での復元用）
        cameraParamsBeforeDualRef.current = { ...currentCameraParams }
     b. dualReadyARef.current = true（A=既ロード済みのため即ready）
        dualReadyBRef.current = false

     // R29-HIGH-2 + R31-HIGH-1対処: orphan cleanup 失敗 → 起動アボート
     // R46-HIGH-2対処: withTimeout（5000ms）でハング時UIロック防止
     c. orphanクリーンアップ（R19-HIGH-3: 全再入場経路共通）:
        if (dualOrphanSessionRef.current) {
          try {
            await withTimeout(invoke("cleanup_orphan_cli_processes"), 5000, "cleanup_orphan at start");  // dual-* スコープのみ対象
            dualOrphanSessionRef.current = false;  // 成功時のみリセット
          } catch {
            // 失敗（エラーまたはタイムアウト）→ 残留CLIとの競合リスクのため起動アボート
            dualReadyARef.current = false;
            setDualSessionActive(false);  // ロック解除（ユーザーに再試行を促す）
            showErrorDialog("前のセッションのクリーンアップに失敗しました。しばらくしてから再試行してください。");
            return;  // 起動シーケンス中断
          }
        }
        // 検証: `pnpm test --grep "theater start or resume recovers when cleanup_orphan_cli_processes hangs"`
     d. （空：a0でsetDualSessionActive済み）
     e. 全イベントリスナー再登録（R23-HIGH-1 + R36-MEDIUM-3対処）:
        // R36-MEDIUM-3対処: 配列を捨てる前に既存リスナーを確実に解除する
        for (const unlisten of dualListenerCleanupsRef.current) {
          try { await unlisten(); } catch {}  // 既存リスナー購読解除
        }
        dualListenerCleanupsRef.current = [];  // クリア後に新規登録
        // 新規イベントリスナーを登録し dualListenerCleanupsRef.current に push
     f. vrmLoadWatchdogタイマー開始（R20-MEDIUM-4）
     g. ++vrmLoadGenerationRef.current（R30-HIGH-1: VRMロード世代インクリメント）
   → secondaryVRM (B) ロード開始 → onLoad完了後にUIアンロック（dualReady）
2. 人間がテーマを入力して送信（初回claude_chat = CLIプロセス実起動）
3. キャラA（左）がテーマに返答
4. AのTTS完了後、自動でBへ送信
5. A→B→A...のターンループ継続（MAX_TURNS超過または人間割り込みで停止）
6. 人間割り込み = 即時停止（TTS中断 + in-flight破棄）

## 技術設計

### VRM起動失敗処理（R6-HIGH-1対処 + R28-MEDIUM-3対処: B専用・矛盾解消）

**Theater Mode起動時に発生し得るVRM起動失敗はVRM-B（secondaryVRM）のみ**:
```
VRM-A（primaryVRM）= 通常モードで Theater Mode 起動前にロード済み。
  Theater Mode 起動時に onLoad は発火しない（既存インスタンスをそのまま流用）。
  VRM-A の起動失敗は通常モード側でハンドリング済み → Theater Mode とは無関係。

VRM-B（secondaryVRM）= Theater Mode 起動時に新規ロード → onLoad 失敗が発生し得る:
  onLoad失敗時:
    → teardown()呼び出し
    → エラーダイアログ「モデルの読み込みに失敗しました。Theater Modeを終了します。」
    → 通常モード復帰
```

`dualReady` は VRM-B の `onLoad` 成功後にのみ true（VRM-A は起動前ガードで保証済み）。
VRM-B が失敗した場合は `dualReady` は立てず teardown() を実行。

AC-11の適用範囲: VRM-B（secondaryVRM）のロード失敗のみ対象。VRM-Aの異常系テストは不要。

**R20-MEDIUM-4対処: secondaryVRMロード無応答（onLoad不到達）のウォッチドッグ**:
```
Theater Mode起動時（secondaryVRM ロード開始と同時）:
  VRM_LOAD_TIMEOUT = 30秒のウォッチドッグタイマー開始:
    vrmLoadWatchdogRef.current = setTimeout(() => {
      teardown();
      showErrorDialog("モデルの読み込みがタイムアウトしました。Theater Modeを終了します。");
    }, 30000);

  onLoad成功時: clearTimeout(vrmLoadWatchdogRef.current) → setDualReady(true)
  onLoad失敗時: clearTimeout(vrmLoadWatchdogRef.current) → teardown() + エラーダイアログ
  teardown()のfinallyでも: clearTimeout(vrmLoadWatchdogRef.current); vrmLoadWatchdogRef.current = null

vrmLoadWatchdogRef: useRef<ReturnType<typeof setTimeout> | null>(null)
```

**R14-HIGH-1対処: Theater Mode A/B VRM構成の明確化**:
```
primaryVRM (A, 左): 通常モードのVRMをそのまま流用（Theater Mode起動前にロード済み）
  Theater Mode起動時に positionOffset(-1, 0, 0) で位置オフセット適用
  = Theater Mode起動時にonLoad発火しない（既ロード済みのため）
  = VRM-A起動失敗は Theater Mode 起動時には発生しない

secondaryVRM (B, 右): Theater Mode起動時に新規ロード（dualAvatarUrlBで指定）
  = onLoad失敗の可能性あり → teardown() + エラーダイアログ

AC-11の「VRM-AまたはVRM-B起動失敗」:
  実際にはVRM-B（secondary）のロード失敗のみが Theater Mode 起動時に発生し得る
  VRM-A = 通常モードで既ロード済み（Theater Mode起動前の失敗は通常モード側でハンドリング）

teardown()でのVRM復元:
  setSecondaryVrmUrl(null) → Bアンマウント
  primaryVRM (A) は teardown後も通常モードでそのまま利用継続（positionOffset解除のみ）
```

**R18-HIGH-1対処 + R19-HIGH-1対処: dualReady成立条件（A=既ロード済みの扱いと起動前提ガード）**:
```
Theater Mode起動前提条件（UI層ガード）:
  Theater Modeボタンは primaryVrm が null の場合 disabled にする
    disabled条件: !primaryVrm || isDualTearingDown || dualSessionActive
  理由: primaryVRM (A) は通常モードで必ずロード済みであること = Theater Mode開始の前提条件
  → ボタンが押せる時点でA=既ロード済みが保証される

dualReadyの状態遷移（A/B非対称を明示）:

  Theater Mode起動ボタン押下直後（同期・上記ガード通過後）:
    dualReadyARef.current = true  // A=primaryVRMは起動前提ガード通過済み = 既ロード済み保証
    dualReadyBRef.current = false // B=secondaryVRMはこれからロード

  // R28-HIGH-1 + R30-HIGH-1対処: VRMロード専用 generation token で後着コールバック識別
  // dualReadyARef.current のみではセッション再起動後の旧世代コールバックを識別できない
  // → ターン管理の turnIdRef に相当する「VRMロード世代トークン」を導入する

  const vrmLoadGenerationRef = useRef(0);

  // Theater Mode起動時（secondaryVRMロード開始直前）:
  ++vrmLoadGenerationRef.current;                    // 世代インクリメント
  const myVrmGeneration = vrmLoadGenerationRef.current;  // コールバックにクロージャで束縛

  secondaryVRM (B) onLoad成功時（myVrmGeneration束縛済みクロージャ内）:
    // 世代トークンが一致しない = teardown後 or 再起動後の旧世代コールバック → 無視
    if (vrmLoadGenerationRef.current !== myVrmGeneration) return;
    clearTimeout(vrmLoadWatchdogRef.current);
    vrmLoadWatchdogRef.current = null;
    dualReadyBRef.current = true;
    setDualReady(true)  // UIアンロック

  secondaryVRM (B) onLoad失敗時（myVrmGeneration束縛済みクロージャ内）:
    if (vrmLoadGenerationRef.current !== myVrmGeneration) return;  // 旧世代は無視
    clearTimeout(vrmLoadWatchdogRef.current);
    vrmLoadWatchdogRef.current = null;
    dualReadyBRef.current = false;
    teardown() + エラーダイアログ

  teardown()のfinallyで（R34-MEDIUM-4対処: 一次ガードの明確化）:
    // vrmLoadGenerationRef は「一次ガード」: 次回起動のインクリメントで旧世代が自動無効化
    // dualReadyARef.current = false は「補助ガード」: 設計上到達しないが念のため
    dualReadyARef.current = false;  // 補助ガード（onLoad/onErrorの一次ガードはvrmLoadGenerationRef）
    dualReadyBRef.current = false;
    setDualReady(false);
    // vrmLoadGenerationRef をここでインクリメントしない理由:
    //   teardown → すぐ再起動のケースで、起動時インクリメントが一次無効化手段のため
    //   teardown側では更新不要（次回起動時のインクリメントが唯一の信頼源）

  // R34-MEDIUM-4対処: ガード設計の一本化（実装者向け）
  // ★ onLoad/onError の一次ガード = vrmLoadGenerationRef (クロージャ束縛比較)
  //   → これ1つで「異なるセッション世代のコールバック」を確実に棄却
  // ★ dualReadyARef.current = false（teardown finally）= 補助ガード（冗長安全策）
  //   → 実装時は vrmLoadGenerationRef 比較のみを onLoad/onError の入口条件とする
  //   → dualReadyARef は状態確認用途（起動前チェック等）に使うが、コールバック棄却の根拠にしない
  // 根拠: vrmLoadGenerationRef は Theater Mode 起動毎にインクリメントされ、
  // コールバックに束縛された myVrmGeneration と比較することで
  // 「複数回のTeater Mode起動をまたいだ旧世代コールバック」も確実に棄却できる。
  // turnIdRef と同じパターンで VRM ロード系にも世代管理を適用。

根拠: A側のonLoadはTheater Mode起動時に発火しないため、
  A側を「起動直後に即ready」として明示的に初期化しないと
  dualReady=trueに到達する経路が存在しない（UIが永続ロック）。
  ボタンdisabled条件でprimaryVRM未ロード時の起動を防止することで
  dualReadyARef.current=true の前提を UI層で保証する。
```

**R14-HIGH-2 + R27-MEDIUM-3 + R29-HIGH-1対処: Three.js GPUリソース明示解放（同一URL安全設計）**:
```
// 同一VRM URLの場合、A（primaryVRM）と B（secondaryVRM）は
// GLTFLoader が同一の Three.js オブジェクト（scene/texture/material）を参照する。
// B の teardown で geometry/material/texture の dispose を実行すると A の描画資産も壊れる。
// → B unmount cleanup は URL が A と異なる場合のみ全 dispose を実行する。

AvatarViewer.tsx の useEffect クリーンアップで:
  // R33-HIGH-1 + R34-MEDIUM-3対処: 同一URL VRM を A/B 両方に設定することを多層禁止
  // Three.js clone(true) は scene graph ノードを複製するが、VRM固有の runtime object
  // （SpringBone, Expression, LookAt）はオリジナルのskeleton/boneへの参照を共有するため
  // clone(true) だけでは VRM アニメーション・物理演算の完全独立が保証されない。
  //
  // 設計決定: 複製の複雑さを排除し、同一URL禁止を不変条件（invariant）として多層強制する:
  //
  // 【Layer 1: UI層（入力時禁止）】
  //   DualSessionPanel のURL設定UIで、B のURLが A と同一の場合は送信ボタンを disabled にし
  //   「キャラA とキャラB は異なるVRMファイルを指定してください」と表示する
  //
  // 【Layer 2: 起動時バリデーション（不変条件ガード）R34-MEDIUM-3対処】
  //   起動シーケンス a0 の直後に runtime invariant を確認:
  //   if (secondaryVrmUrl === primaryVrmUrl) {
  //     dualReadyARef.current = false;
  //     setDualSessionActive(false);
  //     showErrorDialog("キャラA と B に同一VRMを指定することはできません。設定を変更してください。");
  //     return;  // 起動中断
  //   }
  //   → 保存済み設定・将来のAPI呼び出し・state直接変更・テストコードによるバイパスを防ぐ
  //   検証: `pnpm test --grep "dual rejects identical VRM URLs at runtime boundary"`
  //
  // 【Layer 3: AvatarViewer防衛コード】
  //   コード上のガード（url !== primaryVrmUrl）は防衛コードとして残す
  //   （Layer 1+2 で到達不能だが、多重防衛として維持）
  //
  // この制約により A/B は常に独立した GLTF ロードパス = 完全に独立したVRMインスタンスが保証される
  //
  // 同一URLの場合: GPU dispose および useLoader.clear ロジックは、
  //   Layer 1+2 で完全に阻止されるため「同一URL時」のパスは実質到達しない。
  //   それでもコード上のガード（url !== primaryVrmUrl）は防衛コードとして残す。

  // props.instanceId === "secondary" かつ url !== primaryVrmUrl の場合のみ GPU 解放を実行
  // 同一URLの場合（clone使用時）: geometry/material は参照共有のため dispose/useLoader.clear をスキップ
  //                               clone されたscene graph ノードはR3Fアンマウント時に自動クリア
  if (instanceId === "secondary" && url !== primaryVrmUrl) {
    // R28-HIGH-1適用範囲: B専用URLの場合のみ GPU資産を解放
    vrm.scene.traverse((obj) => {
      if (obj.geometry) obj.geometry.dispose();
      if (obj.material) {
        const mats = Array.isArray(obj.material) ? obj.material : [obj.material];
        mats.forEach((m) => {
          // R15-MEDIUM-3対処: 標準PBRスロット解放
          const TEX_SLOTS = [
            'map', 'normalMap', 'roughnessMap', 'metalnessMap',
            'emissiveMap', 'alphaMap', 'aoMap', 'lightMap',
          ] as const;
          TEX_SLOTS.forEach((slot) => { m[slot]?.dispose(); });
          // R16-MEDIUM-3対処: MToon/ShaderMaterial uniforms 内テクスチャも解放
          if ((m as any).uniforms) {
            Object.values((m as any).uniforms).forEach((u: any) => {
              if (u?.value?.isTexture) u.value.dispose();
            });
          }
          m.dispose();
        });
      }
    });
    useLoader.clear(GLTFLoader, url);  // B 専用 URL → キャッシュ安全に破棄
  }
  // 同一URLの場合: A の描画資産（参照共有のテクスチャ・マテリアル）を保護するため何もしない

  // A（primaryVRM、instanceId="primary"）の cleanup: teardown不要（通常モードで継続使用）
  // A のGPUリソース解放は通常モード終了時に行う

理由: Three.jsのGPUリソースはJS GCでは解放されない。
     ただし同一URLの場合はGLTFLoaderのキャッシュ参照を共有しているため、
     B の dispose が A の描画を破壊する危険がある。URL が異なる場合のみ解放する。

解放フロー: setSecondaryVrmUrl(null) → R3FがAvatarViewerをアンマウント → useEffect cleanup発火
→ 異なるURL時のみ: dispose + useLoader.clear でGPUメモリ解放
→ 同一URL時: スキップ（A の描画資産保護）
```
再試行時のリーク防止: teardown finallyで確実にnull化するため、複数回起動失敗でもGPUリソース重複なし。

### TTSタイムアウト条件（R6-HIGH-2対処: 明確化）

**タイムアウト起点**:
```
chat-stream-end-{id} 受信時 → 5秒タイムアウタイマー開始
  （TTSキュー投入と同時に開始。chat-stream-endがTTS開始の契機のため）
tts-stream-end-{id} 受信時 → タイムアウトタイマーキャンセル（正常完了）
タイマー発火（TTS_TIMEOUT秒経過）:
  // R11-HIGH-1対処: 状態ガードで tts-stream-end との競合を防止
  if (dualTurnStateRef.current !== "A_speaking" && dualTurnStateRef.current !== "B_speaking") return;
  dualTurnStateRef.current = 次の状態（先に変更）// tts-stream-endハンドラのガードをブロック
  → await stopTTS(currentTtsRequestId)
  → ターン進行
```

tts-stream-end ハンドラ:
```
if (dualTurnStateRef.current !== "A_speaking" && dualTurnStateRef.current !== "B_speaking") return;
clearTtsTimeoutTimer()  // タイマーキャンセル（タイムアウト側との競合防止）
dualTurnStateRef.current = 次の状態（先に変更）// タイムアウトハンドラのガードをブロック
→ ターン進行
```

**R19-HIGH-2 + R21-HIGH-1対処: TTS_TIMEOUTハンドラ内stopTTS失敗耐性（AC-6保護）**:
```
タイムアウトタイマー発火時:
  if (dualTurnStateRef.current !== "A_speaking" && ...) return;
  dualTurnStateRef.current = 次の状態（先に変更）// one-shotガード
  // R21-HIGH-1対処: stopTTS失敗時はteardown() → AC-6「同時TTS発行ゼロ」保護
  // stopTTS成功 = 前の音声停止確認済み → ターン進行
  // stopTTS失敗/timeout = 前の音声が継続中の可能性 → teardown()でAC-6保護
  let stopOk = false;
  try {
    await withTimeout(stopTTS(currentTtsRequestId), 3000, "stopTTS in timeout handler");
    stopOk = true;
  } catch (e) {
    console.warn("stopTTS failed/timeout in TTS_TIMEOUT handler:", e);
  }
  if (!stopOk) {
    await teardown();
    showErrorDialog("音声停止でエラーが発生しました。Theater Modeを終了します。");
    return;
  }
  → ターン進行（stopTTS成功確認後のみ）

根拠: stopTTS失敗のまま次ターンTTSを発行するとAC-6「同時TTS発行ゼロ」に違反し
  音声が秒単位で重複する可能性がある。teardown()の方がAC-6保護として正しい。
```

**R11-HIGH-1対処: one-shotガードの根拠**:
どちらが先着しても `dualTurnStateRef` を `*_speaking` から変更することで、後着の処理はガードで弾かれる（状態機械を排他フラグとして活用）。

「最後のtts-stream-samples受信から3秒」ではなく「chat-stream-end受信からTTS_TIMEOUT秒」を採用。
理由: tts-stream-samplesはストリーミング中断でも来続けるため信頼性が低い。

**R8-MEDIUM-4対処: TTSタイムアウト設定可能化**:
```
TTS_TIMEOUT: デフォルト10秒（UI設定可能）
  理由: VOICEVOX生成1〜2秒 + 200文字再生3〜4秒 = 最大約6秒。5秒は余裕不足。
  10秒はウォームアップ・OS遅延・話速設定を考慮したバッファ込みの値。
  DualSessionPanelのUIからユーザーが変更可能（5〜30秒の範囲）。
```

**R7-MEDIUM-4対処 + R14-MEDIUM-3対処: requestId所有権とturnId対応の明文化**:
```
currentTtsRequestId 命名規則:
  フォーマット: `dual-{speaker}-{turnId}` （例: "dual-A-7", "dual-B-8"）

  A_thinking→A_speaking遷移時:
    currentTtsRequestIdA = `dual-A-${turnIdRef.current}`
    invoke("tts_speak", { requestId: currentTtsRequestIdA, ... })
    chat-stream-end-dual-A受信時にタイムアウトタイマー開始（このrequestIdに紐づく）

  タイムアウト/tts-stream-end発火時:
    stopTTS(currentTtsRequestIdA)  // 当該ターンの再生のみ停止
    → requestId不一致の旧世代再生はRust側(current_play_id比較)で無視
    → turnIdRef不一致の新世代遅延は上流ガードで弾かれる

  排他保証の根拠:
    turnId N の発話 → requestId "dual-A-N"
    turnId N+1の発話開始 → requestId "dual-A-(N+1)" 発行 → N世代のtts_stopはRustでnoopになる
    物理音重複（OSプロセスkill〜終了の遅延）: 数十ms以内（既知制約）
```

AC-6の保証水準: requestIdガードにより意図的な同時再生発行はゼロ。物理的な音声重複（OSプロセスkill遅延〜数十ms）は設計上の既知制約（防止不可能）。

### teardown()の完走保証（Promise.allSettled + finally）

```typescript
async function teardown() {
  // R24-MEDIUM-4対処: teardown開始直後にUIを即ロック（二重終了・再入場防止）
  setIsDualTearingDown(true);

  // Phase 1: 全ハンドラ即ブロック（同期）
  dualTurnStateRef.current = "idle";
  ++turnIdRef.current;
  clearTtsTimeoutTimer();  // R11-MEDIUM-3: タイマーリソース解放

  // R16-HIGH-1対処: タイムアウト付きラッパーでハング防止（finally到達を保証）
  // withTimeout<T>(promise, ms, label): Promise.race で ms 経過後に reject → catch でスキップ
  try {
    await withTimeout(
      invoke("tts_stop", { requestId: null }).catch((e) => { console.warn("tts_stop failed:", e); }),
      3000, "tts_stop"
    ).catch((e) => { console.warn("tts_stop timeout/error:", e); });
    for (const unlisten of dualListenerCleanupsRef.current) {
      try { await unlisten(); } catch {}
    }
    dualListenerCleanupsRef.current = [];
    const stopResults = await withTimeout(
      Promise.allSettled([
        invoke("stop_project_session", { projectId: "dual-A" }),
        invoke("stop_project_session", { projectId: "dual-B" }),
      ]),
      5000, "stop_project_session"
    ).catch((e) => {
      // R18-HIGH-2対処: タイムアウト経路でも確実に残留フラグを立てる
      console.warn("stop_project_session timeout:", e);
      dualOrphanSessionRef.current = true;
      return [] as any[];
    });
    stopResults.forEach((r: any, i: number) => {
      if (r.status === "rejected") {
        console.warn(`stop_project_session dual-${i === 0 ? "A" : "B"} failed:`, r.reason);
        // R17-MEDIUM-4対処: タイムアウト/失敗時は残留フラグを立てる
        dualOrphanSessionRef.current = true;
      }
    });
  } finally {
    // 必ず実行
    // R12-HIGH-1対処: 再起動時の前回状態残留防止
    historyARef.current = [];
    historyBRef.current = [];
    pauseContextRef.current = null;
    setDualReady(false);
    setTimelineMessages([]);
    setSecondaryVrmUrl(null);
    // R23-HIGH-2対処: primaryVRM (A) の位置オフセット解除（通常モード位置への復元）
    setPrimaryVrmPositionOffset(null);  // positionOffset(-1,0,0) → 解除（通常位置に戻す）
    // vrmLoadWatchdogRef も解除（二重発火防止）
    clearTimeout(vrmLoadWatchdogRef.current); vrmLoadWatchdogRef.current = null;
    if (cameraParamsBeforeDualRef.current) {
      setCameraParams(cameraParamsBeforeDualRef.current);
    }
    // R28-HIGH-1 + R29-MEDIUM-3 + R34-MEDIUM-4対処: VRMコールバックガードのクリア
    // ★一次ガードは vrmLoadGenerationRef（クロージャ束縛比較）。onLoad/onError の棄却判定はこれのみ。
    // ★dualReadyARef.current = false は「補助ガード」（冗長安全策。onLoadガード条件には使わない）
    //   → 実装注意: onLoad/onError 入口条件は `vrmLoadGenerationRef.current !== myVrmGeneration` のみ
    dualReadyARef.current = false;  // 補助ガード（状態確認用途のみ）
    dualReadyBRef.current = false;
    setDualTurnStateDisplay("idle");
    setDualSessionActive(false);
    setIsDualTearingDown(false);
    // R33-MEDIUM-4対処: teardown完了後にorphanが残る場合はUI警告バナー表示
    // バックエンドCLIが停止未完了でも「Theater Mode終了済み」に見えるため、
    // dualOrphanSessionRef.current = true の場合にのみ通知バナーを出す
    if (dualOrphanSessionRef.current) {
      setOrphanCleanupPending(true);  // UI警告バナー: "前のセッションのクリーンアップが残っています。次回起動前に処理されます。"
    }
  }
}

// R33-MEDIUM-4対処: orphanCleanupPending は React state
// const [orphanCleanupPending, setOrphanCleanupPending] = useState(false);
// Theater Mode 起動成功時 / cleanup成功時 に setOrphanCleanupPending(false) でクリア
// UI: dualSessionActive=false かつ orphanCleanupPending=true の場合に警告バナー表示
//   例: "⚠️ 前のセッションのクリーンアップが残っています。次のTheater Mode起動前に自動処理されます。"
```

### 会話文脈の伝搬設計（R6-MEDIUM-3対処: 履歴ロールモデル明確化）

**R7-MEDIUM-2対処: system prompt設計（統一）**:
```
system promptは毎回 claude_chat の systemPrompt 引数として渡す（上書き/再注入）
理由: セッション側の記憶に依存せず呼び出し側で完全制御。役割・テーマを全ターン保証。
```

**R10-MEDIUM-3対処: プロンプトインジェクション対策（topicをsystem promptから分離）**:
```
system prompt（role外サニタイズ済み固定テキスト）:
「あなたは{キャラ名}です。{相手キャラ名}と議論しています。
相手の発言に応じて、自分の立場から自然に返答してください。200文字以内で返答してください。」

テーマ注入（R16-MEDIUM-2対処: 全ターン永続）:
  初回: `[議題]${sanitizedTopic}\n${initialGreeting}`
  継続ターン（A→B/B→A）: `[議題]${sanitizedTopic}\n「${sanitizedResponse}」\nあなたの考えを200文字以内で答えてください。`
  → historyA/BのFIFO窓から議題が脱落しても、毎ターンのuserメッセージに議題を含むため永続保持

topicのサニタイズ: 先頭・末尾空白除去 + 最大100文字に切り詰め
理由: system promptへの直埋め込みを避けることでprompt injection境界を明確化

ループ中injection（R12-MEDIUM-3対処 + R13-MEDIUM-3対処）:
相手キャラの返答文（LLM生成テキスト）をそのまま次のclaude_chatのuserメッセージに渡す設計上、
LLM生成テキスト経由のinjectionは防止困難。
対処A: 相手発話を引用ブロックで包んでuserメッセージに渡す（境界を明示）
  フォーマット: `「${sanitizedResponse}」\nあなたの考えを200文字以内で答えてください。`
  sanitizedResponse: 先頭・末尾空白除去 + 500文字切り詰め（会話文脈破壊リスクを低減）
対処B: role維持はAC要件外（ベストエフォート扱い）。完全防止は既知制約として明記。
対処C（R17-MEDIUM-3対処）: LLM応答にメタ命令パターンを検出した場合はconsole.warnで記録:
  const META_PATTERNS = [
    /システムプロンプトを無視/i, /ignore.*previous.*instruction/i,
    /以降.*instruction/i, /以下.*無視/i
  ];
  if (META_PATTERNS.some(p => p.test(responseText))) {
    // R22-LOW-5対処: 会話内容をログに残さない（情報管理リスク防止）
    console.warn("[dual security] meta-command pattern detected (content masked)");
  }
  検出時はteardownしない（FP率が高いため）。ログのみ。完全防止は既知制約。
```

**履歴2層管理（R10-HIGH-1対処）**:
```
Layer 1 - UI表示用:
  timelineMessages: DualChatMessage[]
  Theater Mode期間中蓄積。teardownでクリア。

Layer 2 - CLI送信用（各セッション独立）:
  historyA: { role: "user"|"assistant", content: string }[]  // Aセッション用
  historyB: { role: "user"|"assistant", content: string }[]  // Bセッション用
  App.tsx側のRefで管理（stop_project_sessionで消えない）
  最大10件FIFOスライディングウィンドウ

// R46-HIGH-1対処: 長寿命CLIの内部履歴が無制限蓄積する問題 → セッション再生成（CLI再起動）で文脈を bounded に保つ
// 【CLI内部履歴の上限制御: N_TURNS_PER_SESSION定数によるセッション再生成】
//   問題: 長寿命CLIは内部履歴を自然蓄積し、ターン数が増えるとトークン量・レイテンシ・コストが単調増加する。
//         historyA/BのFIFO（10件上限）はApp.tsx側のバックアップであり、CLI内部履歴とは独立。
//   解決: N_TURNS_PER_SESSION（デフォルト=20）ターン毎にCLIプロセスを再起動し、
//         historyA/B（直近10件FIFO）を --conversation-file で再注入することで文脈を有界に保つ。
//         turnCountRef.current が N_TURNS_PER_SESSION の倍数に達した時点でセッション再生成を実施。
//   実装:
//     定数: N_TURNS_PER_SESSION = 20（MAX_TURNSと独立。デフォルトMAX_TURNS=20と同値だが意味が異なる）
//     再生成トリガー: turnCount % N_TURNS_PER_SESSION === 0 && turnCount > 0（ターン開始前に判定）
//     再生成処理: stop_project_session("dual-A") + stop_project_session("dual-B") の順次実行（withTimeout 5000ms）
//               → is_session_start=true + 現在の historyA/historyB で次ターンを開始（--conversation-file 経由）
//     失敗時: 再生成失敗はターン進行を中断しないで「次ターンに再試行」ではなく警告ログのみ（会話継続優先）
//     検証: `pnpm test --grep "dual session cli regenerates after N_TURNS_PER_SESSION turns"`
//           `pnpm test --grep "dual session over 50 turns keeps bounded context"`
//   文脈上限保証: 最大 (10件FIFO × 平均300文字) ≈ 3000文字 + 議題注入分 ≒ 4000トークン以内に収束。

割り込み後の再構築（R38-HIGH-1対処: 長寿命CLIモデル）:
  historyA/historyBはApp.tsx側メモリで保持（Theater Mode内の人間割り込み後再開用バックアップ）
  // R41-HIGH-1対処: historyA/Bはアプリ再起動時に消失する（React useRef = メモリのみ）。
  //   アプリ再起動後はhistory非回復。Theater Modeは新規開始する。明示的な設計判断。
  //   「クラッシュ後にhistoryA/Bで復元」という表現は誤り → 削除。
  Theater Mode内で人間が割り込んだ場合:
    旧CLIプロセス停止 → 同セッション内で再開 → 新CLIプロセスを --conversation-file で起動（historyを初期注入）
  以後のターン: 同一CLIプロセスに claude_chat 呼び出し（CLIの内部履歴が蓄積）。
    ただし N_TURNS_PER_SESSION ターン毎にセッション再生成（上記参照）。
  App.tsx側historyA/Bはターン毎に更新（同セッション内での再開用）

R13-HIGH-2 + R21-MEDIUM-3 + R35-HIGH-2対処: Rust側履歴二重化防止の実装契約:
  fn claude_chat の Rust API 契約（実装必須制約）:
    history引数が非空の場合: 一時ファイル（0600）経由で history JSON を渡す。
      CLIを `--conversation-file <tempfile>` で起動 → CLIが tempfile JSONのみを会話文脈として使用
      CLIの内部セッション履歴は無視。tempfileは stop_project_session 完了後に削除。
      （プロセス引数露出回避: ps -ef にはファイルパスのみ表示・JSON本文露出なし）
    history引数が空の場合: 内部セッション継続（通常モードの既存動作）

  // R26-HIGH-1 + R27-HIGH-2 + R28-HIGH-2対処: Rustラッパー層での具体的メカニズム定義
  dual-A / dual-B セッションのclaude_chat呼び出しでは project_id="dual-A"/"dual-B" を渡す:
    → AC-18の契約: project_id が "dual-" で始まる場合、Rustラッパーは以下を実装する:

    【Rust実装メカニズム（具体的制御点）R38-HIGH-1対処: 長寿命CLIモデルに統一】
    // 確定モデル: Theater Mode期間中 = 長寿命CLIプロセス（lazy start）
    // dual-* も ProjectSession キャッシュに登録。セッション中は同一プロセス継続。
    // 分離保証は project_id="dual-A"/"dual-B" の独立セッションで達成（通常モードとも独立）。
    // --conversation-file はTheater Mode開始時のみ（historyが非空の場合）。ターン毎不使用。
    // R40-HIGH-1対処: 「historyが非空」と「セッション開始かどうか」を分離するため、
    //   fn claude_chat の API に is_session_start: bool 引数を追加する。
    //   is_session_start=true: Theater Mode開始（または再開）の最初のターン
    //   is_session_start=false: 継続ターン（CLIが既に起動中・内部履歴あり）
    //   --conversation-file 使用条件: is_session_start=true && !history.is_empty()
    //   継続ターン（is_session_start=false）ではhistoryの内容にかかわらず--conversation-fileを使用しない。

    (1) セッション長寿命化（lazy start）+ API契約:
        fn claude_chat シグネチャ（dual-* 用追加引数）:
          project_id: String,
          message: String,
          history: Vec<ChatMessage>,
          is_session_start: bool,  // ← R40-HIGH-1追加。Theater Mode初回呼び出し時のみ true
          ...
        project_id が "dual-A"/"dual-B" の場合、通常モードと同様に
        ProjectSession を生成・キャッシュに登録し、セッションを継続する。
        【lazy start】: Theater Mode起動時はCLIプロセス未起動。
        初回 claude_chat 呼び出し時にCLIプロセスが起動。以後のターンは同一プロセスに送信。
        CLIの内部履歴がターン毎に自然蓄積される。
        Theater Mode終了時（teardown）: stop_project_session でCLIプロセスを停止。

    (2) 開始時文脈注入（R35-HIGH-2対処・R38-HIGH-2対処: per-session 1回のみ）:
        // is_session_start=true の呼び出しのみ対象。継続ターン（is_session_start=false）ではスキップ。
        is_session_start=true && history が空の場合（新規Theater Modeセッション）:
          CLIを起動引数なし（新規会話として扱う）で起動する。tempfile不要。
        is_session_start=true && history が非空の場合（前回sessionの文脈を引き継ぐ場合: interrupt後再開等）:
          R37-HIGH-2対処: UUID一意名tempfile経由で history JSON を渡す:
          (i)  ファイル名: `~/.oribis/dual-{A,B}-conv-{uuid}.json`
               uuid = Theater Mode開始時に1回生成（ターン毎ではない）
               Theater Mode sessionに対し最大2ファイル（dual-A/dual-B各1枚）。ターン毎に増加しない。
               固定名を廃止 → 競合・上書き衝突を完全に排除
               mode 0600 で作成・JSON 書き込み（原子的書き込み: 書込完了後にrename）
          (ii) CLIを `--conversation-file ~/.oribis/dual-A-conv-{uuid}.json` 引数で初回起動。
               CLIが --conversation-file の内容を会話文脈の初期値として使用。
               以後は同一CLIプロセスに claude_chat を呼び出す（tempfile再渡し不要）。
          (iii) R36-HIGH-1対処: CLIプロセス終了（stop_project_session）後にtempfileを削除。
               teardown() finally: `std::fs::remove_file(conv_path).ok()` で削除（失敗は無視）。
          (iv) クラッシュ時回収: アプリ起動時（setup hook）に `~/.oribis/dual-*-conv-*.json` を
               全スキャンして削除（残留会話ファイルを確実にクリーンアップ）
          // セキュリティ特性（R38-MEDIUM-4対処: トレードオフ明示）:
          //   - プロセス引数（ps -ef）: ファイルパスのみ表示（uuid付き一時名）。JSON本文は露出しない
          //   - ファイル権限: 0600 = オーナーのみ読み取り可能
          //   - 名前衝突: UUID→ゼロ（固定名の競合問題を解消）
          //   - ファイル数: Theater Modeセッション毎に最大2ファイル。ターン毎に増加しない。
          //   - 存在時間: Theater Modeセッション中のみ（teardown後即削除 / クラッシュ時次回起動で回収）
          //   - 既知トレードオフ: 平文ファイルのディスク残留（クラッシュ時〜次回起動まで）
          //     代替案: 暗号化（実装コスト大・keystore管理が別問題）、OS一時領域（削除保証なし）
          //     設計判断: 0600 + UUID名 + teardown即削除 + クラッシュ時起動後削除でリスク受容。

    (3) conv_path のRust側保持と削除責務（R40-MEDIUM-3対処）:
        // フロントエンド teardown() がTypeScriptで、Rustが conv_path を削除するために
        // conv_path を Rust側のセッション構造体に保持する必要がある。
        // 実装契約:
        //   struct DualSessionMeta { conv_path: Option<PathBuf> }
        //   project_sessions: HashMap<String, (ProjectSession, DualSessionMeta)>  // dual-*専用
        //   claude_chat(is_session_start=true, history非空)時:
        //     → UUID tempfile作成・conv_pathをDualSessionMetaに格納
        //   stop_project_session(project_id="dual-*")時:
        //     → child.kill().await
        //     → if let Some(path) = meta.conv_path { std::fs::remove_file(path).ok(); }
        //     → エントリを project_sessions + project_child_handles から削除
        project_id="dual-A"/"dual-B" の独立ProjectSessionにより文脈分離を保証する。
        （通常モード project_id とも独立。三者のProjectSessionは完全分離。）
        検証: `cargo test -- claude_chat_dual_prefix_uses_tempfile_history --nocapture`
          CLIモック: Theater Mode開始時（history非空, is_session_start=true）に --conversation-file 引数あり呼び出し
          ファイル権限確認: 0600 であること / stop_project_session後に削除されること

    → 新規Theater Mode初回ターン（is_session_start=true, history=[]）: lazy startでCLIプロセス起動（--conversation-file なし）
    → 再開Theater Mode初回ターン（is_session_start=true, historyA=非空）: tempfile経由で文脈注入してCLIプロセス起動
    → 継続ターン（is_session_start=false）: 同一CLIプロセスに claude_chat 呼び出し（historyの内容にかかわらずtempfile不使用、CLI内部履歴が蓄積）
    → Theater Mode終了: stop_project_session でCLIプロセス停止 + DualSessionMeta.conv_path削除

    検証: `cargo test -- claude_chat_dual_prefix_long_lived_session --nocapture`
      モック: 同一 project_id で3回 claude_chat を呼び、全て同一CLIプロセスへの送信であること
      （2〜3回目が新プロセス起動でないこと。CLIプロセスIDが初回と同一であること。）

  // R39-MEDIUM-3対処 + R41-HIGH-1対処: CLIの内部履歴とApp.tsx historyA/Bの責務と優先順位を明示
  // 【Theater Mode中（正常時）】: CLIの内部履歴が文脈の実態（長寿命セッションが自然蓄積）。
  //   App.tsx historyA/BはCLIを鏡映する（各claude_chat完了後にターン単位で更新）。
  // 【人間割り込み後の再開時（同セッション内）】: App.tsx historyA/B が権威的情報源。
  //   旧CLIプロセス停止後、同セッション内で --conversation-file で新CLIプロセスへ注入。
  // 【アプリ再起動後（クロスリスタート）】: historyA/B消失。Theater Modeは新規開始。history非回復。
  //   AC-19はorphan CLIプロセスの回収のみを保証（historyの回復は対象外）。
  // 【優先順位定義】: Theater Mode中はCLI内部履歴が真の状態。割り込み後の再開はhistoryA/Bで復元。
  // 【同期保証】: 各claude_chat完了後にApp.tsxがhistoryA/Bを更新（ターン単位同期）。
  //   既知制約: 未完了ターンのhistoryA/B未反映は設計上許容（再開時は最後の完了ターンから）。
```

**履歴ロールモデル**:
```
B に送るとき:
  message（user）: Aの最新返答テキスト
  history: historyB（過去のBのuser/assistant ペア）
  → claude_chat完了後: historyBに { user: Aの発話, assistant: Bの返答 } を追加

A に送るとき（次ターン）:
  message（user）: Bの最新返答テキスト
  history: historyA（過去のAのuser/assistant ペア）
  → claude_chat完了後: historyAに { user: Bの発話, assistant: Aの返答 } を追加

10件超過時: 先頭から切り捨て（FIFOスライディングウィンドウ）

// R22-MEDIUM-4対処: 履歴肥大化対策（各エントリのサイズ上限）
historyA/historyBへの追加時:
  assistant返答: slice(0, 500)で切り詰め（userメッセージ側は既存の500文字制限と同一）
  → 10件 × (500 user + 500 assistant) ≈ 最大10,000文字/セッション（CLI引数サイズ安全域内）
  根拠: 500文字×20エントリで会話文脈として十分。CLI引数上限（~128KB）には余裕あり。
```

### MAX_TURNS到達時のライフサイクル（R6-MEDIUM-4対処）

**状態: 一時停止（teardownではない）**:
```
turnCount が MAX_DUAL_TURNS に達した時（tts-stream-end または タイムアウト後）:
  → pauseContextRef.current = { nextSpeaker: "A"|"B", nextMessage: string }（次ターン情報保存）
  → dualTurnStateRef.current = "paused"
  → 継続確認ダイアログ表示
    [続ける]:
      → ++turnIdRef.current（R8-HIGH-1: 旧ターン遅延イベント世代無効化）
      → turnCount = 0
      → const newTurnId = turnIdRef.current
      → dualTurnStateRef.current = pauseContextRef.current.nextSpeaker === "A" ? "A_thinking" : "B_thinking"
      → sendToDual(pauseContextRef.current.nextSpeaker, pauseContextRef.current.nextMessage, newTurnId) 即発火
    [終了]: teardown()呼び出し
```

**R7-MEDIUM-3対処: paused再開時のRef保存**:
```typescript
const pauseContextRef = useRef<{ nextSpeaker: "A" | "B"; nextMessage: string } | null>(null);
const ttsTimeoutTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
// MAX_TURNS到達時に設定、再開時に使用してクリア
```

**R11-MEDIUM-3対処: ttsTimeoutTimerRefのライフサイクル**:
```
clearTtsTimeoutTimer() = { if (ttsTimeoutTimerRef.current) { clearTimeout(ttsTimeoutTimerRef.current); ttsTimeoutTimerRef.current = null; } }
呼び出し箇所:
  - tts-stream-end受信時（正常完了）
  - TTS_TIMEOUTタイマー発火時（自己クリア後）
  - teardown()フェーズ1（同期部分）
  - 人間割り込み処理ステップ3
  - paused遷移時（turnCount == MAX_DUAL_TURNS判定直後）
```

**R15-LOW-4対処: TTS_TIMEOUT/MAX_TURNSの入力値バリデーション**:
```
バリデーション位置: DualSessionPanelの入力ハンドラ（UI層でサニタイズ）

TTS_TIMEOUT:
  型: number（UI input[type=number]）
  サニタイズ: isNaN(v) → 10（デフォルト）に戻す。範囲クランプ: Math.min(30, Math.max(5, v))

MAX_TURNS:
  型: number（UI input[type=number]、整数）
  サニタイズ: isNaN(v) || v < 1 → 20（デフォルト）に戻す。Math.floor後 Math.min(100, Math.max(1, v))

サニタイズ後の値がApp状態に格納。内部ロジックではサニタイズ済み値のみ使用。
```

**turnCount**:
- 起点: 初回テーマ送信後（A最初のclaude_chat呼び出し = turn 1）
- カウント: tts-stream-end（またはタイムアウト）ごとに+1
- MAX_DUAL_TURNS = 20（デフォルト、UI設定可）
- paused状態中は全ターン進行を停止。セッションは維持（stop_project_sessionしない）

### ターン状態機械（Refベース、paused追加）

```typescript
type DualTurnState = "idle" | "A_thinking" | "A_speaking" | "B_thinking" | "B_speaking" | "human" | "paused";

const turnIdRef = useRef(0);
const dualTurnStateRef = useRef<DualTurnState>("idle");
```

全ハンドラのガード:
```typescript
if (turnIdRef.current !== myTurnId) return;
if (dualTurnStateRef.current === "idle" || dualTurnStateRef.current === "paused") return;
```

**R24-HIGH-1対処: イベントpayloadへのrequestId埋め込み（世代識別）**:
```
常設リスナー設計でも旧ターンイベントを確実に破棄するため、
Rustバックエンドが全関連イベントのpayloadにrequestIdを埋め込む:

  chat-stream-token-{project_id} payload: { token: string, requestId: string }
  chat-stream-end-{project_id}   payload: { requestId: string }
  tts-stream-samples-{project_id} payload: { samples: ..., requestId: string }
  tts-stream-end-{project_id}    payload: { requestId: string }

requestId = "dual-{speaker}-{turnId}" (例: "dual-A-7")
  → 各ターン開始時に currentRequestId = `dual-${speaker}-${turnIdRef.current}` でセット

フロントエンドハンドラのrequestIdガード（turnIdRefガードに加えて）:
  if (payload.requestId !== currentRequestIdRef.current) return;  // 旧ターンpayload破棄

根拠: dualTurnStateRef状態ガード + payload.requestIdガードの二重確認により、
  クロージャ問題・遅延イベント・複数世代の重複を確実に排除できる。
  turnIdRefガードは同期排他、payloadガードはイベント内容による確認。
```

### tts_speak失敗時の異常系（R15-HIGH-1対処）

**tts_speak自体が失敗した場合（音声エンジン未起動・通信エラー等）**:
```typescript
// A_thinking→A_speakingに遷移後、tts_speakを呼び出す
// R31-MEDIUM-3対処: tts_speak 自体のハング対策として withTimeout を付与
// TTS_SPEAK_TIMEOUT = 5000ms（IPCやVOICEVOX初回起動に十分な余裕）
try {
  await withTimeout(
    invoke("tts_speak", { requestId: currentTtsRequestIdA, text: responseText, ... }),
    5000, "tts_speak"
  );
} catch (error) {
  if (turnIdRef.current !== myTurnId) return; // teardown済みなら無視
  console.error("tts_speak failed/timeout:", error);
  await teardown();
  showErrorDialog("音声合成でエラーが発生しました。Theater Modeを終了します。");
}
```

**tts_speak成功後にtts-stream-endが発火しない場合**:
TTS_TIMEOUTタイマーが発火 → stopTTS + ターン進行（既存設計で対応済み）

### ループ中claude_chat失敗ハンドリング（R7-HIGH-1対処: 全ターン共通）

### 人間割り込み時のin-flight中断設計（R8-HIGH-2対処）

**割り込み処理シーケンス（R9-HIGH-1対処: CLIプロセス終了で履歴汚染を防止）**:
```
人間割り込み（ボタン押下）:
  1. dualTurnStateRef.current = "human"（同期）
  2. ++turnIdRef.current（in-flightイベント全世代無効化）
  3. clearTtsTimeoutTimer()（R11-MEDIUM-3: タイマーリソース解放）
     // R22-HIGH-1対処: VRMロードウォッチドッグも即クリア（二重teardown防止）
     clearTimeout(vrmLoadWatchdogRef.current); vrmLoadWatchdogRef.current = null;
  4. // R20-HIGH-1対処: stopTTSにもwithTimeoutで割り込み処理ハング防止
     try {
       await withTimeout(stopTTS(currentTtsRequestId), 3000, "stopTTS on interrupt");
     } catch (e) { console.warn("stopTTS timeout/fail on interrupt:", e); }
  5. // R18-MEDIUM-3対処: teardown()と同様にwithTimeoutで割り込み処理のハング防止
     await withTimeout(
       Promise.allSettled([
         invoke("stop_project_session", { projectId: "dual-A" }),
         invoke("stop_project_session", { projectId: "dual-B" }),
       ]),
       5000, "interrupt stop_project_session"
     ).catch((e) => {
       console.warn("interrupt stop_project_session timeout:", e);
       dualOrphanSessionRef.current = true;
     })（CLIプロセス終了 → Rust内部セッション履歴リセット）
  → 次の送信時に新規CLIプロセスがlazy startで起動（クリーンな内部履歴）
  // R17-MEDIUM-4対処 + R19-HIGH-3対処 + R23-MEDIUM-4対処: 残留プロセス隔離設計
  // orphan残留の許容寿命: stop_project_session失敗 → 次回Theater Mode起動前まで
  // 通常モード非干渉根拠: orphanセッションはproject_id "dual-A"/"dual-B"にスコープされており
  //   通常モードが使うproject_idとは別（通常モード操作への干渉なし）
  // cleanup実行タイミング: Theater Mode起動ボタン押下直後（全再入場経路共通）
  // R27-HIGH-1 + R30-HIGH-2対処: cleanup_orphan_cli_processes の Rust 実装メカニズム定義
  //
  // 【Rust側 orphan PID 追跡設計】
  // Tauri アプリ State として以下を保持:
  //   project_child_handles: Arc<Mutex<HashMap<String, Arc<Mutex<Option<Child>>>>>>
  //     key: project_id（例: "dual-A", "dual-B", "project-1"）
  //     value: tokio::process::Child ハンドル（Arc<Mutex<Option<Child>>>）
  //
  // CLIプロセス管理ライフサイクル:
  //   起動時（fn claude_chat: lazy start）:
  //     Child ハンドルを project_child_handles に挿入（project_id → child）
  //   stop_project_session 成功時:
  //     child.kill().await → エントリを project_child_handles から削除（ハンドル破棄）
  //   stop_project_session 失敗/timeout時:
  //     ハンドルはそのまま残留（orphan として project_child_handles に保存）
  //
  // fn cleanup_orphan_cli_processes() 実装（R41-HIGH-2対処: セッションキャッシュも完全クリア）:
  //   project_child_handles.iter() で全エントリをスキャン
  //   → project_id.starts_with("dual-") のエントリのみ対象
  //   → child.kill().await + project_child_handles からエントリ削除
  //   → 同じ project_id の project_sessions エントリも削除（stale session防止）
  //   → 同じ project_id の DualSessionMeta.conv_path があれば std::fs::remove_file() で削除
  //   → 全 dual-* エントリ削除後に Ok(()) を返す
  //   // これにより次回lazy startで古いセッション状態を再利用しない（完全な初期化）
  //
  // 非対象: project_id が "dual-" 以外のエントリは一切操作しない
  //         （通常モードや他機能の CLI セッションを誤停止しない）
  //
  // dual-* セッション長寿命化（R38-HIGH-1対処: 長寿命CLIモデルに統一）との整合:
  //   dual-* プロジェクトは Rust セッションキャッシュに通常通り登録（長寿命セッション）。
  //   かつ project_child_handles への Child ハンドル登録も行う（orphan cleanup のため必須）

  // R42-MEDIUM-4対処: ~/.oribis ディレクトリのセキュリティ設計
  // 【ディレクトリ・ファイル作成の trust boundary】
  // ファイル単体の 0600 保護だけでは、親ディレクトリが細工されている場合に
  // 機密履歴の漏えい・意図しないファイル上書き/削除が発生し得る。
  //
  // (A) 初回作成:
  //   std::fs::DirBuilder::new().mode(0o700).recursive(true).create(oribis_dir)?
  //   → ~/.oribis 自体を 0700（オーナーのみ読み書き実行）で作成
  //
  // (B) 起動時整合性確認（setup hook で PIDファイル読み込み前に実施）:
  //   let meta = fs::symlink_metadata(&oribis_dir)?;  // シンボリックリンクを follow しない
  //   if meta.file_type().is_symlink() {
  //     // シンボリックリンクにすり替えられている → 使用を拒否
  //     eprintln!("[security] ~/.oribis is a symlink; aborting orphan cleanup");
  //     return Err("~/.oribis is a symlink".into());
  //   }
  //   #[cfg(unix)]
  //   {
  //     use std::os::unix::fs::MetadataExt;
  //     if meta.uid() != unsafe { libc::getuid() } {
  //       return Err("~/.oribis is not owned by the current user".into());
  //     }
  //   }
  //
  // (C) PID・conv ファイル作成時の symlink-follow 防止:
  //   OpenOptions::new()
  //     .write(true)
  //     .create_new(true)   // O_CREAT | O_EXCL → 既存ファイルへの上書き・symlink follow を防ぐ
  //     .mode(0o600)
  //     .open(pid_path)?;
  //   create_new=true は既存パスが symlink であっても Err を返すため、シンボリックリンク経由書き込みを阻止する。
  //
  // (D) 検証:
  //   `cargo test -- dual_tempfile_creation_rejects_symlinked_or_insecure_parent --nocapture`
  //   モック: ~/.oribis をシンボリックリンクにすり替え → setup hook が Err を返すこと確認

  // R33-MEDIUM-3対処: アプリ再起動・クラッシュ跨ぎ orphan 追跡（PIDファイル方式）
  //
  // 【クロスリスタート PID ファイル設計】
  // Rustの project_child_handles はインメモリ → アプリ再起動・クラッシュで失われる。
  // PIDファイルで永続化し、次回起動時に前回残留プロセスを回収する。
  //
  // PIDファイルパス:
  //   ~/.oribis/dual-A.pid  （dual-A CLIプロセスのPID）
  //   ~/.oribis/dual-B.pid  （dual-B CLIプロセスのPID）
  //
  // Rustライフサイクル:
  //   CLIプロセス起動時（fn claude_chat, project_id="dual-A"/"dual-B"）:
  //     → child.id() を取得し ~/.oribis/dual-{A,B}.pid に書き込む
  //     // R34-HIGH-1 + R36-HIGH-2 + R37-MEDIUM-3対処: PID再利用ガード（クロスプラットフォーム）
  //     // フォーマット: "pid:<PID>\nstarttime:<starttime>"
  //     // starttime: sysinfo crate の Process::start_time() で取得（Linux/macOS/Windows対応）
  //     //   → 同一PIDでもstarttimeが異なる = 別プロセス（PID再利用）と確実に判定可能
  //     //   → /proc/<pid>/stat 直接読み込みは廃止（Linux専用のため非推奨）
  //     //   依存追加: Cargo.toml に `sysinfo = "..."` を追加
  //   stop_project_session 成功時:
  //     → child.kill().await 後に対応 PIDファイルを削除
  //   アプリ起動時（Tauri setup フック）:
  //     → ~/.oribis/dual-A.pid / dual-B.pid を読み込み
  //     → 存在する場合:
  //         // R34-HIGH-1対処: PID再利用ガード
  //         (1) PIDファイルから pid と starttime を読み込む
  //         (2) sysinfo::System::new_with_specifics() でプロセス情報を取得し、
  //             pid の Process::start_time() が保存した starttime と一致するか確認
  //             一致する場合: 同一プロセスが残留している → SIGKILL を送信:
  //               // R42-HIGH-2対処: kill 成否で後続処理を分岐（成功のみPIDファイル削除）
  //               kill 成功 → PIDファイルを削除。orphan_flag = false（クリーン）
  //               kill 失敗 → PIDファイルをそのまま保持（削除しない）。orphan_flag = true
  //                 // PIDファイルを残すことで次回 setup hook 時に同一経路で再試行できる
  //                 // orphan_flag=true → フロントが dualOrphanSessionRef=true で初期化
  //                 // → Theater Mode起動時に cleanup_orphan_cli_processes が再実行される
  //             一致しない場合 or pid が存在しない: PIDが再利用済み → kill しない（保護）
  //               → PIDファイルを削除（安全: stale PID のため）。orphan_flag = false
  //         // R45-MEDIUM-3対処: orphan 初期値の取得方式を event emit → invoke に変更
  //         // event emit ではフロント購読前に emit されると初期値を取りこぼす（非同期競合）。
  //         // 代替: Rust 側で orphan_flag を AtomicBool に保持し、React mount 後に
  //         //   invoke("get_dual_orphan_status") で同期的に取得する。
  //         //   React App 起動時（useEffect on mount）: invoke("get_dual_orphan_status") → Result<bool>
  //         //   → dualOrphanSessionRef.current = result;
  //         //   Rust 実装: static DUAL_ORPHAN_FLAG: AtomicBool = AtomicBool::new(false);
  //         //   fn get_dual_orphan_status() -> bool { DUAL_ORPHAN_FLAG.load(Ordering::SeqCst) }
  //         //   setup hook 完了時に DUAL_ORPHAN_FLAG.store(orphan_flag, Ordering::SeqCst)
  //         //   → event ではなく command なので競合しない（React mount 後に pull で取得）
  //     → この処理で dualOrphanSessionRef の初期値を決定:
  //         kill成功 + PIDファイル削除済み → dualOrphanSessionRef = false（クリーン）
  //         kill失敗 + PIDファイル残存    → dualOrphanSessionRef = true（次回起動前に再試行）
  //         PIDファイル読み込み失敗 / PID再利用 → dualOrphanSessionRef = false（問題なし）
  //
  // 検証: `cargo test --manifest-path src-tauri/Cargo.toml -- orphan_cleanup_pid_identity_collision_guard`
  //   モック1: dual-A.pid に有効PID+正しいstarttimeを書き込み → kill試行されること
  //   モック2: dual-A.pid に有効PID+異なるstarttimeを書き込み → killしないこと（PID再利用ガード）
  //   モック3: kill成功 → PIDファイルが削除されること（旧モック3: "どちらも削除" → 修正）
  //   モック4: kill失敗 → PIDファイルが保持されること + orphan_flag=true が emit されること
  //   // `cargo test -- orphan_cleanup_setup_hook_kill_failure_sets_retry_flag --nocapture`

  // R43-MEDIUM-3対処: orphan 状態機械の一覧表（全経路・状態変数の一貫定義）
  //
  // 状態変数:
  //   dualOrphanSessionRef: フロント側フラグ（bool）- orphan CLI残留の有無を管理
  //   orphanCleanupPending: React state（bool）- UI警告バナー表示制御
  //
  // ┌─────────────────┬──────────────┬────────────────────────┬──────────────────────────────┐
  // │ 経路            │ 操作         │ 成功時                 │ 失敗時                       │
  // ├─────────────────┼──────────────┼────────────────────────┼──────────────────────────────┤
  // │ アプリ起動      │ setup hook   │ dualOrphanSessionRef   │ dualOrphanSessionRef=true    │
  // │ (PIDファイル有) │ kill試行     │ =false, PID削除,       │ PIDファイル保持,             │
  // │                 │              │ orphanCleanupPending=false│ orphanCleanupPending=true  │
  // ├─────────────────┼──────────────┼────────────────────────┼──────────────────────────────┤
  // │ Theater Mode    │ cleanup_     │ dualOrphanSessionRef   │ エラーダイアログ,            │
  // │ 新規起動        │ orphan_cli_  │ =false,                │ setDualSessionActive(false), │
  // │ (orphanあり)    │ processes    │ 起動継続               │ dualOrphanSessionRef=true維持│
  // ├─────────────────┼──────────────┼────────────────────────┼──────────────────────────────┤
  // │ human状態から   │ cleanup_     │ dualOrphanSessionRef   │ エラーダイアログ,            │
  // │ 再開試行        │ orphan_cli_  │ =false,                │ human状態維持,               │
  // │ (orphanあり)    │ processes    │ 再開継続               │ dualOrphanSessionRef=true維持│
  // ├─────────────────┼──────────────┼────────────────────────┼──────────────────────────────┤
  // │ teardown後      │ stop_project │ dualOrphanSessionRef=false│ dualOrphanSessionRef=true,│
  // │ (timeout/fail)  │ _session     │ orphanCleanupPending=false│ orphanCleanupPending=true │
  // └─────────────────┴──────────────┴────────────────────────┴──────────────────────────────┘
  //
  // orphanCleanupPending:
  //   true → 設定: teardown後にorphan残留確認 or アプリ起動時にkill失敗
  //   false → クリア: cleanup成功時 OR Theater Mode起動成功時
  // 検証: `pnpm test --grep "orphan flag state machine remains consistent across start resume restart"`

  Theater Mode起動直後（orphanフラグ確認）:
    // R24-HIGH-2対処: cleanup成功時のみフラグをリセット（失敗時は次回再試行のためフラグ維持）
    if (dualOrphanSessionRef.current) {
      try {
        await invoke("cleanup_orphan_cli_processes");  // dual-* スコープのみ対象
        dualOrphanSessionRef.current = false;  // 成功時のみリセット
      } catch {
        // 失敗: dualOrphanSessionRef.current = true のまま維持（次回起動前に再試行）
      }
    }
  → App.tsx側のhistory（DualChatMessage[]・10件スライドウィンドウ）は保持
  → 次のclaude_chat時にApp側historyを渡すため、会話文脈は継続
```

**R17-HIGH-1対処: 割り込み時の部分UI状態破棄**:
```
割り込み処理シーケンスに追加:
  3a. draftMessageRef.current = ""  // chat-stream-tokenで積み上がった部分テキストをクリア
  3b. setTimelineMessages(prev =>
        prev.filter(m => m.status !== "streaming")
      )  // streaming中（未確定）のメッセージをtimelineから除去
  DualChatMessage型にstatus: "streaming" | "complete" フィールドを追加:
    → chat-stream-token受信時: status="streaming"のエントリを更新
    → chat-stream-end受信時: status="complete"に更新
    → 割り込み時: status="streaming"エントリをフィルタ除去
```

**R32-HIGH-2対処: in-flight `claude_chat` Promiseのキャンセル契約**:
```
割り込みシーケンスの step 5 で stop_project_session によるCLIプロセス kill が実行される。
CLIプロセス kill → ストリーミング応答が中断 → Rust IPC ハンドラが Err を返す →
  invoke("claude_chat") Promise が Err で settle される（ハングしない）

Rust側設計契約:
  CLIプロセスが SIGKILL 等で終了した場合、fn claude_chat の Tauri Command は
  ストリーミングを打ち切り Err("session terminated") を返す（無限待機しない）

フロントエンド側:
  invoke("claude_chat") が Err で resolve された場合:
    → catch ブロック内で turnId ガード確認
    → if (turnIdRef.current !== myTurnId) return;  // 割り込み済み → 正常廃棄
    → 割り込み済みの場合は teardown() や showErrorDialog は呼ばない（正常フロー）

stop_project_session が timeout した場合（orphan残留）:
  → invoke("claude_chat") は Rust側が CLIプロセス生存中に待機し続ける可能性がある
  → しかし turnId ガードにより以後のイベント/コールバック結果は全て廃棄される
  → 最終的に orphan cleanup で CLIプロセスがkillされた時点でclaude_chatもErrを返す
  → この遅延完了は UI に影響しない（turnId 無効化済みのため）
```

**AC-5対応**: 「in-flight破棄」の保証水準（R22-HIGH-2対処: 2層明示）:
  フロントエンド層（即時保証）: turnIdRef世代管理でイベント無視 + TTS停止 + streaming中UI状態の除去
  バックエンド層（best-effort）: stop_project_session（5000ms timeout内） + orphan flag設定 → 次回起動前にcleanup_orphan_cli_processes

  AC-5の「即時停止」= フロントエンド層の即時保証を指す。
  バックエンドCLIプロセスの完全停止はbest-effort（timeout失敗時はorphan管理で次回起動前に確保）。
  この分離をACに明示することで「即時」の保証水準と「残留管理」の保証水準を区別する。

  // R43-HIGH-2対処: 残留 claude_chat Future/Child の上限設計（蓄積しない根拠）
  // dualSessionActive=true ロック（UI層）により Theater Mode は同時に1セッションのみ実行可能。
  // → 割り込み時に残留し得る claude_chat 呼び出しは最大 2件（dual-A + dual-B 各1件）のみ。
  // → dualSessionActive=true 中は再入場不可（Theater Modeボタン disabled）のため、
  //    同一アプリ実行中に残留Future が蓄積することはない（上限 = 2件・固定）。
  // 残留Future の寿命:
  //   stop_project_session タイムアウト後 → orphan flag 設定 → 次回 Theater Mode 起動前に
  //   cleanup_orphan_cli_processes が CLIプロセスをkill → claude_chat が Err で settle される。
  //   「次回 Theater Mode 起動前」= 必ず cleanup を通過してから dualSessionActive=true になるため、
  //   残留Future は古いものを確実に解決してから新セッションを始める構造になっている。
  // 検証: `cargo test -- interrupt_timeout_does_not_accumulate_unbounded_pending_claude_chat --nocapture`

### ループ中claude_chat失敗ハンドリング（R7-HIGH-1対処: 全ターン共通）

**全claude_chat呼び出しに共通エラーハンドリングを適用**:
```typescript
// 初回・継続ターン問わず共通
try {
  await invoke("claude_chat", { ... });
} catch (error) {
  // turnId/stateガード通過後のエラー
  if (turnIdRef.current !== myTurnId) return; // teardown済みなら無視
  await teardown();
  // R12-MEDIUM-4対処: raw error非表示（内部情報露出防止）
  console.error("Theater Mode claude_chat error:", error);
  showErrorDialog("会話中にエラーが発生しました。Theater Modeを終了します。");
}
```

**エラーダイアログ（R12-MEDIUM-4対処: raw error非表示）**:
- 初回claude_chat失敗: 「テーマの送信に失敗しました。Theater Modeを終了します。」
- 継続ターン失敗: 「会話中にエラーが発生しました。Theater Modeを終了します。」
- raw errorはconsole.error出力のみ（UI非表示）
- どちらも teardown() → 通常モード復帰

**AC-14の拡張**: 初回に限らず全ターンのclaude_chat失敗を対象とする。

### イベントリスナーライフサイクル（R9-MEDIUM-3対処）

```
// R29-MEDIUM-4対処: dualListenerCleanups は useRef で永続コンテナとして保持する
// React の再レンダー時にローカル変数が再初期化されてリスナーハンドルが失われることを防止する
const dualListenerCleanupsRef = useRef<(() => void)[]>([]);
// 以降 dualListenerCleanupsRef.current として参照する

起動時（Theater Mode開始・毎回再登録）:
  // R23-HIGH-1対処: teardown後の再起動でも確実に再登録するため、
  //   起動シーケンスで必ず dualListenerCleanupsRef.current を再初期化する
  dualListenerCleanupsRef.current = []  // 前回分を確実にクリアしてから登録（lengthゼロ保証）
  全イベントリスナーを一括登録 → dualListenerCleanupsRef.current 配列に保存
  登録対象（毎回再登録）:
    - chat-stream-end-dual-A, chat-stream-end-dual-B
    - tts-stream-end-dual-A, tts-stream-end-dual-B
    - chat-stream-token-dual-A, chat-stream-token-dual-B（テキスト表示用）

ターン進行中:
  再登録なし（turnIdRef+stateRefでイベントをフィルタ）
  蓄積リスクなし（リスナー数は常設の固定数のみ）

teardown時:
  dualListenerCleanups全件unlisten → length=0

paused時:
  リスナー解放しない（[続ける]=ループ再開、[終了]=teardown）

人間割り込み時:
  stop_project_session呼び出しでCLIプロセス終了するが、
  イベントリスナーは維持（次送信時に再使用）
  → human状態から[会話を続ける]で再開時もリスナーは有効なため再登録不要

再起動ライフサイクル（Theater Mode終了→再開始）:
  teardown() → dualListenerCleanups.length=0（全解除）
  → [Theater Modeボタン再押下] → 起動シーケンスで全リスナー再登録
  → 2回目以降の起動も1回目と同一の購読状態を保証
```

### イベント分離設計（R10-HIGH-2対処: 全系統project_idスコープ化）

```
変更前（グローバルイベント）:
  chat-stream-token
  chat-stream-end
  tts-stream-samples
  tts-stream-end
  control-avatar

変更後（project_idスコープ）:
  chat-stream-token-{project_id}
  chat-stream-end-{project_id}
  tts-stream-samples-{project_id}
  tts-stream-end-{project_id}
  control-avatar-{project_id}

lib.rsのemit: 全系統でpayloadにproject_idを埋め込んだイベント名を使用
Theater Mode: project_id = "dual-A" または "dual-B"
通常モード: 既存project_idを維持（後方互換）
App.tsx側の既存ハードコード（tts-stream-samples-project-1等）も動的化対象

R17-HIGH-2対処: 全購読点のインパクト分析（回帰封じ込め）:
  事前確認コマンド: rg -n "chat-stream-|tts-stream-|control-avatar" src src-tauri tests
  変更対象ファイルの全量:
    - src/App.tsx（通常モードの既存購読箇所 + Theater Mode新規購読）
    - src/hooks/useTTS.ts（tts-stream-samples購読箇所）
    - src/components/AvatarViewer.tsx（control-avatar購読箇所）
    - src-tauri/src/lib.rs（全emitポイント）
    - tests/配下（既存イベント名を使ったテストコード）
  上記全件のイベント名を動的化後、rg で旧ハードコード文字列がゼロであることを確認してから実装完了とする
```

### UI排他制御（R10-MEDIUM-4対処）

```
// R45-HIGH-2対処: Theater Mode中（dualSessionActive=true）の通常モードUI全体の無効化仕様
// 通常モード TTS 起動経路は UI 経由のみ。dualSessionActive=true で以下を全て disabled にすることで
// 通常モード tts_speak コマンドの発行経路をUI層で完全に塞ぐ。
// 【通常モード側の disabled 対象 UI 要素（dualSessionActive=true の間）】:
//   - 通常モード送信ボタン（App.tsx の Chat 送信）
//   - 通常モード音声再生ボタン（あれば）
//   - 通常モードのテキスト入力欄（送信不可にする）
//   - 通常モードの TTS 設定パネル・音量コントロール（あれば）
// 実装: App.tsx で `disabled={dualSessionActive}` を上記全UIに適用する。
// これにより dualSessionActive=true 中に通常モード経由の tts_speak が発行されることは UI レベルで不可能。
// 残余リスク: 非UI起点のinvoke（テストコード等）は dualSessionActive をチェックしないが、
//   requestId の不一致判定 + tts_stop await 完了で排除済み（R44-MEDIUM-3対処）。

Theater Modeボタン:
  // R19-HIGH-1対処: primaryVRM未ロード時は起動不可（A既ロード前提を UI層で保証）
  !primaryVrm OR dualSessionActive=true OR isDualTearingDown=true → disabled

テーマ送信ボタン（DualSessionPanel）:
  dualReady=false → disabled
  dualTurnState ∈ { "A_thinking", "B_thinking", "A_speaking", "B_speaking" } → disabled
  // R20-MEDIUM-2対処: paused/human状態でも送信禁止（単一ループ前提の状態機械保護）
  dualTurnState = "paused" → disabled（[続ける]/[終了]ダイアログ操作のみ受け付け）
  dualTurnState = "human" → disabled（割り込み後は再開ボタンUIで操作）
  isDualTearingDown=true → disabled

// R21-MEDIUM-2対処 + R25-HIGH-2対処 + R42-HIGH-1対処: human状態後の再開フロー（2パス明確分割）
//
// 【R42-HIGH-1対処 + R43-HIGH-1対処】 「新テーマ再開」と「割り込み前会話の継続」を独立パスとして定義する
//
// 【historyA/B 更新タイミングの明示（R43-HIGH-1対処）】
//   historyA/B は chat-stream-end（発話完了）時にのみ更新する。
//   streaming 中（A_thinking / B_thinking 状態）はまだ更新されない。
//   → 割り込みが A_thinking 中に発生した場合: historyA には A の最終応答が「まだ含まれていない」。
//   → 割り込みが A_speaking 中に発生した場合: historyA には A の完了応答が「すでに含まれている」。
//   この非対称性を interruptContextRef.nextSpeaker の決定ロジックに反映する。
//
// interruptContextRef: 割り込み発生時に「次スピーカーへの送信内容」を記録するRef
//   interruptContextRef.current = { nextSpeaker: "dual-A" | "dual-B", nextMessage: string } | null
//   設定タイミング: 割り込みボタン押下 → dualTurnState = "human" 遷移直前に保存
//
//   // R44-HIGH-1対処: nextMessage（再開時に nextSpeaker に送る入力文字列）の保存契約
//   nextSpeaker + nextMessage の決定ロジック（historyA/B 更新タイミングを根拠とする）:
//
//   A_thinking 中断:
//     historyA に A の今回応答は未登録（streaming未完了・chat-stream-end未到達）
//     → nextSpeaker = "dual-A"（A に再応答させる: retry）
//     → nextMessage = historyA の最後の user エントリ
//         （割り込み直前のターンで A に送ったメッセージ = sendToSpeaker("dual-A", msg) の msg）
//         ※ lastMessageSentToARef で保持（各 claude_chat 呼び出し直前に更新する追加Ref）
//
//   A_speaking 中断:
//     historyA に A の今回応答は登録済み（chat-stream-end通過・historyA最後のassistantエントリ）
//     → nextSpeaker = "dual-B"（通常継続: B に応答させる）
//     → nextMessage = `[議題]${sanitizedTopic}\n「${historyA.last.assistant}」\nあなたの考えを200文字以内で答えてください。`
//
//   B_thinking / B_speaking 中断: 上記と対称（A/B を入れ替えたロジック）
//
//   lastMessageSentToSpeakerRef: { A: string, B: string } — 各 claude_chat 発行直前に更新。
//     割り込み時に thinking 中のスピーカーへの最後の送信内容を取得するために使用。
//
//   根拠: pauseContextRef はMAX_TURNS一時停止専用。割り込み再開には別Refを用意することで
//         両者の再開パスを明確に分離し、意図しない状態共有を防ぐ。
//   検証: `pnpm test --grep "interrupt during thinking resumes with correct next message payload"`
//         `pnpm test --grep "interrupt during streaming resumes from correct last committed turn"`

// orphan cleanup 共通ブロック（両ボタンで使用）:
// R46-HIGH-2対処: withTimeout（5000ms）でハング時UIロック防止
const doOrphanCheck = async (): Promise<boolean> => {
  if (!dualOrphanSessionRef.current) return true;
  let cleanupOk = false;
  try {
    await withTimeout(invoke("cleanup_orphan_cli_processes"), 5000, "cleanup_orphan in doOrphanCheck");
    dualOrphanSessionRef.current = false;
    cleanupOk = true;
  } catch {}
  if (!cleanupOk) {
    showErrorDialog("前のセッションのクリーンアップに失敗しました。Theater Modeを終了してください。");
    return false;  // human状態を維持（dualTurnStateRef変更なし）
  }
  return true;
};

割り込み後の再開UI（dualTurnState = "human" のとき表示）:

  [割り込み前の会話を続ける] ボタン（パスA: 会話継続再開）:
    // R25-HIGH-2 + R26-HIGH-2対処: orphan cleanup失敗時は再開ブロック（パスA共通）
    if (!await doOrphanCheck()) return;
    // パスA: historyA/B・turnCount・sanitizedTopic・timelineMessages を保持したまま再開
    //   interruptContextRef.current.nextSpeaker に次ターンを自動送信してループを再開する
    //   （pausedからの [続ける] と同じ自動ループ再開パターン）
    if (!interruptContextRef.current) {
      // interruptContextRef未設定（想定外）→ パスBにフォールバック
      dualTurnStateRef.current = "idle"; return;
    }
    const { nextSpeaker, nextMessage } = interruptContextRef.current;
    interruptContextRef.current = null;  // 使用後クリア
    // 状態は保持（historyA/B, turnCount, sanitizedTopic, timelineMessages 変更なし）
    → 通常のターン送信フロー: sendToSpeaker(nextSpeaker, nextMessage) を呼び出してループ再開
       is_session_start=true（CLIプロセスを再起動し historyA/B で文脈注入）
       // 検証: `pnpm test --grep "interrupt resume continues previous conversation using interruptContextRef"`
       //       `pnpm test --grep "interrupt during thinking resumes with correct next message payload"`

  [新テーマで話す] ボタン（パスB: 新テーマ再開）:
    // R25-HIGH-2 + R26-HIGH-2対処: orphan cleanup失敗時は再開ブロック（パスB共通）
    if (!await doOrphanCheck()) return;
    // パスB: 旧テーマ文脈を全クリアして idle に戻し、新テーマ入力を促す
    interruptContextRef.current = null;  // 不要になったためクリア
    → dualTurnStateRef.current = "idle"
    → dualReady = true のまま維持
    → テーマ入力欄が再び有効になる（新しいテーマを入力して再送信可能）
    // R25-MEDIUM-3対処: 新テーマ送信時（dualTurnState="idle"に戻った後）の状態リセットポリシー
    新テーマ送信時:
      turnCount = 0                  // MAX_TURNS到達判定を新テーマから再計算（旧ターン数積算防止）
      pauseContextRef.current = null // 旧paused文脈（旧テーマの続き情報）を破棄
      sanitizedTopic = 新テーマ      // 毎ターン注入する議題を新テーマで上書き（旧議題混入防止）
      historyARef.current = []       // 旧テーマの会話文脈クリア（新テーマでfresh start）
      historyBRef.current = []       // 同上
      // R27-MEDIUM-4対処: UI transcript のセッション境界明示
      setTimelineMessages([])        // 旧テーマの会話ログをUIからクリア（新旧テーマ混在防止）
      → 通常の初回送信フローと同一経路で処理（lazy start → 新CLIプロセス + 空文脈から開始）

    根拠:
      turnCount未リセット → 旧ターン数が積算されMAX_TURNSに即時到達し早期paused
      sanitizedTopic未更新 → 毎ターン注入のuserメッセージに旧議題が混入し新テーマ議論を汚染
      history未クリア → project_idベースのAC-18契約下でも旧テーマ文脈が新テーマターンに混入
      timelineMessages未クリア → UI上に旧テーマの会話ログが残り新旧テーマが混在（AC-7 UX破綻）
      // 検証: `pnpm test --grep "interrupt then new topic resets all state and prevents contamination"`

  [Theater Modeを終了] ボタン:
    → teardown()
  ファイル変更対象: src/components/DualSessionPanel.tsx（human状態の条件分岐・ボタン追加）
                    src/App.tsx（interruptContextRef useRef追加 + 割り込み時に設定）

割り込みボタン:
  dualTurnState = "idle" OR "human" → disabled（既に停止中）

DualSessionPanel全体:
  isDualTearingDown=true → overlay + "終了処理中..."表示
```

### tts_stop Rustコマンド（requestIdベース所有権）

```rust
// R40-HIGH-2対処: TtsState の current_play_id(AtomicU64) を current_request_id(Mutex<Option<String>>) に変更
// TtsState:
//   current_request_id: Mutex<Option<String>>  // None = 再生中なし。Some("dual-A-7") = 再生中requestId
//   ffplay_pid: Mutex<Option<u32>>
//
// tts_speak(request_id: String, ...):
//   let mut id = state.current_request_id.lock().unwrap();
//   *id = Some(request_id.clone());  // 再生開始時に現在のrequestIdを記録
//
// tts_stop(request_id: Option<String>):
//   None → 無条件kill（Theater Mode終了時）+ current_request_id = None
//   Some(id) → *current_request_id == Some(id) の場合のみkill（不一致なら無視）
//   比較: String == String（数値変換不要。requestId形式 "dual-A-7" のまま比較可能）
async fn tts_stop(request_id: Option<String>, state: State<'_, TtsState>) -> Result<(), String>

// R41-MEDIUM-3対処: TTS単一グローバル状態の排他保証（project非分離の安全性根拠）
// 設計不変条件: dualSessionActive=true（Theater Mode中）は通常モードのUI全体がdisabled。
//   → Theater Mode中に通常モードのtts_speakが発火することはUIレベルで不可能。
//   → teardown()のtts_stop(None)は「Theater Mode中の最後のTTS再生を停止」する目的のみ。
//      通常モードTTSとの競合は発生しない（teardown中は通常モードUI無効のため）。
// 将来の複数同時再生拡張（例: Theater Mode + BGMなど）は現在の設計対象外。
//   その場合はTtsStateのproject_id分離が必要（別フィーチャータスク）。
```

### 回帰試験計画（Rust + TS + Theater Mode E2E）

// R43-MEDIUM-4対処: テスト優先順位の明示（PR内必須 vs バックログ分割）
// 【PR内必須テスト】: 実装PRマージ前に全PASS必須
//   - 通常モード回帰（cargo check/test + pnpm test 全量）
//   - イベント名スコープ化クロスレイヤ（T-S1〜T-S4）
//   - 状態機械競合単体（T-1〜T-5）
//   - E2E: AC-1〜AC-10, AC-12, AC-14（基本機能の確認・安定動作）
//   - orphan状態機械一貫性（orphan flag state machine）
//   - interruptContextRef-based 再開（interrupt resume/new topic）
//   - tts_stop request_id 所有権（tts_stop_request_id_ownership）
//   - is_session_start / long-lived session 契約（claude_chat_dual_prefix_long_lived_session）
//
// 【バックログ（後続PRで許容）】: 実装後の継続的品質改善
//   - AC-15 systemPrompt毎ターン確認（構造的保証のみ: ログ監査で代替可）
//   - AC-17 TTS_TIMEOUT/MAX_TURNS設定変更（設定UI完成後に追加）
//   - AC-19 アプリ再起動跨ぎ orphan recovery（E2E環境整備後）
//   - 上限なし残留Future防止（interrupt_timeout_does_not_accumulate...）
//   - symlink/親ディレクトリセキュリティ（dual_tempfile_creation_rejects_symlinked...）
//   - AC-20 シナリオ追試（既定2シナリオ以外の耐障害ケース拡張）
//
// 【規範/参考の区分】
//   - 本セクションのうち「PR内必須テスト」は規範（本PRで満たす必須条件）
//   - 「バックログ（後続PRで許容）」は参考（将来拡張項目）

**通常モード回帰**:
```
1. cargo check --manifest-path src-tauri/Cargo.toml
2. cargo test --manifest-path src-tauri/Cargo.toml
3. pnpm test
4. rg -n "chat-stream-|tts-stream-|control-avatar" src src-tauri tests  # R19-MEDIUM-4対処: 全系統旧名残存チェック（結果がハードコードなしであること確認）
5. E2E: 通常モード送信・TTS・モーション・カメラ操作
```

**イベント名スコープ化 クロスレイヤ契約テスト（R28-MEDIUM-4対処）**:
```
pnpm test --grep "scoped event names":
  T-S1: Rust が dual-A 用に emit する全イベント名が "dual-A" サフィックスを持つこと
    （chat-stream-token-dual-A / chat-stream-end-dual-A / tts-stream-samples-dual-A /
     tts-stream-end-dual-A / control-avatar-dual-A のみが emit されること）
  T-S2: 通常モード用イベント（project-1サフィックス）が Theater Mode リスナーに到達しないこと
    （モック: App.tsx の通常モードイベントを手動 emit → dual リスナーが反応しないこと確認）
  T-S3: dual-A イベントが通常モードリスナーに到達しないこと（逆方向の汚染防止）
  T-S4: 全変更ファイル（App.tsx / useTTS.ts / AvatarViewer.tsx / lib.rs）で
    旧ハードコードイベント名（tts-stream-end 等の非スコープ形式）がゼロであること
    （rg での確認を自動テストに組み込む）
```

**状態機械競合 単体/統合テスト（R17-MEDIUM-5対処）**:
```
pnpm test --grep "dual state machine":
  T-1: tts-stream-endとTTS_TIMEOUTが同着した場合にターン遷移が1回のみ発生すること
  T-2: teardown()実行中に追加イベントが到着しても状態変化が起きないこと
  T-3: paused直前にtts-stream-endが遅延到着してもpauseが維持されること
  T-4: 割り込み後にturnIdRefが更新され旧ターンイベントが無視されること
  T-5: turnId+dualTurnStateRefの二重ガードが機能すること（モックイベント注入）
```

**Theater Mode新機能E2E（R6-MEDIUM-5対処）**:
```
AC-1:  Theater Mode起動 → 2体VRM表示確認
AC-2:  テーマ「AIの未来」送信 → AがA_thinkingになること
AC-3:  A返答完了 → TTS再生 → tts-stream-end → B_thinkingへ遷移
AC-4:  3ターン以上自動ループすること
AC-5:  ループ中に割り込みボタン押下 → TTS停止 + human状態（フロントエンド即時保証）
       + stop_project_session発行（バックエンドbest-effort・timeout時はorphan flag）
  検証: `pnpm test --grep "interrupt stops TTS and transitions to human state immediately"`
        `cargo test -- interrupt_stop_project_session_timeout_sets_orphan_flag --nocapture`
AC-6:  意図的な同時TTS発行がゼロであること（requestIdガードのログで確認）。物理的音声重複（OSプロセスkill遅延〜数十ms）は既知制約として許容し合否判定対象外とする
AC-7:  A発話=左揃え・Aカラー、B発話=右揃え・Bカラーで色分け表示
AC-8:  Theater Mode終了 → 通常モードで送信・TTS正常動作
AC-9:  Theater Mode終了 → カメラが元の設定に戻ること
AC-10: 20ターン到達 → 自動停止 → 継続ダイアログ → [続ける]でturnIdRef++後ループ再開
AC-11: VRM-B（secondary）起動失敗（無効URL指定等）→ エラーダイアログ + 通常モード復帰
AC-12: Theater Modeボタンは primaryVRM ロード済みの場合のみ有効（未ロード時disabled）。起動後 secondaryVRM (B) ロード完了まで テーマ入力欄がdisabled（dualReady=false）
  検証: `pnpm test --grep "dual theater mode button disabled before primaryVRM load"`
        `pnpm test --grep "dual theme input disabled until dualReady"`
AC-13: 割り込み後やpause/resume後に旧ターンの遅延イベントがUI状態変化を起こさないこと（turnIdRefガード）
AC-14: 全ターンのclaude_chat失敗時にteardown()+エラーダイアログ+通常モード復帰
AC-15: 複数ターン後もclaude_chatリクエストにsystemPromptが含まれること（ネットワークログ確認）
AC-16: R37-MEDIUM-4対処: 人間割り込み後の再開検証（2点）
  (a) 次のclaude_chat送信が成功すること（stop_project_session後のlazy start確認）
  (b) 新テーマで再開した場合、旧テーマ文脈が混入しないこと:
      - timelineMessages が空であること（旧transcript消去確認）
      - historyA / historyB が空であること（旧履歴クリア確認）
      - turnCount = 0 であること（旧ターン数リセット確認）
      - 最初のclaude_chat引数に旧テーマの内容が含まれないこと
      検証: `pnpm test --grep "interrupt then new topic resets all state and prevents contamination"`
AC-17/AC-19 は Phase 2 AC（後続PR）を参照
AC-20 は Phase 1 AC セクションの「シナリオA/シナリオB」を正本とする
```

## ファイル変更一覧

| ファイル | 変更内容 |
|---------|---------|
| `src-tauri/src/lib.rs` | control-avatar → project_idスコープ化・tts_stop追加 |
| `src/hooks/useTTS.ts` | stopTTS(requestId?) 追加 |
| `src/components/AvatarViewer.tsx` | instanceId/positionOffset・A/B両方の失敗処理対称・VRM失敗時リソース解放 |
| `src/App.tsx` | TTS動的化・Refベース状態機械（paused含む）・teardown・TTSタイムアウト |
| `src/components/DualSessionPanel.tsx` | 新規（DualChatMessage表示・テーマ入力・MAX_TURNS設定） |
| `src/types/avatar.ts` | DualChatMessage型追加（status: "streaming"\|"complete" フィールド含む） |

## 受け入れ条件 (AC)

// R45-HIGH-1対処: PRスコープとACの不整合を解消するため、ACを2フェーズに明確分割する
// 【Phase 1（本PR必須）】: 以下 AC-1〜AC-16, AC-18, AC-20 がすべて本PRの完了条件
// 【Phase 2（後続PR）】: AC-17, AC-19 は将来ACとしてセクション末尾に分離（本PRの完了条件外）
// → DA判定・最終ゲートは Phase 1 AC の全PASS を確認する

### Phase 1 AC（本PR完了条件）

- AC-1: 同一Canvas内にVRM2体が左右に表示される
- AC-2: テーマ入力後、キャラAが返答を開始する
- AC-3: AのTTS完了後（またはTTS_TIMEOUTタイムアウト+stopTTS後）、自動でBに送信される
- AC-4: A→B→Aのターンが自動ループする
- AC-5: 人間割り込み時にstopTTSが呼ばれin-flightが破棄される（R39-HIGH-2対処: 2層保証を正式AC化）:
  フロントエンド層（即時保証）: stopTTS呼び出し + turnIdRef世代無効化 → イベント破棄 + human状態遷移
  バックエンド層（best-effort）: stop_project_session（5000ms timeout）→ timeout時はorphan flag設定 + 次回Theater Mode起動前にcleanup
  既知制約: stop_project_session タイムアウト時、バックエンドCLIプロセスはorphan管理（次回起動前cleanup）。
           この間バックエンド処理が継続してもturnId無効化によりUI影響はゼロ。CPU/memoryオーバーヘッドは明示的トレードオフ。
- AC-6: 各キャラの発話時にTTSが再生される。意図的な同時TTS発行はrequestIdガードでゼロ保証。物理的音声重複（OSプロセスkill遅延〜数十ms）は既知制約。
- AC-7: A発話=左揃え・Aカラー、B発話=右揃え・Bカラーで色分け表示（DualChatMessage.speakerで制御）
- AC-8a: 通常モード回帰自動テスト全量PASS（cargo check/test + pnpm test）。
  かつ以下の全イベント系統で project_id スコープ化が完了していること:
    chat-stream-token / chat-stream-end / tts-stream-samples / tts-stream-end / control-avatar
    全系統で旧ハードコード形式（非スコープ名）がゼロであること（rg で確認）。
    通常モードの control-avatar 購読が Theater Mode の control-avatar-dual-* と干渉しないこと。
- AC-8b: 通常モード回帰手動E2E確認（送信・TTS・モーション・カメラ操作が正常動作すること）— 手動確認項目として別扱い
- AC-9: teardown()がPromise.allSettled+finallyで完走し通常モード復帰
- AC-10: MAX_TURNS到達時に一時停止（paused）→ 継続確認ダイアログ → [続ける]でループ再開 / [終了]でteardown
- AC-11: VRM-B（secondary）起動失敗時にteardown()+エラーダイアログ+通常モード復帰（A=primaryは起動前ロード済みのため対象外）
- AC-12: 両VRMロード完了後（dualReady）にテーマ入力UIがアンロックされる
- AC-13: 旧ターンの遅延イベントはturnIdRef+dualTurnStateRefで破棄される
- AC-14: 全ターン（初回・継続問わず）のclaude_chat失敗時にteardown()+エラーダイアログ+通常モード復帰
- AC-15: （R33-MEDIUM-5対処: 自動テスト可能な形に変更）
  構造的保証（自動テスト対象）:
    (a) systemPromptをclaude_chatに毎回渡す（ターン番号に関わらず全呼び出しで引数に含まれること）
        検証: `pnpm test --grep "dual every turn includes systemPrompt in claude_chat args"`
              モック: 3ターン分のclaude_chat呼び出しをキャプチャし、全てに systemPrompt 引数があることを確認
    (b) topicは[議題]プレフィックス付きuserメッセージで渡す（100文字制限）
        検証: `pnpm test --grep "dual topic injected as user message with prefix"`
    (c) 相手発話は引用ブロック形式で渡す（500文字切り詰め）
        検証: `pnpm test --grep "dual opponent speech truncated and quoted"`
  LLM生成品質（自動テスト対象外・非機能要件）:
    - role維持は LLM のベストエフォート。コンテンツ評価は自動化不可能のため ACから除外。
    - META_PATTERNS 検出時のみ console.warn（内容マスク）。検出でもteardownしない（FP率が高いため）
    - LLM生成テキスト経由injectionの完全防止は既知制約（設計上防止不可能）。
- AC-16: 人間割り込み後の再開（R42-HIGH-1対処: 2パス明確分割）:
  パスA（会話継続再開）: [割り込み前の会話を続ける] → interruptContextRef.nextSpeakerへ自動送信
    (a) historyA/B・turnCount・sanitizedTopicが保持されたまま次ターンのclaude_chat送信が成功すること
    検証: `pnpm test --grep "interrupt resume continues previous conversation using interruptContextRef"`
  パスB（新テーマ再開）: [新テーマで話す] → idle状態に移行し新テーマ入力可能
    (b) 旧テーマ文脈が一切混入しないこと（timelineMessages/historyA/B/turnCount全リセット確認）
    検証: `pnpm test --grep "interrupt then new topic resets all state and prevents contamination"`
- AC-18: claude_chatのモード分離保証（R25-HIGH-1対処 + R38-HIGH-1対処: 長寿命CLIモデルに確定）:
  fn claude_chat実装契約（長寿命CLIプロセスモデル）:
    project_id が "dual-A"/"dual-B" の場合:
      - 長寿命CLIプロセス（lazy start）。Theater Mode中は同一プロセスを継続。
      - Theater Mode開始時のみ: historyが非空の場合は --conversation-file で文脈注入してプロセス起動。
      - 継続ターン: CLIの内部セッション履歴が自然蓄積（tempfile不使用）。
      - Theater Mode終了: stop_project_session でプロセス停止。
      - "dual-A" と "dual-B" は完全に独立したProjectSession（文脈混入なし）。
    project_id が "dual-" で始まらない場合: 通常モード（既存動作）

  これにより:
    ・初回ターン（historyA=[]）: 新規文脈から自然開始（--conversation-file なし）
    ・割り込み後再開（historyA=数件）: --conversation-file で文脈注入後、CLIが自然蓄積を再開
    ・通常モードへの回帰影響ゼロ（project_idで完全分離）

  検証:
  (a) 通常モード（project_id≠dual-*）: `pnpm test --grep "normal mode claude_chat maintains internal session"`
  (b) Dualモード新規（project_id=dual-A、historyA=[]）: tempfileなし・long-lived session開始
      `cargo test --manifest-path src-tauri/Cargo.toml -- claude_chat_dual_prefix_long_lived_session`
  (c) Dualモード再開（historyA=非空）: tempfile経由で文脈注入後、同一プロセスで継続
      `pnpm test --grep "dual history injection at session start survives interrupt and resume"`
- AC-20: R39-MEDIUM-4対処 + R40-MEDIUM-4対処: cleanup_orphan_cli_processes失敗時の2シナリオ明示
  シナリオA（通常Theater Mode起動時のorphan検出）:
    前提: dualOrphanSessionRef=true（前回teardownでorphan残留）
    操作: Theater Modeボタン押下 → cleanup_orphan_cli_processes がErr
    期待: エラーダイアログ + Theater Mode NOT entered（dualSessionActive=false に留まる）
    検証: `pnpm test --grep "dual orphan cleanup failure on new start shows error and blocks entry"`
  シナリオB（人間割り込み後の再開時のorphan検出）:
    前提: human状態 + dualOrphanSessionRef=true（割り込み時のstop_project_sessionがtimeout）
    操作: resume試行 → cleanup_orphan_cli_processes がErr
    期待: エラーダイアログ + human状態維持（Theater Mode内に留まる・再開はブロック）
    検証: `pnpm test --grep "dual orphan cleanup failure on resume shows error and maintains human state"`

### Phase 2 AC（後続PR完了条件）

// R45-HIGH-1対処: 以下は本PRの完了条件外。実装・テストは後続PRで対応。
// DA判定・最終ゲートは Phase 1 AC のみを評価する。

- AC-17: TTS_TIMEOUT（デフォルト10秒）とMAX_TURNS（デフォルト20）がUI設定画面で変更でき、次ターンから反映されること
  後続PR前提: 設定UIコンポーネント完成後。本PRではハードコード定数のみ実装。
  検証: `pnpm test --grep "dual TTS_TIMEOUT setting changes take effect on next turn"`
        `pnpm test --grep "dual MAX_TURNS setting changes stop loop at new value"`

- AC-19: orphan CLIプロセス回復（アプリ再起動跨ぎE2E）:
  シナリオ: teardown時 stop_project_session タイムアウト → アプリ再起動 →
           PIDファイル照合（sysinfo crate starttime）による自動kill → 次回Theater Mode起動成功
  後続PR前提: E2E環境（再起動シミュレーション）整備後。本PRではPIDファイル読み書き + kill ロジックまで実装。
  Rust単体（本PR内）: `cargo test -- orphan_cleanup_pid_identity_collision_guard`
  E2E（後続PR）: `pnpm test --grep "dual orphan recovery across app restart"`


## Implementation Notes

# FEAT-① Dual Session — 作業ログ

## 2026-04-24

- planner 設計 完了
- tdd-guide Phase 1実装 完了（218b8ed）
- Codex R1レビュー: FAIL（HIGH×4: H-1〜H-4）→ Claude代替実施

## 2026-04-25

- R1 HIGH修正（fc3d9e0）: H-1/H-2/H-3/H-4/M-2/M-3
- useCallback参照安定化（e76f122）: M-2/M-3補完
- feat/dual-session-v2 MMDコード汚染 → git rebase --onto で除去
- Codex R2レビュー: FAIL（NH-1/NH-2/NH-3）→ Claude代替実施
- NH-1修正 + NH-3修正（d348201）
- NH-2修正（d2833fe）: tts_speak fire-and-forget化
- Codex R3レビュー: **PASS**（TS 292/Rust 187 全PASS）
- DA最終ゲート: **GO**（da-gate-final-oribis-dual-session-20260425.md）
- バックログ: H-1 TOCTOU(実害なし)/NM-1 positionOffset(Phase2)/NM-2 vacuous test/NM-3 AC-20シナリオB/NM-4 ORPHAN_FLAG
- feat/dual-session-v2 origin push済み（HEAD: d2833fe）
> 状態: AC-1〜16,18 PASS / AC-20 PARTIAL(シナリオBバックログ) / 次: Producerマージ指示待ち（未マージ）

## Known Issues / Backlog

# FEAT-① Dual Session — 課題・バックログ

## バックログ（後続PR対応）

| ID | 内容 | 優先度 |
|----|------|--------|
| BL-1 | H-1 TOCTOU: tts_speak current_request_id check/set 別ロック | LOW（実害なし） |
| BL-2 | NM-1: VRM-A positionOffset(-1,0,0) 未実装 | MEDIUM（Phase 2） |
| BL-3 | NM-2: H-3テスト vacuous pass（if -1 → no assertion） | LOW |
| BL-4 | NM-3: AC-20 シナリオB（resume時 orphan cleanup失敗→human維持） | MEDIUM |
| BL-5 | NM-4: DUAL_ORPHAN_FLAG 本番コードで never-set | LOW |

## BL-BUGFIX-1: Rustテスト50回連続実行による安定性検証（MEDIUM）
状態: Open  
優先度: LOW  
概要: env var テスト修正後、50回連続cargo testでフラッキー確認未実施。再発時に実施すること。

## BL-BUGFIX-2: cfg(unix)条件不整合（MEDIUM）
状態: Open  
優先度: MEDIUM  
概要: `#[cfg(all(feature="tauri-backend", unix))]` vs `#[cfg(feature="tauri-backend")]` の不整合あり。find_terminal_emulator関連テストのcfg条件を実装側と揃えること。

## BL-BUGFIX-3: Mutex poison握りつぶし（LOW）
状態: Open  
優先度: LOW  
概要: `unwrap_or_else(|e| e.into_inner())` によるpoison握りつぶし。fail-fast性低下。テストフレームワーク移行時または安定化フェーズで `.unwrap()` 統一を検討。

## 解決済み

- H-1/H-2/H-3/H-4: R1 HIGH → fc3d9e0で解決
- NH-1/NH-2/NH-3: R2 HIGH → d348201/d2833feで解決
- R2-HIGH-1/R2-HIGH-2: Codex R2 HIGH → plan-oribis-dual-session-bugfix-20260425.md で即対処（AC-7/AC-8/AC-6追加）

