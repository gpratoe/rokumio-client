' PlaybackStore unit tests.
'
' Streams() talks to an add-on through the scripted transport. Everything else
' is pure: a torrent resolves to a streaming-server URL built from the stream
' itself, so the empty script is the assertion — an unscripted call returns
' not-ok AND is logged, so any request sneaking back in fails on both counts
' rather than one.

function TorrentStream(infoHash as string, fileIdx = invalid as dynamic) as object
    stream = { infoHash: infoHash }
    if fileIdx <> invalid then stream.fileIdx = fileIdx
    return stream
end function

' A torrent stream carrying engine sources. `sources` is what the add-on
' protocol calls the list the streaming server calls `announce`; add-ons in the
' wild send either, so both are settable here.
function SourcedTorrentStream(infoHash as string, sources = invalid as dynamic, announce = invalid as dynamic) as object
    stream = { infoHash: infoHash }
    if sources <> invalid then stream.sources = sources
    if announce <> invalid then stream.announce = announce
    return stream
end function

sub Test_Playback_Streams()
    Harness_Suite("PlaybackStore.Streams fetches the add-on stream list")
    address = "https://addon.example.com"
    script = [
        {
            method: "GET"
            url: address + "/stream/movie/tt0133093.json"
            ok: true
            status: 200
            json: {
                streams: [
                    { name: "Mock Stream", infoHash: "abc123", fileIdx: 1 }
                    { name: "Direct", url: "http://127.0.0.1:11470/mock/file.mp4" }
                ]
            }
            error: ""
        }
    ]
    store = PlaybackStore(ScriptedTransport(script))
    result = store.Streams(address, "movie", "tt0133093")

    Harness_Ok(result.ok, "streams ok")
    Harness_Equal(result.streams.Count(), 2, "two candidates")
    Harness_Equal(result.streams[1].url, "http://127.0.0.1:11470/mock/file.mp4", "direct url intact")
end sub

sub Test_Playback_StreamsValidates()
    Harness_Suite("PlaybackStore.Streams rejects a missing streams array")
    script = [{ method: "GET", ok: true, status: 200, json: {}, error: "" }]
    store = PlaybackStore(ScriptedTransport(script))
    result = store.Streams("https://addon.example.com", "movie", "tt0133093")

    Harness_Ok(not result.ok, "streams rejected")
    Harness_Equal(result.error, "stream response missing streams", "error names the missing array")
end sub

sub Test_Playback_StreamsNoAddress()
    Harness_Suite("PlaybackStore.Streams refuses a blank addon address")
    store = PlaybackStore(ScriptedTransport([]))
    result = store.Streams("", "movie", "tt0133093")
    Harness_Ok(not result.ok, "no address refused")
    Harness_Equal(result.error, "no addon address", "error names the missing address")
end sub

sub Test_Playback_DirectStreamResolvesAsIs()
    Harness_Suite("PlaybackStore.ResolvePlayback passes a direct URL through")
    store = PlaybackStore(ScriptedTransport([]))
    result = store.ResolvePlayback("http://127.0.0.1:11470", { url: "http://direct.example/file.mp4" })

    Harness_Ok(result.ok, "direct resolves")
    Harness_Equal(result.url, "http://direct.example/file.mp4", "url unchanged")
end sub

' --- the container the Video node is told to play --------------------------
'
' Roku defaults streamFormat to MP4 (H.264/AAC), so a format left unset on an
' MKV or an HLS manifest is the "buffers, then errors" case. The add-on's own
' filename is the most trusted hint; the URL is the fallback, because a presigned
' link can carry the filename only in its query and nothing in its path.
sub Test_Playback_StreamFormatFromUrl()
    Harness_Suite("PlaybackStore.StreamFormat reads the container from the URL")
    store = PlaybackStore(ScriptedTransport([]))

    Harness_Equal(store.StreamFormat(invalid, "https://x.example/movie.mp4"), "mp4", "mp4")
    Harness_Equal(store.StreamFormat(invalid, "https://x.example/movie.MKV"), "mkv", "mkv, case-insensitive")
    Harness_Equal(store.StreamFormat(invalid, "https://x.example/master.m3u8"), "hls", "hls")
    Harness_Equal(store.StreamFormat(invalid, "https://x.example/live.m3u"), "hls", "m3u is hls too")
    Harness_Equal(store.StreamFormat(invalid, "https://x.example/hls3/01/15255/stream/master.txt"), "", "txt alone does not declare a format")
    Harness_Equal(store.StreamFormat(invalid, "https://x.example/manifest.mpd"), "dash", "dash")
    Harness_Equal(store.StreamFormat(invalid, "https://x.example/clip.mov"), "mp4", "mov maps to mp4 per Roku")
    Harness_Equal(store.StreamFormat(invalid, "https://x.example/opaque-object-id"), "", "nothing to go on")
end sub

sub Test_Playback_StreamFormatPrefersTheAddonFilename()
    Harness_Suite("PlaybackStore.StreamFormat prefers the add-on's filename, then the title line")
    store = PlaybackStore(ScriptedTransport([]))

    ' behaviorHints.filename is the protocol's dedicated slot. It decides even
    ' when the URL says nothing, which is the presigned direct-link case.
    hinted = { url: "https://x.example/hub/abc?X-Amz-Signature=deadbeef", behaviorHints: { filename: "Backrooms.2026.720p.10Bit.WEB-DL.HEVC.x265-HDHub4u.Ms.mkv" } }
    Harness_Equal(store.StreamFormat(hinted, hinted.url), "mkv", "behaviorHints.filename decides")

    ' The title's first line is the fallback many add-ons use; the metadata lines
    ' below it are not part of the filename.
    titled = { title: "Show.S01E09.2160p.WEB-DL.mkv" + Chr(10) + "Seeders: 284  Size: 7.48 GB", url: "https://x.example/hub/abc" }
    Harness_Equal(store.StreamFormat(titled, titled.url), "mkv", "the title's first line decides")

    ' `name` is the provider/quality label, a different field with a different
    ' meaning, and must not be read as a filename.
    labelled = { name: "Provider 4k.mkv", url: "https://x.example/hub/abc" }
    Harness_Equal(store.StreamFormat(labelled, labelled.url), "", "the name label is not a filename")
end sub

sub Test_Playback_StreamFormatFilenameHintDoesNotShadowTheTitle()
    Harness_Suite("PlaybackStore.StreamFormat lets an extensionless filename hint fall through to the title")
    store = PlaybackStore(ScriptedTransport([]))

    ' The add-on filled behaviorHints.filename with a non-filename (a slug) while
    ' the real release name, extension and all, sits in the title. The hint must
    ' not be believed — this is the add-on shape that returned "" and left an MKV
    ' playing as an unformatted MP4.
    stream = {
        title: "Backrooms.2026.Extended.Version.720P.10bit.Web-Dl.hindi.English.Esubs.x265-1VegaMovies.tw.mkv"
        behaviorHints: { filename: "EZz5fGCc" }
    }
    Harness_Equal(store.StreamFormat(stream, "https://pixeldrain.dev/api/file/EZz5fGCc?download"), "mkv", "the title's .mkv is found past the extensionless hint")

    ' The device log's actual pixeldrain shape: no title and no hint at all —
    ' the release name (extension and all) lives in the description, which is
    ' also the field the stream card renders.
    described = { name: "PixelDrain", description: "[737.69 MB]Backrooms.2026.Extended.Version.720P.10bit.Web-Dl.hindi.English.Esubs.x265-1VegaMovies.tw.mkv" }
    Harness_Equal(store.StreamFormat(described, "https://pixeldrain.dev/api/file/EZz5fGCc?download"), "mkv", "the description's .mkv names the container")

    ' And the same slug-in-the-hint shape with the title missing: the description
    ' is the only thing that names the file.
    slugged = { behaviorHints: { filename: "EZz5fGCc" }, description: "Backrooms.2026.1080p.AMZN.WEBRip.Hindi-English.DDP5.1.H.264-1vegamovies.tw.mkv" }
    Harness_Equal(store.StreamFormat(slugged, "https://pixeldrain.dev/api/file/EZz5fGCc?download"), "mkv", "a slug hint falls through to the description")
