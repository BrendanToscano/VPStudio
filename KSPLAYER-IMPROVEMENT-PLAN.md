# KSPlayer Integration Improvement Plan — VPStudio

**Date:** 2026-04-06
**Status:** PLAN — Ready for review

---

## Current State

VPStudio uses a dual-engine architecture:
- **AVPlayer** (primary on visionOS) — native, low memory, system codec access, spatial video via APMP injection
- **KSPlayer/FFmpeg** (fallback) — broad codec support for MKV, AV1, DTS, edge formats

KSPlayer is ~70-80% visionOS-ready. The gap is in spatial audio, immersive rendering, and memory efficiency.

---

## Phase 1: Strip & Optimize FFmpeg (Reduce binary + memory)

**Impact:** -15-20 MB binary, lower memory pressure on Vision Pro M2
**Effort:** ~4 hours

### What to do
VPStudio's debrid content uses a known codec set. KSPlayer bundles the full FFmpeg with codecs you'll never hit.

**Keep:**
| Type | Codecs |
|------|--------|
| Video decoders | H.264, H.265/HEVC, AV1, VP9, VP8, MPEG-4, MPEG-2 |
| Audio decoders | AAC, AC3, EAC3, DTS, FLAC, Opus, MP3, TrueHD, PCM |
| Demuxers | MKV/WebM (matroska), MP4/MOV, MPEGTS, AVI, FLV |
| Protocols | HTTP/HTTPS, HLS (m3u8), file |

