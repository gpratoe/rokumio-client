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
' Transport is the platform's, but the built-in trick-play UI is disabled: a
' focused Video consumes OK to reveal that UI before the parent OnKeyEvent ever
' sees it. The screen owns pause/resume and its paused action row so one center
' press really pauses. Back records the position and pops.
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

' How long the first `control = "play"` waits for this play's caption drain, in
' playKick ticks (0.25s each). Twelve is three seconds.
'
' Why playback waits at all: SubtitleTracks belongs on the ContentNode BEFORE
' the pump starts — that pre-play path is the only one Roku reliably accepts.
' A track array written onto a content node the video is already playing is a
' mid-play mutation of the thing the pump is reading, and the symptom is not a
' polite error: the video hangs, plays a moment and then buffers forever, or
' fills the buffer and never renders a frame. The drain is sequential (one
' provider in flight, the next launched from onSubtitleResult), so every extra
' subtitle add-on installed is one more of those writes landing later — which is
' how a third add-on turned an occasional wedge into an every-play one.
'
' Why the wait is bounded: a provider that never answers must not be able to
' hold playback hostage. Three seconds is several healthy providers' worth of
' round trips; past it the drain is reaped and the video plays without the
' stragglers (see CancelSubtitles in onPlayKickFire), because a cancelled
' request can never land and can never be applied.
sub init()
    m.video = m.top.FindNode("video")
    m.status = m.top.FindNode("playerStatus")
    m.bufferingGroup = m.top.FindNode("bufferingGroup")
    m.logoBack = m.top.FindNode("logoBack")
    m.logoFront = m.top.FindNode("logoFront")
    m.preVideoPulse = m.top.FindNode("preVideoPulse")
    m.torrentStatsGroup = m.top.FindNode("torrentStatsGroup")
    m.torrentStatsText = m.top.FindNode("torrentStatsText")
    m.torrentStatsTask = invalid
    m.pauseActionsGroup = m.top.FindNode("pauseActionsGroup")
    m.pauseResumeBg = m.top.FindNode("pauseResumeBg")
    m.pauseResumePlayIcon = m.top.FindNode("pauseResumePlayIcon")
    m.pauseResumePauseIcon = m.top.FindNode("pauseResumePauseIcon")
    m.pauseNextBg = m.top.FindNode("pauseNextBg")
    m.pauseCaptionsBg = m.top.FindNode("pauseCaptionsBg")
    m.pauseCaptionsText = m.top.FindNode("pauseCaptionsText")
    m.pauseTitle = m.top.FindNode("pauseTitle")
    m.pauseEpisodeTitle = m.top.FindNode("pauseEpisodeTitle")
    m.seekFocus = m.top.FindNode("seekFocus")
    m.seekFill = m.top.FindNode("seekFill")
    m.seekKnob = m.top.FindNode("seekKnob")
    m.seekElapsed = m.top.FindNode("seekElapsed")
    m.seekDuration = m.top.FindNode("seekDuration")
    m.pauseActionIndex = 0
    m.pauseHasNext = false
    m.controlsVisible = false
    m.controlsPaused = false
    m.seekTarget = 0
    m.seekDirty = false
    m.playNextWhenReady = false
    t = Theme()
    m.top.FindNode("playerBg").color = t.playerBg
    m.status.color = t.textPrimary
    if m.torrentStatsText <> invalid then m.torrentStatsText.color = t.textPrimary
    if m.pauseTitle <> invalid then m.pauseTitle.color = t.textPrimary
    if m.pauseEpisodeTitle <> invalid then m.pauseEpisodeTitle.color = t.textSecondary
    if m.pauseCaptionsText <> invalid then m.pauseCaptionsText.color = t.textPrimary
    if m.seekElapsed <> invalid then m.seekElapsed.color = t.textSecondary
    if m.seekDuration <> invalid then m.seekDuration.color = t.textSecondary
    m.playerUiTick = m.top.FindNode("playerUiTick")
    if m.playerUiTick <> invalid then m.playerUiTick.ObserveField("fire", "onPlayerUiTick")
    m.seekRepeat = m.top.FindNode("seekRepeat")
    m.seekRepeatActive = false
    m.seekRepeatDirection = 0
    m.seekRepeatCoarse = false
    m.seekRepeatTicks = 0
    if m.seekRepeat <> invalid then m.seekRepeat.ObserveField("fire", "onSeekRepeat")
    m.controlsHide = m.top.FindNode("controlsHide")
    if m.controlsHide <> invalid then m.controlsHide.ObserveField("fire", "onControlsHide")

    ' Observed here rather than in CreateVideo: this screen is a static child
    ' that survives every pop, so CreateVideo runs once per play and observing
    ' there would re-observe the same two fields on each one.
    m.video.ObserveField("state", "onVideoStateChanged")
    m.video.ObserveField("bufferingStatus", "onBufferingStatusChanged")
    ' Add-on tracks are known before play, but tracks carried inside the video
    ' only appear after Roku's demuxer opens the stream. Watch that discovery so
    ' an embedded copy can replace the temporary add-on default.
    if m.video.HasField("availableSubtitleTracks") then m.video.ObserveField("availableSubtitleTracks", "onAvailableSubtitleTracksChanged")

    m.resolveTask = invalid
    m.subtitleTask = invalid
    m.subtitleParams = invalid
    m.subtitleCandidates = []
    m.subtitleCursor = 0
    m.subtitleTracks = invalid
    m.subtitleIndex = -1
    m.captionSelection = ""
    m.captionPreferenceSet = false
    m.captionPreferenceEnabled = false
    m.captionPreferenceLanguage = ""
    m.captionPreferenceLabel = ""
    m.captionPreferenceOrdinal = 1
    m.captionPreferenceEmbedded = false
    m.captionPreferenceMetaId = ""
    m.subtitleNodesApplied = false
    m.subtitleAsked = ""
    m.subtitleReached = 0
    m.subtitleTried = 0
    m.subtitlePicker = SubtitlesStore(invalid)

    ' The tick boundary StartPlayback defers `control = "play"` across. Observed
    ' here rather than in CreateVideo so it is armed exactly once, and armed
    ' before any play can ask for it.
    m.playTimer = m.top.FindNode("playKick")
    m.playArmed = false
    ' Set for real the moment a play asks to play, it is the flag that makes the
    ' "never write track arrays onto a playing node" rule enforceable: the drain
    ' only ever applies to a node that has not played yet. Reset per play in
    ' OnEnter — before StartSubtitles runs there, or the next play's drain is
    ' refused before it asks anyone.
    m.playStarted = false
    ' Ticks the playKick has spent waiting on the caption drain, against
    ' m.subtitleHoldMaxTicks.
    m.subtitleHoldTicks = 0
    ' The bound on that wait: twelve 0.25s ticks is three seconds of patience
    ' for a caption drain that cannot finish, which is several healthy
    ' providers' worth of round trips. A component file is compiled as standard
    ' BrightScript, where a file-scope `const` is not available, so the number
    ' lives here — see the header comment for why the wait exists and why it is
    ' bounded.
    m.subtitleHoldMaxTicks = 12
    if m.playTimer <> invalid then m.playTimer.ObserveField("fire", "onPlayKickFire")
    m.stallWatch = m.top.FindNode("stallWatch")
    if m.stallWatch <> invalid then m.stallWatch.ObserveField("fire", "onStallWatch")
    m.recoverKick = m.top.FindNode("recoverKick")
    if m.recoverKick <> invalid then m.recoverKick.ObserveField("fire", "onRecoverKick")
    m.nextStreamTask = invalid
    m.nextResolveTask = invalid
    m.nextPrefetch = invalid
    m.nextPrepared = invalid
    m.pendingPreparedNext = invalid
    m.nextPrefetchStarted = false
    m.nextWaitTimeout = m.top.FindNode("nextWaitTimeout")
    if m.nextWaitTimeout <> invalid then m.nextWaitTimeout.ObserveField("fire", "onNextWaitTimeout")
    ResetRecovery()
end sub

function OnEnter(params as object) as void
    ' The language first: every word this screen shows (the status line, the
    ' toasts, the failure messages) comes from the table, and the player is
    ' pushed with a stream — never re-entered from a settings screen — so the
    ' pull here is the one that matters.
    RefreshTexts()
    if params = invalid or params.stream = invalid then return
    ' Keep an explicit caption choice while moving between episodes of the same
    ' series, including the StreamsScreen fallback route. A different title
    ' starts with the normal locale-based default instead.
    incomingMetaId = StringOf(params.metaId)
    if m.captionPreferenceMetaId <> "" and incomingMetaId <> m.captionPreferenceMetaId
        ResetCaptionPreference()
    end if
    m.playParams = params
    m.saved = false
    m.hasPlayed = false
    m.nextRequested = false
    m.playNextWhenReady = false
    HidePausedControls()
    CancelNextPrefetch()
    ' The per-play flags reset at the real per-play boundary. m.playStarted in
    ' particular: LaunchSubtitleFetch refuses a fetch while it stands, so a flag
    ' left over from the previous play silently kills every play after the
    ' first — no provider is ever asked, no captions land, and the playKick hold
    ' then spends its whole budget against a drain that never started. This has
    ' to happen HERE and not in StartPlayback: StartSubtitles runs from this
    ' function, before the resolve returns, and would already be refused.
    m.playStarted = false
    ' The status line is cleared here, not left to the first onVideoStateChanged.
    ' "playing" is the only branch that clears it (see below), and a stream that
    ' cannot resolve never reaches it — so without this, a dead source's message
    ' outlives the pop and is still on screen for the WHOLE of the next play's
    ' resolve, which for a torrent is up to the long timeout. ResetVideoNode
    ' clears it too; this is the belt to that braces, since a play entered
    ' without a preceding OnExit (the very first one) still starts clean.
    m.status.text = ""

    ' The pre-video pulse (logo beating transparent to solid, Stremio-style)
    ' only has something to show when a logo URL is available; otherwise the
    ' bare screen waits it out. No status label of its own — the pulse IS the
    ' indicator, and it runs from here until the platform's buffering UI takes
    ' over (see StartPreVideoPulse for the lifetime).
    logo = params.logo
    if logo = invalid or logo = "" then logo = params.poster
    if logo <> invalid and logo <> ""
        m.logoBack.uri = logo
        m.logoFront.uri = logo
        m.bufferingGroup.visible = true
        StartPreVideoPulse()
    else
        m.bufferingGroup.visible = false
    end if

    ' The picker's per-play mode wins; the setting is only the fallback for
    ' entries that did not choose (ask mode is resolved in the picker).
    playMode = DirectPlayModeSetting()
    if params.directPlayMode = "on" or params.directPlayMode = "off" then playMode = params.directPlayMode
    m.playMode = playMode
    StartResolve(params.stream, params.serverAddress, ResolveOrdinal(params.season), ResolveOrdinal(params.episode))
    StartTorrentStats()
    StartSubtitles(params)
end function

' Start a live Stremio torrent-statistics subscription for the loading card.
' A URL stream wins over an infoHash just as PlaybackStore.IsTorrent does, so
' direct/debrid streams never display invented peer data.
sub StartTorrentStats()
    if m.torrentStatsTask <> invalid or m.playParams = invalid then return
    params = m.playParams
    if params.stream = invalid or params.serverAddress = invalid or params.serverAddress = "" then return
    stream = params.stream
    ' Lookup + type guard deliberately mirrors PlaybackStore.AsText. url and
    ' infoHash are not normalized at the add-on boundary because coercing a
    ' numeric value would manufacture a URL/hash that should not exist.
    streamUrl = stream.Lookup("url")
    if streamUrl <> invalid and Type(streamUrl) = "roString" and streamUrl.Trim() <> "" then return
    hash = ""
    hashValue = stream.Lookup("infoHash")
    if hashValue <> invalid and Type(hashValue) = "roString" then hash = hashValue.Trim()
    if hash = "" then return

    task = CreateObject("roSGNode", "TorrentStatsTask")
    task.id = "torrentStats"
    m.top.AppendChild(task)
    task.serverAddress = params.serverAddress
    task.infoHash = hash
    task.ObserveField("stats", "onTorrentStats")
    m.torrentStatsTask = task
    if m.torrentStatsGroup <> invalid then m.torrentStatsGroup.visible = true
    if m.torrentStatsText <> invalid
        m.torrentStatsText.text = Fill(Lang("player", "torrentStats"), {
            peers: "0"
            download: TorrentRateText(0)
        })
    end if
    task.control = "RUN"
end sub

sub onTorrentStats()
    if m.torrentStatsTask = invalid or m.torrentStatsText = invalid then return
    value = m.torrentStatsTask.stats
    if value = invalid then return
    peers = 0
    if value.peers <> invalid then peers = Int(value.peers)
    m.torrentStatsText.text = Fill(Lang("player", "torrentStats"), {
        peers: peers.ToStr()
        download: TorrentRateText(value.downloadSpeed)
    })
    if m.torrentStatsGroup <> invalid then m.torrentStatsGroup.visible = true
end sub

sub StopTorrentStats()
    if m.torrentStatsTask <> invalid
        task = m.torrentStatsTask
        m.torrentStatsTask = invalid
        task.UnobserveField("stats")
        task.control = "STOP"
        if task.GetParent() <> invalid then m.top.RemoveChild(task)
    end if
    if m.torrentStatsGroup <> invalid then m.torrentStatsGroup.visible = false
end sub

' Human-sized byte rates matching Stremio's statistics display. One decimal is
' retained for MB/s and KB/s; zero remains explicit so a stalled swarm is clear.
function TorrentRateText(value as dynamic) as string
    if value = invalid or value <= 0 then return "0 B/s"
    if value >= 1048576
        tenths = Int(value * 10 / 1048576)
        return Int(tenths / 10).ToStr() + "." + (tenths mod 10).ToStr() + " MB/s"
    end if
    if value >= 1024
        tenths = Int(value * 10 / 1024)
        return Int(tenths / 10).ToStr() + "." + (tenths mod 10).ToStr() + " KB/s"
    end if
    return Int(value).ToStr() + " B/s"
end function

sub ShowPausedControls()
    ShowPlayerControls(true)
end sub

sub ShowPlayingControls()
    ShowPlayerControls(false)
end sub

' Movies keep their plain title. Series add the same localized S/E marker used
' across Details and Streams so the overlay still identifies the exact episode
' after seamless autoplay replaces the content without leaving the player.
function PlayerOverlayTitle() as string
    if m.playParams = invalid then return ""
    title = StringOf(m.playParams.name)
    metaType = LCase(StringOf(m.playParams.metaType))
    if metaType <> "series" then return title
    if m.playParams.season = invalid or m.playParams.episode = invalid then return title
    marker = Fill(Lang("common", "episodeMarker"), {
        season: StringOf(m.playParams.season)
        episode: StringOf(m.playParams.episode)
    })
    if marker = "" then return title
    if title = "" then return marker
    return title + "  ·  " + marker