end sub

sub Test_Playback_StreamFormatFromTheUrlQuery()
    Harness_Suite("PlaybackStore.StreamFormat reads a filename hidden in the URL query")
    store = PlaybackStore(ScriptedTransport([]))

    ' A presigned link names the object with an opaque path and carries the real
    ' (percent-encoded) filename in response-content-disposition.
    base = "https://bucket.example/hub/86c8d926f3d0a60b?X-Amz-Algorithm=AWS4-HMAC-SHA256"
    disposition = "&response-content-disposition=attachment%3B%20filename%3D%22Backrooms.2026.720p.10Bit.WEB-DL.HEVC.x265-HDHub4u.Ms.mkv%22"
    signature = "&X-Amz-Signature=cbaa23c73ff78d4d69a15ed6cf997e9ce46f3d7bdfe98d2e365efcc200b15caf"
    Harness_Equal(store.StreamFormat(invalid, base + disposition + signature), "mkv", "the query filename is the last resort")
end sub

sub Test_Playback_StreamFormatKeepsManifestsManifests()
    Harness_Suite("PlaybackStore.StreamFormat never overrides an HLS or DASH URL with a file hint")
    store = PlaybackStore(ScriptedTransport([]))

    ' A torrent resolves to our /hls.m3u8 transcode; the source file's container is
    ' irrelevant there, and declaring it would break the transcode that makes it
    ' playable at all.
    torrent = { infoHash: "abc123", behaviorHints: { filename: "Show.2160p.DV.mkv" } }
    result = store.ResolvePlayback("http://127.0.0.1:11470", torrent)
    Harness_Ok(result.ok, "torrent resolves")
    Harness_Equal(result.streamFormat, "hls", "the HLS URL wins for a torrent")

    ' A direct HLS manifest is the transport, not the media, so a filename hint
    ' does not replace it.
    direct = { url: "https://x.example/live/master.m3u8?token=abc", title: "Show.1080p.mkv" }
    Harness_Equal(store.StreamFormat(direct, direct.url), "hls", "an HLS manifest stays HLS")
    Harness_Ok(not store.NeedsFormatProbe(direct, direct.url), "a recognized HLS suffix skips the extra request")

    conflict = { url: "https://x.example/download/movie.mp4", behaviorHints: { filename: "Movie.mkv" } }
    Harness_Ok(store.NeedsFormatProbe(conflict, conflict.url), "conflicting media suffix and filename trigger a probe")

    disguised = { url: "https://x.example/hls3/01/master.mkv", behaviorHints: { filename: "Movie.mkv" } }
    Harness_Ok(store.NeedsFormatProbe(disguised, disguised.url), "an HLS master route is probed even with a media-looking suffix")

    textPlaylist = {
        url: "https://x.example/hls3/01/15255/stream/master.txt"
        behaviorHints: { filename: "Show.1080p.H264.AAC.mkv" }
    }
    Harness_Equal(store.StreamFormat(textPlaylist, textPlaylist.url), "mkv", "the source filename is only the pre-probe fallback")
    Harness_Ok(store.NeedsFormatProbe(textPlaylist, textPlaylist.url), "an extensionless manifest transport gets probed despite its file hint")
end sub

sub Test_Playback_ProbeStreamFormatUsesHeadersAndPlaylistSignature()
    Harness_Suite("PlaybackStore probes an ambiguous response using add-on headers")
    url = "https://video.example/hls3/01/15255/stream/master.txt"
    script = [
        { method: "HEAD", url: url, ok: true, status: 200, responseHeaders: { "Content-Type": "text/plain", "Content-Length": "96" }, error: "" }
        { method: "GET", url: url, ok: true, status: 206, body: "#EXTM3U" + chr(10) + "#EXT-X-VERSION:3" + chr(10), responseHeaders: { "Content-Type": "text/plain" }, error: "" }
    ]
    store = PlaybackStore(ScriptedTransport(script))
    headers = { Referer: "https://source.example/", "User-Agent": "Rokumio test agent" }
    headTransport = ScriptedTransport(script)
    headCheck = headTransport.Head(url, 2500, headers)
    Harness_Equal(headCheck.responseHeaders["Content-Length"], "96", "the mock HEAD response carries its length header")
    Harness_Equal(store.ResponseHeader(headCheck.responseHeaders, "content-length"), "96", "response header lookup is case-insensitive")
    Harness_Equal(store.ResponseContentLength(headCheck.responseHeaders), 96, "content length parser accepts the header value")
    probe = store.ProbeStreamFormat(url, headers)

    Harness_Equal(probe.format, "hls", "the playlist body signature beats text/plain and the .mkv source hint")
    Harness_Equal(probe.contentLength, 96, "HEAD content length is parsed for the bounded read")
    Harness_Equal(probe.source, "body", "format source is the response signature")
    Harness_Equal(store.transport.log.Count(), 2, "small ambiguous body is read after HEAD")
    Harness_Equal(store.transport.log[0].headers.Referer, headers.Referer, "HEAD carries the add-on Referer")
    Harness_Equal(store.transport.log[1].headers.Referer, headers.Referer, "range GET carries the add-on Referer")
    Harness_Equal(store.transport.log[1].headers.Range, "bytes=0-4095", "body probe requests only a prefix")
end sub

sub Test_Playback_ProbeStreamFormatUsesMimeWithoutReadingLargeBody()
    Harness_Suite("PlaybackStore uses a known response MIME without fetching a large body")
    url = "https://video.example/opaque"
    script = [
        { method: "HEAD", url: url, ok: true, status: 200, responseHeaders: { "Content-Type": "application/dash+xml", "Content-Length": "8000000" }, error: "" }
    ]
    store = PlaybackStore(ScriptedTransport(script))
    probe = store.ProbeStreamFormat(url, {})

    Harness_Equal(probe.format, "dash", "DASH MIME identifies the transport")
    Harness_Equal(probe.source, "content-type", "format source is response MIME")
    Harness_Equal(store.transport.log.Count(), 1, "large response is not fetched for body sniffing")

    smallScript = [
        { method: "HEAD", url: url, ok: true, status: 200, responseHeaders: { "Content-Type": "video/mp4", "Content-Length": "128" }, error: "" }
    ]
    smallStore = PlaybackStore(ScriptedTransport(smallScript))
    smallProbe = smallStore.ProbeStreamFormat(url, {})
    Harness_Equal(smallProbe.format, "mp4", "MP4 MIME identifies the container")
    Harness_Equal(smallStore.transport.log.Count(), 1, "a known MIME avoids a redundant GET even for a small file")
