' PlayerScreen — minimal video playback for a stream handed over by StreamsScreen.
'
' StreamsScreen pushes { stream, serverAddress, … } and playback resolution
' (ResolvePlayback) happens HERE, not on the picker: ResolvePlayback passes a
' direct URL through as-is and creates a torrent engine on the streaming server
' (up to the 120s long timeout on a cold engine) off the render thread. While it
' waits the media logo beats from transparent to solid (the Stremio pre-buffer
' pulse); on success the video starts, on failure the player stays with the
' Stremio wording and Back returns to the stream list.
'
' Tracks position, and on Back (or exit) records where the user stopped through
' LibraryStore.SetPosition so Continue Watching / Resume can pick it up. Leaving
' during the resolve phase never saves — hasPlayed guards the write. Resume
' positions are stored in seconds and carried into the content node's playStart
' field; playback state is surfaced through the status label so a broken stream
' is a message, not a black screen.
'
' Transport is entirely this screen's own because the Video runs with
' enableUI=false — the platform never draws a pause screen or trick-play
' timeline. OK and the play/pause buttons all toggle playback, Left/Right step
' ±10s and FF/RW ±30s, and the custom bottom bar shows progress. The bar hides
' after a few seconds of playing but stays up while paused/error.
'
' Params: { stream, serverAddress, metaType, metaId, videoId, season, episode,
'           position, name, poster, logo }.

sub init()
    m.videoSurface = m.top.FindNode("videoSurface")
    m.status = m.top.FindNode("playerStatus")
    m.overlay = m.top.FindNode("playerOverlay")
    m.title = m.top.FindNode("overlayTitle")
    m.playButton = m.top.FindNode("playButton")
    m.fill = m.top.FindNode("progressFill")
    m.timeLabel = m.top.FindNode("timeLabel")
    m.seekToast = m.top.FindNode("seekToast")
    m.seekToastText = m.top.FindNode("seekToastText")
    m.hideTimer = m.top.FindNode("overlayHideTimer")
    m.toastTimer = m.top.FindNode("toastHideTimer")
    m.bufferingGroup = m.top.FindNode("bufferingGroup")
    m.logoBack = m.top.FindNode("logoBack")
    m.logoFront = m.top.FindNode("logoFront")
    m.resolvePulse = m.top.FindNode("resolvePulse")

    m.hideTimer.ObserveField("fire", "onOverlayHideTimerFire")
    m.toastTimer.ObserveField("fire", "onToastHideTimerFire")
    m.stopWatchdog = m.top.FindNode("stopWatchdog")
    m.stopWatchdog.ObserveField("fire", "onStopWatchdogFire")
    m.pendingStop = false
    m.seekPending = 0
    m.resolveTask = invalid
end sub

function SetStores(stores as object) as void
    m.stores = stores
end function

function OnEnter(params as object) as void
    if params = invalid or params.stream = invalid then return
    m.playParams = params
    m.saved = false
    m.hasPlayed = false

    title = params.name
    if title = invalid then title = ""
    m.title.text = title

    ' The pre-buffer pulse (logo beating transparent to solid, Stremio-style)
    ' only has something to show when a logo URL is available; otherwise the
    ' bare screen waits out the resolve. No status label here — the pulse IS
    ' the indicator.
    logo = params.logo
    if logo = invalid or logo = "" then logo = params.poster
    if logo <> invalid and logo <> ""
        m.logoBack.uri = logo
        m.logoFront.uri = logo
        m.bufferingGroup.visible = true
        StartResolvePulse()
    else
        m.bufferingGroup.visible = false
    end if

    StartResolve(params.stream, params.serverAddress)
end function

' Kick the stream resolution off the render thread. The task frees the UI as the
' create/torrent warm-up parks (up to the long timeout); a direct URL resolves
' instantly through the same path.
sub StartResolve(stream as object, serverAddress as dynamic)
    if stream = invalid then
        m.status.text = "This source is poorly available or your internet connection is not fast enough."
        return
    end if
    if serverAddress = invalid then serverAddress = ""
    task = CreateObject("roSGNode", "StreamResolveTask")
    task.id = "playerResolve"
    m.top.AppendChild(task)
    task.stream = stream
    task.serverAddress = serverAddress
    task.observeField("result", "onResolveResult")
    m.resolveTask = task
    task.control = "RUN"
end sub

