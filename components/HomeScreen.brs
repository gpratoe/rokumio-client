' HomeScreen — the stack bottom: continue watching first, then catalog rows.
'
' The body is a single RowList: Roku owns the whole grid physics — vertical row
' scrolling/clipping (no row is ever stranded past the screen edge), horizontal
' per-row tile scrolling, row labels, focus reporting and non-focused-row
' dimming. Each row item is a PosterTile (see its interface fields). OK on a
' poster publishes one pushRequest; the Scene does the stack work.
'
' Rows are served by the addon stores: a HomeCatalogsTask walks the add-ons off
' the UI thread, fetching every enabled browsable catalog, and republishes the row
' set after each completion so the grid fills in one row at a time instead of
' blocking startup on the whole catalog set. On top sits a Continue Watching row
' built from the (local) LibraryStore whenever the user has entries — guests
' included, since that state is local. Rows that fail to load are skipped; on
' total failure the grid stays empty so a break in the fetch pipeline is
' unambiguous.
'
' The grid tree is built lazily on first OnEnter, not in init(): init runs during
' CreateScene, before screen.Show(), and nodes created pre-Show can be dropped by
' the renderer. Rows are inserted as they arrive and the grid is assembled
' exactly once; later visits either leave the tree alone (nothing changed) or
' refresh only the Continue Watching row in place (progress was made elsewhere).
' The RowList's own scroll + focus therefore survive every trip away and back.

sub init()
    m.catalog = m.top.FindNode("catalog")
    m.catalog.ObserveField("rowItemSelected", "onRowItemSelected")
    m.catalog.ObserveField("rowItemFocused", "onCatalogItemFocused")
    m.rail = m.top.FindNode("rail")
    m.railExpandAnim = m.top.FindNode("railExpandAnim")
    m.railCollapseAnim = m.top.FindNode("railCollapseAnim")
    m.railBrand = m.top.FindNode("railBrand")
    m.railBrandExpanded = m.top.FindNode("railBrandExpanded")
    m.railBrandExpandAnim = m.top.FindNode("railBrandExpandAnim")
    m.railBrandCollapseAnim = m.top.FindNode("railBrandCollapseAnim")
    m.railBg = m.top.FindNode("railBg")
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
    m.heroMetaDelay = m.top.FindNode("heroMetaDelay")
    m.heroMetaDelay.ObserveField("fire", "onHeroMetaDelayFire")
    m.heroPrefetchDelay = m.top.FindNode("heroPrefetchDelay")
    m.heroPrefetchDelay.ObserveField("fire", "onHeroPrefetchDelayFire")
    m.heroTitleGrace = m.top.FindNode("heroTitleGrace")
    m.heroLogoWarmers = [m.top.FindNode("heroLogoWarm1"), m.top.FindNode("heroLogoWarm2")]
    m.heroPrefetchTasks = []
    m.heroPrefetchKeys = {}
    m.heroMetaCache = {}
    m.heroMetaRequest = invalid
    m.heroMetaTask = invalid
    m.heroMetaTaskKey = ""

    HeroInitState()
    m.heroPoster.ObserveField("loadStatus", "HeroOnPosterStatus")
    m.heroLogo.ObserveField("loadStatus", "HeroOnLogoStatus")
    m.heroTitleGrace.ObserveField("fire", "HeroOnTitleGraceFire")
    m.homeEmpty = m.top.FindNode("homeEmpty")
    m.heroBeforeBusy = ""

    t = Theme()
    m.heroScrim.color = t.scrim
    m.heroTitle.color = t.textPrimary
    m.heroMeta.color = t.textSecondary
    m.heroRatingText.color = t.accentWarm
    m.heroGenres.color = t.textSecondary
    m.heroDescription.color = t.textPrimary
    m.homeEmpty.color = t.textSecondary
    m.railBg.color = t.navBg
    m.catalog.rowLabelOffset = [0,10]
    m.catalog.focusBitmapBlendColor = t.accentFocus

    m.catalogRowsBuilt = false
    m.catalogRows = []
    m.gridRows = []
    m.gridBuilt = false
    ' The language the grid was built in — see OnEnter, where a
    ' change of it is what makes the grid rebuild.
    m.gridLanguage = ""
    ' Bumped on explicit replay refresh so PosterTile retries images even when
    ' they were already ready (recovers from stale/failed loads on bad links).
    m.posterReloadNonce = 0
    m.cwSignature = ""
    m.catalogSignature = ""
    m.catalogVisibilitySignature = ""
    m.railBuilt = false
    m.railLanguage = ""
    m.railFocusIndex = -1
    m.railRememberedIndex = 0
end sub

' Kick off the catalog walk. The walking happens off the UI thread in a
' HomeCatalogsTask (a hung add-on then costs the worker, not startup); it
' republishes the row set after every completed catalog, and onCatalogState
' slots each new row into the grid immediately. Only plain add-on descriptors
' and hidden catalog identities cross the thread boundary. A no-op once started
' or finished.
'
' The walk records which add-on set it derived from (see CatalogSignature), which
' is the only way anything downstream can later tell that Home's rows have been
' overtaken. It records the set BEFORE branching on the empty case on purpose: a
' walk that latched on an empty registry is exactly the state that must still be
' recognised as stale once add-ons arrive, and a signature left at "" would make
' that indistinguishable from a correct empty grid.
sub StartCatalogLoad()
    if m.catalogRowsBuilt or m.catalogTask <> invalid then return
    if m.stores = invalid then
        m.catalogRowsBuilt = true
        UpdateHomeEmptyState()
        return
    end if
    addons = []
    for each addon in m.stores.addons.callFunc("AddonsGetAll")
        addons.Push({ address: addon.address, catalogs: addon.catalogs, name: addon.name })
    end for
    m.catalogSignature = CatalogSignature()
    hiddenCatalogs = m.stores.settings.callFunc("SettingsGetHiddenHomeCatalogs")
    if hiddenCatalogs = invalid then hiddenCatalogs = []
    m.catalogVisibilitySignature = FormatJson(hiddenCatalogs)
    if addons.Count() = 0 then
        m.catalogRowsBuilt = true
        UpdateHomeEmptyState()
        return
    end if
    task = AsyncTask_Launch(m.top, "HomeCatalogsTask", "onCatalogState", {
        addons: addons
        hiddenCatalogs: hiddenCatalogs
    }, invalid)
    m.catalogTask = task
end sub

' The add-on set Home's catalog rows were derived from, as a comparable string.
' Mirrors ContinueWatchingSignature deliberately: derive from live store state,
' sort so ordering cannot make two equal sets look different, join. No network
' and no catalog walk — this is a set comparison, not a re-derivation, so it is
' cheap enough to call on every entry and after every sync.
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

' Re-derive the grid if the add-on set has moved under it. Cheap when fresh, and
' it is the ONLY thing that can notice Home is stale.
'
' Why this exists. The add-on sync used to gate its rebuild on "at least one
' add-on was newly installed". That predicate is false on every run after the
' first: the account's add-ons are already in the registry, so none of them is
' "added", so Home was never told to re-derive. Home kept the catalog set it
' walked at launch — in a stremio session that is often just the built-in seeds,
' because a session swap replaces what AddonsGetAll returns wholesale — while the
' Add-ons screen, which reads the registry live, listed the account's add-ons
' correctly. The two views disagreed permanently, Settings-and-back changed
' nothing, and no fault ever appeared, because nothing had failed. The sync
' succeeded and simply told nobody.
'
' Comparing the add-on SET rather than a count also covers the two cases no
' count can see: a session swap (the set changes without anything being
' installed) and a walk that latched on an empty registry.
sub EnsureCurrentRows()
    if m.stores = invalid then return
    if m.catalogSignature = CatalogSignature() and m.catalogVisibilitySignature = HomeCatalogVisibilitySignature() then return
    RebuildRows()