end sub

sub Test_Playback_ProbeStreamFormatUsesNarrowPlaylistRouteFallback()
    Harness_Suite("PlaybackStore recognizes the HLS3 master route without an unbounded GET")
    url = "https://video.example/hls3/01/15255/stream/master.txt"
    script = [
        { method: "HEAD", url: url, ok: false, status: 405, body: "", responseHeaders: {}, error: "HTTP 405" }
    ]
    store = PlaybackStore(ScriptedTransport(script))
    probe = store.ProbeStreamFormat(url, {})

    Harness_Equal(probe.format, "hls", "the specific HLS master route is the last-resort signal")
    Harness_Equal(probe.source, "url-pattern", "route fallback is identified as a heuristic")
    Harness_Equal(store.transport.log.Count(), 1, "no GET is made when HEAD has no bounded size")
end sub

sub Test_Playback_ProbeStreamFormatStopsBeforePrefixGet()
    Harness_Suite("PlaybackStore skips the body probe after playback cancellation")
    url = "https://video.example/opaque"
    script = [
        { method: "HEAD", url: url, ok: true, status: 200, responseHeaders: { "Content-Length": "64" }, error: "" }
        { method: "GET", url: url, ok: true, status: 206, body: "#EXTM3U", responseHeaders: {}, error: "" }
    ]
    store = PlaybackStore(ScriptedTransport(script))
    stoppedTask = { state: "stop" }
    probe = store.ProbeStreamFormat(url, {}, stoppedTask)

    Harness_Ok(probe.cancelled, "probe records cancellation")
    Harness_Equal(store.transport.log.Count(), 1, "no prefix GET after stop")
end sub

sub Test_Playback_ProbeStreamFormatUsesContainerSignature()
    Harness_Suite("PlaybackStore identifies an MP4 container from a small response signature")
    url = "https://video.example/opaque"
    ' The interpreter drops NUL characters from BrightScript strings, so model
    ' the visible ftyp marker directly; the production check also tolerates that.
    body = "ftypisom"
    script = [
        { method: "HEAD", url: url, ok: true, status: 200, responseHeaders: { "Content-Type": "application/octet-stream", "Content-Length": body.Len().ToStr() }, error: "" }
        { method: "GET", url: url, ok: true, status: 206, body: body, responseHeaders: {}, error: "" }
    ]
    store = PlaybackStore(ScriptedTransport(script))
    Harness_Equal(store.FormatFromBody(body), "mp4", "container signature recognizer accepts ftyp")
    probe = store.ProbeStreamFormat(url, {})

    Harness_Equal(probe.format, "mp4", "ftyp identifies ISO BMFF")
    Harness_Equal(probe.source, "body", "format source is the byte signature")
end sub

sub Test_Playback_ResolvePlaybackReportsTheStreamFormat()
    Harness_Suite("PlaybackStore.ResolvePlayback attaches the resolved stream format")
    store = PlaybackStore(ScriptedTransport([]))

    direct = store.ResolvePlayback("http://127.0.0.1:11470", { url: "https://x.example/movie.mkv" })
    Harness_Ok(direct.ok, "direct resolves")
    Harness_Equal(direct.streamFormat, "mkv", "the direct url's container rides the result")

    refused = store.ResolvePlayback("", { infoHash: "abc123" })
    Harness_Ok(not refused.ok, "a torrent with no server is refused")
    Harness_Equal(refused.streamFormat, "", "a refused stream reports an empty format, never invalid")
end sub

sub Test_Playback_ResolvePlaybackIncludesProxyRequestHeaders()
    Harness_Suite("PlaybackStore.ResolvePlayback carries add-on proxy request headers")
    store = PlaybackStore(ScriptedTransport([]))
    stream = {
        url: "https://video.example/master.m3u8"
        behaviorHints: {
            proxyHeaders: {
                request: {
                    "User-Agent": "Rokumio test agent"
                    Referer: "https://play.example/"
                    "X-Invalid": 42
                    "Bad Header": "ignored"
                    "X-Newline": "bad" + chr(10) + "value"
                }
            }
        }
    }
    result = store.ResolvePlayback("", stream)

    Harness_Ok(result.ok, "direct URL still resolves")
    Harness_Equal(result.requestHeaders["User-Agent"], "Rokumio test agent", "user-agent retained")
    Harness_Equal(result.requestHeaders.Referer, "https://play.example/", "referer retained")
    Harness_Equal(result.requestHeaders.Count(), 2, "malformed names and values are dropped")

    noHeaders = store.ResolvePlayback("", { url: "https://video.example/open.m3u8" })
    Harness_Equal(noHeaders.requestHeaders.Count(), 0, "streams without proxy headers clear to an empty map")
end sub

' --- the file index the stream already carries -----------------------------
'
' The stream's own fileIdx IS the file, so the URL is the whole answer and the
' server is never asked anything.
sub Test_Playback_IntegerFileIdxResolvesWithoutAskingTheServer()
    Harness_Suite("PlaybackStore.ResolvePlayback uses an integer fileIdx without calling the server")
    server = "http://127.0.0.1:11470"
    infoHash = "0123456789abcdef0123456789abcdef01234567"
    store = PlaybackStore(ScriptedTransport([]))
    result = store.ResolvePlayback(server, TorrentStream(infoHash, 3))

    Harness_Ok(result.ok, "resolves")
    Harness_Equal(store.transport.log.Count(), 0, "no request made at all")
    Harness_Equal(result.url, server + "/" + infoHash + "/3/hls.m3u8", "HLS url built from the index")
end sub

' 0 is the index that was most wrong before: sent as a guessFileIdx needle it
' matched the first path containing a zero, which on a 1080p/x264 release is the
' 1080p file regardless of what the add-on meant.
sub Test_Playback_ZeroFileIdxIsAnIndexNotANeedle()
    Harness_Suite("PlaybackStore.ResolvePlayback treats fileIdx 0 as index 0")
    server = "http://127.0.0.1:11470"
    infoHash = "0123456789abcdef0123456789abcdef01234567"
    store = PlaybackStore(ScriptedTransport([]))
    result = store.ResolvePlayback(server, TorrentStream(infoHash, 0))

    Harness_Ok(result.ok, "resolves")
    Harness_Equal(store.transport.log.Count(), 0, "no request made at all")
    Harness_Equal(result.url, server + "/" + infoHash + "/0/hls.m3u8", "index 0, not a name search")
end sub

' A stream with no index is not a problem to be solved by asking the server.
' -1 IS the protocol's way of saying "you choose", and the file list it chooses
' from is on the server already, so the URL is fully determined without a
' request. This is the test that the create round-trip cannot come back: there
' is no longer a fallback path that could quietly make a request while still
' producing a working URL.
sub Test_Playback_MissingFileIdxAsksTheServerToChoose()
    Harness_Suite("PlaybackStore.ResolvePlayback answers a missing fileIdx with -1, no round trip")
    server = "http://127.0.0.1:11470"
    infoHash = "0123456789abcdef0123456789abcdef01234567"
    store = PlaybackStore(ScriptedTransport([]))
    result = store.ResolvePlayback(server, TorrentStream(infoHash))

    Harness_Ok(result.ok, "resolves")
    Harness_Equal(store.transport.log.Count(), 0, "no request made at all")
    Harness_Equal(result.url, server + "/" + infoHash + "/-1/hls.m3u8", "-1 tells the server to choose")
