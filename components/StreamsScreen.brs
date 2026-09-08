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
    m.params = params
    name = params.name
    if name = invalid then name = ""
    m.headTitle.text = name

    RenderMeta(params)
    RenderStreams(params)
end function

' Fill the left panel from the full meta (episodes.GetMeta against the meta
' add-on). The fetched meta carries the real title, background artwork and
' synopsis the slim catalog params lack.
sub RenderMeta(params as object)
    meta = invalid
    if m.stores <> invalid and m.stores.episodes <> invalid
        answer = m.stores.episodes.GetMeta(params.addonAddress, params.metaType, params.metaId)
        if answer.ok then meta = answer.meta
    end if

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

' Collect every stream candidate from the installed add-ons that advertise the
' "stream" resource, then fill the right-side list.
sub RenderStreams(params as object)
    m.streams = []
    m.status.text = "Looking for streams…"
    m.streamsList.content = invalid

    if m.stores = invalid or m.stores.addons = invalid or m.stores.playback = invalid then return
    for each addon in m.stores.addons.GetAll()
        if addon.resources <> invalid and HasResource(addon.resources, "stream")
            result = m.stores.playback.Streams(addon.address, params.metaType, params.videoId)
            if result.ok and result.streams <> invalid
                for each stream in result.streams
                    m.streams.Push({
                        stream: stream
                        addonName: addon.name
                    })
                end for
            end if
        end if
    end for

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

' OK on a stream card: resolve to a playable URL (direct URLs play as-is; torrent
' streams need the streaming server, configured via SettingsStore once the
' settings screen exists) and push the player.
sub onStreamSelected()
    data = m.streamsList.rowItemSelected
    if data = invalid or data.Count() < 2 then return
    index = data[0]
    if m.streams = invalid or index < 0 or index >= m.streams.Count() then return
    if m.stores = invalid or m.stores.playback = invalid then return

    stream = m.streams[index].stream
    serverAddress = ""
    if m.stores.settings <> invalid then serverAddress = m.stores.settings.GetServerAddress()
    result = m.stores.playback.ResolvePlayback(serverAddress, stream)
    if not result.ok
        m.status.text = "Could not play this stream: " + result.error
        return
    end if

    m.status.text = "Starting playback…"
    m.top.pushRequest = {
        screen: "playerScreen"
        params: {
            url: result.url
            metaType: m.params.metaType
            metaId: m.params.metaId
            videoId: m.params.videoId
            season: m.params.season
            episode: m.params.episode
            position: m.params.position
            name: m.headTitle.text
            poster: m.params.poster
        }
    }
end sub

sub RestoreFocus()
    if m.streams.Count() > 0 then m.streamsList.SetFocus(true)
end sub

function OnExit() as void
end function

function OnBackPressed() as boolean
    return false
end function

sub BlurFocus()
end sub
