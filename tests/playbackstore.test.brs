' PlaybackStore unit tests.
'
' Streams() talks to an add-on through the scripted transport; CreateSession
' POSTs to the streaming-server create endpoint and asserts the request + log;
' PlaybackUrl/ResolvePlayback are pure middle (> a transport script the
' torrent path needs).

function TorrentStream(infoHash as string, fileIdx = invalid as dynamic) as object
    stream = { infoHash: infoHash }
    if fileIdx <> invalid then stream.fileIdx = fileIdx
    return stream
end function

sub Test_Playback_Streams()
    Harness_Suite("PlaybackStore.Streams fetches the add-on stream list")
    address = "https://torrentio.strem.fun"
    script = [
        {
            method: "GET"
            url: address + "/stream/movie/tt0133093.json"
            ok: true
            status: 200
            json: {
                streams: [
                    { name: "Mock Torrent", infoHash: "abc123", fileIdx: 1 }
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

sub Test_Playback_CreateSessionForwardsFileIdx()
    Harness_Suite("PlaybackStore.CreateSession POSTs the stream fileIdx hint")
    server = "http://127.0.0.1:11470"
    infoHash = "0123456789abcdef0123456789abcdef01234567"
    script = [
        {
            method: "POST"
            url: server + "/" + infoHash + "/create"
            ok: true
            status: 200
            json: { files: [{ idx: 7 }, { idx: 9 }], guessedFileIdx: 7 }
            error: ""
        }
    ]
    store = PlaybackStore(ScriptedTransport(script))
    session = store.CreateSession(server, TorrentStream(infoHash, 7))

    Harness_Ok(session.ok, "session created")
    Harness_Equal(store.transport.log.Count(), 1, "one request logged")
    Harness_Equal(store.transport.log[0].method, "POST", "create is a POST")
    Harness_Equal(store.transport.log[0].body.guessFileIdx, 7, "fileIdx hint forwarded in body")
    Harness_Equal(session.fileIdx, 7, "guessedFileIdx surfaced")
    Harness_Equal(session.files.Count(), 2, "file list surfaced")
end sub

sub Test_Playback_TorrentResolvesThroughServer()
    Harness_Suite("PlaybackStore.ResolvePlayback creates a torrent then serves HLS")
    server = "http://127.0.0.1:11470"
    infoHash = "0123456789abcdef0123456789abcdef01234567"
    script = [
        {
            method: "POST"
            url: server + "/" + infoHash + "/create"
            ok: true
            status: 200
            json: { files: [], guessedFileIdx: 2 }
            error: ""
        }
    ]
    store = PlaybackStore(ScriptedTransport(script))
    result = store.ResolvePlayback(server, TorrentStream(infoHash))

    Harness_Ok(result.ok, "torrent resolves")
    Harness_Equal(result.url, server + "/" + infoHash + "/2/hls.m3u8", "HLS master url")
end sub

sub Test_Playback_CreateSessionLargestVideoWhenGuessedMissing()
    Harness_Suite("PlaybackStore.CreateSession picks the largest video file when guessedFileIdx is absent")
    server = "http://127.0.0.1:11470"
    infoHash = "0123456789abcdef0123456789abcdef01234567"
    script = [
        {
            method: "POST"
            url: server + "/" + infoHash + "/create"
            ok: true
            status: 200
            json: {
                files: [
                    { name: "Episode 1.mkv", length: 1048576 }
                    { name: "sample.mp4", length: 10485760 }
                ]
                guessedFileIdx: invalid
            }
            error: ""
        }
    ]
    store = PlaybackStore(ScriptedTransport(script))
    session = store.CreateSession(server, TorrentStream(infoHash))

    Harness_Ok(session.ok, "session created despite no guessedFileIdx")
    Harness_Equal(session.fileIdx, 1, "largest video file chosen")
    Harness_Equal(session.files.Count(), 2, "file list surfaced")
end sub

sub Test_Playback_CreateSessionNamesServerKeysWhenNothingPicked()
    Harness_Suite("PlaybackStore.CreateSession reports the server keys when no file can be picked")
    server = "http://127.0.0.1:11470"
    infoHash = "0123456789abcdef0123456789abcdef01234567"
    script = [
        {
            method: "POST"
            url: server + "/" + infoHash + "/create"
            ok: true
            status: 200
            json: { files: [], guessedFileIdx: invalid }
            error: ""
        }
    ]
    store = PlaybackStore(ScriptedTransport(script))
    session = store.CreateSession(server, TorrentStream(infoHash))

    Harness_Ok(not session.ok, "session refused")
    Harness_Ok(session.error.InStr("guessedFileIdx") >= 0, "error names guessedFileIdx")
    Harness_Ok(session.error.InStr("files") >= 0, "error names the returned keys")
end sub

sub Test_Playback_TorrentWithoutServerAddress()
    Harness_Suite("PlaybackStore.ResolvePlayback refuses a torrent with no server")
    store = PlaybackStore(ScriptedTransport([]))
    result = store.ResolvePlayback("", { infoHash: "abc123" })

    Harness_Ok(not result.ok, "resolved refused")
    Harness_Equal(result.error, "no streaming server address", "error names the missing server")
end sub

sub Test_Playback_PlaybackUrl()
    Harness_Suite("PlaybackStore.PlaybackUrl builds the master HLS url")
    store = PlaybackStore(ScriptedTransport([]))
    Harness_Equal(
        store.PlaybackUrl("http://127.0.0.1:11470", "abc123", 4),
        "http://127.0.0.1:11470/abc123/4/hls.m3u8",
        "master HLS url"
    )
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