end sub

' A filename is not an index. The official client types this field as an
' integer and treats anything else as absent; forwarding a name as a search
' needle was how fileIdx 0 came to match the 1080p release, so a name is now
' treated exactly like a missing value rather than given a second meaning.
sub Test_Playback_StringFileIdxIsNotAnIndex()
    Harness_Suite("PlaybackStore.ResolvePlayback treats a string fileIdx as absent")
    server = "http://127.0.0.1:11470"
    infoHash = "0123456789abcdef0123456789abcdef01234567"
    store = PlaybackStore(ScriptedTransport([]))
    result = store.ResolvePlayback(server, TorrentStream(infoHash, "Show.S01E05.1080p.mkv"))

    Harness_Ok(result.ok, "still resolves")
    Harness_Equal(store.transport.log.Count(), 0, "no request made at all")
    Harness_Equal(result.url, server + "/" + infoHash + "/-1/hls.m3u8", "-1, and the name is nowhere in the url")
end sub

' A fraction is not a position in any file list, so it is not an index either.
sub Test_Playback_FractionalFileIdxIsNotAnIndex()
    Harness_Suite("PlaybackStore.ResolvePlayback will not index into a file list with a fraction")
    server = "http://127.0.0.1:11470"
    infoHash = "0123456789abcdef0123456789abcdef01234567"
    store = PlaybackStore(ScriptedTransport([]))
    result = store.ResolvePlayback(server, TorrentStream(infoHash, 1.5))

    Harness_Ok(result.ok, "still resolves")
    Harness_Equal(store.transport.log.Count(), 0, "no request made at all")
    Harness_Equal(result.url, server + "/" + infoHash + "/-1/hls.m3u8", "-1, not a truncated 1")
end sub

' --- filters and trackers ride the URL -------------------------------------
'
' The server collects every occurrence of a key, so a repeated f= is two
' constraints it ANDs together. One comma-joined value would be a single
' constraint looking for a literal comma, which matches nothing and fails
' silently into the largest-video fallback — the wrong episode, no error.
sub Test_Playback_EpisodeFiltersTravelAsRepeatedParams()
    Harness_Suite("PlaybackStore sends the season/episode filters as repeated f= parameters")
    server = "http://127.0.0.1:11470"
    infoHash = "0123456789abcdef0123456789abcdef01234567"
    store = PlaybackStore(ScriptedTransport([]))
    result = store.ResolvePlayback(server, TorrentStream(infoHash), 1, 5)

    Harness_Ok(result.ok, "resolves")
    Harness_Equal(store.transport.log.Count(), 0, "no request made at all")
    Harness_Equal(result.url, server + "/" + infoHash + "/-1/hls.m3u8?f=episode%3A%205&f=season%3A%201", "both filters, percent-encoded, as separate keys")
end sub

' A movie has no season or episode, and neither does a special. "season: 0" would
' not narrow the match to the right file, it would narrow it to a wrong one, so
' specials are left on the server's own largest-video choice.
sub Test_Playback_NoFiltersWithoutARealEpisode()
    Harness_Suite("PlaybackStore asks for no filters for a movie or a special")
    server = "http://127.0.0.1:11470"
    infoHash = "0123456789abcdef0123456789abcdef01234567"
    store = PlaybackStore(ScriptedTransport([]))

    movie = store.ResolvePlayback(server, TorrentStream(infoHash), 0, 0)
    Harness_Equal(movie.url, server + "/" + infoHash + "/-1/hls.m3u8", "a movie asks for nothing")

    special = store.ResolvePlayback(server, TorrentStream(infoHash), 0, 5)
    Harness_Equal(special.url, server + "/" + infoHash + "/-1/hls.m3u8", "season 0 asks for nothing")

    noEpisode = store.ResolvePlayback(server, TorrentStream(infoHash), 2, 0)
    Harness_Equal(noEpisode.url, server + "/" + infoHash + "/-1/hls.m3u8", "episode 0 asks for nothing")
end sub

' The trackers are the engine's bootstrapping sources and the official client
' passes every one through. Dropping them is what made a cold engine expensive:
' with nothing to try, metadata has to arrive over DHT alone.
sub Test_Playback_TrackersTravelAsRepeatedParams()
    Harness_Suite("PlaybackStore sends the stream's sources as repeated tr= parameters")
    server = "http://127.0.0.1:11470"
    infoHash = "0123456789abcdef0123456789abcdef01234567"
    store = PlaybackStore(ScriptedTransport([]))
    stream = SourcedTorrentStream(infoHash, ["udp://tracker.example:1337/announce", "http://backup.example/announce"])
    result = store.ResolvePlayback(server, stream)

    Harness_Ok(result.ok, "resolves")
    Harness_Equal(store.transport.log.Count(), 0, "no request made at all")
    Harness_Equal(result.url, server + "/" + infoHash + "/-1/hls.m3u8?tr=udp%3A%2F%2Ftracker.example%3A1337%2Fannounce&tr=http%3A%2F%2Fbackup.example%2Fannounce", "both trackers, percent-encoded, as separate keys")
end sub

' The add-on protocol says `sources` and the streaming server says `announce`.
' They are the same list, and both spellings are in the wild.
sub Test_Playback_AnnounceIsReadWhenSourcesIsAbsent()
    Harness_Suite("PlaybackStore reads announce when the stream has no sources")
    server = "http://127.0.0.1:11470"
    infoHash = "0123456789abcdef0123456789abcdef01234567"
    store = PlaybackStore(ScriptedTransport([]))
    stream = SourcedTorrentStream(infoHash, invalid, ["udp://only.example:1337/announce"])
    result = store.ResolvePlayback(server, stream)

    Harness_Equal(result.url, server + "/" + infoHash + "/-1/hls.m3u8?tr=udp%3A%2F%2Fonly.example%3A1337%2Fannounce", "announce used when sources is absent")
end sub

' Filters first, then trackers, sharing ONE question mark. Two "?" would make
' the second one part of the first value's data.
sub Test_Playback_FiltersAndTrackersShareOneQuery()
    Harness_Suite("PlaybackStore joins filters and trackers into a single query string")
    server = "http://127.0.0.1:11470"
    infoHash = "0123456789abcdef0123456789abcdef01234567"
    store = PlaybackStore(ScriptedTransport([]))
    stream = SourcedTorrentStream(infoHash, ["udp://tracker.example:1337/announce"])
    result = store.ResolvePlayback(server, stream, 2, 7)

    Harness_Equal(result.url, server + "/" + infoHash + "/-1/hls.m3u8?f=episode%3A%207&f=season%3A%202&tr=udp%3A%2F%2Ftracker.example%3A1337%2Fannounce", "one ?, filters then trackers")
end sub

