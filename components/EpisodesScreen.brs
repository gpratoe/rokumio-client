' EpisodesScreen — the season/episode browser behind Details' "Episodes".
'
' The hero carries the series identity only (logo or fallback title over the
' artwork); the episode words live on the cards themselves. Below it, one wide
' EpisodeTile per RowList row — the StreamsScreen list architecture: each row
' holds exactly one item, so the list only travels Up/Down and LEFT/RIGHT
' bubble out to the screen, which swallows them to flip the active season (the
' indicator in the top-right corner names it and shows a chevron for each
' direction a season still exists).
'
' Season 0 is Stremio's "specials" bucket (behind-the-scenes extras, not a real
' season), so it is relabelled "Special" and pushed to the end of the list.
'
' Params: { addonAddress, meta, resume } — resume { season, episode } opens the
' list on the watch-in-progress spot when given.

sub init()
    m.heroLogo = m.top.FindNode("heroLogo")
    m.heroLogo.ObserveField("loadStatus", "onHeroLogoStatus")
    m.heroLogoUri = ""
    m.epName = m.top.FindNode("epName")
    m.bgPoster = m.top.FindNode("bgPoster")
    m.seasonName = m.top.FindNode("seasonName")
    m.seasonLeft = m.top.FindNode("seasonLeft")
    m.seasonRight = m.top.FindNode("seasonRight")
    m.epStatus = m.top.FindNode("epStatus")
    m.epList = m.top.FindNode("epList")

    t = Theme()
    m.top.FindNode("bgScrim").color = t.scrim
    m.epName.color = t.textPrimary
    m.seasonName.color = t.textPrimary
    m.seasonLeft.blendColor = t.textSecondary
    m.seasonRight.blendColor = t.textSecondary
    m.epStatus.color = t.textSecondary

    m.epList.ObserveField("rowItemSelected", "onItemSelected")

    m.seasons = []
    m.seasonEpisodes = []
    m.seasonRuns = []
    m.seriesMarks = []
    m.dateParts = []
    m.dateOffsets = []
    m.seasonContents = []
    m.activeRow = -1
    m.focusItem = invalid
    ' The language the content tree was built in — a language change rebuilds it.
    m.textsLanguage = ""
end sub

' LEFT/RIGHT never belong to the list (each row holds one item, so there is
' nothing horizontal to move to) — they flip the season here. At the ends there
' is nothing to move to, so the key is left for the stack/Scene. OPTIONS keeps
' the watched-status dialog.
function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "left"
        if m.activeRow > 0
            SelectSeason(m.activeRow - 1)
            return true
        end if
    else if key = "right"
        if m.seasons.Count() > 0 and m.activeRow < m.seasons.Count() - 1
            SelectSeason(m.activeRow + 1)
            return true
        end if
    else if key = "options"
        if m.epList <> invalid and m.epList.HasFocus()
            if ShowWatchDialog() then return true
        end if
    end if
    return false
end function

function OnEnter(params as object) as void
    ' The language first: the season label and the episode labels are words, and
    ' a language changed since the last visit makes them wrong.
    RefreshTexts()
    if m.textsLanguage <> TextsLanguage()
        ' The visited season survives (that is the point of the re-entry path
        ' below), but the words on it do not survive a language change — so the
        ' cached pages are dropped and rebuilt from the series already loaded,
        ' with no fetch.
        m.textsLanguage = TextsLanguage()
        if m.seriesMeta <> invalid and m.stores <> invalid then
            BuildList(m.seriesMeta)
            return
        end if
    end if
    ' Re-entry after a push (streams, player, …): params is invalid and the
    ' screen Group was handed focus by the stack. The episode list must take
    ' it back, or nothing inside is reachable — the season and its cards
    ' survive, so no rebuild is needed.
    if params = invalid
        RestoreFocus()
        ' A pushed screen (streams, player) just popped back: the store's watched
        ' map may have moved while it had focus, so repaint the badge marks in
        ' place — the row and its cards survive the trip, no rebuild needed.
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

    logo = StringOf(m.meta.logo)
    if logo <> m.heroLogoUri
        m.heroLogoUri = logo
        m.heroLogo.uri = logo
    end if
    ApplyHeroLogo()

    LoadSeries()
end function

' Logo artwork: a loaded logo takes the hero slot and the title steps aside;
' artwork that never loaded, or none offered at all, leaves the title up.
sub ApplyHeroLogo()
    if m.heroLogoUri = ""
        m.heroLogo.visible = false
        m.epName.visible = true
        ResetHeroLogoLayout()
    else
        ready = m.heroLogo.loadStatus = "ready"
        m.heroLogo.visible = ready
        m.epName.visible = not ready
        if ready then FitHeroLogo() else ResetHeroLogoLayout()
    end if
end sub

sub onHeroLogoStatus()
    if m.heroLogo.uri <> m.heroLogoUri then return
    ApplyHeroLogo()
end sub

' The hero box: a tall narrow logo centers in the portrait envelope, a wide one
' rises to the band like Details'. The fallback title sits beneath the same
' top-left anchor.
sub FitHeroLogo()
    fit = HeroFit(m.heroLogo.bitmapWidth, m.heroLogo.bitmapHeight)
    if fit = invalid then return
    m.heroLogo.width = fit.width
    m.heroLogo.height = fit.height
    if fit.tall
        m.heroLogo.translation = [162, 72 + Int((460 - fit.height) / 2)]
    else
        m.heroLogo.translation = [162, 72 + Int((190 - fit.height) / 2)]
    end if
end sub

sub ResetHeroLogoLayout()
    m.heroLogo.translation = [162, 72]
    m.heroLogo.width = 820
    m.heroLogo.height = 460
end sub

' Begin a fresh season load: clear the old list, swap the status line to a
' loading hint, and fetch the series meta off the UI thread. Re-entry with a new
' series supersedes whatever is still in flight (CancelLoad drops it first).
sub LoadSeries()
    if m.meta = invalid then return
    m.epList.content = CreateObject("roSGNode", "ContentNode")
    m.epList.numRows = 0
    m.seasons = []
    m.seasonEpisodes = []
    m.seasonRuns = []
    m.seriesMarks = []
    m.dateParts = []
    m.dateOffsets = []
    m.seasonContents = []
    m.activeRow = -1
    UpdateSeasonIndicator()
    m.epStatus.text = Lang("episodes", "loading")
    m.epStatus.text = Lang("episodes", "loading")
    m.epStatus.visible = true

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

' The series meta came back. Failure leaves the status line with a message and
' the list empty (Back pops); success lays out the active season.
sub onSeriesLoaded()
    if m.loadTask = invalid then return
    task = m.loadTask
    m.loadTask = invalid
    result = task.result
    AsyncTask_Reap(task, m.top, false)

    if result = invalid or not result.ok or result.meta = invalid
        m.epStatus.text = Lang("episodes", "loadFailed")
        return
    end if
    m.seriesMeta = result.meta
    BuildList(result.meta)
end sub

' Lay the series data out from an already-fetched series meta. Each episode card
' carries a checked badge when LibraryStore says it is watched, and its air-date
' line + synopsis from the meta; the full ordered episode-id list is resolved
' first so the account bitfield decodes against the complete list (bit indexes
' are positions in that ordering).
sub BuildList(meta as object)
    seriesData = m.stores.episodes.callFunc("EpisodesSeriesData", m.meta.id, meta)
    if seriesData = invalid or seriesData.seasons = invalid or seriesData.seasons.Count() = 0
        UpdateSeasonIndicator()
        m.epStatus.text = Lang("episodes", "noneFound")
        m.epStatus.visible = true
        return
    end if

    m.seasons = seriesData.seasons
    m.seasonRuns = seriesData.runs
    orderedEpisodes = seriesData.orderedVideoIds
    m.orderedVideoIds = orderedEpisodes
    nowIso = m.stores.time.callFunc("TimeNowIso")

    ' Phase 1: one grouping pass over the series meta, then one series-wide
    ' marks call. The old path sent the whole meta to EpisodesForSeason once
    ' per season, and the whole ordered-id list to LibraryEpisodeMarks once
    ' per season; both copies and the account-bitfield decode repeated 39
    ' times for The Simpsons. These two queries do that work once per series —
    ' and the air dates join them as one batch (the cards each carry a date
    ' line, so per-episode store calls would reintroduce exactly the N-crossings
    ' this phase exists to avoid).
    m.seasonEpisodes = []
    allEps = []
    m.dateOffsets = []
    for each seasonRun in m.seasonRuns
        m.seasonEpisodes.Push(seasonRun.episodes)
        m.dateOffsets.Push(allEps.Count())
        for each ep in seasonRun.episodes
            allEps.Push(ep)
        end for
    end for
    m.seriesMarks = m.stores.library.callFunc("LibraryEpisodeMarksForSeries", m.meta.id, m.seasonRuns, orderedEpisodes, nowIso)
    m.dateParts = m.stores.time.callFunc("TimeAirDatePartsBatch", allEps)

    ' Series-complete check once per build, as before.
    WatchedSummary()

    ' A language change jumps here with the cursor already inside the series;
    ' a fresh entry starts from the resume hint (or the first season).
    m.seasonContents = []
    position = ResumePosition()
    m.focusItem = position[1]
    cursor = m.activeRow
    if cursor < 0 or cursor >= m.seasons.Count() then cursor = position[0]
    m.activeRow = cursor
    RenderSeason(cursor)
end sub

' The watched/count summary the store needs to stamp a series complete. One
' scan over all seasons' marks: specials (season 0) are outside the ordered
' bitfield, so they contribute nothing.
sub WatchedSummary()
    anyRegular = false
    allDone = true
    for s = 0 to m.seasons.Count() - 1
        if m.seasons[s] = 0 then continue for
        marks = m.seriesMarks[s].marks
        for e = 0 to m.seasonEpisodes[s].Count() - 1
            mark = MarkAt(marks, e)
            if mark.aired
                anyRegular = true
                if not mark.watched then allDone = false
            end if
        end for
    end for
    m.stores.library.callFunc("LibraryMarkAllIfDone", m.meta.id, anyRegular, allDone)
end sub

' Build (or reuse) the active season's card page and hand the list to it. Pages
' are cached per season so a LEFT/RIGHT flip that comes back costs no rebuild;
' watched edits invalidate the other seasons' pages (see RefreshWatchedMarks).
sub RenderSeason(rowIndex as integer)
    if rowIndex < 0 or rowIndex >= m.seasons.Count() then return
    m.activeRow = rowIndex

    if m.seasonContents[rowIndex] = invalid then BuildSeasonPage(rowIndex)

    m.epStatus.visible = false
    m.epList.content = m.seasonContents[rowIndex]
    m.epList.numRows = m.seasonEpisodes[rowIndex].Count()
    ' A fresh build lands focus on the resume spot; a season flip starts at the
    ' first card. The hint is spent on its first use so a flip back and forth
    ' does not keep re-jumping.
    index = 0
    if m.focusItem <> invalid and m.focusItem > 0
        index = m.focusItem
        if index >= m.epList.numRows then index = m.epList.numRows - 1
        m.focusItem = invalid
    end if
    if m.epList.numRows > 0 then m.epList.jumpToRowItem = [index, 0]
    UpdateSeasonIndicator()
    if m.top.screenActive then m.epList.SetFocus(true)
end sub

' One season's full ContentNode page: a card per episode with its label
' (S#E# name), thumbnail, watched/aired verdicts, air-date line and synopsis.
sub BuildSeasonPage(rowIndex as integer)
    season = m.seasons[rowIndex]
    episodes = m.seasonEpisodes[rowIndex]
    marks = []
    if season <> 0 and m.seriesMarks <> invalid and rowIndex < m.seriesMarks.Count()
        marks = m.seriesMarks[rowIndex].marks
    end if
    dateBase = m.dateOffsets[rowIndex]

    content = CreateObject("roSGNode", "ContentNode")
    for e = 0 to episodes.Count() - 1
        ep = episodes[e]
        ' Two levels, like every RowList page: the row node is the row the
        ' list walks, the item under it is what the tile component receives.
        row = content.CreateChild("ContentNode")
        item = row.CreateChild("TileContent")
        item.title = EpisodeLabel(season, ep)
        ' StringOf: thumbnails are add-on JSON too, and hdPosterUrl is a typed
        ' string field — a numeric thumbnail would throw on the compare first
        ' and on the assignment next.
        thumbnail = StringOf(ep.thumbnail)
        if thumbnail <> "" then item.hdPosterUrl = thumbnail
        if season <> 0
            mark = MarkAt(marks, e)
            item.watched = mark.watched
            item.aired = mark.aired
        end if
        ' The date line: parts came back in the series-wide batch, marked
        ' invalid when an episode had no usable date.
        dateText = ""
        upcoming = false
        if m.dateParts <> invalid and dateBase + e < m.dateParts.Count()
            dateText = AirDateLabel(m.dateParts[dateBase + e])
            if m.dateParts[dateBase + e] <> invalid then upcoming = m.dateParts[dateBase + e].upcoming
        end if
        item.dateLabel = dateText
        item.dateUpcoming = upcoming
        ' StringOf, not a raw field: an add-on overview can arrive as a number,
        ' and description is a typed string field.
        item.description = StringOf(ep.overview)
    end for
    while m.seasonContents.Count() <= rowIndex
        m.seasonContents.Push(invalid)
    end while
    m.seasonContents[rowIndex] = content
end sub

' Fill the date-line template for one episode's parts. The store answers WHEN,
' the screen says it: month names and the words are ours (the table), the
' verdict aired/upcoming comes back as a fact. No parts at all → no line.
function AirDateLabel(parts as object) as string
    if parts = invalid then return ""
    dateText = Fill(Lang("common", "dateFormat"), {
        month: MonthName(parts.month)
        day: parts.day
        year: parts.year
    })
    if not parts.known
        return dateText
    else if parts.upcoming
        return Fill(Lang("common", "airDatePremieres"), { date: dateText })
    end if
    return Fill(Lang("common", "airDateAired"), { date: dateText })
end function

' Season indicator chrome: the active season's name, and a chevron for each
' direction a season still exists. Hidden entirely while no season is active.
sub UpdateSeasonIndicator()
    if m.activeRow < 0 or m.activeRow >= m.seasons.Count()
        m.seasonName.text = ""
        m.seasonLeft.visible = false
        m.seasonRight.visible = false
        return
    end if
    m.seasonName.text = SeasonLabel(m.seasons[m.activeRow])
    m.seasonLeft.visible = m.activeRow > 0
    m.seasonRight.visible = m.activeRow < m.seasons.Count() - 1
end sub

' Move the whole page to another season. The list keeps focus — only its
' content and the indicator change.
sub SelectSeason(rowIndex as integer)
    if rowIndex < 0 or rowIndex >= m.seasons.Count() then return
    if rowIndex = m.activeRow then return
    RenderSeason(rowIndex)
end sub

' Re-paint the episode watched badges in place after a return from a push
' (streams, player): the visible page's tiles are patched live, the other
' seasons' cached pages are dropped so their next render recomputes, and the
' series-complete check runs anew in case the last episode was just finished.
sub RefreshWatchedMarks() as void
    if m.epList = invalid or m.epList.content = invalid then return
    if m.seasons.Count() = 0 or m.seasonEpisodes.Count() = 0 then return
    if m.stores = invalid or m.seriesMeta = invalid then return
    if m.activeRow < 0 or m.activeRow >= m.seasons.Count() then return
    orderedEpisodes = m.stores.episodes.callFunc("EpisodesOrderedVideoIds", m.meta.id, m.seriesMeta)
    nowIso = m.stores.time.callFunc("TimeNowIso")
    ' One series-wide refreshed marks call, then three uses of it: this season's
    ' live repaint, the summary, and the cache.
    m.seriesMarks = m.stores.library.callFunc("LibraryEpisodeMarksForSeries", m.meta.id, m.seasonRuns, orderedEpisodes, nowIso)
    for i = 0 to m.seasons.Count() - 1
        if i <> m.activeRow then m.seasonContents[i] = invalid
    end for

    marks = []
    if m.seasons[m.activeRow] <> 0 and m.activeRow < m.seriesMarks.Count()
        marks = m.seriesMarks[m.activeRow].marks
    end if
    episodes = m.seasonEpisodes[m.activeRow]
    page = m.epList.content
    for e = 0 to episodes.Count() - 1
        rowNode = page.GetChild(e)
        if rowNode = invalid then exit for
        item = rowNode.GetChild(0)
        if item = invalid then exit for
        if m.seasons[m.activeRow] <> 0
            mark = MarkAt(marks, e)
            item.watched = mark.watched
            item.aired = mark.aired
        end if
    end for
    WatchedSummary()
end sub

' The mark for one episode of a run, or an empty one when the run did not
' answer for it. The run always answers (the store pushes one mark per
' episode), so a missing one is a store bug — and it must not take the screen
' down with it: this runs on the render thread, which is the worst place to
' crash.
function MarkAt(marks as object, index as integer) as object
    if marks = invalid then return { aired: false, watched: false }
    if index < 0 or index >= marks.Count() then return { aired: false, watched: false }
    mark = marks[index]
    if mark = invalid then return { aired: false, watched: false }
    return mark
end function

' The month name, in the display language. The names are a list in the table
' (a list is a thing the table can hold), and the store hands the month as a
' number — so the two meet here.
function MonthName(month as integer) as string
    months = LangList("common", "months")
    if months = invalid or month < 1 or month > months.Count() then return month.ToStr()
    return months[month - 1]
end function

function SeasonLabel(season as integer) as string
    if season = 0 then return Lang("episodes", "special")
    return Fill(Lang("episodes", "season"), { number: season.ToStr() })
end function

' "S#E#  name" for a card — "Special E#  name" for season 0.
'
' ep.name is add-on data: an add-on that answers the episode name with a number
' makes the raw concatenation throw (the same Type Mismatch the detail header
' hit on imdbRating), so the name arrives coerced.
function EpisodeLabel(season as integer, ep as object) as string
    number = ""
    if ep.episode <> invalid then number = ep.episode.ToStr()
    if season = 0
        label = Fill(Lang("episodes", "specialEpisode"), { number: number })
    else
        label = Fill(Lang("common", "episodeMarker"), { season: season.ToStr(), episode: number })
    end if
    if ep.name <> invalid and StringOf(ep.name) <> "" then label = label + "  " + StringOf(ep.name)
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

' A card's OK lands on its episode: rowItemSelected's row IS the episode index
' of the active season's page.
sub onItemSelected()
    data = m.epList.rowItemSelected
    if data = invalid or data.Count() < 2 then return
    entry = EntryAt(data[0])
    if entry = invalid then return
    PushEpisode(entry.season, entry.ep)
end sub

' The OPTIONS key on a focused regular (non-season-0) episode opens the
' watched-status dialog — season 0 specials are not part of the ordered/
' bitfield list, so they never offer it. Returns true when a dialog was shown.
' The "rest of season" actions are scoped to the focused season's page: they
' cover that season's episodes from its first up to (and including) the focused
' one, so a season can be caught up or reverted without touching any other
' season's marks.
function ShowWatchDialog() as boolean
    if m.meta = invalid or m.orderedVideoIds = invalid or m.orderedVideoIds.Count() = 0 then return false
    if m.stores = invalid then return false
    data = m.epList.rowItemFocused
    if data = invalid or data.Count() < 2 then return false
    entry = EntryAt(data[0])
    if entry = invalid or entry.season = 0 or entry.ep = invalid or entry.ep.episode = invalid then return false
    if m.activeRow < 0 or m.activeRow >= m.seasons.Count() then return false

    videoId = m.stores.episodes.callFunc("EpisodesResolveVideoId", m.meta.id, entry.season, entry.ep.episode)
    seasonIds = SeasonVideoIds(m.activeRow)
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
    syncNote = Lang("episodes", "syncedToAccount")
    if not stremio then syncNote = Lang("episodes", "savedOnDevice")
    ' Both dialogs read alike: a QUESTION on top, and the episode it is about
    ' on the line below it, with the sync note under that. The title is a
    ' question (so a language can open it with its own question mark), and the
    ' episode is a line.
    episode = EpisodeLabel(entry.season, entry.ep)
    dialog = CreateObject("roSGNode", "StandardMessageDialog")
    if mark.watched
        dialog.title = Lang("episodes", "markUnwatchedTitle")
        dialog.buttons = [Lang("episodes", "markUnwatchedButton"), Lang("episodes", "markSeasonUnwatchedButton"), Lang("common", "cancel")]
    else
        dialog.title = Lang("episodes", "markWatchedTitle")
        dialog.buttons = [Lang("episodes", "markWatchedButton"), Lang("episodes", "markSeasonWatchedButton"), Lang("common", "cancel")]
    end if
    dialog.message = [episode, syncNote]
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
    if kind = "watch"
        m.stores.library.callFunc("LibraryMarkEpisodeWatched", action.metaId, action.videoId)
    else if kind = "restWatched"
        m.stores.library.callFunc("LibraryMarkUpToWatched", action.metaId, action.seasonIds, action.seasonIndex)
    else if kind = "restUnwatched"
        m.stores.library.callFunc("LibraryMarkUpToUnwatched", action.metaId, action.seasonIds, action.seasonIndex)
    else
        m.stores.library.callFunc("LibraryMarkEpisodeUnwatched", action.metaId, action.videoId)
    end if
    m.top.watchedChange = {
        metaId: action.metaId
        videoId: action.videoId
        orderedVideoIds: m.orderedVideoIds
        name: m.meta.name
        metaType: m.meta.type
        poster: m.meta.poster
        posterShape: m.meta.posterShape
    }
    RefreshWatchedMarks()
end sub

' The watchable video ids of the current season page, in display order — the
' slice of the series' ordered list the page owns, so a season-scoped mark
' lands exactly on that season's non-special episodes.
function SeasonVideoIds(rowIndex as integer) as object
    ids = []
    if rowIndex < 0 or rowIndex >= m.seasons.Count() then return ids
    if m.stores = invalid then return ids
    episodes = m.seasonEpisodes[rowIndex]
    for each ep in episodes
        if ep <> invalid and ep.episode <> invalid
            ids.Push(m.stores.episodes.callFunc("EpisodesResolveVideoId", m.meta.id, m.seasons[rowIndex], ep.episode))
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

function EntryAt(episodeIndex as integer) as object
    if m.seasons.Count() = 0 then return invalid
    if m.activeRow < 0 or m.activeRow >= m.seasons.Count() then return invalid
    episodes = m.seasonEpisodes[m.activeRow]
    if episodes = invalid or episodeIndex < 0 or episodeIndex >= episodes.Count() then return invalid
    return { season: m.seasons[m.activeRow], ep: episodes[episodeIndex] }
end function

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
            posterShape: m.meta.posterShape
            logo: m.meta.logo
            background: m.meta.background
            episodeName: ep.name
            episodeOverview: ep.overview
        }
    }
end sub

' Re-entry: the visible season survives a push, so focus goes straight back to
' the list; nothing renders because nothing was cleared.
sub RestoreFocus()
    if m.activeRow < 0 or m.activeRow >= m.seasons.Count() then return
    if m.seasonEpisodes[m.activeRow].Count() = 0 then return
    if m.top.screenActive then m.epList.SetFocus(true)
end sub

function OnExit() as void
end function

function OnBackPressed() as boolean
    return false
end function

sub BlurFocus()
end sub
