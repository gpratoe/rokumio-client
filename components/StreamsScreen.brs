' StreamsScreen — the stream picker behind every Play/Resume action.
'
' The left panel renders the media from its full meta (title, episode line for
' series, synopsis, Cinemeta background artwork — deliberately no poster). The
' right side lists every stream candidate from the installed add-ons that
' advertise the "stream" resource (Torrentio, the mock add-on, …), one card per
' stream. OK resolves a card to a playable URL and pushes the PlayerScreen; a
' resolution failure (torrent streams need the streaming server, which is not
' configured until the settings screen exists) lands on the status line.
'
' Nothing here blocks the render thread: meta + every add-on's stream list load
' through StreamsLoaderTask, and every torrent resolve runs through
' StreamResolveTask (the create call can park for the full 120s long timeout on
' a cold engine). The screen only does cheap formatting in its own thread.
'
' Params: { addonAddress, metaType, metaId, videoId, season, episode, position,
'           name, poster }.

sub init()
    m.headTitle = m.top.FindNode("headTitle")
    m.headSub = m.top.FindNode("headSub")
    m.synopsis = m.top.FindNode("synopsis")
    m.status = m.top.FindNode("status")
    m.bgPoster = m.top.FindNode("bgPoster")
    m.streamsList = m.top.FindNode("streamsList")

    m.streamsList.ObserveField("rowItemSelected", "onStreamSelected")

    m.streams = []
    m.loadTask = invalid
    m.resolveTask = invalid
    m.resolving = false
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
    m.params = params
    name = params.name
    if name = invalid then name = ""
    m.headTitle.text = name

    m.synopsis.text = "No synopsis available."
    m.headSub.text = ""
    m.bgPoster.uri = ""
    m.streams = []
    m.streamsList.content = invalid
    m.status.text = "Looking for streams…"

    LoadStreams(params)
end function

' Kick the meta + stream-list fetch off the render thread. The installed add-ons
' are read here (registry reads only, no network) so only the addresses that
' advertise the "stream" resource cross into the task.
sub LoadStreams(params as object)
    print "[rokumio] LoadStreams called"
    if m.stores = invalid or m.stores.addons = invalid then return
    if m.loadTask <> invalid then return

    addresses = []
    for each addon in m.stores.addons.GetAll()
        if addon.resources <> invalid and HasResource(addon.resources, "stream")
            if addon.address <> invalid and addon.address <> "" then addresses.Push(addon.address)
        end if
    end for
    print "[rokumio] LoadStreams addonAddresses=" + addresses.Count().ToStr()

    task = CreateObject("roSGNode", "StreamsLoaderTask")
    task.id = "streamsLoader"
    m.top.AppendChild(task)
    task.metaAddress = ParamString(params.addonAddress)
    task.metaType = ParamString(params.metaType)
    task.metaId = ParamString(params.metaId)
    task.videoId = ParamString(params.videoId)
    task.addonAddresses = addresses
    task.observeField("result", "onStreamsLoaded")
    m.loadTask = task
    task.control = "RUN"
    print "[rokumio] LoadStreams task started"
end sub

' The loader finished. Apply the fetched meta to the left panel, then fill the
' stream list. A stale result that landed after CancelStreamsLoad is dropped by
' the m.loadTask guard.
sub onStreamsLoaded()
    if m.loadTask = invalid then return
    task = m.loadTask
    m.loadTask = invalid
    result = task.result
    'print "[rokumio] onStreamsLoaded result ok=" + (result <> invalid).ToStr() + " streams=" + (result.streams <> invalid and result.streams.Count()).ToStr() + " error=" + (result.error <> invalid and result.error or "")
    task.unobserveField("result")
    if task.getParent() <> invalid then m.top.RemoveChild(task)

    if result <> invalid then ApplyMeta(m.params, result.meta)

    m.streams = []
    if result <> invalid and result.streams <> invalid
        for each stream in result.streams
            m.streams.Push({ stream: stream })
        end for
    end if
    PopulateStreams()
end sub

sub CancelStreamsLoad()
    if m.loadTask <> invalid
        m.loadTask.unobserveField("result")
        m.loadTask.control = "STOP"
        if m.loadTask.getParent() <> invalid then m.top.RemoveChild(m.loadTask)
        m.loadTask = invalid
    end if
end sub

