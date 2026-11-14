' DiscoverScreen — browse every installed add-on's catalogs by three filters:
' type (derived from the catalogs' declared types), catalog (every feed-capable
' catalog of the chosen type) and genre (the chosen catalog's declared options).
' Each filter is a chip; OK opens a dropdown menu of that chip's options. The
' dropdown is a Back-friendly menu — Up/Down move, OK picks, Back dismisses
' without changing anything — so a wrong pick is an instant undo, never a full
' cycle.
'
' Sources are resolved once per installed add-on set: CatalogSourcesTask fetches
' the manifests the registry has none for (the built-in seeds ship catalogs =
' invalid until a manifest lands) and the result is cached. A filter change
' kicks DiscoverLoaderTask off the render thread against the chosen
' (add-on, catalog) pair, with the genre as an encoded "genre=" extra. Results
' are chunked into poster rows; OK on a tile pushes DetailsScreen exactly like a
' Home catalog tile. Filters + results persist across Details round-trips; entry
' re-derives only when the add-on set moved, then re-focuses the results when
' there is something to show, otherwise the chips.

sub init()
    m.status = m.top.FindNode("discoverStatus")
    m.filterBar = m.top.FindNode("filterBar")
    m.grid = m.top.FindNode("discoverGrid")

    m.heroPoster = m.top.FindNode("heroPoster")
    m.heroPosterFadeAnim = m.top.FindNode("heroPosterFadeAnim")
    m.heroScrim = m.top.FindNode("heroScrim")
    m.heroLogo = m.top.FindNode("heroLogo")
    m.heroTitle = m.top.FindNode("heroTitle")
    m.heroMeta = m.top.FindNode("heroMeta")
    m.heroRating = m.top.FindNode("heroRating")
    m.heroRatingText = m.top.FindNode("heroRatingText")
    m.heroGenres = m.top.FindNode("heroGenres")
    m.heroDescription = m.top.FindNode("heroDescription")
    m.heroTitleGrace = m.top.FindNode("heroTitleGrace")

    HeroInitState()
    m.heroPoster.ObserveField("loadStatus", "HeroOnPosterStatus")
    m.heroLogo.ObserveField("loadStatus", "HeroOnLogoStatus")
    m.heroTitleGrace.ObserveField("fire", "HeroOnTitleGraceFire")
    m.filtersHint = m.top.FindNode("filtersHint")
    m.filtersHintFade = m.top.FindNode("filtersHintFade")

    t = Theme()
    m.heroScrim.color = t.scrim
    m.heroTitle.color = t.textPrimary
    m.heroMeta.color = t.textSecondary
    m.heroRatingText.color = t.accentWarm
    m.heroGenres.color = t.textSecondary
    m.heroDescription.color = t.textPrimary
    m.status.color = t.accent
    m.grid.focusBitmapBlendColor = t.accentFocus

    m.filterBar.ObserveField("chipActivated", "onChipActivated")
    m.filterBar.ObserveField("optionPicked", "onOptionPicked")
    m.grid.ObserveField("rowItemSelected", "onResultSelected")
    m.grid.ObserveField("rowItemFocused", "onGridItemFocused")

    m.chunk = 6
    ' The grid's row budget: RowList translation x 90 + itemSize width 1800,
    ' with 18px gaps (rowItemSpacing), fits 6 standard poster tiles per row.
    m.rowWidth = 1800
    m.rowGap = 18
    m.sources = []
    m.sourcesSignature = ""
    m.sourcesTask = invalid
    m.selectedCatalog = invalid
    m.typeKey = ""
    m.genre = ""
    m.metas = []
    m.loaded = false
    m.allLoaded = false
    m.loadTask = invalid
    m.discoverRetryTimer = m.top.FindNode("discoverRetryTimer")
    m.discoverRetryTimer.ObserveField("fire", "onDiscoverRetry")
    m.discoverRetryCount = 0
    m.discoverMaxRetries = 3
    m.discoverRetryOffset = 0
end sub