end function

' The episode's own title gets a quieter second line. It is separate from the
' series/SxE line so adding it does not move the controls, timeline, or actions.
function PlayerOverlayEpisodeTitle() as string
    if m.playParams = invalid then return ""
    if LCase(StringOf(m.playParams.metaType)) <> "series" then return ""
    return StringOf(m.playParams.episodeName).Trim()
end function

sub ShowPlayerControls(paused as boolean)
    m.controlsVisible = true
    m.controlsPaused = paused
    m.pauseActionIndex = 0
    m.pauseHasNext = NextEpisodeParams() <> invalid
    m.seekDirty = false
    m.seekTarget = 0
    if m.video <> invalid and m.video.position <> invalid then m.seekTarget = Int(m.video.position)
    if m.pauseTitle <> invalid
        m.pauseTitle.text = PlayerOverlayTitle()
    end if
    if m.pauseEpisodeTitle <> invalid
        m.pauseEpisodeTitle.text = PlayerOverlayEpisodeTitle()
        m.pauseEpisodeTitle.visible = m.pauseEpisodeTitle.text <> ""
    end if
    if m.pauseActionsGroup <> invalid then m.pauseActionsGroup.visible = true
    UpdateSeekDisplay()
    if m.playerUiTick <> invalid
        m.playerUiTick.control = "stop"
        m.playerUiTick.control = "start"
    end if
    StartTorrentStats()
    UpdatePausedControlFocus()
    if paused
        if m.controlsHide <> invalid then m.controlsHide.control = "stop"
    else
        ArmControlsHide()
    end if
end sub

sub HidePausedControls()
    StopSeekRepeat()
    m.controlsVisible = false
    if m.controlsHide <> invalid then m.controlsHide.control = "stop"
    if m.pauseActionsGroup <> invalid then m.pauseActionsGroup.visible = false
    if m.playerUiTick <> invalid then m.playerUiTick.control = "stop"
    StopTorrentStats()
end sub

sub ArmControlsHide()
    if m.controlsHide = invalid or m.controlsPaused then return
    m.controlsHide.control = "stop"
    m.controlsHide.control = "start"
end sub

sub onControlsHide()
    if m.controlsVisible and not m.controlsPaused then HidePausedControls()
end sub

sub UpdatePausedControlFocus()
    t = Theme()
    idle = "0x242136F2"
    disabled = "0x181620B8"
    if m.seekFocus <> invalid
        if m.pauseActionIndex = 0 then m.seekFocus.color = "0xFFFFFF18" else m.seekFocus.color = "0x00000000"
    end if
    if m.pauseResumeBg <> invalid
        if m.pauseActionIndex = 1 then m.pauseResumeBg.color = t.accent else m.pauseResumeBg.color = idle
    end if
    if m.pauseResumePlayIcon <> invalid then m.pauseResumePlayIcon.visible = m.controlsPaused
    if m.pauseResumePauseIcon <> invalid then m.pauseResumePauseIcon.visible = not m.controlsPaused
    if m.pauseNextBg <> invalid
        if not m.pauseHasNext
            m.pauseNextBg.color = disabled
        else if m.pauseActionIndex = 2
            m.pauseNextBg.color = t.accent
        else
            m.pauseNextBg.color = idle
        end if
    end if
    if m.pauseCaptionsBg <> invalid
        if m.pauseActionIndex = 3
            m.pauseCaptionsBg.color = t.accent
        else if CaptionIsOn()
            m.pauseCaptionsBg.color = "0x51407AF2"
        else
            m.pauseCaptionsBg.color = idle
        end if
    end if
    if m.pauseCaptionsText <> invalid then m.pauseCaptionsText.text = "CC"
end sub

function CaptionIsOn() as boolean
    if m.video = invalid or not m.video.HasField("globalCaptionMode") then return false
    mode = m.video.globalCaptionMode
    return mode <> invalid and LCase(mode) <> "off"
end function

function CurrentCaptionTrack() as string
    if m.video = invalid then return ""
    ' Ask Roku first: it may auto-select an embedded track after the app's
    ' pre-play add-on selection, so the cached request is not always what is
    ' actually rendering.
    if m.video.HasField("currentSubtitleTrack")
        current = m.video.currentSubtitleTrack
        if current <> invalid and Type(current) = "roString" and current <> "" then return current
    end if
    if m.captionSelection <> invalid and m.captionSelection <> "" then return m.captionSelection
    if m.video.HasField("subtitleTrack")
        selected = m.video.subtitleTrack
        if selected <> invalid and Type(selected) = "roString" then return selected
    end if
    return ""
end function

function SubtitleTrackNamesMatch(leftName as dynamic, rightName as dynamic) as boolean
    leftText = LCase(StringOf(leftName).Trim())
    rightText = LCase(StringOf(rightName).Trim())
    return leftText <> "" and leftText = rightText
end function

' Resolve a candidate through the list Roku is displaying. The media player can
' expose a live identifier only after playback begins, while the app also keeps
' the pre-play URL/track it requested. Validate each source against this exact
' list so a stale or reformatted identifier cannot leave every row unchecked.
function CaptionTrackFromList(tracks as object, candidate as dynamic) as string
    if tracks = invalid or StringOf(candidate).Trim() = "" then return ""
    for each track in tracks
        trackName = StringOf(track.Lookup("TrackName")).Trim()
        if trackName = "" then trackName = StringOf(track.Lookup("trackName")).Trim()
        if SubtitleTrackNamesMatch(trackName, candidate) then return trackName
    next
    return ""
end function

function SelectedCaptionTrackFromList(tracks as object) as string
    if m.video = invalid then return ""
    if m.video.HasField("currentSubtitleTrack")
        matched = CaptionTrackFromList(tracks, m.video.currentSubtitleTrack)
        if matched <> "" then return matched
    end if
    matched = CaptionTrackFromList(tracks, m.captionSelection)
    if matched <> "" then return matched
    if m.video.HasField("subtitleTrack")
        matched = CaptionTrackFromList(tracks, m.video.subtitleTrack)
        if matched <> "" then return matched
    end if
    return ""
end function

' Side-loaded add-on captions identify themselves with their download URL.
' Roku's in-stream identifiers use a source/id pair such as mkv/english1,
' dash/..., or eia608/1. The URL boundary also covers future stream sources.
function IsEmbeddedSubtitleTrack(track as dynamic) as boolean
    if track = invalid then return false
    trackName = StringOf(track.Lookup("TrackName")).Trim()
    if trackName = "" then trackName = StringOf(track.Lookup("trackName")).Trim()
    if trackName = "" then return false
    lowered = LCase(trackName)
    ' Roku prefixes side-loaded URLs after playback starts (for example
    ' <dev_3_0>https://...). Search the whole identifier, not only its start,
    ' or an external SRT is mistaken for an embedded stream track.
    if Instr(0, lowered, "http://") >= 0 then return false
    if Instr(0, lowered, "https://") >= 0 then return false
    return Instr(0, trackName, "/") > 0
end function

' Compare the two-letter Roku locale with either ISO-639-1 or the common
' ISO-639-2 codes found in MKV tracks.
function SubtitleLanguageFamily(value as dynamic) as string
    language = LCase(StringOf(value).Trim())
    if language = "" then return ""
    if Instr(0, language, "_") = 2 or Instr(0, language, "-") = 2 then return Left(language, 2)
    aliases = {
        eng: "en", spa: "es", fre: "fr", fra: "fr", ger: "de", deu: "de"
        ita: "it", por: "pt", rus: "ru", jpn: "ja", kor: "ko", chi: "zh"
        zho: "zh", ara: "ar", hin: "hi", dut: "nl", nld: "nl", pol: "pl"
        tur: "tr", swe: "sv", nor: "no", dan: "da", fin: "fi", cze: "cs"
        ces: "cs", hun: "hu", rum: "ro", ron: "ro", gre: "el", ell: "el"
        heb: "he", ind: "id", tha: "th", vie: "vi", ukr: "uk"
    }
    if aliases.DoesExist(language) then return aliases[language]
    return language
end function

function PreferredEmbeddedSubtitleTrack(tracks as object) as dynamic
    if tracks = invalid then return invalid
    wanted = SubtitleLanguageFamily(DeviceLocale())
    wantedOrdinal = 1
    if m.captionPreferenceSet and m.captionPreferenceEnabled and m.captionPreferenceEmbedded
        preferred = SubtitleLanguageFamily(m.captionPreferenceLanguage)
        if preferred <> "" then wanted = preferred
        wantedOrdinal = m.captionPreferenceOrdinal
        if wantedOrdinal < 1 then wantedOrdinal = 1
    end if

    firstEmbedded = invalid
    firstEnglish = invalid
    firstWanted = invalid
    wantedCount = 0
    for each track in tracks
        if IsEmbeddedSubtitleTrack(track)
            if firstEmbedded = invalid then firstEmbedded = track
            language = SubtitleLanguageFamily(track.Lookup("language"))
            if language = "en" and firstEnglish = invalid then firstEnglish = track
            if wanted <> "" and language = wanted
                wantedCount = wantedCount + 1
                if firstWanted = invalid then firstWanted = track
                if wantedCount = wantedOrdinal then return track
            end if
        end if
    next
    if firstWanted <> invalid then return firstWanted
    if firstEnglish <> invalid then return firstEnglish
    return firstEmbedded
end function

' Embedded subtitles arrive only after Roku opens the stream. Prefer them
' automatically because their timing and authored placement belong to this
' exact video. Explicit Off/external choices still win; an explicit embedded
' choice is rematched by language on the next episode.
sub onAvailableSubtitleTracksChanged()
    if m.video = invalid then return
    if m.captionPreferenceSet and (not m.captionPreferenceEnabled or not m.captionPreferenceEmbedded) then return
    tracks = m.video.availableSubtitleTracks
    embedded = PreferredEmbeddedSubtitleTrack(tracks)
    if embedded = invalid then return
    trackName = StringOf(embedded.Lookup("TrackName")).Trim()
    if trackName = "" then trackName = StringOf(embedded.Lookup("trackName")).Trim()
    if trackName = "" then return
    if CaptionIsOn() and SubtitleTrackNamesMatch(CurrentCaptionTrack(), trackName) then return
    m.captionSelection = trackName
    if m.video.HasField("subtitleTrack") then m.video.subtitleTrack = trackName
    SetCaptionMode("on")
    print "[captions] preferred embedded track -> " ; trackName
    UpdatePausedControlFocus()
end sub

' Caption selection lives in the player chrome as well as Roku's * dialog. The
' list comes from Video.availableSubtitleTracks, so it includes both add-on SRT/
' TTML tracks and embedded tracks discovered after playback begins.
sub ShowCaptionChoice()
    if m.video = invalid then return
    tracks = []
    if m.video.HasField("availableSubtitleTracks") and m.video.availableSubtitleTracks <> invalid
        tracks = m.video.availableSubtitleTracks
    end if
    captionOn = CaptionIsOn()
    selectedTrack = SelectedCaptionTrackFromList(tracks)
    mark = Chr(10003) + "  "
    offLabel = Lang("player", "captionsOff")
    selectedButton = 0
    if not captionOn then offLabel = mark + offLabel
    buttons = [offLabel]
    m.captionDialogTracks = []
    languageCounts = {}
    for each track in tracks
        trackName = StringOf(track.Lookup("TrackName"))
        if trackName = "" then trackName = StringOf(track.Lookup("trackName"))
        if trackName <> ""
            description = StringOf(track.Lookup("Description"))
            if description = "" then description = Lang("player", "captionsFallback")
            embedded = IsEmbeddedSubtitleTrack(track)
            displayDescription = description
            if embedded then displayDescription = description + " · " + Lang("player", "captionsEmbedded")
            language = LCase(StringOf(track.Lookup("language")).Trim())
            label = LCase(description.Trim())
            identity = language
            if identity = "" then identity = label
            ordinal = 1
            if languageCounts.DoesExist(identity) then ordinal = languageCounts[identity] + 1
            languageCounts[identity] = ordinal
            if captionOn and SubtitleTrackNamesMatch(trackName, selectedTrack)
                displayDescription = mark + displayDescription
                selectedButton = buttons.Count()
            end if
            buttons.Push(displayDescription)
            m.captionDialogTracks.Push({
                trackName: trackName
                language: language
                label: label
                ordinal: ordinal
                embedded: embedded
            })
        end if
    next
    buttons.Push(Lang("common", "cancel"))
    dialog = CreateObject("roSGNode", "StandardMessageDialog")
    dialog.title = Lang("player", "captions")
    dialog.buttons = buttons
    dialog.ObserveField("buttonSelected", "onCaptionChoice")
    m.top.GetScene().dialog = dialog
    if dialog.HasField("focusButton") then dialog.focusButton = selectedButton
end sub

sub onCaptionChoice()
    scene = m.top.GetScene()
    if scene = invalid or scene.dialog = invalid then return
    index = scene.dialog.buttonSelected
    scene.dialog = invalid
    if index = 0
        if m.video.HasField("globalCaptionMode") then m.video.globalCaptionMode = "Off"
        m.captionSelection = ""
        m.captionPreferenceSet = true
        m.captionPreferenceEnabled = false
        RememberCaptionPreferenceTitle()
        UpdatePausedControlFocus()
        return
    end if
    trackIndex = index - 1
    if m.captionDialogTracks = invalid or trackIndex < 0 or trackIndex >= m.captionDialogTracks.Count() then return
    selection = m.captionDialogTracks[trackIndex]
    m.captionSelection = selection.trackName
    m.captionPreferenceSet = true
    m.captionPreferenceEnabled = true
    m.captionPreferenceLanguage = selection.language
    m.captionPreferenceLabel = selection.label
    m.captionPreferenceOrdinal = selection.ordinal
    m.captionPreferenceEmbedded = selection.embedded
    RememberCaptionPreferenceTitle()
    if m.video.HasField("subtitleTrack") then m.video.subtitleTrack = selection.trackName
    if m.video.HasField("globalCaptionMode") then m.video.globalCaptionMode = "On"
    UpdatePausedControlFocus()
end sub

sub RememberCaptionPreferenceTitle()
    m.captionPreferenceMetaId = ""
    if m.playParams <> invalid then m.captionPreferenceMetaId = StringOf(m.playParams.metaId)
end sub

sub ResetCaptionPreference()
    m.captionPreferenceSet = false
    m.captionPreferenceEnabled = false
    m.captionPreferenceLanguage = ""
    m.captionPreferenceLabel = ""
    m.captionPreferenceOrdinal = 1
    m.captionPreferenceEmbedded = false
    m.captionPreferenceMetaId = ""