' Fill the left panel from the full meta (episodes.GetMeta against the meta
' add-on). The fetched meta carries the real title, background artwork and
' synopsis the slim catalog params lack.
sub ApplyMeta(params as object, meta as object)
    m.synopsis.text = "No synopsis available."
    m.headSub.text = ""
    bg = ""
    if meta <> invalid
        if meta.name <> invalid and meta.name <> "" then m.headTitle.text = meta.name
        if meta.background <> invalid then bg = meta.background
        if params.metaType = "series"
            epLine = "S" + params.season.ToStr() + "E" + params.episode.ToStr()
            episode = EpisodeFor(meta, params.season, params.episode)
            if episode <> invalid
                if episode.name <> invalid and episode.name <> "" then epLine = epLine + "  " + episode.name
                if episode.overview <> invalid and episode.overview <> "" then m.synopsis.text = episode.overview
            else if meta.description <> invalid and meta.description <> ""
                m.synopsis.text = meta.description
            end if
            m.headSub.text = epLine
        else
            if meta.description <> invalid and meta.description <> "" then m.synopsis.text = meta.description
            if meta.runtime <> invalid
                runtime = FormatRuntime(meta.runtime)
                if runtime <> "" then m.headSub.text = "Movie  ·  " + runtime
            end if
        end if
    end if
    m.bgPoster.uri = bg
end sub

function EpisodeFor(meta as object, season as object, episode as object) as dynamic
    if meta = invalid or meta.videos = invalid then return invalid
    for each video in meta.videos
        if video.season <> invalid and video.season = season and video.episode <> invalid and video.episode = episode
            return video
        end if
    end for
    return invalid
end function

' Build the right-side list from the loaded m.streams (already wrapped one card
' per stream).
sub PopulateStreams()
    if m.streams.Count() = 0
        m.status.text = "No streams found for this title."
        return
    end if
    m.status.text = ""

    content = CreateObject("roSGNode", "ContentNode")
    for i = 0 to m.streams.Count() - 1
        row = content.CreateChild("ContentNode")
        item = row.CreateChild("ContentNode")
        stream = m.streams[i].stream
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
    m.streamsList.jumpToRowItem = [0, 0]
    m.streamsList.SetFocus(true)
end sub

function HasResource(resources as object, name as string) as boolean
    if resources = invalid then return false
    for each resource in resources
        if resource = name then return true
    end for
    return false
end function

' The card's primary line: the add-on's stream name (Torrentio names already
' carry quality, e.g. "Torrentio\n4K"), then title, then a generic label.
function StreamLabel(stream as object) as string
    label = stream.name
    if label = invalid or label.Trim() = "" then label = stream.title
    if label = invalid or label.Trim() = "" then label = "Stream"
    return FlattenNewlines(label).Trim()
end function

' The card's lines below the name, straight from the stream title split at its
' embedded line feeds exactly as Torrentio ships them — the release, then the
' file path, then "👤 412 💾 54.2 GB ⚙️ RARBG", then a languages line when one
' is present. Direct URLs and add-ons with no title get a "source · quality"
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

' Torrentio names/titles carry embedded line feeds ("Torrentio\n4K"); the card
' labels are single-line, so replace them with a space.
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

' OK on a stream card: direct-URL streams play as-is (nothing blocking); torrent
' streams resolve through StreamResolveTask, which owns the streaming-server
' create call (up to the 120s long timeout on a cold engine) off the render
' thread. A re-entry guard swallows repeat OKs until the resolve reports back.
sub onStreamSelected()
    data = m.streamsList.rowItemSelected
    if data = invalid or data.Count() < 2 then return
    index = data[0]
    if m.streams = invalid or index < 0 or index >= m.streams.Count() then return
    if m.resolving or m.resolveTask <> invalid then return

    stream = m.streams[index].stream
    url = stream.url
    if url <> invalid and url.Trim() <> ""
        StartPlayback(url.Trim())
        return
    end if

    serverAddress = ""
    if m.stores <> invalid and m.stores.settings <> invalid then serverAddress = m.stores.settings.GetServerAddress()

    m.resolving = true
    m.status.text = "Resolving stream…"
    task = CreateObject("roSGNode", "StreamResolveTask")
    task.id = "streamResolve"
    m.top.AppendChild(task)
    task.serverAddress = serverAddress
    task.stream = stream
    task.observeField("result", "onResolveResult")
    m.resolveTask = task
    task.control = "RUN"
end sub

' The resolve finished. Success pushes the player; a failure (e.g. "request
' timed out") surfaces on the status line. Results that land after a Back-out
' are dropped by the m.resolveTask guard.
sub onResolveResult()
    if m.resolveTask = invalid then return
    if not m.resolving then return
    task = m.resolveTask
    m.resolveTask = invalid
    result = task.result
    task.unobserveField("result")
    if task.getParent() <> invalid then m.top.RemoveChild(task)
    m.resolving = false

    if result = invalid or not result.ok
        error = ""
        if result <> invalid then error = result.error
        m.status.text = "Could not play this stream: " + error
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
    m.resolving = false
end sub

sub StartPlayback(url as string)
    m.status.text = "Starting playback…"
    m.top.pushRequest = {
        screen: "playerScreen"
        params: {
            url: url
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
    CancelResolve()
end function

function OnBackPressed() as boolean
    return false
end function

sub BlurFocus()
end sub