' A malformed entry from an add-on must cost that entry, not the whole URL: an
' exception escaping here would take playback down over a bad tracker.
sub Test_Playback_OneBadTrackerDoesNotCostTheUrl()
    Harness_Suite("PlaybackStore drops unusable tracker entries instead of failing")
    server = "http://127.0.0.1:11470"
    infoHash = "0123456789abcdef0123456789abcdef01234567"
    store = PlaybackStore(ScriptedTransport([]))
    stream = SourcedTorrentStream(infoHash, ["udp://good.example:1337/announce", 42])
    result = store.ResolvePlayback(server, stream)

    Harness_Ok(result.ok, "still resolves")
    Harness_Equal(result.url, server + "/" + infoHash + "/-1/hls.m3u8?tr=udp%3A%2F%2Fgood.example%3A1337%2Fannounce", "the number is dropped, the tracker survives")
end sub

sub Test_Playback_TorrentWithoutServerAddress()
    Harness_Suite("PlaybackStore.ResolvePlayback refuses a torrent with no server")
    store = PlaybackStore(ScriptedTransport([]))
    result = store.ResolvePlayback("", { infoHash: "abc123" })

    Harness_Ok(not result.ok, "resolved refused")
    Harness_Equal(result.error, "no streaming server address", "error names the missing server")
end sub

sub Test_Playback_PlaybackUrl()
    Harness_Suite("PlaybackStore.PlaybackUrl builds the master HLS url and appends the query")
    store = PlaybackStore(ScriptedTransport([]))
    Harness_Equal(
        store.PlaybackUrl("http://127.0.0.1:11470", "abc123", 4),
        "http://127.0.0.1:11470/abc123/4/hls.m3u8",
        "master HLS url, no query when there is nothing to say"
    )
    Harness_Equal(
        store.PlaybackUrl("http://127.0.0.1:11470", "abc123", -1, ["episode: 5"], ["udp://t.example:1337/announce"]),
        "http://127.0.0.1:11470/abc123/-1/hls.m3u8?f=episode%3A%205&tr=udp%3A%2F%2Ft.example%3A1337%2Fannounce",
        "query appended after the suffix"
    )
end sub

' The warm-up goes to the bare route, which is a DIFFERENT url from the one the
' player is handed. If the two could drift, the engine would be warmed for one
' file while another was asked to play, and the warm-up would be worse than
' useless — so both are pinned here rather than only the one being changed.
sub Test_Playback_EngineUrlIsTheBareRoute()
    Harness_Suite("PlaybackStore.EngineUrl builds the bare torrent url the warm-up is sent to")
    server = "http://127.0.0.1:11470"
    store = PlaybackStore(ScriptedTransport([]))

    Harness_Equal(
        store.EngineUrl(server, TorrentStream("abc123", 4)),
        server + "/abc123/4",
        "the official shape, with no hls suffix"
    )
    Harness_Equal(
        store.EngineUrl(server, TorrentStream("abc123", 4), 2, 5),
        server + "/abc123/4?f=episode%3A%205&f=season%3A%202",
        "carrying the same filters the playlist url does"
    )
    Harness_Equal(
        store.EngineUrl(server, SourcedTorrentStream("abc123", invalid, ["udp://t.example:1337/announce"])),
        server + "/abc123/-1?tr=udp%3A%2F%2Ft.example%3A1337%2Fannounce",
        "and the same trackers, which is what makes warming it early worth doing"
    )
    Harness_Equal(store.EngineUrl("", TorrentStream("abc123")), "", "no server, no url")
    Harness_Equal(store.EngineUrl(server, TorrentStream("")), "", "no hash, no url")
end sub

sub Test_Playback_Heartbeat()
    Harness_Suite("PlaybackStore.Heartbeat checks the streaming server")
    server = "http://127.0.0.1:11470"
    script = [{ method: "GET", url: server + "/heartbeat", ok: true, status: 200, json: { success: true }, error: "" }]
    store = PlaybackStore(ScriptedTransport(script))
    alive = store.Heartbeat(server)
    dead = store.Heartbeat("")

    Harness_Ok(alive.ok, "heartbeat ok")
    Harness_Ok(alive.alive, "server alive")
    Harness_Ok(not dead.ok, "blank address refused")
end sub

' --- IsTorrent: which streams need a server that has to be ready ------------
'
' The predicate that decides whether a stream gets the readiness wait, so it has
' to agree with ResolvePlayback about the same stream. A stream carrying both a
' playable URL and a hash resolves as the URL there, and is not a torrent here.
sub Test_Playback_IsTorrentOnlyForHashes()
    Harness_Suite("PlaybackStore.IsTorrent distinguishes a server-backed torrent from a direct URL")
    store = PlaybackStore(ScriptedTransport([]))

    Harness_Ok(store.IsTorrent(TorrentStream("abc123")), "a bare infoHash is a torrent")
    Harness_Ok(not store.IsTorrent({ url: "http://direct.example/f.mp4" }), "a direct URL is not a torrent")
    Harness_Ok(store.IsTorrent({ url: "   ", infoHash: "abc123" }), "a blank URL does not make it a direct stream")
    Harness_Ok(not store.IsTorrent({ url: "http://direct.example/f.mp4", infoHash: "abc123" }), "URL wins over hash, as in ResolvePlayback")
    Harness_Ok(not store.IsTorrent(invalid), "no stream is not a torrent")
end sub

' --- WarmEngine: the requests that have to happen before the probe -----------
'
' Two of them, in this order. The HEAD gets the engine CREATED and comes back in
' milliseconds, so on its own it never said whether the engine could then answer —
' which is what left the readiness probe timing out against a server that was
' still legitimately gathering metadata. The second request is a ranged GET of
' the first 64KB, which blocks until the engine is real. The server's log for a
' device that starts cleanly shows exactly these two sitting before its /hls.m3u8.
'
' The bare route is a stream endpoint advertising a Content-Length in the
' gigabytes, so both halves of that are load-bearing: the method decides whether
' the HEAD asks for headers or tries to pull a whole feature into a string, and
' the Range header is what stops the GET from doing the same thing.
sub Test_Playback_WarmEngineSendsAHeadThenRangedGet()
    Harness_Suite("PlaybackStore.WarmEngine HEADs the bare route, then reads a byte range to wait out the engine")
    url = "http://127.0.0.1:11470/abc123/4"
    store = PlaybackStore(ScriptedTransport([
        { method: "HEAD", url: url, ok: true, status: 200, body: "", error: "" }
        { method: "GET", url: url, ok: true, status: 206, body: "", error: "" }
    ]))

    warm = store.WarmEngine(url)

    Harness_Ok(warm.ok, "warm-up ok")
    Harness_Equal(warm.status, 200, "the status that says the server answered")
    Harness_Equal(store.transport.log.Count(), 2, "exactly two requests, and in this order")
    Harness_Equal(store.transport.log[0].method, "HEAD", "the first is a HEAD, not a GET")
    Harness_Equal(store.transport.log[0].url, url, "the bare route, not the playlist")
    Harness_Equal(store.transport.log[1].method, "GET", "the second is the ranged read")
    Harness_Equal(store.transport.log[1].url, url, "against the same bare route")
    Harness_Equal(store.transport.log[1].headers.Range, "bytes=0-65535", "ranged, or it is a request to buffer a whole feature into a string")
    ' Recorded apart from `ok` rather than folded into it, because "the engine was
    ' created" and "the engine can serve" are different answers and the HEAD only
    ' ever gives the first one.
    Harness_Ok(warm.range.ok, "the range read reports the engine ready")
    Harness_Equal(warm.range.status, 206, "with the partial-content a ranged read answers with")
    ' The two budgets are the point of splitting them, so they are asserted rather
    ' than trusted: a HEAD that answers in 30-65ms must not be carrying the same
    ' cap as the request that blocks until a DHT-only engine has metadata, because
    ' one shared number is exactly how a cold engine outlived the budget meant to
    ' notice it.
    Harness_Equal(store.transport.log[0].timeoutMs, 4000, "the HEAD carries its own small budget, not the readiness one")
    Harness_Equal(store.transport.log[1].timeoutMs, 10000, "and the readiness read carries the larger one, which is the request that is supposed to wait")
