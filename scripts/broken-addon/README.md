# broken-addon — Rokumio test fixture

A static Stremio add-on with malformed/off-spec payloads for on-device
verification. It exists to reproduce crashes caused by bad add-on data and to
confirm the guards/resolvers handle them safely:

- **Movie catalog (`Broken Test Movies`)** — every malformed meta id shape plus
  one valid control (v0.3.1 Home/`MakeRowNode` crash class).
- **Series catalog (`Broken Test Series`)** — `tt9000001`, a series whose
  `meta.videos` mixes malformed season/episode identity data with valid episodes
  (the `EpisodesResolveVideoId` / Details Play crash when `episode` was
  `Invalid`, plus id-first/fallback resolution checks).

**Not for real use.** Committed test tooling, like `scripts/metahub-proxy.js`.

## Serve it

Static JSON is all a Stremio add-on needs; any file server works. Ngrok
supplies the HTTPS the app requires. Catalog payloads are provided both as
`catalog/<type>/broken.json` and as `catalog/<type>/broken/skip=0.json`
(path-extras convention).

```sh
cd scripts/broken-addon
python3 -m http.server 8940
ngrok http 8940
```

Then install in Rokumio's Add-ons screen:

```
https://<your-subdomain>.ngrok-free.app/manifest.json
```

Tip: before installing, confirm ngrok is passing non-browser requests through
(free tier may inject an interstitial for browser-like requests):

```sh
curl -H "User-Agent: rokumio" https://<your-subdomain>.ngrok-free.app/manifest.json
```

## Expected behavior

### Movies — malformed meta ids

| Meta | Pre-fix build | Fixed build |
|---|---|---|
| `tt0111161` (valid) | renders, opens Details | same |
| no id / null id | **Home crashes on launch** | dropped, toast + console log |
| numeric id `12345` | crash | dropped (protocol requires text), toast |
| empty id | crash | dropped, toast |

On the fixed build the console may show the offending add-on, e.g.:

```
Rokumio: dropped 4 metas without a usable id (addon=… catalog=broken)
```

### Series — broken/valid episode identity (`tt9000001`)

`meta/series/tt9000001.json` intentionally includes:
- videos with missing/`null` `episode` or `season` and no usable `video.id`
  (unaddressable; reproduces the old typed-parameter cast crash path),
- a video with a canonical `id` but `episode: null` (id-first resolution),
- valid videos (canonical `id` + ordinals, and ordinals-only fallback).

Verify on a fixed build:
- **Details → Play** on the series does **not** crash; it resolves the first
  addressable episode and opens Streams (skipping malformed leading entries).
- **Episodes screen** opens and lists seasons/episodes; selecting a valid
  episode opens Streams.
- Watched/options actions and season-scoped actions must not crash when
  malformed entries are present (unaddressable entries are skipped).
- No `Type Mismatch. Unable to cast "roInvalid" to "Integer"` from episode
  resolution.