end sub

' The hidden-catalog set that Home was built against. The settings store keeps
' entries in a deterministic array order for the life of the session, so its
' JSON representation is a cheap change signature without a network request.
function HomeCatalogVisibilitySignature() as string
    if m.stores = invalid then return ""
    hiddenCatalogs = m.stores.settings.callFunc("SettingsGetHiddenHomeCatalogs")
    if hiddenCatalogs = invalid then hiddenCatalogs = []
    return FormatJson(hiddenCatalogs)
end function

' Each result carries one completed row ({ row, done: false }) or the final
' completion marker. The task assigns each row a stable index, so the slot is
' cwOffset + index whether the Continue Watching row is present or not.
sub onCatalogState(event as object)
    if m.catalogRowsBuilt then return
    state = event.GetData()
    if state = invalid then return
    ' >= rather than =: a lost or coalesced result message must not wedge the
    ' walk — with an exact match, one missed row would fail the check forever
    ' and silently truncate the grid. ApplyCatalogRow slots by row.index, so a
    ' gapped arrival still lands every later row in its deterministic slot.
    if state.row <> invalid and state.row.index >= m.catalogRows.Count() then ApplyCatalogRow(state.row)
    if state.done = true then FinishCatalogLoad()
end sub

' Insert one streamed catalog row at its deterministic slot. All rows arrive in
' ascending index order, so the grid stays in task order even though each
' snapshot is a full copy.
sub ApplyCatalogRow(row as object)
    displayMetas = row.metas
    if displayMetas <> invalid and displayMetas.Count() > 15
        capped = []
        for i = 0 to 14
            capped.Push(displayMetas[i])
        end for
        capped.Push({ seeMore: true, name: Lang("home", "seeMore") })
        displayMetas = capped
    end if
    descriptor = {
        addonAddress: row.addonAddress
        catalogId: row.catalogId
        title: row.title
        metaType: row.metaType
        posterShape: TilePosterShape(row.metas)
        metas: displayMetas
    }
    cwOffset = 0
    if m.gridRows.Count() > 0 and m.gridRows[0].source = "library" then cwOffset = 1
    slot = cwOffset + row.index
    node = MakeRowNode(descriptor, invalid)
    if m.catalog.content <> invalid and m.catalog.content.getChildCount() > slot
        m.catalog.content.InsertChild(node, slot)
    else
        m.catalog.content.AppendChild(node)
    end if
    m.catalogRows.Push(descriptor)
    m.gridRows.Push(descriptor)
    UpdateHomeEmptyState()
    m.catalog.numRows = m.gridRows.Count()
    ApplyCatalogSizes()
    ResyncRowLabels()
    RefreshHomeHeroFromFocus()
end sub

' Rewrite row titles so duplicated catalog names carry their type suffix; only
' interesting once a later row turns a previously-unique name into a duplicate.
' A malformed (invalid/blank) title is coerced to "" so the histogram lookup
' cannot throw — the grid degrades to a blank label instead of crashing.
sub ResyncRowLabels()
    if m.catalog.content = invalid then return
    counts = DuplicateCounts()
    for r = 0 to m.gridRows.Count() - 1
        label = m.gridRows[r].title
        if label = invalid then label = ""
        if counts[label] > 1 then label = label + " · " + TypeLabel(m.gridRows[r].metaType)
        node = m.catalog.content.GetChild(r)
        if node <> invalid and node.title <> label then node.title = label
    end for
end sub

' The task finished (the walk completed or errored out): the rows already
' applied are the final row set. Tear the task node down.
sub FinishCatalogLoad()
    m.catalogRowsBuilt = true
    if m.catalogTask <> invalid
        task = m.catalogTask
        m.catalogTask = invalid
        AsyncTask_Reap(task, m.top, false)
    end if
    UpdateHomeEmptyState()
end sub

' Assemble the visible grid: Continue Watching (when the local library has
' entries) first, then the catalog rows as they stream in via onCatalogState.
' On first entry the content tree is created here; later visits refresh only the
' live Continue Watching row in place (see RefreshContinueWatching) so the rest
' of the grid keeps the RowList's own scroll + focus.
sub BuildRows()
    m.gridRows = []
    cw = LibraryRow()
    if cw <> invalid then m.gridRows.Push(cw)
    for each row in m.catalogRows
        m.gridRows.Push(row)
    end for

    counts = DuplicateCounts()

    content = CreateObject("roSGNode", "ContentNode")
    for r = 0 to m.gridRows.Count() - 1
        content.AppendChild(MakeRowNode(m.gridRows[r], counts))
    end for
    m.catalog.content = content
    if m.gridRows.Count() > 0 then m.catalog.numRows = m.gridRows.Count()
    ApplyCatalogSizes()
    UpdateHomeEmptyState()
    RefreshHomeHeroFromFocus()
end sub

' Keep the top hero synchronized with the focused poster. The focused row is
' supplied by RowList as [rowIndex, itemIndex]; all display data is already in
' the same meta the tile uses.
sub onCatalogItemFocused()
    UpdateHomeHero(m.catalog.rowItemFocused)
end sub

sub RefreshHomeHeroFromFocus()
    data = m.catalog.rowItemFocused
    if data <> invalid then UpdateHomeHero(data)
end sub

sub UpdateHomeHero(position as dynamic)
    if position = invalid or position.Count() < 2 then return
    rowIndex = position[0]
    itemIndex = position[1]
    if rowIndex < 0 or rowIndex >= m.gridRows.Count() then return
    metas = m.gridRows[rowIndex].metas
    if metas = invalid or itemIndex < 0 or itemIndex >= metas.Count() then return
    meta = metas[itemIndex]
    if meta <> invalid and meta.seeMore = true
        ' Keep the previously shown hero artwork/details; "see more" is an action,
        ' not a title to preview.
        CancelHeroMetaRequest()
        CancelHeroPrefetch()
        return
    end if
    key = HomeHeroMetaKey(meta)
    if key <> m.heroFocusKey
        CancelHeroMetaRequest()
        CancelHeroPrefetch()
        m.heroFocusKey = key
    end if
    if m.heroPrefetchDelay <> invalid
        m.heroPrefetchDelay.control = "stop"
        m.heroPrefetchDelay.control = "start"
    end if

    displayMeta = meta
    if m.heroMetaCache.DoesExist(key)
        displayMeta = m.stores.episodes.callFunc("EpisodesMergeMeta", meta, m.heroMetaCache[key])
        metas[itemIndex] = displayMeta
        UpdateHomeTileMeta(rowIndex, itemIndex, displayMeta)
    end if
    RenderHomeHero(displayMeta)
    meta = displayMeta

    needsHeroMeta = false
    if m.stores <> invalid and m.gridRows[rowIndex].source = "library"
        needsHeroMeta = m.stores.episodes.callFunc("EpisodesNeedsMetaFetch", meta)
        if StringOf(meta.background).Trim() = "" or StringOf(meta.description).Trim() = "" then needsHeroMeta = true
        if StringOf(meta.logo).Trim() = "" or Type(meta.genres) <> "roArray" then needsHeroMeta = true
        ' A full meta cached centrally (e.g. fetched by Details/Episodes) can fill
        ' the hero without another request, but we must not pull its episode list
        ' into the grid row or the focus path.
        if needsHeroMeta and not m.heroMetaCache.DoesExist(key)
            cachedFull = m.stores.episodes.callFunc("EpisodesFullMeta", meta.type, meta.id)
            if cachedFull <> invalid
                full = m.stores.episodes.callFunc("EpisodesMergeMeta", meta, cachedFull)
                display = m.stores.episodes.callFunc("EpisodesDisplayMeta", full)
                m.heroMetaCache[key] = display
                metas[itemIndex] = display
                UpdateHomeTileMeta(rowIndex, itemIndex, display)
                RenderHomeHero(display)
                meta = display
                needsHeroMeta = m.stores.episodes.callFunc("EpisodesNeedsMetaFetch", meta)
                if StringOf(meta.background).Trim() = "" or StringOf(meta.description).Trim() = "" then needsHeroMeta = true
                if StringOf(meta.logo).Trim() = "" or Type(meta.genres) <> "roArray" then needsHeroMeta = true
            end if
        end if
    end if
    if m.gridRows[rowIndex].source = "library" and not m.heroMetaCache.DoesExist(key)
        if needsHeroMeta and m.stores <> invalid
            if m.heroMetaRequest = invalid or m.heroMetaRequest.key <> key
                m.heroMetaRequest = { key: key, row: rowIndex, item: itemIndex, meta: meta }
                m.heroMetaDelay.control = "stop"
                m.heroMetaDelay.control = "start"
            end if
        end if
    else
        CancelHeroMetaRequest()
    end if
