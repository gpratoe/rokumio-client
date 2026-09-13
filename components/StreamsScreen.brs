' StreamsScreen — the stream picker behind every Play/Resume action.
'
' The left panel renders the media entirely from params the pusher already had:
' title, the episode line for series, synopsis, and the Cinemeta background
' artwork (deliberately no poster). The pusher hands over what it knows — the
' movie plays its description and runtime, EpisodesScreen the episode name and
' overview it just fetched — so the panel is full the instant the screen
' opens. The right side lists every stream candidate from the installed add-ons
' that advertise the "stream" resource, one task per provider, one card per
' stream. OK drops straight into the PlayerScreen: the torrent is resolved
' there (logo pulse while its engine warms up), so the picker answers instantly
' and a resolution failure stays on the player with a message instead of
' bouncing back here.
'
' Nothing here blocks the render thread: each add-on's stream list loads through
' its own StreamsLoaderTask, so providers resolve in parallel and their cards
' appear the moment each one answers, with the status line counting down the
' rest. The player owns playback resolution.
'
' Params: { addonAddress, metaType, metaId, videoId, season, episode, position,
'           name, poster, logo, background }, plus the panel's data where the
'           pusher holds it: description + runtime (movie), and episodeName +
'           episodeOverview (series from EpisodesScreen). A series push straight
'           from Details (Play/Resume, so no video list travelled) enriches the
'           panel with the same two fields via a parallel MetaLoaderTask — the
'           right-side stream list never waits on it.

sub init()
    m.headTitle = m.top.FindNode("headTitle")
    m.headSub = m.top.FindNode("headSub")
    m.synopsis = m.top.FindNode("synopsis")
    m.status = m.top.FindNode("status")
    m.bgPoster = m.top.FindNode("bgPoster")
    m.streamsList = m.top.FindNode("streamsList")

    m.streamsList.ObserveField("rowItemSelected", "onStreamSelected")

    m.streams = []
    m.loadTasks = invalid
    m.providers = invalid
    m.providersTotal = 0
    m.pendingCount = 0
    m.listFilled = false
    m.epMetaTask = invalid
end sub

' Stores are class instances, which cannot cross components through an interface
' field, so the Scene hands them over with callFunc instead.
function SetStores(stores as object) as void
    m.stores = stores
end function

function OnEnter(params as object) as void
    ' Re-entry after the player pops: params is invalid and the Group was given
    ' focus by the stack. The stream list must take it back.
    if params = invalid
        RestoreFocus()
        return
    end if

    CancelStreamsLoad()
    CancelEpisodeLoad()
    m.params = params
    ApplyParamsChrome(params)

    m.streams = []
    m.listFilled = false
    EmptyStreamsList()

    LoadStreams(params)
    StartEpisodeLoad(params)
end function

' Build the left panel instantly from the params the pusher already had — title,
' the SxE action line (or "Movie"), the background artwork Details/Episodes were
' already showing, and the synopsis data the pusher held (movie description, or
' the episode the EpisodesScreen had already fetched). Missing data leaves a
' placeholder instead of a blank panel — no fetch ever fills this pane.
sub ApplyParamsChrome(params as object)
    name = params.name
    if name = invalid then name = ""
    m.headTitle.text = name

    bg = params.background
    if bg = invalid then bg = ""
    m.bgPoster.uri = bg

    action = ""
    synopsis = ""
    if params.metaType = "series"
        season = ParamString(params.season)
        episode = ParamString(params.episode)
        if season <> "" or episode <> ""
            action = "S" + season + "E" + episode
        end if
        episodeName = params.episodeName
        if episodeName <> invalid and episodeName <> ""
            if action <> "" then action = action + "  " + episodeName else action = episodeName
        end if
        episodeOverview = params.episodeOverview
        if episodeOverview <> invalid and episodeOverview <> "" then synopsis = episodeOverview
    else if params.metaType <> invalid and params.metaType <> ""
        action = "Movie"
        description = params.description
        if description <> invalid and description <> "" then synopsis = description
        runtime = params.runtime
        if runtime <> invalid and runtime <> ""
            formatted = FormatRuntime(runtime)
            if formatted <> "" then action = "Movie  ·  " + formatted
        end if
    end if
    m.headSub.text = action

    if synopsis = "" then synopsis = "No synopsis available."
    m.synopsis.text = synopsis