function OnEnter(params as object) as void
    RefreshTexts()
    if m.filterBar.callFunc("IsMenuOpen") then m.filterBar.callFunc("HideMenu")

    ' Return from a child screen (ScreenStack pop passes invalid params): restore
    ' results/filters/position instead of resetting.
    if params = invalid and (m.loaded or m.sources.Count() > 0 or m.selectedCatalog <> invalid)
        if m.grid <> invalid and m.metas.Count() > 0
            m.grid.SetFocus(true)
            RefreshDiscoverHeroFromFocus()
        else if m.filterBar <> invalid
            m.filterBar.callFunc("FocusChips")
        end if
        UpdateFiltersHint()
        return
    end if

    CancelLoad()
    CancelSources()
    if m.discoverRetryTimer <> invalid then m.discoverRetryTimer.control = "stop"
    m.discoverRetryCount = 0

    m.targetCatalog = invalid
    if params <> invalid and params.targetCatalog <> invalid then m.targetCatalog = params.targetCatalog

    ' Fresh entry by default: do not preserve previous results/filters/position.
    ' A target catalog (from Home's "see more") is applied once sources resolve.
    ResetDiscover()
    m.selectedCatalog = invalid
    m.typeKey = ""
    m.genre = ""
    m.sources = []
    m.sourcesSignature = ""
    m.loaded = false
    m.allLoaded = false
    ClearDiscoverHero()
    EnsureSources()
end function

function OnExit() as void
    if m.discoverRetryTimer <> invalid then m.discoverRetryTimer.control = "stop"
    CancelLoad()
    CancelSources()
end function

function OnBackPressed() as boolean
    return false
end function

sub BlurFocus()
    if m.heroTitleGrace <> invalid then m.heroTitleGrace.control = "stop"
    if m.heroPosterFadeAnim <> invalid then m.heroPosterFadeAnim.control = "stop"
    if m.filtersHint <> invalid then m.filtersHint.visible = false
end sub

' --- sources (which add-ons serve which catalogs) ---------------------------

' The installed add-on set the current sources were derived from, as a
' comparable string. Mirrors HomeScreen's signature: derive from live store
' state, sort so ordering cannot make two equal sets look different, join. No
' network — a set comparison, not a re-derivation.
function CatalogSignature() as string
    if m.stores = invalid then return ""
    addons = m.stores.addons.callFunc("AddonsGetAll")
    if addons = invalid then return ""
    parts = []
    for each addon in addons
        if addon.address <> invalid then parts.Push(addon.address)
    end for
    parts.Sort("i")
    return parts.Join(";")
end function

' Resolve the catalog sources, reusing the cache when the installed set is
' unchanged. When every add-on already carries its catalog descriptors the
' sources are built inline; otherwise a CatalogSourcesTask fetches the missing
' manifests off the UI thread (the built-in seeds are the only packets that
' need it).
sub EnsureSources()
    if m.stores = invalid
        m.status.text = Lang("discover", "loadFailedAddons")
        return
    end if

    signature = CatalogSignature()
    if signature = m.sourcesSignature and m.sources.Count() > 0 then
        ReadySources()
        return
    end if

    addons = m.stores.addons.callFunc("AddonsGetAll")
    if addons = invalid then addons = []

    packets = []
    allKnown = true
    for each addon in addons
        if addon.catalogs = invalid or Type(addon.catalogs) <> "roArray" then allKnown = false
        name = addon.name
        if name = invalid then name = ""
        packets.Push({ address: addon.address, name: name, resources: addon.resources, catalogs: addon.catalogs })
    end for

    m.sourcesSignature = signature
    if packets.Count() = 0
        m.sources = []
        ShowEmpty()
        return
    end if

    if allKnown
        m.sources = packets
        ReadySources()
        return
    end if

    CancelSources()
    m.status.text = Lang("discover", "loading")
    task = AsyncTask_Launch(m.top, "CatalogSourcesTask", "onSourcesLoaded", { addons: packets }, "catalogSources")
    m.sourcesTask = task
end sub

' A CatalogSourcesTask result landed. Dropped when it arrived after a cancel
' (m.sourcesTask was cleared) so a late manifest can never repaint a screen the
' user already left.
sub onSourcesLoaded()
    if m.sourcesTask = invalid then return
    task = m.sourcesTask
    m.sourcesTask = invalid
    AsyncTask_Reap(task, m.top, false)

    result = task.result
    if result = invalid or result.sources = invalid or Type(result.sources) <> "roArray"
        m.status.text = Lang("discover", "loadFailedAddons")
        return
    end if

    m.sources = result.sources
    ReadySources()
end sub

' Sources are in hand: pick a valid selection and fetch.
sub ReadySources()
    if not SelectDefaults()
        ShowEmpty()
        return
    end if
    ApplyTargetCatalog()
    m.loaded = false
    FetchDiscover()
    SetChips()
    m.filterBar.callFunc("FocusChips")
end sub

' If opened with a target catalog (Home "see more"), select that catalog when
' available; otherwise keep the defaults SelectDefaults chose.
sub ApplyTargetCatalog()
    target = m.targetCatalog
    m.targetCatalog = invalid
    if target = invalid then return
    targetType = TypeKey(target.metaType)
    if targetType = "" then return
    m.typeKey = targetType
    catalogs = CatalogsForType()
    for each candidate in catalogs
        if candidate.address = target.addonAddress and candidate.catalogId = target.catalogId and TypeMatches(candidate.rawType, targetType) then
            m.selectedCatalog = candidate
            EnsureGenre()
            return
        end if
    end for