end sub

function HomeHeroMetaKey(meta as object) as string
    if meta = invalid then return ""
    return StringOf(meta.type) + "|" + StringOf(meta.id)
end function

sub RenderHomeHero(meta as object)
    if meta = invalid then return
    enriched = {}
    for each key in meta
        enriched[key] = meta[key]
    end for
    title = StringOf(enriched.name)
    if title.Trim() = "" then title = StringOf(enriched.title)
    if title.Trim() = "" then enriched.name = Lang("home", "continueWatching")
    description = StringOf(enriched.description)
    if description.Trim() = "" then description = StringOf(enriched.overview)
    if description.Trim() = "" and enriched.season <> invalid and enriched.episode <> invalid
        enriched.description = Fill(Lang("common", "episodeMarker"), { season: StringOf(enriched.season), episode: StringOf(enriched.episode) })
    end if
    HeroRender(enriched, "", false)
end sub

sub UpdateHomeTileMeta(rowIndex as integer, itemIndex as integer, meta as object)
    if m.catalog.content = invalid then return
    if rowIndex < 0 or rowIndex >= m.catalog.content.GetChildCount() then return
    rowNode = m.catalog.content.GetChild(rowIndex)
    if rowNode = invalid or itemIndex < 0 or itemIndex >= rowNode.GetChildCount() then return
    tile = rowNode.GetChild(itemIndex)
    if tile = invalid then return
    PaintTileFields(tile, meta, tile.watchedGlyph)
end sub

sub onHeroMetaDelayFire()
    if m.heroMetaRequest = invalid or m.heroMetaTask <> invalid then return
    if m.heroMetaRequest.key <> m.heroFocusKey then return
    address = MetaAddress()
    if address = "" then return
    request = m.heroMetaRequest
    task = AsyncTask_Launch(m.top, "MetaLoaderTask", "onHomeHeroMetaLoaded", {
        addonAddress: address
        metaType: request.meta.type
        metaId: request.meta.id
    }, "homeHeroMeta")
    m.heroMetaTask = task
    m.heroMetaTaskKey = request.key
end sub

sub onHomeHeroMetaLoaded()
    if m.heroMetaTask = invalid then return
    task = m.heroMetaTask
    result = task.result
    if result = invalid then return
    m.heroMetaTask = invalid
    m.heroMetaTaskKey = ""
    AsyncTask_Reap(task, m.top, false)
    request = m.heroMetaRequest
    m.heroMetaRequest = invalid
    if request = invalid or request.key <> m.heroFocusKey then return
    if result.ok <> true or result.meta = invalid then return
    full = m.stores.episodes.callFunc("EpisodesMergeMeta", request.meta, result.meta)
    m.stores.episodes.callFunc("EpisodesCacheFullMeta", full)
    display = m.stores.episodes.callFunc("EpisodesDisplayMeta", full)
    m.heroMetaCache[request.key] = display
    if request.row < 0 or request.row >= m.gridRows.Count() then return
    row = m.gridRows[request.row]
    if request.item < 0 or request.item >= row.metas.Count() then return
    if HomeHeroMetaKey(row.metas[request.item]) <> request.key then return
    row.metas[request.item] = display
    UpdateHomeTileMeta(request.row, request.item, display)
    RenderHomeHero(display)
end sub

sub CancelHeroMetaRequest()
    if m.heroMetaDelay <> invalid then m.heroMetaDelay.control = "stop"
    m.heroMetaRequest = invalid
    if m.heroMetaTask <> invalid
        task = m.heroMetaTask
        m.heroMetaTask = invalid
        m.heroMetaTaskKey = ""
        AsyncTask_Reap(task, m.top, true)
    end if
end sub

sub CancelHeroPrefetch()
    if m.heroPrefetchDelay <> invalid then m.heroPrefetchDelay.control = "stop"
    if m.heroPrefetchTasks <> invalid
        for each entry in m.heroPrefetchTasks
            if entry <> invalid and entry.task <> invalid then AsyncTask_Reap(entry.task, m.top, true)
        end for
    end if
    m.heroPrefetchTasks = []
    m.heroPrefetchKeys = {}
    ClearHeroLogoWarmers()
end sub

sub ClearHeroLogoWarmers()
    if m.heroLogoWarmers = invalid then return
    for each warmer in m.heroLogoWarmers
        if warmer <> invalid then warmer.uri = ""
    end for
end sub

sub onHeroPrefetchDelayFire()
    if m.heroFocusKey = "" or m.stores = invalid then return
    position = m.catalog.rowItemFocused
    if position = invalid or position.Count() < 2 then return
    rowIndex = position[0]
    itemIndex = position[1]
    if HomeHeroMetaKeyAt(rowIndex, itemIndex) <> m.heroFocusKey then return

    candidates = HeroPrefetchCandidates(rowIndex, itemIndex)
    WarmNeighborLogos(candidates)
    PrefetchNeighborHeroMeta(candidates)
    WarmNeighborLogos(HeroPrefetchCandidates(rowIndex, itemIndex))
end sub

function HomeHeroMetaKeyAt(rowIndex as integer, itemIndex as integer) as string
    if m.gridRows = invalid or rowIndex < 0 or rowIndex >= m.gridRows.Count() then return ""
    metas = m.gridRows[rowIndex].metas
    if metas = invalid or itemIndex < 0 or itemIndex >= metas.Count() then return ""
    return HomeHeroMetaKey(metas[itemIndex])
end function

