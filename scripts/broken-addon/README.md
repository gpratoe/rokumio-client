# broken-addon — Rokumio test fixture

A static Stremio add-on whose catalog ships **every malformed meta id shape**
plus one valid control. It exists to reproduce the v0.3.1 channel-killer (one
add-on meta without a usable id crashed Home in `MakeRowNode` on every launch —
Roku cast `roInvalid` into a typed `String` `callFunc` parameter, and
BrightScript has no try/catch) and to verify the guard stack against it:

- row-build filter drops the bad metas and toasts ("Some titles were skipped…"),
- the push handlers refuse to open one if a path ever leaks it ("This title is
  not available"),
- the library adapters coerce non-text ids so no call can crash on them.

**Not for real use.** It is committed test tooling, like `scripts/metahub-proxy.js`.

## Serve it

Static JSON is all a Stremio add-on needs (see the official
`stremio-static-addon-example`); any file server works. Ngrok supplies the
HTTPS the app requires. Note the Stremio path-extras convention: with any
extras (even a bare `skip=0`) the catalog URL gains a path segment, so the
payload lives at `catalog/movie/broken/skip=0.json`:

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
(free tier injects an interstitial for browser-like requests):

```sh
curl -H "User-Agent: rokumio" https://<your-subdomain>.ngrok-free.app/manifest.json
```

## Expected behavior

| Meta | Pre-fix build | Fixed build |
|---|---|---|
| `tt0111161` (valid) | renders, opens Details | same |
| no id / null id | **Home crashes on launch** | dropped, toast + console log |
| numeric id `12345` | crash | dropped (protocol requires text), toast |
| empty id | crash | dropped, toast |

On the fixed build the console shows the offending add-on, e.g.:

```
Rokumio: dropped 4 metas without a usable id (addon=… catalog=broken)
```
