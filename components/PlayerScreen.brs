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
' Transport is the platform's: the Video runs with enableUI and enableTrickPlay
' on, so OK/play-pause show the native pause screen, Left/Right and FF/RW use
' the native seek/trick-play UI, and "*" opens Roku's Options overlay with its
' certification-mandated captions dialog. The screen only owns the resolve
' (pre-video) phase and teardown; Back records the position and pops.
'
' Subtitle captions are fetched off-thread (SubtitleLoaderTask) from an add-on
' advertising the "subtitles" resource (OpenSubtitles v3 is the built-in, an
' installed add-on wins) and attached to the video through SubtitleTracks /
' SubtitleConfig. The per-video caption mode is forced on so a device captions
' setting cannot keep them hidden, and a track list already in hand when the
' stream starts rides on the ContentNode (Roku's documented home for
' SubtitleTracks) before play. The native Options dialog lists Off + every
' track from SubtitleTracks, so the Roku OS owns track selection from there.
' Auto-pick is by device locale, else English, else the first track.
'
' Params: { stream, serverAddress, metaType, metaId, videoId, season, episode,
'           position, name, poster, logo }.

sub init()
    m.video = m.top.FindNode("video")
    m.status = m.top.FindNode("playerStatus")
    m.bufferingGroup = m.top.FindNode("bufferingGroup")
    m.logoBack = m.top.FindNode("logoBack")
    m.logoFront = m.top.FindNode("logoFront")
    m.resolvePulse = m.top.FindNode("resolvePulse")

    m.stopWatchdog = m.top.FindNode("stopWatchdog")
    m.stopWatchdog.ObserveField("fire", "onStopWatchdogFire")
    m.pendingStop = false
    m.resolveTask = invalid
    m.subtitleTask = invalid
    m.subtitleTracks = invalid
    m.subtitleIndex = -1
    m.subtitleNodesApplied = false
    m.subtitlePicker = SubtitlesStore(invalid)
end sub

function SetStores(stores as object) as void
    m.stores = stores
end function

function OnEnter(params as object) as void
    if params = invalid or params.stream = invalid then return
    m.playParams = params
    m.saved = false
    m.hasPlayed = false

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
    StartSubtitles(params)
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

' Kick the caption fetch off the render thread. Subtitles never gate playback:
' StartPlayback applies whatever had arrived by then and a late result applies
' to the live Video node the moment it reports in. The add-on scan prefers an
' installed (non-built-in) add-on so a locally installed mock beats the
' internet-bound OpenSubtitles built-in; OpenSubtitles is only used when
' nothing else advertises the resource.
sub StartSubtitles(params as object)
    if m.stores = invalid or m.stores.addons = invalid then return
    if m.subtitleTask <> invalid then return
    if params.metaType = invalid or params.videoId = invalid then return
    if params.metaType = "" or params.videoId = "" then return

    address = FindSubtitlesAddress(m.stores.addons.GetAll())
    if address = "" then return

    task = CreateObject("roSGNode", "SubtitleLoaderTask")
    task.id = "playerSubtitles"
    m.top.AppendChild(task)
    task.addonAddress = address
    task.metaType = params.metaType
    task.videoId = params.videoId
    task.observeField("result", "onSubtitleResult")
    m.subtitleTask = task
    task.control = "RUN"
    print "[rokumio] PlayerScreen subtitle task started address='" + address + "'"
end sub

' Address of the add-on to ask for captions: the first installed (non-built-in)
' add-on advertising "subtitles", else the built-in that does.
function FindSubtitlesAddress(addons as object) as string
    builtin = ""
    for each addon in addons
        if addon <> invalid and addon.address <> invalid and addon.address <> ""
            if addon.resources <> invalid and m.stores.addons.HasResource(addon.resources, "subtitles")
                if addon.builtin = true
                    if builtin = "" then builtin = addon.address
                else
                    return addon.address
                end if
            end if
        end if
    end for
    return builtin
end function

