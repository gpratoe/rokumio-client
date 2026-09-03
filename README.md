<div align="center">

# Rokumio

### A modified Roku client for Stremio with support for external streaming servers.

<p>
  <img src="https://img.shields.io/badge/platform-Roku-662D91?style=flat-square" alt="Roku" />
  <img src="https://img.shields.io/badge/runtime-SceneGraph-8B5CF6?style=flat-square" alt="SceneGraph" />
  <img src="https://img.shields.io/badge/version-0.1.0-F59E0B?style=flat-square" alt="Version 0.1.0" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-22C55E?style=flat-square" alt="MIT License" /></a>
</p>


Rokumio is based on [Stroku-Native](https://github.com/gabrielsmith1874/Stroku/tree/main/Stroku-Native) and extends its native Roku Stremio client with the ability to connect to an external
streaming server. The server can resolve and process streams that cannot be played directly by Roku.

</div>

## What Rokumio does

- Browse Cinemeta movie and series metadata with the Roku remote.
- Connect a Stremio account through the official link-code flow.
- Browse, add, remove, and sync library items.
- Explore series with seasons, episodes, air dates, descriptions, and progress.
- Install multiple stream and subtitle add-ons from manifest URLs.
- Match add-ons by their declared resources, types, and ID prefixes.
- Play direct HTTP(S) media URLs and select subtitle tracks.
- Customize subtitle appearance and playback settings.
- Accept direct media URLs through Roku deep linking with `contentId`.
- Connect to an external Stremio-compatible streaming server.
- Send selected streams to the external server for processing and playback.

## What it does not do
Rokumio is a Roku client and does not provide or distribute media itself. Media that cannot be played directly by Roku can be handled by a configured external streaming server. The server is responsible for resolving and processing supported streams before they are delivered to the Roku client. Rokumio-client itself does not contain a torrent engine.

## How it works

```text
Your Roku  <->  Rokumio-client  <->  Stremio metadata / account services
                    │
                    ├── add-ons you install yourself
                    │
                    ├── direct HTTP(S) media URLs
                    │
              Streaming server
```

Add-ons are supplied by the user through a manifest URL. Rokumio stores configured add-ons and the Stremio auth key in the Roku registry; it does not operate or control third-party add-ons.

## Quick start

### 1. Package the channel

Requires Node.js and a Roku device in developer mode.

```powershell
npm install
npm run package
```

Sideload `dist/rokumio-client.zip` through Roku developer mode.

### 2. Add stream or subtitle add-ons

While Rokumio is open, visit the phone setup address shown in the upper-right corner of the TV. Paste a complete `https://.../manifest.json` URL and select **Add to Roku**. Your phone and Roku must be on the same local network.

### 3. Connect Stremio

Press `*` on the home screen, choose **Connect Stremio**, then open the displayed `link.stremio.com` URL on another device and approve the connection. Once connected, your library and watch history can be accessed from the Roku.

### 4. Connect an external streaming server

For streams that cannot be played directly by Roku, you can optionally configure an external Stremio-compatible streaming server.

For a quick setup on a mobile device, you can use [Rokumio Service](https://github.com/gpratoe/rokumio-service). Alternatively, you can use a desktop device running Stremio Service or another Stremio-compatible streaming server of your choice.

Rokumio Client does not provide or operate the streaming server itself.

## Development

Run the checks locally:

```powershell
npm test
```

The mock add-on server exercises direct streams, subtitle results, malformed manifests, and torrent-only filtering without changing the production package:

```powershell
node tests/mock-addon-server.mjs
powershell -ExecutionPolicy Bypass -File tests/build-mock-package.ps1
```

For a provider-neutral manifest fixture:

```powershell
powershell -ExecutionPolicy Bypass -File tests/build-mock-package.ps1 `
  -ManifestUrl "http://127.0.0.1:7319/generic/manifest.json"
```

## Documentation

- [Contributing guide](CONTRIBUTING.md)
- [Security policy](SECURITY.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)

Research notes and UI reference captures are intentionally excluded from this
public export pending separate ownership and trademark review.

## Limitations

Playback depends on the protocols, codecs, and subtitle formats supported by the Roku model. Roku-specific behavior still needs testing on physical devices, especially playback headers, codec compatibility, local setup, and registry persistence.

## Based on

Rokumio is based on [Stroku/Stroku-Native](https://github.com/gabrielsmith1874/Stroku), originally developed by [gabrielsmith1874](https://github.com/gabrielsmith1874) and contributors.

The original project provides the Roku-side Stremio client,
including metadata, libraries, add-ons, subtitles, and direct
HTTP(S) playback. Rokumio extends this functionality with
external streaming server support.

## Disclaimer

<details>
<summary>Read the project disclaimer</summary>

Rokumio is a free, open-source client application. It does not host, index, cache, or distribute media content, operate content servers, provide streaming services, or maintain a catalogue of sources. Rokumio itself has no torrent client and does not process magnet links, `.torrent` files, or peer-to-peer swarms. Users may optionally configure an external streaming server of their choice to process and serve streams that cannot be played directly by Roku. Rokumio does not provide, operate, or control such servers.

The only add-on included by default is Cinemeta, the official Stremio metadata catalogue, which supplies titles, artwork, and descriptions only. Every other add-on is installed by the user from a manifest URL the user supplies. This project does not recommend, rank, bundle, link to, or distribute third-party add-ons, and does not operate or control any add-on you install.

Users are responsible for ensuring that the sources they connect and the content they access are lawful in their jurisdiction. Do not use this software to infringe copyright or to circumvent access controls.

Rokumio is an independent project and is not affiliated with, endorsed by, or associated with Roku, Inc. or Stremio. All trademarks are the property of their respective owners.

Provided “as is”, without warranty of any kind. See [LICENSE](LICENSE).

</details>