end sub

' The pair is only worth printing because it can disagree. An engine that was
' created and never became ready looks identical to a healthy one if the range
' read is folded into the HEAD's ok — and the two call for opposite conclusions.
sub Test_Playback_WarmEngineRecordsAnEngineThatNeverBecameReady()
    Harness_Suite("PlaybackStore.WarmEngine keeps a created-but-not-ready engine distinguishable from a healthy one")
    url = "http://127.0.0.1:11470/abc123/4"
    store = PlaybackStore(ScriptedTransport([
        { method: "HEAD", url: url, ok: true, status: 200, body: "", error: "" }
        { method: "GET", url: url, ok: false, status: 0, body: "", error: "request timed out" }
    ]))

    warm = store.WarmEngine(url)

    Harness_Ok(warm.ok, "the HEAD still reports ok — the engine WAS created")
    Harness_Ok(not warm.range.ok, "while the range read says it never became ready")
    Harness_Equal(warm.range.error, "request timed out", "and keeps the reason that says so")
end sub

' The warm-up is an optimisation, so a server that will not answer it must be
' recorded and not raised: the probe behind it is what decides the outcome, and a
' failure here cannot be allowed to look like one.
sub Test_Playback_WarmEngineRecordsAFailureWithoutRaising()
    Harness_Suite("PlaybackStore.WarmEngine records a refusal instead of raising")
    url = "http://127.0.0.1:11470/abc123/4"
    store = PlaybackStore(ScriptedTransport([{ method: "HEAD", url: url, ok: false, status: 405, body: "", error: "HTTP 405" }]))

    warm = store.WarmEngine(url)

    Harness_Ok(not warm.ok, "not ok")
    Harness_Equal(warm.status, 405, "the status that says why")
    Harness_Equal(warm.error, "HTTP 405", "the server's own reason kept")
end sub

' An unscripted url must be recorded too. A warm-up that silently did nothing is
' the failure this change is meant to rule out.
sub Test_Playback_WarmEngineRecordsAnUnscriptedUrl()
    Harness_Suite("PlaybackStore.WarmEngine records that it asked, even when nothing answers")
    store = PlaybackStore(ScriptedTransport([]))

    warm = store.WarmEngine("http://127.0.0.1:11470/abc/0")

    Harness_Ok(not warm.ok, "not ok")
    Harness_Equal(warm.status, 0, "no status invented")
    Harness_Equal(store.transport.log.Count(), 2, "and both requests are in the log")
    Harness_Ok(warm.range <> invalid, "with the unanswered metadata read recorded rather than dropped")
end sub

sub Test_Playback_WarmEngineWithNoUrl()
    Harness_Suite("PlaybackStore.WarmEngine refuses an empty url without asking for anything")
    store = PlaybackStore(ScriptedTransport([]))

    warm = store.WarmEngine("")

    Harness_Ok(not warm.ok, "not ok")
    Harness_Equal(warm.error, "no engine url", "the reason is the missing url")
    Harness_Equal(store.transport.log.Count(), 0, "and nothing was sent")
end sub
' --- ProbePlaylist: the request the player is not asked to make --------------
'
' The body comes back as text, not parsed json: a manifest is not json, and
' through Get a perfectly good playlist would read as "invalid JSON response" —
' the one response whose text is the whole diagnosis thrown away.
sub Test_Playback_ProbePlaylistReportsStatusAndBody()
    Harness_Suite("PlaybackStore.ProbePlaylist returns the manifest text the server sent")
    server = "http://127.0.0.1:11470"
    infoHash = "0123456789abcdef0123456789abcdef01234567"
    url = server + "/" + infoHash + "/0/hls.m3u8"
    manifest = "#EXTM3U" + Chr(10) + "#EXT-X-VERSION:3" + Chr(10) + "#EXTINF:4.0," + Chr(10) + "seg1.ts" + Chr(10)
    store = PlaybackStore(ScriptedTransport([{ method: "GET", url: url, ok: true, status: 200, body: manifest, error: "" }]))

    probe = store.ProbePlaylist(url)

    Harness_Ok(probe.ok, "probe ok")
    Harness_Equal(probe.status, 200, "status reported")
    Harness_Equal(probe.body, manifest, "manifest text intact, not json-parsed away")
    Harness_Equal(store.transport.log.Count(), 1, "exactly one request, and it is logged")
    Harness_Equal(store.transport.log[0].url, url, "the playlist url is what got asked for")
end sub

' A cold engine refusing the playlist is the case this whole probe exists for,
' so the refusal has to survive into the record rather than collapsing into a
' generic failure.
sub Test_Playback_ProbePlaylistRecordsTheServersRefusal()
    Harness_Suite("PlaybackStore.ProbePlaylist reports a refusal with its status and reason")
    url = "http://127.0.0.1:11470/abc/0/hls.m3u8"
    store = PlaybackStore(ScriptedTransport([{ method: "GET", url: url, ok: false, status: 503, body: "", error: "HTTP 503" }]))

    probe = store.ProbePlaylist(url)

    Harness_Ok(not probe.ok, "probe not ok")
    Harness_Equal(probe.status, 503, "the status that says why")
    Harness_Equal(probe.error, "HTTP 503", "the server's own reason kept")
end sub

' An unscripted url must be both not-ok AND logged: a probe that silently did
' nothing would look exactly like a server that refused, and those are opposite
' bugs.
sub Test_Playback_ProbePlaylistOnAnUnscriptedUrl()
    Harness_Suite("PlaybackStore.ProbePlaylist records that it asked, even when nothing answers")
    store = PlaybackStore(ScriptedTransport([]))
    probe = store.ProbePlaylist("http://127.0.0.1:11470/abc/0/hls.m3u8")

    Harness_Ok(not probe.ok, "probe not ok")
    Harness_Equal(probe.status, 0, "no status invented")
    Harness_Equal(probe.error, "no scripted response", "the reason is the silence, not a status")
    Harness_Equal(store.transport.log.Count(), 1, "the attempt is on the record")
end sub

' A long manifest must not be allowed to fill a label and push the state
' timeline — the part being diagnosed — out of its window.
sub Test_Playback_ProbePlaylistTruncatesALongManifest()
    Harness_Suite("PlaybackStore.ProbePlaylist keeps a long manifest to a readable head")
    url = "http://127.0.0.1:11470/abc/0/hls.m3u8"
    long = "#EXTM3U"
    while Len(long) < 900
        long = long + "#EXTINF:4.0,seg.ts" + Chr(10)
    end while
    store = PlaybackStore(ScriptedTransport([{ method: "GET", url: url, ok: true, status: 200, body: long, error: "" }]))

    probe = store.ProbePlaylist(url)

    Harness_Ok(probe.ok, "probe ok")
    Harness_Equal(Len(probe.body), 400, "truncated to a readable head")
    Harness_Equal(probe.body.Left(7), "#EXTM3U", "and it is the head, not the tail")