end sub

' The catalog type keys present across the sources, in a stable order: the
' three media families first, then any other declared type alphabetically.
' Only types that yield at least one feed-capable catalog are listed, so every
' type chip leads somewhere.
function TypeGroups() as object
    groups = []
    if m.stores = invalid then return groups

    seen = {}
    otherKeys = []
    for each source in m.sources
        if source.catalogs = invalid then continue for
        for each descriptor in source.catalogs
            if descriptor = invalid then continue for
            caps = m.stores.addons.callFunc("AddonsCatalogCapabilities", descriptor)
            if caps = invalid or not caps.feed then continue for
            key = TypeKey(descriptor.type)
            if key = "" then continue for
            if seen.DoesExist(key) then continue for
            seen[key] = true
            if TypeOrder(key) >= 3 then otherKeys.Push(key)
        end for
    end for

    otherKeys.Sort("i")
    ordered = []
    preferred = ["movie", "series", "channels"]
    for each key in preferred
        if seen.DoesExist(key) then ordered.Push(key)
    end for
    for each key in otherKeys
        ordered.Push(key)
    end for
    for each key in ordered
        groups.Push({ key: key, label: TypeLabel(key) })
    end for
    return groups
end function

' The chip entries for the type filter ({ raw, label }).
function TypeOptions() as object
    options = []
    for each group in TypeGroups()
        options.Push({ raw: group.key, label: group.label })
    end for
    return options
end function

' A catalog type folded into a filter key. movie/series stand alone; channel and
' tv are one family (manifests use either spelling for the same content);
' anything else keeps its declared name.
function TypeKey(raw as dynamic) as string
    if raw = invalid then return ""
    if raw = "movie" then return "movie"
    if raw = "series" then return "series"
    if raw = "channel" or raw = "tv" then return "channels"
    return raw
end function

function TypeOrder(key as string) as integer
    if key = "movie" then return 0
    if key = "series" then return 1
    if key = "channels" then return 2
    return 3
end function

function TypeLabel(key as string) as string
    if key = "movie" then return Lang("common", "movies")
    if key = "series" then return Lang("common", "series")
    if key = "channels" then return Lang("common", "channels")
    if key = "" then return ""
    ' A declared type is a free string ("sports", "tv", …), so this fallback is
    ' reachable. UCase is a global function, not an roString method — the chained
    ' form threw &hf4 the first time a custom type hit it.
    return UCase(key.Left(1)) + key.Mid(1)
end function

function TypeMatches(declared as dynamic, key as string) as boolean
    if declared = invalid then return false
    if key = "channels" then return declared = "channel" or declared = "tv"
    return declared = key
end function

' Every feed-capable catalog of the current type, across all sources. A catalog
' is feed-capable when nothing beyond skip/genre is required (AddonsStore owns
' that rule), which keeps odd catalogs like cinemeta's required-id last-videos
' out without any per-add-on special case.
function CatalogsForType() as object
    list = []
    if m.stores = invalid then return list
    for each source in m.sources
        if source.catalogs = invalid then continue for
        for each descriptor in source.catalogs
            if descriptor = invalid then continue for
            if not TypeMatches(descriptor.type, m.typeKey) then continue for
            caps = m.stores.addons.callFunc("AddonsCatalogCapabilities", descriptor)
            if caps = invalid or not caps.feed then continue for
            sourceName = source.name
            if sourceName = invalid then sourceName = ""
            list.Push({
                address: source.address
                sourceName: sourceName
                rawType: descriptor.type
                catalogId: descriptor.id
                supportsPagination: caps.pagination
                title: m.stores.addons.callFunc("AddonsCatalogTitle", descriptor, source.name)
                catalog: descriptor
            })
        end for
    end for
    return list
end function

' The catalog chip's options. Duplicate catalog names across add-ons are
' disambiguated with the add-on's name so two "Popular" rows are distinguishable.
function CatalogOptions() as object
    catalogs = CatalogsForType()
    options = []
    count = catalogs.Count()
    ' Indexed loops, not nested "for each" over the same array: a Roku device
    ' gives an roArray ONE internal iterator, so an inner "for each" over the
    ' same list exhausts it and the outer loop stops after the first element
    ' (the brs interpreter uses independent iterators, so tests never see it).
    for i = 0 to count - 1
        candidate = catalogs[i]
        label = candidate.title
        dupes = 0
        for j = 0 to count - 1
            other = catalogs[j]
            if other.title = candidate.title and not SameCatalog(other, candidate) then dupes = dupes + 1
        end for
        if dupes > 0 then label = label + " (" + candidate.sourceName + ")"
        options.Push({ raw: candidate.catalogId, label: label, catalog: candidate })
    end for
    return options