' The caption list landed. The raw add-on tracks become the SubtitleTracks
' source and a pick index selects the active one; a failure leaves the player
' caption-free, which is fine (no subs is never an error). Results that land
' after a Back-out are dropped by the m.subtitleTask guard.
sub onSubtitleResult()
    if m.subtitleTask = invalid then return
    task = m.subtitleTask
    m.subtitleTask = invalid
    result = task.result
    task.unobserveField("result")
    if task.getParent() <> invalid then m.top.RemoveChild(task)

    if result = invalid or not result.ok or result.subtitles = invalid or result.subtitles.Count() = 0
        ClearSubtitles()
        return
    end if

    m.subtitleTracks = result.subtitles
    m.subtitleNodesApplied = false
    m.subtitleIndex = m.subtitlePicker.PickTrack(result.subtitles, DeviceLocale())
    print "[rokumio] PlayerScreen subtitles=" + result.subtitles.Count().ToStr() + " pick=" + m.subtitleIndex.ToStr()
    ' Playback never waits for this fetch, so a list that lands here applies to
    ' the live content node (and writes video.subtitleTrack) mid-play; the
    ' native Options dialog picks the tracks up from the updated SubtitleTracks.
    ApplySubtitleIndex(invalid)
end sub

sub CancelSubtitles()
    if m.subtitleTask <> invalid
        m.subtitleTask.unobserveField("result")
        m.subtitleTask.control = "STOP"
        if m.subtitleTask.getParent() <> invalid then m.top.RemoveChild(m.subtitleTask)
        m.subtitleTask = invalid
    end if
end sub

' Drop the caption state back to none without touching the Video node's current
' config — a per-play node starts clean, so there is nothing to undo.
sub ClearSubtitles()
    m.subtitleTracks = invalid
    m.subtitleIndex = -1
    m.subtitleNodesApplied = false
end sub

' Push the current subtitle selection onto the video's content. SubtitleTracks is
' content metadata on the ContentNode the Video plays. Roku's native player
' expects each entry as an associative array with TrackName set to the
' downloadable subtitle URL; tracks already in hand ride the node pre-play (the
' reliable sideloaded path), and a list that arrives later targets the live
' content node instead. Selection is matched from the raw list by URL because
' BuildSubtitleTracks drops entries without one, so the pick index does not
' always line up with the built array. Visibility is driven through
' globalCaptionMode (the per-video switch that overrides the device caption
' setting); the native Options dialog takes over track selection from there.
sub ApplySubtitleIndex(content as object)
    if content = invalid then content = CurrentContent()
    if content = invalid then return

    if m.subtitleTracks = invalid or m.subtitleTracks.Count() = 0
        content.subtitleTracks = []
        content.subtitleConfig = {}
        SetCaptionMode("off")
        return
    end if

    if not m.subtitleNodesApplied
        content.subtitleTracks = BuildSubtitleTracks()
        m.subtitleNodesApplied = true
    end if

    selected = SelectedSubtitleTrack()
    if selected = ""
        content.subtitleConfig = {}
        SetCaptionMode("off")
        return
    end if

    content.subtitleConfig = { TrackName: selected }
    SelectSubtitleTrack(selected)
    ' Force captions on when we have tracks so the user sees them by default
    SetCaptionMode("on")
end sub

' The TrackName URL of the picked raw track — the same URL BuildSubtitleTracks
' wrote into the built array — or "" when there is nothing to select.
function SelectedSubtitleTrack() as string
    if m.subtitleTracks = invalid then return ""
    if m.subtitleIndex < 0 or m.subtitleIndex >= m.subtitleTracks.Count() then return ""
    rawTrack = m.subtitleTracks[m.subtitleIndex]
    if rawTrack = invalid then return ""
    url = ""
    if rawTrack.DoesExist("url") and rawTrack.url <> invalid then url = rawTrack.url
    if url = "" and rawTrack.DoesExist("downloadUrl") and rawTrack.downloadUrl <> invalid then url = rawTrack.downloadUrl
    return url
end function

' The content node currently driving the player, or invalid before StartPlayback.
function CurrentContent() as object
    if m.video <> invalid then return m.video.content
    return invalid
end function

' The per-video caption switch. This is the Video node's globalCaptionMode
' ("On"/"Off"); Roku expects apps to write it whenever captions are toggled, so
' the chosen state applies even when the device-level caption setting says the
' opposite.
sub SetCaptionMode(mode as string)
    if m.video = invalid then return
    if not m.video.HasField("globalCaptionMode") then return
    value = "Off"
    if mode = "on" then value = "On"
    m.video.globalCaptionMode = value
end sub