end sub

' Streams are add-on JSON, so their fields can be the wrong type too. A `url`
' that is not text is no direct link and an `infoHash` that is not text is no
' hash: both fall through to the answers a missing field gets, instead of a
' string method (Trim/ToStr) being called on a raw value and throwing out of the
' play handler.
sub Test_Playback_NonTextStreamFields()
    Harness_Suite("PlaybackStore treats non-text stream fields as absent")
    store = PlaybackStore(ScriptedTransport([]))

    Harness_Equal(store.StreamInfoHash({ infoHash: 1234 }), "", "numeric infoHash is no hash")
    Harness_Equal(store.StreamInfoHash({ infoHash: ["abc"] }), "", "container infoHash is no hash")
    Harness_Equal(store.StreamInfoHash({ infoHash: "abc123" }), "abc123", "text infoHash passes through")

    Harness_Ok(store.IsTorrent({ url: 42, infoHash: "abc123" }), "a numeric url does not make it a direct stream")
    Harness_Ok(not store.IsTorrent({ url: 42 }), "a numeric url with no hash is not a torrent")

    direct = store.ResolvePlayback("http://127.0.0.1:11470", { url: 42, infoHash: "abc123" })
    Harness_Ok(direct.ok, "resolve falls through to the torrent route")
    Harness_Equal(direct.url, "http://127.0.0.1:11470/abc123/-1/hls.m3u8", "torrent URL built instead")
end sub

' --- the codec-hint route ---------------------------------------------------
'
' A device profile turns the URL into the streaming server's own HLS2 converter
' route, reached directly so the advertised codec lists and the channel cap can
' ride the query. The legacy /hls.m3u8 URL is still built — it is what the
' resolve falls back to when the server predates /hlsv2 — so every assertion
' below pins BOTH halves.

' A profile shaped the way StreamResolveTask builds one.
function CodecProfile(videoCodecs as object, audioCodecs as object, maxAudioChannels as integer) as object
    return {
        videoCodecs: videoCodecs
        audioCodecs: audioCodecs
        maxAudioChannels: maxAudioChannels
        fingerprint: CodecFingerprint(videoCodecs, audioCodecs, maxAudioChannels)
    }
end function

sub Test_Playback_CodecProfileBuildsTheHlsV2Url()
    Harness_Suite("PlaybackStore.ResolvePlayback builds the hinted HLS2 URL")
    server = "http://127.0.0.1:11470"
    infoHash = "0123456789abcdef0123456789abcdef01234567"
    profile = CodecProfile(["h264", "hevc"], ["aac", "mp3"], 2)
    store = PlaybackStore(ScriptedTransport([]))

    result = store.ResolvePlayback(server, TorrentStream(infoHash, 3), 0, 0, profile)

    Harness_Ok(result.ok, "resolves")
    Harness_Equal(store.transport.log.Count(), 0, "still no request made at all")
    Harness_Equal(result.url, server + "/hlsv2/" + infoHash + "-3-vh264-hevc.aaac-mp3.c2/master.m3u8" + "?mediaURL=http%3A%2F%2F127.0.0.1%3A11470%2F" + infoHash + "%2F3" + "&videoCodecs=h264&videoCodecs=hevc" + "&audioCodecs=aac&audioCodecs=mp3" + "&maxAudioChannels=2", "the whole hinted URL, repeated keys and all")
    Harness_Equal(result.fallbackUrl, server + "/" + infoHash + "/3/hls.m3u8", "the legacy URL is kept as the fallback")
    Harness_Equal(result.streamFormat, "hls", "the format is still read off the manifest URL")
end sub

' The hint lists REPLACE the server's defaults, so a single comma-joined value
' would arrive as one string and advertise nothing. The keys must repeat.
sub Test_Playback_CodecProfileRepeatsEveryCodecKey()
    Harness_Suite("PlaybackStore repeats one query key per advertised codec")
    store = PlaybackStore(ScriptedTransport([]))
    profile = CodecProfile(["h264", "hevc"], ["aac", "mp3"], 2)

    url = store.ResolvePlayback("http://127.0.0.1:11470", TorrentStream("abc123", 0), 0, 0, profile).url

    Harness_Equal(Hints_Count(url, "videoCodecs="), 2, "two video keys")
    Harness_Equal(Hints_Count(url, "audioCodecs="), 2, "two audio keys")
    Harness_Equal(Hints_Count(url, "maxAudioChannels="), 1, "one channel key")
    Harness_Equal(Hints_Count(url, "mediaURL="), 1, "one media url key")
    Harness_Ok(url.InStr("videoCodecs=h264,hevc") < 0, "never one comma-joined value")
end sub

' The mediaURL is the server's own loopback address, not the LAN address the
' client was handed: the server fetches the torrent from ITSELF while remuxing.
sub Test_Playback_CodecProfilePointsMediaUrlAtLoopback()
    Harness_Suite("PlaybackStore points mediaURL at the server's loopback")
    store = PlaybackStore(ScriptedTransport([]))
    profile = CodecProfile(["h264"], ["aac"], 2)

    url = store.ResolvePlayback("http://192.168.1.50:11470", TorrentStream("abc123", 7), 0, 0, profile).url

    queryAt = url.InStr("?")
    query = url.Mid(queryAt + 1)
    Harness_Ok(url.InStr("mediaURL=http%3A%2F%2F127.0.0.1%3A11470%2Fabc123%2F7") > 0, "loopback host and the client's port")
    Harness_Ok(query.InStr("192.168.1.50") < 0, "the LAN address never appears in the query")
    Harness_Equal(url.Left(26), "http://192.168.1.50:11470/", "the request itself still goes to the LAN address")
end sub

sub Test_Playback_CodecProfileCarriesTheFiltersLast()
    Harness_Suite("PlaybackStore appends the file filters after the codec hints")
    store = PlaybackStore(ScriptedTransport([]))
    profile = CodecProfile(["h264"], ["aac"], 2)

    url = store.ResolvePlayback("http://127.0.0.1:11470", TorrentStream("abc123", 0), 2, 5, profile).url

    Harness_Ok(url.InStr("&maxAudioChannels=2&f=episode%3A%205&f=season%3A%202") > 0, "f= parameters follow the hints")
end sub

' The converter is cached by id, so a changed profile MUST change the id or the
' server answers with the converter built from the old hints.
sub Test_Playback_CodecProfileChangesTheConverterId()
    Harness_Suite("PlaybackStore changes the converter id with the profile")
    store = PlaybackStore(ScriptedTransport([]))
    stream = TorrentStream("abc123", 1)

    quiet = store.ResolvePlayback("http://127.0.0.1:11470", stream, 0, 0, CodecProfile(["h264"], ["aac"], 2)).url
    loud = store.ResolvePlayback("http://127.0.0.1:11470", stream, 0, 0, CodecProfile(["h264", "hevc"], ["aac", "mp3"], 2)).url

    Harness_Ok(quiet.InStr("/hlsv2/abc123-1-vh264.aaac.c2/") > 0, "the quiet profile names itself in the id")
    Harness_Ok(loud.InStr("/hlsv2/abc123-1-vh264-hevc.aaac-mp3.c2/") > 0, "the loud profile names itself in the id")
    Harness_Ok(quiet <> loud, "the two profiles do not share an id")