end function

function SameCatalog(a as dynamic, b as dynamic) as boolean
    if a = invalid or b = invalid then return false
    return a.address = b.address and a.rawType = b.rawType and a.catalogId = b.catalogId
end function

function CatalogChipLabel() as string
    if m.selectedCatalog = invalid then return ""
    for each option in CatalogOptions()
        if SameCatalog(option.catalog, m.selectedCatalog) then return option.label
    end for
    return m.selectedCatalog.title
end function

' --- selection defaults -----------------------------------------------------

' Validate the current (type, catalog, genre) against the resolved sources and
' fall back to the first available value where the old one is gone. Returns
' false only when no feed-capable catalog exists at all.
function SelectDefaults() as boolean
    groups = TypeGroups()
    if groups.Count() = 0 then return false

    typeFound = false
    for each group in groups
        if group.key = m.typeKey then typeFound = true
    end for
    if not typeFound then m.typeKey = groups[0].key

    catalogs = CatalogsForType()
    if catalogs.Count() = 0 then
        for each group in groups
            m.typeKey = group.key
            catalogs = CatalogsForType()
            if catalogs.Count() > 0 then exit for
        end for
    end if
    if catalogs.Count() = 0 then return false

    keep = false
    if m.selectedCatalog <> invalid
        for each candidate in catalogs
            if SameCatalog(candidate, m.selectedCatalog) then
                m.selectedCatalog = candidate
                keep = true
            end if
        end for
    end if
    if not keep then m.selectedCatalog = catalogs[0]

    EnsureGenre()
    return true
end function

sub ShowEmpty()
    m.status.text = Lang("discover", "noCatalogAddons")
    m.filterBar.callFunc("SetChips", [])
    ClearDiscoverHero()
end sub

' --- genre (the chosen catalog's filter) ------------------------------------

function SelectedCapabilities() as object
    if m.stores = invalid or m.selectedCatalog = invalid then return invalid
    return m.stores.addons.callFunc("AddonsCatalogCapabilities", m.selectedCatalog.catalog)
end function

' The genre chip's options: the catalog's declared genres, prefixed with "All"
' when a genre is optional. A catalog with no genre extra, or with no declared
' options, gets no genre chip.
function GenreOptions() as object
    options = []
    caps = SelectedCapabilities()
    if caps = invalid or not caps.genre then return options
    if caps.genreOptions = invalid or Type(caps.genreOptions) <> "roArray" or caps.genreOptions.Count() = 0 then return options
    if not caps.genreRequired then options.Push({ raw: "all", label: Lang("common", "all") })
    for each genre in caps.genreOptions
        options.Push({ raw: genre, label: genre })
    end for
    return options
end function

' The default genre for the chosen catalog: the current year when a genre is
' required and the year is one of its options (the "New" catalog's shape), else
' the first declared option; "all" when a genre is optional.
function DefaultGenre() as string
    caps = SelectedCapabilities()
    if caps = invalid or not caps.genre then return ""
    options = caps.genreOptions
    if options = invalid or Type(options) <> "roArray" or options.Count() = 0 then return ""
    if caps.genreRequired
        year = CreateObject("roDateTime").GetYear().ToStr()
        for each option in options
            if option = year then return year
        end for
        return options[0]
    end if
    return "all"
end function

' Keep the genre valid across a catalog/type change: leave it alone when the new
' catalog still offers it, otherwise fall back to that catalog's default.
sub EnsureGenre()
    options = GenreOptions()
    if options.Count() = 0 then m.genre = "" : return
    for each option in options
        if option.raw = m.genre then return
    end for
    m.genre = DefaultGenre()
end sub

' The genre value to send to the server, or "" for no genre filter. Required
' genres always send their value; optional ones drop the "all" sentinel.
function GenreFilter() as string
    caps = SelectedCapabilities()
    if caps = invalid or not caps.genre then return ""
    if caps.genreRequired then return m.genre
    if m.genre = "" or m.genre = "all" then return ""
    return m.genre
end function

' --- filter chips (data) ----------------------------------------------------

' The chip row itself lives in FilterBar; the screen owns the values and their
' labels. The genre chip is omitted when the chosen catalog has no genre filter.
sub SetChips()
    entries = []
    if TypeGroups().Count() > 0
        entries.Push({ raw: m.typeKey, label: TypeLabel(m.typeKey) })
    end if
    if m.selectedCatalog <> invalid
        entries.Push({ raw: m.selectedCatalog.catalogId, label: CatalogChipLabel() })
    end if
    if GenreOptions().Count() > 0
        label = m.genre
        if label = "" or label = "all" then label = Lang("common", "all")
        entries.Push({ raw: m.genre, label: label })
    end if
    m.filterBar.callFunc("SetChips", entries)
    UpdateFiltersHintAnchor()
