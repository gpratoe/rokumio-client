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
'           poster }.

sub init()
    m.video = m.top.FindNode("video")
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

    m.video.ObserveField("state", "onVideoStateChanged")
    m.video.ObserveField("position", "refreshOverlay")
    m.video.ObserveField("duration", "refreshOverlay")
    m.hideTimer.ObserveField("fire", "onOverlayHideTimerFire")
    m.toastTimer.ObserveField("fire", "onToastHideTimerFire")
end sub

function SetStores(stores as object) as void
    m.stores = stores
end function

function OnEnter(params as object) as void
    if params = invalid or params.url = invalid then return
    m.playParams = params
    m.saved = false

    m.status.text = "Loading stream…"

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
    state = m.video.state
    print "[rokumio] PlayerScreen state='" + state.ToStr() + "'"
    if state = invalid then return
    if state = "playing"
        m.status.text = ""
        m.playButton.uri = "pkg:/images/icon_pause.png"
        restartHideTimer()
    else if state = "paused"
        m.playButton.uri = "pkg:/images/icon_play.png"
    else if state = "error"
        m.status.text = "Playback failed: check the stream and server."
        m.playButton.uri = "pkg:/images/icon_play.png"
    else if state = "buffering"
        m.status.text = "Loading stream…"
    else if state = "finished" or state = "stopped"
        m.overlay.visible = false
    end if
    refreshOverlay()
end sub

' All transport keys land here. OK/Play/Pause/Replay all mean the same thing
' (toggle), so there is no state where a press does something unexpected;
' Left/Right and FF/RW seek immediately. Everything else falls through (Back
' reaches the stack → stop + save + pop).
function OnKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
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
    target = position + seconds
    if duration <> invalid and duration > 0 and target > duration then target = duration
    if target < 0 then target = 0
    m.video.seek = target
    print "[rokumio] PlayerScreen seek " + seconds.ToStr() + "s -> " + target.ToStr()
    ShowOverlay()
    ShowSeekToast(target)
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
    state = m.video.state
    if state = "playing" then m.overlay.visible = false
end sub

' Keep the progress fill and time text current; position/duration are float
' seconds, and the fill spans the 1640px track.
sub refreshOverlay()
    if m.overlay = invalid or not m.overlay.visible then return
    position = m.video.position
    duration = m.video.duration
    if position = invalid then position = 0.0
    if duration = invalid then duration = 0.0
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

' Back stops the video, records the position and lets the stack pop. OnExit also
' saves, guarded so the position is written once.
function OnBackPressed() as boolean
    m.video.control = "stop"
    SavePosition()
    return false
end function

function OnExit() as void
    SavePosition()
end function

sub BlurFocus()
end sub

sub SavePosition()
    if m.saved then return
    if m.playParams = invalid or m.playParams.videoId = invalid then return
    if m.stores = invalid or m.stores.library = invalid then return

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