end sub

sub onPlayerUiTick()
    UpdateSeekDisplay()
end sub

' Keep the timeline independent of Roku's native trick-play chrome. The Video
' node still reports position/duration while paused, so the bar remains exact
' after a seek and on resumed Continue Watching playback.
sub UpdateSeekDisplay()
    if m.video = invalid then return
    position = m.video.position
    duration = m.video.duration
    if position = invalid or position < 0 then position = 0
    if duration = invalid or duration < 0 then duration = 0
    ' While scrubbing, the marker is a preview. Do not write Video.seek until
    ' OK confirms it; an immediate write leaves paused state after one press and
    ' is why the old timeline could move only once.
    if m.seekDirty then position = m.seekTarget
    fraction = 0
    if duration > 0 then fraction = position / duration
    if fraction < 0 then fraction = 0
    if fraction > 1 then fraction = 1
    width = Int(1560 * fraction)
    if m.seekFill <> invalid then m.seekFill.width = width
    if m.seekKnob <> invalid then m.seekKnob.translation = [width - 8, 1]
    if m.seekElapsed <> invalid then m.seekElapsed.text = PlaybackTime(position)
    if m.seekDuration <> invalid then m.seekDuration.text = PlaybackTime(duration)
end sub

function PlaybackTime(value as dynamic) as string
    if value = invalid or value < 0 then value = 0
    total = Int(value)
    hours = Int(total / 3600)
    minutes = Int((total mod 3600) / 60)
    seconds = total mod 60
    minuteText = minutes.ToStr()
    if hours > 0 and minutes < 10 then minuteText = "0" + minuteText
    secondText = seconds.ToStr()
    if seconds < 10 then secondText = "0" + secondText
    if hours > 0 then return hours.ToStr() + ":" + minuteText + ":" + secondText
    return minuteText + ":" + secondText
end function

sub AdjustTimeline(direction as integer, coarse as boolean)
    if m.video = invalid then return
    duration = m.video.duration
    if duration = invalid or duration <= 0 then return
    if not m.seekDirty
        m.seekTarget = 0
        if m.video.position <> invalid then m.seekTarget = Int(m.video.position)
    end if
    ' Normal arrows move one percent of the program (at least ten seconds), so
    ' holding a direction can cross the whole timeline. FF/RW move ten percent.
    stepSize = Int(duration / 100)
    if stepSize < 10 then stepSize = 10
    if coarse
        stepSize = Int(duration / 10)
        if stepSize < 60 then stepSize = 60
    end if
    target = m.seekTarget + (direction * stepSize)
    if target < 0 then target = 0
    if duration <> invalid and duration > 0 and target > duration - 1 then target = Int(duration - 1)
    m.seekTarget = target
    m.seekDirty = true
    UpdateSeekDisplay()
    ArmControlsHide()
end sub

' Roku reports a held direction as one key-down followed later by key-up on
' devices that do not synthesize repeat presses. Own the repeat cadence so the
' marker keeps travelling for as long as the viewer holds the button.
sub StartSeekRepeat(direction as integer, coarse as boolean)
    if m.seekRepeatActive and m.seekRepeatDirection = direction and m.seekRepeatCoarse = coarse then return
    StopSeekRepeat()
    m.seekRepeatActive = true
    m.seekRepeatDirection = direction
    m.seekRepeatCoarse = coarse
    m.seekRepeatTicks = 0
    AdjustTimeline(direction, coarse)
    if m.seekRepeat <> invalid
        m.seekRepeat.control = "stop"
        m.seekRepeat.control = "start"
    end if
end sub

sub StopSeekRepeat()
    m.seekRepeatActive = false
    m.seekRepeatDirection = 0
    m.seekRepeatTicks = 0
    if m.seekRepeat <> invalid then m.seekRepeat.control = "stop"
end sub

sub onSeekRepeat()
    if not m.seekRepeatActive then return
    if m.video = invalid
        StopSeekRepeat()
        return
    end if
    state = m.video.state
    if (state <> "paused" and state <> "playing") or not m.controlsVisible or m.pauseActionIndex <> 0
        StopSeekRepeat()
        return
    end if
    m.seekRepeatTicks = m.seekRepeatTicks + 1
    ' Accelerate a held arrow in stages: fine control first, then increasingly
    ' fast travel so a viewer can cross a long episode without dozens of taps.
    moves = 1
    if m.seekRepeatTicks >= 28
        moves = 8
    else if m.seekRepeatTicks >= 17
        moves = 4
    else if m.seekRepeatTicks >= 8
        moves = 2
    end if
    for moveIndex = 1 to moves
        AdjustTimeline(m.seekRepeatDirection, m.seekRepeatCoarse)
    end for
end sub

sub CommitTimelineSeek()
    StopSeekRepeat()
    if m.video = invalid then return
    if not m.seekDirty
        if m.controlsPaused then m.video.control = "resume" else HidePausedControls()
        return
    end if
    if not m.video.HasField("seek") then return
    if m.video.HasField("autoplayAfterSeek") then m.video.autoplayAfterSeek = true
    target = m.seekTarget
    m.seekDirty = false
    HidePausedControls()
    m.video.seek = target
end sub

' Stremio's explicit NextVideo action adapted to the Roku remote. A warm result
' swaps immediately. If the viewer is early and nothing is warm yet, hold the
' current frame and finish the same-provider prefetch before swapping.
sub PlayNextFromPause()
    if not m.pauseHasNext then return
    HidePausedControls()
    StopTorrentStats()
    if m.nextPrepared <> invalid
        StartNextEpisode()
        return
    end if

    m.playNextWhenReady = true
    m.status.text = Lang("player", "preparingNextEpisode")
    if m.nextWaitTimeout <> invalid
        m.nextWaitTimeout.control = "stop"
        m.nextWaitTimeout.control = "start"
    end if
    if m.nextPrefetchStarted then return
    nextParams = NextEpisodeParams()
    if nextParams = invalid
        m.playNextWhenReady = false
        return
    end if
    LaunchNextPrefetch(nextParams, -1)
end sub

' Kick stream resolution off the render thread. The task frees the UI while the
' torrent engine warms or an ambiguous direct URL gets a short format probe.
'
' Season and episode go across as INTEGERS, not as the name fragments the server
' will match release names against. Two reasons, and the second is the one that
' bites: the fragments are the streaming server's protocol, so the store builds
' them; and a Task field is assigned through AddReplace, which enforces its
' declared type and rejects an array on the device with a runtime "Type
' mismatch" the test suite cannot see.
sub StartResolve(stream as object, serverAddress as dynamic, season = 0 as integer, episode = 0 as integer)
    if stream = invalid then
        m.status.text = Lang("player", "sourceUnavailable")
        return
    end if
    if serverAddress = invalid then serverAddress = ""
    ' The pre-video wait starts here, so its label does too. StartSubtitles runs
    ' on the very next line of OnEnter and overwrites this with the drain's own
    ' moving counter whenever there is a provider to ask — which is why a play
    ' WITH subtitle add-ons never actually sees this line. It survives only when
    ' there is nothing to drain (no subtitle add-on, a live channel), where the
    ' alternative is a blank status line under the pulsing logo for the whole of a
    ' torrent warm-up.
    m.status.text = PreVideoWaitLabel()
    task = AsyncTask_Launch(m.top, "StreamResolveTask", "onResolveResult", {
        stream: stream
        serverAddress: serverAddress
        season: season
        episode: episode
        audioPassthrough: AudioPassthroughEnabled()
        audioTransmux: AudioTransmuxEnabled()
        directPlayMode: m.playMode
    }, "playerResolve")
    m.resolveTask = task
end sub

' Whether the streaming server may copy the audio instead of re-encoding it.
' Read here, where the stores are reachable: a Task gets its input as fields
' and cannot ask the store itself. The names are literals on purpose — the
' static check that catches a mistyped callFunc is what stands between a
' typo and the device's &hf4.
function AudioPassthroughEnabled() as boolean
    if m.stores = invalid then return false
    return m.stores.settings.callFunc("SettingsGetAudioPassthrough")
end function

function AudioTransmuxEnabled() as boolean
    if m.stores = invalid then return false
    return m.stores.settings.callFunc("SettingsGetAudioTransmux")
end function

function DirectPlayModeSetting() as string
    if m.stores = invalid then return "off"
    mode = m.stores.settings.callFunc("SettingsGetDirectPlayMode")
    if mode = "on" or mode = "ask" or mode = "off" then return mode
    return "off"
end function

' Season and episode as whole numbers, 0 when the play has neither. Coerced
' rather than passed through because the Task fields are declared integer and
' AddReplace will not coerce a float on the player's behalf.
function ResolveOrdinal(value as dynamic) as integer
    if value = invalid then return 0
    try
        return Int(value)
    catch notANumber
        return 0
    end try
end function

' Start the pre-video pulse. Its lifetime is the whole of playback preparation
' — the stream resolve (a torrent's engine warm-up happens inside the resolve
' task, so it is covered here too), and the caption drain that continues after
' the resolve returns — NOT just the resolve. It is started once, on entry, and
' is stopped only where playback is handed over to the platform or where no
' video will follow at all; nothing in between restarts it.
'
' The lifetime is the whole point. A restart rewinds the 3s animation to its
' first keyframe, and the beat visibly jumps — as a flicker, not a pulse. Tying
' the stop to the resolve boundary is what forced that restart the moment the
' caption drain pushed pre-video work past the resolve; keep the boundary where
' the WORK ends, not where one subroutine happens to return.
sub StartPreVideoPulse()
    if m.preVideoPulse = invalid then return
    ' The pulse is logoBack alone — the front (reveal) copy is hidden so it can't
    ' sit solid on top and mask the beat. StopPreVideoPulse brings it back for the
    ' buffering fill.
    if m.logoFront <> invalid then m.logoFront.visible = false
    m.preVideoPulse.control = "stop"
    m.preVideoPulse.control = "start"
end sub

' The end of the pre-video phase, and the only way the pulse is ever stopped
' from a running state. Freeze it and restore the resting buffering pose: the
' back returns to its faint opacity (0.22), the solid front is back on top but
' fully clipped so it is "not shown" yet — onBufferingStatusChanged reveals it
' from the left as buffering % arrives.
'
' Called at the handoff to the platform (both play paths, in onPlayKickFire and
' MaybeReleaseHeldPlay), when buffering takes over, and on the exits where the
' resolve fails — see onResolveResult for why it is deliberately NOT called when
' the resolve task merely returns.
sub StopPreVideoPulse()
    if m.preVideoPulse <> invalid then m.preVideoPulse.control = "stop"
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
'
' The handoff to the player is wrapped in a try. Uncaught, a throw between here
' and the first frame killed playback with nothing on screen to say why — the
' status line kept whatever the pre-resolve text was, so a dead player and a
' player that had not started yet looked identical. This says which it was.
sub onResolveResult()
    if m.resolveTask = invalid then return
    task = m.resolveTask
    m.resolveTask = invalid
    result = task.result
    try
        AsyncTask_Reap(task, m.top, false)
        ' The pulse is deliberately NOT stopped here. Its lifetime is the whole
        ' pre-video phase — the resolve, the engine warm-up just below, and the
        ' caption drain that outlives this call — so it runs on into playback
        ' and is ended where playback is actually handed over (the play paths)
        ' or where no video follows at all (the two exits at the bottom of this
        ' function). Stopping it here is what used to freeze the logo at the
        ' resolve boundary and force a restart, and a restart rewinds the
        ' animation to its first keyframe: that rewind is the flicker.

        ' The engine warm-up, printed on both paths and unconditionally within
        ' them. The transport trace deliberately stays quiet about a 2xx, so
        ' without this line a warm-up that worked leaves no trace at all — and
        ' "did the HEAD reach the server" is the first thing to establish when a
        ' torrent is slow to start, since everything downstream of it assumes the
        ' engine exists.
        '
        ' `trackers` is the field that decides what the answer meant. A cold engine
        ' given trackers resolves in seconds; one given none has DHT alone to find
        ' metadata, which is a wait no timeout here should be tuned against.
        '
        ' `range` is the second request in that warm-up: a ranged GET of the first
        ' 64KB of the file, which is what actually waits out the metadata. The HEAD
        ' above only reports that the engine was CREATED — it returns in
        ' milliseconds and says nothing about whether the engine can then answer.
        ' Printed next to it because the pair is the diagnosis: HEAD 200 with a
        ' dead range means the engine was created and never became ready (the
        ' stream is not coming), and both 200 means the engine was ready and
        ' anything after this is the player''s own problem.
        if result <> invalid and result.warmup <> invalid then
            warmTrackers = -1
            if result.warmup.trackers <> invalid then warmTrackers = result.warmup.trackers
            warmIdx = -1
            if result.warmup.fileIdx <> invalid then warmIdx = result.warmup.fileIdx
            print "[resolve] engine warm-up HEAD -> status=" ; result.warmup.status ; " ok=" ; result.warmup.ok ; " trackers=" ; warmTrackers ; " fileIdx=" ; warmIdx ; " error=[" ; result.warmup.error ; "]"
            ' Printed on its own line rather than folded into the one above, because
            ' a range of `invalid` is a warm-up that never got to run the request
            ' and concatenating a missing field would throw &h18 — the same trap
            ' MainScene.onAddonSyncResult documents.
            if result.warmup.range <> invalid then
                print "[resolve] engine metadata read -> status=" ; result.warmup.range.status ; " ok=" ; result.warmup.range.ok ; " error=[" ; result.warmup.range.error ; "]"
            end if
        end if

        ' The probe's own account, and it is printed for the SUCCESS case too. That used to
        ' be gated to the failure branch on the reasoning that a probe which gave up
        ' is always an unsuccessful resolve — which is true, and which meant the
        ' successful case reported nothing at all. A play that timed out once and
        ' then recovered on attempt 2 is a SUCCESS, so its one timeout was visible
        ' only as a stray [http] line with nothing to say how many attempts it took
        ' or what the first one answered. That is exactly the distinction needed to
        ' tell a cold engine (first attempt expires, engine not ready yet) from a
        ' flaky link (an already-warm engine still loses a request), and it was the
        ' thing that made the two indistinguishable in the log.
        '
        ' Read only when result is known valid: a field read on invalid throws &h18
        ' (the trap MainScene.onAddonSyncResult documents). Printed only when the
        ' probe took more than one attempt — a first-try success is the expected
        ' case and printing it every play would be noise, so its absence from the
        ' log IS the signal that nothing went wrong.
        if result <> invalid and result.probe <> invalid then
            probeStatus = -1
            if result.probe.status <> invalid then probeStatus = result.probe.status
            probeAttempts = 0
            if result.probe.attempts <> invalid then probeAttempts = result.probe.attempts
            if result.probe.gaveUp = true then
                print "[resolve] probe gave up after " ; probeAttempts ; " attempt(s) — status=" ; probeStatus ; " firstError=[" ; result.probe.firstError ; "] body=" ; Left(result.probe.body, 200)
            else if probeAttempts > 1 then
                print "[resolve] probe recovered after " ; probeAttempts ; " attempt(s) — status=" ; probeStatus ; " firstError=[" ; result.probe.firstError ; "]"
            end if
        end if

        if result = invalid or not result.ok or result.url = invalid or result.url = ""
            m.status.text = Lang("player", "sourceUnavailable")
            ' No video follows, so nothing downstream will end the pulse: this
            ' exit ends it.
            StopPreVideoPulse()
            return
        end if

        StartPlayback(result.url, result.streamFormat, result.requestHeaders)
    catch e
        ' Printed on purpose: this catch used to swallow the failure in silence,
        ' which is how a dead player came to look exactly like one still
        ' preparing — the pulse frozen, and the caption drain overwriting the
        ' status line set below. A caught handoff failure must always name itself.
        print "[video] handoff FAILED (caught): " ; e.message
        m.status.text = Lang("player", "couldNotStart")
        ' Same as the failure exit above: a play that never starts leaves the
        ' pulse with nothing to hand off to.
        StopPreVideoPulse()
    end try