end sub

' The hint circle hugs the front of the chip row: its x sits one gap left of
' the first chip, vertically centered on the chip height, so it reads as part
' of the filter row — a keycap for the asterisk button.
sub UpdateFiltersHintAnchor()
    if m.filtersHint = invalid then return
    x = m.filterBar.translation[0] - 44 - 16
    y = m.filterBar.translation[1] + (m.filterBar.chipItemHeight - 44) / 2
    m.filtersHint.translation = [x, y]
end sub

' The chip OK'd in the FilterBar: hand it that chip's options and the index of
' the current value, and the component opens the dropdown pre-scrolled there.
sub onChipActivated()
    chip = m.filterBar.chipActivated
    if chip < 0 then return
    options = OptionsFor(chip)
    if options.Count() = 0 then return
    m.filterBar.callFunc("ShowMenu", options, CurrentOptionIndex(chip))
end sub

function OptionsFor(chip as integer) as object
    if chip = 0 then return TypeOptions()
    if chip = 1 then return CatalogOptions()
    if chip = 2 then return GenreOptions()
    return []
end function

function CurrentOptionIndex(chip as integer) as integer
    options = OptionsFor(chip)
    if chip = 0
        for i = 0 to options.Count() - 1
            if options[i].raw = m.typeKey then return i
        end for
    else if chip = 1
        for i = 0 to options.Count() - 1
            if SameCatalog(options[i].catalog, m.selectedCatalog) then return i
        end for
    else if chip = 2
        for i = 0 to options.Count() - 1
            if options[i].raw = m.genre then return i
        end for
    end if
    return 0
end function

' An option OK'd in the FilterBar's dropdown, then re-fetches. Re-picking the
' current value just closes the menu.
sub onOptionPicked()
    pick = m.filterBar.optionPicked
    if pick = invalid or pick.chip = invalid or pick.index = invalid then return
    chip = pick.chip
    options = OptionsFor(chip)
    index = pick.index
    if index < 0 or index >= options.Count() then return
    option = options[index]

    if chip = 0
        if option.raw = m.typeKey then m.filterBar.callFunc("HideMenu") : return
        m.typeKey = option.raw
        catalogs = CatalogsForType()
        if catalogs.Count() = 0 then m.filterBar.callFunc("HideMenu") : return
        m.selectedCatalog = catalogs[0]
        EnsureGenre()
    else if chip = 1
        if SameCatalog(option.catalog, m.selectedCatalog) then m.filterBar.callFunc("HideMenu") : return
        m.selectedCatalog = option.catalog
        EnsureGenre()
    else if chip = 2
        if option.raw = m.genre then m.filterBar.callFunc("HideMenu") : return
        m.genre = option.raw
    end if

    m.filterBar.callFunc("HideMenu")
    SetChips()
    if m.discoverRetryTimer <> invalid then m.discoverRetryTimer.control = "stop"
    m.discoverRetryCount = 0
    ResetDiscover()
    FetchDiscover()
end sub

' --- fetching ---------------------------------------------------------------

' A fresh filter set: start back at page 0.
sub ResetDiscover()
    m.metas = []
    m.allLoaded = false
    m.loaded = false
    if m.grid <> invalid
        m.grid.content = CreateObject("roSGNode", "ContentNode")
        m.grid.numRows = 0
    end if
    ClearDiscoverHero()
end sub

' Kick the chosen catalog off the render thread. A filter change supersedes
' whatever page is still in flight (its result is dropped by the offset guard
' below), so picks never queue behind a stale load. The wanted offset is
' captured so a page that lands after the user changed filters (or exited) is
' dropped instead of appended to the wrong list.
sub FetchDiscover(resetRetry = true as boolean)
    if m.selectedCatalog = invalid then return
    if resetRetry
        if m.discoverRetryTimer <> invalid then m.discoverRetryTimer.control = "stop"
        m.discoverRetryCount = 0
        m.discoverRetryOffset = 0
    end if
    CancelLoad()

    m.status.text = Lang("discover", "loading")
    task = AsyncTask_Launch(m.top, "DiscoverLoaderTask", "onDiscoverLoaded", {
        addonAddress: m.selectedCatalog.address
        metaType: m.selectedCatalog.rawType
        catalogId: m.selectedCatalog.catalogId
        supportsPagination: m.selectedCatalog.supportsPagination
        genre: GenreFilter()
        pageOffset: 0
    }, "discoverLoader")
    m.loadTask = task