function HeroPrefetchCandidates(rowIndex as integer, itemIndex as integer) as object
    candidates = []
    if m.gridRows = invalid or rowIndex < 0 or rowIndex >= m.gridRows.Count() then return candidates
    row = m.gridRows[rowIndex]
    metas = row.metas
    if metas = invalid then return candidates

    offsets = [-1, 1]
    for each offset in offsets
        idx = itemIndex + offset
        if idx >= 0 and idx < metas.Count()
            meta = metas[idx]
            key = HomeHeroMetaKey(meta)
            if key <> ""
                candidates.Push({
                    row: rowIndex
                    item: idx
                    meta: meta
                    key: key
                    source: row.source
                })
            end if
        end if
    end for
    return candidates
end function

sub WarmNeighborLogos(candidates as object)
    ClearHeroLogoWarmers()
    if m.heroLogoWarmers = invalid or candidates = invalid then return
    slot = 0
    for each candidate in candidates
        if slot >= m.heroLogoWarmers.Count() then exit for
        logo = HeroCandidateLogo(candidate)
        if logo <> ""
            warmer = m.heroLogoWarmers[slot]
            if warmer <> invalid then warmer.uri = logo
            slot = slot + 1
        end if
    end for
end sub

function HeroCandidateLogo(candidate as object) as string
    if candidate = invalid then return ""
    key = candidate.key
    if key <> "" and m.heroMetaCache <> invalid and m.heroMetaCache.DoesExist(key)
        cached = m.heroMetaCache[key]
        if cached <> invalid then return StringOf(cached.logo)
    end if
    if candidate.meta <> invalid then return StringOf(candidate.meta.logo)
    return ""
end function

sub PrefetchNeighborHeroMeta(candidates as object)
    if candidates = invalid or m.stores = invalid then return
    for each candidate in candidates
        if m.heroPrefetchTasks.Count() >= 2 then exit for
        if candidate.source <> "library" then continue for
        if candidate.key = "" or candidate.key = m.heroFocusKey then continue for
        if m.heroMetaCache <> invalid and m.heroMetaCache.DoesExist(candidate.key) then continue for
        if m.heroPrefetchKeys <> invalid and m.heroPrefetchKeys.DoesExist(candidate.key) then continue for
        if m.heroMetaTaskKey <> invalid and m.heroMetaTaskKey = candidate.key then continue for

        if HeroTryFillFromSharedCache(candidate) then continue for
        if not HeroCandidateNeedsEnrichment(candidate.meta) then continue for

        address = MetaAddress()
        if address = "" then continue for
        task = AsyncTask_Launch(m.top, "MetaLoaderTask", "onHeroPrefetchLoaded", {
            addonAddress: address
            metaType: candidate.meta.type
            metaId: candidate.meta.id
        }, "homeHeroPrefetch")
        if task = invalid then continue for
        m.heroPrefetchTasks.Push({ task: task, key: candidate.key, row: candidate.row, item: candidate.item })
        m.heroPrefetchKeys[candidate.key] = true
    end for
end sub

function HeroCandidateNeedsEnrichment(meta as object) as boolean
    if meta = invalid or m.stores = invalid then return false
    if m.stores.episodes.callFunc("EpisodesNeedsMetaFetch", meta) then return true
    if StringOf(meta.background).Trim() = "" then return true
    if StringOf(meta.description).Trim() = "" then return true
    if StringOf(meta.logo).Trim() = "" then return true
    if Type(meta.genres) <> "roArray" then return true
    return false
end function

function HeroTryFillFromSharedCache(candidate as object) as boolean
    if candidate = invalid or m.stores = invalid then return false
    cachedFull = m.stores.episodes.callFunc("EpisodesFullMeta", candidate.meta.type, candidate.meta.id)
    if cachedFull = invalid then return false
    full = m.stores.episodes.callFunc("EpisodesMergeMeta", candidate.meta, cachedFull)
    display = m.stores.episodes.callFunc("EpisodesDisplayMeta", full)
    m.heroMetaCache[candidate.key] = display
    StoreHeroDisplayMeta(candidate.row, candidate.item, candidate.key, display)
    return true
end function

sub StoreHeroDisplayMeta(rowIndex as integer, itemIndex as integer, key as string, display as object)
    if m.gridRows = invalid or rowIndex < 0 or rowIndex >= m.gridRows.Count() then return
    row = m.gridRows[rowIndex]
    metas = row.metas
    if metas = invalid or itemIndex < 0 or itemIndex >= metas.Count() then return
    if HomeHeroMetaKey(metas[itemIndex]) <> key then return
    metas[itemIndex] = display
    UpdateHomeTileMeta(rowIndex, itemIndex, display)
end sub

sub onHeroPrefetchLoaded(event as object)
    if event = invalid then return
    task = event.getRoSGNode()
    if task = invalid then return

    completed = invalid
    remaining = []
    for each entry in m.heroPrefetchTasks
        isMatch = false
        if completed = invalid and entry <> invalid and entry.task <> invalid
            isMatch = entry.task.isSameNode(task)
        end if
        if isMatch
            completed = entry
        else
            if entry <> invalid then remaining.Push(entry)
        end if
    end for
    m.heroPrefetchTasks = remaining
    if completed = invalid then return
    if m.heroPrefetchKeys <> invalid then m.heroPrefetchKeys.Delete(completed.key)

    result = task.result
    AsyncTask_Reap(task, m.top, false)

    if result = invalid or result.ok <> true or result.meta = invalid then return
    if m.stores = invalid then return

    baseMeta = invalid
    if m.gridRows <> invalid and completed.row >= 0 and completed.row < m.gridRows.Count()
        metas = m.gridRows[completed.row].metas
        if metas <> invalid and completed.item >= 0 and completed.item < metas.Count()
            if HomeHeroMetaKey(metas[completed.item]) = completed.key then baseMeta = metas[completed.item]
        end if
    end if
    if baseMeta = invalid then baseMeta = { id: result.meta.id, type: result.meta.type }

    full = m.stores.episodes.callFunc("EpisodesMergeMeta", baseMeta, result.meta)
    m.stores.episodes.callFunc("EpisodesCacheFullMeta", full)
    display = m.stores.episodes.callFunc("EpisodesDisplayMeta", full)
    m.heroMetaCache[completed.key] = display
    StoreHeroDisplayMeta(completed.row, completed.item, completed.key, display)

    if completed.key = m.heroFocusKey
        RenderHomeHero(display)
    end if

    position = m.catalog.rowItemFocused
    if position <> invalid and position.Count() >= 2 and HomeHeroMetaKeyAt(position[0], position[1]) = m.heroFocusKey
        WarmNeighborLogos(HeroPrefetchCandidates(position[0], position[1]))
    end if
end sub


' If Continue Watching and every catalog row are absent, explain where catalog
' rows come from and how to enable them instead of leaving an unexplained blank.
sub UpdateHomeEmptyState()
    if m.homeEmpty = invalid then return
    m.homeEmpty.text = Lang("home", "emptyCatalogRows")
    m.homeEmpty.visible = m.catalogRowsBuilt and m.gridRows.Count() = 0
end sub