end sub

sub CancelResolve()
    if m.resolveTask <> invalid
        task = m.resolveTask
        m.resolveTask = invalid
        AsyncTask_Reap(task, m.top, true)
    end if
    StopPreVideoPulse()
end sub


' Kick the caption fetch off the render thread.
'
' The drain is SEQUENTIAL and playback waits for it: one provider in flight at a
' time, the next launched from onSubtitleResult, and StartPlayback's first
' `control = "play"` is held until the drain finishes (onPlayKickFire, budget
' m.subtitleHoldMaxTicks — twelve 0.25s ticks). That ordering is the point:
' SubtitleTracks on the ContentNode before the pump starts is the only path Roku
' reliably accepts, and a track array applied to a node the video is already
' playing is a mid-play mutation that hangs it. A result that does land after
' playback has started is dropped instead (see onSubtitleResult).
'
' The candidate list comes from SubtitlesAddresses, which RANKS by what a
' provider is rather than taking whatever the registry happened to yield first.
'
' Every ranked provider is asked, in that order, and their tracks are MERGED
' rather than raced: first provider's captions are usable after one round trip,
' and each later provider only adds to them. So the ranking decides which captions
' appear first in the list and which provider's pick wins by default, not which
' provider is the only one that gets a say — a provider that cannot answer costs
' one round trip and contributes nothing rather than ending the search.
sub StartSubtitles(params as object)
    if m.stores = invalid then return
    if m.subtitleTask <> invalid then return
    if params.metaType = invalid or params.videoId = invalid then return
    if params.metaType = "" or params.videoId = "" then return

    ' A merge is append-only, so it has to start from nothing. Reusing the
    ' previous play's tracks would mix two videos' captions into one list and
    ' leave m.subtitleIndex pointing into the older half.
    m.subtitleTracks = invalid
    m.subtitleIndex = -1
    m.subtitleNodesApplied = false

    m.subtitleParams = { metaType: params.metaType, videoId: params.videoId }
    m.subtitleCandidates = SubtitlesAddresses(m.stores.addons.callFunc("AddonsGetAll"))
    m.subtitleCursor = 0
    ' What this play's drain is able to report when it ends. `reached` counts the
    ' providers that actually produced an HTTP response; `tried` counts every
    ' provider asked. The pair is what separates "nobody has captions for this
    ' title" (tried > 0, reached > 0) from "we could not get to anyone" (tried >
    ' 0, reached = 0) — the two are the same empty list to the player and only one
    ' of them is worth telling the user about.
    m.subtitleReached = 0
    m.subtitleTried = 0
    print "[subs] enter " ; params.metaType ; "/" ; params.videoId ; " — registry has " ; AddonsCount() ; " addon(s), " ; m.subtitleCandidates.Count() ; " offer subtitles"
    LaunchSubtitleFetch()
end sub

' Playback is waiting on the caption drain and the drain is done: play now
' instead of making the user sit out the rest of the budget. The tracks are
' already on the content node by every path that reaches here, so this is the
' last thing that happens before `control = "play"`.
sub MaybeReleaseHeldPlay()
    if not m.playArmed then return
    m.playArmed = false
    m.subtitleHoldTicks = 0
    if m.video = invalid then return
    m.playStarted = true
    StopPreVideoPulse()
    m.video.control = "play"
end sub

' The caption drain has nothing left to ask. Two things follow, in this order:
' the status line stops naming the drain — the work it names is finished — and a
' play that was holding for exactly this drain is released.
'
' Both drain-exhaustion points route through here rather than calling
' MaybeReleaseHeldPlay directly, because there are two of them (a provider with
' nothing to give, and the last provider's tracks landing), and the status handoff
' is wanted on both.
sub DrainSettled()
    UpdatePreVideoStatus()
    MaybeReleaseHeldPlay()
end sub

' Hand the status line back to whatever the play is still waiting on. It only
' speaks while the RESOLVE is still out and playback has not been handed over: past
' that point the platform's buffering UI owns the screen and clears the line itself
' (onVideoStateChanged), and a resolve that fails writes its own message over this
' one.
'
' This exists because the pre-video wait has two workers and only one of them says
' anything. The caption drain writes "Loading subtitles x/n…"; when the drain ends
' on a torrent the resolve is usually still out, so before this the last counter
' sat on screen naming work that had already finished, for the whole of a torrent
' engine warm-up that can run for a minute.
sub UpdatePreVideoStatus()
    if m.playStarted then return
    if m.resolveTask = invalid then return
    m.status.text = PreVideoWaitLabel()
end sub

' What the screen says while it is preparing a stream and nothing more specific
' applies. Deliberately vague about which half is slow: one label covers a torrent
' engine warm-up and a direct URL that is merely taking its time, and it is never
' shown alongside the drain's own counter.
function PreVideoWaitLabel() as string
    return Lang("player", "preparingStream")
end function

sub Notify(message as string, kind = "info" as string)
    scene = m.top.getScene()
    if scene <> invalid then scene.callFunc("Notify", message, kind)
end sub

' How many add-ons the registry holds right now. Reporting it separately from the
' subtitle count is the whole diagnostic: a provider list of 0 against a registry
' of 12 means the ranking found nothing to ask, and a registry of 0 means the
' snapshot was taken before the sync registered anything (see
' EnsureSubtitleProviders). Print, because this app is debugged over telnet.
function AddonsCount() as integer
    addons = m.stores.addons.callFunc("AddonsGetAll")
    if addons = invalid then return 0
    return addons.Count()
end function

' The display name of the add-on behind an address, or "" when the registry no
' longer holds that address. The subtitle queue ranks addresses, but a failure
' toast that named only the address would lecture with a URL; the name is what
' the user installed and recognises.
function SubtitleProviderName(address as string) as string
    addons = m.stores.addons.callFunc("AddonsGetAll")
    if addons = invalid then return ""
    for each addon in addons
        if addon <> invalid and addon.address <> invalid and addon.address = address
            ' StringOf: the registry's name is manifest JSON, and this one is read
            ' back out as a string for a toast.
            name = StringOf(addon.name)
            if name <> "" then return name
        end if
    end for
    return ""
end function

' The provider list was snapshotted once, at OnEnter — during the stream resolve,
' which is the busiest moment in the app's startup. When the add-on sync has not
' registered its descriptors by then, SubtitlesAddresses returns an empty list,
' LaunchSubtitleFetch has nothing to ask, MoreSubtitleCandidates is false, and
' SubtitlesAddresses has no other caller: the caption search is over for that
' play and the Options dialog lists nothing, permanently. Nothing had failed, so
' nothing said so — it only ever showed on a stremio session whose subtitle
' provider is an account add-on, because the built-in seeds cover every other case.
'
' MainScene calls this from the two points the registry actually moves (the sync
' install loop, and a Rokumio import), next to its own HomeScreen call. Re-derive
' the list and append whatever is new, so a provider that arrived mid-play is
' asked then and its tracks land on the live node through the existing late-arrival
' path (onSubtitleResult -> ApplySubtitleIndex(invalid)).
'
' Appending, not re-queuing: the cursor only moves forward, so pushing onto the
' tail asks the new provider without re-asking one already tried, and AddressIn
' keeps a provider that merely appears twice from being fetched twice. m.subtitleIndex
' is untouched — onSubtitleResult picks the default once, on the first provider
' that yields tracks, so a list that grows later cannot renumber a selection the
' user has already made.
sub EnsureSubtitleProviders()
    if m.stores = invalid then return
    ' Not a play, or the play is over: OnExit's CancelSubtitles blanked the
    ' params, and there is nothing left to attach captions to.
    if m.subtitleParams = invalid then return
    ' One request in flight at a time. The drain resumes from onSubtitleResult
    ' when this one settles, against a candidate list this call has already
    ' extended, so there is nothing to do but wait.
    if m.subtitleTask <> invalid then return

    fresh = SubtitlesAddresses(m.stores.addons.callFunc("AddonsGetAll"))
    added = 0
    for each address in fresh
        if not AddressIn(m.subtitleCandidates, address)
            m.subtitleCandidates.Push(address)
            added = added + 1
            print "[subs] new provider joined the queue: " ; RedactUrl(address)
        end if
    next
    if added = 0
        print "[subs] registry moved but offered nothing new"
        return
    end if
    print "[subs] resuming: " ; added ; " new provider(s), queue now " ; m.subtitleCandidates.Count() ; " at cursor " ; m.subtitleCursor
    LaunchSubtitleFetch()
end sub

' Is there another ranked provider left to ask? Kept as one predicate because
' two branches need it — a provider that answered with nothing, and a provider
' that answered with something and still has company — and they must agree.
sub MoreSubtitleCandidates() as boolean
    if m.subtitleCandidates = invalid then return false
    return m.subtitleCursor < m.subtitleCandidates.Count()
end sub

' Ask the next queued provider. One candidate is in flight at a time and the
' cursor only ever moves forward, so a registry full of dead providers costs one
' request each and still terminates.
'
' Refused once playback has started: the result would have nowhere safe to go
' (a track array written onto a playing node hangs the video), so asking is only
' wasting the request.
sub LaunchSubtitleFetch()
    if m.subtitleParams = invalid then return
    if m.playStarted then return
    if m.subtitleTask <> invalid then return
    if m.subtitleCandidates = invalid then return
    if m.subtitleCursor >= m.subtitleCandidates.Count() then return

    address = m.subtitleCandidates[m.subtitleCursor]
    m.subtitleCursor = m.subtitleCursor + 1
    if address = invalid or address = "" then
        LaunchSubtitleFetch()
        return
    end if
    m.subtitleAsked = address
    m.subtitleTried = m.subtitleTried + 1
    print "[subs] asking #" ; m.subtitleCursor ; "/" ; m.subtitleCandidates.Count() ; " -> " ; RedactUrl(address)

    ' Progress on the status line, because the drain is now something playback
    ' visibly waits on and a moving counter beats a frozen screen. This line names
    ' the drain, so it is only ever true while the drain runs: when the drain ends
    ' with the resolve still out, DrainSettled hands the line back to the phase
    ' label, and the platform's buffering UI clears it when playback takes over.
    ' Leaving it standing at the end of a drain is what put a finished counter on
    ' screen for the whole of a torrent resolve.
    m.status.text = Fill(Lang("player", "loadingSubtitles"), { loaded: m.subtitleCursor.ToStr(), total: m.subtitleCandidates.Count().ToStr() })

    task = AsyncTask_Launch(m.top, "SubtitleLoaderTask", "onSubtitleResult", {
        addonAddress: address
        metaType: m.subtitleParams.metaType
        videoId: m.subtitleParams.videoId
    }, "playerSubtitles")
    m.subtitleTask = task
end sub

' Ranked list of addresses worth asking for captions, best first.
'
' This used to answer "the first add-on advertising subtitles, and prefer it
' over the built-in" — a winner decided by POSITION, in a list that has no
' position. The registry is an roAssociativeArray, so on a Roku device "the
' first" was whichever entry the hash order produced: a different pick on every
' device, and one no test in this repo could have caught because the brs
' interpreter only has a single ordering. Guest sessions escaped it because the
' two built-in seeds head the list and the winner fell out of that deterministic
' part. A stremio session is hash-ordered end to end, so it was the only session
' where the pick was arbitrary — and the symptom was the working provider
' sitting right there in the registry, never being asked.
'
' Ranked by capability now:
'   1. the official built-in, recognised by ID. The built-in is the one provider
'      proven to need no credentials, so it leads.
'   2. everything else advertising subtitles, ordered by name then id.
'
' Duplicates collapse, so a provider that answered under two records is asked
' once rather than twice.
function SubtitlesAddresses(addons as object) as object
    ranked = []
    rest = []
    if addons = invalid then return ranked
    for each addon in addons
        if addon <> invalid and addon.address <> invalid and addon.address <> ""
            if addon.resources <> invalid and m.stores.addons.callFunc("AddonsHasResource", addon.resources, "subtitles")
                if m.stores.addons.callFunc("AddonsIsBuiltin", addon.id)
                    if not AddressIn(ranked, addon.address) then ranked.Push(addon.address)
                else
                    if not AddressIn(rest, addon.address) then rest.Push(addon.address)
                end if
            end if
        end if
    end for
    SortAddressesByName(rest)
    for each address in rest
        ranked.Push(address)
    end for
    return ranked
end function

function AddressIn(list as object, address as string) as boolean
    if list = invalid then return false
    for each entry in list
        if entry = address then return true
    end for
    return false
end function

' Insertion sort so the tail of the candidate list is ordered by something the
' screen controls outright, rather than by however the registry happened to
' iterate.
sub SortAddressesByName(list as object) as void
    for i = 1 to list.Count() - 1
        item = list[i]
        j = i - 1
        while j >= 0
            if not (list[j] > item) then exit while
            list[j + 1] = list[j]
            j = j - 1
        end while
        list[j + 1] = item
    end for
end sub