end sub

' Deterministically blank the stream list: a fresh empty content node, so no
' previously rendered cards can linger while the new load is in flight.
sub EmptyStreamsList()
    content = CreateObject("roSGNode", "ContentNode")
    m.streamsList.content = content
    m.streamsList.numRows = 0
end sub

' Kick the stream-list fetches off the render thread. One StreamsLoaderTask per
' provider resolves in parallel — each task answers with its own { streams,
' error } the instant that address responds, and onStreamsLoaded routes it into
' the matching provider slot. The installed add-ons are read here (registry reads
' only, no network) so only the addresses that advertise the "stream" resource
' cross into the tasks. Failure handling mirrors Home: on total failure the grid
' stays empty, and a hung add-on only delays its own provider, never the others.
sub LoadStreams(params as object)
    print "[rokumio] LoadStreams called"
    if m.stores = invalid or m.stores.addons = invalid then return
    if m.loadTasks <> invalid and m.loadTasks.Count() > 0 then return

    providers = []
    for each addon in m.stores.addons.GetAll()
        if m.stores.addons.HasResource(addon.resources, "stream")
            if addon.address <> invalid and addon.address <> ""
                name = addon.name
                if name = invalid or name = "" then name = addon.address
                providers.Push({ name: name, address: addon.address, streams: [], error: "" })
            end if
        end if
    end for
    print "[rokumio] LoadStreams providers=" + providers.Count().ToStr()

    m.providers = providers
    m.providersTotal = providers.Count()
    m.pendingCount = providers.Count()
    m.loadError = ""
    m.loadTasks = []

    for i = 0 to providers.Count() - 1
        task = CreateObject("roSGNode", "StreamsLoaderTask")
        task.id = "streamsLoader" + i.ToStr()
        m.top.AppendChild(task)
        task.metaType = ParamString(params.metaType)
        task.videoId = ParamString(params.videoId)
        task.addonAddress = providers[i].address
        task.providerIndex = i
        task.providerName = providers[i].name
        task.observeField("result", "onStreamsLoaded")
        m.loadTasks.Push(task)
        task.control = "RUN"
    end for
    print "[rokumio] LoadStreams tasks started=" + m.loadTasks.Count().ToStr()

    UpdateStreamsStatus()
end sub

' A single provider's stream list landed (or failed). The task reports which
' provider it was via its providerIndex slot; results can arrive in any order.
' A stale result that landed after CancelStreamsLoad is dropped by the slot
' guard — the slot was cleared, so nothing applies. On every landing the flat
' list and cards are rebuilt so the user sees each provider's streams the moment
' they resolve, with the status line counting down the rest.
sub onStreamsLoaded(event as object)
    if m.loadTasks = invalid then return
    task = event.GetRoSGNode()
    if task = invalid then return
    index = task.providerIndex
    if index < 0 or index >= m.loadTasks.Count() then return
    if m.loadTasks[index] = invalid then return
    m.loadTasks[index] = invalid
    if m.providers = invalid or index >= m.providers.Count() then return

    result = task.result
    provider = m.providers[index]
    if result <> invalid and result.streams <> invalid
        for each stream in result.streams
            provider.streams.Push(stream)
        end for
    else if result <> invalid and result.error <> invalid and result.error <> ""
        provider.error = result.error
        if m.loadError = "" then m.loadError = result.error
    end if

    if m.pendingCount > 0 then m.pendingCount = m.pendingCount - 1
    RebuildFlatStreams()
    UpdateStreamsStatus()
    PopulateStreams()
end sub

' Project the per-provider stream lists into the flat m.streams the list renders.
' Re-running the whole projection each time keeps the card order stable as later
' providers land (results arrive in completion order, not add-on order — the
' slot assignment fixes each card's provenance without reshuffling what is shown).
sub RebuildFlatStreams()
    m.streams = []
    if m.providers = invalid then return
    for each provider in m.providers
        for each stream in provider.streams
            m.streams.Push(stream)
        end for
    end for
end sub

