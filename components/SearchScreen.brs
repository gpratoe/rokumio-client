' SearchScreen — Netflix-style split-pane search. The left column is an
' embedded SearchKeyboard (the DynamicMiniKeyboard extension): its native
' VoiceTextEditBox is the visible query box — the focused voice-enabled field
' the OS routes the remote's mic button to — with the compact key grid below.
' Every settled keystroke fans the query out to every search-capable catalog
' debounced 0.7s so a typed word searches once, not per letter. Results land
' as poster rows on the right, one per search-capable catalog — rows appear
' only for catalogs that return results, nothing is premised on the screen,
' so a catalog with no matches (or a failed add-on) simply never shows a row.
' Each row is titled "{Catalog} - {mediaType}" ("Popular - Movies", "HD - Tv
' channel"). OK on a result pushes DetailsScreen with the meta's own add-on
' address. The * (options) key always returns to the keyboard pane.
'
' Sources are resolved once per installed add-on set through the same shared
' resolution as Discover (CatalogSourcesTask fetches manifests the registry has
' none for; a query arriving before sources land is held as m.pendingQuery and
' run when they do). One SearchLoaderTask per add-on runs off the render thread,
' carrying that add-on's catalogs, and lands a { sections } batch the screen fans
' into rows by catalog key — so results appear as each add-on answers, in the
' same order the catalogs were discovered. Every new keystroke reaps the
' previous query's in-flight tasks (CancelSearch), so a slow add-on never
' accumulates stale work — only the latest query lives.

sub init()
    m.status = m.top.FindNode("searchStatus")
    m.hint = m.top.FindNode("searchHint")
    m.results = m.top.FindNode("searchResults")
    m.keyboard = m.top.FindNode("searchKeyboard")
    m.debounce = m.top.FindNode("queryDebounce")
    m.fitTimer = m.top.FindNode("keyboardFit")
    m.keyboardPane = m.top.FindNode("keyboardPane")
    m.paneBg = m.top.FindNode("paneBg")
    m.title = m.top.FindNode("searchTitle")
    m.searchPulse = m.top.FindNode("searchPulse")

    t = Theme()
    m.status.color = t.textSecondary
    m.hint.color = t.textSecondary
    m.title.color = t.textPrimary
    m.results.focusBitmapBlendColor = t.accentFocus
    ' The key grid reads its colors from the RSGPalette node set on its own
    ' palette field (never from a palette node in the tree: RSGPalette is
    ' non-renderable and its subtree is skipped by the render traversal).
    ' AppPalette carries both the Dialog* names the dialogs read and the
    ' KeyboardColor/PrimaryTextColor/FocusColor family this grid reads, so
    ' one palette styles both.
    m.keyboard.keyGrid.palette = AppPalette()
    ' On this pane the key faces step above the backdrop (dropdownBg) instead
    ' of matching it, so the grid reads as content on its own surface.
    palette = m.keyboard.keyGrid.palette
    if palette <> invalid
        palette.colors.KeyboardColor = t.tileFaceFocus
    end if
    ' The mini keyboard wraps at its grid edges by default, which swallows
    ' Down/Right forever and traps the user in the pane. Edges must propagate
    ' so the screen's onKeyEvent can hand focus to the results.
    m.keyboard.keyGrid.horizWrap = false
    m.keyboard.keyGrid.vertWrap = false
    m.paneBg.blendColor = t.dropdownBg

    m.keyboard.ObserveField("text", "onQueryChanged")
    ' Pane escapes come from inside the keyboard: the native grid consumes
    ' its arrows (and options) behind the scenes, so the screen-level
    ' onKeyEvent never sees them — the SearchKeyboard extension detects the
    ' edges and publishes them here.
    m.keyboard.ObserveField("escape", "onKeyboardEscape")
    m.debounce.ObserveField("fire", "onDebounceFire")
    m.results.ObserveField("rowItemSelected", "onResultSelected")
    m.fitTimer.ObserveField("fire", "onKeyboardFit")
    m.fitTimer.control = "start"

    m.pendingQuery = ""
    m.lastQuery = ""
    m.sources = []
    m.sourcesSignature = ""
    m.sourcesTask = invalid
    m.searchOrder = []
    m.landed = {}
    m.searchFailed = false
    m.rows = []
    m.searchTasks = invalid
    m.title.text = Lang("search", "title")
end sub

