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

    t = Theme()
    m.top.FindNode("bgScrim").color = t.scrim
    m.epName.color = t.accent
    m.epTitle.color = t.accent
    m.epDesc.color = t.textSecondary
    m.epList.rowLabelTextColor = t.textSecondary

    m.epList.ObserveField("rowItemFocused", "onItemFocused")
    m.epList.ObserveField("rowItemSelected", "onItemSelected")

    m.seasons = []
    m.seasonEpisodes = []
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if key = "options" and press
        if m.epList <> invalid and m.epList.HasFocus()
            if ShowWatchDialog() then return true
        end if
    end if
    return false
end function

function OnEnter(params as object) as void
    ' Re-entry after a push (streams, player, …): params is invalid and the
    ' screen Group was handed focus by the stack. The episode RowList must take
    ' it back, or nothing inside is reachable — the list and its seasons survive,
    ' so no rebuild is needed.
    if params = invalid
        if m.epList <> invalid then m.epList.SetFocus(true)
        ' A pushed screen (streams, player) just popped back: the store's watched
        ' map may have moved while it had focus, so repaint the badge marks in
        ' place — the list nodes themselves survive the trip, no rebuild needed.
        RefreshWatchedMarks()
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
    m.orderedVideoIds = []
    m.epTitle.text = ""
    m.epDesc.text = "Loading episodes…"

    CancelLoad()
    task = AsyncTask_Launch(m.top, "MetaLoaderTask", "onSeriesLoaded", {
        addonAddress: m.addonAddress
        metaType: "series"
        metaId: m.meta.id
    }, "episodesLoader")
    m.loadTask = task
end sub

' Tear down an in-flight season load (a newer entry supersedes it). STOP is the
' real cancel — merely removing a running Task node does not kill its worker
' thread — and dropping the observer means its result can never land; re-entering
' this screen builds the list afresh anyway.
sub CancelLoad()
    if m.loadTask <> invalid
        task = m.loadTask
        m.loadTask = invalid
        AsyncTask_Reap(task, m.top, true)
    end if
end sub

' The series meta came back. Failure leaves the header with a message and the
' list empty (Back pops); success lays out a row per season.
sub onSeriesLoaded()
    if m.loadTask = invalid then return
    task = m.loadTask
    m.loadTask = invalid
    result = task.result
    AsyncTask_Reap(task, m.top, false)

    if result = invalid or not result.ok or result.meta = invalid
        m.epTitle.text = ""
        m.epDesc.text = "Series information could not be loaded."
        return
    end if
    m.seriesMeta = result.meta
    BuildList(result.meta)
end sub

' Lay out one RowList row per season from an already-fetched series meta. Each
' episode tile carries a checked badge when LibraryStore says it is watched; the
' full ordered episode-id list is resolved first so the account bitfield decodes
' against the complete list (bit indexes are positions in that ordering).
sub BuildList(meta as object)
    allSeasons = m.stores.episodes.callFunc("EpisodesSeasons", meta)
    if allSeasons.Count() = 0
        m.epTitle.text = ""
        m.epDesc.text = "No episodes found for this series."
        return
    end if

    m.seasons = m.stores.episodes.callFunc("EpisodesOrderedSeasons", allSeasons)
    orderedEpisodes = m.stores.episodes.callFunc("EpisodesOrderedVideoIds", m.meta.id, meta)
    m.orderedVideoIds = orderedEpisodes

    content = CreateObject("roSGNode", "ContentNode")
    anyRegular = false
    allDone = true
    nowIso = invalid
    if m.stores <> invalid then nowIso = m.stores.time.callFunc("TimeNowIso")
    for s = 0 to m.seasons.Count() - 1
        season = m.seasons[s]
        episodes = m.stores.episodes.callFunc("EpisodesEpisodesForSeason", meta, season)
        m.seasonEpisodes.Push(episodes)

        row = content.CreateChild("ContentNode")
        row.title = SeasonLabel(season)
        for each ep in episodes
            item = row.CreateChild("TileContent")
            item.title = EpisodeLabel(season, ep)
            if ep.thumbnail <> invalid and ep.thumbnail <> "" then item.hdPosterUrl = ep.thumbnail
            if season <> 0
                mark = m.stores.library.callFunc("LibraryEpisodeMark", m.meta.id, season, ep, orderedEpisodes, nowIso)
                item.watched = mark.watched
                if mark.aired
                    anyRegular = true
                    if not item.watched then allDone = false
                end if
            end if
        end for
    end for

    m.epList.content = content
    m.epList.numRows = m.seasons.Count()
    m.epList.jumpToRowItem = ResumePosition()
    if m.top.screenActive then m.epList.SetFocus(true)
    UpdateHeader(m.epList.jumpToRowItem)

    m.stores.library.callFunc("LibraryMarkAllIfDone", m.meta.id, anyRegular, allDone)