sub StartResolvePulse()
    if m.resolvePulse = invalid then return
    ' The pulse is logoBack alone — the front (reveal) copy is hidden so it can't
    ' sit solid on top and mask the beat. StopResolvePulse brings it back for the
    ' buffering fill.
    if m.logoFront <> invalid then m.logoFront.visible = false
    m.resolvePulse.control = "stop"
    m.resolvePulse.control = "start"
end sub

' Freeze the pulse and restore the resting buffering pose: the back returns to
' its faint opacity (0.22), the solid front is back on top but fully clipped so
' it is "not shown" yet — onBufferingStatusChanged reveals it from the left as
' buffering % arrives.
sub StopResolvePulse()
    if m.resolvePulse <> invalid then m.resolvePulse.control = "stop"
    if m.logoFront <> invalid
        m.logoFront.visible = true
        m.logoFront.clippingRect = [0, 0, 0, 506]
    end if
    if m.logoBack <> invalid then m.logoBack.opacity = 0.22
end sub

' The resolve finished. Success starts playback; a failure (e.g. "request timed
' out") stays on the player with the Stremio wording and Back returns to the
' stream list. Results that land after a Back-out are dropped by the
' m.resolveTask guard.
sub onResolveResult()
    if m.resolveTask = invalid then return
    task = m.resolveTask
    m.resolveTask = invalid
    result = task.result
    task.unobserveField("result")
    if task.getParent() <> invalid then m.top.RemoveChild(task)

    StopResolvePulse()

    if result = invalid or not result.ok or result.url = invalid or result.url = ""
        m.status.text = "This source is poorly available or your internet connection is not fast enough."
        return
    end if
    StartPlayback(result.url)
end sub

sub CancelResolve()
    if m.resolveTask <> invalid
        m.resolveTask.unobserveField("result")
        m.resolveTask.control = "STOP"
        if m.resolveTask.getParent() <> invalid then m.top.RemoveChild(m.resolveTask)
        m.resolveTask = invalid
    end if
    StopResolvePulse()
end sub

' The Video node is a per-play instance: created fresh on every enter and torn
' down on exit, because a reused node refuses to abandon a stream once playback
' has begun (content swaps and control="stop" are ignored mid-buffer) — on top
' of that, a still-running player keeps decoding/downloading invisibly after the
' screen is gone. A from-scratch node each play guarantees a clean player and
' silence on exit, at no cost beyond node creation. Only created once the stream
' has resolved to a URL.
sub CreateVideo()
    m.video = CreateObject("roSGNode", "Video")
    m.video.width = 1920
    m.video.height = 1080
    m.video.enableUI = false
    m.video.enableTrickPlay = false
    m.videoSurface.AppendChild(m.video)

    m.video.ObserveField("state", "onVideoStateChanged")
    m.video.ObserveField("position", "onPositionChanged")
    m.video.ObserveField("duration", "refreshOverlay")
    m.video.ObserveField("bufferingStatus", "onBufferingStatusChanged")
end sub

' The resolved URL is the only thing that ever touches the Video node: build the
' content (title, resume offset, sniffed stream format), then play.
sub StartPlayback(url as string)
    CreateVideo()

    content = CreateObject("roSGNode", "ContentNode")
    content.url = url
    params = m.playParams
    title = params.name
    if title = invalid then title = ""
    content.title = title
    startOffset = 0
    if params.position <> invalid and params.position > 0 then startOffset = params.position
    if startOffset > 0 then content.playStart = startOffset
    streamFormat = DetectStreamFormat(url)
    if streamFormat <> "" then content.streamFormat = streamFormat

    print "[rokumio] PlayerScreen url='" + url + "' format='" + streamFormat + "' playStart=" + startOffset.ToStr()

    m.video.enablePositionTracking = true
    m.video.content = content
    m.video.SetFocus(true)
    m.video.control = "play"
    m.playButton.uri = "pkg:/images/icon_pause.png"
    ShowOverlay()
end sub

' The stream format has to be told to the Video node — Roku does not reliably
' sniff media from a bare contentUri, and a format-less HLS manifest is the
' classic black-screen-with-title failure.
function DetectStreamFormat(url as string) as string
    cleanUrl = LCase(url.Trim())
    queryIndex = cleanUrl.InStr("?")
    if queryIndex > 0 then cleanUrl = cleanUrl.Left(queryIndex - 1)
    if cleanUrl.Right(5) = ".m3u8" then return "hls"
    if cleanUrl.Right(4) = ".mpd" then return "dash"
    if cleanUrl.Right(4) = ".mkv" then return "mkv"
    if cleanUrl.Right(4) = ".mp4" or cleanUrl.Right(4) = ".m4v" then return "mp4"
    return ""