' Live-node track switch for lists applied after playback has begun:
' Video.subtitleTrack is the documented write field that re-selects a track on
' the fly. Before play the ContentNode carries the tracks, so this is a no-op
' there.
sub SelectSubtitleTrack(trackName as string)
    if m.video = invalid then return
    if not m.video.HasField("subtitleTrack") then return
    if trackName = "" then return
    m.video.subtitleTrack = trackName
end sub

function BuildSubtitleTracks() as object
    tracks = []
    if m.subtitleTracks = invalid then return tracks
    languageCounts = {}
    for each track in m.subtitleTracks
        subtitleUrl = ""
        if track.DoesExist("url") and track.url <> invalid then subtitleUrl = track.url
        if subtitleUrl = "" and track.DoesExist("downloadUrl") and track.downloadUrl <> invalid then subtitleUrl = track.downloadUrl
        if subtitleUrl = "" then
            continue for
        end if

        language = TrackDisplayName(track)
        count = 1
        if languageCounts.DoesExist(language) then count = languageCounts[language] + 1
        languageCounts[language] = count

        ' Roku's native Video expects subtitleTracks as an array of associative
        ' arrays. TrackName must be the downloadable subtitle URL; Url plus
        ' ContentNode children are not reliably enumerated by the native menu.
        tracks.Push({
            Language: m.subtitlePicker.TrackLang(track)
            Description: language + " " + count.ToStr()
            TrackName: subtitleUrl
        })
    end for
    return tracks
end function

function TrackDisplayName(track as object) as string
    if track <> invalid
        if track.langName <> invalid and track.langName.Trim() <> "" then return track.langName.Trim()
        if track.lang <> invalid and track.lang.Trim() <> "" then return track.lang.Trim()
    end if
    return "Captions"
end function

' The Roku locale for the default caption pick, e.g. "es_ES"; a two-letter
' prefix is what SubtitlesStore.PickTrack matches against the tracks.
function DeviceLocale() as string
    device = CreateObject("roDeviceInfo")
    if device <> invalid
        locale = device.GetCurrentLocale()
        if locale <> invalid then return locale.ToStr()
    end if
    return ""
end function

' The Video node is declared in XML so Roku owns its native UI lifecycle. Each
' player screen is a fresh component instance; the node is reused only for the
' single stream played by that screen and is cleared during teardown.
sub CreateVideo()
    if m.video = invalid then return
    m.video.visible = true
    m.video.ObserveField("state", "onVideoStateChanged")
    m.video.ObserveField("bufferingStatus", "onBufferingStatusChanged")
end sub

' The resolved URL is the only thing that ever touches the Video node: build the
' content (title, resume offset, sniffed stream format), then play. Captions do
' not gate playback — a list already in hand rides the content pre-play, and a
' result still in flight applies to the live node the moment it lands.
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

    m.video.enablePositionTracking = true
    ApplySubtitleIndex(content)
    m.video.content = content
    m.video.SetFocus(true)
    m.video.control = "play"
    print "[rokumio] PlayerScreen url='" + url + "' format='" + streamFormat + "' playStart=" + startOffset.ToStr()
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

' Surface playback state on the status line for the grab-before-video resolve
' phase and for failures: a broken stream is a message, not a silent black
' frame. The native chrome owns everything once the platform has a stream.
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
        HideBuffering()
    else if state = "error"
        m.status.text = "Playback failed: check the stream and server."
        HideBuffering()
    else if state = "buffering"
        StopResolvePulse()
        if HasLogo() then m.bufferingGroup.visible = true
    else if state = "finished" or state = "stopped"
        HideBuffering()
    end if
end sub

' Native playback owns every remote key once a Video exists: the platform's
' pause screen, seek/trick-play, and Options (captions) dialog all handle their
' own keys when this handler lets them through, so nothing is intercepted and
' every key except Back falls through to the focused Video node.
'
' Before the stream resolves (or after a failure) there is no video: Back still
' pops (OnBackPressed returns false) and every other key is swallowed so a
' press routes nowhere else. Everything else falls through (Back reaches the
' stack → stop + save + pop).
function OnKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if m.video = invalid
        if key = "back" then return false
        return true
    end if
    ' Mid-teardown: every key is swallowed until the player actually reports
    ' "stopped" (see RequestStopAndWait) so nothing can interrupt the stop.
    if m.pendingStop then return true
    return false
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
    CancelSubtitles()
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
    m.video.UnobserveField("bufferingStatus")
    m.video.control = "stop"
    m.video.content = invalid
    m.video.visible = false
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