end sub

sub onDiscoverRetry()
    ' Retry a catalog fetch after a transient failure (initial or load-more).
    if m.selectedCatalog = invalid then return
    if m.discoverRetryOffset = 0
        if m.metas.Count() > 0 then return
        FetchDiscover(false)
    else
        if m.metas.Count() = 0 or m.allLoaded then return
        FetchDiscoverPage(m.discoverRetryOffset, false)
    end if
end sub

' The user scrolled near the bottom of the fetched results: fetch the next page
' (skip = metas already shown) and append. Silent — the grid stays up untouched
' until the page lands, so scrolling never blinks.
sub LoadMore()
    if m.selectedCatalog = invalid then return
    if m.loadTask <> invalid then return
    if m.allLoaded then return
    if m.metas.Count() = 0 then return
    m.discoverRetryCount = 0
    m.discoverRetryOffset = m.metas.Count()
    FetchDiscoverPage(m.metas.Count(), false)
end sub

' Fetch a specific page offset. Used for load-more and its retries; retries do
' not reset the retry counter/offset (resetRetry=false from timer path).
sub FetchDiscoverPage(offset as integer, resetRetry = false as boolean)
    if m.selectedCatalog = invalid then return
    if resetRetry
        if m.discoverRetryTimer <> invalid then m.discoverRetryTimer.control = "stop"
        m.discoverRetryCount = 0
        m.discoverRetryOffset = offset
    end if
    CancelLoad()

    task = AsyncTask_Launch(m.top, "DiscoverLoaderTask", "onDiscoverLoaded", {
        addonAddress: m.selectedCatalog.address
        metaType: m.selectedCatalog.rawType
        catalogId: m.selectedCatalog.catalogId
        supportsPagination: m.selectedCatalog.supportsPagination
        genre: GenreFilter()
        pageOffset: offset
    }, "discoverLoaderMore")
    m.loadTask = task
end sub

' Near the bottom of the fetched results, pull the next page and update the
' hero to reflect the focused item.
sub onGridItemFocused()
    data = m.grid.rowItemFocused
    if data = invalid or data.Count() < 2 then return
    row = data[0]
    UpdateDiscoverHero(data)
    UpdateFiltersHint()
    rows = 0
    if m.chunk > 0 then rows = (m.metas.Count() + m.chunk - 1) / m.chunk
    if rows >= 4 and row >= rows - 3 then LoadMore()
end sub

' The asterisk-key hint lives only where it is needed: the grid focus is past
' the first row (Up is consumed there by the RowList) and the grid holds focus.
' It fades in beside the chip row and vanishes the moment it is irrelevant.
sub UpdateFiltersHint()
    if m.filtersHint = invalid then return
    visible = false
    if m.grid.HasFocus()
        data = m.grid.rowItemFocused
        if data <> invalid and data.Count() >= 2 and data[0] >= 1 then visible = true
    end if
    if m.filtersHint.visible = visible then return
    m.filtersHint.visible = visible
    if m.filtersHintFade = invalid then
        m.filtersHint.opacity = 1
        return
    end if
    if visible
        m.filtersHintFade.control = "stop"
        m.filtersHint.opacity = 0
        m.filtersHintFade.control = "start"
    else
        m.filtersHintFade.control = "stop"
        m.filtersHint.opacity = 0
    end if
end sub

sub RefreshDiscoverHeroFromFocus()
    data = m.grid.rowItemFocused
    if data <> invalid and data.Count() >= 2
        row = data[0]
        col = data[1]
        flat = row * m.chunk + col
        if flat >= 0 and flat < m.metas.Count()
            RenderDiscoverHero(m.metas[flat])
            return
        end if
    end if
    if m.metas.Count() > 0
        RenderDiscoverHero(m.metas[0])
    else
        ClearDiscoverHero()
    end if
end sub

sub UpdateDiscoverHero(position as object)
    if position = invalid or position.Count() < 2 then return
    row = position[0]
    col = position[1]
    flat = row * m.chunk + col
    if flat < 0 or flat >= m.metas.Count()
        if m.metas.Count() > 0 then RenderDiscoverHero(m.metas[0])
        return
    end if
    RenderDiscoverHero(m.metas[flat])
end sub

sub ClearDiscoverHero()
    HeroClear()
end sub

sub RenderDiscoverHero(meta as object)
    fallbackType = ""
    if m.selectedCatalog <> invalid then fallbackType = StringOf(m.selectedCatalog.rawType)
    HeroRender(meta, fallbackType)
end sub

