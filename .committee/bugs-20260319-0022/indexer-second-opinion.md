# Indexer second-opinion: stremio fetch + content usage

## Audit scope
- Focused on `VPStudio/Services/Indexers/StremioIndexer.swift` (fetch + parse flow)
- Checked fetch tests:
  - `VPStudioTests/StremioIndexerTests.swift`
  - `VPStudioTests/IndexerConnectivityTests.swift`
- Cross-checked with Stremio stream-handler contract and open-source parsing behavior (AIOStreams).

## Finding (High)
### Missing hash-normalization path for modern Torrentio stream payloads drops valid results

- **File/Lines:** `VPStudio/Services/Indexers/StremioIndexer.swift:96-106`, `129-156`
- In `search(...)`, VPStudio calls the stream endpoint directly (`/stream/<movie|series>/<imdb[:S:E]>.json`) via `makeStreamURL(...)` and parses `streams` in `parseStreamPayload(...)`.
- Streams are accepted only if `infoHash` can be resolved from:
  1) `stream["infoHash"]`
  2) `extractInfoHash(from: urlString)`
  3) `extractInfoHash(from: stream["magnet"])`
- There is no fallback for URL-only hashes (e.g. Torrentio real-debrid URL format with hash in path, no `infoHash` field).
- Result: valid RD-style stremio items are filtered out early (`guard let infoHash, !infoHash.isEmpty else { return nil }`) and never reach ranking/sorting, reducing indexer quality and hit rate.

#### Why this is a concrete regression risk
- Open-source style parsers (e.g. AIOStreams) already treat `stream.infoHash` as optional and fallback to extracting the hash from the stream URL path before emitting torrent data.
  - See `AIOStreams` stream parser pattern: `stream.infoHash ?? getInfoHash(stream)` and `getInfoHash` regex over URL for 40-hex token.
- External streaming ecosystem examples (Torrentio/Riven) report valid streams returned without `infoHash`, with hash embedded in resolve URL.

## Recommendation
1. **Add hash fallback from `url` in stremio parser** (after magnet parsing), using a resilient 40-hex token extraction over URL path/query (case-insensitive).
2. Keep existing `infoHash`/`magnet` paths first for backwards compatibility.
3. Add regression test in `VPStudioTests/StremioIndexerTests.swift` using a payload like:
   - stream with valid title + `url: "https://torrentio.strem.fun/resolve/realdebrid/.../<40hex>/..."`
   - no `infoHash`
   - expected parsed count = 1
4. Optionally normalize extracted hash to lowercase before passing into `TorrentResult.fromSearch` (consistent with internal hash comparisons and debrid cache lookups).

## Secondary confirmation (fetch strategy)
- `search()` currently does the expected Stremio-style direct stream request (no preflight manifest request in search), matching desired fast-fetch strategy.
  - Confirmed by tests in `StremioIndexerTests.swift` (`manifestAndStreamURLComposition`, `searchDoesNotFetchManifest`) and `stremioConnectionTargetsManifestEndpoint` in connectivity tests for config validation.

---

### Confidence: High
Single change with clear upstream behavior mismatch; no code edits were made for this review.