' Rebuild the grid from the current add-on set — called by the Scene after a
' deep-link import registered new add-ons (see MainScene FinishImport). Mirrors
' a fresh launch: drop any in-flight catalog walk first so no stale result can
' apply, clear the accumulated descriptors, rebuild the content from Continue
' Watching only, then restart the walk so imported catalogs appear without an
' app relaunch. Safe to run while Home is under a dialog: the walk re-fills the
' rows one at a time behind it, and the existing guards (gridBuilt /
' catalogRowsBuilt / catalogTask) keep later OnEnter visits consistent.
function RebuildRows() as void
    CancelHeroMetaRequest()
    if m.catalogTask <> invalid
        ' STOP, and not a bare RemoveChild. The walk is a Task on its own thread,
        ' so removing a running Task node frees the node WITHOUT killing the
        ' worker — the trap AsyncTask.bs opens by spelling out. This walk can
        ' still be fetching when a deep-link import calls RebuildRows, so
        ' unobserved it runs to completion and lands its descriptors through
        ' onCatalogState anyway: two walks interleaving rows into a grid that has
        ' already been thrown away and rebuilt, with StartCatalogLoad below
        ' having launched a third. Reap with doStop = true, as AsyncTask.bs
        ' prescribes for a possibly-still-running task, and let the helper do the
        ' unobserving too. (FinishCatalogLoad reaps with false on purpose — by
        ' then that task has already reported in.)
        AsyncTask_Reap(m.catalogTask, m.top, true)
        m.catalogTask = invalid
    end if
    m.catalogRows = []
    m.catalogRowsBuilt = false
    m.gridRows = []
    m.gridBuilt = false
    BuildRows()
    m.gridLanguage = TextsLanguage()
    StartCatalogLoad()
end function

' Rebuild the title histogram across the current grid rows; used to decide the
' duplicated-name type suffix. An associative array cannot be keyed by invalid,
' so malformed titles are coerced to "" before the lookup (a row without a
' usable title then just groups with the other blank-label rows).
function DuplicateCounts() as object
    counts = {}
    for each row in m.gridRows
        title = row.title
        if title = invalid then title = ""
        count = counts[title]
        if count = invalid then count = 0
        counts[title] = count + 1
    end for
    return counts
end function

' Build the ContentNode for one grid row: a titled group of poster children.
' counts carries the merged name histogram so duplicated catalog labels get
' their type suffix (it is invalid for rows streamed in before their duplicate
' arrives — ResyncRowLabels backfills the suffix then, and for a freshly
' inserted Continue Watching row the label is unique anyway).
function MakeRowNode(row as object, counts = invalid as object) as object
    node = CreateObject("roSGNode", "ContentNode")
    label = row.title
    if label = invalid then label = ""
    if counts <> invalid and counts[label] > 1 then label = label + " · " + TypeLabel(row.metaType)
    node.title = label
    for each meta in row.metas
        item = node.CreateChild("TileContent")
        if meta.seeMore = true
            item.seeMore = true
            item.title = Lang("home", "seeMore")
            item.hdPosterUrl = ""
            item.progress = 0
            item.watchedGlyph = ""
            item.reloadNonce = 0
        else
            glyph = meta.watchedGlyph
            if glyph = invalid and m.stores <> invalid then glyph = m.stores.library.callFunc("LibraryWatchedGlyph", meta.id, meta.type)
            PaintTileFields(item, meta, glyph)
        end if
    end for
    return node
end function

' The poster cell for one grid row. Channel-style add-ons (Stremio content types
' "channel"/"tv") ship 1:1 posters, so those rows get square cells; everything
' else keeps the 2:3 poster slab. A catalog-supplied posterShape (folded to the
' row's majority shape once when the row lands) overrides the type fallback, so
' a 16:9 catalog gets a wide row instead of letterboxed 2:3 cells. PosterTile
' sizes itself from the cell it is handed, so this drives both the slot and the
' tile shape.
function RowCellSize(row as object) as object
    mt = invalid
    ps = ""
    if row <> invalid then
        mt = row.metaType
        if row.posterShape <> invalid then ps = row.posterShape
    end if
    ' Compact Home tiles and their row slots together, preserving each poster
    ' shape while revealing more of the next row at the bottom of the screen.
    size = TileCellSize(mt, ps)
    return [Int(size[0] * 0.92), Int(size[1] * 0.92)]
end function

' Per-row item sizes, one vector2d per grid row, in grid order. Rebuilt with the
' size of m.gridRows whenever the grid changes (rows stream in one at a time and
' the Continue Watching row slots in front).
function RowSizes() as object
    sizes = []
    for each row in m.gridRows
        sizes.Push(RowCellSize(row))
    end for
    return sizes
end function

' Set both the per-row tile sizes and the matching per-row heights. RowList reads
' a row's slot height from itemSize.y (one value for every row) unless rowHeights
' overrides it per row, so a landscape/square row taller-than-its-tile case left
' phantom space under every non-2:3 row. Mirroring the tile heights fixes the gap.
sub ApplyCatalogSizes()
    sizes = RowSizes()
    m.catalog.rowItemSize = sizes
    m.catalog.rowHeights = TileRowHeights(sizes)
end sub

' Paint the shared poster-tile fields — title, hdPosterUrl, progress-bar fraction
' and watched glyph — onto an item ContentNode. Overlay fields are always
' written a concrete value (""/0 when there is none): they're typed fields on
' TileContent, and on a recycled node an "unset" is not reliably cleared by
' assigning invalid, so a tile that previously held a bar/badge would keep it
' into a cell that has none. fallbackGlyph is the store-computed glyph when the
' meta did not carry one.
sub PaintTileFields(item as object, meta as object, fallbackGlyph as dynamic)
    name = meta.name
    if name = invalid then name = ""
    item.title = name
    poster = meta.poster
    if poster = invalid then poster = ""
    item.hdPosterUrl = poster
    item.progress = 0
    if meta.progress <> invalid and meta.progress > 0 then item.progress = meta.progress
    glyph = meta.watchedGlyph
    if glyph = invalid then glyph = fallbackGlyph
    if glyph = invalid then glyph = ""
    item.watchedGlyph = glyph
    if m.posterReloadNonce <> invalid then item.reloadNonce = m.posterReloadNonce
end sub

' The top row when the user has watched something: one tile per local
' continue-watching entry, carrying its resume hint so Details can reopen on
' the right spot. Items are synthesized catalog metas. Each tile also carries
' the progress fraction (position/duration) and the coarse watched glyph, so a
' finished watch paints a bar/badge on the tile without reopening Details.
function LibraryRow() as dynamic
    if m.stores = invalid then return invalid
    entries = m.stores.library.callFunc("LibraryContinueWatching")
    if entries = invalid then return invalid
    if entries.Count() = 0 then return invalid
    metas = []
    for each entry in entries
        metas.Push({
            id: entry.metaId
            type: entry.metaType
            name: entry.name
            poster: entry.poster
            posterShape: entry.posterShape
            videoId: entry.videoId
            season: entry.season
            episode: entry.episode
            position: entry.position
            playback: entry.playback
            progress: m.stores.library.callFunc("LibraryProgressFraction", entry.metaId)
            watchedGlyph: m.stores.library.callFunc("LibraryWatchedGlyph", entry.metaId, entry.metaType)
        })
    end for
    return { source: "library", title: Lang("home", "continueWatching"), metaType: "", posterShape: TilePosterShape(metas), metas: metas }
end function

function ContinueWatchingSignature() as string
    if m.stores = invalid then return ""
    entries = m.stores.library.callFunc("LibraryContinueWatching")
    if entries = invalid or entries.Count() = 0 then return ""
    parts = []
    for each entry in entries
        position = entry.position
        if position = invalid then position = 0
        duration = entry.duration
        if duration = invalid then duration = 0
        glyph = m.stores.library.callFunc("LibraryWatchedGlyph", entry.metaId, entry.metaType)
        parts.Push(entry.metaId + "|" + entry.videoId + "|" + entry.season.toStr() + "|" + entry.episode.toStr() + "|" + position.toStr() + "|" + duration.toStr() + "|" + glyph)
    end for
    parts.Sort("i")
    return parts.Join(";")