' The key grid builds from its Key Definition File off the render thread, so
' its painted width is not known at init. When it is: scale the keyboard down
' if it would cross into the results pane (the fit target is the left pane's
' 600px column), and size the pane backdrop to the keyboard's painted bounds
' (which include its visible text box) so the section reads as one surface.
' A zero rect means the grid has not built yet; OnEnter retries.
sub onKeyboardFit()
    FitKeyboard()
end sub

sub FitKeyboard()
    rect = m.keyboard.boundingRect()
    if rect = invalid or rect.width = invalid or rect.width <= 0 then return
    w = rect.width
    if w > 600
        s = 600 / w
        m.keyboard.scale = [s, s]
        w = 600
    else
        m.keyboard.scale = [1.0, 1.0]
    end if
    ' Backdrop: 24px padding on every side of the whole keyboard — the same
    ' generous framing the app's chips and panels use.
    h = rect.height * m.keyboard.scale[0]
    if rect.height = invalid or rect.height <= 0 then h = 700
    m.paneBg.width = w + 48
    m.paneBg.loadWidth = w + 48
    m.paneBg.height = h + 48
    m.paneBg.loadHeight = h + 48
end sub

sub FocusKeyboardPane()
    ' Focus the key grid, not the keyboard node: node-level SetFocus lands on
    ' the internal VoiceTextEditBox, whose caret navigation eats every arrow
    ' before it can bubble — the user could type but could never leave the
    ' pane. The grid is the real focusable: arrows move between keys, OK
    ' presses them, and edge arrows publish pane escapes through the
    ' SearchKeyboard extension.
    m.keyboard.keyGrid.SetFocus(true)
end sub

' The dictation-ready state. Config mirrors the dialog-era recipe that was
' verified working on device: the voice mode is applied AFTER the node is
' built (writes at creation time land before the dictation UI is listening
' and get dropped — see SearchKeyboard.init), and focus lands on the text
' box itself. Node-level SetFocus on the keyboard is NOT used for entry:
' when the keyboard node manages its own focus its native layer consumes
' Back, which stranded the user on the screen.
sub FocusQueryBox()
    editor = m.keyboard.textEditBox
    if editor <> invalid
        ' The box does not come voice-enabled on this firmware (it reads
        ' false at creation, docs notwithstanding — the mic press is handled
        ' globally by the OS and only reaches the app through a focused,
        ' voice-enabled box; no key event is ever delivered to the app, so
        ' this flag is the only door). Writes at creation time are dropped —
        ' the dictation UI is not listening yet, the lesson the dialog-era
        ' code already recorded — so it is asserted here, post-creation, at
        ' the moment before focus.
        editor.voiceEnabled = true
        ' Full-word dictation for search queries. The mini keyboard builds its
        ' box with voiceEntryType "alphanumeric" (letter-by-letter, meant for
        ' street addresses) — the same reason the dialog-era code pinned this.
        editor.voiceEntryType = "generic"
        editor.SetFocus(true)
    end if
end sub

sub FocusResultsPane()
    m.results.SetFocus(true)
end sub

' The status line above the results: "Searching…" pulses quietly; terminal
' states (errors, no results) hold steady; an empty text hides it. The pulse
' animation is stopped when hidden so it never runs invisibly.
sub SetSearchStatus(text as string, searching = false as dynamic)
    if searching <> true then searching = false
    if text = ""
        m.status.text = ""
        m.status.visible = false
        m.status.opacity = 1.0
        if m.searchPulse <> invalid then m.searchPulse.control = "stop"
        return
    end if
    m.status.text = text
    m.status.visible = true
    if searching
        if m.searchPulse <> invalid then m.searchPulse.control = "start"
    else
        if m.searchPulse <> invalid then m.searchPulse.control = "stop"
        m.status.opacity = 1.0
    end if
end sub

function OnEnter(params as object) as void
    ' The language first, then the labels that read it (the markup holds the
    ' English defaults; the table decides what is shown).
    RefreshTexts()
    m.title.text = Lang("search", "title")
    ' The add-on set can move while Search is off-screen (install/uninstall,
    ' session swap). Re-derive when it did, so the rows never describe a
    ' registry that no longer exists.
    if m.stores <> invalid and CatalogSignature() <> m.sourcesSignature then ResetSearch()

    ' A caller-supplied query (future rail-injected) runs as soon as sources are
    ' in hand; it is held in m.pendingQuery until they land. The pane shows the
    ' query too — the observer fires, the debounce runs, and the duplicate
    ' onDebounceFire is absorbed by the query = m.lastQuery guard.
    if params <> invalid and params.query <> invalid and params.query <> ""
        m.pendingQuery = params.query
        RestoreQueryText(params.query)
        EnsureSources()
        return
    end if

    ' Re-entry after Details: results are still here — restore the query box
    ' to match and take focus back on the results.
    if m.rows.Count() > 0
        RestoreQueryText(m.lastQuery)
        m.hint.visible = false
        m.results.SetFocus(true)
        return
    end if

    EnsureSources()
    ShowHint()
    FitKeyboard()
    ' Fresh entry lands dictation-ready: the mic button works at once, and
    ' Down steps into the key grid for d-pad typing.
    FocusQueryBox()
