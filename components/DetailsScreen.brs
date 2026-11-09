' DetailsScreen — one screen for both content kinds.
'
' Movies render a hero (poster, name, type/year/rating, description) plus a chip
' row (Play, and an "add to library" toggle backed by LibraryStore) and push a
' stream selection on Play. Series render the same hero, then a chip row: a
' Resume chip for the saved position (falling back to "Play S1E1" when nothing
' is saved), the same "add to library" toggle, and an "Episodes" chip that
' pushes the dedicated EpisodesScreen.
'
' One shared chips ChipsRow serves both kinds — the chips differ, the
' plumbing doesn't. The row publishes OK through its `selection` field and
' one observer dispatches on the stored action id.

sub init()
    m.bgPoster = m.top.FindNode("bgPoster")
    m.bgScrim = m.top.FindNode("bgScrim")
    m.heroLogo = m.top.FindNode("heroLogo")
    m.heroLogo.ObserveField("loadStatus", "onHeroLogoStatus")
    m.heroLogoUri = ""
    m.detailName = m.top.FindNode("detailName")
    m.detailType = m.top.FindNode("detailType")
    m.detailRating = m.top.FindNode("detailRating")
    m.detailRatingText = m.top.FindNode("detailRatingText")
    m.detailGenres = m.top.FindNode("detailGenres")
    m.detailDesc = m.top.FindNode("detailDesc")
    m.chipsRow = m.top.FindNode("chipsRow")
    ' The language the chips were built in — a language change rebuilds them.
    m.textsLanguage = ""

    t = Theme()
    m.top.FindNode("detailsBg").color = t.screenBg
    m.bgScrim.color = t.scrim
    m.detailName.color = t.textPrimary
    m.detailType.color = t.textSecondary
    m.detailRatingText.color = t.accentWarm
    m.detailGenres.color = t.textSecondary
    m.detailDesc.color = t.textPrimary
    m.chipsRow.ObserveField("selection", "onChipSelected")
end sub

function OnEnter(params as object) as void
    ' The language first, and the chips are the words: they survive a visit
    ' (the re-entry path below), so a language change is what makes them
    ' rebuild.
    RefreshTexts()
    if m.textsLanguage <> TextsLanguage()
        m.textsLanguage = TextsLanguage()
        if m.meta <> invalid
            ' The hero carries the kind ("Movie", "Series") and the chips carry
            ' the actions — both are words, and both survive a visit.
            RenderHero(m.meta)
            if m.meta.type = "series"
                ShowSeries()
            else
                ShowMovie()
            end if
        end if
    end if
    ' Re-entry after a push (EpisodesScreen, streams, …): params is invalid and
    ' the screen Group (not a focus target) was handed focus by the stack. A
    ' chip must take focus back, or nothing inside is reachable.
    if params = invalid
        RestoreFocus()
        return
    end if
    m.params = params
    if params.meta = invalid then return
    meta = params.meta
    m.addonAddress = params.addonAddress
    m.meta = meta

    ' Resume hint: the Continue-Watching row passes its own; otherwise the local
    ' library stands in (catalog-opened shows still know where you stopped).
    if params.resume <> invalid
        m.resume = params.resume
    else if m.stores <> invalid
        m.resume = m.stores.library.callFunc("LibraryResumeFor", meta.id)
    else
        m.resume = invalid
    end if

    m.metaRefreshed = false
    m.textsLanguage = TextsLanguage()
    RenderHero(meta)

    if meta.type = "series"
        ShowSeries()
    else
        ShowMovie()
    end if
    MaybeRefreshMeta()
end function

