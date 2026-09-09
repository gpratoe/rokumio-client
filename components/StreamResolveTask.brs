' StreamResolveTask — resolve a torrent stream to a playable URL off the UI
' thread. Direct-URL streams never get here (the screen plays them as-is); a
' torrent stream is created on the streaming server first, and the create call
' can park in Wait for the full long timeout while a cold engine gathers DHT /
' tracker metadata. The task owns its own store + transport instances inside
' the task scope, so the blocking wait stays on the worker thread and the
' screen keeps rendering and answering keys.
sub init()
    m.top.functionName = "resolve"
end sub

sub resolve()
    print "[rokumio] StreamResolveTask starting"
    try
        http = Transport(CreateSyncHttpClient())
        store = PlaybackStore(http)
        resolved = store.ResolvePlayback(m.top.serverAddress, m.top.stream)
        print "[rokumio] StreamResolveTask infoHash='" + store.StreamInfoHash(m.top.stream) + "' -> ok=" + resolved.ok.ToStr() + " url='" + resolved.url + "' error='" + resolved.error + "'"
        m.top.result = resolved
    catch e
        print "[rokumio] StreamResolveTask error: " + e.message
        m.top.result = { ok: false, url: "", error: e.message }
    end try
end sub
