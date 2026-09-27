' StreamResolveTask — resolve a torrent stream to a playable URL off the UI
' thread, and make sure the streaming server will actually serve it.
'
' Direct-URL streams never get here (the screen plays them as-is).
'
' The task owns the wait, and that is the point of it. Building the URL needs no
' request, but the Video node's first request is a cold engine: the server has to
' gather metadata over DHT and trackers before it can answer, and the node's load
' patience is far shorter than ours. A node that cannot load in time reports the
' stream as FINISHED — no error, no message, the buffering indicator simply goes
' away — which is why a first play can die instantly while a second play of the
' same title gets partway, having found the engine already warm.
'
' So the playlist is asked for here, on a worker thread, until the server will
' serve one. The URL is handed over either way when the attempts run out, which
' makes this a floor on how long the player waits and never a reason it cannot
' start: the worst case is today's behaviour plus a delay.
'
' The probe rides back attached to the result. "How many times was it asked, and
' what did the server say" is the diagnosis if it is still wrong, which is the
' whole reason this file keeps a record instead of only waiting.
'
' The wait policy lives here rather than in PlaybackStore on purpose. Wait()
' aborts the brs interpreter's run and Ticks() does not exist in it, so a wait
' loop in store code would be neither exercised by the suite nor timed; the task
' is the one place whose blocking is expected.

' The wait is bounded by a COUNT of attempts, never by a clock reading. An earlier
' version measured elapsed milliseconds through
' CreateObject("roDateTime").AsMilliseconds() — a method this codebase has never
' put on a device; the only two it does use are ToISOString() and GetYear() — and
' the device answered &hf4, member function not found. Because the throw landed
' inside resolve()'s own try it took the result down with it: a URL that had
' already resolved correctly was thrown away, and every torrent reported "resolve
' FAILED: Member function not found" while direct URLs, which skip this file's
' wait entirely, played fine. Counting attempts needs no platform API at all, and
' a request that stalls ends at the probe's own short timeout rather than at a
' deadline somebody has to poll.

sub init()
    m.top.functionName = "resolve"
end sub

sub resolve()
    try
        http = Transport()
        store = PlaybackStore(http)
        resolved = store.ResolvePlayback(m.top.serverAddress, m.top.stream, m.top.season, m.top.episode)
        ' The probe gets its own try, and this is the other half of the fix
        ' described above. It is a diagnostic: its job is to ADD what is known,
        ' and a throw in here must not be able to remove the answer. Sharing the
        ' catch below meant any fault in the wait loop reported as a failed
        ' resolve, which is worse than having no probe at all — it looks like a
        ' server refusing a stream it was never asked about.
        if resolved.ok and store.IsTorrent(m.top.stream) then
            try
                resolved.probe = WaitForPlaylist(store, resolved.url)
            catch e
                resolved.probe = {
                    ok: false
                    status: 0
                    attempts: 0
                    firstError: e.message
                    body: ""
                    gaveUp: true
                }
            end try
        end if
        m.top.result = resolved
    catch e
        m.top.result = { ok: false, url: "", error: e.message }
    end try
end sub

' Ask the streaming server for the playlist until it will serve one or the
' attempts run out, and report the whole attempt: { ok, status, attempts,
' firstError, body, gaveUp }.
'
' No elapsed time is recorded because none is measured: the bound is six
' attempts with a pause between, and a stalled request is cut off by the probe's
' short timeout rather than by a deadline. `gaveUp` is set from the loop's own
' exit rather than inferred by the reader.
function WaitForPlaylist(store as object, url as string) as object
    probe = {
        ok: false
        status: 0
        attempts: 0
        firstError: ""
        body: ""
        gaveUp: false
    }
    ' The count is a literal rather than a computed bound so the ceiling is
    ' readable in one place. It is also only ever a floor on how long the player
    ' waits, never a reason it cannot start: the URL is handed over either way.
    for attempt = 1 to 6
        probe.attempts = attempt
        answer = store.ProbePlaylist(url)
        probe.status = answer.status
        probe.body = answer.body
        if answer.ok
            probe.ok = true
            exit for
        end if
        if probe.firstError = "" then probe.firstError = answer.error
        ' Interval: 4s. Long enough not to hammer a server still starting an
        ' engine, short enough that a warm one is noticed within one poll. Two
        ' arguments because that is the signature BrighterScript checks against
        ' (BS1002); an invalid port is Roku's own one-argument Wait. Skipped on
        ' the last attempt, where it would only be a pause before giving up.
        if attempt < 6 then Wait(4000, invalid)
    end for
    if not probe.ok then probe.gaveUp = true
    return probe
end function