' One provider answered. Its tracks are APPENDED to whatever earlier providers
' contributed, and the drain continues: the ranking decides the order tracks
' appear in and which provider's pick wins by default, not which provider gets to
' be the only one with a say. First-hit-wins meant a perfectly good second
' provider was never asked, so a user with one flaky add-on and one good one
' sometimes got captions and sometimes did not, with nothing on screen to explain
' which.
'
' Two properties make append-only safe rather than merely different:
'
'   m.subtitleIndex is chosen ONCE, on the first provider that yields tracks, and
'   never recomputed. Later providers only push to the end of the list, so every
'   index the user could already be looking at still means the same track. A
'   re-pick per provider would renumber the list underneath a selection the user
'   had already made, silently switching them to a different caption.
'
'   BuildSubtitleTracks numbers duplicates per language as it walks the list
'   ("English 1", "English 2"), so two providers offering English produce two
'   distinguishable entries rather than two identical-looking ones. No dedup is
'   wanted: the same caption offered twice is not an error, and dropping the
'   second copy would make the count depend on provider order.
sub onSubtitleResult()
    if m.subtitleTask = invalid then return
    task = m.subtitleTask
    m.subtitleTask = invalid
    result = task.result

    ' An empty result means "not yet", not "nothing to report": `result` is
    ' alwaysNotify with no value, so it also notifies before this worker wrote
    ' anything, and that notification is dispatched on the event loop — i.e. while
    ' the request is still in flight. Reaping here unobserves the field and
    ' removes the node, and removing a running Task does not kill its worker, so
    ' the real answer would land on a node nobody is watching. See
    ' MainScene.onAddonSyncResult for the same defect and the same fix.
    if result = invalid then return
    AsyncTask_Reap(task, m.top, false)

    raw = 0
    if result.subtitles <> invalid then raw = result.subtitles.Count()
    have = 0
    if m.subtitleTracks <> invalid then have = m.subtitleTracks.Count()

    ' Every outcome is reported with its classification, its attempt count and the
    ' transport's own error string. Those three together are what makes this
    ' diagnosable from a telnet trace: `kind` says whether the request could have
    ' been retried, `attempts` says whether it was, and `error` says what actually
    ' happened at the socket — none of which reached the screen before, because the
    ' only test on this branch was `not result.ok`, which cannot tell a timeout
    ' from a 404 from a malformed body.
    kind = "?"
    if result.kind <> invalid then kind = result.kind
    attempts = 0
    if result.attempts <> invalid then attempts = result.attempts
    reached = false
    if result.reached = true then reached = true
    status = -1
    if result.status <> invalid then status = result.status
    if result.reached = true then m.subtitleReached = m.subtitleReached + 1

    if not result.ok or result.subtitles = invalid or result.subtitles.Count() = 0
        print "[subs] " ; RedactUrl(m.subtitleAsked) ; " gave nothing — kind=" ; kind ; " status=" ; status ; " attempts=" ; attempts ; " reached=" ; reached ; " raw=" ; raw ; " error=[" ; result.error ; "] merged so far: " ; have

        ' An empty list from a provider that DID answer is not a fault and gets no
        ' toast: the add-on was asked a well-formed question about this title and
        ' reported it holds no captions, which is an answer, not a failure. Only a
        ' provider that never got to answer is worth apologising for, and by this
        ' point it has already been retried.
        ' The failure is one provider's, not subtitles as a whole: the drain keeps
        ' asking the rest of the queue and tracks merged so far stay put, so a
        ' verdict like "Could not fetch subtitles" would denounce the whole system
        ' for one add-on's answer. Say which add-on could not be reached, in terms
        ' the user would recognise — a URL on a toast reads as noise.
        if not result.ok and (kind = "retry" or kind = "server") then
            name = SubtitleProviderName(m.subtitleAsked)
            if name = "" then
                Notify(Lang("player", "subtitlesOneUnreachable"), "error")
            else
                Notify(Fill(Lang("player", "subtitlesOneUnreachableNamed"), { name: name }), "error")
            end if
        end if

        ' This provider had nothing to give. Another candidate still queued means
        ' the search is not over: choosing the wrong provider must not read the
        ' same as owning no subtitles at all, which is exactly what made an
        ' unreachable pick indistinguishable from a device with no subtitle
        ' add-ons. Tracks already merged from an EARLIER provider are kept — a
        ' later provider coming back empty is not a reason to throw away captions
        ' the user can already see.
        if MoreSubtitleCandidates() then
            LaunchSubtitleFetch()
            return
        end if

        print "[subs] drain exhausted after " ; m.subtitleTried ; " provider(s), " ; m.subtitleReached ; " reached, " ; have ; " track(s)"

        ' The end of the drain is the only place a verdict is possible, and it needs
        ' both counts: tried = 0 means this play never had a provider to ask at
        ' all (nothing to apologise for — EnsureSubtitleProviders will resume the
        ' search if the registry is still filling), and tried > 0 with reached = 0
        ' means every provider was asked and not one of them could be reached. That
        ' last case is worth a word on screen, because the list the Options dialog
        ' shows is empty and otherwise says nothing about why.
        if m.subtitleTried > 0 and m.subtitleReached = 0 then
            Notify(Lang("player", "subtitlesSomeUnreachable"), "error")
        end if

        if m.subtitleTracks = invalid or m.subtitleTracks.Count() = 0 then ClearSubtitles()

        ' Nothing left to wait for: if the play is holding on this drain, this
        ' is its cue to start.
        DrainSettled()
        return
    end if

    ' First tracks of this play? Then this is the one provider whose preference
    ' wins the default pick.
    firstTracks = m.subtitleTracks = invalid or m.subtitleTracks.Count() = 0
    if m.subtitleTracks = invalid then m.subtitleTracks = []
    for each track in result.subtitles
        m.subtitleTracks.Push(track)
    end for
    ' The built array is a snapshot of the raw list, so it has to be rebuilt
    ' before the newly appended tracks can reach the content node.
    m.subtitleNodesApplied = false
    if m.captionPreferenceSet
        if m.captionPreferenceEnabled
            m.subtitleIndex = PreferredSubtitleIndex()
        else
            m.subtitleIndex = -1
        end if
    else
        if firstTracks then m.subtitleIndex = m.subtitlePicker.PickTrack(m.subtitleTracks, DeviceLocale())
    end if

    ' Everyone ranked is still worth asking, even though the list already has
    ' tracks in it.
    if MoreSubtitleCandidates() then LaunchSubtitleFetch()

    if not m.playStarted
        ' Pre-play, on the ContentNode that is about to be handed to the Video:
        ' the one path Roku reliably accepts, and the whole reason the kick held.
        ' The native Options dialog picks the tracks up from the SubtitleTracks
        ' written here.
        ApplySubtitleIndex(invalid)
    else
        ' The gate's last line of defence, and the reason it exists at all: the
        ' tracks are merged for the count, but the array is NOT written onto the
        ' content node. SubtitleTracks on a node the pump is already reading is
        ' a mid-play mutation, and that mutation is what hangs a running video
        ' (buffers forever, or fills and never renders). The next play re-asks
        ' every provider anyway, so nothing is lost permanently.
        print "[subs] DROPPED " ; raw ; " track(s) from " ; RedactUrl(m.subtitleAsked) ; " — playback had already started, and a track array written mid-play hangs the player"
    end if
    picked = SelectedSubtitleTrack()
    usable = "none"
    if picked <> "" then usable = "ok"
    print "[subs] LANDED " ; raw ; " from " ; RedactUrl(m.subtitleAsked) ; " on attempt " ; attempts ; "/3 — merged " ; have ; " + " ; raw ; " = " ; m.subtitleTracks.Count() ; ", picked index " ; m.subtitleIndex ; " (url " ; usable ; ")"

    ' The drain is done (no candidates left) and the tracks are on the content
    ' node: release a play that was holding for exactly this.
    if not MoreSubtitleCandidates() then DrainSettled()
end sub

sub CancelSubtitles()
    m.subtitleCandidates = []
    m.subtitleCursor = 0
    m.subtitleParams = invalid
    m.subtitleAsked = ""
    ' A held kick waiting on this drain must not fire into a play that is ending
    ' (OnExit) — the node is static and would outlive it.
    m.playArmed = false
    m.subtitleHoldTicks = 0
    if m.subtitleTask <> invalid
        task = m.subtitleTask
        m.subtitleTask = invalid
        AsyncTask_Reap(task, m.top, true)
    end if
end sub

' Drop the caption state back to none without touching the Video node's current
' config — a per-play node starts clean, so there is nothing to undo.
sub ClearSubtitles()
    m.subtitleTracks = invalid
    m.subtitleIndex = -1
    m.captionSelection = ""
    m.subtitleNodesApplied = false
end sub

' Push the current subtitle selection onto the video's content. SubtitleTracks is
' content metadata on the ContentNode the Video plays. Roku's native player
' expects each entry as an associative array with TrackName set to the
' downloadable subtitle URL; tracks ride the node PRE-PLAY, which is the
' reliable path and the only one this code uses — onSubtitleResult refuses to
' call this once playback has started, because a track array written onto a node
' the pump is reading is what hangs the video. Selection is matched from the raw
' list by URL because BuildSubtitleTracks drops entries without one, so the pick
' index does not always line up with the built array. Visibility is driven
' through globalCaptionMode (the per-video switch that overrides the device
' caption setting); the native Options dialog takes over track selection from
' there.
sub ApplySubtitleIndex(content as object)
    if content = invalid then content = CurrentContent()
    if content = invalid then return

    if m.subtitleTracks = invalid or m.subtitleTracks.Count() = 0
        ' Nothing is written to the content node here, and that is the whole
        ' point. This runs on the node that is about to become m.video.content,
        ' so an empty subtitleTracks array and an empty subtitleConfig are two
        ' fields handed to the Video node for it to accept or reject on the very
        ' tick that decides whether it plays at all — and an empty collection is
        ' exactly the kind of value a node has cause to refuse. A player with no
        ' captions needs no fields set; it already starts caption-free. Writing
        ' nothing is what the rest of this sub argues for, and this path never
        ' did it.
        SetCaptionMode("off")
        return
    end if

    ' Build the track list BEFORE the content node is touched, and bail out
    ' entirely when it comes back empty. BuildSubtitleTracks drops every entry
    ' without a usable URL, so a provider can hand back a non-empty raw list
    ' that yields nothing playable — and the old order wrote that empty array
    ' onto the LIVE content node anyway, blanking the caption state of a video
    ' that was already playing. Writing nothing at all is the correct answer
    ' when there is no track to select; the player already starts caption-free.
    tracks = invalid
    if not m.subtitleNodesApplied then tracks = BuildSubtitleTracks()
    if tracks <> invalid and tracks.Count() = 0 then
        m.subtitleNodesApplied = false
        ClearSubtitles()
        return
    end if
    if tracks <> invalid
        content.subtitleTracks = tracks
        m.subtitleNodesApplied = true
    end if

    selected = SelectedSubtitleTrack()
    if selected = ""
        content.subtitleConfig = {}
        SetCaptionMode("off")
        return
    end if

    content.subtitleConfig = { TrackName: selected }
    m.captionSelection = selected
    SelectSubtitleTrack(selected)
    ' Force captions on only now, once a track with a real URL is confirmed
    ' selected. Turning captions on over a list the platform cannot load is how
    ' the player ends up in a caption state it cannot leave: the Options dialog
    ' shows entries, every one fails to render, and there is no path back.
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

' Match a user-selected caption across episodes by language and its ordinal
' within that language. Track URLs contain the episode id and cannot be reused.
' Falling back to the first same-language track keeps the preference useful when
' a provider returns fewer duplicate tracks for the next episode.
function PreferredSubtitleIndex() as integer
    if m.subtitleTracks = invalid or not m.captionPreferenceEnabled then return -1
    wantedOrdinal = m.captionPreferenceOrdinal
    if wantedOrdinal < 1 then wantedOrdinal = 1
    firstMatch = -1
    ordinal = 0
    for i = 0 to m.subtitleTracks.Count() - 1
        track = m.subtitleTracks[i]
        language = m.subtitlePicker.TrackLang(track)
        label = LCase(TrackDisplayName(track))
        matches = false
        if m.captionPreferenceLanguage <> ""
            matches = language = m.captionPreferenceLanguage
        else if m.captionPreferenceLabel <> ""
            matches = label = m.captionPreferenceLabel
        end if
        if matches
            ordinal = ordinal + 1
            if firstMatch < 0 then firstMatch = i
            if ordinal = wantedOrdinal then return i
        end if
    end for
    return firstMatch
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
    return Lang("player", "captionsFallback")
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

sub CustomizeVideoNode()
    if m.video = invalid then return

    ApplyCaptionStyle()
    ' Arrow presses only move our preview marker, so seeking stays disarmed
    ' until OK commits it. CommitTimelineSeek flips this back on for the actual
    ' jump; older firmware simply keeps its default behavior.
    if m.video.HasField("autoplayAfterSeek") then m.video.autoplayAfterSeek = false

    ' Before the trick-play tint and independent of it: the native buffering
    ' suppression has to be armed BEFORE playback so the initial retrieving bar is
    ' already opted out when it would otherwise appear. It does not depend on
    ' trickPlayBar, so it cannot live below that guard.
    SuppressNativeBufferingUi()

    ' trickPlayBar is a member READ, and a read of a member the running Roku OS
    ' does not have THROWS — where a set of a missing member (see
    ' enablePositionTracking in StartPlayback) only warns and is discarded. The
    ' throw used to land here, inside CreateVideo, which runs BEFORE
    ' m.video.content is assigned: the player was therefore never handed a URL
    ' at all. What that looks like from the room is the resolve logo pulse ending
    ' on schedule and then nothing playing, with no message, because nothing
    ' failed that anything was watching — the buffer indicator is hidden by the
    ' "finished"/"stopped" state handler, and direct streams and torrents fail
    ' identically because neither ever reached the player.
    '
    ' Guarded the way globalCaptionMode already is below, and additionally
    ' wrapped, because a trick-play bar tint is decoration and decoration is not
    ' allowed to be the reason a video does not start. On a Roku OS that does have
    ' trickPlayBar this changes nothing.
    if not m.video.HasField("trickPlayBar") then return
    try
        m.video.trickPlayBar.filledBarBlendColor = Theme().accent
    catch e
        ' Decoration only. A tint this firmware will not take is not a reason to
        ' refuse playback.
    end try
end sub

' Stremio-style readable captions without the opaque black box. captionStyle is
' a Video field (Roku OS 9.4+); keys omitted here continue to use the viewer's
' system defaults. TTML/DFXP positioning remains owned by Roku's renderer.
sub ApplyCaptionStyle()
    if m.video = invalid or not m.video.HasField("captionStyle") then return
    try
        m.video.captionStyle = {
            "Text/Color": "White"
            "Text/Opacity": "100%"
            "Text/Effect": "Drop shadow (right)"
            "Background/Opacity": "Off"
            "Window/Opacity": "Off"
        }
    catch e
        print "[captions] caption style unavailable on this Roku OS: " ; e.message
    end try