end function

' Live-update the Continue Watching row after progress was made elsewhere,
' without touching the rest of the grid. The catalog rows' nodes stay bit-for-bit
' intact, so the RowList's own scroll + focus survive the visit; only the top
' row's posters/titles change. A row appearing (first watch) or disappearing
' (history cleared) is handled by inserting/removing precisely that one row —
' which may clamp focus to the top, an acceptable reset confined to those rare
' transitions.
sub RefreshContinueWatching()
    if m.catalog.content = invalid then return
    content = m.catalog.content
    haveCw = m.gridRows.Count() > 0 and m.gridRows[0].source = "library"
    live = LibraryRow()
    if live <> invalid
        if haveCw
            SyncContinueWatchingRow(content.GetChild(0), live.metas)
            m.gridRows[0] = live
        else
            content.InsertChild(MakeRowNode(live, invalid), 0)
            m.gridRows.Unshift(live)
            m.catalog.numRows = m.gridRows.Count()
            ApplyCatalogSizes()
        end if
    else if haveCw
        content.RemoveChildIndex(0)
        m.gridRows.Delete(0)
        m.catalog.numRows = m.gridRows.Count()
        ApplyCatalogSizes()
    end if
    RefreshHomeHeroFromFocus()
end sub

' Refresh a row node's poster children to match a fresh meta list, reusing the
' existing child nodes by index so the RowList sees no structural change in the
' common case: no flicker, and focus holds even when entries reorder (a watched
' title rises to the front). Surplus children are trimmed from the tail.
sub SyncContinueWatchingRow(node as object, metas as object)
    existing = node.getChildCount()
    for c = 0 to metas.Count() - 1
        item = invalid
        if c < existing
            item = node.GetChild(c)
        else
            item = node.CreateChild("TileContent")
        end if
        PaintTileFields(item, metas[c], metas[c].watchedGlyph)
    end for
    while node.getChildCount() > metas.Count()
        node.RemoveChildIndex(node.getChildCount() - 1)
    end while
end sub

' Where the meta for a library-sourced tile comes from. The library records no
' addon origin, so the Cinemeta built-in (the meta authority) is the default.
function MetaAddress() as string
    if m.stores = invalid then return ""
    addon = m.stores.addons.callFunc("AddonsGet", "com.linvo.cinemeta")
    if addon = invalid then return ""
    return addon.address
end function

' Row-label suffix for duplicated catalog names.
'
' An add-on reports a catalog named "Popular" for a movie catalog and for a
' series catalog, so two rows would read the same, and the type is what tells
' them apart. The words are ours — a label we add, so they are translated —
' and the add-on's title is not, because what an add-on reports is what we
' show. Which is why the two are separated by a middle dot: a space read as
' part of the title, a middle dot reads as our annotation on it.
function TypeLabel(metaType as string) as string
    if metaType = "movie" then return Lang("common", "movies")
    if metaType = "series" then return Lang("common", "series")
    return metaType
end function

function OnEnter(params as object) as void
    ' Pull the current language before rebuilding the rail or grid labels.
    RefreshTexts()
    if not m.railBuilt or m.railLanguage <> TextsLanguage()
        BuildRail()
        m.railLanguage = TextsLanguage()
    end if
    StartCatalogLoad()
    sig = ContinueWatchingSignature()
    ' The grid is not rebuilt on every visit — that is what m.gridBuilt is
    ' for, and the rebuild is the expensive part of this screen. But the grid
    ' carries words (the Continue-Watching row, the type suffix on a
    ' duplicated name), and a language change makes every one of them wrong.
    ' So the language it was built in is part of what the grid remembers.
    if not m.gridBuilt or m.gridLanguage <> TextsLanguage()
        BuildRows()
        m.gridBuilt = true
        m.gridLanguage = TextsLanguage()
    else if sig <> m.cwSignature
        RefreshContinueWatching()
    end if
    m.cwSignature = sig
    ' After the Continue Watching reconciliation, and deliberately last: it is the
    ' catalog set that a sync can invalidate while the grid is already "built", and
    ' StartCatalogLoad above is a no-op once the walk has latched. Running it here
    ' as well means leaving for another screen and coming back repairs a stale
    ' grid, instead of the staleness being permanent until a relaunch.
    EnsureCurrentRows()
    UpdateHomeEmptyState()
    ' The place the cursor goes is the place it was left: the grid for a trip
    ' into the tiles, the rail — at the icon the user left it on — for a trip
    ' opened from the rail. BlurFocus records which had it.
    if m.railWasFocus = true
        FocusRail()
    else
        m.catalog.SetFocus(true)
    end if
    if m.catalog.rowItemFocused <> invalid then UpdateHomeHero(m.catalog.rowItemFocused)
end function

function OnExit() as void
end function

function OnBackPressed() as boolean
    return false
end function

' Remember where the grid sits when another screen takes focus. ScreenStack
' calls BlurFocus on every push; the content tree is never replaced after first
' entry, so the RowList keeps its own scroll + focus across every trip away and
' back — the one thing that must be saved is whether the focus belonged to the
' rail or the grid, so returning re-enters through the same one. A
' Continue-Watching open still in flight is cancelled: the user moved on, so
' its Details push must not land on the next screen.
sub BlurFocus()
    m.railWasFocus = m.railFocusIndex >= 0
    CollapseRail()
    CancelHeroMetaRequest()
    CancelHeroPrefetch()
    if m.heroTitleGrace <> invalid then m.heroTitleGrace.control = "stop"
    if m.heroPosterFadeAnim <> invalid then m.heroPosterFadeAnim.control = "stop"
    CancelOpen()
end sub

' The left rail: a fixed one-column icon menu. Built once (nodes created in init
' can be dropped pre-Show, so it happens on first OnEnter like the catalog). The
' last row is a modal (the support dialog), so its entry carries dialog = true
' and selection routes it through the pushRequest contract the same way;
' MainScene picks it up and shows the native dialog instead of pushing a
' stack screen.
sub BuildRail()
    entries = [
        { glyph: "pkg:/images/search.png", name: Lang("home", "railSearch"), screen: "searchScreen" }
        { glyph: "pkg:/images/discover.png", name: Lang("home", "railDiscover"), screen: "discoverScreen" }
        { glyph: "pkg:/images/library.png", name: Lang("home", "railLibrary"), screen: "libraryScreen" }
        { glyph: "pkg:/images/puzzle.png", name: Lang("home", "railAddons"), screen: "addonsScreen" }
        { glyph: "pkg:/images/settings.png", name: Lang("home", "railSettings"), screen: "settingsScreen" }
        { glyph: "pkg:/images/support.png", name: Lang("home", "railSupport"), screen: "supportDialog", dialog: true }
    ]
    m.railEntries = entries
    m.railFocusIndex = -1
    if m.railRememberedIndex >= entries.Count() then m.railRememberedIndex = 0
    while m.rail.GetChildCount() > 0
        m.rail.RemoveChildIndex(0)
    end while
    for i = 0 to entries.Count() - 1
        entry = entries[i]
        tile = m.rail.CreateChild("RailTile")
        tile.focusable = true
        tile.translation = [0, i * 120]
        tile.callFunc("SetTile", entry.glyph, entry.name)
    end for
    m.railBuilt = true
end sub