end function

' Surface playback state on the status line and drive the play/pause icon: a
' broken stream is a message, not a silent black frame. The overlay hides on
' finished/stopped but otherwise follows the hide timer.
sub onVideoStateChanged()
    if m.video = invalid then return
    state = m.video.state
    print "[rokumio] PlayerScreen state='" + state.ToStr() + "'"
    if state = invalid then return
    if m.pendingStop
        ' Waiting on an asynchronous stop (see RequestStopAndWait): the player is
        ' only released once the OS reports a terminal state — Roku runs the
        ' media player outside the node, so tearing the node down mid-stop lets
        ' the buffered stream start outputting audio anyway. "stopping" (OS 12.5+
        ' while asyncStopSemantics is on) still counts as in-progress.
        if state = "stopped" or state = "finished" or state = "error"
            print "[rokumio] PlayerScreen stop confirmed, tearing down"
            m.pendingStop = false
            TeardownVideo()
            FireCloseRequest()
        end if
        return
    end if
    if state = "playing"
        m.hasPlayed = true
        m.status.text = ""
        m.playButton.uri = "pkg:/images/icon_pause.png"
        HideBuffering()
        restartHideTimer()
    else if state = "paused"
        m.playButton.uri = "pkg:/images/icon_play.png"
    else if state = "error"
        m.status.text = "Playback failed: check the stream and server."
        m.playButton.uri = "pkg:/images/icon_play.png"
        HideBuffering()
    else if state = "buffering"
        StopResolvePulse()
        if HasLogo() then m.bufferingGroup.visible = true
    else if state = "finished" or state = "stopped"
        m.overlay.visible = false
        HideBuffering()
    end if
    refreshOverlay()
end sub

' All transport keys land here while a video exists. OK/Play/Pause/Replay all
' mean the same thing (toggle), so there is no state where a press does
' something unexpected; Left/Right and FF/RW seek immediately. Before the stream
' resolves (or after a failure) there is no video: Back still pops (OnBackPressed
' returns false) and every other key is swallowed so a press routes nowhere else.
' Everything else falls through (Back reaches the stack → stop + save + pop).
function OnKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if m.video = invalid
        if key = "back" then return false
        return true
    end if
    ' Mid-teardown: every key is swallowed until the player actually reports
    ' "stopped" (see RequestStopAndWait) so nothing can interrupt the stop.
    if m.pendingStop then return true
    if key = "OK" or key = "play" or key = "pause" or key = "replay"
        togglePlayPause()
        return true
    end if
    if key = "left" or key = "right"
        if key = "left" then seekBy(-10) else seekBy(10)
        return true
    end if
    if key = "fastforward" or key = "rewind"
        if key = "rewind" then seekBy(-30) else seekBy(30)
        return true
    end if
    return false
end function

sub togglePlayPause()
    state = m.video.state
    if state = "paused"
        m.video.control = "resume"
        m.playButton.uri = "pkg:/images/icon_pause.png"
        print "[rokumio] PlayerScreen toggle -> resume (state=" + state.ToStr() + ")"
    else if state = "playing"
        m.video.control = "pause"
        m.playButton.uri = "pkg:/images/icon_play.png"
        print "[rokumio] PlayerScreen toggle -> pause (state=" + state.ToStr() + ")"
    else
        m.video.control = "play"
        m.playButton.uri = "pkg:/images/icon_pause.png"
        print "[rokumio] PlayerScreen toggle -> play (state=" + state.ToStr() + ")"
    end if
    ShowOverlay()
end sub

sub seekBy(seconds as integer)
    duration = m.video.duration
    position = m.video.position
    if position = invalid then position = 0
    if m.seekPending = invalid then m.seekPending = 0
    m.seekPending = m.seekPending + seconds
    target = position + m.seekPending
    if duration <> invalid and duration > 0 and target > duration then target = duration
    if target < 0 then target = 0
    m.video.seek = target
    print "[rokumio] PlayerScreen seek " + seconds.ToStr() + "s -> " + target.ToStr() + " (pending=" + m.seekPending.ToStr() + ")"
    ShowOverlay()
    UpdateProgress(target, duration)
    ShowSeekToast(target)
