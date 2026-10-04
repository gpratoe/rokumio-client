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
