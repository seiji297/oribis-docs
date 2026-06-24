# Babylon VRMA / FBX Retarget

## Overview

Babylon renderer migration work tracks VRM motion playback independently from the Three.js renderer where possible.

This document records the current acceptance procedure for:

- official VRoid Studio VRMA playback comparison between Three.js and Babylon.js
- Babylon-side VRMA humanoid track application
- Babylon-side Mixamo FBX retarget follow-up work

## Scope

In scope:

- VRM model `Idea.vrm`
- official VRoid Studio VRMA files from `C:\Users\admin\Downloads\VRMA_MotionPack\VRMA_MotionPack\vrma`
- Mixamo FBX fixture set from `animations/raw-mixamo`
- Three.js reference capture for VRMA-specific comparison only
- Babylon.js capture from the selected animation source and deterministic inspection time
- Windows QA screenshot evidence
- Babylon-side motion playback parity checks

Out of scope:

- pixel-perfect renderer equality
- MToon material parity
- springBone/nodeConstraint parity
- IK-based foot correction
- generic arbitrary-rig FBX support

## Current VRMA Retarget Definition

For Babylon.js, "VRMA retargeted" currently means:

1. Load raw `VRMAnimation` data.
2. Resolve target VRM human bones from `VRMC_vrm` / legacy `VRM` metadata.
3. Map VRMA humanoid track names to Babylon transform nodes / skeleton bones.
4. Sample rotation tracks at the requested local time.
5. Apply sampled quaternions to target bones in local space, with target base pose considered.
6. Sample hips translation and scale it by source/target rest hips height.
7. Apply expression tracks to available morph targets by preset/custom aliases.
8. While VRMA playback is active, do not layer idle/thinking/talking/typing procedural poses over it.

This is not a generic IK retargeter. It is a VRMA humanoid-track bridge:

```text
VRMA humanoid tracks
  -> VRM humanBones metadata
  -> Babylon bone nodes
  -> local rotation / hips translation / morph target influence
```

Implementation note:

- VRMA is loaded through `GLTFLoader` + `VRMAnimationLoaderPlugin` as raw `VRMAnimation`.
- Babylon.js does not use the FBX/Mixamo retarget path for VRMA.
- Babylon.js samples `VRMAnimation.humanoidTracks.rotation` and `humanoidTracks.translation` directly.
- Target nodes come from VRM `VRMC_vrm` / legacy `VRM` humanBones metadata.
- While VRMA playback is active, Babylon.js does not layer the procedural idle/thinking/talking/typing poses or finger curl on top. This is required; layering procedural hand poses over VRMA was a likely cause of previous twisted-hand artifacts.
- This path intentionally avoids `createVRMAnimationClip()` because that produces a Three.js `AnimationClip`; Babylon applies the underlying VRMA humanoid tracks directly.

## Reference QA Procedure

WDIO spec:

```text
e2e/wdio/tests/vrma-reference-visual.spec.ts
```

Capture set:

- VRMA files: `VRMA_01.vrma` through `VRMA_07.vrma`
- Renderers: `three`, `babylon`
- Angles: `rotH=-90`, `rotH=0`, `rotH=90`
- Output count: 7 files * 2 renderers * 3 angles = 42 PNG files
- This VRMA evidence set must not be mixed with the focused Mixamo FBX evidence set below.

Timing rule:

1. Three.js loads the VRMA reference.
2. Three.js seeks to a deterministic frame ratio, currently `0.25`.
3. The resulting exact `timeSeconds` is stored per VRMA.
4. Babylon.js loads the same VRMA.
5. Babylon.js seeks to the exact `timeSeconds` captured from Three.js.

Acceptance rule:

- `babylonStats.appliedCount` equals the VRMA humanoid rotation track count for the loaded file.
- `babylonStats.missingBones` is empty.
- hips translation is applied when present.
- Screenshots are reviewed at `-90 / 0 / 90` to catch side-view hand/arm failures.
- Pixel-perfect equality is not required because renderer, material, lighting, and camera projection are not identical.

Known VRMA evidence fields:

- Windows QA task: `OribisVrmaReferenceFull`
- Local evidence folder: `C:\Users\admin\Pictures\agante-projects\oribis`
- Representative Babylon stats: `appliedCount=52`, `translationAppliedCount=1`, `missingBones=[]`

Latest Babylon-only VRMA load evidence:

- Date: 2026-06-24
- WDIO spec: `e2e/wdio/tests/babylon-vrma-load.spec.ts`
- Windows QA script: `scripts/qa/run-babylon-vrma-load.ps1`
- Source files: `VRMA_01.vrma` through `VRMA_07.vrma`
- Renderer: `babylon`
- Capture frame: `frame ratio 0.25`
- Angles: `rotH=-90`, `rotH=-45`, `rotH=0`, `rotH=45`, `rotH=90`
- Output count: `7 files * 5 angles = 35 PNG files`
- QA result: `1 passing`
- Local evidence folder: `C:\Users\admin\Pictures\agante-projects\oribis\vrma-babylon-load`
- Log file: `C:\Users\admin\Pictures\agante-projects\oribis\vrma-babylon-load\wdio-babylon-vrma-load.log`
- Numeric result: all seven VRMA files reported `matchedCount=52`, `appliedCount=52`, `missingBones=[]`, `translationAppliedCount=1`.
- Visual result: captured frames are animated VRMA poses, not T-pose/A-pose fallback. The previously observed right-knee "damaged jeans" artifact is present in the Three.js reference too, so it is treated as model clothing/body clipping, not a Babylon VRMA mapping failure.

Focused knee clipping comparison:

- Date: 2026-06-24
- WDIO spec: `e2e/wdio/tests/three-vrma-knee-check.spec.ts`
- Windows QA script: `scripts/qa/run-three-vrma-knee-check.ps1`
- Source file: `VRMA_02.vrma`
- Renderer: `three`
- Capture frame: `frameIndex=109`, `timeSeconds=1.816702961921692`, `frame ratio 0.25`
- Angles: `rotH=-90`, `rotH=-45`, `rotH=0`, `rotH=45`, `rotH=90`
- Output folder: `C:\Users\admin\Pictures\agante-projects\oribis\vrma-knee-compare`
- Comparison set: matching `three-VRMA_02-frame25-*` and `babylon-VRMA_02-frame25-*` screenshots.
- Finding: the white right-knee/pants hole artifact appears in both Three.js and Babylon.js at the same VRMA frame, so it is classified as model-side clothing mesh / body clipping / skin weight behavior rather than a Babylon-specific VRMA retarget bug.

## Camera Notes

Three.js and Babylon.js do not currently have pixel-identical camera projection.

For visual comparison:

- Three.js remains the reference capture.
- Babylon.js uses QA camera values adjusted to keep the model visible at comparable inspection scale.
- Angles must match semantically (`rotH=-90/0/90`), not necessarily pixel-perfect framing.

If pixel/geometry comparison becomes required later, the next step is a controlled offscreen capture path with:

- identical model scale normalization
- identical camera projection matrix
- identical clear color
- material override to flat unlit color
- UI-free canvas-only capture

## Mixamo FBX Retarget

Mixamo FBX cannot use the VRMA path directly. Required conversion:

```text
FBX AnimationClip
  -> sample raw keyframe tracks
  -> resolve Mixamo / Unity / Auto-Rig Pro humanoid bone names
  -> VRM humanoid bone name
  -> apply FBX-rest-relative rotation / hips translation delta
  -> Babylon bone nodes
```

Babylon.js does not rely on the Three.js FBX retarget result for this path. It uses the mapping tables as source knowledge, then samples the assigned `AnimationClip` directly inside `BabylonAvatarViewer`.

Current implementation notes:

- E2E hook: `window.__ORIBIS_ASSIGN_FBX_ANIMATION__(state, url)`
- Runtime stats: `window.__ORIBIS_BABYLON_EXTERNAL_CLIP_STATE__`
- Supported mapping sources: Mixamo, Unity Humanoid, Auto-Rig Pro
- FBX loader stores source rest hierarchy metadata on `AnimationClip.userData`.
- Arms, hands, and shoulders use FBX source hierarchy world-space rest delta, then convert that result back through the target VRM parent.
- Torso and legs use local rest delta to avoid lower-body over-rotation from source/target skeleton shape differences.
- For the Mixamo fixture path, Babylon reconstructs source animated world positions from the FBX rest hierarchy and applies one-pass parent-to-child segment direction correction for legs/arms/hands.
- Hand/finger FBX quaternion tracks are not applied directly in the current Babylon path. Mixamo hand/finger local axes do not line up cleanly with the target VRM hand chains, so direct quaternion retargeting can create stretched/splayed hands even when wrist-level metrics pass. The current path uses a Three.js/three-vrm retarget pass for hand and finger quaternion tracks, then merges those tracks back into the Babylon direct-FBX body/arm/leg path. Full-body and full-upper-body replacement with the Three.js-retargeted clip were tested and rejected because they damaged `typing.fbx` arm placement; the accepted hybrid keeps shoulders/arms on the Babylon source-direction path and swaps only the hand chain.
- `hips -> upperLeg` is measured but intentionally excluded from the correction pass. `hips` is the common parent of both legs, so rotating it to satisfy one leg can damage the opposite leg and the upper body.
- This direction correction is intentionally not iterative and does not force source endpoint coordinates onto the target skeleton, because the Mixamo rig and VRM rig have different bone lengths and proportions. Acceptance is based on matching motion direction and avoiding visible inversion/stretch artifacts, not zero endpoint distance.
- Fallback when no FBX rest pose exists: `delta = inverse(frame0) * currentFrame`
- Hips translation: frame-0-relative delta, scaled by source/target hips rest height
- Procedural idle/thinking/talking/typing poses are not layered while an external FBX clip is active
- Mixamo fixture source: `animations/raw-mixamo`
- Current Mixamo fixture names: `error-defeated.fbx`, `error-sad-idle.fbx`, `greet-waving.fbx`, `idle-breathing.fbx`, `idle-standing.fbx`, `success-happy-idle.fbx`, `talking.fbx`, `thinking.fbx`, `typing.fbx`
- Non-humanoid helper bones such as skirt/bust secondary bones are ignored, not treated as retarget failures