end sub

' A real playback-progress event means the last seek has landed and the video is
' moving again; the next press starts a fresh accumulation instead of stacking on
' a position that has not caught up yet.
sub onPositionChanged()
    if m.video = invalid then return
    m.seekPending = 0
    refreshOverlay()
end sub

sub ShowSeekToast(target as integer)
    if m.seekToast = invalid then return
    m.seekToastText.text = FormatTime(target)
    m.seekToast.visible = true
    m.toastTimer.control = "stop"
    m.toastTimer.control = "start"
end sub

sub onToastHideTimerFire()
    if m.seekToast <> invalid then m.seekToast.visible = false
end sub

sub ShowOverlay()
    if m.overlay = invalid then return
    m.overlay.visible = true
    refreshOverlay()
    restartHideTimer()
end sub

sub restartHideTimer()
    if m.hideTimer = invalid then return
    m.hideTimer.control = "stop"
    m.hideTimer.control = "start"
end sub

' The bar hides after the timeout only while genuinely playing; while paused,
' stale, or still buffering it stays so transport state stays visible.
sub onOverlayHideTimerFire()
    if m.video = invalid then return
    state = m.video.state
    if state = "playing" then m.overlay.visible = false
end sub

' Keep the progress fill and time text current; position/duration are float
' seconds, and the fill spans the 1640px track.
sub refreshOverlay()
    if m.video = invalid then return
    if m.overlay = invalid or not m.overlay.visible then return
    position = m.video.position
    duration = m.video.duration
    if position = invalid then position = 0.0
    UpdateProgress(position, duration)
end sub

' Set the fill width and time text for an absolute position. Driven both by live
' playback and immediately by seeks, so the bar and clock follow the presses
' instead of waiting for the position field to catch up after a seek.
sub UpdateProgress(position as float, duration as dynamic)
    if duration = invalid then duration = 0.0
    if duration < 0 then duration = 0.0
    if position < 0 then position = 0.0

    m.timeLabel.text = FormatTime(position) + " / " + FormatTime(duration)

    width = 0
    if duration > 0 then width = Int(1640 * (position / duration))
    if width > 1640 then width = 1640
    if width < 0 then width = 0
    m.fill.width = width
end sub

function FormatTime(seconds as dynamic) as string
    total = Int(seconds)
    if total < 0 then total = 0
    h = total \ 3600
    m = (total mod 3600) \ 60
    s = total mod 60
    if h > 0
        return h.ToStr() + ":" + Pad2Time(m) + ":" + Pad2Time(s)
    end if
    return Pad2Time(m) + ":" + Pad2Time(s)
end function

function Pad2Time(value as integer) as string
    if value < 10 then return "0" + value.ToStr()
    return value.ToStr()
end function

' The buffering logo tracks Video.bufferingStatus for real: percentage (0-100)
' is "% buffering complete", reported on every segment fetch, so the left-to-right
' reveal mirrors actual throughput — a fast stream fills fast, a slow one crawls.
' The field turns invalid the moment buffering finishes (including rebuffers), so
' that is the "done" signal: hide and rewind the clip.
sub onBufferingStatusChanged()
    if m.video = invalid then return
    status = m.video.bufferingStatus
    if status = invalid
        print "[rokumio] bufferingStatus invalid -> buffering done"
        HideBuffering()
        return
    end if
    pct = status.percentage
    if pct = invalid then pct = 0
    if pct < 0 then pct = 0
    if pct > 100 then pct = 100
    print "[rokumio] buffering pct=" + pct.ToStr()
    m.logoFront.clippingRect = [0, 0, Int(900 * pct / 100), 506]
end sub

function HasLogo() as boolean
    if m.logoBack = invalid then return false
    return m.logoBack.uri <> invalid and m.logoBack.uri <> ""
end function

sub HideBuffering()
    if m.logoFront <> invalid then m.logoFront.clippingRect = [0, 0, 0, 506]
    if m.bufferingGroup <> invalid then m.bufferingGroup.visible = false
end sub