' The status line: while any provider is still resolving, show how many remain
' ("2/3 providers loading…"); when all are done, clear it, or report failure/empty
' precisely the way the old single-shot load did.
sub UpdateStreamsStatus()
    if m.status = invalid then return
    if m.pendingCount > 0
        m.status.text = m.pendingCount.ToStr() + "/" + m.providersTotal.ToStr() + " providers loading…"
    else
        if m.streams.Count() = 0
            if m.loadError <> ""
                m.status.text = "Could not load streams: " + m.loadError
            else
                m.status.text = "No streams found for this title."
            end if
        else
            m.status.text = ""
        end if
    end if
end sub

sub CancelStreamsLoad()
    if m.loadTasks <> invalid
        for each task in m.loadTasks
            if task <> invalid
                task.control = "STOP"
                task.unobserveField("result")
                if task.getParent() <> invalid then m.top.RemoveChild(task)
            end if
        end for
    end if
    m.loadTasks = invalid
end sub

' Series opened straight from Details carry no episode name/overview in their
' params (resume/Play-S1E1 never passed through EpisodesScreen). Spin a parallel
' MetaLoaderTask so the panel can refine once the video land — the stream list
' is not held back. Movies and EpisodesScreen-origin series (which already pass
' both fields) skip this.
sub StartEpisodeLoad(params as object)
    if params = invalid or params.metaType <> "series" then return
    if params.addonAddress = invalid or params.addonAddress = "" then return
    if params.metaId = invalid or params.metaId = "" then return
    if params.episodeName <> invalid and params.episodeName <> "" then return
    if params.episodeOverview <> invalid and params.episodeOverview <> "" then return
    if m.epMetaTask <> invalid then return

    task = CreateObject("roSGNode", "MetaLoaderTask")
    task.id = "episodeMetaLoader"
    m.top.AppendChild(task)
    task.addonAddress = ParamString(params.addonAddress)
    task.metaType = "series"
    task.metaId = ParamString(params.metaId)
    task.observeField("result", "onEpisodeMetaLoaded")
    m.epMetaTask = task
    task.control = "RUN"
end sub

' The series meta came back. If it holds the target episode, fill the two panel
' params the pusher couldn't supply and re-run the pure chrome builder — the
' SxE line and synopsis refine in place, everything else stays. A stale result
' that landed after CancelEpisodeLoad is dropped by the m.epMetaTask guard.
sub onEpisodeMetaLoaded()
    if m.epMetaTask = invalid then return
    task = m.epMetaTask
    m.epMetaTask = invalid
    task.unobserveField("result")
    if task.getParent() <> invalid then m.top.RemoveChild(task)

    result = task.result
    if result = invalid or not result.ok or result.meta = invalid then return
    if m.params = invalid then return

    episode = EpisodeInMeta(result.meta, m.params.season, m.params.episode)
    if episode = invalid then return
    if m.params.episodeName = invalid or m.params.episodeName = "" then m.params.episodeName = episode.name
    if m.params.episodeOverview = invalid or m.params.episodeOverview = "" then m.params.episodeOverview = episode.overview
    ApplyParamsChrome(m.params)
end sub

sub CancelEpisodeLoad()
    if m.epMetaTask <> invalid
        m.epMetaTask.unobserveField("result")
        m.epMetaTask.control = "STOP"
        if m.epMetaTask.getParent() <> invalid then m.top.RemoveChild(m.epMetaTask)
        m.epMetaTask = invalid
    end if
end sub

' Find the video for a (season, episode) inside a fetched series meta. The video
' list mirrors the episode tiles EpisodesScreen builds from the same store.
function EpisodeInMeta(meta as object, season as dynamic, episode as dynamic) as dynamic
    if meta = invalid or meta.videos = invalid or season = invalid or episode = invalid then return invalid
    for each video in meta.videos
        if video.season <> invalid and video.season = season and video.episode <> invalid and video.episode = episode then return video
    end for
    return invalid
end function

