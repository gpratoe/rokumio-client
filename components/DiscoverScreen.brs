' DiscoverScreen — Cinemeta browsing by three filters: type (movie/series),
' chart (Popular / New / Featured) and genre. Each filter is a chip; OK opens a
' dropdown menu of that chip's options. The dropdown is a Back-friendly menu —
' Up/Down move, OK picks, Back dismisses without changing anything — so a
' wrong pick is an instant undo, never a full cycle.
'
' A filter change kicks DiscoverLoaderTask off the render thread against the
' appropriate Cinemeta catalog (top / year / imdbRating), with the genre (or the
' current year for New) as a "genre=" extra. Results are chunked into poster
' rows; OK on a tile pushes DetailsScreen exactly like a Home catalog tile.
' Filters + results persist across Details round-trips; entry re-focuses the
' results when there is something to show, otherwise the chips.

sub init()
    m.status = m.top.FindNode("discoverStatus")
    m.header = m.top.FindNode("discoverHeader")
    m.filterBar = m.top.FindNode("filterBar")
    m.grid = m.top.FindNode("discoverGrid")

    t = Theme()
    m.top.FindNode("discoverTitle").color = t.accent
    m.top.FindNode("discoverSub").color = t.textSecondary
    m.status.color = t.accent
    m.header.color = t.textSecondary

    m.filterBar.ObserveField("chipActivated", "onChipActivated")
    m.filterBar.ObserveField("optionPicked", "onOptionPicked")
    m.grid.ObserveField("rowItemSelected", "onResultSelected")
    m.grid.ObserveField("itemFocused", "onGridFocused")

    m.chunk = 6
    m.type = "movie"
    m.chart = "Popular"
    m.genre = "All"
    m.metas = []
    m.loaded = false
    m.allLoaded = false
    m.loadTask = invalid
    m.cinemetaAddress = ""
end sub

function OnEnter(params as object) as void
    if m.stores <> invalid
        addon = m.stores.addons.callFunc("AddonsGet", "com.linvo.cinemeta")
        if addon <> invalid then m.cinemetaAddress = addon.address
    end if

    if m.filterBar.callFunc("IsMenuOpen") then m.filterBar.callFunc("HideMenu")

    ' Re-entry after Details: results are still here, just take focus back.
    if m.metas.Count() > 0
        m.grid.SetFocus(true)
        return
    end if

    if not m.loaded then FetchDiscover()
    SetChips()
    m.filterBar.callFunc("FocusChips")
end function

function OnExit() as void
    CancelLoad()
end function

function OnBackPressed() as boolean
    return false
end function

sub BlurFocus()
end sub

' --- filter chips (data) ----------------------------------------------------

' The chip row itself lives in FilterBar; the screen owns the values
' (m.type/m.chart/m.genre) and their labels. "Type · Movies"-style labels make
' each chip's role readable; the genre chip is skipped while New is selected
' (New's only filter is the year). Rebuilt on every pick so the label always
' reflects the active value.
sub SetChips()
    entries = [
        { raw: m.type, label: "Type · " + TypeLabel(m.type) }
        { raw: m.chart, label: "Chart · " + m.chart }
    ]
    if m.chart <> "New" then entries.Push({ raw: m.genre, label: "Genre · " + m.genre })
    m.filterBar.callFunc("SetChips", entries)
end sub

function TypeLabel(metaType as string) as string
    if metaType = "series" then return "Series"
    return "Movies"
end function

' The chip OK'd in the FilterBar: hand it that chip's options and the index of
' the current value, and the component opens the dropdown pre-scrolled there —
' whatever is focused is the value that OK will commit, Back leaves everything
' untouched.
sub onChipActivated()
    chip = m.filterBar.chipActivated
    if chip < 0 then return
    options = OptionsFor(chip)
    if options.Count() = 0 then return
    m.filterBar.callFunc("ShowMenu", options, CurrentOptionIndex(chip))
end sub