sub FocusRail()
    if m.railFocusIndex < 0 then m.railFocusIndex = m.railRememberedIndex
    if m.railFocusIndex >= m.rail.GetChildCount() then m.railFocusIndex = 0
    m.railRememberedIndex = m.railFocusIndex
    SetRailExpanded(true)
    m.rail.GetChild(m.railFocusIndex).focused = true
    m.rail.GetChild(m.railFocusIndex).SetFocus(true)
    if m.railExpandAnim <> invalid
        m.railCollapseAnim.control = "stop"
        m.railExpandAnim.control = "stop"
        m.railExpandAnim.control = "start"
    end if
end sub

sub CollapseRail()
    if m.railFocusIndex >= 0 and m.railFocusIndex < m.rail.GetChildCount()
        m.railRememberedIndex = m.railFocusIndex
        m.rail.GetChild(m.railFocusIndex).focused = false
    end if
    m.railFocusIndex = -1
    SetRailExpanded(false)
    if m.railCollapseAnim <> invalid
        m.railExpandAnim.control = "stop"
        m.railCollapseAnim.control = "stop"
        m.railCollapseAnim.control = "start"
    end if
end sub

sub SetRailExpanded(expanded as boolean)
    for i = 0 to m.rail.GetChildCount() - 1
        m.rail.GetChild(i).expanded = expanded
    end for
    if expanded
        m.railBg.color = Theme().navBgExpanded
        m.railBrandCollapseAnim.control = "stop"
        m.railBrandExpandAnim.control = "stop"
        m.railBrandExpandAnim.control = "start"
    else
        m.railBg.color = Theme().navBg
        m.railBrandExpandAnim.control = "stop"
        m.railBrandCollapseAnim.control = "stop"
        m.railBrandCollapseAnim.control = "start"
    end if
end sub

sub MoveRailFocus(delta as integer)
    if m.railFocusIndex < 0 then return
    nextIndex = m.railFocusIndex + delta
    if nextIndex < 0 or nextIndex >= m.rail.GetChildCount() then return
    m.rail.GetChild(m.railFocusIndex).focused = false
    m.railFocusIndex = nextIndex
    m.railRememberedIndex = nextIndex
    m.rail.GetChild(nextIndex).focused = true
    m.rail.GetChild(nextIndex).SetFocus(true)
end sub

' OK on a rail icon: an action request the Scene routes. Stack screens publish
' screen + params; the support modal adds dialog = true, which must survive into
' the pushRequest or the Scene would push the dialog node as a bogus stack
' screen and hide Home instead of showing the native dialog over it.
sub SelectRailEntry()
    if m.railFocusIndex < 0 or m.railEntries = invalid or m.railFocusIndex >= m.railEntries.Count() then return
    entry = m.railEntries[m.railFocusIndex]
    request = {
        screen: entry.screen
        params: {}
    }
    if entry.dialog = true then request.dialog = true
    m.top.pushRequest = request
end sub

' Cross-focus between the rail and the catalog grid. Left from the grid enters
' the rail; Right from the rail enters the grid. The rail tiles are plain
' focusable nodes, so Up/Down/OK are handled here and the default focus
' navigation is suppressed while the rail owns focus.
' Replay/instantreplay (↺) forces a full home refresh so partial/failed loads
' on poor connections can be retried without leaving and re-entering Home.
function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "instantreplay" or key = "replay"
        m.posterReloadNonce = m.posterReloadNonce + 1
        scene = m.top.getScene()
        if scene <> invalid then scene.callFunc("Notify", Lang("home", "refreshing"), "info")
        RebuildRows()
        return true
    end if

    if m.railFocusIndex >= 0
        if key = "right"
            CollapseRail()
            m.catalog.SetFocus(true)
            return true
        else if key = "up"
            MoveRailFocus(-1)
            return true
        else if key = "down"
            MoveRailFocus(1)
            return true
        else if key = "OK"
            SelectRailEntry()
            return true
        else if key = "options"
            CollapseRail()
            m.catalog.SetFocus(true)
            return true
        end if
    else if key = "left" and m.catalog.HasFocus()
        FocusRail()
        return true
    else if key = "options"
        if m.catalog.HasFocus()
            FocusRail()
            return true
        end if
    end if
    return false
end function

' rowItemSelected is a field observer, so this receives the roSGNodeEvent. Its
' data is a [row, itemIndex] pair; the selected name comes from the row's own
' data (the tiles only know their parsed label). A catalog tile opens Details
' for its meta. A Continue-Watching tile adds the resume hint and, like any
' other tile, needs its full meta from the Cinemeta built-in by id (the local
' record stores only what the Home row shows — id, name, poster, resume) so
' Details renders the same full hero as a catalog-opened title; that fetch now
' runs off the UI thread (OpenContinueWatching) so the grid stays interactive
' while it answers, and on failure the slim record falls back so the row still
' opens.
sub onRowItemSelected(event as object)
    data = event.GetData()
    if data = invalid or data.Count() < 2 then return
    row = data[0]
    index = data[1]
    if row < 0 or index < 0 or m.stores = invalid then return
    if row >= m.gridRows.Count() then return
    metas = m.gridRows[row].metas
    if index >= metas.Count() then return

    item = metas[index]
    if item <> invalid and item.seeMore = true
        m.top.pushRequest = {
            screen: "discoverScreen"
            params: {
                targetCatalog: {
                    addonAddress: m.gridRows[row].addonAddress
                    catalogId: m.gridRows[row].catalogId
                    metaType: m.gridRows[row].metaType
                }
            }
        }
        return
    end if
    if m.gridRows[row].source = "library"
        OpenContinueWatching(item)
    else
        m.top.pushRequest = {
            screen: "detailsScreen"
            params: {
                addonAddress: m.gridRows[row].addonAddress
                meta: item
            }
        }
    end if
end sub

' Begin opening a Continue-Watching tile. The full meta is fetched off the UI
' thread so Home stays interactive (Back, rail and other tiles keep working);
' the hint line shows "Loading…" meanwhile. A newer tile press or any
' navigation away cancels the pending open (CancelOpen); when the meta lands
' Details is pushed with the full hero, or the slim record on failure.
sub OpenContinueWatching(item as object)
    ' Continue Watching must remain a choice, not an automatic replay of the
    ' last source. Open the stream list for the saved movie/episode and let the
    ' viewer choose a provider and stream again. The library row is intentionally
    ' slim, so recover the full meta first; otherwise this route sends logo: ""
    ' and the player falls back to the rectangular poster during preparation.
    CancelOpen()
    CancelHeroMetaRequest()
    address = MetaAddress()
    key = HomeHeroMetaKey(item)
    display = invalid
    if m.heroMetaCache.DoesExist(key)
        display = m.stores.episodes.callFunc("EpisodesMergeMeta", item, m.heroMetaCache[key])
    else
        cachedFull = m.stores.episodes.callFunc("EpisodesFullMeta", item.type, item.id)
        if cachedFull <> invalid
            full = m.stores.episodes.callFunc("EpisodesMergeMeta", item, cachedFull)
            display = m.stores.episodes.callFunc("EpisodesDisplayMeta", full)
            m.heroMetaCache[key] = display
        end if
    end if
    if display <> invalid
        PushContinueWatchingStreams(item, display, address)
        return
    end if

    m.pendingOpen = {
        route: "streams"
        address: address
        meta: item
    }
    ShowHomeBusy(true)
    m.openTask = AsyncTask_Launch(m.top, "MetaLoaderTask", "onContinueWatchingLoaded", {
        addonAddress: address
        metaType: item.type
        metaId: item.id
    }, "continueWatchingLoader")