sub LandingChipsFocus()
    if m.top.screenActive and not m.filterBar.callFunc("IsMenuOpen")
        m.filterBar.callFunc("FocusChips")
    end if
end sub

' A catalog page came back. Stale results are dropped: a page whose offset no
' longer matches the metas already shown landed after a filter change (which
' resets the list), and the m.loadTask guard drops anything that arrived after
' CancelLoad.
sub onDiscoverLoaded()
    if m.loadTask = invalid then return
    task = m.loadTask
    m.loadTask = invalid
    AsyncTask_Reap(task, m.top, false)

    wantedOffset = task.pageOffset
    if wantedOffset <> m.metas.Count() then return

    label = DiscoverLabel()
    result = task.result
    if result = invalid or not result.ok or result.metas = invalid
        if wantedOffset = 0 and m.metas.Count() = 0
            if m.discoverRetryCount < m.discoverMaxRetries
                m.discoverRetryCount = m.discoverRetryCount + 1
                m.discoverRetryOffset = 0
                m.status.text = Lang("discover", "loading")
                if m.discoverRetryTimer <> invalid
                    m.discoverRetryTimer.control = "stop"
                    m.discoverRetryTimer.control = "start"
                else
                    FetchDiscover(false)
                end if
            else
                m.status.text = Fill(Lang("discover", "loadFailedCatalogRetry"), { label: label })
                LandingChipsFocus()
            end if
        else if wantedOffset > 0 and wantedOffset = m.metas.Count() and m.metas.Count() > 0
            ' Append failed: retry silently so a transient error doesn't look like
            ' the end of the catalog.
            if m.discoverRetryCount < m.discoverMaxRetries
                m.discoverRetryCount = m.discoverRetryCount + 1
                m.discoverRetryOffset = wantedOffset
                if m.discoverRetryTimer <> invalid
                    m.discoverRetryTimer.control = "stop"
                    m.discoverRetryTimer.control = "start"
                else
                    FetchDiscoverPage(wantedOffset, false)
                end if
            end if
        end if
        return
    end if

    if wantedOffset = 0
        m.discoverRetryCount = 0
        m.discoverRetryOffset = 0
        m.metas = result.metas
        m.loaded = true
        m.allLoaded = not result.hasMore or result.metas.Count() = 0
        if m.metas.Count() = 0
            m.grid.content = CreateObject("roSGNode", "ContentNode")
            m.grid.numRows = 0
            m.status.text = Fill(Lang("discover", "noResults"), { label: label })
            ClearDiscoverHero()
            LandingChipsFocus()
            return
        end if
        UpdateGrid()
        m.grid.jumpToRowItem = [0, 0]
        m.status.text = ""
        RefreshDiscoverHeroFromFocus()
        LandingChipsFocus()
    else
        m.discoverRetryCount = 0
        m.discoverRetryOffset = 0
        ' Append only metas not already shown. Cinemeta's skip=49 page
        ' repeats the last item of the 49-item first page, and an add-on
        ' that ignores skip returns the same page forever — a page that
        ' adds no new ids ends pagination instead of paging infinitely.
        seen = {}
        for each existing in m.metas
            if existing.id <> invalid then seen[existing.id] = true
        end for
        added = 0
        for each meta in result.metas
            if meta.id <> invalid and seen.DoesExist(meta.id) then continue for
            if meta.id <> invalid then seen[meta.id] = true
            m.metas.Push(meta)
            added = added + 1
        end for
        if added = 0
            m.allLoaded = true
        else
            m.allLoaded = not result.hasMore
            UpdateGrid(AppendRestorePosition())
            RefreshDiscoverHeroFromFocus()
        end if
    end if
end sub

' The grid position to keep after an append: the focused row and tile, or the
' first tile of the freshly added block when the focused row already fell off
' the end. Because rowItemFocused is read before the content rebuild, the tile
' column survives, so the exact selected item keeps focus.
function AppendRestorePosition() as object
    if m.grid.rowItemFocused = invalid or m.grid.rowItemFocused.Count() < 2 then return [0, 0]
    position = [m.grid.rowItemFocused[0], m.grid.rowItemFocused[1]]
    newRows = (m.metas.Count() + m.chunk - 1) / m.chunk
    if position[0] < 0 then return [0, 0]
    if position[0] >= newRows then position[0] = newRows - 1
    return position
end function

' The human summary of the current filters, e.g. "Popular · Movies · Sci-Fi".
function DiscoverLabel() as string
    if m.selectedCatalog = invalid then return ""
    label = m.selectedCatalog.title + " · " + TypeLabel(TypeKey(m.selectedCatalog.rawType))
    if m.genre <> "" and m.genre <> "all" then label = label + " · " + m.genre
    return label
end function