function OptionsFor(chip as integer) as object
    options = []
    if chip = 0
        options = [
            { raw: "movie", label: "Movies" }
            { raw: "series", label: "Series" }
        ]
    else if chip = 1
        options = [
            { raw: "Popular", label: "Popular" }
            { raw: "New", label: "New" }
            { raw: "Featured", label: "Featured" }
        ]
    else if chip = 2
        genres = ["All", "Action", "Adventure", "Animation", "Biography", "Comedy", "Crime", "Documentary", "Drama", "Family", "Fantasy", "History", "Horror", "Mystery", "Romance", "Sci-Fi", "Sport", "Thriller", "War", "Western"]
        for each genre in genres
            options.Push({ raw: genre, label: genre })
        end for
    end if
    return options
end function

function CurrentOptionIndex(chip as integer) as integer
    if chip = 0
        if m.type = "series" then return 1
        return 0
    else if chip = 1
        if m.chart = "New" then return 1
        if m.chart = "Featured" then return 2
        return 0
    end if
    options = OptionsFor(chip)
    index = 0
    for i = 0 to options.Count() - 1
        if options[i].raw = m.genre then index = i
    end for
    return index
end function

' An option OK'd in the FilterBar's dropdown, then re-fetches. Re-picking the
' current value just closes the menu. The raw value and the commit effect are
' the screen's; the component reports which chip and which row were picked.
sub onOptionPicked()
    pick = m.filterBar.optionPicked
    if pick = invalid or pick.chip = invalid or pick.index = invalid then return
    chip = pick.chip
    options = OptionsFor(chip)
    index = pick.index
    if index < 0 or index >= options.Count() then return
    option = options[index]

    if chip = 0
        if option.raw = m.type then m.filterBar.callFunc("HideMenu") : return
        m.type = option.raw
    else if chip = 1
        if option.raw = m.chart then m.filterBar.callFunc("HideMenu") : return
        m.chart = option.raw
    else if chip = 2
        if option.raw = m.genre then m.filterBar.callFunc("HideMenu") : return
        m.genre = option.raw
    end if

    m.filterBar.callFunc("HideMenu")
    SetChips()
    ResetDiscover()
    FetchDiscover()
end sub

' --- fetching ---------------------------------------------------------------

' The chart's catalog id: Popular → top, New → year, Featured → imdbRating.
function CatalogId() as string
    if m.chart = "New" then return "year"
    if m.chart = "Featured" then return "imdbRating"
    return "top"
end function

' The catalog "extra" segment for the current filters, without pagination.
' New's year catalog requires a genre extra whose options are years, so it
' always sends the current year; Popular and Featured take a real genre when one
' is chosen. The dropdown genre set is fixed ASCII (a hyphen is the only
' non-alphanumeric character, and it is RFC 3986 unreserved), so raw values need
' no encoding.
function FilterExtra() as string
    if m.chart = "New"
        return "genre=" + CreateObject("roDateTime").GetYear().ToStr()
    end if
    if m.genre <> "All"
        return "genre=" + m.genre
    end if
    return ""
end function

' Concatenate the filter extras with a skip offset (extras are k=v pairs joined
' by '&' in the Stremio protocol). skip counts already-loaded metas, so page 0 is
' "skip=0" whether or not a genre is pinned.
function PageExtra(offset as integer) as string
    filter = FilterExtra()
    if filter = "" then return "skip=" + offset.ToStr()
    return filter + "&skip=" + offset.ToStr()
end function

' A fresh filter set: start back at page 0.
sub ResetDiscover()
    m.metas = []
    m.allLoaded = false
    m.loaded = false
    if m.grid <> invalid
        m.grid.content = CreateObject("roSGNode", "ContentNode")
        m.grid.numRows = 0
    end if
end sub

' Kick the filtered catalog off the render thread against Cinemeta. A filter
' change supersedes whatever page is still in flight (its result is dropped by
' the offset guard below), so picks never queue behind a stale load. The wanted
' offset is captured so a page that lands after the user changed filters (or
' exited) is dropped instead of appended to the wrong list.
sub FetchDiscover()
    if m.cinemetaAddress = "" then return
    CancelLoad()

    m.status.text = "Loading…"
    task = AsyncTask_Launch(m.top, "DiscoverLoaderTask", "onDiscoverLoaded", {
        addonAddress: m.cinemetaAddress
        metaType: m.type
        catalogId: CatalogId()
        extra: PageExtra(0)
        pageOffset: 0
    }, "discoverLoader")
    m.loadTask = task