' Fill the hero chrome from a meta: title, the {type · release · rating} line,
' poster, background and description. Called on entry with the catalog meta, and
' again when a deferred meta fetch returns a fuller record — the passed-in
' values always win, fetched fields only top up the gaps.
sub RenderHero(meta as object)
    if meta = invalid then return

    bg = meta.background
    m.bgPoster.uri = StringOf(bg)
    m.bgPoster.visible = m.bgPoster.uri <> ""

    title = StringOf(meta.name)
    if title.Trim() = "" then title = StringOf(meta.title)
    description = StringOf(meta.description)
    if description.Trim() = "" then description = StringOf(meta.overview)
    if description.Trim() = "" and meta.season <> invalid and meta.episode <> invalid
        description = "S" + StringOf(meta.season) + "E" + StringOf(meta.episode)
    end if
    kind = TypeLabel(StringOf(meta.type))
    releaseInfo = StringOf(meta.releaseInfo)
    if releaseInfo <> "" then kind = kind + " · " + releaseInfo
    runtime = ""
    if StringOf(meta.type) <> "series" then runtime = FormatRuntime(meta.runtime)
    if runtime <> "" then kind = kind + " · " + runtime
    rating = StringOf(meta.imdbRating)
    genres = HeroGenresText(meta.genres)
    logo = StringOf(meta.logo)
    previousLogoUri = m.heroLogo.uri
    m.heroLogoUri = logo
    ResetHeroLogoLayout()
    m.heroLogo.visible = false
    m.detailName.visible = true
    m.detailName.text = title
    m.detailType.text = kind
    m.detailRatingText.text = rating
    m.detailRating.visible = rating.Trim() <> ""
    m.detailGenres.text = genres
    m.detailGenres.visible = genres <> ""
    m.detailDesc.text = description
    m.detailDesc.visible = description.Trim() <> ""
    m.heroLogo.uri = logo
    if logo <> "" and logo = previousLogoUri and m.heroLogo.loadStatus = "ready" then FitHeroLogo()
end sub

' Search and Discover hand over slim catalog metas ({ id, type, name }) whose
' hero fields are missing. Fetch the full Cinemeta record off the UI thread when
' that is the case, then MergeMeta it into m.meta — the caller's non-empty
' values stay put, the fetch only fills the blanks. Already-complete metas,
' metas with nothing fetchable, and metas without an add-on to ask skip the trip
' entirely.
sub MaybeRefreshMeta()
    if m.stores = invalid then return
    if m.meta = invalid or m.meta.id = invalid or m.meta.type = invalid then return
    if m.addonAddress = invalid or m.addonAddress = "" then return
    if m.metaRefreshed then return

    CancelMetaLoad()

    if not m.stores.episodes.callFunc("EpisodesNeedsMetaFetch", m.meta) then return

    task = AsyncTask_Launch(m.top, "MetaLoaderTask", "onMetaLoaded", {
        addonAddress: m.addonAddress
        metaType: m.meta.type
        metaId: m.meta.id
    }, "detailsMetaLoader")
    m.loadTask = task
end sub

' Tear down an in-flight meta refresh. A newer entry supersedes it, and leaving
' this screen drops it too. STOP is the real cancel — merely removing a running
' Task node does not kill its worker thread — and dropping the observer means
' its result can never land.
sub CancelMetaLoad()
    if m.loadTask <> invalid
        task = m.loadTask
        m.loadTask = invalid
        AsyncTask_Reap(task, m.top, true)
    end if
end sub

' The full meta came back. Merge it into what the caller handed in (their values
' win), remember we are done, and re-render the hero. A failed or mismatched
' fetch changes nothing — the screen keeps the catalog record it already shows.
sub onMetaLoaded()
    if m.stores = invalid then return
    if m.loadTask = invalid then return
    task = m.loadTask
    m.loadTask = invalid
    result = task.result
    AsyncTask_Reap(task, m.top, false)

    if result = invalid or not result.ok or result.meta = invalid then return
    if result.meta.id <> invalid and m.meta <> invalid and result.meta.id <> m.meta.id then return

    m.meta = m.stores.episodes.callFunc("EpisodesMergeMeta", m.meta, result.meta)
    m.metaRefreshed = true
    RenderHero(m.meta)
end sub

' Re-entry: the shared chips row just needs focus back. m.meta/m.resume
' survive the push/pop, so a rebuild is not needed.
sub RestoreFocus()
    if m.meta = invalid then return
    m.chipsRow.callFunc("FocusChip", -1)
end sub

sub onHeroLogoStatus()
    if m.heroLogo.uri <> m.heroLogoUri then return
    if m.heroLogo.loadStatus = "ready"
        FitHeroLogo()
    else if m.heroLogo.loadStatus = "failed"
        m.heroLogo.visible = false
        m.detailName.visible = true
        ResetHeroLogoLayout()
    end if
end sub