Focused Mixamo QA evidence:

- Renderer: `babylon`
- Angles: `rotH=-90`, `rotH=0`, `rotH=90`
- Capture time: `1.5s`, clamped to the clip duration for short clips
- Output count: 9 files * 1 renderer * 3 angles = 27 PNG files
- Output names: `babylon-mixamo-fbx-*.png`
- Do not include VRMA captures, aggregate contact sheets, or unrelated FBX captures in the evidence folder for this run.
- Three.js is intentionally excluded from the Mixamo acceptance run because the Three-side FBX retarget is not treated as a correctness oracle.
- Windows QA result on 2026-06-22: `1 passing`, `1 skipped` for the intentionally skipped Three Mixamo evidence case
- Local evidence folder: `C:\Users\admin\Pictures\agante-projects\oribis`

Three.js Mixamo baseline evidence:

- Purpose: establish whether the existing Three.js / three-vrm Mixamo -> VRM path is itself a reliable visual baseline before comparing or tuning Babylon.js.
- Renderer: `three`
- Source files: same 9-file Mixamo FBX set
- Capture times: `0.5s`, `1.5s`, `2.5s`
- Angles: body captures at `rotH=-90`, `rotH=0`, `rotH=90`; close-up captures at `rotH=0`
- Output count: 9 files * 3 times * (3 body angles + 1 close-up angle) = 108 PNG files
- WDIO spec: `e2e/wdio/tests/three-mixamo-reference.spec.ts`
- Windows QA script: `scripts/qa/run-three-mixamo-reference.ps1`
- Latest Windows evidence: `C:\Users\admin\Pictures\agante-projects\oribis\three-mixamo-reference-20260623-124807` (`screenshots=108`, Windows QA `Last Result: 0`, `wdioExitCode=0`)
- Review note: the latest Three.js baseline is animated and does not show a fixed T/A-pose fallback or whole lower-body inversion in the checked frames, but several clips put arms high or in front of the chest/face and the close-up hand evidence is often occluded by sleeves. Treat Three.js as a comparison input, not a complete correctness oracle.

Focused Mixamo video evidence:

- Renderer: `babylon`
- Source files: same 9-file Mixamo FBX set
- Capture method: WebView2 canvas `captureStream(30)` via `MediaRecorder`
- Output count: 9 files * 1 renderer = 9 body WebM files, plus 9 close-up WebM files when hand/upper-body review is required
- Output names: `babylon-mixamo-fbx-*.webm`
- Output folder: `C:\Users\admin\Pictures\agante-projects\oribis\videos`
- Close-up output folder: same as the output folder above; latest body and close-up files are placed directly in `videos` with no subdirectories.
- Close-up output names: `babylon-mixamo-fbx-closeup-*.webm`
- WDIO spec: `e2e/wdio/tests/babylon-mixamo-video.spec.ts`
- One-shot proof script: `scripts/qa/run-babylon-mixamo-retarget-proof.ps1`
- Windows QA script: `scripts/qa/run-babylon-mixamo-video.ps1`
- Windows QA close-up script: `scripts/qa/run-babylon-mixamo-closeup-video.ps1`
- Windows QA result on 2026-06-23: one-shot proof task completed with `Last Result: 0`
- Windows QA one-shot task: `OribisBabylonMixamoRetargetProof`
- Latest one-shot Windows evidence: `C:\Users\admin\Pictures\agante-projects\oribis\retarget-proof-20260623-183118` (`bodyVideos=9`, `closeupVideos=9`, Windows QA `Last Result: 0`)
- Latest local video evidence: `C:\Users\admin\Pictures\agante-projects\oribis\videos` (`body=9`, `closeup=9`; old files are removed before copy; no aggregate/contact-sheet files)
- Recorded files are validated by file size and readable VP9 video frames; numeric retarget stats must still show external clip application and empty missing-bone lists for the 9-file Mixamo fixture set.
- Direction-alignment stats are emitted as `sourcePoseAlignmentBefore` / `sourcePoseAlignmentAfter`. Finger chains remain useful debug measurements, but current acceptance is visual-stability based because hand/finger FBX quaternions are retargeted through the Three.js/three-vrm clip path and merged back into the Babylon direct-FBX path rather than used raw.

