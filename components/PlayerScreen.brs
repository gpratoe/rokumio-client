' PlayerScreen — minimal video playback for a resolved stream URL.
'
' Plays the direct/HLS URL handed over by StreamsScreen, tracks position, and on
' Back (or exit) records where the user stopped through LibraryStore.SetPosition
' so Continue Watching / Resume can pick it up. Resume positions are stored in
' seconds and carried into the content node's playStart field; playback state is
' surfaced through the status label so a broken stream is a message, not a black
' screen.
'
' Transport is entirely this screen's own because the Video runs with
' enableUI=false — the platform never draws a pause screen or trick-play
' timeline. OK and the play/pause buttons all toggle playback, Left/Right step
' ±10s and FF/RW ±30s, and the custom bottom bar shows progress. The bar hides
' after a few seconds of playing but stays up while paused/error.
'
' Params: { url, metaType, metaId, videoId, season, episode, position, name,
'           poster, logo }.

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

    m.hideTimer.ObserveField("fire", "onOverlayHideTimerFire")
    m.toastTimer.ObserveField("fire", "onToastHideTimerFire")
    m.stopWatchdog = m.top.FindNode("stopWatchdog")
    m.stopWatchdog.ObserveField("fire", "onStopWatchdogFire")
    m.pendingStop = false
    m.seekPending = 0
end sub

' The Video node is a per-play instance: created fresh on every enter and torn
' down on exit, because a reused node refuses to abandon a stream once playback
' has begun (content swaps and control="stop" are ignored mid-buffer) — on top
' of that, a still-running player keeps decoding/downloading invisibly after the
' screen is gone. A from-scratch node each play guarantees a clean player and
' silence on exit, at no cost beyond node creation.
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

function SetStores(stores as object) as void
    m.stores = stores
end function

function OnEnter(params as object) as void
    if params = invalid or params.url = invalid then return
    m.playParams = params
    m.saved = false
    m.hasPlayed = false
    CreateVideo()

    logo = params.logo
    if logo = invalid or logo = "" then logo = params.poster
    if logo <> invalid and logo <> ""
        m.logoBack.uri = logo
        m.logoFront.uri = logo
    else
        m.bufferingGroup.visible = false
    end if

    content = CreateObject("roSGNode", "ContentNode")
    content.url = params.url
    title = params.name
    if title = invalid then title = ""
    content.title = title
    m.title.text = title
    startOffset = 0
    if params.position <> invalid and params.position > 0 then startOffset = params.position
    if startOffset > 0 then content.playStart = startOffset
    streamFormat = DetectStreamFormat(params.url)
    if streamFormat <> "" then content.streamFormat = streamFormat

    print "[rokumio] PlayerScreen url='" + params.url + "' format='" + streamFormat + "' playStart=" + startOffset.ToStr()

    m.video.enablePositionTracking = true
    m.video.content = content
    m.video.SetFocus(true)
    m.video.control = "play"
    m.playButton.uri = "pkg:/images/icon_pause.png"
    ShowOverlay()
end function

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
        if HasLogo() then m.bufferingGroup.visible = true
    else if state = "finished" or state = "stopped"
        m.overlay.visible = false
        HideBuffering()
    end if
    refreshOverlay()
end sub

' All transport keys land here. OK/Play/Pause/Replay all mean the same thing
' (toggle), so there is no state where a press does something unexpected;
' Left/Right and FF/RW seek immediately. Everything else falls through (Back
' reaches the stack → stop + save + pop).
function OnKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
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
function OnBackPressed() as boolean
    SavePosition()
    return RequestStopAndWait()
end function

function OnExit() as void
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