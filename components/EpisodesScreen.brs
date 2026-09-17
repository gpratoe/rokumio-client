' EpisodesScreen — the season/episode browser behind Details' "Episodes".
'
' Same pattern as HomeScreen: a single RowList where each row is a season and
' each tile an episode (landscape EpisodeTile). Roku owns the whole grid physics
' — vertical row scrolling/clipping, horizontal per-row tile scrolling, row
' labels, focus reporting and non-focused-row dimming. The top header tracks the
' focused episode's label and synopsis; OK on a tile pushes stream selection.
'
' Season 0 is Stremio's "specials" bucket (behind-the-scenes extras, not a real
' season), so it is relabelled "Special" and pushed to the end of the list.
'
' Params: { addonAddress, meta, resume } — resume { season, episode } lands the
' list back on the watch-in-progress spot when given.

sub init()
    m.epName = m.top.FindNode("epName")
    m.bgPoster = m.top.FindNode("bgPoster")
    m.epTitle = m.top.FindNode("epTitle")
    m.epDesc = m.top.FindNode("epDesc")
    m.epList = m.top.FindNode("epList")

    m.epList.ObserveField("rowItemFocused", "onItemFocused")
    m.epList.ObserveField("rowItemSelected", "onItemSelected")

    m.seasons = []
    m.seasonEpisodes = []
end sub

' Stores are class instances, which cannot cross components through an interface
' field, so the Scene hands them over with callFunc instead.
function SetStores(stores as object) as void
    m.stores = stores
end function

function OnEnter(params as object) as void
    ' Re-entry after a push (streams, player, …): params is invalid and the
    ' screen Group was handed focus by the stack. The episode RowList must take
    ' it back, or nothing inside is reachable — the list and its seasons survive,
    ' so no rebuild is needed.
    if params = invalid
        if m.epList <> invalid then m.epList.SetFocus(true)
        return
    end if
    if params.meta = invalid then return
    m.addonAddress = params.addonAddress
    m.meta = params.meta
    m.resume = params.resume

    name = m.meta.name
    if name = invalid then name = ""
    m.epName.text = name

    bg = m.meta.background
    if bg = invalid then bg = ""
    m.bgPoster.uri = bg

    LoadSeries()
end function

' Begin a fresh season-list build: clear the old list, swap the header to a
' loading hint, and fetch the series meta off the UI thread. Re-entry with a new
' series supersedes whatever is still in flight (CancelLoad drops it first).
sub LoadSeries()
    if m.meta = invalid then return
    m.epList.content = CreateObject("roSGNode", "ContentNode")
    m.epList.numRows = 0
    m.seasons = []
    m.seasonEpisodes = []
    m.epTitle.text = ""
    m.epDesc.text = "Loading episodes…"

    CancelLoad()
    task = CreateObject("roSGNode", "MetaLoaderTask")
    task.id = "episodesLoader"
    m.top.AppendChild(task)
    task.addonAddress = m.addonAddress
    task.metaType = "series"
    task.metaId = m.meta.id
    task.observeField("result", "onSeriesLoaded")
    m.loadTask = task
    task.control = "RUN"
end sub

' Tear down an in-flight season load (a newer entry supersedes it). The worker
' finishes on its own thread; removing the observer means its result can never
' land, and re-entering this screen builds the list afresh anyway.
sub CancelLoad()
    if m.loadTask <> invalid
        task = m.loadTask
        m.loadTask = invalid
        task.unobserveField("result")
        if task.getParent() <> invalid then m.top.RemoveChild(task)
    end if
end sub

' The series meta came back. Failure leaves the header with a message and the
' list empty (Back pops); success lays out a row per season.
sub onSeriesLoaded()
    if m.loadTask = invalid then return
    task = m.loadTask
    m.loadTask = invalid
    task.unobserveField("result")
    if task.getParent() <> invalid then m.top.RemoveChild(task)

    result = task.result
    if result = invalid or not result.ok or result.meta = invalid
        m.epTitle.text = ""
        m.epDesc.text = "Series information could not be loaded."
        return
    end if
    BuildList(result.meta)
end sub

' Lay out one RowList row per season from an already-fetched series meta. Each
' episode tile carries a checked badge when LibraryStore says it is watched; the
' full ordered episode-id list is resolved first so the account bitfield decodes
' against the complete list (bit indexes are positions in that ordering).
sub BuildList(meta as object)
    allSeasons = m.stores.episodes.Seasons(meta)
    if allSeasons.Count() = 0
        m.epTitle.text = ""
        m.epDesc.text = "No episodes found for this series."
        return
    end if

    m.seasons = OrderedSeasons(allSeasons)
    orderedEpisodes = OrderedVideoIds(meta)

    content = CreateObject("roSGNode", "ContentNode")
    anyRegular = false
    allDone = true
    nowIso = invalid
    if m.stores <> invalid and m.stores.library <> invalid then nowIso = m.stores.library.NowIso()
    for s = 0 to m.seasons.Count() - 1
        season = m.seasons[s]
        episodes = m.stores.episodes.EpisodesForSeason(meta, season)
        m.seasonEpisodes.Push(episodes)

        row = content.CreateChild("ContentNode")
        row.title = SeasonLabel(season)
        for each ep in episodes
            item = row.CreateChild("TileContent")
            item.title = EpisodeLabel(season, ep)
            if ep.thumbnail <> invalid and ep.thumbnail <> "" then item.hdPosterUrl = ep.thumbnail
            if season <> 0
                ' An unaired episode can't be watched yet — account bitfields
                ' for a series marked fully watched mark the whole known list,
                ' placeholders included, and literally decoding that would paint
                ' checks on episodes that don't exist yet.
                aired = m.stores.library.EpisodeAired(ep, nowIso)
                item.watched = aired and Watched(season, ep, orderedEpisodes)
                if aired
                    anyRegular = true
                    if not item.watched then allDone = false
                end if
            end if
        end for
    end for

    m.epList.content = content
    m.epList.numRows = m.seasons.Count()
    m.epList.jumpToRowItem = ResumePosition()
    m.epList.SetFocus(true)
    UpdateHeader(m.epList.jumpToRowItem)

    ' The full list is now known: a series whose every regular episode is
    ' watched crosses from in-progress (clock) to done (eye) on the grid
    ' tiles that only carry a coarse SeriesStatus badge.
    if anyRegular and allDone and m.stores <> invalid and m.stores.library <> invalid
        m.stores.library.MarkSeriesDone(m.meta.id)
    end if
end sub

' The series' ordered episode-id list, "{metaId}:{season}:{episode}" per regular
' (non-special) episode in display order — the ordering the account watched
' bitfield indexes.
function OrderedVideoIds(meta as object) as object
    ids = []
    if m.stores = invalid or m.stores.episodes = invalid or m.meta = invalid then return ids
    for s = 0 to m.seasons.Count() - 1
        season = m.seasons[s]
        if season = 0 then continue for
        episodes = m.stores.episodes.EpisodesForSeason(meta, season)
        for each ep in episodes
            if ep.episode <> invalid
                ids.Push(m.stores.episodes.ResolveVideoId(m.meta.id, season, ep.episode))
            end if
        end for
    end for
    return ids
end function

' Per-episode watched, precise (local set or the decoded account bitfield).
function Watched(season as integer, ep as object, orderedEpisodes as object) as boolean
    if m.stores = invalid or m.stores.library = invalid then return false
    if ep = invalid or ep.episode = invalid then return false
    return m.stores.library.EpisodeWatched(m.meta.id, season, ep.episode, orderedEpisodes)
end function

' Real seasons keep ascending order; season 0 (specials) is relabelled and moved
' to the end of the list so it never masquerades as the first broadcast season.
function OrderedSeasons(allSeasons as object) as object
    ordered = []
    specials = []
    for each season in allSeasons
        if season = 0
            specials.Push(0)
        else
            ordered.Push(season)
        end if
    end for
    for each special in specials
        ordered.Push(special)
    end for
    return ordered
end function

function SeasonLabel(season as integer) as string
    if season = 0 then return "Special"
    return "Season " + season.ToStr()
end function

' "S#E#  name" for a tile — "Special E#  name" for season 0.
function EpisodeLabel(season as integer, ep as object) as string
    if season = 0
        label = "Special E"
    else
        label = "S" + season.ToStr() + "E"
    end if
    if ep.episode <> invalid then label = label + ep.episode.ToStr()
    if ep.name <> invalid and ep.name <> "" then label = label + "  " + ep.name
    return label
end function

' [seasonRow, itemIndex] for the resume hint's (season, episode), else the first
' cell. Rows follow OrderedSeasons, so specials live at the end.
function ResumePosition() as object
    if m.resume <> invalid
        for s = 0 to m.seasons.Count() - 1
            if m.seasons[s] <> m.resume.season then continue for
            episodes = m.seasonEpisodes[s]
            for e = 0 to episodes.Count() - 1
                if episodes[e].episode = m.resume.episode then return [s, e]
            end for
            return [s, 0]
        end for
    end if
    return [0, 0]
end function

' rowItemFocused is a [row, itemIndex] pair; drive the header off the focused
' episode.
sub onItemFocused()
    data = m.epList.rowItemFocused
    if data = invalid or data.Count() < 2 then return
    UpdateHeader(data)
end sub

sub onItemSelected()
    data = m.epList.rowItemSelected
    if data = invalid or data.Count() < 2 then return
    entry = EntryAt(data[0], data[1])
    if entry = invalid then return
    PushEpisode(entry.season, entry.ep)
end sub

function EntryAt(row as integer, index as integer) as object
    if m.seasons.Count() = 0 then return invalid
    if row < 0 or row >= m.seasons.Count() then return invalid
    episodes = m.seasonEpisodes[row]
    if episodes = invalid or index < 0 or index >= episodes.Count() then return invalid
    return { season: m.seasons[row], ep: episodes[index] }
end function

sub UpdateHeader(position as object)
    if position = invalid or position.Count() < 2 then return
    entry = EntryAt(position[0], position[1])
    if entry = invalid
        m.epTitle.text = ""
        m.epDesc.text = ""
        return
    end if

    m.epTitle.text = EpisodeLabel(entry.season, entry.ep)

    overview = "No synopsis available."
    ep = entry.ep
    if ep <> invalid and ep.overview <> invalid and ep.overview <> "" then overview = ep.overview
    m.epDesc.text = overview
end sub

' Episodes push stream selection for "{metaId}:{season}:{episode}" — the same
' play path Details' resume chip uses.
sub PushEpisode(season as integer, ep as object)
    if ep = invalid or ep.episode = invalid then return
    videoId = m.stores.episodes.ResolveVideoId(m.meta.id, season, ep.episode)
    position = 0
    if m.resume <> invalid and m.resume.episode <> invalid and m.resume.episode = ep.episode and m.resume.season <> invalid and m.resume.season = season
        position = m.resume.position
    end if
    m.top.pushRequest = {
        screen: "streamsScreen"
        params: {
            addonAddress: m.addonAddress
            metaType: "series"
            metaId: m.meta.id
            videoId: videoId
            season: season
            episode: ep.episode
            position: position
            name: m.meta.name
            poster: m.meta.poster
            logo: m.meta.logo
            background: m.meta.background
            episodeName: ep.name
            episodeOverview: ep.overview
        }
    }
end sub

function OnExit() as void
end function

function OnBackPressed() as boolean
    return false
end function

sub BlurFocus()
end sub