end sub

' Re-paint the episode watched badges in place after a return from a push
' (streams, player): the existing row/tile nodes are kept, so focus and scroll
' survive, and each tile's watched flag is recomputed against the current store
' state. A no-op when nothing flipped; the series-complete check runs anew in
' case the last episode was just finished.
sub RefreshWatchedMarks() as void
    if m.epList = invalid or m.epList.content = invalid then return
    if m.seasons.Count() = 0 or m.seasonEpisodes.Count() = 0 then return
    if m.stores = invalid or m.seriesMeta = invalid then return
    orderedEpisodes = m.stores.episodes.callFunc("EpisodesOrderedVideoIds", m.meta.id, m.seriesMeta)
    anyRegular = false
    allDone = true
    nowIso = m.stores.time.callFunc("TimeNowIso")
    for s = 0 to m.seasons.Count() - 1
        season = m.seasons[s]
        row = m.epList.content.GetChild(s)
        episodes = m.seasonEpisodes[s]
        for e = 0 to episodes.Count() - 1
            ep = episodes[e]
            item = row.GetChild(e)
            if season <> 0
                mark = m.stores.library.callFunc("LibraryEpisodeMark", m.meta.id, season, ep, orderedEpisodes, nowIso)
                item.watched = mark.watched
                if mark.aired
                    anyRegular = true
                    if not item.watched then allDone = false
                end if
            end if
        end for
    end for
    m.stores.library.callFunc("LibraryMarkAllIfDone", m.meta.id, anyRegular, allDone)
end sub

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
' cell. Rows follow the store's OrderedSeasons order, so specials live at the end.
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

' The OPTIONS key on a focused regular (non-season-0) episode opens the
' watched-status dialog — season 0 specials are not part of the ordered/
' bitfield list, so they never offer it. Returns true when a dialog was shown.
' The "rest of season" actions are scoped to the focused season's row: they
' cover that season's episodes from its first up to (and including) the focused
' one, so a season can be caught up or reverted without touching any other
' season's marks.
function ShowWatchDialog() as boolean
    if m.meta = invalid or m.orderedVideoIds = invalid or m.orderedVideoIds.Count() = 0 then return false
    if m.stores = invalid then return false
    data = m.epList.rowItemFocused
    if data = invalid or data.Count() < 2 then return false
    row = data[0]
    entry = EntryAt(data[0], data[1])
    if entry = invalid or entry.season = 0 or entry.ep = invalid or entry.ep.episode = invalid then return false

    videoId = m.stores.episodes.callFunc("EpisodesResolveVideoId", m.meta.id, entry.season, entry.ep.episode)
    seasonIds = SeasonVideoIds(row)
    seasonIndex = IndexInIds(seasonIds, videoId)
    if seasonIndex < 0 then return false
    mark = m.stores.library.callFunc("LibraryEpisodeMark", m.meta.id, entry.season, entry.ep, m.orderedVideoIds, m.stores.time.callFunc("TimeNowIso"))

    m.pendingWatchAction = {
        metaId: m.meta.id
        videoId: videoId
        seasonIds: seasonIds
        seasonIndex: seasonIndex
        watched: mark.watched
    }

    stremio = m.stores.auth.callFunc("AuthGetSession") = "stremio"
    syncNote = "Synced to your Stremio account."
    if not stremio then syncNote = "Saved on this device only."
    dialog = CreateObject("roSGNode", "StandardMessageDialog")
    if mark.watched
        dialog.title = "Mark as not watched?"
        dialog.message = [syncNote]
        dialog.buttons = ["Mark as not watched", "Mark rest of season as unwatched", "Cancel"]
    else
        dialog.title = EpisodeLabel(entry.season, entry.ep) + " — mark watched?"
        dialog.message = [syncNote]
        dialog.buttons = ["Mark watched", "Mark rest of season as watched", "Cancel"]
    end if
    dialog.observeField("buttonSelected", "onWatchChoice")
    m.top.getScene().dialog = dialog
    return true