' Build the right-side list from the loaded m.streams (one card per stream).
' Called on every provider completion, so focus/jump only on the first fill
' (listFilled) — later providers topping up the list must not yank the user's
' cursor. Empty/error messaging lives in UpdateStreamsStatus, not here.
sub PopulateStreams()
    if m.streams.Count() = 0 then return

    content = CreateObject("roSGNode", "ContentNode")
    for i = 0 to m.streams.Count() - 1
        row = content.CreateChild("ContentNode")
        item = row.CreateChild("ContentNode")
        stream = m.streams[i]
        item.title = StreamLabel(stream)
        lines = StreamTitleLines(stream)
        if lines.Count() > 0
            description = ""
            for each line in lines
                if description <> "" then description = description + chr(10)
                description = description + line
            end for
            item.description = description
        end if
    end for
    m.streamsList.content = content
    m.streamsList.numRows = m.streams.Count()
    if not m.listFilled
        m.listFilled = true
        m.streamsList.jumpToRowItem = [0, 0]
        m.streamsList.SetFocus(true)
    end if
end sub

' The card's primary line: the add-on's stream name, then title, then a generic
' label.
function StreamLabel(stream as object) as string
    label = stream.name
    if label = invalid or label.Trim() = "" then label = stream.title
    if label = invalid or label.Trim() = "" then label = "Stream"
    return FlattenNewlines(label).Trim()
end function

' The card's lines below the name, straight from the stream title split at its
' embedded line feeds — the release, then the file path, then
' "👤 412 💾 54.2 GB ⚙️ RARBG", then a languages line when one is present. Direct URLs and add-ons with no title get a "source · quality"
' line so the card is never empty.
function StreamTitleLines(stream as object) as object
    lines = []
    if stream <> invalid and stream.title <> invalid and stream.title.Trim() <> ""
        pieces = stream.title.Trim().Split(chr(10))
        if pieces <> invalid and pieces.Count() > 0
            for each piece in pieces
                line = piece.Trim()
                if line <> "" then lines.Push(line)
            end for
        end if
    end if
    if lines.Count() = 0 and stream <> invalid
        if stream.source <> invalid and stream.source <> "" then lines.Push(stream.source)
        if stream.quality <> invalid and stream.quality <> "" then lines.Push(stream.quality)
    end if
    return lines
end function

' Stream names/titles carry embedded line feeds; the card labels are
' single-line, so replace them with a space.
function FlattenNewlines(text as string) as string
    if text = "" then return text
    pieces = text.Split(chr(10))
    if pieces = invalid or pieces.Count() <= 1 then return text
    result = ""
    for each piece in pieces
        if result <> "" then result = result + " "
        result = result + piece
    end for
    return result
end function

' Runtime echoed straight from the meta JSON — Cinemeta ships plain minutes, so
' no parsing and no "2h 5m" conversion.
function FormatRuntime(runtime as dynamic) as string
    if runtime = invalid then return ""
    return runtime.ToStr().Trim()
end function

' OK on a stream card drops straight into the player with the raw stream and the
' streaming-server address. The PlayerScreen resolves it (ResolvePlayback passes
' a direct URL through as-is and creates a torrent engine on the server, up to
' the 120s long timeout on a cold engine) while its logo pulses, so the picker
' answers instantly and stays the place a failed source lands back on.
sub onStreamSelected()
    data = m.streamsList.rowItemSelected
    if data = invalid or data.Count() < 2 then return
    index = data[0]
    if m.streams = invalid or index < 0 or index >= m.streams.Count() then return

    serverAddress = ""
    if m.stores <> invalid and m.stores.settings <> invalid then serverAddress = m.stores.settings.GetServerAddress()

    m.top.pushRequest = {
        screen: "playerScreen"
        params: {
            stream: m.streams[index]
            serverAddress: serverAddress
            metaType: m.params.metaType
            metaId: m.params.metaId
            videoId: m.params.videoId
            season: m.params.season
            episode: m.params.episode
            position: m.params.position
            name: m.headTitle.text
            poster: m.params.poster
            logo: m.params.logo
        }
    }
end sub

' Params values can carry invalid; string interface fields cannot, so coerce.
function ParamString(value as dynamic) as string
    if value = invalid then return ""
    return value.ToStr()
end function

sub RestoreFocus()
    if m.streams.Count() > 0 then m.streamsList.SetFocus(true)
end sub

function OnExit() as void
    CancelStreamsLoad()
    CancelEpisodeLoad()
end function

function OnBackPressed() as boolean
    return false
end function

sub BlurFocus()
end sub