' Back records the position first (while the node can still report one), then
' starts the teardown. When the player is mid-buffer the stop is asynchronous:
' we swallow Back until the OS confirms "stopped" (or the watchdog gives up),
' then the stack pops. Either way this never pops itself — closeRequest is how
' the real pop is asked for, so the pop lands only after playback truly ended.
' Before the stream resolves there is no video to save or stop: just let the
' stack pop (the resolve task is cancelled by OnExit).
function OnBackPressed() as boolean
    if m.video = invalid then return false
    SavePosition()
    return RequestStopAndWait()
end function

function OnExit() as void
    CancelResolve()
    SavePosition()
    if not m.pendingStop then TeardownVideo()
end function

' Request the stop and tell the caller whether it must hold the screen open.
'
' A synchronous `control = "stop"` is dropped while the player is mid-async-op
' (the buffering that follows a play command), and destroying the Video node /
' whole component during that op does NOT stop the platform media player — it
' keeps decoding, then starts outputting audio the moment the buffer fills. So
' a leave is two-phase: ask for an asynchronous stop (asyncStopSemantics, the
' documented OS 12.5+ field; sync stop by default), wait for the real "stopped"
' state, and only then tear down. onVideoStateChanged completes the leave.
function RequestStopAndWait() as boolean
    if m.video = invalid then return false
    state = m.video.state
    if state = "stopped" or state = "finished" or state = "error"
        TeardownVideo()
        return false
    end if
    print "[rokumio] PlayerScreen stopping (state='" + state.ToStr() + "')"
    if m.video.HasField("asyncStopSemantics") and not m.video.asyncStopSemantics
        m.video.asyncStopSemantics = true
    end if
    m.pendingStop = true
    m.status.text = "Stopping…"
    m.video.control = "stop"
    if m.stopWatchdog <> invalid
        m.stopWatchdog.control = "stop"
        m.stopWatchdog.control = "start"
    end if
    return true
end function

' Last resort: the stop never landed (a stalled buffer, an old OS without
' asyncStopSemantics). Mute + detach the stream before the teardown so whatever
' survives the destroy cannot start playing audio, then leave anyway.
sub onStopWatchdogFire()
    if not m.pendingStop then return
    print "[rokumio] PlayerScreen stop watchdog fired, forcing teardown"
    if m.video <> invalid
        if m.video.HasField("asyncStopSemantics") then m.video.asyncStopSemantics = true
        m.video.mute = true
        m.video.content = invalid
    end if
    m.pendingStop = false
    TeardownVideo()
    FireCloseRequest()
end sub

' Immediate teardown. Only runs once the player has actually stopped (or was
' already terminal); destroying a live player session is exactly how the audio
' leaked. Unobserve, detach the in-flight stream, remove the node and drop the
' reference so the stack's whole-component destroy has nothing left to hold.
sub TeardownVideo()
    if m.video = invalid then return
    m.video.UnobserveField("state")
    m.video.UnobserveField("position")
    m.video.UnobserveField("duration")
    m.video.UnobserveField("bufferingStatus")
    m.video.control = "stop"
    m.video.content = invalid
    m.videoSurface.RemoveChild(m.video)
    m.video = invalid
    HideBuffering()
end sub

' Ask MainScene to pop this screen. The pop runs OnExit (guarded, nothing left to
' do) and tears the whole component out of the tree — the true release.
sub FireCloseRequest()
    print "[rokumio] PlayerScreen closeRequest"
    m.top.closeRequest = { requested: true }
end sub

sub BlurFocus()
end sub

sub SavePosition()
    if m.saved then return
    if m.playParams = invalid or m.playParams.videoId = invalid then return
    if m.stores = invalid or m.stores.library = invalid then return
    ' Leaving while the stream is still buffering means nothing was actually
    ' watched — the video node cannot even report a position yet. Skip the write
    ' so an existing resume point is never clobbered with a bogus one.
    if not m.hasPlayed then return

    position = m.video.position
    duration = m.video.duration
    if position = invalid then position = 0
    if duration = invalid then duration = 0

    params = m.playParams
    season = 0
    if params.season <> invalid then season = params.season
    episode = 0
    if params.episode <> invalid then episode = params.episode
    name = ""
    if params.name <> invalid then name = params.name
    poster = ""
    if params.poster <> invalid then poster = params.poster

    m.stores.library.SetPosition(params.videoId, params.metaId, params.metaType, season, episode, name, poster, Int(position), Int(duration))
    m.saved = true
end sub