end function

' A dialog button landed. Reset the Scene's dialog slot, apply the chosen edit
' to the store (which publishes the account push and repaints the badges), then
' hand focus back to the list. An unwatched dialog's index = 0 is "mark this
' episode watched", index = 1 is "mark rest of this season watched"; a watched
' dialog's index = 0 is "mark as not watched", index = 1 is "mark rest of this
' season unwatched". Both rest-of-season actions revert their own counterpart.
sub onWatchChoice()
    dialog = m.top.getScene().dialog
    if dialog <> invalid
        index = dialog.buttonSelected
        if index = invalid then index = -1
        m.top.getScene().dialog = invalid
        action = m.pendingWatchAction
        m.pendingWatchAction = invalid
        if action <> invalid
            if action.watched
                if index = 0
                    ApplyWatchChange("unwatch", action)
                else if index = 1
                    ApplyWatchChange("restUnwatched", action)
                end if
            else
                if index = 0
                    ApplyWatchChange("watch", action)
                else if index = 1
                    ApplyWatchChange("restWatched", action)
                end if
            end if
        end if
    end if
    if m.epList <> invalid then m.epList.SetFocus(true)
end sub

' Apply a watched edit: mutate the store's local display layer, publish the
' change so MainScene can push it to the account, then repaint the tiles in
' place (which re-runs the series-complete check for the grid "done" badge).
' "restWatched"/"restUnwatched" operate on the focused season's video id list,
' from its first episode through the focused one.
sub ApplyWatchChange(kind as string, action as object)
    if m.stores = invalid then return
    library = m.stores.library
    if kind = "watch"
        library.MarkEpisodeWatched(action.metaId, action.videoId)
    else if kind = "restWatched"
        library.MarkUpToWatched(action.metaId, action.seasonIds, action.seasonIndex)
    else if kind = "restUnwatched"
        library.MarkUpToUnwatched(action.metaId, action.seasonIds, action.seasonIndex)
    else
        library.MarkEpisodeUnwatched(action.metaId, action.videoId)
    end if
    m.top.watchedChange = {
        metaId: action.metaId
        videoId: action.videoId
        orderedVideoIds: m.orderedVideoIds
    }
    RefreshWatchedMarks()
end sub

' The watchable video ids of one season row, in display order — the slice of the
' series' ordered list that row owns, so a season-scoped mark lands exactly on
' that season's non-special episodes.
function SeasonVideoIds(row as integer) as object
    ids = []
    if row < 0 or row >= m.seasons.Count() then return ids
    if m.stores = invalid then return ids
    episodes = m.seasonEpisodes[row]
    for each ep in episodes
        if ep <> invalid and ep.episode <> invalid
            ids.Push(m.stores.episodes.callFunc("EpisodesResolveVideoId", m.meta.id, m.seasons[row], ep.episode))
        end if
    end for
    return ids
end function

' The position of a video id in a list (-1 when absent).
function IndexInIds(ids as object, videoId as string) as integer
    if ids = invalid or videoId = "" then return -1
    for i = 0 to ids.Count() - 1
        if ids[i] = videoId then return i
    end for
    return -1
end function

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
    videoId = m.stores.episodes.callFunc("EpisodesResolveVideoId", m.meta.id, season, ep.episode)
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