end sub

sub PushContinueWatchingStreams(item as object, meta as object, address as string)
    if item = invalid then return
    if meta = invalid then meta = item
    name = StringOf(meta.name)
    if name = "" then name = StringOf(item.name)
    poster = StringOf(meta.poster)
    if poster = "" then poster = StringOf(item.poster)
    posterShape = StringOf(meta.posterShape)
    if posterShape = "" then posterShape = StringOf(item.posterShape)
    description = StringOf(meta.description)
    if description = "" then description = StringOf(meta.overview)
    m.top.pushRequest = {
        screen: "streamsScreen"
        params: {
            addonAddress: address
            metaType: item.type
            metaId: item.id
            videoId: item.videoId
            season: item.season
            episode: item.episode
            position: item.position
            name: name
            poster: poster
            posterShape: posterShape
            logo: StringOf(meta.logo)
            background: StringOf(meta.background)
            description: description
            runtime: meta.runtime
        }
    }
end sub

' Original Continue Watching route: fill the slim library record from the meta
' provider and open Details. It is intentionally separate so a stale remembered
' source can fall back here without immediately attempting that same source
' again.
sub OpenContinueWatchingDetails(item as object)
    address = MetaAddress()
    CancelOpen()
    CancelHeroMetaRequest()
    key = HomeHeroMetaKey(item)
    display = invalid
    if m.heroMetaCache.DoesExist(key)
        display = m.stores.episodes.callFunc("EpisodesMergeMeta", item, m.heroMetaCache[key])
    else
        cachedFull = m.stores.episodes.callFunc("EpisodesFullMeta", item.type, item.id)
        if cachedFull <> invalid
            full = m.stores.episodes.callFunc("EpisodesMergeMeta", item, cachedFull)
            display = m.stores.episodes.callFunc("EpisodesDisplayMeta", full)
            m.heroMetaCache[key] = display
        end if
    end if
    if display <> invalid
        m.top.pushRequest = {
            screen: "detailsScreen"
            params: {
                addonAddress: address
                meta: display
                resume: { videoId: item.videoId, season: item.season, episode: item.episode, position: item.position }
            }
        }
        return
    end if
    m.pendingOpen = {
        route: "details"
        address: address
        meta: item
        resume: {
            videoId: item.videoId
            season: item.season
            episode: item.episode
            position: item.position
        }
    }
    ShowHomeBusy(true)

    task = AsyncTask_Launch(m.top, "MetaLoaderTask", "onContinueWatchingLoaded", {
        addonAddress: address
        metaType: item.type
        metaId: item.id
    }, "continueWatchingLoader")
    m.openTask = task
end sub

sub onRememberedStreamsLoaded()
    if m.openTask = invalid then return
    task = m.openTask
    result = task.result
    ' result is alwaysNotify and can notify once before the worker has supplied
    ' a value. Keep the task alive for the real answer.
    if result = invalid then return
    m.openTask = invalid
    AsyncTask_Reap(task, m.top, false)

    pending = m.pendingOpen
    m.pendingOpen = invalid
    ShowHomeBusy(false)
    if pending = invalid then return
    if result.streams = invalid or result.streams.Count() = 0
        OpenContinueWatchingDetails(pending.meta)
        return
    end if

    playback = pending.playback
    savedKey = StringOf(playback.Lookup("streamKey"))
    streamIndex = -1
    if savedKey <> ""
        for i = 0 to result.streams.Count() - 1
            if StreamIdentity(result.streams[i]) = savedKey
                streamIndex = i
                exit for
            end if
        next
    else
        savedIndex = playback.Lookup("streamIndex")
        if savedIndex <> invalid
            try
                streamIndex = Int(savedIndex)
            catch badIndex
                streamIndex = -1
            end try
        end if
    end if
    if streamIndex < 0 or streamIndex >= result.streams.Count()
        OpenContinueWatchingDetails(pending.meta)
        return
    end if

    mode = StringOf(playback.Lookup("directPlayMode"))
    if mode <> "on" and mode <> "off"
        mode = m.stores.settings.callFunc("SettingsGetDirectPlayMode")
        if mode <> "on" then mode = "off"
    end if
    item = pending.meta
    serverAddress = m.stores.settings.callFunc("SettingsGetServerAddress")
    m.top.pushRequest = {
        screen: "playerScreen"
        params: {
            stream: result.streams[streamIndex]
            directPlayMode: mode
            serverAddress: serverAddress
            metaType: item.type
            metaId: item.id
            videoId: item.videoId
            season: item.season
            episode: item.episode
            position: item.position
            name: item.name
            poster: item.poster
            posterShape: item.posterShape
            logo: ""
            background: ""
            addonAddress: pending.address
            providerAddress: StringOf(playback.Lookup("providerAddress"))
            streamIndex: streamIndex
        }
    }
end sub

' Stop a pending Continue-Watching open: tear down any in-flight task, clear the
' pending context and restore the hint. Called on blur (navigating away cancels
' the open) and when another tile supersedes it. STOP is the real cancel — merely
' removing a running Task node does not kill its worker thread (see MainScene) —
' and dropping the observer means its result can never land afterwards.
sub CancelOpen()
    if m.openTask <> invalid
        task = m.openTask
        m.openTask = invalid
        AsyncTask_Reap(task, m.top, true)
    end if
    m.pendingOpen = invalid
    ShowHomeBusy(false)
end sub

' The full meta arrived (or failed). CancelOpen dropped any superseded task's
' result before it could fire, so the pending context here is still the one that
' started this task. Push Details with the full meta, or the slim record on
' failure so the row still opens.
sub onContinueWatchingLoaded()
    if m.openTask = invalid then return
    task = m.openTask
    m.openTask = invalid
    result = task.result
    AsyncTask_Reap(task, m.top, false)

    pending = m.pendingOpen
    m.pendingOpen = invalid
    ShowHomeBusy(false)
    if pending = invalid then return

    meta = pending.meta
    if result <> invalid and result.ok and result.meta <> invalid
        full = m.stores.episodes.callFunc("EpisodesMergeMeta", pending.meta, result.meta)
        m.stores.episodes.callFunc("EpisodesCacheFullMeta", full)
        display = m.stores.episodes.callFunc("EpisodesDisplayMeta", full)
        key = HomeHeroMetaKey(meta)
        if key <> "" then m.heroMetaCache[key] = display
        meta = display
    end if
    if pending.route = "streams"
        PushContinueWatchingStreams(pending.meta, meta, pending.address)
        return
    end if
    m.top.pushRequest = {
        screen: "detailsScreen"
        params: {
            addonAddress: pending.address
            meta: meta
            resume: pending.resume
        }
    }
end sub

' A brief "Loading…" on the hint line while the Continue-Watching meta is
' fetched; the original hint text comes back when the open resolves or cancels.
sub ShowHomeBusy(show as boolean)
    if m.heroDescription = invalid then return
    if show
        if m.heroDescription.text <> Lang("home", "loading")
            m.heroBeforeBusy = m.heroDescription.text
            m.heroDescription.text = Lang("home", "loading")
        end if
    else
        if m.heroBeforeBusy <> invalid then m.heroDescription.text = m.heroBeforeBusy
        m.heroBeforeBusy = ""
    end if
end sub