Fast retarget proof workflow after a Babylon retarget code change:

1. Sync the changed frontend/spec files to `C:\oribis-qa\oribis`.
2. Run Windows QA task `OribisBabylonMixamoRetargetProof`.
3. Review the generated `retarget-proof-*` folder under `C:\Users\admin\Pictures\agante-projects\oribis`.
4. Use `debug/typing-debug.json` for fixed-time bone stats and `body` / `closeup` WebM files for immediate visual playback.

Minimum Babylon acceptance for the Mixamo 9-file set:

- all 9 Mixamo FBX files can be loaded as animation sources
- Babylon VRM model moves visibly from the FBX animation
- core body and arms do not explode
- hand/finger tracks do not force permanent stretched hands
- `__ORIBIS_BABYLON_EXTERNAL_CLIP_STATE__.stats.appliedCount > 20`
- `__ORIBIS_BABYLON_EXTERNAL_CLIP_STATE__.stats.missingBones` is empty for the chosen fixture
- evidence screenshots are placed in `C:\Users\admin\Pictures\agante-projects\oribis`
- visual review confirms the captured pose is not T-pose/A-pose fallback
- visual review checks all 9 clips from front and side angles instead of treating numeric stats alone as pass
- close-up visual review checks hand/upper-body frames for `thinking` and `typing`, because full-body captures can hide hand-end errors.

## Related Code

| Code | Purpose |
|------|---------|
| `src/components/BabylonAvatarViewer.tsx` | Babylon VRM load, VRMA application, QA hooks |
| `src/components/AvatarViewer.tsx` | Three.js reference VRMA hooks |
| `src/loaders/animationLoader.ts` | FBX/VRMA loading |
| `src/adapters/VrmAvatarAdapter.ts` | Three.js VRM external clip playback |
| `src/adapters/retargetMixamoToVrm.ts` | Existing FBX retarget mapping/correction code |
| `e2e/wdio/tests/vrma-reference-visual.spec.ts` | VRMA visual comparison hooks and Babylon-only Mixamo 9-file evidence |
| `e2e/wdio/tests/babylon-vrma-load.spec.ts` | Babylon-only official VRMA load/apply evidence |
| `e2e/wdio/tests/three-vrma-knee-check.spec.ts` | Three.js reference capture for the right-knee clipping check |
| `scripts/qa/run-babylon-vrma-load.ps1` | Windows QA runner for Babylon-only VRMA evidence |
| `scripts/qa/run-three-vrma-knee-check.ps1` | Windows QA runner for Three.js knee comparison evidence |
| `e2e/wdio/tests/babylon-mixamo-video.spec.ts` | Babylon-only Mixamo 9-file video evidence |
| `e2e/wdio/tests/babylon-mixamo-debug.spec.ts` | Fixed-time Babylon Mixamo bone debug and front/side screenshots |
| `scripts/qa/run-babylon-mixamo-debug.ps1` | Windows QA runner for fixed-time Babylon Mixamo debug evidence |
| `scripts/qa/run-babylon-mixamo-retarget-proof.ps1` | One-shot Windows QA runner for fixed-frame debug plus body/close-up Mixamo videos |
| `scripts/qa/run-babylon-mixamo-video.ps1` | Windows QA runner for Babylon Mixamo video evidence |
| `scripts/qa/run-babylon-mixamo-closeup-video.ps1` | Windows QA runner for Babylon Mixamo close-up video evidence |

## Status

| Area | Status |
|------|--------|
| VRMA raw load for Babylon | Implemented |
| VRMA bone rotation application | Implemented |
| VRMA hips translation application | Implemented |
| VRMA expression application | Implemented, depends on available morph target names |
| Windows VRMA comparison QA | Implemented |
| Pixel-perfect Three/Babylon parity | Not implemented |
| Mixamo FBX on Babylon | Implemented; Windows QA evidence required per change |