end function

function OnExit() as void
    ' Any query held while sources were still resolving is dropped with the
    ' exit — a later re-entry shows the pane ready for a fresh query, it must
    ' not replay it. The debounce dies with the screen too: no fire can run a
    ' search on a hidden screen.
    m.pendingQuery = ""
    m.debounce.control = "stop"
    CancelSearch()
    CancelSources()
end function

function OnBackPressed() as boolean
    return false
end function

sub BlurFocus()
    m.debounce.control = "stop"
end sub

' The quiet empty-state line above the rows, shown until the first typed
' character. Text is (re)read on entry so a language swap repopulates it.
sub ShowHint()
    if m.hint = invalid then return
    m.hint.text = Lang("search", "hint")
    m.hint.visible = true
end sub

' Puts a query back in the pane's box (re-entry after Details, a deep-link
' query) and parks the caret after it. The caret fix carried over from the
' dialog era: parked at 0, backspace and the left arrow are no-ops by
' definition while typing still appends, which reads as a dead keyboard.
' voiceEntryType is pinned to "generic" (full-word dictation) because the
' dynamic keyboard builds its internal edit box without a guarantee of that
' default across firmware.
sub RestoreQueryText(text as string)
    if m.keyboard.text <> text then m.keyboard.text = text
    editor = m.keyboard.textEditBox
    if editor <> invalid
        editor.voiceEntryType = "generic"
        editor.cursorPosition = Len(text)
    end if
end sub

' --- sources (which add-ons serve which catalogs) ---------------------------

' The installed add-on set the current sources were derived from, as a
' comparable string. Mirrors Home/Discover: derive from live store state, sort
' so ordering cannot make two equal sets look different, join. No network — a
' set comparison, not a re-derivation.
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
        SetSearchStatus(Lang("search", "loadFailedAddons"))
        return
    end if

    signature = CatalogSignature()
    if signature = m.sourcesSignature and m.sources.Count() > 0 then
        FlushPendingQuery()
        return
    end if

    addons = m.stores.addons.callFunc("AddonsGetAll")
    if addons = invalid then addons = []

    packets = []
    allKnown = true
    for each addon in addons
        address = addon.address
        if address = invalid or address = "" then continue for
        resources = addon.resources
        hasCatalog = false
        if resources <> invalid and Type(resources) = "roArray"
            hasCatalog = m.stores.addons.callFunc("AddonsHasResource", resources, "catalog")
        end if
        if not hasCatalog then continue for
        if addon.catalogs = invalid or Type(addon.catalogs) <> "roArray" then allKnown = false
        name = addon.name
        if name = invalid then name = ""
        packets.Push({ address: address, name: name, resources: resources, catalogs: addon.catalogs })
    end for

    m.sourcesSignature = signature
    if packets.Count() = 0
        m.sources = []
        FlushPendingQuery()
        return
    end if

    if allKnown
        m.sources = packets
        FlushPendingQuery()
        return
    end if

    CancelSources()
    task = AsyncTask_Launch(m.top, "CatalogSourcesTask", "onSourcesLoaded", { addons: packets }, "searchSources")
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
        SetSearchStatus(Lang("search", "loadFailedAddons"))
        return
    end if

    m.sources = result.sources
    FlushPendingQuery()
end sub

sub CancelSources()
    if m.sourcesTask <> invalid
        task = m.sourcesTask
        m.sourcesTask = invalid
        AsyncTask_Reap(task, m.top, true)
    end if
end sub

' A query that arrived before sources landed: run it now that they have. Nothing
' to do for a plain entry (no pending query).
sub FlushPendingQuery()
    if m.pendingQuery <> invalid and m.pendingQuery <> "" then
        query = m.pendingQuery
        m.pendingQuery = ""
        RunSearch(query)
    end if
end sub

' Drop the sources/rows/results for a changed add-on set so the next entry
' re-resolves from scratch.
sub ResetSearch()
    CancelSearch()
    CancelSources()
    m.sources = []
    m.sourcesSignature = ""
    m.pendingQuery = ""
    m.lastQuery = ""
    m.searchOrder = []
    m.landed = {}
    m.searchFailed = false
    m.rows = []
    ClearResults()
end sub

sub ClearResults()
    if m.results <> invalid
        m.results.content = CreateObject("roSGNode", "ContentNode")
        m.results.numRows = 0
    end if
end sub

' --- live query (the keyboard pane) -----------------------------------------

' The embedded keyboard reports its own text — typed keys and voice dictation
' alike land here. Every change reaps the previous query's in-flight tasks so
' a slow add-on never answers into the wrong query, and restarts the debounce
' window that fans the settled query out. Landed rows stay visible until the
' new search replaces them.
sub onQueryChanged()
    CancelSearch()
    SetSearchStatus("")

    query = m.keyboard.text.Trim()
    if query.Len() < 2
        ' Too short to search: back to the fresh-screen state. Emptying the
        ' box is unambiguous, so the results go immediately rather than
        ' waiting out the debounce.
        m.debounce.control = "stop"
        m.lastQuery = ""
        m.searchOrder = []
        m.landed = {}
        m.searchFailed = false
        m.rows = []
        ClearResults()
        ShowHint()
        return
    end if

    m.hint.visible = false
    m.debounce.control = "stop"
    m.debounce.control = "start"
end sub

' The debounce window closed on a quiet keyboard: fan the query out — unless
' it is the query already on screen (the same string arriving twice: a text
' restore on re-entry, or a deep-link replay after FlushPendingQuery).
sub onDebounceFire()
    query = m.keyboard.text.Trim()
    if query.Len() < 2 then return
    if query = m.lastQuery then return
    RunSearch(query)
end sub

' OK while the keyboard pane holds focus skips the debounce window and fans
' the query out immediately.
sub onSearchSubmitted()
    query = m.keyboard.text.Trim()
    if query.Len() < 2 then return
    if query = m.lastQuery then return
    m.debounce.control = "stop"
    RunSearch(query)
end sub

' Kick the query off the render thread against every search-capable catalog
' across the resolved sources. One SearchLoaderTask per add-on runs in parallel,
' each carrying that add-on's catalogs. No rows are premised: the grid stays
' empty until a catalog answers with results, and each row is then inserted in
' the catalog's discovery order.
sub RunSearch(query as string)
    if query = "" then
        SetSearchStatus(Lang("search", "typeNothing"))
        return
    end if

    ' Sources still resolving (a task is in flight): hold the query until they
    ' land, then run against whatever arrived.
    if m.sources = invalid or m.sources.Count() = 0
        if m.sourcesTask <> invalid
            m.pendingQuery = query
            SetSearchStatus(Lang("search", "searching"), true)
            return
        end if
        SetSearchStatus(Lang("search", "noSearchAddons"))
        return
    end if

    candidates = SearchCandidates()

    CancelSearch()
    m.pendingQuery = ""
    m.lastQuery = query

    if candidates.Count() = 0 then
        m.searchOrder = []
        m.landed = {}
        m.searchFailed = false
        m.rows = []
        ClearResults()
        SetSearchStatus(Lang("search", "noSearchAddons"))
        return
    end if

    m.searchOrder = candidates
    m.landed = {}
    m.searchFailed = false
    m.rows = []
    m.searchTasks = {}
    SetSearchStatus(Lang("search", "searching"), true)
    m.hint.visible = false
    ClearResults()

    LaunchSearchTasks()
end sub

' The ordered list of searchable catalogs across all sources: one entry per
' search-capable catalog, in addon/manifest order. Title is always
' "{Catalog} - {mediaType}"; when two entries would still carry the same title
' (same catalog name, same media type, different add-ons) the add-on's name is
' prefixed so the rows stay distinguishable.
function SearchCandidates() as object
    candidates = []
    if m.stores = invalid then return candidates

    for each source in m.sources
        if source = invalid then continue for
        if source.catalogs = invalid then continue for
        address = source.address
        if address = invalid or address = "" then continue for
        addonName = source.name
        if addonName = invalid then addonName = ""
        for each descriptor in source.catalogs
            if descriptor = invalid then continue for
            if descriptor.type = invalid or descriptor.type = "" then continue for
            if descriptor.id = invalid or descriptor.id = "" then continue for
            caps = m.stores.addons.callFunc("AddonsCatalogCapabilities", descriptor)
            if caps = invalid or not caps.search then continue for
            base = m.stores.addons.callFunc("AddonsCatalogTitle", descriptor, source.name)
            candidates.Push({
                key: address + "|" + descriptor.type + "|" + descriptor.id
                addonKey: address
                addonName: addonName
                addonAddress: address
                rawType: descriptor.type
                catalogId: descriptor.id
                title: base + " - " + TypeSearchLabel(descriptor.type)
            })
        end for
    end for

    titleCounts = {}
    for each c in candidates
        if titleCounts[c.title] = invalid then titleCounts[c.title] = 0
        titleCounts[c.title] = titleCounts[c.title] + 1
    end for
    for each c in candidates
        if titleCounts[c.title] > 1 then c.title = c.addonName + " - " + c.title
    end for

    return candidates
end function

' The media type half of a search row title ("Popular - Movies"). movie/series
' read as "Movies"/"Series"; channel and tv are one family spelled "Tv channel";
' anything else keeps its declared name capitalized.
function TypeSearchLabel(raw as dynamic) as string
    if raw = invalid then return ""
    if raw = "movie" then return Lang("common", "movies")
    if raw = "series" then return Lang("common", "series")
    if raw = "channel" or raw = "tv" then return Lang("search", "tvChannel")
    if raw = "" then return ""
    ' UCase is a global function, not an roString method; the chained form threw
    ' &hf4 the first time an add-on declared a custom catalog type.
    return UCase(raw.Left(1)) + raw.Mid(1)
end function

' One SearchLoaderTask per add-on, passing the catalogs that add-on serves.
' Tasks are independent, so their completion order does not matter.
sub LaunchSearchTasks()
    byAddon = {}
    order = []
    for each candidate in m.searchOrder
        addonKey = candidate.addonKey
        if byAddon.DoesExist(addonKey) = false
            byAddon[addonKey] = { address: candidate.addonAddress, cats: [] }
            order.Push(addonKey)
        end if
        byAddon[addonKey].cats.Push({
            key: candidate.key
            type: candidate.rawType
            id: candidate.catalogId
        })
    end for

    for each addonKey in order
        task = AsyncTask_Launch(m.top, "SearchLoaderTask", "onSearchLoaded", {
            addonAddress: byAddon[addonKey].address
            addonKey: addonKey
            catalogs: byAddon[addonKey].cats
            query: m.lastQuery
        }, "searchLoader" + addonKey)
        m.searchTasks[addonKey] = task
    end for
end sub

' One add-on's search landed (or failed). The task reports its sections keyed by
' catalog key; a stale result that landed after CancelSearch is dropped by the
' slot guard — the whole map is invalid (cancel), or the slot was cleared
' (already applied). A section's metas are parked in m.landed by key, then the
' row list is rebuilt from scratch so only catalogs that actually returned
' results appear, in discovery order.
sub onSearchLoaded(event as object)
    if m.searchTasks = invalid then return
    task = event.GetRoSGNode()
    if task = invalid then return
    addonKey = task.addonKey
    if addonKey = invalid or addonKey = "" then return
    slot = m.searchTasks[addonKey]
    if slot = invalid then return
    m.searchTasks[addonKey] = invalid

    result = task.result
    AsyncTask_Reap(task, m.top, false)

    if result = invalid or result.sections = invalid or Type(result.sections) <> "roArray"
        m.searchFailed = true
    else
        for each section in result.sections
            if section = invalid or section.key = invalid then continue for
            if section.metas <> invalid and section.metas.Count() > 0
                m.landed[section.key] = section.metas
            else if section.error <> invalid and section.error <> ""
                m.searchFailed = true
            end if
        end for
    end if

    RebuildRows()
    UpdateSearchStatus()
end sub

' m.rows = every catalog that landed metas, in the discovery order of
' m.searchOrder. Rows appear only with results, so a catalog with no matches (or
' an add-on that got no usable answer) never occupies a row.
sub RebuildRows()
    prevCount = m.rows.Count()
    rows = []
    for each candidate in m.searchOrder
        metas = m.landed[candidate.key]
        if metas <> invalid and metas.Count() > 0
            rows.Push({
                key: candidate.key
                addonAddress: candidate.addonAddress
                title: candidate.title
                rawType: candidate.rawType
                metas: metas
            })
        end if
    end for
    m.rows = rows
    RenderRows()
    if prevCount = 0 and m.rows.Count() > 0 then m.results.jumpToRowItem = [0, 0]
end sub

' Rebuild the whole grid from m.rows. Every row carries only landed metas, so
' there is nothing to render while a catalog is still resolving — the status
' line says what is happening.
sub RenderRows()
    content = CreateObject("roSGNode", "ContentNode")
    sizes = []
    for each row in m.rows
        rowNode = content.CreateChild("ContentNode")
        rowNode.title = row.title
        for each meta in row.metas
            entry = rowNode.CreateChild("TileContent")
            name = meta.name
            if name = invalid then name = ""
            entry.title = name
            poster = meta.poster
            if poster <> invalid and poster <> "" then entry.hdPosterUrl = poster
            glyph = ""
            if m.stores <> invalid then glyph = m.stores.library.callFunc("LibraryWatchedGlyph", meta.id, meta.type)
            entry.watchedGlyph = glyph
        end for
        ' Each result catalog sizes its own row to its posterShape (folded from
        ' the metas), so a landscape catalog lands wide rows even among 2:3 ones;
        ' falls back to the content type when no shape ships.
        sizes.Push(TileCellSize(row.rawType, TilePosterShape(row.metas)))
    end for
    m.results.content = content
    m.results.rowItemSize = sizes
    ' Per-row slot heights so a landscape/square catalog row sits tight instead of
    ' inheriting the 2:3 itemSize height and leaving a phantom gap (see
    ' TileRowHeights).
    m.results.rowHeights = TileRowHeights(sizes)
    m.results.numRows = m.rows.Count()
end sub

' The status line: "Searching…" while any add-on is still resolving; once all
' settle, clears when results exist, names the failure when every catalog failed,
' or says there were no matches.
sub UpdateSearchStatus()
    if m.searchTasks = invalid then return
    pending = 0
    for each key in m.searchTasks
        if m.searchTasks[key] <> invalid then pending = pending + 1
    end for
    if pending > 0
        ' The moment any catalog has landed results, stop the busy state — the
        ' rows are already useful and more may stream in quietly behind them.
        if m.rows.Count() = 0
            SetSearchStatus(Lang("search", "searching"), true)
        else
            SetSearchStatus("")
        end if
    else if m.rows.Count() > 0
        SetSearchStatus("")
    else if m.searchFailed
        SetSearchStatus(Lang("search", "searchFailed"))
    else
        SetSearchStatus(Fill(Lang("search", "noResults"), { query: m.lastQuery }))
    end if
end sub

sub CancelSearch()
    if m.searchTasks <> invalid
        for each key in m.searchTasks
            task = m.searchTasks[key]
            if task <> invalid then AsyncTask_Reap(task, m.top, true)
        end for
    end if
    m.searchTasks = invalid
end sub

' A result opens DetailsScreen through the same one-action channel Home uses for
' a catalog tile: full meta + the source add-on's address (from the row).
sub onResultSelected()
    data = m.results.rowItemSelected
    if data = invalid or data.Count() < 2 then return
    row = data[0]
    index = data[1]
    if row < 0 or index < 0 then return
    if row >= m.rows.Count() then return
    target = m.rows[row]
    metas = target.metas
    if index >= metas.Count() then return
    m.top.pushRequest = {
        screen: "detailsScreen"
        params: {
            addonAddress: target.addonAddress
            meta: metas[index]
        }
    }
end sub

' The keyboard extension reported a pane escape: Down/Right pressed at an
' edge of the grid (no focus movement followed), or the * key. Edges move to
' the results when they exist; * toggles back home from the results.
sub onKeyboardEscape()
    key = m.keyboard.escape
    if key = "options"
        FocusKeyboardPane()
    else if key = "OK"
        onSearchSubmitted()
    else if key = "up"
        FocusQueryBox()
    else if key = "down" or key = "right"
        if m.rows.Count() > 0 then FocusResultsPane()
    end if
end sub

' Screen-level keys are only the ones the keyboard lets through — which is
' to say, the ones pressed while the RESULTS hold focus. While the keyboard
' pane is focused, its own extension owns options and the edge arrows.
function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "options" and m.keyboard.HasFocus() = false
        FocusKeyboardPane()
        return true
    end if
    if m.results.HasFocus()
        data = m.results.rowItemFocused
        onFirstColumn = data <> invalid and data.Count() >= 2 and data[1] = 0
        onFirstRow = data <> invalid and data.Count() >= 2 and data[0] = 0
        if (key = "left" and onFirstColumn) or (key = "up" and onFirstRow)
            FocusKeyboardPane()
            return true
        end if
    end if
    return false
end function