end sub

' The platform's buffering feedback is NOT one widget — it is three internal
' nodes, and the app-owned logo reveal is meant to be the only one on screen:
'
'   - retrievingBar (documented READ_WRITE field, an internal ProgressBar): the
'     bottom bar shown while the stream first loads.
'   - bufferingBar (documented READ_WRITE field, an internal ProgressBar): the
'     bottom bar + percentage shown on a re-buffer.
'
' The app now owns the pause controls and disables built-in UI so center presses
' reach OnKeyEvent. These guards remain for firmware that still instantiates or
' flashes the internal bars during the handoff.
'
' Why it has to be re-run, not done once: the OS re-shows the bars and the wheel
' on EVERY buffer event. A single hide at play start is undone by the first
' re-buffer. So this runs at play start (from CustomizeVideoNode) AND from the
' state observer's "buffering" branch, per event.
'
' It only acts when a logo is present (HasLogo): with no logo the reveal never
' shows, and a stream that shows NO buffering feedback at all is a certification
' risk on slow connections. Without a logo the native indicators stay as the
' fallback.
'
' Everything here is decoration and is guarded as decoration: a READ of a member
' the running OS lacks THROWS, so every field access is wrapped, and a missing
' field, a missing node, or a future OS that renames or drops these internals costs
' only the hide (the wheel simply shows again).
'
' THE ONE RULE THIS FUNCTION MAY NEVER BREAK: it must not throw. It runs inside
' CreateVideo → StartPlayback, which is inside onResolveResult's handoff try, so
' anything that escapes aborts the handoff BEFORE m.video.content is assigned: the
' play dies behind "The player could not start.", the pulse freezes into the dimmed
' logo, and the still-running caption drain overwrites that message — a dead player
' indistinguishable from one that never began. That is not hypothetical; the first
' version of this reached for the wheel with a method roSGNode does not have
' (FindNodesByType), left it unguarded, and stopped every play. Hence the single
' outer try below, ON TOP of the per-step guards: the guards keep one failure from
' stopping the others, the outer try is the guarantee that no failure reaches the
' player.
sub SuppressNativeBufferingUi()
    if m.video = invalid then return
    if not HasLogo() then return
    try
        ' Persistent, set it once and the OS stops auto-showing the initial
        ' retrieving bar for good. Undocumented field, so HasField-guarded: on an
        ' OS without it this is a no-op and the per-event hide below still covers
        ' it.
        if m.video.HasField("retrievingBarVisibilityAuto") then m.video.retrievingBarVisibilityAuto = false
        HideNativeBufferingUi()
    catch e
        ' Failure only, so this never appears in a healthy play's log — but if a
        ' future OS makes this throw, the line says so instead of letting the
        ' suppression vanish silently.
        print "[video] buffering suppression aborted (playback unaffected): " ; e.message
    end try
end sub

' The per-event half: bring the two bars and the wheel back down. Cheap enough to
' call on every buffer event, and idempotent, so there is no bookkeeping about
' what has already been hidden.
sub HideNativeBufferingUi()
    if m.video = invalid then return
    if not HasLogo() then return

    ' bufferingBar/retrievingBar are documented fields, but a READ of either on an
    ' OS that lacks it still throws — hence the wrap, not just a HasField.
    try
        bar = m.video.bufferingBar
        if bar <> invalid then bar.visible = false
    catch e
        print "[video] bufferingBar not hideable on this OS: " ; e.message
    end try
    try
        bar = m.video.retrievingBar
        if bar <> invalid then bar.visible = false
    catch e
        print "[video] retrievingBar not hideable on this OS: " ; e.message
    end try

end sub

' The Video node is declared in XML so Roku owns its native UI lifecycle. The
' screen is a static child reused across plays, so the node outlives a pop and is
' re-armed here on every play.
sub CreateVideo()
    if m.video = invalid then return
    m.video.visible = true
    CustomizeVideoNode()
end sub

' The resolved URL and request headers are the stream-specific data handed to the
' Video node: apply headers, build the content (title, resume offset, resolved
' stream format), then play. Captions do not arrive mid-play: whatever the drain
' has delivered rides the content pre-play, and a result that lands after
' `control = "play"` is dropped rather than written (see onSubtitleResult).
'
' The format is resolved by PlaybackStore and rides the resolve result, the same
' one path a direct URL and a torrent take. It must not be re-sniffed here: Roku
' defaults an unset streamFormat to MP4, so an MKV or an HLS manifest handed over
' with nothing declared buffers and then errors.
sub StartPlayback(url as string, streamFormat = "" as string, requestHeaders = invalid as dynamic)
    m.playArmed = false
    CreateVideo()
    ApplyPlaybackHeaders(requestHeaders)
    ResetRecovery()
    if m.stallWatch <> invalid
        m.stallWatch.control = "stop"
        m.stallWatch.control = "start"
    end if

    content = CreateObject("roSGNode", "ContentNode")
    content.url = url
    ' Belt-and-braces with Video.enableUI=false in XML: content can carry its
    ' own playback-UI preference, and it must not re-enable the native OK menu.
    if content.HasField("VideoDisableUI") then content.VideoDisableUI = true
    params = m.playParams
    title = params.name
    if title = invalid then title = ""
    content.title = title
    startOffset = 0
    if params.position <> invalid and params.position > 0 then startOffset = params.position
    if startOffset > 0 then content.playStart = startOffset
    if streamFormat <> "" then content.streamFormat = streamFormat

    ' Guarded for the same reason trickPlayBar is, and because the warning this
    ' used to print on every single play ("Tried to set nonexistent field
    ' enablepositiontracking") was the loudest thing in the console and buried
    ' anything real. A set of a missing field is discarded, so losing it costs
    ' nothing; position still reads back, it just is not tracked by the node.
    if m.video.HasField("enablePositionTracking") then m.video.enablePositionTracking = true
    ApplySubtitleIndex(content)
    m.video.content = content
    m.video.SetFocus(true)

    ' Play is asked for on the NEXT tick, not this one. Handing the node its
    ' content and its control in the same tick lets it act on `control` before it
    ' has taken the content in, and the symptom of that is precisely the one
    ' being chased: the buffer indicator comes up, the node goes straight to a
    ' terminal state, and nothing plays with no error anywhere to find. A
    ' one-shot timer is a guaranteed tick boundary. m.playArmed makes it at most
    ' one kick per StartPlayback, and disarms a kick still in flight when a new
    ' play starts before it lands.
    ' Armed through `control`, not Start()/Stop(): an roSGNode Timer has no such
    ' methods and calling one is a runtime &hf4 "Member function not found",
    ' which is what the first version of this did — thrown inside StartPlayback,
    ' so the player died on the one function that must never throw.
    m.playArmed = true
    m.subtitleHoldTicks = 0
    if m.playTimer <> invalid
        m.playTimer.control = "stop"
        m.playTimer.control = "start"
    else
        m.playArmed = false
        ' No tick boundary available, so there is nothing to wait across and
        ' nothing to hold: play now. The flag is still set, because the rule the
        ' hold enforces — never write a track array onto a playing node — has to
        ' hold on this path too.
        m.playStarted = true
        StopPreVideoPulse()
        m.video.control = "play"
    end if
end sub

' Replace the Video node's request headers for every play. SetHeaders is on the
' node's ifHttpAgent interface and applies to the native player's URL requests;
' replacing with an empty map also prevents one stream's headers leaking into
' the next. A header API failure must not prevent ordinary direct playback.
sub ApplyPlaybackHeaders(requestHeaders as dynamic)
    if m.video = invalid then return
    if requestHeaders = invalid then requestHeaders = {}
    if Type(requestHeaders) <> "roAssociativeArray" then requestHeaders = {}

    try
        applied = m.video.SetHeaders(requestHeaders)
        if applied <> true
            print "[video] SetHeaders returned false; continuing with " ; requestHeaders.Count() ; " add-on header(s)"
        else if requestHeaders.Count() > 0
            print "[video] applied " ; requestHeaders.Count() ; " add-on playback header(s)"
        end if
    catch e
        print "[video] SetHeaders failed (continuing without add-on headers): " ; e.message
    end try
end sub

' The deferred half of StartPlayback, and where playback waits for captions.
'
' The hold: while this play's subtitle drain can still deliver, the kick re-arms
' itself instead of playing, so the tracks land on the ContentNode pre-play (the
' reliable path) rather than onto a node the pump is already reading. The pulse
' beats through the hold — nothing else on screen says the app is still working —
' and the budget is what ends it if the drain never does.
'
' The budget is spent or the drain drained: either way this ends with exactly
' one `control = "play"`. A spent budget also reaps the drain (CancelSubtitles
' unobserves the task, so a late result can never arrive and can never be
' written mid-play), and the play is flagged started so any result that does
' somehow land afterwards is refused rather than applied.
sub onPlayKickFire()
    if not m.playArmed then return
    m.playArmed = false
    if m.video = invalid then return
    if SubtitlesStillDraining() and m.subtitleHoldTicks < m.subtitleHoldMaxTicks
        m.playArmed = true
        m.subtitleHoldTicks = m.subtitleHoldTicks + 1
        ' The pulse is already beating and simply keeps beating through the hold
        ' — the hold is pre-video work like the resolve is, so it neither starts
        ' nor stops the indicator. See the pulse's charter (StartPreVideoPulse).
        if m.playTimer <> invalid
            m.playTimer.control = "stop"
            m.playTimer.control = "start"
            return
        end if
        ' No timer, no way to wait for it: fall through and play.
    else if m.subtitleHoldTicks >= m.subtitleHoldMaxTicks
        CancelSubtitles()
    end if
    m.playStarted = true
    StopPreVideoPulse()
    m.video.control = "play"
end sub

' True while this play's caption drain can still contribute: a provider is in
' flight, or candidates are still queued. A play with no subtitle providers at
' all (a live channel, or a registry with no subtitle add-on) answers false
' immediately, so playback never waits on behalf of nothing.
function SubtitlesStillDraining() as boolean
    if m.subtitleTask <> invalid then return true
    return MoreSubtitleCandidates()
end function

' The stream format is resolved by PlaybackStore.ResolvePlayback, not sniffed
' here — see StartPlayback for why an unset format is not a safe default.

' Surface playback state on the status line for the grab-before-video resolve
' phase and for failures: a broken stream is a message, not a silent black
' frame. The native chrome owns everything once the platform has a stream.
sub onVideoStateChanged()
    if m.video = invalid then return
    state = m.video.state
    if state = invalid then return
    if state = "playing"
        m.hasPlayed = true
        m.status.text = ""
        HidePausedControls()
        StopTorrentStats()
        HideBuffering()
    else if state = "error" and m.hasPlayed = true and not NotPlayableOnDevice() and m.recoverCount < STALL_MAX_RECOVERIES()
        ' Mid-play failure of a stream that was already playing: almost always
        ' the connection to the host dropping. Reopen at the last good position
        ' instead of leaving a dead player on screen.
        LogVideoError()
        TryRecover("error")
    else if state = "finished" and EndedEarly()
        ' The host closed the connection and the platform read that as the end
        ' of the file. Treat it like a drop, not a real ending.
        TryRecover("early-finish")
    else if state = "error"
        HidePausedControls()
        ' Show the platform's error code on the status line; the diagnosis itself
        ' (category/errcode/dbgmsg) is printed by LogVideoError below. The status
        ' line alone cannot tell a network drop from a format the device refuses,
        ' but a capability verdict (unsupported container/codec on THIS box) gets
        ' its own wording so it is not blamed on the network.
        code = 0
        if m.video.HasField("errorCode") and m.video.errorCode <> invalid then code = m.video.errorCode
        if NotPlayableOnDevice() then
            message = Lang("player", "notPlayable")
        else
            message = Lang("player", "playbackFailed")
        end if
        if code <> 0 then message = Fill(Lang("player", "playbackFailedCode"), { message: message, code: Str(code).Trim() })
        m.status.text = message
        StopTorrentStats()
        HideBuffering()
        LogVideoError()
    else if state = "buffering"
        ' The platform's own buffering UI (wheel + bars) is suppressed in favor of
        ' the app-owned reveal, so the pre-video indicators yield together: the
        ' pulse freezes into the reveal pose, the "Loading subtitles x/n" line
        ' goes, and the native wheel/bars come down so only the logo fill shows.
        ' By the time a play can reach buffering, the drain is over or has been
        ' reaped — nothing is still being waited on.
        StopPreVideoPulse()
        HidePausedControls()
        m.status.text = ""
        StartTorrentStats()
        SuppressNativeBufferingUi()
        if HasLogo() then m.bufferingGroup.visible = true
    else if state = "paused"
        ShowPausedControls()
        PublishWatchState()
    else if state = "finished"
        HidePausedControls()
        StopTorrentStats()
        HideBuffering()
        StartNextEpisode()
    else if state = "stopped"
        if m.pendingPreparedNext <> invalid
            BeginPreparedNext()
            return
        end if
        HidePausedControls()
        StopTorrentStats()
        HideBuffering()
    end if
end sub

' Publish the next regular episode after a genuine end. EndedEarly() is handled
' by the earlier branch in onVideoStateChanged, so a dropped connection can
' never advance the series. The full series meta is cached by EpisodesScreen or
' StreamsScreen; without it there is no safe episode order to infer, and the
' completed player remains where it is.
sub StartNextEpisode()
    if m.nextRequested or m.playParams = invalid or m.stores = invalid then return
    params = m.playParams
    if params.metaType <> "series" then return
    if params.metaId = invalid or params.videoId = invalid then return

    m.nextRequested = true
    if m.nextPrepared <> invalid
        PlayPreparedNext()
        return
    end if

    nextParams = NextEpisodeParams()
    if nextParams = invalid then return
    SavePosition()
    print "[next] prefetch unavailable — opening provider load for " ; nextParams.videoId
    m.top.playbackAction = {
        action: "nextEpisode"
        params: nextParams
    }
end sub