end sub

' No profile is the test path and the un-probed path: the legacy URL is both the
' answer and the fallback, so there is nothing to fall back FROM.
sub Test_Playback_NoProfileKeepsTheLegacyUrl()
    Harness_Suite("PlaybackStore keeps the legacy URL without a profile")
    server = "http://127.0.0.1:11470"
    store = PlaybackStore(ScriptedTransport([]))

    result = store.ResolvePlayback(server, TorrentStream("abc123", 3))

    Harness_Equal(result.url, server + "/abc123/3/hls.m3u8", "legacy URL")
    Harness_Equal(result.fallbackUrl, "", "no fallback to fall back to")
end sub

' A profile missing a piece cannot build a request, and must degrade to the
' legacy URL rather than send a hint-less /hlsv2 URL the server would reject.
sub Test_Playback_IncompleteProfileFallsBackToLegacy()
    Harness_Suite("PlaybackStore refuses an incomplete profile")
    server = "http://127.0.0.1:11470"
    store = PlaybackStore(ScriptedTransport([]))

    noVideo = store.ResolvePlayback(server, TorrentStream("abc123", 3), 0, 0, { audioCodecs: ["aac"], maxAudioChannels: 2, fingerprint: "x" })
    Harness_Equal(noVideo.url, server + "/abc123/3/hls.m3u8", "a profile with no video list is not used")
    Harness_Equal(noVideo.fallbackUrl, "", "and carries no fallback")

    badChannels = store.ResolvePlayback(server, TorrentStream("abc123", 3), 0, 0, { videoCodecs: ["h264"], audioCodecs: ["aac"], maxAudioChannels: 0, fingerprint: "x" })
    Harness_Equal(badChannels.url, server + "/abc123/3/hls.m3u8", "a zero channel cap is not a request")

    noPrint = store.ResolvePlayback(server, TorrentStream("abc123", 3), 0, 0, { videoCodecs: ["h264"], audioCodecs: ["aac"], maxAudioChannels: 2 })
    Harness_Equal(noPrint.url, server + "/abc123/3/hls.m3u8", "a profile with no fingerprint cannot name a converter")
end sub

' The loopback base is built from the port the client was handed, and degrades to
' the address itself when it names no port rather than inventing one.
sub Test_Playback_LoopbackMediaBaseReadsThePort()
    Harness_Suite("PlaybackStore reads the streaming server's port back")
    store = PlaybackStore(ScriptedTransport([]))

    Harness_Equal(store.LoopbackMediaBase("http://192.168.1.50:11470"), "http://127.0.0.1:11470", "scheme and host are replaced, the port is kept")
    Harness_Equal(store.LoopbackMediaBase("https://box.example:443/"), "http://127.0.0.1:443", "always http, and a trailing slash is not a port or a path")
    Harness_Equal(store.LoopbackMediaBase("http://streamer.local"), "http://streamer.local", "a portless address falls back to itself")
    ' An IPv6 literal's colons are not a port, and there is no bracket parsing
    ' here to tell them apart — so the address is left whole rather than cut at a
    ' colon. [::1] is loopback anyway, and the Roku is handed an IPv4 host in
    ' every realistic setup.
    Harness_Equal(store.LoopbackMediaBase("http://[::1]:11470"), "http://[::1]:11470", "an IPv6 literal is left whole, not cut at a colon")
end sub

sub Test_Playback_ProbeServerMediaAsksTheHlsV2Probe()
    Harness_Suite("PlaybackStore probes the server's media report")
    server = "http://192.168.1.50:11470"
    probeUrl = server + "/hlsv2/probe?mediaURL=http%3A%2F%2F127.0.0.1%3A11470%2Fabc123%2F3"
    media = { format: "matroska,webm", streams: [
        { codec_type: "video", codec_name: "hevc" },
        { codec_type: "audio", codec_name: "aac" }
    ] }
    store = PlaybackStore(ScriptedTransport([
        { method: "GET", url: probeUrl, ok: true, status: 200, json: media, error: "" }
    ]))

    result = store.ProbeServerMedia(server, "abc123", 3)

    Harness_Ok(result.ok, "a scripted probe answers ok")
    Harness_Equal(result.status, 200, "status carried back")
    Harness_Equal(result.format, "matroska,webm", "format carried back")
    Harness_Equal(result.streams.Count(), 2, "streams carried back")
    Harness_Equal(store.transport.log.Count(), 1, "one request made")
    Harness_Equal(store.transport.log[0].url, probeUrl, "the hlsv2 probe with the loopback mediaURL")
end sub

sub Test_Playback_ProbeServerMediaFailureIsNotFatal()
    Harness_Suite("PlaybackStore media probe failure stays a failure record")
    server = "http://127.0.0.1:11470"

    refused = PlaybackStore(ScriptedTransport([])).ProbeServerMedia(server, "abc123", 0)
    Harness_Ok(not refused.ok, "an unscripted probe answers not ok")
    Harness_Equal(refused.streams.Count(), 0, "and carries no streams")

    missing = PlaybackStore(ScriptedTransport([])).ProbeServerMedia("", "abc123", 0)
    Harness_Ok(not missing.ok, "no server address is not probed")

    noHash = PlaybackStore(ScriptedTransport([])).ProbeServerMedia(server, "", 0)
    Harness_Ok(not noHash.ok, "no infoHash is not probed")
end sub

' A timeout (status 0) is the one failure worth asking again: ffprobe reads
' through the torrent engine, and a slow first read can succeed on a second
' ask. An HTTP answer is final and must not be retried.
sub Test_Playback_ProbeServerMediaRetriesTimeoutsOnly()
    Harness_Suite("PlaybackStore media probe retries timeouts")
    server = "http://127.0.0.1:11470"
    probeUrl = server + "/hlsv2/probe?mediaURL=http%3A%2F%2F127.0.0.1%3A11470%2Fabc123%2F0"

    timedOut = PlaybackStore(ScriptedTransport([])).ProbeServerMedia(server, "abc123", 0)
    Harness_Ok(not timedOut.ok, "a probe that keeps timing out still answers not ok")
    Harness_Equal(timedOut.attempts, 3, "and was asked three times")
    Harness_Equal(timedOut.status, 0, "the last timeout is the status")

    refused = PlaybackStore(ScriptedTransport([
        { method: "GET", url: probeUrl, ok: false, status: 404, json: invalid, error: "HTTP 404" }
    ])).ProbeServerMedia(server, "abc123", 0)
    Harness_Ok(not refused.ok, "a 404 answers not ok")
    Harness_Equal(refused.attempts, 1, "and was asked only once — a refusal is not a timeout")
end sub

' Counts the occurrences of a literal key in a string. Local so the assertions
' above do not have to know where in the URL a key sits.
function Hints_Count(text as string, key as string) as integer
    count = 0
    at = text.InStr(key)
    while at >= 0
        count = count + 1
        at = text.InStr(at + key.Len(), key)
    end while
    return count
end function
