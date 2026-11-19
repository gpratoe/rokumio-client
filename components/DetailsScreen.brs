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
    m.bgPosterFull = m.top.FindNode("bgPosterFull")
    m.bgScrim = m.top.FindNode("bgScrim")
    m.bgPosterFadeAnim = m.top.FindNode("bgPosterFadeAnim")
    m.bgFullFadeAnim = m.top.FindNode("bgFullFadeAnim")
    m.heroLogo = m.top.FindNode("heroLogo")
    m.bgPosterLoader = m.top.FindNode("bgPosterLoader")
    m.bgFullLoader = m.top.FindNode("bgFullLoader")
    m.logoLoader = m.top.FindNode("logoLoader")
    m.bgPosterLoader.target = m.bgPoster
    m.bgFullLoader.target = m.bgPosterFull
    m.logoLoader.target = m.heroLogo
    m.bgPosterLoader.ObserveField("ready", "onBgPosterReady")
    m.bgPosterLoader.ObserveField("status", "onBgPosterReady")
    m.bgFullLoader.ObserveField("ready", "onBgFullReady")
    m.bgFullLoader.ObserveField("status", "onBgFullReady")
    m.bgPosterFadeAnim.ObserveField("state", "onBgPosterFadeState")
    m.logoLoader.ObserveField("ready", "onLogoStateChanged")
    m.logoLoader.ObserveField("status", "onLogoStateChanged")
    m.bgUri = ""
    m.bgMode = ""
    m.preferHeroTexture = false
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
    ' the screen Group (not a focus target) was handed focus by the stack. The
    ' resume hint may have moved while a child screen had focus (watching an
    ' episode updates library state), so refresh it before handing focus back or
    ' the Episodes chip would open on the stale spot from the first entry.
    if params = invalid
        if m.meta <> invalid and m.stores <> invalid
            m.resume = m.stores.library.callFunc("LibraryResumeFor", m.meta.id)
            if m.meta.type = "series"
                ShowSeries()
            else
                ShowMovie()
            end if
        end if
        ' Re-entry (pop back): recover hero assets only if current state is not satisfied.
        if m.meta <> invalid then RenderHero(m.meta)
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

    m.preferHeroTexture = false
    if params.heroTextureReady <> invalid and params.heroTextureReady = true then m.preferHeroTexture = true
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

    bg = StringOf(meta.background)
    if bg = ""
        m.bgUri = ""
        m.bgMode = ""
        if m.bgPosterFadeAnim <> invalid then m.bgPosterFadeAnim.control = "stop"
        if m.bgFullFadeAnim <> invalid then m.bgFullFadeAnim.control = "stop"
        m.bgPosterLoader.uri = ""
        m.bgFullLoader.uri = ""
        m.bgPoster.opacity = 0
        m.bgPoster.visible = false
        m.bgPosterFull.opacity = 0
        m.bgPosterFull.visible = false
    else
        requestBg = ProxyImageUri(bg)
        desiredHero = m.preferHeroTexture = true
        desiredMode = "fullOnly"
        if desiredHero then desiredMode = "heroThenFull"

        bgChanged = bg <> m.bgUri
        ' Don't downgrade a healthy/visible heroThenFull state just because
        ' preferHeroTexture changed (e.g. meta refresh) for the same background.
        if not bgChanged and m.bgMode = "heroThenFull" and desiredMode = "fullOnly"
            if m.bgFullLoader.ready = true or m.bgPosterLoader.ready = true or m.bgPoster.opacity > 0 or m.bgPosterFull.opacity > 0
                desiredMode = "heroThenFull"
            end if
        end if

        sameConfig = (not bgChanged) and (m.bgMode = desiredMode)
        needsRequest = not sameConfig
        if sameConfig
            if desiredMode = "heroThenFull"
                if not (m.bgFullLoader.ready = true or m.bgPosterLoader.ready = true) then needsRequest = true
            else
                if not (m.bgFullLoader.ready = true) then needsRequest = true
            end if
        end if

        bgVisualReady = false
        if sameConfig and not needsRequest
            if desiredMode = "heroThenFull"
                if m.bgFullLoader.ready = true and m.bgPosterFull.visible = true and m.bgPosterFull.opacity >= 1
                    bgVisualReady = true
                else if not (m.bgFullLoader.ready = true) and m.bgPosterLoader.ready = true and m.bgPoster.visible = true and m.bgPoster.opacity >= 1
                    bgVisualReady = true
                end if
            else
                if m.bgFullLoader.ready = true and m.bgPosterFull.visible = true and m.bgPosterFull.opacity >= 1
                    bgVisualReady = true
                end if
            end if
        end if

        m.bgUri = bg
        m.bgMode = desiredMode
        continuity = (desiredMode = "heroThenFull" and m.preferHeroTexture = true)
        m.bgContinuity = continuity

        if not (sameConfig and not needsRequest and bgVisualReady)
            if needsRequest
                ' New/changed/unsatisfied background: request loads (loaders handle retry).
                if bgChanged or not sameConfig
                    if m.bgPosterFadeAnim <> invalid then m.bgPosterFadeAnim.control = "stop"
                    if m.bgFullFadeAnim <> invalid then m.bgFullFadeAnim.control = "stop"
                end if

                if desiredMode = "heroThenFull"
                    ' Continuity promised (Home/Discover hero loaded): show low-res first when available, no fade.
                    ' No continuity: fade in from black to first background that becomes ready.
                    if m.bgPosterLoader.uri <> requestBg then m.bgPosterLoader.uri = requestBg
                    if m.bgFullLoader.uri <> requestBg then m.bgFullLoader.uri = requestBg
                    m.bgPoster.visible = true
                    m.bgPosterFull.visible = true

                    if continuity
                        m.bgPosterFull.opacity = 0
                        if m.bgPosterLoader.ready = true or m.bgPosterLoader.status = "ready"
                            m.bgPoster.opacity = 1
                        else
                            m.bgPoster.opacity = 0
                        end if
                        if m.bgFullLoader.ready = true and (m.bgPosterLoader.ready = true or m.bgPosterLoader.status = "ready" or m.bgPosterLoader.status = "failed")
                            m.bgPoster.opacity = 0
                            m.bgPosterFull.opacity = 1
                        end if
                    else
                        ' No continuity signal: if already ready now show instantly (no late-arrival snap),
                        ' otherwise keep black and fade in the first background that arrives.
                        m.bgPoster.opacity = 0
                        m.bgPosterFull.opacity = 0
                        if m.bgPosterLoader.ready = true or m.bgPosterLoader.status = "ready"
                            m.bgPoster.opacity = 1
                            if m.bgFullLoader.ready = true or m.bgFullLoader.status = "ready"
                                m.bgPoster.opacity = 0
                                m.bgPosterFull.opacity = 1
                            end if
                        else if m.bgFullLoader.ready = true or m.bgFullLoader.status = "ready"
                            m.bgPosterFull.opacity = 1
                        else
                        end if
                    end if
                else
                    ' fullOnly: fade in from black on fresh/unsatisfied presentation.
                    if m.bgPosterLoader.uri <> "" then m.bgPosterLoader.uri = ""
                    if m.bgFullLoader.uri <> requestBg then m.bgFullLoader.uri = requestBg
                    m.bgPoster.opacity = 0
                    m.bgPoster.visible = false
                    m.bgPosterFull.visible = true
                    if m.bgFullLoader.ready = true
                        if bgChanged or not sameConfig
                            m.bgPosterFull.opacity = 0
                            if m.bgFullFadeAnim <> invalid
                                m.bgFullFadeAnim.control = "stop"
                                m.bgFullFadeAnim.control = "start"
                            else
                                m.bgPosterFull.opacity = 1
                            end if
                        else
                            m.bgPosterFull.opacity = 1
                        end if
                    else
                        m.bgPosterFull.opacity = 0
                    end if
                end if
            else
                ' Same config satisfied but visual state not fully settled: normalize without restart.
                if m.bgFullLoader.ready = true
                    if m.bgFullFadeAnim <> invalid and m.bgFullFadeAnim.state = "running"
                        ' Let fade complete.
                    else
                        if m.bgFullFadeAnim <> invalid then m.bgFullFadeAnim.control = "stop"
                        m.bgPosterFull.visible = true
                        m.bgPosterFull.opacity = 1
                    end if
                else if desiredMode = "heroThenFull" and m.bgPosterLoader.ready = true
                    if m.bgPosterFadeAnim <> invalid and m.bgPosterFadeAnim.state = "running"
                        ' Let fade complete.
                    else
                        if m.bgPosterFadeAnim <> invalid then m.bgPosterFadeAnim.control = "stop"
                        m.bgPoster.visible = true
                        m.bgPoster.opacity = 1
                        m.bgPosterFull.visible = true
                        if m.bgPosterFull.opacity >= 1 then m.bgPosterFull.opacity = 0
                    end if
                end if
            end if
        else
        end if
    end if

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
    m.detailName.text = title
    m.detailType.text = kind
    m.detailRatingText.text = rating
    m.detailRating.visible = rating.Trim() <> ""
    m.detailGenres.text = genres
    m.detailGenres.visible = genres <> ""
    m.detailDesc.text = description
    m.detailDesc.visible = description.Trim() <> ""
    m.logoLoader.uri = ProxyImageUri(logo)
    ApplyDetailsLogoPresentation()
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

    metaAddresses = m.stores.addons.callFunc("AddonsMetaAddresses", m.meta.type, m.meta.id, m.addonAddress)
    task = AsyncTask_Launch(m.top, "MetaLoaderTask", "onMetaLoaded", {
        addonAddress: m.addonAddress
        candidateAddresses: metaAddresses
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

    full = m.stores.episodes.callFunc("EpisodesMergeMeta", m.meta, result.meta)
    m.stores.episodes.callFunc("EpisodesCacheFullMeta", full)
    m.meta = m.stores.episodes.callFunc("EpisodesDisplayMeta", full)
    m.metaRefreshed = true
    ' Only downgrade to full-only if refreshed meta introduces/changes background.
    newBg = StringOf(m.meta.background)
    if newBg = "" or newBg <> m.bgUri then m.preferHeroTexture = false
    RenderHero(m.meta)
end sub

' Re-entry: the shared chips row just needs focus back. m.meta/m.resume
' survive the push/pop, so a rebuild is not needed.
sub RestoreFocus()
    if m.meta = invalid then return
    m.chipsRow.callFunc("FocusChip", -1)
end sub

sub onLogoStateChanged()
    ApplyDetailsLogoPresentation()
end sub

sub ApplyDetailsLogoPresentation()
    logo = StringOf(m.logoLoader.uri)
    if logo = ""
        ResetHeroLogoLayout()
        m.heroLogo.visible = false
        m.detailName.visible = true
        return
    end if
    if m.logoLoader.ready = true or m.logoLoader.status = "ready"
        FitHeroLogo()
    else
        ' Show fallback while loading; loader retries on failure/stuck states.
        ResetHeroLogoLayout()
        m.heroLogo.visible = false
        m.detailName.visible = true
    end if
end sub

sub onBgPosterReady()
    if m.bgPosterLoader = invalid or m.bgPoster = invalid then return
    if m.bgMode <> "heroThenFull" then return
    if StringOf(m.bgPosterLoader.uri) <> ProxyImageUri(m.bgUri) or m.bgUri = "" then return
    ' Continuity (heroTextureReady): show low-res instantly when ready.
    ' No continuity: fade in first ready background from black (poster may win race).
    if m.bgPosterLoader.ready = true or m.bgPosterLoader.status = "ready"
        m.bgPoster.visible = true
        posterShown = (m.bgPoster.opacity >= 1) or (m.bgPosterFadeAnim <> invalid and m.bgPosterFadeAnim.state = "running")
        fullShown = m.bgPosterFull <> invalid and ((m.bgPosterFull.opacity >= 1) or (m.bgFullFadeAnim <> invalid and m.bgFullFadeAnim.state = "running"))

        if m.bgContinuity = true
            if m.bgPoster.opacity < 1
                if m.bgPosterFadeAnim <> invalid then m.bgPosterFadeAnim.control = "stop"
                m.bgPoster.opacity = 1
            end if
            if m.bgPoster.opacity >= 1 and m.bgFullLoader <> invalid and (m.bgFullLoader.ready = true or m.bgFullLoader.status = "ready")
                m.bgPoster.opacity = 0
                m.bgPosterFull.visible = true
                m.bgPosterFull.opacity = 1
            end if
        else
            if not fullShown and not posterShown
                if m.bgPosterFadeAnim <> invalid
                    m.bgPosterFadeAnim.control = "stop"
                    m.bgPoster.opacity = 0
                    m.bgPosterFadeAnim.control = "start"
                else
                    m.bgPoster.opacity = 1
                end if
            else if m.bgPoster.opacity >= 1 and m.bgFullLoader <> invalid and (m.bgFullLoader.ready = true or m.bgFullLoader.status = "ready") and m.bgPosterFull.opacity < 1
                m.bgPoster.opacity = 0
                m.bgPosterFull.visible = true
                m.bgPosterFull.opacity = 1
            end if
        end if
    else if m.bgPosterLoader.status = "failed" and m.bgPosterLoader.retryCount >= m.bgPosterLoader.maxRetries
        ' If full-res is ready, show/fade it in (depending on continuity path) or keep stable.
        if m.bgFullLoader <> invalid and (m.bgFullLoader.ready = true or m.bgFullLoader.status = "ready")
            m.bgPoster.opacity = 0
            m.bgPosterFull.visible = true
            if m.bgContinuity = true or m.bgPosterFull.opacity >= 1
                m.bgPosterFull.opacity = 1
            else if m.bgFullFadeAnim <> invalid and m.bgFullFadeAnim.state <> "running"
                m.bgPosterFull.opacity = 0
                m.bgFullFadeAnim.control = "start"
            end if
        else
            m.bgPoster.visible = true
            if m.bgPoster.opacity <= 0 then m.bgPoster.opacity = 1
        end if
    end if
end sub

sub onBgPosterFadeState()
    if m.bgMode <> "heroThenFull" then return
    if m.bgPosterFadeAnim = invalid then return
    if m.bgPosterFadeAnim.state <> "stopped" then return
    if m.bgPoster.opacity < 1 then return
    if m.bgFullLoader <> invalid and (m.bgFullLoader.ready = true or m.bgFullLoader.status = "ready")
        if m.bgPosterFull <> invalid and m.bgPosterFull.opacity < 1
            m.bgPoster.opacity = 0
            m.bgPosterFull.visible = true
            m.bgPosterFull.opacity = 1
        end if
    end if
end sub

sub onBgFullReady()
    if m.bgFullLoader = invalid or m.bgPosterFull = invalid then return
    if StringOf(m.bgFullLoader.uri) <> ProxyImageUri(m.bgUri) or m.bgUri = "" then return
    if m.bgFullLoader.ready = true or m.bgFullLoader.status = "ready"
        m.bgPosterFull.visible = true
        if m.bgMode = "fullOnly"
            if m.bgPosterFull.opacity >= 1 then return
            if m.bgFullFadeAnim <> invalid
                if m.bgFullFadeAnim.state = "running" then return
                m.bgFullFadeAnim.control = "stop"
                m.bgPosterFull.opacity = 0
                m.bgFullFadeAnim.control = "start"
            else
                m.bgPosterFull.opacity = 1
            end if
        else
            ' heroThenFull
            if m.bgContinuity = true
                heroShown = m.bgPosterLoader <> invalid and (m.bgPosterLoader.ready = true or m.bgPosterLoader.status = "ready") and m.bgPoster.opacity >= 1
                if heroShown
                    m.bgPoster.opacity = 0
                    m.bgPosterFull.opacity = 1
                else if m.bgPosterLoader <> invalid and m.bgPosterLoader.status = "failed"
                    m.bgPoster.opacity = 0
                    m.bgPosterFull.opacity = 1
                else
                    ' Wait for low-res continuity layer to show to avoid flash.
                end if
            else
                posterShown = m.bgPoster.opacity >= 1
                posterFading = m.bgPosterFadeAnim <> invalid and m.bgPosterFadeAnim.state = "running"
                fullShown = m.bgPosterFull.opacity >= 1
                fullFading = m.bgFullFadeAnim <> invalid and m.bgFullFadeAnim.state = "running"
                if posterShown
                    m.bgPoster.opacity = 0
                    m.bgPosterFull.opacity = 1
                else if posterFading
                else if not fullShown and not fullFading
                    if m.bgFullFadeAnim <> invalid
                        m.bgFullFadeAnim.control = "stop"
                        m.bgPosterFull.opacity = 0
                        m.bgFullFadeAnim.control = "start"
                    else
                        m.bgPosterFull.opacity = 1
                    end if
                end if
            end if
        end if
    else if m.bgFullLoader.status = "failed" and m.bgFullLoader.retryCount >= m.bgFullLoader.maxRetries
        ' If full-res cannot load and no low-res is available/shown, hide it.
        if m.bgPosterLoader = invalid or not (m.bgPosterLoader.ready = true) then m.bgPosterFull.visible = false
    end if
end sub

sub FitHeroLogo()
    fit = HeroFit(m.heroLogo.bitmapWidth, m.heroLogo.bitmapHeight)
    if fit = invalid then return
    logoWidth = fit.width
    logoHeight = fit.height

    m.heroLogo.width = logoWidth
    m.heroLogo.height = logoHeight
    m.heroLogo.translation = [162, 46 + Int((190 - logoHeight) / 2)]
    m.detailType.translation = [166, 250]
    m.detailRating.translation = [166, 292]
    m.detailGenres.translation = [166, 336]
    m.detailDesc.translation = [166, 378]
    m.detailDesc.width = 720
    m.detailDesc.height = 215
    m.heroLogo.visible = true
    m.detailName.visible = false
end sub

sub ResetHeroLogoLayout()
    m.heroLogo.translation = [162, 48]
    m.heroLogo.width = 820
    m.heroLogo.height = 460
    m.detailType.translation = [166, 192]
    m.detailRating.translation = [166, 232]
    m.detailGenres.translation = [166, 283]
    m.detailDesc.translation = [166, 333]
    m.detailDesc.width = 720
    m.detailDesc.height = 265
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
    if m.resume = invalid or m.meta = invalid or m.stores = invalid then return
    resumeVideo = {
        id: m.resume.videoId
        season: m.resume.season
        episode: m.resume.episode
    }
    sel = m.stores.episodes.callFunc("EpisodesResolveEpisodeSelection", m.meta.id, resumeVideo)
    if sel = invalid then return
    position = 0
    if m.resume.position <> invalid then position = m.resume.position
    m.top.pushRequest = {
        screen: "streamsScreen"
        params: {
            addonAddress: m.addonAddress
            metaType: m.meta.type
            metaId: m.meta.id
            videoId: sel.videoId
            season: sel.season
            episode: sel.episode
            position: position
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
    metaType = ""
    if m.meta.type <> invalid then metaType = m.meta.type
    videoId = m.meta.id
    season = 1
    episode = 1
    if metaType = "movie"
        if videoId = invalid then return
    else
        videos = invalid
        if m.meta.videos <> invalid
            videos = m.meta.videos
        else
            full = m.stores.episodes.callFunc("EpisodesFullMeta", m.meta.type, m.meta.id)
            if full <> invalid then videos = full.videos
        end if
        sel = invalid
        if videos <> invalid and videos.Count() > 0
            sel = m.stores.episodes.callFunc("EpisodesFirstPlayableEpisodeSelection", m.meta.id, { videos: videos })
        end if
        ' No addressable episode in known metadata: do not push a broken stream
        ' request (malformed addon data must not crash the play path).
        if sel = invalid then return
        videoId = sel.videoId
        season = sel.season
        episode = sel.episode
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
    resume = invalid
    if m.resume <> invalid and m.resume.season <> invalid and m.resume.episode <> invalid
        position = 0
        if m.resume.position <> invalid then position = m.resume.position
        resume = { season: m.resume.season, episode: m.resume.episode, position: position }
    end if
    ' The hint travels as a resume object, not bare ordinals: EpisodesScreen
    ' reads params.resume to land the browser on the watch-in-progress spot.
    ' The heavy episode list stays in the shared meta cache; Episodes resolves it
    ' on demand so this push does not copy a full series payload.
    episodeMeta = m.meta
    if m.stores <> invalid and m.meta <> invalid then episodeMeta = m.stores.episodes.callFunc("EpisodesDisplayMeta", m.meta)
    m.top.pushRequest = {
        screen: "episodesScreen"
        params: {
            addonAddress: m.addonAddress
            meta: episodeMeta
            resume: resume
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