' Pure next-play description shared by background prefetch and the visible
' fallback. It never starts work and never changes playback state.
function NextEpisodeParams() as dynamic
    if m.playParams = invalid or m.stores = invalid then return invalid
    params = m.playParams
    if params.metaType <> "series" or params.metaId = invalid or params.videoId = invalid then return invalid
    meta = m.stores.episodes.callFunc("EpisodesFullMeta", params.metaType, params.metaId)
    if meta = invalid then return invalid
    nextEpisode = m.stores.episodes.callFunc("EpisodesNextEpisode", params.metaId, params.videoId, meta)
    if nextEpisode = invalid then return invalid
    return {
        addonAddress: params.addonAddress
        metaType: "series"
        metaId: params.metaId
        videoId: nextEpisode.videoId
        season: nextEpisode.season
        episode: nextEpisode.episode
        position: 0
        name: params.name
        poster: params.poster
        posterShape: params.posterShape
        logo: params.logo
        background: params.background
        episodeName: nextEpisode.name
        episodeOverview: nextEpisode.overview
        ' Keep these at the top level too: a prepared episode bypasses
        ' StreamsScreen, so its params become the source for the following
        ' episode's prefetch. Without them autoplay is seamless only once.
        providerAddress: params.providerAddress
        streamIndex: params.streamIndex
        directPlayMode: params.directPlayMode
        autoPlay: {
            providerAddress: params.providerAddress
            streamIndex: params.streamIndex
            directPlayMode: params.directPlayMode
        }
    }
end function

' Begin fetching and warming the next episode while the current episode still
' has enough time left to hide a cold torrent engine. Only the same provider is
' asked; failure is silent and leaves StartNextEpisode's existing picker
' fallback intact.
sub MaybePrefetchNext(position as dynamic, duration as dynamic)
    if m.nextPrefetchStarted or m.nextPrepared <> invalid then return
    if position = invalid or duration = invalid or duration <= 0 then return
    remaining = duration - position
    if remaining <= 0 or remaining > 120 then return
    nextParams = NextEpisodeParams()
    if nextParams = invalid or nextParams.autoPlay = invalid then return
    LaunchNextPrefetch(nextParams, remaining)
end sub

sub LaunchNextPrefetch(nextParams as object, remaining as dynamic)
    if m.nextPrefetchStarted or nextParams = invalid or nextParams.autoPlay = invalid then return
    providerAddress = nextParams.autoPlay.providerAddress
    if providerAddress = invalid or providerAddress = "" then return

    m.nextPrefetchStarted = true
    m.nextPrefetch = nextParams
    if remaining <> invalid and remaining >= 0
        print "[next] prefetch streams for " ; nextParams.videoId ; " at " ; Int(remaining) ; "s remaining"
    else
        print "[next] prefetch streams for explicit Next action -> " ; nextParams.videoId
    end if
    m.nextStreamTask = AsyncTask_Launch(m.top, "StreamsLoaderTask", "onNextStreamsLoaded", {
        metaType: "series"
        videoId: nextParams.videoId
        addonAddress: providerAddress
        providerIndex: 0
        providerName: "next"
        loadToken: nextParams.videoId
    }, "nextStreams")
end sub

sub onNextStreamsLoaded()
    if m.nextStreamTask = invalid then return
    task = m.nextStreamTask
    result = task.result
    if result = invalid then return
    m.nextStreamTask = invalid
    AsyncTask_Reap(task, m.top, false)
    if m.nextPrefetch = invalid or result.streams = invalid or result.streams.Count() = 0
        NextPrefetchFailed()
        return
    end if

    index = 0
    wanted = m.nextPrefetch.autoPlay.streamIndex
    if wanted <> invalid and wanted >= 0 and wanted < result.streams.Count() then index = wanted
    m.nextPrefetch.stream = result.streams[index]
    m.nextPrefetch.directPlayMode = m.nextPrefetch.autoPlay.directPlayMode
    m.nextPrefetch.serverAddress = m.playParams.serverAddress
    print "[next] prefetch resolve stream " ; index
    m.nextResolveTask = AsyncTask_Launch(m.top, "StreamResolveTask", "onNextResolveResult", {
        stream: m.nextPrefetch.stream
        serverAddress: m.nextPrefetch.serverAddress
        season: ResolveOrdinal(m.nextPrefetch.season)
        episode: ResolveOrdinal(m.nextPrefetch.episode)
        audioPassthrough: AudioPassthroughEnabled()
        audioTransmux: AudioTransmuxEnabled()
        directPlayMode: m.nextPrefetch.directPlayMode
    }, "nextResolve")
end sub

sub onNextResolveResult()
    if m.nextResolveTask = invalid then return
    task = m.nextResolveTask
    result = task.result
    if result = invalid then return
    m.nextResolveTask = invalid
    AsyncTask_Reap(task, m.top, false)
    if m.nextPrefetch = invalid or not result.ok or result.url = invalid or result.url = ""
        NextPrefetchFailed()
        return
    end if
    m.nextPrefetch.resolvedUrl = result.url
    m.nextPrefetch.streamFormat = result.streamFormat
    m.nextPrefetch.requestHeaders = result.requestHeaders
    m.nextPrepared = m.nextPrefetch
    m.nextPrefetch = invalid
    print "[next] prefetched and ready " ; m.nextPrepared.videoId
    if m.playNextWhenReady then PlayPreparedNext()
end sub

sub NextPrefetchFailed()
    if m.nextWaitTimeout <> invalid then m.nextWaitTimeout.control = "stop"
    m.nextPrefetch = invalid
    m.nextPrefetchStarted = false
    if m.playNextWhenReady
        m.playNextWhenReady = false
        StartNextEpisode()
    end if
end sub

' A manual Next must never imprison the player behind a slow provider. After a
' bounded wait, cancel the warm-up and use the ordinary next-episode route.
sub onNextWaitTimeout()
    if not m.playNextWhenReady then return
    print "[next] explicit warm-up timed out — falling back to stream selection"
    CancelNextPrefetch()
    m.nextRequested = false
    StartNextEpisode()
end sub

' Swap the existing Video node directly. No Streams screen is exposed and no
' title/logo preparation banner is shown; the already-resolved URL is assigned
' on the same player and starts on the normal deferred play tick.
sub PlayPreparedNext()
    prepared = m.nextPrepared
    m.nextPrepared = invalid
    if prepared = invalid then return
    if m.nextWaitTimeout <> invalid then m.nextWaitTimeout.control = "stop"
    SavePosition()
    CancelResolve()
    CancelSubtitles()
    m.pendingPreparedNext = prepared
    ' Video.stop is asynchronous. Wait for the stopped state before replacing
    ' content while playback is active, otherwise the old and new media players
    ' race during the swap. At natural episode completion the node is already
    ' finished and Roku may never emit another stopped notification; begin the
    ' prepared episode immediately or autoplay remains on a locked black frame.
    if m.video <> invalid
        oldState = m.video.state
        if oldState = "finished" or oldState = "stopped"
            BeginPreparedNext()
        else
            m.video.control = "stop"
        end if
    else
        BeginPreparedNext()
    end if
end sub

sub BeginPreparedNext()
    prepared = m.pendingPreparedNext
    m.pendingPreparedNext = invalid
    if prepared = invalid then return
    if m.video <> invalid
        m.video.content = invalid
        ClearSubtitleTrack()
    end if
    if m.stallWatch <> invalid then m.stallWatch.control = "stop"
    if m.recoverKick <> invalid then m.recoverKick.control = "stop"
    ResetRecovery()

    m.playParams = prepared
    m.saved = false
    m.hasPlayed = false
    m.nextRequested = false
    m.playStarted = false
    m.nextPrefetchStarted = false
    m.playNextWhenReady = false
    m.nextPrefetch = invalid
    m.status.text = ""
    m.bufferingGroup.visible = false
    m.playMode = prepared.directPlayMode
    ClearSubtitles()
    print "[next] direct player swap -> " ; prepared.videoId
    ' This is a new video even though it reuses the same PlayerScreen. Start the
    ' full subtitle provider drain before StartPlayback builds its ContentNode,
    ' exactly like OnEnter does for a manually opened episode.
    StartSubtitles(prepared)
    StartPlayback(prepared.resolvedUrl, prepared.streamFormat, prepared.requestHeaders)
end sub

sub CancelNextPrefetch()
    if m.nextWaitTimeout <> invalid then m.nextWaitTimeout.control = "stop"
    if m.nextStreamTask <> invalid
        task = m.nextStreamTask
        m.nextStreamTask = invalid
        AsyncTask_Reap(task, m.top, true)
    end if
    if m.nextResolveTask <> invalid
        task = m.nextResolveTask
        m.nextResolveTask = invalid
        AsyncTask_Reap(task, m.top, true)
    end if
    m.nextPrefetch = invalid
    m.nextPrepared = invalid
    m.pendingPreparedNext = invalid
    m.nextPrefetchStarted = false
    m.playNextWhenReady = false
end sub

' True when the failure is this device's capability, not the network: the
' platform reports an unsupported container/codec as errorCode -5 ("unknown or
' unsupported media format") and — on the OS versions that phrase it — names it
' "no playable tracks". Either signature means no stream of this type will ever
' start on this box, so the status line says that instead of blaming the
' connection.
function NotPlayableOnDevice() as boolean
    if m.video = invalid then return false
    if m.video.HasField("errorCode") and m.video.errorCode <> invalid and m.video.errorCode = -5 then return true
    text = ""
    if m.video.HasField("errorStr") and m.video.errorStr <> invalid then text = m.video.errorStr
    if m.video.HasField("errorInfo") and m.video.errorInfo <> invalid and m.video.errorInfo.dbgmsg <> invalid then
        text = text + " " + m.video.errorInfo.dbgmsg
    end if
    if text.InStr("no playable tracks") > 0 or text.InStr("not supported") > 0 then return true
    return false
end function

' Print the platform's real verdict for a playback failure. The status line is
' one sentence for every cause — a bad container, a dropped connection, a DRM
' refusal — so a report of "it will not play" otherwise arrives with nothing to
' act on. The Video node carries the diagnosis: errorCode (-5 unknown or
' unsupported media format, -1 network, -2 timeout, -6 DRM), errorStr
' (category/errcode/source) and errorInfo (category/errcode/dbgmsg). Every read
' is guarded because a missing field on a node throws, and this is the one path
' that must not itself fail.
sub LogVideoError()
    if m.video = invalid then return
    code = 0
    if m.video.HasField("errorCode") then code = m.video.errorCode
    message = ""
    if m.video.HasField("errorMsg") then message = m.video.errorMsg
    detail = ""
    if m.video.HasField("errorStr") then detail = m.video.errorStr
    print "[video] error code=" ; code ; " msg=[" ; message ; "] str=[" ; detail ; "]"
    if m.video.HasField("errorInfo")
        info = m.video.errorInfo
        if info <> invalid and Type(info) = "roAssociativeArray"
            print "[video] error category=" ; info.category ; " errcode=" ; info.errcode ; " dbgmsg=[" ; info.dbgmsg ; "]"
        end if
    end if
end sub

' Up/Down reveals our compact controls without changing playback. Center/OK is
' handled explicitly so its behavior is stable across Roku OS versions: with
' the controls hidden it pauses immediately; with them visible it activates the
' focused timeline, pause/resume, next, or caption action. Both halves are
' consumed so the Video node cannot also toggle playback underneath.
'
' Before the stream resolves (or after a failure) there is no video: Back still
' pops (OnBackPressed returns false) and every other key is swallowed so a
' press routes nowhere else. Everything else falls through (Back reaches the
' stack → stop + save + pop).
function OnKeyEvent(key as string, press as boolean) as boolean
    if m.playNextWhenReady
        ' Back still reaches ScreenStack and cancels the request in OnExit.
        if key = "back" then return false
        return true
    end if
    currentVideoState = ""
    if m.video <> invalid then currentVideoState = m.video.state

    ' Reveal controls without changing playback. Only act on key-down so the
    ' matching release cannot reopen an overlay that has just been hidden.
    if not m.controlsVisible and press and (key = "up" or key = "down")
        if currentVideoState = "playing"
            ShowPlayingControls()
        else if currentVideoState = "paused"
            ShowPausedControls()
        end if
        return true
    end if

    ' Left/Right from clean playback opens the timeline and immediately starts
    ' a seek preview. The repeat timer accelerates while the key stays held.
    if not m.controlsVisible and press and (key = "left" or key = "right")
        if currentVideoState = "playing"
            ShowPlayingControls()
        else if currentVideoState = "paused"
            ShowPausedControls()
        else
            return true
        end if
        if key = "left" then StartSeekRepeat(-1, false) else StartSeekRepeat(1, false)
        return true
    end if

    if currentVideoState = "paused" or m.controlsVisible
        if not press
            if key = "left" or key = "right" or key = "rewind" or key = "fastforward" then StopSeekRepeat()
            return true
        end if
        if currentVideoState = "playing" then ArmControlsHide()
        if key = "rewind"
            m.pauseActionIndex = 0
            UpdatePausedControlFocus()
            StartSeekRepeat(-1, true)
            return true
        else if key = "fastforward"
            m.pauseActionIndex = 0
            UpdatePausedControlFocus()
            StartSeekRepeat(1, true)
            return true
        else if key = "up"
            StopSeekRepeat()
            ' The action buttons are physically above the timeline.
            if m.pauseActionIndex = 0
                m.pauseActionIndex = 1
                UpdatePausedControlFocus()
            end if
            return true
        else if key = "down"
            StopSeekRepeat()
            if m.pauseActionIndex = 0
                ' Down from the lowest row dismisses the compact overlay.
                HidePausedControls()
            else
                m.pauseActionIndex = 0
                UpdatePausedControlFocus()
            end if
            return true
        else if key = "left"
            if m.pauseActionIndex = 0
                StartSeekRepeat(-1, false)
            else
                if m.pauseActionIndex = 3 and m.pauseHasNext then
                    m.pauseActionIndex = 2
                else
                    m.pauseActionIndex = 1
                end if
                UpdatePausedControlFocus()
            end if
            return true
        else if key = "right"
            if m.pauseActionIndex = 0
                StartSeekRepeat(1, false)
            else if m.pauseActionIndex = 1 and m.pauseHasNext
                m.pauseActionIndex = 2
                UpdatePausedControlFocus()
            else
                m.pauseActionIndex = 3
                UpdatePausedControlFocus()
            end if
            return true
        else if key = "OK"
            StopSeekRepeat()
            if m.pauseActionIndex = 2 and m.pauseHasNext
                PlayNextFromPause()
            else if m.pauseActionIndex = 3
                ShowCaptionChoice()
            else if m.pauseActionIndex = 0
                CommitTimelineSeek()
            else
                if currentVideoState = "playing"
                    m.video.control = "pause"
                else if currentVideoState = "paused"
                    m.video.control = "resume"
                end if
            end if
            return true
        end if
    end if
    if key = "OK"
        if not press then return true
        if m.video = invalid then return true
        videoState = m.video.state
        if videoState = "playing"
            m.video.control = "pause"
            return true
        else if videoState = "paused"
            m.video.control = "resume"
            return true
        end if
        return true
    end if
    if not press then return false
    if m.video = invalid
        if key = "back" then return false
        return true
    end if
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
        HideBuffering()
        return
    end if
    pct = status.percentage
    if pct = invalid then pct = 0
    if pct < 0 then pct = 0
    if pct > 100 then pct = 100
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

