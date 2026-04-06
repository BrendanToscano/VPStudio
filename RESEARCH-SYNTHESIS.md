# VPStudio Research Synthesis

## 1. Player Architecture & visionOS 26 APIs

### 1A. Engine Selector: AV1 Must Be Deprioritized, Not Just Scored Lower

**What the research found:** The M2 chip has **no AV1 hardware decoder**. `VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)` returns `false`. Software AV1 decode (even via dav1d with ARM NEON) draws 35-40W sustained at 4K -- thermally impossible in the headset. VP9 is in the same boat.

**What VPStudio currently does wrong:** `PlayerEngineSelector.streamRequiresKSPlayerOnVisionOS()` does not flag `.av1` as requiring KSPlayer. The comment on line 55 even says "AV1 on M2" as if AVPlayer handles it natively -- it cannot. Additionally, `PlayerSessionRouting.fallbackScore()` gives AV1 a score of 8 (only slightly below H.264's 10), treating it as a viable alternative rather than a last resort.

**Required changes:**

- In `PlayerEngineSelector`, `.av1` must route to KSPlayer on visionOS (FFmpeg's `libdav1d` software path), and should cap resolution at 1080p:
```swift
// In streamRequiresKSPlayerOnVisionOS():
case .av1:
    return true  // No HW decoder on M2; must use FFmpeg/dav1d
```

- In `PlayerSessionRouting.fallbackScore()`, AV1 should be scored negatively or near-zero to push HEVC alternatives ahead:
```swift
case .av1:
    score -= 20  // Software-only on M2, thermal risk
```

- Add a `PlayerCapabilityEvaluator` warning for AV1 content:
```swift
if stream.codec == .av1 {
    warnings.append("AV1 requires software decoding on Vision Pro (no hardware support). Expect higher power usage; 4K may not be sustainable.")
}
```

- **Ideal path:** Surface a recommendation in the stream picker UI to prefer HEVC alternatives when both AV1 and HEVC streams are available for the same content.

---

### 1B. VP9 Also Lacks Hardware Decode -- Add to VideoCodec Enum

**Currently missing:** `VideoCodec` has no `.vp9` case. VP9 is filename-detected in `streamRequiresKSPlayerOnVisionOS` via string matching ("vp9") but cannot be properly scored or warned about. Add:
```swift
case vp9 = "VP9"
```
Parse it in `VideoCodec.parse(from:)` and apply the same deprioritization as AV1.

---

### 1C. ImmersionStyle Should Be `.progressive`, Not `.full`

**What the research found:** visionOS 26 adds `.progressive` immersion (Digital Crown adjustable), which is the recommended style for cinema apps. The `.progressive(0.2...1.0, initialAmount: 0.8)` range lets users control immersion depth, and `.preferredSurroundingsEffect(.systemDark)` dims passthrough for theater ambiance.

**What VPStudio currently does:** Both `hdriImmersionStyle` and `customEnvImmersionStyle` are hardcoded to `.full` in `VPStudioApp.swift` (lines 50-51). This locks users into full immersion with no Digital Crown control.

**Required change in `VPStudioApp.swift`:**
```swift
@State private var hdriImmersionStyle: ImmersionStyle = .progressive
@State private var customEnvImmersionStyle: ImmersionStyle = .progressive

// And update the immersionStyle declarations:
.immersionStyle(selection: $hdriImmersionStyle, in: .progressive, .full)
.immersionStyle(selection: $customEnvImmersionStyle, in: .progressive, .full)
```

Also add `.preferredSurroundingsEffect(.systemDark)` to both ImmersiveSpace blocks for automatic passthrough dimming.

---

### 1D. AVExperienceController -- New API, Not Yet Integrated

**What it enables:** Programmatic transitions between embedded/expanded/immersive modes. The delegate protocol (`didChangeAvailableExperiences`, `prepareForTransitionUsing`, `didChangeTransitionContext`) gives lifecycle hooks during mode switches. Setting `configuration.expanded.automaticTransitionToImmersive = .none` forces portal mode for immersive content without full immersion.

**VPStudio has no AVExperienceController usage today.** This is a visionOS 26 addition that should be adopted when targeting the new SDK. It replaces the current manual `openImmersiveSpace`/`dismissImmersiveSpace` pattern with a more controlled transition system.

**Action:** Add as a tracked future work item for the visionOS 26 SDK target. The key benefit is glitch-free transitions -- the current `openImmersiveSpace` async approach can fail or lag.

---

### 1E. VideoPlayerComponent vs VideoMaterial -- Current Usage Is Correct but Incomplete

**What the research clarifies:**
- `VideoMaterial` (current approach for cinema screens): correct for curved/custom geometry. Provides no captions, no transport controls, no automatic aspect ratio. VPStudio already uses this on flat planes in `HDRISkyboxEnvironment`.
- `VideoPlayerComponent` (not used): auto-generates a properly proportioned mesh, renders captions natively, and in visionOS 26 supports `.portal`, `.progressive`, `.full` immersive modes plus native 180/360/Apple Immersive Video.

**Decision point:** For standard flat-screen cinema playback, `VideoPlayerComponent` would be simpler and more feature-complete (free captions, free transport controls). VPStudio should consider:
- Using `VideoPlayerComponent` as the default immersive rendering surface
- Falling back to `VideoMaterial` on custom geometry only when the user selects a curved/IMAX screen preset
- Setting `videoPlayerComponent.desiredImmersiveViewingMode = .progressive` for Digital Crown control

---

### 1F. Shared AVPlayer Pattern -- Architecture Is Confirmed Correct

VPStudio already uses a shared `VPPlayerEngine` state object injected via `.environment()` into all scenes, with the same AVPlayer continuing across window and immersive transitions. This matches the research's recommended pattern exactly. No changes needed.

---

### 2A. Memory Budget: Target < 1.5 GB, Currently Unmonitored

**Hard numbers from the research:**

| Component | Budget |
|-----------|--------|
| VideoToolbox HW decode buffers | 200-400 MB |
| Render target triple buffer (rgba16Float) | ~190 MB |
| UI, app logic, RealityKit scene | 200-400 MB |
| **Total app target** | **< 1.5-2 GB** |

Key frame sizes:
- Single 4K P010 frame: ~24 MB
- HEVC L5.1 reference buffers (16 frames): ~380 MB
- Single rgba16Float 4K render target: ~63 MB
- Foreground jetsam limit estimate: 2-4 GB (up to ~5 GB with `increased-memory-limit` entitlement, now accepted on visionOS 26)

**What VPStudio currently does:** `RuntimeMemoryDiagnostics` logs RSS at lifecycle events but takes no action on the values. There is no memory pressure response, no buffer pool management, and no jetsam-avoidance logic.

**Required additions:**
- Add `os_proc_available_memory()` polling to the player pipeline (it already exists in `LocalInferenceEngine` but not in the player path)
- Register for `didReceiveMemoryWarningNotification` and respond by releasing caches and reducing buffer pool sizes
- Add the `increased-memory-limit` entitlement to the visionOS 26 target (now valid on visionOS 26)
- Log available memory at player startup and emit warnings when crossing thresholds

---

### 2B. Zero-Copy Pipeline -- APMPInjector Uses BGRA, Should Use P010

**Critical finding:** The `APMPInjector` requests frames in `kCVPixelFormatType_32BGRA` (line 52), which forces a color space conversion from the native decode format. The research specifies the optimal pipeline:

```
VideoToolbox HW decode -> CVPixelBuffer (P010, IOSurface-backed)
  -> CVMetalTextureCacheCreateTextureFromImage (zero-copy binding)
    -> Metal fragment shader (YUV->RGB + PQ/HLG EOTF + tonemapping)
      -> CompositorServices drawable (.rgba16Float)
```

Requesting BGRA forces VideoToolbox to perform a YUV-to-RGB conversion on every frame, doubling memory bandwidth and losing the zero-copy benefit. The correct approach:
- Request `kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange` (P010) from `AVPlayerItemVideoOutput`
- Bind Y and CbCr planes as separate `MTLTexture` objects via `CVMetalTextureCache`
- Convert YUV to RGB in a Metal fragment shader at render time

**This is a significant performance change** but requires a custom Metal rendering pipeline that VPStudio does not currently have. For the AVPlayer path, the system handles this automatically. For the APMPInjector (SBS/OU stereo injection), the BGRA conversion is the practical path until a Metal renderer is built.

---

### 2C. KSPlayer FFmpeg Path -- Prefer VideoToolbox Hardware Acceleration

For the KSPlayer/FFmpeg path: configure FFmpeg to use `AV_PIX_FMT_VIDEOTOOLBOX` so decoded frames arrive as IOSurface-backed CVPixelBuffers in `frame->data[3]`. This avoids software YUV-to-RGB conversion. When software decode is unavoidable, create an IOSurface-backed `CVPixelBufferPool`, copy frames into it, then use the same CVMetalTextureCache binding.

**Action:** Verify KSPlayer's VideoToolbox integration is configured correctly. Limit FFmpeg decode threads to 2-4 on visionOS. Call `av_frame_unref()` promptly to release reference-counted buffers.

---

### 3A. MV-HEVC Detection: Asset-Level Check Is Correct, Add Runtime CMTaggedBuffer Path

**What VPStudio has:** `SpatialVideoTitleDetector.detectMVHEVC(from:)` inspects `CMFormatDescription` extensions for `HasLeftStereoEyeView`/`HasRightStereoEyeView`. This is correct and matches the research's recommended approach (reading the VEXU box metadata that surfaces through these format description extensions).

**What to add for runtime frame access (if building a custom renderer):**
```swift
// Request both MV-HEVC layers during VTDecompressionSession:
kVTDecompressionPropertyKey_RequestedMVHEVCVideoLayerIDs: [0, 1] as CFArray

// For AVPlayer-based access to stereo frames:
let spec = AVVideoOutputSpecification(
    tagCollections: [.stereoscopicForVideoOutput()]
)
let videoOutput = AVPlayerVideoOutput(specification: spec)
```

**Current gap:** For standard playback of MV-HEVC, `AVPlayerViewController` handles stereo rendering automatically -- no custom work needed. But for the immersive cinema path (VideoMaterial), VPStudio should verify that setting `.preferredViewingMode = .stereo` on the VideoMaterial controller works correctly with MV-HEVC content.

---

### 3B. SBS/OU Conversion -- APMPInjector Approach Is Viable but Has Alternatives

**The research confirms:** SBS and OU are **not natively supported** for stereoscopic playback on visionOS. VPStudio's APMPInjector approach (injecting stereo metadata extensions into CMSampleBuffers) is a valid workaround.

**Alternative approach from research:** Use `ShaderGraphMaterial` with `GeometrySwitchCameraIndex` (the Infuse approach) to render different UV regions per eye. This avoids the DisplayLink frame-copy overhead of APMPInjector.

**Apple's official conversion path:** `VTPixelTransferSession` for frame splitting + `CMTaggedBuffer` for eye tagging + `AVAssetWriterInputTaggedPixelBufferGroupAdaptor` for encoding. Export presets: `AVAssetExportPresetMVHEVC1440x1440` and `AVAssetExportPresetMVHEVC960x960`. This adds latency and is better for pre-conversion rather than real-time playback.

---

### 4A. HDR Pipeline: Metadata Extraction Is Good, Rendering Chain Is Incomplete

**What VPStudio has right:**
- `HDRMetadataExtractor` correctly reads MDCV (mastering display color volume) and CLLI (content light level info) from format descriptions
- Correctly detects PQ (`SMPTE_ST_2084_PQ`) and HLG (`ITU_R_2100_HLG`) transfer functions
- Correctly identifies Dolby Vision via fourCC codes (`dvh1`, `dvhe`, `dva1`, `dvav`)

**What's missing for a full HDR pipeline (CompositorServices path):**
```swift
// Required CompositorServices configuration:
struct HDRConfiguration: CompositorLayerConfiguration {
    func makeConfiguration(capabilities: LayerRenderer.Capabilities,
                          configuration: inout LayerRenderer.Configuration) {
        configuration.colorFormat = .rgba16Float  // REQUIRED for HDR/EDR
        configuration.isFoveationEnabled = capabilities.supportsFoveation
        let layouts = capabilities.supportedLayouts(options: [.foveationEnabled])
        configuration.layout = layouts.contains(.layered) ? .layered : .dedicated
    }
}

// CAMetalLayer configuration for EDR:
metalLayer.wantsExtendedDynamicRangeContent = true
metalLayer.pixelFormat = .rgba16Float
metalLayer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)
```

**Key constraint:** `bgr10a2Unorm` (32 bpp, 10-bit RGB) **cannot represent EDR** values > 1.0. Only `rgba16Float` works for HDR on visionOS. CompositorServices defaults to a non-HDR format and must be explicitly configured.

**For the AVPlayer path:** The system handles HDR rendering automatically through AVPlayerViewController. The extracted HDR metadata is useful for UI display (showing "HDR10"/"Dolby Vision" badges) and for the future CompositorServices custom renderer.

---

### 4B. Display Refresh Rate -- 96 Hz for 24 fps Cinema Content

Vision Pro runs at 96 Hz for 24 fps content (4x frame repeat for judder-free playback), 90 Hz standard, and 100 Hz modes. The system manages this automatically when using AVPlayerViewController. If VPStudio builds a custom frame presentation loop (CADisplayLink/CompositorServices), it must account for these variable display modes.

---

### 5A. Audio Pipeline Gaps

**Confirmed correct in VPStudio:**
- Audio session configured with `.playback` category, `.moviePlayback` mode, `.longFormVideo` policy
- `setSupportsMultichannelContent(true)` is called

**New finding -- Spatial Audio Experience API (visionOS 26):**
- Each sound source can now be assigned to its own window or volume for cross-scene audio
- Audio decoded via FFmpeg (DTS, TrueHD) should output as multichannel PCM through `AVAudioEngine` for system spatialization
- **Atmos object metadata will NOT survive** the FFmpeg decode path -- only channel-based surround is preserved

**New audio codec -- APAC (Apple Positional Audio Codec):**
- 5th-order ambisonics + up to 15 audio objects at 80:1 compression (~81 Mbps raw to ~1 Mbps)
- Mandatory for Apple Immersive Video titles
- AVPlayer handles APAC natively; VPStudio does not need to decode it manually

---

### 5B. APMP (Apple Projected Media Profile) -- New Container Metadata

A metadata-driven format within QuickTime/MPEG-4 containers for wide-FOV and immersive video. Supported by AVKit, RealityKit, Quick Look, and WebKit -- but **only in expanded and immersive modes, not inline playback**.

**Action:** When targeting visionOS 26, verify that APMP-tagged content is routed to expanded/immersive mode and not attempted in inline windows.

---

### 6. Summary: What Must Change vs What's Already Correct

**Must change (bugs/wrong behavior):**
- `PlayerEngineSelector`: AV1 is not flagged as requiring KSPlayer on visionOS (line 55 comment is misleading)
- `PlayerSessionRouting`: AV1 scored too high relative to its actual capability on M2
- `VPStudioApp`: ImmersionStyle locked to `.full` instead of `.progressive`
- `APMPInjector`: Requests BGRA format instead of preserving native P010 (performance issue, not blocking)

**Should add (missing functionality):**
- `os_proc_available_memory()` monitoring in player pipeline with jetsam-avoidance response
- `increased-memory-limit` entitlement for visionOS 26 target
- `PlayerCapabilityEvaluator` warnings for AV1 and VP9 codecs
- `.preferredSurroundingsEffect(.systemDark)` on ImmersiveSpace blocks
- `VP9` case in `VideoCodec` enum

**Already correct (confirmed by research):**
- Shared AVPlayer pattern via `@Observable` `VPPlayerEngine` + `.environment()` injection
- Dual-engine architecture (AVPlayer primary, KSPlayer/FFmpeg fallback)
- MV-HEVC detection via format description extensions in `SpatialVideoTitleDetector`
- HDR metadata extraction (MDCV, CLLI, DV fourCC detection) in `HDRMetadataExtractor`
- APMPInjector's stereo metadata injection approach for SBS/OU content
- VideoMaterial usage for custom cinema screen geometry
- Audio session configuration

**Deferred to visionOS 26 SDK adoption:**
- `AVExperienceController` programmatic transitions
- `VideoPlayerComponent.desiredImmersiveViewingMode = .progressive`
- Spatial Audio Experience API (per-window audio anchoring)
- APMP content routing

---

## 3. Competitive Landscape & Strategy

### 3.1 VPStudio's Unique Market Position -- The Gap No One Fills

No visionOS app today combines debrid streaming, TMDB-powered content discovery, broad codec support (DTS-HD MA, TrueHD, VP9, SSA/ASS subtitles), and immersive cinema environments in a single native package. Every competitor excels in one or two of these dimensions but neglects the others:

- **Infuse** = best codec breadth + zero debrid awareness, zero content discovery workflow
- **CineUltra** = best immersive environments + no debrid, no content discovery, no DTS/TrueHD
- **Moon Player** = best community environments + AI 2D-to-3D + no debrid, no Plex, weak subtitles
- **Scorpio Player** = only App Store app with explicit debrid integration + no immersive cinema, limited codecs
- **Stremio Web via Safari** = current debrid-user default on Vision Pro + no episode tracking, no addon subtitles, no environments, deeply unsatisfying UX

VPStudio's dual-engine architecture (AVPlayer + KSPlayer/FFmpeg) positions it to match Infuse's codec breadth while serving the debrid community that Infuse and every other serious player completely ignores.

---

### 3.2 Competitors by Tier

**Tier 1 -- Native visionOS Powerhouses (the quality bar)**

| App | Strengths | Weaknesses | What VPStudio should take |
|-----|-----------|------------|--------------------------|
| CineUltra | Apple 2025 "Best App on Vision Pro," real-time AI 2D-to-3D, Plex/Emby, Blu-ray ISO, HDR/DV, free with IAP | Folder browsing UX is icon-only thumbnails; no debrid; no DTS/TrueHD | AI 2D-to-3D conversion; immersive environment quality bar |
| Moon Player | AI 2D-to-3D, 12K VR support, Moon Portal community environments, $5 one-time | No Plex server integration beyond DLNA; dual subtitles overlap; no debrid | Moon Portal community environment concept; AI upscaling |
| Infuse 8 | 33+ formats, DTS-HD MA, TrueHD-to-LPCM, Plex/Emby/Jellyfin, Trakt, TMDB metadata, iCloud sync, 5 immersive envs | No debrid awareness; no content discovery workflow; $9.99/yr or $74.99 lifetime | Codec breadth target; Trakt integration; TMDB metadata approach |
| Supercut | Only app with Netflix Dolby Atmos on Vision Pro; spatial speaker positioning; $4.99 | Streaming wrapper only, not a general player | Spatial audio speaker positioning in environments |

**Tier 2 -- Specialized Spatial/VR Players**

| App | Key differentiator |
|-----|-------------------|
| SKYBOX VR Player | Best automatic 3D format detection (SBS, OU, 180, 360); PC streaming client |
| Theater | Most distinct environments (360 planetarium dome, Eagle Theater LA); strongest Plex OAuth integration |
| Plexi | Free Plex client with curved cinema screen + 2D-to-3D |

**Tier 3 -- First-Party & Major Streaming**

- **Apple TV**: Reference standard -- Cinema Environment with selectable seating, 200+ MV-HEVC 3D movies, Apple Immersive Video (180 8K 3D @ 90fps), Multiview sports
- **Disney+**: Six ILM-built branded environments (Avengers Tower, Tatooine, etc.) -- the gold standard for themed spaces
- **Netflix**: No native app, blocked Safari on visionOS 26; Supercut is only path
- **YouTube**: Native visionOS app since Feb 2026, spatial video, 8K on M5

**Tier 4 -- Debrid-Aware (VPStudio's direct competition, remarkably thin)**

| App | Status | Gaps VPStudio fills |
|-----|--------|---------------------|
| Scorpio Player | App Store, explicit RD/AD/Premiumize | No immersive cinema, limited codecs, no TMDB discovery |
| Streamer | GitHub experimental visionOS build, not on App Store | Not discoverable, unstable |
| Stremio Lite | App Store but torrent streaming stripped | Debrid-resolved HTTP only, no environments, took 6+ months of review |
| Vision Player | $4.99-$24.99 sub, broadest protocol support (HLS/RTMP/RTSP/DASH) | No debrid, no content discovery |

---

### 3.3 Features Users Are Screaming For

Source: r/VisionPro, r/Stremio, r/Plex, Firecore forums, App Store reviews.

1. **Immersive cinema environments** -- Single most requested feature across ALL media player apps. Infuse users complained for over a year before v8.3 added them. Supercut dev called it "THE most requested feature." Users want: multiple themed theaters (classic, IMAX, outdoor, sci-fi), adjustable screen size/distance/height, ambient lighting that reacts to on-screen content.

2. **Native debrid streaming** -- Stremio officially closed the Vision Pro native app request (GitHub Issue #1218, "not planned"). The Safari workaround lacks episode progress, addon subtitles, and environments. Reddit calls Stremio + Real-Debrid "the Netflix Killer that actually works" but Vision Pro gets the worst experience of any platform.

3. **DTS and TrueHD audio** -- Recurring frustration for UHD Blu-ray collection owners. Only Infuse handles TrueHD on visionOS. Only Infuse + nPlayer handle DTS-HD MA.

4. **Native Plex/Jellyfin** -- Plex explicitly stated "not currently developing a dedicated Vision Pro app." Users cobble together Infuse, Theater, CineUltra, and Aurora with no single solution matching native Plex on other platforms.

5. **4K sharpness in passthrough** -- "UHD content looks blurry if not scaled close to 1:1 ratio" but at 1:1 the screen is too close. Only fix: immersive environments (further reinforcing their importance).

---

### 3.4 Pricing Strategy

Vision Pro owners spent $3,499 on hardware and demonstrate high willingness to pay. Market patterns:

- **Sweet spot: one-time $5-$10** -- Supercut ($4.99), Moon Player ($5), SKYBOX ($9.99), Theater ($4). Users describe these as "worth every penny."
- **Freemium/subscription works at scale** -- Infuse ($9.99/yr or $74.99 lifetime), Plex Pass ($69.99/yr or $249.99 lifetime).
- **No Vision Pro-specific pricing tiers exist** -- all apps price identically across Apple platforms.
- **Free-with-ads is nearly nonexistent** on Vision Pro.

**Recommended for VPStudio**: $7.99-$9.99 one-time purchase, OR freemium with $4.99/yr subscription. The debrid audience already pays $3-$10/month for debrid services and will accept a premium price for a quality native client.

---

### 3.5 Dual-Distribution Strategy (App Store vs Sideload)

Apple's Guideline 5.2.3 ("Apps should not facilitate illegal file sharing") and 2.3.1 (no hidden features) create a hard constraint. Key precedents:

- **Stremio**: Full app removed from App Store early 2026. Stremio Lite took 6+ months of review, then was temporarily removed again.
- **Kodi**: Never on App Store; core team considers it philosophically incompatible. Fork MrMC succeeded only by removing ALL addon/plugin support.
- **Infuse**: Connects to Real-Debrid via WebDAV (dav.real-debrid.com) as "network share" -- never mentions debrid in marketing.
- **Wako**: Positions as "Movie, TV Show & Anime Tracking App," debrid support buried in unofficial third-party addons with explicit disclaimers.
- **Scorpio Player**: On App Store with explicit debrid service names -- most aggressive positioning that has survived review.

**Feature risk map:**

| Risk Level | Features |
|------------|----------|
| HIGH (likely rejection) | Built-in torrent indexer (Torrentio, YTS, Jackett), TMDB-browse-to-indexer-to-debrid pipeline as single workflow, any "torrent" reference in code/metadata |
| MEDIUM (mixed precedent) | Debrid API if positioned as "cloud storage" / "WebDAV," TMDB display without direct streaming, custom URL playback |
| LOW (clear precedent) | Generic player from URLs/shares/WebDAV, Plex/Emby/Jellyfin, Trakt, TMDB for library metadata, immersive environments, codec support |

**Recommended architecture:**

- **App Store version (VPStudio Player)**: Spatial media player + broad codecs + immersive HDRI environments + 3D playback + network shares (SMB, WebDAV, FTP, DLNA) + Plex/Emby/Jellyfin + Trakt/Simkl + OpenSubtitles + spatial audio. Debrid users connect via WebDAV endpoints (as Infuse users already do). No content discovery, no indexer, no debrid mention. Screenshots show player and environments only.
- **Sideload version (VPStudio Full)**: All features including TMDB discovery, torrent indexer integration, direct debrid API streaming, AI content curation. Distributed as IPA via GitHub releases or website. EU users may access via alternative marketplaces under the Digital Markets Act.
- **TestFlight**: Intermediate channel (up to 10K testers, 90-day expiration) but still requires Beta App Review and carries rejection risk.

---

### 3.6 Specific Features to Steal

| Feature | Source App | Priority | Rationale |
|---------|-----------|----------|-----------|
| AI 2D-to-3D real-time conversion | Moon Player, CineUltra | HIGH | Most praised differentiator; users consistently highlight it; table-stakes for serious visionOS players |
| Moon Portal community environments | Moon Player | MEDIUM | User-generated-content moat; lets community build and share custom virtual cinemas; reduces VPStudio's environment creation burden |
| SharePlay collaborative viewing | Bigscreen, Theater (in dev) | MEDIUM | visionOS 26 adds nearby SharePlay (same room, no FaceTime); only Bigscreen seriously pursuing it; differentiation opportunity |
| Foveated Streaming API | New in visionOS 26.4 | HIGH | Exposes gaze region for adaptive bitrate -- prioritize quality where user looks; novel optimization for debrid streaming bandwidth |
| Spatial Widgets (persistent watchlist) | Moon Player (Poster Wall) | LOW | visionOS 26 feature; pin Trakt/Simkl watchlist as spatial widgets on walls/tables across sessions |
| Audio ray tracing / room acoustics | visionOS 26.4 APIs | MEDIUM | RealityKit ReverbComponent + Spatial Audio Experience API; simulate theater acoustics in cinema mode; visionOS 26.4 stores room profiles |
| Selectable seating positions | Apple TV | HIGH | Floor/balcony, front/middle/back presets; best-practice for cinema environments |
| Auto 3D format detection | SKYBOX | MEDIUM | Correctly identifies SBS, OU, 180, 360 without manual config |
| Poster Wall / spatial content browsing | Moon Player | LOW | Pin favorite films as spatial widgets in physical space; novel content discovery leveraging Vision Pro's unique capability |

---

### 3.7 Competitive Feature Matrix -- Where VPStudio Wins vs Loses

| Capability | VPStudio (planned) | Infuse 8 | CineUltra | Moon Player | Scorpio | SKYBOX |
|---|---|---|---|---|---|---|
| **Debrid streaming** | **WIN** | -- | -- | -- | Partial | -- |
| **TMDB discovery workflow** | **WIN** | Library only | -- | -- | -- | -- |
| **DTS-HD MA decode** | **WIN** | TIE | -- | Partial | -- | -- |
| **Dolby TrueHD decode** | **WIN** | TIE | -- | Partial | -- | -- |
| **VP9 decode** | TIE | TIE | Partial | TIE | -- | TIE |
| **MV-HEVC 3D** | TIE | TIE | TIE | TIE | -- | TIE |
| **SSA/ASS styled subs** | TIE | TIE | Partial | Partial | -- | TIE |
| **PGS/SUP bitmap subs** | TIE | TIE | Partial | Partial | -- | TIE |
| **Immersive environments** | Building (HDRI) | 5 envs | **LOSE** | **LOSE** (community) | -- | 4 envs |
| **AI 2D-to-3D conversion** | Not yet | -- | **LOSE** | **LOSE** | -- | -- |
| **Plex/Emby/Jellyfin** | Planned | **LOSE** | **LOSE** | DLNA only | -- | -- |
| **Trakt sync** | Planned | **LOSE** | -- | -- | -- | -- |
| **SharePlay** | Not yet | -- | -- | -- | -- | -- |
| **Environment count/quality** | Early | Mature | **LOSE** | **LOSE** (UGC) | -- | Mature |

**Summary of position**: VPStudio's decisive wins are in the debrid + TMDB + codec triangle -- no competitor even attempts this combination. The decisive losses are in environment maturity and AI 2D-to-3D, both of which are addressable through development investment. The Plex/Trakt integrations are table-stakes that need to ship but don't differentiate.

---

### 3.8 Five Strategic Priorities (Ranked)

1. **Match Infuse's codec breadth** -- DTS-HD MA, TrueHD-to-LPCM, VP9, full SSA/ASS and PGS subtitle rendering. The dual-engine architecture enables this; execution must be flawless.
2. **Invest heavily in HDRI environments** -- Minimum 5 distinct environments with adjustable seating position and reactive ambient lighting. This is the feature users most associate with Vision Pro's value.
3. **Implement AI 2D-to-3D conversion** -- Match Moon Player and CineUltra's most praised differentiator. Without this, VPStudio loses head-to-head comparisons in every review.
4. **Ship the dual-distribution model** -- App Store "player" version for discoverability; full-featured sideload version for debrid power users. The Infuse/Wako model (never mention debrid, use WebDAV) is the proven template.
5. **Price at $7.99 one-time or $4.99/yr** -- Competitive with Supercut/SKYBOX while reflecting broader feature set. The debrid audience will pay.

## 4. Subtitle Rendering in Immersive Space

### The Core Problem

`VideoMaterial` **cannot render captions**. Apple confirmed this in WWDC23 session 10070: apps using `VideoMaterial` on custom geometry must implement their own entire caption rendering system. Apple TV+, Disney+, and IMAX all sidestep this by delegating to `AVPlayerViewController`, which VPStudio cannot use for its virtual cinema screen. The new visionOS 26 `VideoPlayerComponent` and `AVExperienceController` APIs restore system caption support for Apple's own immersive video pipeline, but not for custom `VideoMaterial` surfaces. Every subtitle in VPStudio must be custom-rendered.

### Unified Texture-Overlay Architecture

All subtitle formats -- text-based (SRT, ASS/SSA, WebVTT) and bitmap-based (PGS, VobSub) -- converge on a single rendering path:

1. **Parse/decode** the subtitle data for the current timestamp
2. **Generate an RGBA texture** at the cinema screen's resolution
3. **Apply it as an `UnlitMaterial`** on a transparent `ModelEntity` plane parented slightly in front of the video surface in RealityKit

For text formats, `swift-ass-renderer` (or direct libass) produces the texture. For bitmap formats, FFmpeg decodes images directly into the same texture pipeline. This unified path means one overlay entity, one material setup, and one update loop regardless of subtitle format.

### swift-ass-renderer: The Key Integration

The **`swift-ass-renderer`** library (MIT license, v1.3.1, December 2024) is the strongest candidate for ASS/SSA rendering. Key facts:

- Wraps libass via `swift-libass`, which ships prebuilt xcframeworks for libass, FreeType, FriBidi, HarfBuzz, and FontConfig
- **Confirmed visionOS builds** via Swift Package Index (tested across Swift 5.10, 6.0, 6.1, 6.2)
- Pure Swift Package Manager dependency -- low integration complexity
- Rendering pipeline: calls `ass_render_frame()`, composites alpha layers via `AccelerateImagePipeline` into a single RGBA `CGImage`, convertible to Metal texture via `MTKTextureLoader`
- Thread-safe; already proposed for Jellyfin/Swiftfin (Issue #1892)
- CPU-side compositing via Accelerate (not GPU-native Metal), but subtitle overlays are small regions updated infrequently -- unlikely bottleneck

**Practical integration note:** KSPlayer already uses FFmpegKit which bundles prebuilt libass xcframeworks for visionOS. VPStudio can leverage those existing xcframeworks with `swift-ass-renderer`'s compositing pipeline, or build a custom Metal compute shader for higher performance.

libass handles all ASS animation and positioning internally -- `\move`, `\fad`, `\t`, `\k`/`\kf` karaoke, `\pos(x,y)`, `\an1`-`\an9`, `\frx`/`\fry`/`\frz` transforms -- as a stateless renderer. Provide a timestamp, receive correct bitmaps. No RealityKit animation integration needed.

### DMM-Based Sizing (Not Arbitrary Point Sizes)

The current implementation (36pt at 10m, 60pt at 20m, 80pt at 35m) uses arbitrary point sizes that need validation. **Replace with DMM-based sizing** for guaranteed consistent readability.

**DMM (Distance-independent Millimeter):** 1 DMM = 1mm of physical height at 1m viewing distance = ~0.0573 degrees of visual angle.

| Use Case | Minimum | Target | Angular Size |
|---|---|---|---|
| Subtitle text (quick reading) | 24 DMM | **30--35 DMM** | 1.38--2.0 degrees |
| Absolute minimum (still legible) | 16--20 DMM | -- | 0.92--1.15 degrees |

**Formula:** `text_height_meters = target_DMM * distance_meters / 1000`

At 32 DMM target: 320mm at 10m, 640mm at 20m, 1120mm at 35m in world space. At Vision Pro's 34 PPD, this spans ~62 display pixels -- more than sufficient for crisp rendering.

### MACaptionAppearance: Mandatory Accessibility APIs

When rendering custom captions, Apple **requires** respecting the user's system caption styling preferences via `MACaptionAppearance` (MediaAccessibility framework). This is not optional -- it is an accessibility requirement. APIs to query:

- `MACaptionAppearanceCopyFontDescriptorForStyle` -- user-preferred font
- `MACaptionAppearanceGetForegroundColor` / `GetBackgroundColor` / `GetWindowColor` -- colors
- `MACaptionAppearanceGetForegroundOpacity` / `GetBackgroundOpacity` / `GetWindowOpacity` -- opacity
- `MACaptionAppearanceGetTextEdgeStyle` -- edge treatment (none, raised, depressed, uniform, drop shadow)
- `MACaptionAppearanceGetRelativeCharacterSize` -- user's preferred relative text size (must be used to scale DMM target)

Also required: check `UIAccessibility.isClosedCaptioningEnabled` and observe `closedCaptioningStatusDidChangeNotification`. RealityKit does not natively support Dynamic Type, so manual scaling via the relative character size API is the only path.

### Pop-On Captions Only (Roll-Up Causes Nausea)

Per WWDC23 session 10034 ("Create accessible spatial experiences"): **use pop-on captions, never roll-up**. Roll-up captions (word-by-word appearance) cause "reading fatigue and nausea when reading for a long duration" in spatial experiences. Full-phrase display (pop-on) is mandatory for XR comfort.

### PGS/VobSub Bitmap Subtitle Handling

Bitmap subtitles feed into the same unified texture-overlay pipeline:

- **PGS** (Blu-ray): full-color bitmaps with transparency at source resolution (1080p or 4K UHD). Decoded via FFmpeg's `hdmv_pgs_subtitle` codec. MKV CodecID: `S_HDMV/PGS`.
- **VobSub** (DVD): 4-color palette, RLE-compressed, DVD resolution (720x480 or 720x576). Decoded via FFmpeg's `dvd_subtitle` codec. MKV CodecID: `S_VOBSUB`.

**Scaling concern:** VobSub at DVD resolution looks noticeably soft when scaled up. Mitigations: edge-aware upscaling via custom Metal compute shader (bicubic/Lanczos), or **OCR conversion** via Apple's Vision framework (`VNRecognizeTextRequest`) -- native, on-device, no external dependencies. OCR loses original styling, so the practical recommendation is: **direct bitmap rendering as default**, optional OCR-to-text as an accessibility feature for Dynamic Type and VoiceOver.

### Font and Background Treatment

**Font:** SF Pro Medium or Bold. visionOS already uses Medium weight for body text (heavier than iOS Regular). SF Pro auto-switches between "Text" (<20pt) and "Display" (>=20pt) optical variants. For multilingual content, fall back to Noto Sans. **Never use weights lighter than Medium. Never use serif fonts** -- thin strokes "vibrate" at VR resolutions.

**Background:** Semi-transparent black box at **60--70% opacity**, combined with a **1.5--2px black text outline** for maximum edge sharpness. On Vision Pro's OLED displays, deep blacks make this treatment exceptionally clean. For HDR content, increase box opacity to 75--80%. Target WCAG AAA contrast ratio (7:1 minimum). Keep line length under 40 characters.

### Format Support Priority

| Priority | Formats | Coverage |
|---|---|---|
| Must support now | SRT, ASS/SSA, WebVTT | 95%+ of local media files |
| Should support | PGS, VobSub | Blu-ray and DVD rips |
| Good to add | IMSC1/TTML | Future-proofing for streaming |
| Watch only | W3C/MPEG-I spatial subtitle standards | No spec finalized yet |

### Implementation Pipeline (Per Frame)

1. Use `CADisplayLink` or player frame callback to invoke libass / FFmpeg decoder at current playback time
2. Composite resulting alpha bitmaps into a Metal texture (via Accelerate or custom Metal compute shader)
3. Apply as `UnlitMaterial` on plane entity parented to cinema screen entity
4. Use libass `detect_change` flag to skip re-rendering when subtitles have not changed
5. Query `MACaptionAppearance` on launch and on notification, apply user overrides to all rendering parameters

---

## 5. Debrid Integration & Streaming Architecture

### 5.1 Per-Service API Comparison

| Service | Rate Limit | Auth Model | Batch Cache Check | IP Restriction | Link Expiry |
|---------|-----------|------------|-------------------|----------------|-------------|
| **Real-Debrid** | 250 req/min | OAuth2 device-code or Bearer token | Yes (hashes in URL path) | **Strict single-IP** -- multi-IP risks permanent ban | ~6 hours, IP-locked |
| **TorBox** | 60/hr (creation endpoints) | API key Bearer | Yes (hex hashes) | **None** -- account sharing allowed | Resets on each request |
| **AllDebrid** | 429-enforced (undocumented threshold) | API key + mandatory `agent` param | **No** (individual only) | Moderate single-IP | ~hours |
| **Premiumize** | Fair-use point system (no fixed cap) | API key/OAuth2/device pairing | Yes -- **free endpoint** (zero quota cost) | None | Session-based |
| **Debrid-Link** | 250 req/min | Bearer/OAuth2 device flow | Yes (comma-separated) | Undocumented | Undocumented |
| **Offcloud** | Undocumented | API key (query param) | Yes (hash array POST) | Undocumented | Undocumented |
| **EasyNews** | None documented | HTTP Basic Auth | N/A (Usenet -- content either exists or doesn't) | Plan-dependent | **No expiry** while subscribed |

**Key takeaways for VPStudio's abstraction layer:**
- Premiumize `/cache/check` is free -- use it for aggressive pre-filtering without quota penalty.
- AllDebrid requires the `agent` string on every request -- bake it into the client init, not per-call.
- Real-Debrid's single-IP policy is the strictest; proxy-mode architectures (like Comet) exist specifically to work around this.
- EasyNews is fundamentally different: no caching concept, no link expiry, direct HTTP streaming with Basic Auth.

---

### 5.2 Just-in-Time Resolution Pattern

**Core rule: never pre-resolve CDN URLs.** Store only the torrent hash + file ID. Resolve the actual CDN link only at the moment playback begins.

The pattern the ecosystem has converged on:
1. Build stream list using hashes and metadata (no API calls to unrestrict).
2. User presses play -> call `/unrestrict/link` (Real-Debrid) or equivalent -> get fresh CDN URL -> hand to AVPlayer.
3. If AVPlayer hits HTTP 403/404 mid-stream -> re-resolve the same hash -> seek to saved position -> resume. Retry limit: 2-3 attempts.
4. For continuous playback >3 hours, proactively re-resolve in the background (novel optimization -- not commonly implemented elsewhere).

**Why this matters:** CDN URLs are IP-locked (Real-Debrid) and time-limited (~6 hours). Pre-resolving wastes quota and produces stale links by the time the user actually watches.

---

### 5.3 Three-Tier Cache Architecture

| Tier | Backing Store | TTL | Contents |
|------|--------------|-----|----------|
| **L1** | `NSCache` (in-memory) | 15-30 min | Availability results being actively browsed, resolved URLs, current watchlist metadata |
| **L2** | SQLite or Core Data | **24 hours** (availability), **30 days** (torrent metadata: hash, title, quality, file list) | Cross-session persistence, eliminates redundant API calls between app launches |
| **L3** | Live API call | N/A (fallback) | Per-service rate limiter enforced (250 req/min for Real-Debrid) |

**Production-tested TTLs from open-source projects:**
- Comet: `CACHE_TTL = 86400` (24h), `BACKGROUND_SCRAPER_SUCCESS_TTL = 604800` (7-day re-scrape cooldown)
- Sootio: `SQLITE_CACHE_TTL_DAYS = 30` (up to 180 days), with priority-based checking (top 20 highest-quality hashes first, quality quotas per category: Remux 2, BluRay 2, WEB-DL 2 -- stop once quotas met)

---

### 5.4 Season Pack Detection -- Zero API Cost for Subsequent Episodes

**The most underutilized optimization in the debrid ecosystem.** When a user is watching from a full-season torrent pack, every subsequent episode is already available as a different file index within the same torrent -- zero additional API calls required. VPStudio only needs to select the correct file index at transition time.

Implementation:
- On initial playback, record whether the source is a season pack (multi-file torrent with episode pattern).
- For subsequent episodes in the same season, skip all availability checks and unrestrict calls -- just reference the next file index.
- This converts an N-API-call binge session into a 1-API-call binge session.

---

### 5.5 Episode Pre-Fetching Timing

**Trigger point: 75-80% playback completion.**
- At 50%: too many wasted API calls (users frequently stop mid-episode).
- At 75-80%: a 1-hour episode leaves ~12 minutes of preparation time -- sufficient for cache checks and metadata resolution.
- Credits detection: AVFoundation chapter metadata or a "less than 3 minutes remaining" threshold -> show Next Up UI.

**Critical: pre-fetch metadata, not CDN URLs.** The full flow:
1. 75% completion -> check if current source is a season pack.
2. Season pack -> record file index for next episode (**zero API cost**).
3. Individual torrent -> background cache check -> resolve hash if needed.
4. Store result as hash + file ID only (never a CDN URL).
5. Episode ends -> Next Up UI -> user confirms or auto-play fires.
6. Just-in-time: call unrestrict API -> fresh CDN URL -> begin playback -> target **<2 second transition**.
7. After 3-4 consecutive auto-plays, show "Still Watching?" prompt to prevent runaway pre-fetching.

---

### 5.6 Real-Debrid instantAvailability Removal -- Alternatives

Real-Debrid removed `/torrents/instantAvailability`, breaking the standard cache-check workflow across the entire addon ecosystem. Alternatives:

- **Zilean**: Indexes all DMM (Debrid Media Manager) community-shared hashlists. Returns infohash + filename pairs for content **almost certainly already cached** on debrid services. Self-hosted via Docker; initial indexing requires ~6-7 GB RAM; uses Lucene-based search.
- **Crowdsourced cache databases**: Torrentio, MediaFusion, and StremThru record which torrents users successfully stream, sharing data across all users.
- **StremThru shared cache**: Aggregated user-behavior-driven cache data. VPStudio could integrate with this or build its own behavioral cache.
- **Local L2 cache becomes even more important**: With the API endpoint gone, VPStudio's own SQLite cache of previously-successful hashes is the fastest path to confirming availability.

---

### 5.7 Failover Architecture

#### Health Scoring & Circuit Breakers

- Run lightweight health probes every 60 seconds against unauthenticated endpoints: Real-Debrid `GET /time`, AllDebrid `GET /v4/ping?agent=VPStudio`.
- Track per-service health score (exponential moving average of success/failure), circuit breaker state, and latency.
- Resolution flow: sort services by circuit state (CLOSED first) -> health score x priority weight -> attempt -> on retryable failure, record and try next service -> on non-retryable failure (auth error, not cached), handle specifically without failover.
- Circuit breaker parameters: **5-failure threshold**, **60-second recovery timeout**, supplemented by a shared token bucket governing total retry budget across all services.

#### Retry Classification by HTTP Status

| Category | Status Codes | Action |
|----------|-------------|--------|
| **Retryable (same service, backoff)** | 429, 500, 502, 503, 504 | Exponential backoff with full jitter: `random(0, min(1s x 2^attempt, 30s))`, max 3 attempts. Respect `Retry-After` header on 429. |
| **Failover immediately** | 403 (account locked/IP ban), 404 (content gone) | Skip to next service in priority list. |
| **Token refresh then single retry** | 401 (expired token) | Refresh OAuth token, retry once. Real-Debrid error codes 9, 12, 13, 14 trigger `reset_authorization()`. |
| **Silent cross-provider check** | "Torrent not cached" response | Not an error -- try the same hash on other providers. |

#### Geographic Diversification

Real-Debrid, AllDebrid, and Debrid-Link are all France-based. In November 2024, FNEF anti-piracy enforcement simultaneously disrupted all three for weeks. **Maintain at least one non-France-based provider** (TorBox, Premiumize, Offcloud) as insurance against correlated regulatory action.

---

### 5.8 HTTP Streaming Best Practices

#### AVPlayer Configuration
- **moov atom**: MP4 files must have the moov atom at the beginning (faststart). Without this, AVPlayer cannot determine duration or support seeking. Detect and handle gracefully when debrid CDNs serve non-faststarted files.
- **Buffer tuning**: Set `preferredForwardBufferDuration = 30` seconds as baseline. Adaptive adjustment: <1 Mbps -> 60s, >5 Mbps -> 15s. Monitor via `AVPlayerItem.accessLog()` -> `observedBitrate`.
- **Leave `automaticallyWaitsToMinimizeStalling = true`** (default) -- let AVPlayer manage stall prevention.

#### AVAssetResourceLoaderDelegate for Mid-Stream Token Refresh
- Use a custom URL scheme with `AVAssetResourceLoaderDelegate` for full control over `URLSession` -- authentication headers, range requests, retry logic.
- Handle HTTP 403 as expired CDN token (not true auth failure) -> trigger re-resolution flow.
- Avoid undocumented `AVURLAssetHTTPHeaderFieldsKey` -- risks App Store rejection.

#### URLSession Configuration for Streaming
- `timeoutIntervalForRequest = 60` (seconds between data chunks)
- `timeoutIntervalForResource = 86400` (24 hours -- multi-GB files)
- `waitsForConnectivity = true`
- `multipathServiceType = .handover` (seamless WiFi-to-cellular transition)
- `urlCache = nil` (never cache multi-GB video data)
- `httpMaximumConnectionsPerHost = 4`
- Headers: `Accept-Encoding: identity`, `Connection: keep-alive`

#### AVPlayer vs KSPlayer Decision Matrix

| Use AVPlayer when... | Use KSPlayer (FFmpeg backend) when... |
|---------------------|--------------------------------------|
| Standard MP4/MOV with H.264/H.265 + AAC | MKV, AVI, or non-Apple-native containers |
| Hardware decoding / battery life priority | DTS audio or non-AAC/AC3 codecs |
| Standard SRT subtitles | Embedded ASS/SSA subtitle rendering |

KSPlayer supports visionOS and exposes `preferredForwardBufferDuration`, `maxBufferDuration`, `isSecondOpen` (fast start), `isAccurateSeek`.

---

### 5.9 App Store Compliance Tiers

**The Scorpio Player precedent (2025):** Currently approved on iOS, macOS, tvOS, and visionOS with explicit debrid mentions ("Real-debrid, All-debrid, Premiumize.me"), plus Jackett and Sonarr/Radarr API integration listed. This is the strongest existing precedent for named debrid integration in the App Store, though Apple's enforcement is inconsistent.

| Tier | Risk Level | What's Included | Precedent Apps |
|------|-----------|-----------------|----------------|
| **Tier 1** | Lowest | Generic media player: WebDAV, SMB, SFTP, HTTP URLs. Zero debrid knowledge -- users connect via middleware (Zurg). | Infuse, VLC, nPlayer, Outplayer |
| **Tier 2** | Moderate | Named debrid as one of many cloud sources. User supplies own API key. "Stream from your own account" framing. | **Scorpio Player** |
| **Tier 3** | High / certain rejection | Content discovery + debrid streaming combined. Browsing/searching for content within the app. | Stremio Lite (removed), Ferrite (sideload only) |

**Recommended dual-distribution strategy:**
- **App Store version**: High-quality media player with WebDAV, SMB, SFTP, HTTP, cloud storage (Google Drive, Dropbox, OneDrive), local files, Trakt sync, subtitles. Optionally include debrid as a named source (Tier 2, following Scorpio precedent) with "your own account" framing. **Exclude**: content catalogs, torrent search, indexer integration, community addon/plugin system.
- **Sideload / TestFlight version**: Full-featured with torrent indexer integration, content discovery, and advanced debrid features for power users.

**Key guidelines**: 5.2.3 (no facilitating illegal file sharing) and 1.4 (no facilitating illegal media sharing). Legal safeguards: demonstrate substantial non-infringing uses (Betamax doctrine), never market as a piracy tool (Grokster risk), register DMCA agent, implement repeat-infringer policy.

---

### 5.10 Content Discovery Sources

| Source | Type | Key Value |
|--------|------|-----------|
| **Zilean** | DMM hashlist index | Content almost certainly cached on debrid services; primary source for cache-first workflows |
| **BitMagnet** | Self-hosted DHT crawler | Autonomous indexing (~5,000 torrents/hr), TMDB classification, GraphQL + Torznab APIs, can import RARBG dump |
| **Comet** | Stremio addon / scraper aggregator | Pulls from Jackett, Prowlarr, Torrentio, Zilean, MediaFusion, BitMagnet; includes CometNet (decentralized metadata sharing) |
| **AIOStreams** | Super-addon aggregator | Built-in scrapers for Knaben, Zilean, AnimeTosho, TorrentGalaxy, BitMagnet |
| **MediaFusion** | Multi-language addon | Tamil, Hindi, Malayalam support; live sports |
| **Knaben Database** | Multi-search cached proxy | Aggregates TPB, 1337x, Nyaa.si |
| **Orionoid** | Commercial API | Pre-filtered by resolution/codec/audio/cache status; $0-$199 lifetime |
| **Jackett / Prowlarr** | Torznab proxy | Broad indexer coverage via standardized API |
| **NZBHydra2** | Usenet aggregator | Unified Newznab endpoint with deduplication across NZBgeek, NZBFinder, DrunkenSlug |
| **SeaDex + AnimeTosho** | Anime-specific | Curated best releases (SeaDex), comprehensive anime indexing (AnimeTosho) |

**Recommended stack for VPStudio**: Zilean (primary, cache-likely content) + Jackett/Prowlarr (broad coverage) + TMDB (metadata/matching) + Trakt (watchlist/history/scrobbling). All hash-providing sources feed the core workflow: collect hashes -> batch-query debrid availability -> filter to cached -> instant streaming.

---

## 6. GPT Research: Player Architecture Additions

The following findings come from GPT deep research on visionOS player architecture. Only items that ADD to or CORRECT what is already documented above are included. Items that merely confirm existing findings are omitted.

---

### 6A. VideoPlayerComponent Urgency Is Stronger Than Section 1E Suggests

Section 1E frames VideoPlayerComponent vs VideoMaterial as a "decision point." The GPT research makes the case more forcefully: Apple is actively building premium immersive behaviors **exclusively** into `VideoPlayerComponent` -- portal mode, progressive mode, full immersive mode, automatic comfort mitigation, APMP profile support, light spill, passthrough tinting, and native caption rendering. `VideoMaterial` is explicitly positioned in Apple's own spatial playback session as a "lower-level API suited for video as an effect on arbitrary geometry" with real tradeoffs: no aspect ratio correctness guarantees, no built-in captions.

**Correction to current plan:** Section 1E says "use VideoPlayerComponent as default, fall back to VideoMaterial for curved/IMAX." The GPT research adds a stronger rationale: Apple may continue adding immersive features only to `VideoPlayerComponent`, meaning the gap between the two paths will widen with each OS release. Prioritize the migration accordingly -- VideoMaterial should be the exception path, not a co-equal alternative.

**New detail:** `VideoPlayerComponent` now supports portal, progressive, and full immersive viewing for both APMP and Apple Immersive Video profiles specifically. Apple explicitly says **progressive mode is preferred** for APMP/AIV because it supports comfort mitigation and flexibility. This is more specific than section 1C's general `.progressive` recommendation.

---

### 6B. VideoMaterial HDR Fidelity Is Uncertain -- Developer Reports of SDR Tonemapping

Section 4A documents the HDR pipeline but does not flag a risk with `VideoMaterial` specifically. The GPT research surfaces **credible developer reports** that `VideoMaterial` can appear SDR-tonemapped in some pipelines, while direct AVPlayer-based layers render properly in HDR. Apple's public documentation does not explicitly guarantee that `VideoMaterial` preserves HDR10/Dolby Vision end-to-end.

**Action:** Treat HDR correctness on `VideoMaterial` as a **device-test requirement**, not an assumption. If HDR fidelity cannot be validated on-device, this becomes an additional reason to migrate to `VideoPlayerComponent` for the default cinema path.

---

### 6C. Automatic High-Motion Comfort Mitigation (New visionOS 26 Behavior)

Not mentioned in the Claude synthesis. visionOS 26 can **automatically detect high-motion content** in APMP/immersive video playback and **reduce immersion "when necessary"** to preserve user comfort. This is a system-level behavior, not something VPStudio controls directly.

**Implication:** When using `VideoPlayerComponent` with `.progressive` mode, the system may override the current immersion level during fast-paced scenes. VPStudio should not fight this behavior or attempt to lock immersion during high-motion content. Design the UI so users understand why immersion depth may change without their Digital Crown input.

---

### 6D. Per-Frame Dynamic Masks (New visionOS 26 Feature)

Not mentioned in the Claude synthesis. visionOS 26 introduces **per-frame dynamic masks** that allow videos to change size and aspect ratio seamlessly during playback, reducing letterboxing and pillarboxing artifacts. This is relevant for content that switches between aspect ratios mid-stream (e.g., IMAX sequences in theatrical releases).

**Action:** Track as a visionOS 26 adoption item. Investigate whether `VideoPlayerComponent` exposes this automatically or whether manual configuration is needed.

---

### 6E. DockingRegionComponent -- Structured Environment Docking

Section 1D covers `AVExperienceController` but does not mention `DockingRegionComponent`. This is a separate RealityKit component that establishes a **fixed area within an immersive environment** where an `AVPlayerViewController` window scene anchors to. Apple's WWDC24 guidance says the recommended way to build cinema experiences is to use `AVPlayerViewController` with Reality Composer Pro docking components, reflections, passthrough tint, and environment selection.

**New detail for environment design:** When building HDRI environments in Reality Composer Pro, add a `DockingRegionComponent` to define where the cinema screen appears. This gives Apple's system the information it needs to properly anchor `AVPlayerViewController` and apply light spill and reflections from the video onto the environment.

**Implication for architecture:** This is an alternative to VPStudio's current approach of manually placing a `VideoMaterial` plane in the scene. The docking approach delegates screen placement and scaling to the system, gaining light spill, reflections, and caption support for free.

---

### 6F. Metal 10-Bit Extended-Range Pixel Formats as RGBA16Float Alternative

Section 4A states that `bgr10a2Unorm` cannot represent EDR values >1.0 and that only `rgba16Float` works for HDR. The GPT research identifies **additional EDR-capable formats** not mentioned in the Claude synthesis:

| Format | Size | Use Case |
|--------|------|----------|
| `MTLPixelFormat.bgr10_xr` | 32 bpp | Extended-range RGB, no alpha; lower memory than RGBA16Float |
| `MTLPixelFormat.bgr10_xr_srgb` | 32 bpp | Extended-range with automatic sRGB conversion |
| `MTLPixelFormat.bgra10_xr` | 64 bpp | Extended-range with alpha |

These are explicitly documented as valid for `CAMetalLayer.pixelFormat` and DO support EDR values >1.0 (unlike `bgr10a2Unorm`).

**Correction:** Section 4A's claim that "only `rgba16Float` works for HDR on visionOS" is too absolute. `bgr10_xr` at 32 bpp is half the memory of `rgba16Float` at 64 bpp and supports EDR. For the cinema screen rendering path (where alpha is not needed on the video surface itself), `bgr10_xr` could halve render target memory from ~63 MB to ~32 MB per 4K target.

**Caveat:** CompositorServices may still require `rgba16Float` for its layer configuration. The 10-bit XR formats are most applicable if VPStudio uses `CAMetalLayer` directly (e.g., in a windowed HDR preview) rather than the CompositorServices path.

---

### 6G. preferredPeakBitRate and preferredMaximumResolution -- Unused AVPlayer Levers

Section 5.8 covers `preferredForwardBufferDuration` but does not mention two additional AVPlayer properties relevant to memory and thermal management:

- **`preferredPeakBitRate`**: Caps the bitrate AVPlayer attempts during adaptive streaming. Useful for thermal management -- if the device is under thermal pressure during immersive playback, reduce this dynamically.
- **`preferredMaximumResolution`**: Caps the maximum resolution when multiple variants exist. The GPT research specifically recommends this for AV1 on M2: if AV1 must play in immersive mode, cap resolution to reduce software decode load.

**Action:** Add both properties to the adaptive playback strategy. Particularly useful as a thermal response: when `ProcessInfo.processInfo.thermalState` reaches `.serious`, reduce `preferredPeakBitRate` and/or `preferredMaximumResolution` to shed decode load before the system throttles or kills the app.

---

### 6H. APMP Production vs Delivery Profile Distinction

Section 5B describes APMP as a container metadata format but does not distinguish between production and delivery profiles. The GPT research clarifies:

- **APMP for production**: Allows frame-packed video (SBS/OU), additional codecs (ProRes, non-MV HEVC), and broader container flexibility. Intended for capture/editing workflows.
- **APMP for delivery**: Stricter constraints. Stereoscopic delivery **requires MV-HEVC**. SBS/OU frame packing is not valid for delivery-profile APMP.

**Implication for VPStudio:** When dealing with debrid-sourced SBS/OU content, it will NOT conform to APMP delivery profiles. The APMPInjector approach (runtime metadata injection) remains necessary for this content. However, if VPStudio ever implements pre-conversion (SBS -> MV-HEVC), the output should conform to APMP delivery profile constraints to gain full system integration.

---

### 6I. AVPlaybackCoordinationMedium -- Future Multi-Stream Sync

Not mentioned in the Claude synthesis. visionOS 26 introduces `AVPlaybackCoordinationMedium` as Apple's blessed synchronization primitive for coordinating rate changes, seeks, stalling, and startup sync across multiple AVPlayers.

**Not immediately actionable** for single-stream playback, but relevant if VPStudio adds: main video + alternate angle, main video + commentary track, or SharePlay collaborative viewing. File under visionOS 26 future work alongside `AVExperienceController`.

---

### 6J. Jetsam Debugging and Memory Allocation Timing

Section 2A covers memory budgets and `os_proc_available_memory()` but does not mention two specific pieces of guidance from the GPT research:

1. **Jetsam event reports**: Apple recommends using these to identify high-memory termination scenarios post-hoc. When VPStudio gets killed during immersive playback, check device jetsam logs to determine whether it was memory (vs thermal or other).

2. **Do not allocate/deallocate during critical operations**: Apple's visionOS performance planning doc explicitly warns against large memory operations during mode transitions. If VPStudio's fallback engine (KSPlayer/FFmpeg) allocates decode buffers when switching to immersive mode, the OS may kill the app immediately.

**Action:** Pre-allocate KSPlayer decode buffers during player initialization, not during the immersive space transition. Add jetsam log parsing to the crash diagnostics workflow.

---

### 6K. Display P3 Is Vision Pro's Native Gamut

Not explicitly stated in the Claude synthesis. Vision Pro uses **Display P3 as its native display gamut**. Textures authored in other gamuts will be converted at build time. For EDR/HDR output, Apple explicitly demonstrates **extended linear Display P3** (not extended linear ITU-R 2020).

**Potential correction:** Section 4A specifies `CGColorSpace.extendedLinearITUR_2020` for the `CAMetalLayer` colorspace. Apple's own WWDC22 EDR example uses `kCGColorSpaceExtendedLinearDisplayP3`. Since the display is P3-native, using Rec.2020 forces a gamut conversion at display time. Consider whether P3 is the better choice for the final output colorspace, reserving Rec.2020 for internal processing of wide-gamut HDR content.

---

### 6L. Environment Optimization -- Treat Like Real-Time Game Levels

Section 2A mentions reducing texture resolution and geometry sizes but the GPT research adds more specific guidance from Apple's WWDC25 environment optimization sessions:

- Exploit the **immersive boundary** (people only move within a limited traversable area) -- do not waste geometric detail outside what can be perceived from the user's actual position.
- Use appropriately **small IBL (image-based lighting) textures** -- HDRI skyboxes for ambient lighting do not need full resolution; only the environment map visible to the user needs high detail.
- Bake lighting where possible and minimize real-time lighting calculations.

**Action for HDRI environments:** Audit current skybox texture resolutions. If using full-resolution HDRIs for IBL, downsample the IBL probe texture (lighting contribution) independently from the skybox texture (visual background). A 256x256 or 512x512 IBL probe is typically sufficient for ambient lighting even when the visible skybox is 4K+.

---

## 8. GPT Research: Competitor & Strategy Additions

*Source: GPT deep-research competitor analysis (Cprompt3.md, April 2026). Only findings not already captured in Section 3 are included.*

### 8.1 New Competitors Not Previously Profiled

Section 3.2 covers Infuse, CineUltra, Moon Player, Supercut, SKYBOX, Scorpio, Stremio, Theater, Plexi, and Vision Player. The GPT research surfaces additional players worth tracking:

**4XVR Video Player** -- Freemium native visionOS player. Structurally closest to VPStudio's "format maximalism" pitch: MVC 3D decoding for Blu-ray 3D ISOs, full MV-HEVC + AV1 + VP9 codec support, 5.1/7.1 spatial audio, Dolby Vision profiles, selectable immersive environments, and passthrough video mode. Also lists WebDAV/WebDAVS + SMB + Plex/Emby/Jellyfin as streaming sources -- making it debrid-adjacent via the same WebDAV path Infuse uses. Runs a public TestFlight beta program. **Implication for VPStudio**: 4XVR already occupies the "plays everything including Blu-ray ISOs" niche. Competing head-on on format breadth alone is insufficient -- the debrid discovery workflow is the differentiation.

**SenPlayer** -- "All-in-one" utility player available on Vision Pro. Claims 4K/8K at up to 120fps, HDR10/HDR10+/HLG support, and multiple source protocols (WebDAV/SMB/FTP + cloud). Markets a "native rendering engine" rather than immersive environments. Positioned as a smooth-decoding utility, not a cinema experience. **Implication**: reinforces that "just plays files" is a commodity -- environments and discovery are the differentiation layer.

**DeoVR Hyper** -- Native visionOS VR video platform. Positions itself as the primary discovery + playback destination for VR180/360 content -- essentially a streaming service for XR video formats, not a utility player. **Implication**: if VPStudio adds VR format support, DeoVR Hyper owns the discovery mindshare for that content type. VPStudio should focus on flat/3D cinema content discovery and treat VR formats as "supported but not primary."

**MVPlayer.app** -- Lightweight spatial player for 180/360 video from Files/library/HLS. Supports HEVC and MV-HEVC. Head-tracking and lock modes are premium IAP features. Minimalist positioning. **Implication**: confirms that "head-tracking lock" (screen follows vs stays fixed) is a feature users pay for. VPStudio should include both modes.

**Explore POV** -- Immersive 180 3D travel/experience subscription library. Very large catalog with frequent additions; references Apple Immersive Video content. Monetized via subscription bundles. **Implication**: content-library apps in immersive video are viable subscription businesses, but only when the app IS the content. Not a model for VPStudio.

**AmazeVR Concerts** -- 8K "spatial music" concert marketplace. Per-concert IAP purchases. App is storefront + playback shell. **Implication**: validates per-content transactional pricing on Vision Pro, but only relevant if VPStudio ever considers a content marketplace layer.

**JigSpace** -- Spatial presentation platform (not a video player). Supports SharePlay for up to 4 participants with remote-control capabilities and walk-around 3D interaction patterns. **Implication**: JigSpace's SharePlay-with-remote-control demonstrates a pattern VPStudio could adapt for shared watch sessions where a host controls playback for the group.

---

### 8.2 New UI Pattern Details

**Controls detach and move closer in immersive mode.** Section 3 notes environments and Digital Crown control. The GPT research adds a specific Apple-documented UX behavior: when an app opens an Immersive Space, playback controls physically detach from the screen and reposition closer to the user for ergonomic reach. VPStudio's immersive player should replicate this detachment -- controls as a separate floating panel anchored ~1m from the user, not affixed to the cinema screen surface at 10-20m distance.

**"Glassy window" browsing with left-side tab bar.** Supercut markets a "glassy window" browsing metaphor with a persistent left-side native visionOS tab bar for shortcuts and search. This is the spatial equivalent of sidebar navigation, adapted for gaze targeting. VPStudio's library/discovery UI should adopt this: persistent left-side navigation that is spatially stable and easy to re-acquire with gaze, rather than hamburger menus or top-tab bars requiring upward head tilt.

**Apple's recommended browse-to-play transition pattern.** Apple's video playback session demos a specific flow: browse content in a window -> open an info/metadata page -> app opens an Immersive Space -> video docks to optimal viewing position -> app can overlay custom info panels (cast, related content) during playback. **For VPStudio**: this validates designing the debrid resolution steps (searching, selecting quality, resolving link) as an intentional "info page" phase rather than hiding them behind loading spinners. Users tolerate multi-step flows when each step feels like content progression.

**"Content funnel" via Apple companion app.** Apple now ships an iPhone/iPad companion app that promotes "latest content and spatial experiences" to Vision Pro owners. Apps on the App Store benefit from this discovery funnel. A sideload-only VPStudio misses this entirely -- reinforcing that the dual-distribution strategy (App Store player + sideload full) is critical for user acquisition.

**Seat selection as explicit pre-playback UX.** IMAX lets users choose between three different seats as part of the experience (not a settings toggle). Apple TV Cinema Environment also offers selectable seating. This is a first-class pre-playback choice screen, not a buried preference. VPStudio should present environment + seating selection together as an intentional "choose your theater" moment before entering immersion.

---

### 8.3 User Pain Points -- Additional Specifics

Section 3.3 captures general themes (environments, debrid, DTS/TrueHD, Plex, sharpness). The GPT research adds these concrete complaints:

- **IMAX: "black screen / doesn't work"** -- Repeated App Store reviews reporting total playback failure, alongside praise for the IMAX aspect ratio. Users demand more purchasable catalog titles (requesting blockbusters like *Interstellar* specifically). Even premium immersive apps ship broken basics.

- **MUBI: crashes 10 minutes in** -- 2026 App Store reviews: "crashing constantly about 10 minutes into every movie" on Vision Pro. A subscription streaming service with a dedicated visionOS presence still cannot maintain stable long-form playback. VPStudio must clear this bar: sustained stability over 2+ hour sessions.

- **Tubi: window sizing chaos** -- Reviews complain the app "opens gigantic every single time" with content failing to play. Consistent, predictable window sizing on launch is non-negotiable.

- **SKYBOX: missing skip-back** -- Users specifically complain about no 10/15 second skip-back, calling existing back/forward "unusable." VPStudio must ship standard transport controls (skip -10s, skip +30s, scrubber, speed) from day one.

- **CineUltra: broken SMB browsing** -- Reviews cite icon-only thumbnail view (no list view option) and failure to remember last-browsed folders. VPStudio's file browser must include both grid and list views and persist navigation state across sessions.

- **Supercut: Atmos disrupted by OS updates** -- Users who bought Vision Pro specifically for Dolby Atmos report OS updates breaking Atmos in cinema mode. VPStudio should regression-test audio format passthrough after every major OS update.

- **External player hand-off is fragile** -- Users report only MoonPlayer, Infuse, and VLC reliably appear as external-player targets from Stremio Lite. Other players silently fail to register. VPStudio must correctly register for `x-callback-url` and custom URL schemes and verify it appears in the system player picker.

---

### 8.4 App Store Policy -- Additional Nuances

**Guideline 5.2.2 (Third-Party Sites/Services)** -- Not cited in Section 3.5. This rule requires that if an app "uses, accesses, monetizes access to, or displays content from a third-party service," the developer must be permitted under that service's terms and provide proof of authorization on request. For VPStudio, this cleanly covers TMDB API usage (clear terms). But Apple could argue that displaying content resolved through debrid services constitutes "accessing content from a third-party service" without authorization from the original rights holder. This is a separate rejection vector from 5.2.3, targeting the access pattern rather than the file-sharing facilitation.

**Stremio sideloadable IPA (February 2026)** -- Section 3.5 mentions Stremio Lite and sideloading generally. The GPT research adds that Stremio published a "fully featured sideloadable IPA" in February 2026 for iOS/tvOS, explicitly positioning sideloading as the distribution path for App Store-incompatible features. This is a concrete, recent (2 months ago) precedent validating VPStudio's dual-distribution architecture as industry-standard.

**Netflix blocked Safari on visionOS 26** -- Section 3.2 notes Netflix has no native app and opted out of iPad compatibility mode. The GPT research adds that Netflix now also blocks Safari-based playback on visionOS 26, making Supercut the only remaining path for Netflix on Vision Pro. This deepens the Netflix gap and increases the value of any app that can play Netflix-catalog content from alternative sources.

---

### 8.5 Pricing Data Updates

| App | Price (GPT, April 2026) | Price (Claude synthesis, Section 3.4) | Delta |
|-----|------------------------|---------------------------------------|-------|
| Moon Player | **$8.99** one-time | $5 one-time | +80% |
| Supercut | **$6.99** one-time | $4.99 one-time | +40% |
| Outplayer | Free + one-time IAP | Not previously priced | Confirmed freemium |

**Interpretation**: Both Moon Player and Supercut have raised prices since Section 3.4 was written, suggesting Vision Pro early adopters demonstrate higher willingness to pay than initially estimated. VPStudio's recommended $7.99--9.99 one-time price point is now validated by direct comps rather than being aspirational. The price floor has moved up.

---

### 8.6 Glare and Comfort in Environment Design

Section 3 does not address glare/comfort. The GPT research surfaces a specific finding:

**Darker environments worsen perceived glare on Vision Pro's OLED+lens optics.** Users report that dark theater environments (black void, dark cinema) increase visibility of lens flare and light scatter artifacts, particularly around bright UI elements or high-contrast video. Some users actively prefer brighter environments (well-lit rooms, outdoor scenes) to reduce perceived glare.

**Design implications for VPStudio's HDRI environments:**

1. The "void black" environment should be offered but NOT be the default -- it maximizes glare visibility.
2. Default cinema environments should have moderate ambient brightness in the surround (equivalent to a dimly lit theater, not pitch-black). Target 5--15% luminance in the peripheral surround to mask lens artifacts.
3. Environment selection UI should include contextual guidance: "Brighter environments reduce lens glare."
4. For HDR content specifically, increase environment surround brightness slightly -- bright HDR specular highlights scatter more through the lens stack, and a brighter surround masks this.
5. Test every HDRI environment with both SDR and HDR content, evaluating glare during high-contrast scenes (explosions on dark backgrounds, white text on black, etc.).

---

### 8.7 Market Segmentation Model

The GPT research proposes a five-segment taxonomy not explicitly articulated in Section 3:

1. **First-party baseline** -- Apple TV, system player. Sets user expectations.
2. **Subscription streamers with native immersion** -- Disney+, Max, YouTube. Set the quality ceiling for environments.
3. **Spatial-first experience libraries** -- Explore POV, AmazeVR, DeoVR Hyper. Content IS the app.
4. **Third-party "plays anything" players** -- Infuse, Moon Player, CineUltra, 4XVR, VLC, SKYBOX. VPStudio's App Store competitive set.
5. **TestFlight/sideload gray zone** -- Debrid-aware apps, Stremio Lite, community tools. VPStudio's full-feature distribution channel.

**Strategic implication**: VPStudio competes in segment 4 (App Store) and segment 5 (sideload). Segment 4 is commodity-converging on codec breadth and environment quality. The remaining differentiation axes are: (a) debrid/content discovery (segment 5 only), (b) UX polish exceeding incumbents, and (c) first-mover adoption of new visionOS APIs (Foveated Streaming, Spatial Audio Experience, nearby SharePlay).

---

### 8.8 Paramount+ Interactive Environments

Not in Section 3: Paramount+ experimented with interactive franchise environments (SpongeBob-themed with interactive elements was reported in coverage). This extends the Disney+ model beyond passive themed backdrops into environments with interactive affordances. While VPStudio will not license franchise content, the concept of interactive environment elements (clickable objects triggering Easter eggs, ambient animations responding to playback state) could differentiate VPStudio's HDRI environments from static panoramas.

---

### 8.9 iPad Compatibility Mode -- Structural Advantage

Section 3 does not explicitly quantify what iPad compat mode loses. The GPT research cites Apple's language: "compatible iOS apps built with the iOS SDK will get an iOS compatible experience" -- meaning no immersive environments, no spatial controls, no visionOS-native window management, no system dimming. For VLC, nPlayer, and Outplayer (all iPad compat), this means zero immersive features despite superior codec/protocol support. **VPStudio being native visionOS is a structural advantage over the entire class of iPad compat players**, even those with broader codec or protocol coverage. This advantage should be explicit in App Store marketing: "Built for Vision Pro" as a headline differentiator.

---

## 9. GPT Research: Subtitle Rendering Additions

*Source: GPT deep-research report (Cprompt4.md). Only findings not already captured in Section 4 are listed.*

### 9A. Movable Captions as Platform Idiom

Apple Immersive Video now allows users to **reposition captions via the window bar** during playback. Apple's accessibility page describes "Movable captions on Apple Vision Pro" as a first-class feature. This establishes a platform expectation: captions in immersive experiences are spatial objects the user can relocate, not fixed overlays. VPStudio must offer at least vertical repositioning of the subtitle overlay entity in immersive mode to match this idiom. Horizontal nudge and slight depth (forward/back) adjustment would fully align with Apple's direction.

### 9B. .itt (iTunes Timed Text) Format Support

Apple Immersive Video Utility accepts **`.itt` and `.vtt`** as subtitle inputs for immersive HLS streams. Section 4 lists WebVTT but not `.itt`. iTunes Timed Text is a TTML profile used across Apple's ecosystem (iTunes Store, Apple TV+). Adding `.itt` parsing alongside the planned IMSC/TTML support is low incremental effort and ensures VPStudio can ingest subtitle tracks prepared with Apple's own immersive tooling.

### 9C. Two Rendering Modes: Preserve vs Accessible

The GPT research articulates a clean two-mode architecture that Section 4 implies but does not name:

**Preserve (typesetting-first):** Render libass output as the canonical display for anime/fansub content. Offer only minimal safety options -- global scale multiplier and an optional background plate behind dialogue lines. Heavy rewriting defeats the purpose of ASS typesetting.

**Accessible (comprehension-first):** Treat dialogue and SDH as captions, not graphics. Normalize dialogue into a consistent caption style honoring system `MACaptionAppearance` preferences (font, size, background, edge style). Keep "signs" or on-screen labels as image overlays placed where authored but with contrast-boosted backplates. Disable karaoke/per-syllable animation when Reduce Motion is enabled.

**Architecture implication:** The subtitle renderer needs a mode switch that gates whether libass output passes through raw (Preserve) or gets post-processed into system-styled text (Accessible). The mode should default to Accessible for SRT/WebVTT and Preserve for ASS/SSA, with user override.

### 9D. Reduce Motion Handling for Karaoke Effects

Apple's spatial accessibility guidance warns against motion-inducing subtitle behaviors. ASS `\k`/`\kf` karaoke timing, `\move` animations, and `\t` transforms can be physically unpleasant in a headset. When `UIAccessibility.isReduceMotionEnabled` is `true`, VPStudio should:

- Suppress `\k`/`\kf` karaoke sweep -- display the full line as pop-on instead
- Suppress `\move` -- render at the final position statically
- Suppress `\t` (animated transforms) -- apply the end-state immediately
- Suppress `\fad` fade-in/fade-out -- display at full opacity instantly

This can be implemented by passing modified ASS override tags to libass or by post-processing the event text before rendering. Check `UIAccessibility.reduceMotionStatusDidChangeNotification` for runtime changes.

### 9E. "Follow with Lag" Hybrid Anchoring Mode

VR subtitle research identifies three anchoring strategies, only one of which Section 4 addresses (screen-anchored world-space):

| Mode | Behavior | Tradeoff |
|------|----------|----------|
| **Screen-anchored** (current) | Subtitle plane parented to cinema screen entity | User can lose captions if they glance away from the screen |
| **Head-locked** | Subtitle plane follows head orientation 1:1 | Easiest to find but causes nausea; conflicts with visionOS Zoom (also head-anchored) |
| **Follow with lag** | Subtitle plane drifts toward head orientation with damping (e.g., 0.3-0.5s lerp, 15-20 degree deadzone) | Compromise -- always findable, reduced nausea vs hard head-lock |

VPStudio should offer screen-anchored as default (correct for cinema) and "follow with lag" as a user-selectable accessibility option. Hard head-lock should be avoided entirely -- Apple explicitly warns it conflicts with the Zoom accessibility feature and harms low-vision usability. Honor the `UIAccessibility.prefersCrossFadeTransitions` preference signal (Apple's proxy for "prefers alternatives to head-anchored content").

### 9F. BBC VR Subtitle Placement: 15 Degrees Below Horizon

BBC R&D's 360-video subtitle prototype places caption blocks at a fixed **15 degrees below the horizon** with a **two-line maximum**. While VPStudio is a cinema-screen experience (not 360 video), this specific angle is a validated starting point for the default vertical offset of the subtitle overlay relative to the screen center. The current DMM-based sizing (Section 4) handles text height but does not specify the default vertical placement angle. 15 degrees below the screen's horizontal midpoint (or the user's eye-line) is the research-backed default.

### 9G. Live Captions Coexistence

visionOS provides **Live Captions** as a systemwide real-time transcription window that is resizable and repositionable. VPStudio's subtitle UI must not prevent simultaneous use of Live Captions. Practical requirements:

- Do not hard-lock subtitles to a position that blocks the Live Captions window with no way to move either
- Making VPStudio subtitles repositionable (9A above) inherently solves this
- Consider detecting when Live Captions is active and adjusting default subtitle placement to avoid overlap (no public API for this currently, but spatial separation is sufficient)

### 9H. KSPlayer GPL-3.0 Licensing Warning

Section 4 notes that KSPlayer bundles FFmpegKit with prebuilt libass xcframeworks. What it does not flag: **KSPlayer is licensed GPL-3.0**. Linking GPL-3.0 code into a distributed app triggers copyleft obligations -- VPStudio's entire source must be made available under GPL-compatible terms, or the distribution violates the license. This is a hard legal constraint, not a style preference.

**Mitigations:**
- Use KSPlayer only in a sideload/TestFlight build where source availability can be managed
- For the App Store build, isolate FFmpeg/libass behind a process boundary (XPC service) to argue separability, or use only independently-licensed xcframeworks (the `swift-libass` wrapper ships its own MIT/LGPL-licensed xcframeworks independent of KSPlayer)
- The FFmpeg build-script repo targeting visionOS is LGPL by default (becomes GPL only if built with `--enable-gpl` options) -- build without GPL flags for App Store safety

### 9I. Vision Pro Display Acuity Context

Section 4 references 34 PPD in the DMM sizing table. Additional context from the GPT research: human 20/20 acuity corresponds to approximately **60 PPD** (derived from 1 arcminute resolution, per Nature). Vision Pro at ~34 PPD is roughly half the acuity threshold, which explains why text that reads fine on a phone becomes borderline in the headset. This reinforces the Section 4 recommendation of 30-35 DMM minimum -- at 34 PPD, that target spans ~62 display pixels of height, comfortably above the minimum legibility threshold but nowhere near the "retina" clarity users expect from Apple devices. Do not go below 24 DMM under any circumstances.

---

## 10. GPT Research: Debrid Integration Additions

Findings below come from a GPT deep-research pass on debrid integration (Cprompt5.md). Only items that are genuinely new relative to sections 5.1-5.10 above are included.

### 10.1 TorBox Permalinks -- Explicit "Do Not Store CDN Links" Guidance

Section 5.2 captures the "never pre-resolve CDN URLs" rule, but the GPT research surfaces a specific TorBox mechanism not documented here: TorBox provides a **permalink endpoint** that returns a stable URL which redirects to a fresh CDN link on each request. Their docs explicitly state: *"Use this method rather than saving CDN links as they are not permanent."*

**Action for VPStudio:** For TorBox specifically, store the permalink URL (not the CDN URL) as the durable stream reference. This eliminates the need for explicit re-resolution on resume -- the permalink handles it via redirect. Other providers lack this mechanism, so the `StreamRecoveryContext` re-resolution pattern remains necessary for them.

### 10.2 TorBox Streaming Endpoints (Not in Claude Doc)

TorBox documents dedicated streaming endpoints separate from its download endpoints:
- `GET /api/stream/createstream` -- creates a stream session, returns a token/metadata
- `GET /api/stream/getstreamdata` -- retrieves stream data using the session token

These are distinct from the download-link flow (`/api/torrents/requestdl`). VPStudio's TorBox adapter should evaluate whether the streaming endpoints provide better behavior for playback (potentially better seek support or adaptive behavior) versus the standard download-link approach.

### 10.3 TorBox 600-Second Server-Side Update Interval

TorBox docs state that some list data "only gets updated every 600 seconds" server-side. This sets a hard floor on useful poll cadence for status/list endpoints -- polling faster than every 10 minutes is wasted API budget.

**Action for VPStudio:** Set a minimum 600s cache TTL on TorBox list/status responses. This also means the L1 cache TTL for TorBox availability data should be at least 10 minutes (not the 15-30 minute range in section 5.3, which happens to be compatible but was not justified by this provider-specific constraint).

### 10.4 AllDebrid Rate Limits and Multi-Step Streaming Flow

Section 5.1 lists AllDebrid's rate limits as "429-enforced (undocumented threshold)." The GPT research found AllDebrid **does publish specific limits**: **12 requests/second and 600 requests/minute**, with 429 or 503 responses on violation and a recommendation to use "throttling or grouped calls."

More importantly, AllDebrid's streaming flow is multi-step, not a single unlock call:
1. `/link/unlock` -- unrestrict the link
2. `/link/streaming` -- select stream quality (resolution/codec variants)
3. `/link/delayed` -- poll for the final link if generation is asynchronous (recommended poll interval: >= 5 seconds)

**Action for VPStudio:** The AllDebrid provider adapter must implement this as a state machine (unlock -> quality select -> delayed poll), not a single-shot unrestrict. The token bucket rate limiter should be configured at 12 req/s and 600 req/min (replacing the "undocumented" designation in section 5.1).

### 10.5 TorBox General Rate Limit: 300 req/min

Section 5.1 only lists TorBox's creation-endpoint limit (60/hr). The GPT research found TorBox publishes a **baseline rate limit of 300 requests/minute per API token** across all endpoints, with the 60/hr limit applying specifically to "create download" endpoints.

**Action for VPStudio:** The TorBox token bucket should enforce both limits: 300 req/min overall, and a separate 60 req/hr bucket for creation endpoints.

### 10.6 Real-Debrid ETag / If-None-Match Support

Real-Debrid's API sends `ETag` headers and supports `If-None-Match` for conditional requests. This is the HTTP-native mechanism for "don't send me the same response again" -- a 304 Not Modified response saves bandwidth and counts against rate limits less aggressively on most CDN implementations.

**Action for VPStudio:** The Real-Debrid HTTP client should store ETags from cacheable endpoint responses (availability checks, torrent info) and send `If-None-Match` on subsequent requests. This is complementary to the L1/L2 cache -- it validates that cached data is still current without transferring the full payload.

### 10.7 Real-Debrid "30 Day" Link Validity vs Practical Expiry

A widely-circulated Real-Debrid FAQ claims "a Real-Debrid link remains valid for 30 days." Section 5.1 states "~6 hours, IP-locked." The GPT research reconciles this: the 30-day claim may apply to the provider-side record, but the actual CDN URL can expire much sooner due to IP-locking, CDN signed-URL rotation, or provider-side gating changes.

**Action for VPStudio:** Continue treating Real-Debrid URLs as short-lived (~hours). The 30-day figure is not operationally reliable for playback URLs. Document the discrepancy so future developers don't rely on the FAQ claim.

### 10.8 Real-Debrid Account Sharing / VPS Restrictions

Real-Debrid's ToS explicitly states: accounts are personal-use only, connections are logged to detect sharing, "generated links sharing" can lead to suspension, and dedicated server/VPS/cloud usage must go through their "Remote Traffic" feature.

**Impact on VPStudio:** Multi-device failover or streaming from cloud-hosted instances (CI, TestFlight build servers, etc.) can trigger Real-Debrid enforcement even when the app is behaving correctly. VPStudio should:
- Warn users if Real-Debrid is configured alongside multiple active IP sources
- Never fan out the same Real-Debrid link to multiple concurrent connections
- Document the "Remote Traffic" requirement for any server-side proxy architecture

### 10.9 AllDebrid LINK_TOO_MANY_DOWNLOADS Error Code

AllDebrid returns a specific error code `LINK_TOO_MANY_DOWNLOADS` ("Too many concurrent downloads") plus related capacity codes (`SERVERS_FULL`, `HOST_LIMIT_REACHED`). These are not listed in section 5.7's retry classification table.

**Action for VPStudio:** Add to the retry classification:

| Error Code | Category | Action |
|-----------|----------|--------|
| `LINK_TOO_MANY_DOWNLOADS` | **Backoff then retry** | Exponential backoff (start 5s), max 3 attempts. Reduce parallel download count for AllDebrid. |
| `SERVERS_FULL` / `HOST_LIMIT_REACHED` | **Failover** | Skip to next provider; open circuit breaker for AllDebrid (5-15 min). |

### 10.10 Cache TTL Refinements -- Asymmetric Positive/Negative

Section 5.3 uses a flat 24-hour TTL for availability data. The GPT research argues for asymmetric TTLs based on provider behavior:

| Cache Result | Recommended TTL | Justification |
|-------------|----------------|---------------|
| **Positive** ("cached/available") | **6-24 hours** | Debrid caches are relatively stable (TorBox retains 30 days if accessed); refresh in background if item is relevant to active browsing. |
| **Negative** ("not cached") | **5-30 minutes** | Can flip to positive at any time (another user caches it, or a background job completes). Short TTL prevents stale negative results blocking playback. |
| **Invalidation trigger** | **Immediate** | If a play attempt fails with "not cached/not available," invalidate the cached positive result immediately -- the play attempt is more recent ground truth. |

**Action for VPStudio:** Replace the flat 24h L2 availability TTL with asymmetric TTLs. Suggested defaults: 12h positive, 15min negative, with immediate invalidation on playback failure.

### 10.11 Premiumize Transcoded Files

Premiumize makes transcoded versions of some video files available in their cloud storage. This can matter for player compatibility (e.g., a transcoded H.264 version of a file that's natively H.265 with DTS audio).

**Action for VPStudio:** When building the Premiumize provider adapter, check for transcoded file availability alongside the original. If the original requires KSPlayer (non-native codec/container) but a transcoded version would play natively in AVPlayer, surface both options in the stream picker with a note like "Transcoded (H.264, smaller)" vs "Original (HEVC DTS, full quality)."

### 10.12 URLSessionTaskMetrics for Debugging

iOS exposes `URLSessionTaskMetrics` and `URLSessionTaskTransactionMetrics` with granular timing data. The `networkProtocolName` property returns the ALPN identifier (e.g., "h2", "http/1.1") for the negotiated protocol.

**Action for VPStudio:** Instrument the debrid HTTP client to collect `URLSessionTaskMetrics` on every request. Key uses:
- Distinguish "TLS handshake slow" from "server stalled mid-transfer" in diagnostic logs
- Detect whether HTTP/2 is being negotiated (most debrid CDNs serve over HTTP/1.1; knowing this informs connection pooling strategy)
- Feed timing data into adaptive retry thresholds (e.g., if TLS setup consistently takes >2s for a provider, adjust timeout expectations)
- Surface `networkProtocolName` in the debug/diagnostics UI for support troubleshooting

### 10.13 Request Coalescing and Stale-While-Revalidate

Two patterns the GPT research recommends that are not explicitly called out in sections 5.1-5.10:

**Request coalescing:** If multiple UI components (stream picker, availability badge, pre-fetch logic) all request the same availability check simultaneously, coalesce into a single network call and fan out the result. Implementation: a `Dictionary<CacheKey, [CheckedContinuation]>` that gates duplicate in-flight requests.

**Stale-while-revalidate:** Return cached availability data immediately to the UI, then refresh in the background. If the background refresh produces a different result, update the UI. This eliminates loading spinners for cached content while keeping data fresh.

**Action for VPStudio:** Both patterns should be built into the debrid provider abstraction layer, not left to individual call sites. The coalescing dictionary lives in the rate-limited request scheduler; stale-while-revalidate is a cache-read policy flag on the L1/L2 cache.

### 10.14 iOS CFNetwork Error Masking

When debrid CDN URLs expire, iOS often surfaces the failure as opaque CFNetwork/SecureTransport errors (e.g., `kCFStreamErrorDomainSSL` with code `-2205`) rather than clean HTTP 403/410 responses. This happens because the TLS connection to the CDN fails or is reset before an HTTP-layer response is delivered.

**Action for VPStudio:** The stream recovery logic should treat SSL/TLS stream errors from debrid CDN domains as "URL likely expired; re-resolve and retry" rather than "network connectivity problem." Specifically:
- `kCFStreamErrorDomainSSL` errors during active playback -> trigger `StreamRecoveryContext` re-resolution
- Inspect `NSError.userInfo` for the underlying `kCFStreamErrorCodeKey` to log the real cause
- Do not show "connection failed" UI for these errors; instead show "refreshing stream..." while re-resolving

---

## 7. GPT Research: Spatial Audio Additions

*Source: GPT deep-research report (Cprompt2.md). Cross-referenced against sections 1E, 5A, 5B, and 6 above. Only genuinely new findings are included.*

---

### 7.1 setIntendedSpatialExperience -- Exact Usage from Destination Video

The Claude synthesis (5A) lists this API as a deferred item but provides no usage details. The GPT research extracts the concrete pattern from Apple's Destination Video sample:

- **Inline playback**: Configure a **small, view-originating soundstage** where audio originates from the location of the view itself. The system anchors the sound to the visual presentation without app-side 3D emitter placement.
- **Full-window / immersive playback**: Configure a **large, fully immersive soundstage** with head-tracked anchoring.
- The API call is `AVAudioSession.setIntendedSpatialExperience(...)` with a head-tracked soundstage sized to the presentation and an automatic anchoring strategy.

**Key insight not in Claude doc:** With AVPlayer/AVKit-style playback, the system can anchor audio to the visual presentation without placing emitters in 3D space. You are **declaring intent**, not building a renderer. This is Apple's closest thing to an official "do this for cinema apps" answer.

**VPStudio action:** When using AVPlayer for standard content, call `setIntendedSpatialExperience` with a large head-tracked soundstage at the moment the immersive cinema space opens. This single call replaces any need to manually position audio sources for the AVPlayer path.

---

### 7.2 AudioGeneratorController -- The KSPlayer/FFmpeg Bridge to RealityKit Spatial Audio

The Claude synthesis (5A) mentions routing FFmpeg audio through `AVAudioEngine` but does not describe the RealityKit bridge pattern. The GPT research provides the missing piece:

- `Entity.playAudio(...)` has a variant that returns an `AudioGeneratorController`.
- This controller accepts **real-time audio sample buffers** written directly into its buffer.
- Apple explicitly states you can pipe audio from "Apple audio units, your own audio units, or the output of your own audio engines" -- this is the sanctioned path for custom decode pipelines.
- The result is rendered by RealityKit's spatial audio system, consistent with all other scene audio (reverb, head tracking, distance attenuation).

**The bridge pattern for VPStudio:**
```
KSPlayer/FFmpeg decode -> PCM buffers
  -> (optional) AVAudioEngine DSP/EQ/dynamics
    -> AudioGeneratorController.write(samples:)
      -> RealityKit spatial renderer (head-tracked, reverb-matched)
```

**Why this matters vs raw AVAudioEngine output:** AVAudioEngine alone outputs to the system mixer but does **not** attach audio to a RealityKit entity transform. AudioGeneratorController does -- meaning audio tracks the cinema screen entity's world position. This is the only documented path to get FFmpeg-decoded audio spatialized at the virtual screen location rather than the listener's head.

**Caveat not in Claude doc:** RealityKit does **not** provide a built-in adapter to take audio from an AVPlayer and route it into a RealityKit emitter. If you want AVPlayer's decode but RealityKit's anchoring, you must either (a) let AVKit own the presentation, (b) tap AVPlayer audio into your own buffer pipeline and feed those buffers into AudioGeneratorController (complex, not always compatible with every streaming mode), or (c) use newer platform components like VideoPlayerComponent that keep video+audio features intact.

---

### 7.3 ChannelAudioComponent vs SpatialAudioComponent vs AmbientAudioComponent

The Claude synthesis does not distinguish between these three RealityKit audio component types. The GPT research clarifies when to use each:

| Component | Degrees of Freedom | Mixdown Behavior | Use Case |
|---|---|---|---|
| **SpatialAudioComponent** | 6DoF (level and tone change with source/listener movement AND rotation) | **Mixed down to mono** before spatialization | Point-source effects: a speaker, an object, a character. Apple recommends authoring mono files to avoid unexpected mixdown artifacts. |
| **ChannelAudioComponent** | Channel-layout-preserving | Preserves stereo/surround speaker layout | **This is what VPStudio should use for cinema audio.** When you want channel-meaningful playback (stereo, 5.1, 7.1) rather than mono-point-source spatialization. |
| **AmbientAudioComponent** | 3DoF (rotation observed, translation ignored) | Preserves source channels | Background music, ambient soundscapes. Apple notes large files are good candidates for `loadingStrategy: .stream`. |

**Critical finding for VPStudio:** If cinema audio is routed through `SpatialAudioComponent`, a 5.1 or 7.1 track will be **collapsed to mono** before spatialization. This would destroy the stereo/surround sound field. For movie playback via the AudioGeneratorController bridge, use `ChannelAudioComponent` to preserve the original channel layout.

---

### 7.4 Personalized Spatial Audio Entitlement

The Claude synthesis does not mention this entitlement. The GPT research identifies:

- **Entitlement:** `com.apple.developer.spatial-audio.profile-access`
- **Purpose:** Applies the user's Personalized Spatial Audio profile (ear shape, head geometry) to your app's audio output when rendering via engine-level APIs including `AVAudioEngine`.
- **When needed:** Only required if VPStudio renders audio through AVAudioEngine or AudioGeneratorController. The AVPlayer/AVKit path gets personalization automatically.
- **Action:** Request this entitlement from Apple and add it to the visionOS target. Without it, the AudioGeneratorController bridge (7.2) will produce generic HRTF spatialization rather than user-personalized spatialization, making VPStudio's cinema audio feel subtly "off" compared to Apple TV+.

---

### 7.5 APAC Ambisonic Encoding -- Practical Details via AVAssetWriter

The Claude synthesis (5A) mentions APAC's compression ratio and that AVPlayer handles it natively but provides no encoding details. The GPT research adds practical specifications for VPStudio's 360/immersive content pipeline:

**Channel counts by ambisonic order:**

| Order | Channels | APAC Bitrate (recommended for APMP) |
|---|---|---|
| 1st (FOA) | 4 | ~384 kbps |
| 2nd (2OA) | 9 | ~576 kbps (interpolated) |
| 3rd (3OA) | 16 | ~768 kbps |

- **AVAssetWriter supports APAC encoding through 3rd-order ambisonics.** This is the sanctioned path for creating immersive content that plays back with head-tracked spatial audio on Vision Pro.
- APAC is a scene-based audio format using spherical harmonics -- not tied to a speaker layout. The system renderer handles binaural/head-tracked output.
- The APAC specification confirms rendering support for devices "ranging from theaters to head-tracked headphones."
- **ASAF (Apple Spatial Audio Format)** goes further: combines Higher Order Ambisonics with discrete audio objects, rendered adaptively. This is the format behind Apple Immersive Video and represents Apple's long-term direction.

**VPStudio action (future):** If VPStudio adds a 360 content export/transcode pipeline, use `AVAssetWriter` with APAC encoding at 3rd-order ambisonics (~768 kbps) paired with APMP-tagged video for maximum platform integration.

---

### 7.6 Three Implementation Routes -- Expanded Decision Framework

The Claude synthesis mentions AVKit vs RealityKit audio loosely. The GPT research defines three explicit routes with clear decision criteria:

**Route A -- AVKit/AVPlayerViewController + setIntendedSpatialExperience**
- Best for: Standard content (H.264/H.265 + AAC/AC3/EAC3/Atmos), where AVPlayer handles decode.
- Audio anchoring: Automatic. The system knows "the view" and anchors the soundstage to it.
- Atmos: Fully preserved (object metadata intact).
- VPStudio fit: Primary path for all content AVPlayer can handle. Matches Apple TV+, Disney+, IMAX behavior.

**Route B -- RealityKit Entity Audio (SpatialAudioComponent / ChannelAudioComponent)**
- Best for: Pre-loaded or file-based audio that must be positioned in the 3D scene.
- Audio anchoring: Entity transform defines position. Spatial audio is default (6DoF).
- Limitation: Requires `AudioFileResource` -- not directly compatible with streaming decode.
- VPStudio fit: Ambient theater sounds, UI audio, environment-specific effects (not primary movie audio).

**Route C -- AudioGeneratorController Bridge (for KSPlayer/FFmpeg)**
- Best for: Content requiring FFmpeg decode (DTS, TrueHD, exotic containers) where you still want screen-anchored spatial audio.
- Audio anchoring: Attach the generator entity to the cinema screen entity. Audio follows the screen's world position.
- Atmos: Not preserved (FFmpeg collapses to channel bed). But a good 7.1 channel bed through ChannelAudioComponent can still produce a convincing cinema soundstage.
- VPStudio fit: Fallback path for "weird files." The pragmatic hybrid is AVPlayer (Route A) for standard content and AudioGeneratorController (Route C) for FFmpeg-only codecs.

**Decision matrix addition not in Claude doc:**

| Signal | Route |
|---|---|
| AVPlayer can decode the audio natively | A |
| Audio is environmental/ambient (not movie timeline) | B |
| FFmpeg must decode AND audio must anchor to screen | C |
| User has Atmos content | A (mandatory -- C loses object metadata) |

---

### 7.7 ReverbComponent for Cinema Environment Acoustics

Not mentioned in the Claude synthesis. The GPT research details visionOS 2's `ReverbComponent`:

- **Reverb presets** can be attached to entities in the RealityKit scene hierarchy.
- In **progressive immersive spaces**, the system blends the user's real-world acoustics with the preset based on immersion level (Digital Crown position).
- In **full immersive spaces**, spatial audio sources reverberate **only according to the preset** -- real-world acoustics are fully replaced.
- A reverb component attached to the environment entity affects **all audio in the scene**, including system audio -- not just your media track. This creates a unified acoustic "place."

**VPStudio action:** Each HDRI cinema environment should include a matched `ReverbComponent` preset:
- Classic theater HDRI -> medium room reverb
- IMAX HDRI -> large hall reverb
- Outdoor/drive-in HDRI -> open-air reverb (minimal reflections)

This is configured in Reality Composer Pro or in code as part of the environment entity hierarchy. It pairs with `setIntendedSpatialExperience` to create a complete audiovisual "place" rather than an HDRI that only provides lighting.

**Key clarification:** HDRI gives you lighting. Reverb presets give you acoustics. If you want geometry-aware reflections/diffraction, you need actual geometry plus an acoustic simulation engine -- not just a skybox.

---

### 7.8 Per-App Spatial Audio User Overrides

Not mentioned in the Claude synthesis. The GPT research highlights a UX constraint:

- Apple Vision Pro supports **per-app Spatial Audio modes**: Off, Fixed, and Head Tracked. Users set these in Control Center and the preference persists per app.
- "Head Tracked" makes audio sound like it comes from the app (world-locked). "Fixed" keeps the soundstage head-locked. "Off" disables spatialization entirely.
- Any cinema anchoring strategy VPStudio builds **must gracefully handle the user turning head tracking off**. If the user selects "Fixed," audio will stay head-locked regardless of `setIntendedSpatialExperience` configuration.

**VPStudio action:** Do not assume head tracking is always active. Test all three modes. Consider surfacing a gentle recommendation in settings ("For the best cinema experience, enable Head Tracked spatial audio in Control Center") rather than fighting the user's system preference.