' Lay all loaded metas out as poster rows so the RowList clips/scrolls them
' vertically. The column count (m.chunk) is recomputed from the cell size so the
' row always fits the grid width; jumpToRow keeps the view anchored after an
' append, preserving the focused row and tile.

sub UpdateGrid(rowToShow = invalid as dynamic)
    mt = invalid
    if m.selectedCatalog <> invalid then mt = m.selectedCatalog.rawType
    ' The whole grid sizes to the catalog's posterShape (folded from its metas),
    ' the same rule Home rows use, so a 16:9 catalog gets wide tiles instead of
    ' letterboxed 2:3 cells; falls back to the content type when no shape ships.
    ' Size to the catalog's posterShape (or type fallback) using canonical
    ' cell sizes so tiles/decode targets stay consistent across screens.
    size = TileCellSize(mt, TilePosterShape(m.metas))
    ' A wide (16:9) cell places fewer tiles per row instead of overflowing the row
    ' into per-row horizontal scrolling (the "grid becomes a list of rows" break).
    ' All rows share one chunk so the flat index (row*chunk + col) stays honest.
    m.chunk = TileColumns(m.rowWidth, size[0], m.rowGap)
    if m.chunk < 1 then m.chunk = 1

    content = CreateObject("roSGNode", "ContentNode")
    for r = 0 to (m.metas.Count() - 1) / m.chunk
        row = content.CreateChild("ContentNode")
        for c = 0 to m.chunk - 1
            flat = r * m.chunk + c
            if flat >= m.metas.Count() then exit for
            meta = m.metas[flat]
            item = row.CreateChild("TileContent")
            name = meta.name
            if name = invalid then name = ""
            item.title = name
            poster = meta.poster
            if poster <> invalid and poster <> "" then item.hdPosterUrl = poster
            glyph = ""
            if m.stores <> invalid then glyph = m.stores.library.callFunc("LibraryWatchedGlyph", meta.id, meta.type)
            item.watchedGlyph = glyph
        end for
    end for
    m.grid.content = content
    m.grid.itemSize = [m.rowWidth, size[1]]
    m.grid.rowItemSize = [size]
    m.grid.rowHeights = [size[1]]
    m.grid.numRows = (m.metas.Count() + m.chunk - 1) / m.chunk
    if rowToShow <> invalid and m.grid.numRows > 0
        m.grid.jumpToRowItem = rowToShow
    end if
end sub

sub CancelLoad()
    if m.loadTask <> invalid
        task = m.loadTask
        m.loadTask = invalid
        AsyncTask_Reap(task, m.top, true)
    end if
end sub

sub CancelSources()
    if m.sourcesTask <> invalid
        task = m.sourcesTask
        m.sourcesTask = invalid
        AsyncTask_Reap(task, m.top, true)
    end if
end sub


' A result opens DetailsScreen through the same one-action channel Home and
' Search use for a catalog tile: full meta + the source add-on's address.
sub onResultSelected()
    if m.selectedCatalog = invalid then return
    data = m.grid.rowItemSelected
    if data = invalid or data.Count() < 2 then return
    flat = data[0] * m.chunk + data[1]
    if flat < 0 or flat >= m.metas.Count() then return
    m.top.pushRequest = {
        screen: "detailsScreen"
        params: {
            addonAddress: m.selectedCatalog.address
            meta: m.metas[flat]
        }
    }
end sub

' Focus travel between the chips and the results grid. The dropdown's own keys
' are handled inside FilterBar (it owns the menu focus); with the menu closed
' Down from the chips enters the results grid and Up from the grid returns.
function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    ' Replay/instantreplay (↺) re-fetches the current catalog from scratch
    ' (manual recovery after failures or to refresh results).
    if key = "instantreplay" or key = "replay"
        if m.selectedCatalog <> invalid
            if m.discoverRetryTimer <> invalid then m.discoverRetryTimer.control = "stop"
            m.discoverRetryCount = 0
            m.discoverRetryOffset = 0
            ResetDiscover()
            FetchDiscover()
            return true
        end if
        return false
    end if

    ' The asterisk key is a one-press escape hatch: from anywhere in the
    ' results grid it drops focus back up onto the filter chips.
    if key = "options" and m.grid.HasFocus()
        m.filterBar.callFunc("FocusChips")
        UpdateFiltersHint()
        return true
    else if key = "down" and m.filterBar.callFunc("FocusIsOnChips")
        m.filterBar.callFunc("BlurChips")
        m.grid.SetFocus(true)
        UpdateFiltersHint()
        return true
    else if key = "up" and m.grid.HasFocus()
        m.filterBar.callFunc("FocusChips")
        UpdateFiltersHint()
        return true
    end if
    return false
end function