**Strip:**
- All encoders (VPStudio doesn't encode)
- Unused decoders: AMR, GSM, QCELP, RealAudio, RealVideo, WMV, WMA, Theora, COOK, ADPCM variants
- Unused demuxers: ASF, RM, RTSP, SDP, NUT, OGG (unless needed)
- All muxers
- All filters except `yadif` (deinterlace) and audio format converters

### How
Fork KSPlayer or use a custom FFmpeg build script with `--disable-everything` + explicit `--enable-decoder=X` for each needed codec. KSPlayer's build system already supports custom FFmpeg flags.

---

## Phase 2: Hardware Decode Priority (Battery + Performance)

**Impact:** 2-3x less CPU, 40% less battery drain on hardware-decoded content
**Effort:** ~3 hours

### What to do
KSPlayer defaults `hardwareDecode = true` but `asynchronousDecompression = false`. VPStudio already sets `asynchronousDecompression = true` in KSPlayerEngine — good. But there are gaps:

1. **Force VideoToolbox for AV1** on visionOS 2.0+ (M2 chip supports AV1 hardware decode natively)
   - Currently AV1 falls back to software decode
   - Check: `VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)` at runtime
   - If supported, ensure VideoToolbox path is taken (KSPlayer may not map AV1 to VideoToolbox)

2. **Prefer hardware decode for 10-bit HEVC**
   - Vision Pro M2 handles 10-bit HEVC natively
   - Verify KSPlayer's VideoToolboxDecode doesn't reject 10-bit profiles

3. **Disable software fallback for known-supported codecs**
   - For H.264, HEVC, AV1 on visionOS: if hardware decode fails, it's likely a stream issue, not a codec issue
   - Report error instead of silently falling to software (which will stutter on 4K)

### Where to change
- `KSPlayerEngine.swift` — add AV1 hardware decode preference
- Fork `VideoToolboxDecode.swift` if KSPlayer doesn't expose AV1 hardware path

---

## Phase 3: Spatial Audio Enhancement

**Impact:** Immersive audio experience for Dolby Atmos/DTS-X content
**Effort:** ~6 hours

### Current state
- VPStudio detects Atmos/DTS-HD MA as audio formats
- KSPlayer has spatial audio detection via `AVAudioSession.isSpatialAudioEnabled`
- Multi-channel output works (up to 7.1)
- But: no object-based audio positioning, no environment-aware reverb

### What to do

#### 3A: Screen-Anchored Audio Source
When in immersive mode, position the audio source at the cinema screen location instead of at the viewer:
```swift
// In HDRISkyboxEnvironment.swift, when creating the screen entity:
let audioSource = Entity()
audioSource.components.set(SpatialAudioComponent(directivity: .beam(focus: 0.5)))
audioSource.position = screenEntity.position
screenEntity.addChild(audioSource)
```
This makes audio feel like it's coming FROM the screen, not from inside your head.

#### 3B: Environment-Aware Audio
Match the audio reverb to the HDRI environment:
- **Theater HDRI** → Large room reverb, long decay
- **Living room HDRI** → Small room, short decay  
- **Outdoor HDRI** → No reverb, open air

Implement via `AVAudioEnvironmentNode` with preset reverb matching.

#### 3C: Channel Layout Passthrough
For Atmos content, ensure the full channel layout is preserved through the KSPlayer → AVAudioEngine pipeline:
- Extract `AudioChannelLayout` from FFmpeg's `AVFrame`
- Map to `AVAudioChannelLayout` for the output node
- Let visionOS handle spatial rendering of the channel bed

### Where to change
- New file: `Services/Player/Audio/SpatialAudioManager.swift`
- Modify: `HDRISkyboxEnvironment.swift` — attach audio source to screen entity
- Modify: `KSPlayerEngine.swift` — expose channel layout from KSPlayer

---

## Phase 4: HDR Tone Mapping for Vision Pro Display

**Impact:** Accurate HDR rendering on Vision Pro's micro-OLED (true blacks, 5000 nit peak)
**Effort:** ~4 hours

### Current state
- KSPlayer's Metal shaders handle PQ/HLG tone curves and ITU-R 2020 color
- But: no display-specific tone mapping for Vision Pro's unique characteristics
- Dolby Vision metadata detected but not extracted for rendering hints

### What to do

#### 4A: Extract Mastering Display Metadata
From AVPlayer's `AVAsset`:
```swift
let formatDescriptions = track.formatDescriptions
for desc in formatDescriptions {
    // Extract: kCMFormatDescriptionExtension_MasteringDisplayColorVolume
    // Extract: kCMFormatDescriptionExtension_ContentLightLevelInfo
}
```
Use this to set proper tone mapping parameters (max luminance, min luminance, MaxCLL, MaxFALL).

#### 4B: EDR Rendering for Window Mode
When playing HDR in windowed mode (not immersive):
- Use `CAMetalLayer` with `wantsExtendedDynamicRangeContent = true`
- Set `MTLPixelFormat.rgba16Float` for the render target
- This enables the full EDR pipeline on Vision Pro

#### 4C: Immersive HDR Adaptation
In immersive mode, the cinema screen `VideoMaterial` should adapt:
- Use mastering display metadata to set the material's luminance range
- Map content peak brightness to Vision Pro's display capability
- Preserve shadow detail (Vision Pro OLED handles this natively)

### Where to change
- New file: `Services/Player/Rendering/HDRMetadataExtractor.swift`
- Modify: `HDRISkyboxEnvironment.swift` — apply HDR metadata to VideoMaterial
- Modify: `PlayerView.swift` — configure EDR for windowed playback

---

## Phase 5: Subtitle Rendering in 3D Space

**Impact:** Readable subtitles in immersive mode that don't break immersion
**Effort:** ~5 hours

### Current state
- External subtitles from OpenSubtitles API parsed by custom `SubtitleParser`
- Rendered as 2D SwiftUI text overlay on the player window
- In immersive mode: flat overlay, not spatially positioned

### What to do

#### 5A: Screen-Relative Subtitle Positioning
In immersive mode, render subtitles as a RealityKit entity attached below the cinema screen:
```swift
let subtitleEntity = ModelEntity(mesh: .generatePlane(width: screenWidth * 0.8, height: 0.1))
subtitleEntity.position = [0, screenBottom - 0.05, 0] // Just below screen
subtitleEntity.components.set(UnlitMaterial(color: .clear))
// Render text to texture, apply as material
```

#### 5B: Distance-Adaptive Font Size
Scale subtitle text size based on viewing distance:
- Personal (10m): 36pt equivalent
- Cinema (20m): 48pt equivalent  
- IMAX (35m): 64pt equivalent

#### 5C: ASS/SSA Rich Subtitle Support
For anime/foreign content with styled subtitles:
- Parse ASS style tags (bold, italic, color, positioning)
- Render to `CGContext` → `MTLTexture` → `UnlitMaterial`
- Preserve original positioning and styling in 3D space

### Where to change
- New file: `Views/Immersive/ImmersiveSubtitleView.swift`
- Modify: `HDRISkyboxEnvironment.swift` — add subtitle entity to screen
- Modify: `PlayerView.swift` — route subtitle text to immersive renderer when in immersive mode

---

## Phase 6: MV-HEVC Native Support

**Impact:** True stereoscopic 3D without APMP injection overhead for native 3D content
**Effort:** ~3 hours

### Current state
- MV-HEVC detected by `SpatialVideoTitleDetector`
- Treated as generic stereo → goes through APMP injection pipeline
- APMP injection creates separate CMSampleBuffers per frame (CPU overhead)

### What to do
For actual MV-HEVC content:
- Let AVPlayer handle it natively (it supports MV-HEVC out of the box on visionOS)
- Skip APMP injection entirely
- Use `AVPlayerLayer` or `VideoPlayerComponent` which renders both eye views automatically

Detection:
```swift
// Check if track is actually MV-HEVC (not just filename detection)
if let videoTrack = asset.tracks(withMediaType: .video).first {
    let descriptions = videoTrack.formatDescriptions as! [CMFormatDescription]
    for desc in descriptions {
        let codecType = CMFormatDescriptionGetMediaSubType(desc)
        if codecType == kCMVideoCodecType_HEVC {
            // Check for multi-view extension
            let extensions = CMFormatDescriptionGetExtensions(desc)
            // Look for kCMFormatDescriptionExtension_HasLeftStereoEyeView
        }
    }
}
```

### Where to change
- Modify: `PlayerEngineSelector.swift` — force AVPlayer for verified MV-HEVC
- Modify: `APMPInjector.swift` — skip injection for native MV-HEVC
- Modify: `KSPlayerEngine.swift` — never use KSPlayer for MV-HEVC

---

## Phase 7: Memory Optimization

**Impact:** Fewer OOM crashes, smoother multitasking on Vision Pro (16 GB shared)
**Effort:** ~3 hours

### What to do

#### 7A: Shared URLSession for Downloads
Current: Each download creates a new `URLSession(configuration: .default)` (DownloadManager line 304).
Fix: Use a shared session with connection pooling:
```swift
private static let downloadSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.httpMaximumConnectionsPerHost = 4
    config.timeoutIntervalForResource = 3600
    config.urlCache = nil // Downloads don't need caching
    return URLSession(configuration: config)
}()
```

#### 7B: KSPlayer Buffer Tuning for Vision Pro
Vision Pro has 16 GB shared between GPU and CPU. Current buffers:
- High-demand: 16s max buffer = ~80 MB for 4K HEVC
- Standard: 8s max buffer = ~40 MB

Reduce for visionOS specifically:
- High-demand: 10s max buffer
- Standard: 5s max buffer
- The M2's hardware decode is fast enough that less buffering is fine

#### 7C: Texture Memory Management
When switching between immersive and windowed mode:
- Release HDRI skybox textures when exiting immersive
- Release cinema screen VideoMaterial when exiting immersive
- Pre-warm textures before entering immersive (avoid stutter)

### Where to change
- Modify: `DownloadManager.swift` — shared URLSession
- Modify: `KSPlayerEngine.swift` — visionOS-specific buffer sizes
- Modify: `HDRISkyboxEnvironment.swift` — texture lifecycle management

---

## Phase 8: KSPlayer Build Warning Fix

**Impact:** Clean build log
**Effort:** 30 minutes

### What to do
The `-D_THREAD_SAFE` FFmpeg build flag triggers Xcode warnings. Two options:

1. **PR to KSPlayer**: Remove `-D_THREAD_SAFE` from FFmpeg compilation flags (it's redundant on Apple platforms)
2. **Xcode config**: Add to Other Swift Flags: `-Xcc -Wno-unused-command-line-argument` to suppress

### Where to change
- KSPlayer's FFmpeg build script or VPStudio's Xcode build settings

---

## Priority Matrix

| Phase | Impact | Effort | Priority |
|-------|--------|--------|----------|
| 1. Strip FFmpeg | High (binary/memory) | 4h | P1 |
| 2. Hardware decode | High (battery/perf) | 3h | P1 |
| 3. Spatial audio | High (immersion) | 6h | P2 |
| 4. HDR tone mapping | Medium (visual quality) | 4h | P2 |
| 5. 3D subtitles | Medium (usability) | 5h | P3 |
| 6. MV-HEVC native | Medium (efficiency) | 3h | P3 |
| 7. Memory optimization | High (stability) | 3h | P1 |
| 8. Build warning | Low (cosmetic) | 0.5h | P4 |

**Recommended order:** 7 → 2 → 1 → 3 → 4 → 6 → 5 → 8

Start with memory optimization (immediate stability win), then hardware decode (biggest UX impact), then strip FFmpeg (binary size + memory), then work through the immersive features.

---

## Dependencies

- Phases 1, 2, 8 may require forking KSPlayer or contributing upstream
- Phase 3 requires ARKit entitlement (already present for HeadTracker)
- Phase 4 requires visionOS 2.0+ (already the deployment target)
- Phase 6 requires testing with actual MV-HEVC content files

## Risk Assessment

| Risk | Mitigation |
|------|-----------|
| FFmpeg stripping breaks edge-case codec | Keep software decode fallback for stripped codecs; test against debrid content sample set |
| AV1 hardware decode not available on older visionOS | Runtime check with `VTIsHardwareDecodeSupported` |
| Spatial audio positioning breaks stereo content | Only apply to immersive mode; windowed mode stays as-is |
| KSPlayer fork diverges from upstream | Pin to specific commit; merge upstream releases quarterly |