sub FitHeroLogo()
    bitmapWidth = m.heroLogo.bitmapWidth
    bitmapHeight = m.heroLogo.bitmapHeight
    if bitmapWidth <= 0 or bitmapHeight <= 0 then return
    ratio = bitmapWidth / bitmapHeight
    if ratio < 1.7
        maxWidth = 420
        maxHeight = 460
    else
        maxWidth = 820
        maxHeight = 190
    end if
    logoWidth = ratio * maxHeight
    if logoWidth > maxWidth then logoWidth = maxWidth
    logoHeight = logoWidth / ratio

    m.heroLogo.width = Int(logoWidth)
    m.heroLogo.height = Int(logoHeight)
    if ratio < 1.7
        m.heroLogo.translation = [162, Int((540 - logoHeight) / 2)]
        contentX = 162 + Int(logoWidth) + 48
        m.detailType.translation = [contentX, 110]
        m.detailRating.translation = [contentX, 154]
        m.detailGenres.translation = [contentX, 198]
        m.detailDesc.translation = [contentX, 244]
        m.detailDesc.width = 1920 - contentX - 160
        m.detailDesc.height = 260
    else
        m.heroLogo.translation = [162, 70 + Int((190 - logoHeight) / 2)]
        m.detailType.translation = [166, 274]
        m.detailRating.translation = [166, 316]
        m.detailGenres.translation = [166, 360]
        m.detailDesc.translation = [166, 402]
        m.detailDesc.width = 1000
        m.detailDesc.height = 215
    end if
    m.heroLogo.visible = true
    m.detailName.visible = false
end sub

sub ResetHeroLogoLayout()
    m.heroLogo.translation = [162, 72]
    m.heroLogo.width = 820
    m.heroLogo.height = 460
    m.detailType.translation = [166, 216]
    m.detailRating.translation = [166, 256]
    m.detailGenres.translation = [166, 307]
    m.detailDesc.translation = [166, 357]
    m.detailDesc.width = 860
    m.detailDesc.height = 215
end sub

function TypeLabel(metaType as string) as string
    if metaType = "movie" then return Lang("common", "kindMovie")
    if metaType = "series" then return Lang("common", "kindSeries")
    return metaType
end function

function OnExit() as void
    CancelMetaLoad()
end function

function OnBackPressed() as boolean
    return false
end function

sub BlurFocus()
end sub

' Series chips: Resume for the saved spot when there is one, otherwise a "Play
' S1E1" stand-in (the episode list itself loads on EpisodesScreen; the optional
' hero refresh above only tops up missing catalog fields), then the same
' "add to library" toggle the movie row carries, then "Episodes".
sub ShowSeries()
    actions = []
    if m.resume <> invalid and m.resume.season <> invalid and m.resume.episode <> invalid
        actions.Push({ action: "resume", title: EpisodeCode(m.resume.season, m.resume.episode), icon: "pkg:/images/play.png" })
    else
        actions.Push({ action: "play", title: EpisodeCode(1, 1), icon: "pkg:/images/play.png" })
    end if
    actions.Push({ action: "episodes", title: Lang("details", "episodes"), icon: "pkg:/images/episodes.png" })
    actions.Push({ action: "library", title: "", icon: LibraryIcon() })
    ShowChips(actions)
end sub

sub ShowMovie()
    actions = []
    actions.Push({ action: "play", title: Lang("details", "play"), icon: "pkg:/images/play.png" })
    actions.Push({ action: "library", title: "", icon: LibraryIcon() })
    ShowChips(actions)
end sub

' Fill the shared chips row and remember the action id per chip so the
' selection observer can dispatch. The row owns focus and the keys.
sub ShowChips(actions as object)
    m.chips = actions
    entries = []
    for each chip in actions
        entries.Push({ title: ChipTitle(chip), icon: ChipIconOrEmpty(chip), active: false })
    end for
    m.chipsRow.callFunc("SetChips", entries)
    ' A fresh Details always opens on the first chip — the row's remembered
    ' position is only for re-entry after a push (RestoreFocus below), not
    ' for carrying a stale cursor from the previous Details visit.
    if m.top.screenActive then m.chipsRow.callFunc("FocusChip", 0)
end sub

function ChipTitle(chip as object) as string
    if chip.title <> invalid then return chip.title
    return ""
end function

function ChipIconOrEmpty(chip as object) as string
    if chip.icon <> invalid then return chip.icon
    return ""
end function

function EpisodeCode(season as dynamic, episode as dynamic) as string
    return Fill(Lang("common", "episodeMarker"), { season: season.ToStr(), episode: episode.ToStr() })
end function

sub onChipSelected()
    index = m.chipsRow.selection
    if m.chips = invalid or index < 0 or index >= m.chips.Count() then return
    action = m.chips[index].action
    if action = "resume"
        ResumeEpisode()
    else if action = "play"
        PlayMedia()
    else if action = "episodes"
        OpenEpisodes()
    else if action = "library"
        ToggleLibrary()
    end if