' Back records the position (while the node can still report one) and declines,
' so the stack pops. The stop itself is OnExit's business, which runs before the
' screen is hidden.
function OnBackPressed() as boolean
    if m.video = invalid then return false
    SavePosition()
    return false
end function

' Leaving cancels the resolve, records where we got to, and resets the Video
' node. Nothing is reaped: this screen and its node are static children of the
' Scene and survive the pop, so the next play re-arms them in CreateVideo.
function OnExit() as void
    HidePausedControls()
    StopTorrentStats()
    CancelNextPrefetch()
    CancelResolve()
    CancelSubtitles()
    SavePosition()
    ResetVideoNode()
end function

' Leave the node as the next play expects to find it: stopped, and carrying
' nothing of the play that just ended.
'
' Blanking the content is the whole point. The node survives the pop, so whatever
' is still on it is what the NEXT entry starts from — and the screen becomes
' visible again before anything has been resolved, with the native chrome
' (enableUI) painting content.title off whatever ContentNode is attached. That is
' why the prebuffer showed the PREVIOUS title, correcting itself only once
' StartPlayback replaced the content. Clear it here, on the way out, where the
' screen is already hidden: ScreenStack.pop sets visible = false before it calls
' OnExit, so this cannot flicker.
'
' Order matters twice over: SavePosition has already read position and duration
' off the node by the time this runs, and the stop goes before the blank so the
' node is not still holding a stream when we detach from it.
sub ResetVideoNode()
    ' Same cross-play leak the toast nodes below are swept for: playerStatus is a
    ' static child too, and onVideoStateChanged only ever blanks it on "playing".
    ' A source that failed to resolve — or a video that reached "error" — leaves
    ' its message behind, so the next entry would open already showing the last
    ' play's verdict while the new resolve is still running. The screen is
    ' already hidden here (ScreenStack.pop sets visible = false before OnExit),
    ' so clearing it cannot flicker.
    '
    ' Before the m.video guard, not after it: this is a Label, so it exists
    ' whether or not the Video node did, and a label left holding the previous
    ' play's verdict is exactly the bug. A missing Video would fail the play
    ' anyway — that is onVideoStateChanged's "The player could not start." — but
    ' it must not also inherit stale text on the way there.
    m.status.text = ""
    if m.stallWatch <> invalid then m.stallWatch.control = "stop"
    if m.recoverKick <> invalid then m.recoverKick.control = "stop"
    ResetRecovery()
    if m.video = invalid then return
    m.video.control = "stop"
    m.video.content = invalid
    ClearSubtitleTrack()
    HideBuffering()
end sub

' video.subtitleTrack is a write-only selector on the LIVE node, so unlike
' SubtitleTracks (which lives on the ContentNode and goes with it) its value
' outlives the play that set it. It is inert while the next play has no tracks at
' all — the native dialog has nothing to list — but the one place it could bite
' is a play that DOES get tracks: the stale name is not among them, so it
' selects nothing at best. Cleared with the rest of the node so every play
' starts at the platform default.
sub ClearSubtitleTrack()
    if m.video = invalid then return
    if not m.video.HasField("subtitleTrack") then return
    m.video.subtitleTrack = ""
end sub

sub BlurFocus()
end sub

sub SavePosition()
    if m.saved then return
    if m.playParams = invalid or m.playParams.videoId = invalid then return
    if m.stores = invalid then return
    ' Leaving while the stream is still buffering means nothing was actually
    ' watched — the video node cannot even report a position yet. Skip the write
    ' so an existing resume point is never clobbered with a bogus one.
    if not m.hasPlayed then return

    params = m.playParams

    ' Live channels (Stremio types "channel"/"tv") are kept out of Continue
    ' Watching on every session, by policy: a live stream has no resume point,
    ' and on a linked session a position record would also propagate a
    ' meaningless resume marker to the account. Leaving the gate out here would
    ' resurrect them through either the local stack or the server push.
    metaType = params.metaType
    if metaType = invalid then metaType = ""
    if m.stores.library.callFunc("LibraryIsChannelType", metaType) then return

    position = m.video.position
    duration = m.video.duration
    if position = invalid then position = 0
    if duration = invalid then duration = 0
    ' A player that errored, ended early or was reset can report 0 (or junk)
    ' for position. The watchdog's last position that actually played is the
    ' honest resume point there, so a freeze is never saved as "start over".
    nodeState = m.video.state
    if m.lastGoodPos <> invalid and m.lastGoodPos > 0
        if position <= 0 or nodeState = "error" or (nodeState = "finished" and EndedEarly())
            print "[resume] node pos=" ; position ; " state=" ; nodeState ; " — saving lastGoodPos=" ; m.lastGoodPos ; " instead"
            position = m.lastGoodPos
        end if
    end if

    season = 0
    if params.season <> invalid then season = params.season
    episode = 0
    if params.episode <> invalid then episode = params.episode
    name = ""
    if params.name <> invalid then name = params.name
    poster = ""
    if params.poster <> invalid then poster = params.poster
    posterShape = ""
    if params.posterShape <> invalid then posterShape = params.posterShape

    playback = invalid
    if params.providerAddress <> invalid and params.providerAddress <> "" and params.streamIndex <> invalid and params.stream <> invalid
        playback = {
            providerAddress: params.providerAddress
            streamIndex: params.streamIndex
            directPlayMode: params.directPlayMode
            streamKey: StreamIdentity(params.stream)
        }
    end if
    m.stores.library.callFunc("LibrarySetPosition", params.videoId, params.metaId, params.metaType, season, episode, name, poster, Int(position), Int(duration), posterShape)
    if playback <> invalid then m.stores.library.callFunc("LibraryRememberPlayback", params.videoId, params.metaId, playback)
    mid = ""
    if params.metaId <> invalid then mid = params.metaId
    m.stores.library.callFunc("LibraryMarkWatchedIfFinished", mid, params.videoId, Int(position), Int(duration))
    m.saved = true
    PublishWatchState()
end sub

' Publish the current playback position through the watchStateUpdate field for
' MainScene to push back to Stremio (a stremio session only). Fired on pause
' and on leave (from SavePosition); MainScene coalesces, so the last state
' always wins and at most one push is in flight at a time. Publishing is purely
' local state — the player never touches the API — and harmless in a guest
' session, where MainScene drops it.
sub PublishWatchState()
    if m.playParams = invalid or m.playParams.videoId = invalid then return
    if m.stores = invalid then return
    if m.video = invalid then return
    if not m.hasPlayed then return

    ' Same live-channel policy as SavePosition: a paused channel must not
    ' publish a position for the account push either. WatchRecord never sees
    ' the packet, so the buffer and MainScene's push stay clean.
    params = m.playParams
    metaType = ""
    if params.metaType <> invalid then metaType = params.metaType
    if m.stores.library.callFunc("LibraryIsChannelType", metaType) then return

    position = m.video.position
    duration = m.video.duration
    if position = invalid then position = 0
    if duration = invalid then duration = 0

    name = ""
    if params.name <> invalid then name = params.name
    poster = ""
    if params.poster <> invalid then poster = params.poster

    packet = {
        videoId: params.videoId
        metaId: params.metaId
        metaType: metaType
        name: name
        poster: poster
        position: Int(position)
        duration: Int(duration)
    }
    ' Record before publishing: MainScene's observer can fire synchronously on
    ' the field write, so the shared buffer must already hold this packet when
    ' it reads.
    m.stores.watch.callFunc("WatchRecord", packet)
    m.top.watchStateUpdate = packet
end sub

' ---------------------------------------------------------------------------
' Stall recovery.
'
' Long streams (debrid links especially) can lose their connection mid-play.
' The platform then sits buffering forever, reports "error", or reads the
' closed connection as "finished" well before the real end. Seeking re-opens
' the stream and it plays on fine, so this does that automatically: a 1s
' watchdog notes the last position that actually advanced, and on a stall,
' a mid-play error or an early finish, the same content is re-opened a few
' seconds before that position. Bounded so a stream that is really gone ends
' with a message instead of looping.
' ---------------------------------------------------------------------------

' Seconds without progress while playing/buffering before we reopen.
function STALL_SECONDS() as integer
    return 20
end function

' Reopen attempts before giving up. The count resets after a stretch of
' healthy playback, so a long film can survive several separate drops.
function STALL_MAX_RECOVERIES() as integer
    return 5
end function

' Healthy playback (seconds) that clears the attempt count.
function STALL_HEALTHY_RESET_SECONDS() as integer
    return 120
end function

sub ResetRecovery()
    m.lastGoodPos = 0
    m.lastSeenPos = -1
    m.lastProgressAt = UpTime(0)
    m.recoverCount = 0
    m.recovering = false
    m.healthySince = UpTime(0)
    m.lastCheckpointAt = UpTime(0)
end sub

' How often the resume point is written while a video plays.
function CHECKPOINT_SECONDS() as integer
    return 30
end function

' Write the resume point mid-play. SavePosition only runs on the way out, so
' a freeze that ends with Roku killing the channel, or a stream abandoned from
' the stream list, used to leave the old resume point behind. Local write only:
' the account push still happens once, on exit, via SavePosition.
sub Checkpoint(position as dynamic)
    if m.stores = invalid or m.playParams = invalid or m.playParams.videoId = invalid then return
    if position = invalid or position <= 0 then return
    params = m.playParams
    metaType = params.metaType
    if metaType = invalid then metaType = ""
    if m.stores.library.callFunc("LibraryIsChannelType", metaType) then return
    duration = m.video.duration
    if duration = invalid then duration = 0
    season = 0
    if params.season <> invalid then season = params.season
    episode = 0
    if params.episode <> invalid then episode = params.episode
    name = ""
    if params.name <> invalid then name = params.name
    poster = ""
    if params.poster <> invalid then poster = params.poster
    posterShape = ""
    if params.posterShape <> invalid then posterShape = params.posterShape
    metaId = ""
    if params.metaId <> invalid then metaId = params.metaId
    m.stores.library.callFunc("LibrarySetPosition", params.videoId, metaId, metaType, season, episode, name, poster, Int(position), Int(duration), posterShape)
end sub

' "finished" with more than a minute of a known duration left is a dropped
' connection, not the end of the video.
function EndedEarly() as boolean
    if m.video = invalid then return false
    if m.hasPlayed <> true then return false
    duration = m.video.duration
    if duration = invalid or duration <= 0 then return false
    return m.lastGoodPos > 0 and m.lastGoodPos < duration - 60
end function

sub onStallWatch()
    if m.video = invalid or m.recovering then return
    if m.hasPlayed <> true then return
    state = m.video.state
    curPos = m.video.position
    if curPos = invalid then curPos = 0
    now = UpTime(0)

    if curPos <> m.lastSeenPos
        ' Any movement counts, including a seek backwards by the viewer.
        m.lastSeenPos = curPos
        m.lastProgressAt = now
        if state = "playing" then m.lastGoodPos = curPos
    end if

    MaybePrefetchNext(curPos, m.video.duration)

    if state = "paused" or state = "stopped" or state = "finished" or state = "error"
        ' A viewer pause is not a stall; neither is a terminal state (those are
        ' handled by onVideoStateChanged).
        m.lastProgressAt = now
        m.healthySince = now
        return
    end if

    if state = "playing" and now - m.lastCheckpointAt >= CHECKPOINT_SECONDS()
        m.lastCheckpointAt = now
        Checkpoint(curPos)
    end if

    if state = "playing" and m.recoverCount > 0 and now - m.healthySince >= STALL_HEALTHY_RESET_SECONDS()
        print "[recover] healthy for " ; STALL_HEALTHY_RESET_SECONDS() ; "s at pos=" ; curPos ; " — attempts reset (was " ; m.recoverCount ; ")"
        m.recoverCount = 0
    end if

    stalledFor = now - m.lastProgressAt
    if stalledFor >= STALL_SECONDS()
        print "[recover] stall detected: state=" ; state ; " pos=" ; curPos ; " no progress for " ; Int(stalledFor) ; "s buffering=" ; FormatJson(m.video.bufferingStatus)
        TryRecover("stall-" + state)
    end if
end sub

sub TryRecover(reason as string)
    if m.video = invalid or m.recovering then return
    content = m.video.content
    if content = invalid
        print "[recover] " ; reason ; " — no content on the node, cannot reopen"
        return
    end if
    if m.recoverCount >= STALL_MAX_RECOVERIES()
        print "[recover] " ; reason ; " — giving up after " ; m.recoverCount ; " attempts at pos=" ; m.lastGoodPos
        m.status.text = Lang("player", "streamKeptDropping")
        HideBuffering()
        if m.stallWatch <> invalid then m.stallWatch.control = "stop"
        return
    end if

    m.recovering = true
    m.recoverCount = m.recoverCount + 1
    m.healthySince = UpTime(0)
    ' After a viewer seek the node reports the seek target while it buffers, so
    ' a stall there resumes from the target, not from before the seek. A
    ' finished/error node's position is not trusted.
    base = m.lastGoodPos
    if Left(reason, 5) = "stall" and m.video.position <> invalid and m.video.position > base then base = m.video.position
    resumeAt = base - 3
    if resumeAt < 0 then resumeAt = 0
    print "[recover] " ; reason ; " — attempt " ; m.recoverCount ; "/" ; STALL_MAX_RECOVERIES() ; " lastGoodPos=" ; m.lastGoodPos ; " nodePos=" ; m.video.position ; " resumeAt=" ; resumeAt ; " dur=" ; m.video.duration ; " up=" ; UpTime(0)
    Notify(Lang("player", "reconnecting"))

    ' A fresh copy of the same ContentNode (url, format, subtitle tracks) so the
    ' platform treats it as a new open rather than a no-op re-assign.
    reopened = invalid
    try
        reopened = content.Clone(true)
    catch e
        print "[recover] clone failed (" ; e.message ; "), reusing the node"
    end try
    if reopened = invalid then reopened = content
    reopened.playStart = resumeAt

    m.video.control = "stop"
    m.video.content = reopened
    ' Same reason StartPlayback defers play by a tick: content and control in
    ' one tick can race.
    if m.recoverKick <> invalid
        m.recoverKick.control = "stop"
        m.recoverKick.control = "start"
    else
        onRecoverKick()
    end if
end sub

sub onRecoverKick()
    if m.video = invalid then return
    print "[recover] play from " ; m.video.content.playStart ; " up=" ; UpTime(0)
    m.lastProgressAt = UpTime(0)
    m.lastSeenPos = -1
    m.video.control = "play"
    m.recovering = false
end sub