end sub

' The user scrolled near the bottom of the fetched results: fetch the next page
' (skip = metas already shown) and append. Silent — the grid stays up untouched
' until the page lands, so scrolling never blinks.
sub LoadMore()
    if m.cinemetaAddress = "" then return
    if m.loadTask <> invalid then return
    if m.allLoaded then return
    if m.metas.Count() = 0 then return

    task = AsyncTask_Launch(m.top, "DiscoverLoaderTask", "onDiscoverLoaded", {
        addonAddress: m.cinemetaAddress
        metaType: m.type
        catalogId: CatalogId()
        extra: PageExtra(m.metas.Count())
        pageOffset: m.metas.Count()
    }, "discoverLoaderMore")
    m.loadTask = task
end sub

' Near the bottom of the fetched results, pull the next page. The 3-row horizon
' means a smooth pre-load; because an append keeps the focused row anchored, one
' page lands per scroll instead of cascading to the end. itemFocused is the
' integer index of the focused row; the total row count is derived from what we
' have loaded (numRows is the visible count).
sub onGridFocused()
    row = m.grid.itemFocused
    rows = (m.metas.Count() + m.chunk - 1) / m.chunk
    if rows >= 4 and row >= rows - 3 then LoadMore()
end sub

' A landing may grab chips focus only when the dropdown is closed — an open
' menu keeps its focus through the landing so a load finishing can't yank the
' user out of a pick (the batch #2 / #4 screen-active rule, plus the menu
' guard).
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
        if m.metas.Count() = 0
            m.status.text = "Failed to load " + Chr(34) + label + Chr(34) + "."
            LandingChipsFocus()
        end if
        return
    end if

    if wantedOffset = 0
        m.metas = result.metas
        m.loaded = true
        m.header.text = label
        m.allLoaded = not result.hasMore or result.metas.Count() = 0
        if m.metas.Count() = 0
            m.grid.content = CreateObject("roSGNode", "ContentNode")
            m.grid.numRows = 0
            m.status.text = "No results for " + Chr(34) + label + Chr(34) + "."
            LandingChipsFocus()
            return
        end if
        UpdateGrid()
        m.status.text = ""
        LandingChipsFocus()
    else
        for each meta in result.metas
            m.metas.Push(meta)
        end for
        m.allLoaded = not result.hasMore or result.metas.Count() = 0
        UpdateGrid(AppendRestorePosition())
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

' The human summary of the current filters, e.g. "Featured · Movies · Sci-Fi".
function DiscoverLabel() as string
    label = m.chart + " · " + TypeLabel(m.type)
    if m.chart <> "New" and m.genre <> "All" then label = label + " · " + m.genre
    return label
end function

' Lay all loaded metas out as poster rows of m.chunk tiles so the RowList
' clips/scrolls them vertically. jumpToRow keeps the view anchored after an
' append, preserving the focused row and tile.
sub UpdateGrid(rowToShow = invalid as dynamic)
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

' --- selection --------------------------------------------------------------

' A result opens DetailsScreen through the same one-action channel Home and
' Search use for a catalog tile: full meta + the Cinemeta address.
sub onResultSelected()
    data = m.grid.rowItemSelected
    if data = invalid or data.Count() < 2 then return
    flat = data[0] * m.chunk + data[1]
    if flat < 0 or flat >= m.metas.Count() then return
    m.top.pushRequest = {
        screen: "detailsScreen"
        params: {
            addonAddress: m.cinemetaAddress
            meta: m.metas[flat]
        }
    }
end sub

' Focus travel between the chips and the results grid. The dropdown's own keys
' are handled inside FilterBar (it owns the menu focus); with the menu closed
' Down from the chips enters the results grid and Up from the grid returns.
function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    ' The asterisk key is a one-press escape hatch: from anywhere in the
    ' results grid it drops focus back up onto the filter chips.
    if key = "options" and m.grid.HasFocus()
        m.filterBar.callFunc("FocusChips")
        return true
    else if key = "down" and m.filterBar.callFunc("FocusIsOnChips")
        m.grid.SetFocus(true)
        return true
    else if key = "up" and m.grid.HasFocus()
        m.filterBar.callFunc("FocusChips")
        return true
    end if
    return false
end function