end sub

sub ResumeEpisode()
    if m.resume = invalid or m.stores = invalid then return
    videoId = m.stores.episodes.callFunc("EpisodesResolveVideoId", m.meta.id, m.resume.season, m.resume.episode)
    m.top.pushRequest = {
        screen: "streamsScreen"
        params: {
            addonAddress: m.addonAddress
            metaType: m.meta.type
            metaId: m.meta.id
            videoId: videoId
            season: m.resume.season
            episode: m.resume.episode
            position: m.resume.position
            name: m.meta.name
            poster: m.meta.poster
            posterShape: m.meta.posterShape
            logo: m.meta.logo
            background: m.meta.background
            description: StreamDescription(m.meta)
            runtime: m.meta.runtime
        }
    }
end sub

sub PlayMedia()
    if m.meta = invalid or m.stores = invalid then return
    videoId = m.meta.id
    season = 1
    episode = 1
    if m.meta.type = "movie"
        videoId = m.meta.id
    else if m.meta.videos <> invalid and m.meta.videos.Count() > 0
        video = m.meta.videos[0]
        season = video.season
        episode = video.episode
        videoId = m.stores.episodes.callFunc("EpisodesResolveVideoId", m.meta.id, season, episode)
    end if
    m.top.pushRequest = {
        screen: "streamsScreen"
        params: {
            addonAddress: m.addonAddress
            metaType: m.meta.type
            metaId: m.meta.id
            videoId: videoId
            season: season
            episode: episode
            position: 0
            name: m.meta.name
            poster: m.meta.poster
            posterShape: m.meta.posterShape
            logo: m.meta.logo
            background: m.meta.background
            description: StreamDescription(m.meta)
            runtime: m.meta.runtime
        }
    }
end sub

function StreamDescription(meta as object) as string
    description = StringOf(meta.description)
    if description.Trim() = "" then description = StringOf(meta.overview)
    return description
end function

sub OpenEpisodes()
    if m.meta = invalid then return
    season = 0
    episode = 0
    position = 0
    if m.resume <> invalid
        season = m.resume.season
        episode = m.resume.episode
        position = m.resume.position
    end if
    m.top.pushRequest = {
        screen: "episodesScreen"
        params: {
            addonAddress: m.addonAddress
            meta: m.meta
            season: season
            episode: episode
            position: position
        }
    }
end sub

sub ToggleLibrary()
    if m.meta = invalid or m.stores = invalid then return
    poster = ""
    if m.meta.poster <> invalid then poster = m.meta.poster
    posterShape = ""
    if m.meta.posterShape <> invalid then posterShape = m.meta.posterShape
    added = false
    if m.stores.library.callFunc("LibraryIsSaved", m.meta.id)
        m.stores.library.callFunc("LibraryRemoveSaved", m.meta.id)
    else
        m.stores.library.callFunc("LibraryAddSaved", m.meta.id, m.meta.type, m.meta.name, poster, posterShape)
        added = true
    end if
    icon = LibraryIcon()
    for i = 0 to m.chips.Count() - 1
        if m.chips[i].action = "library"
            if i < m.chipsRow.GetChildCount()
                m.chipsRow.GetChild(i).callFunc("SetChip", m.chips[i].title, icon, 80, false)
            end if
            exit for
        end if
    end for
    ' Publish the write-back packet. An add/remove only affects the account in a
    ' stremio session — a guest's library is local-only, so it stays silent
    ' (MainScene re-gates on the session; the screen keeps the payload
    ' stremio-only). The change appears in the local LibraryStore immediately
    ' either way, so the Library screen reflects it before the account does.
    if m.stores.library.callFunc("LibrarySessionType") = "stremio"
        m.top.libraryChange = {
            metaId: m.meta.id
            metaType: m.meta.type
            name: m.meta.name
            poster: poster
            added: added
        }
    end if
end sub

function LibraryActionLabel() as string
    if m.stores <> invalid and m.stores.library.callFunc("LibraryIsSaved", m.meta.id) then return Lang("details", "inLibrary")
    return Lang("details", "addToLibrary")
end function

function LibraryIcon() as string
    if m.stores <> invalid and m.stores.library.callFunc("LibraryIsSaved", m.meta.id) then return "pkg:/images/library_add_check.png"
    return "pkg:/images/library_add.png"
end function
