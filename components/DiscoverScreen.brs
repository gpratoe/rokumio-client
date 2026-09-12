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
    m.chips = m.top.FindNode("discoverChips")
    m.grid = m.top.FindNode("discoverGrid")
    m.menuGroup = m.top.FindNode("discoverMenuGroup")
    m.menuBackdrop = m.top.FindNode("discoverMenuBackdrop")
    m.menu = m.top.FindNode("discoverMenu")

    m.chips.ObserveField("rowItemSelected", "onChipSelected")
    m.menu.ObserveField("rowItemSelected", "onMenuSelected")
    m.grid.ObserveField("rowItemSelected", "onResultSelected")
    m.grid.ObserveField("itemFocused", "onGridFocused")

    m.chunk = 6
    m.chipsX = 150
    m.chipPitch = 272
    m.type = "movie"
    m.chart = "Popular"
    m.genre = "All"
    m.metas = []
    m.activeChip = 0
    m.menuOptions = []
    m.loaded = false
    m.allLoaded = false
    m.loadTask = invalid
    m.cinemetaAddress = ""
end sub

' Stores are class instances, which cannot cross components through an interface
' field, so the Scene hands them over with callFunc instead.
function SetStores(stores as object) as void
    m.stores = stores
end function

function OnEnter(params as object) as void
    if m.stores <> invalid and m.stores.addons <> invalid
        addon = m.stores.addons.Get("com.linvo.cinemeta")
        if addon <> invalid then m.cinemetaAddress = addon.address
    end if

    if m.menuGroup.visible then CloseMenu()

    ' Re-entry after Details: results are still here, just take focus back.
    if m.metas.Count() > 0
        m.grid.SetFocus(true)
        return
    end if

    if not m.loaded then FetchDiscover()
    BuildChips()
    m.chips.SetFocus(true)
end function

function OnExit() as void
    CancelLoad()
end function

function OnBackPressed() as boolean
    return false
end function

sub BlurFocus()
end sub

' --- chips ------------------------------------------------------------------

' The focused chip's value is stored raw (m.type/m.chart/m.genre); the chips
' show "Type · Movies"-style labels so each chip's role is readable. The genre
' chip is skipped while New is selected (New's only filter is the year).
sub BuildChips()
    entries = [
        { raw: m.type, label: "Type · " + TypeLabel(m.type) }
        { raw: m.chart, label: "Chart · " + m.chart }
    ]
    if m.chart <> "New" then entries.Push({ raw: m.genre, label: "Genre · " + m.genre })

    m.chipEntries = entries
    if m.activeChip >= entries.Count() then m.activeChip = entries.Count() - 1

    content = CreateObject("roSGNode", "ContentNode")
    row = content.CreateChild("ContentNode")
    for each entry in entries
        item = row.CreateChild("ContentNode")
        item.title = entry.label
    end for
    m.chips.content = content
    m.chips.jumpToRowItem = [0, m.activeChip]
end sub

function TypeLabel(metaType as string) as string
    if metaType = "series" then return "Series"
    return "Movies"
end function

' --- dropdown ---------------------------------------------------------------

' OK on a chip opens the dropdown for it, positioned under the chips row and
' pre-scrolled to the current value: whatever is focused is the value that OK
' will commit, Back leaves everything untouched.
sub onChipSelected()
    data = m.chips.rowItemSelected
    if data = invalid or data.Count() < 2 then return
    chip = data[1]
    if chip < 0 or chip >= m.chipEntries.Count() then return

    options = OptionsFor(chip)
    if options.Count() = 0 then return
    m.menuOptions = options
    m.activeChip = chip

    content = CreateObject("roSGNode", "ContentNode")
    for each option in options
        row = content.CreateChild("ContentNode")
        item = row.CreateChild("ContentNode")
        item.title = option.label
    end for
    m.menu.content = content

    shown = options.Count()
    if shown > 9 then shown = 9
    m.menu.numRows = shown
    m.menuBackdrop.width = 252
    m.menuBackdrop.height = shown * 56 + (shown - 1) * 6 + 4

    ' Hang the dropdown under the activating chip, not always the first one.
    ' The chips are one row of 260px tiles with a 12px gap (DiscoverScreen.xml),
    ' so menu x walks with the chip index; y lines up below the row.
    m.menuGroup.translation = [m.chipsX + chip * m.chipPitch, 300]

    m.menuGroup.visible = true
    m.menu.jumpToRowItem = [CurrentOptionIndex(), 0]
    m.menu.SetFocus(true)
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

function CurrentOptionIndex() as integer
    if m.activeChip = 0
        if m.type = "series" then return 1
        return 0
    else if m.activeChip = 1
        if m.chart = "New" then return 1
        if m.chart = "Featured" then return 2
        return 0
    end if
    index = 0
    for i = 0 to m.menuOptions.Count() - 1
        if m.menuOptions[i].raw = m.genre then index = i
    end for
    return index
end function

' OK inside the dropdown commits the highlighted option, then re-fetches. The
' menu lays one option per row, so rowItemSelected is [optionRow, 0] — the
' option index is the row (data[0]); a single-column row always reports 0 for
' the column. Re-picking the current value just closes the menu.
sub onMenuSelected()
    data = m.menu.rowItemSelected
    if data = invalid or data.Count() < 2 then return
    index = data[0]
    if index < 0 or index >= m.menuOptions.Count() then return
    option = m.menuOptions[index]

    if m.activeChip = 0
        if option.raw = m.type then CloseMenu() : return
        m.type = option.raw
    else if m.activeChip = 1
        if option.raw = m.chart then CloseMenu() : return
        m.chart = option.raw
    else if m.activeChip = 2
        if option.raw = m.genre then CloseMenu() : return
        m.genre = option.raw
    end if

    CloseMenu()
    BuildChips()
    ResetDiscover()
    FetchDiscover()
end sub

' Dismiss the dropdown and hand focus back to the chips. Called on Back (no
' change) and after a pick (the pick already committed above).
sub CloseMenu()
    m.menuGroup.visible = false
    m.chips.SetFocus(true)
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
    task = CreateObject("roSGNode", "DiscoverLoaderTask")
    task.id = "discoverLoader"
    m.top.AppendChild(task)
    task.addonAddress = m.cinemetaAddress
    task.metaType = m.type
    task.catalogId = CatalogId()
    task.extra = PageExtra(0)
    task.pageOffset = 0
    task.observeField("result", "onDiscoverLoaded")
    m.loadTask = task
    task.control = "RUN"
end sub

' The user scrolled near the bottom of the fetched results: fetch the next page
' (skip = metas already shown) and append. Silent — the grid stays up untouched
' until the page lands, so scrolling never blinks.
sub LoadMore()
    if m.cinemetaAddress = "" then return
    if m.loadTask <> invalid then return
    if m.allLoaded then return
    if m.metas.Count() = 0 then return

    task = CreateObject("roSGNode", "DiscoverLoaderTask")
    task.id = "discoverLoaderMore"
    m.top.AppendChild(task)
    task.addonAddress = m.cinemetaAddress
    task.metaType = m.type
    task.catalogId = CatalogId()
    task.extra = PageExtra(m.metas.Count())
    task.pageOffset = m.metas.Count()
    task.observeField("result", "onDiscoverLoaded")
    m.loadTask = task
    task.control = "RUN"
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

' A catalog page came back. Stale results are dropped: a page whose offset no
' longer matches the metas already shown landed after a filter change (which
' resets the list), and the m.loadTask guard drops anything that arrived after
' CancelLoad.
sub onDiscoverLoaded()
    if m.loadTask = invalid then return
    task = m.loadTask
    m.loadTask = invalid
    task.unobserveField("result")
    if task.getParent() <> invalid then m.top.RemoveChild(task)

    wantedOffset = task.pageOffset
    if wantedOffset <> m.metas.Count() then return

    label = DiscoverLabel()
    result = task.result
    if result = invalid or not result.ok or result.metas = invalid
        if m.metas.Count() = 0
            m.status.text = "Failed to load " + Chr(34) + label + Chr(34) + "."
            m.chips.SetFocus(true)
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
            m.chips.SetFocus(true)
            return
        end if
        UpdateGrid()
        m.status.text = ""
        m.chips.SetFocus(true)
    else
        for each meta in result.metas
            m.metas.Push(meta)
        end for
        m.allLoaded = not result.hasMore or result.metas.Count() = 0
        UpdateGrid(AppendRestoreRow())
        m.grid.SetFocus(true)
    end if
end sub

' The row index to keep visible after an append: the first row of the freshly
' added block when the focused row already fell off the end, otherwise the
' currently focused row.
function AppendRestoreRow() as integer
    if m.grid.rowItemFocused = invalid or m.grid.rowItemFocused.Count() < 2 then return 0
    before = m.grid.rowItemFocused[0]
    newRows = (m.metas.Count() + m.chunk - 1) / m.chunk
    if before < 0 then return 0
    if before >= newRows then return newRows - 1
    return before
end function

' The human summary of the current filters, e.g. "Featured · Movies · Sci-Fi".
function DiscoverLabel() as string
    label = m.chart + " · " + TypeLabel(m.type)
    if m.chart <> "New" and m.genre <> "All" then label = label + " · " + m.genre
    return label
end function

' Lay all loaded metas out as poster rows of m.chunk tiles so the RowList
' clips/scrolls them vertically. jumpToRow keeps the view anchored after an
' append.
sub UpdateGrid(rowToShow = -1 as integer)
    content = CreateObject("roSGNode", "ContentNode")
    for r = 0 to (m.metas.Count() - 1) / m.chunk
        row = content.CreateChild("ContentNode")
        for c = 0 to m.chunk - 1
            flat = r * m.chunk + c
            if flat >= m.metas.Count() then exit for
            meta = m.metas[flat]
            item = row.CreateChild("ContentNode")
            name = meta.name
            if name = invalid then name = ""
            item.title = name
            poster = meta.poster
            if poster <> invalid and poster <> "" then item.hdPosterUrl = poster
        end for
    end for
    m.grid.content = content
    m.grid.numRows = (m.metas.Count() + m.chunk - 1) / m.chunk
    if rowToShow >= 0 and m.grid.numRows > 0
        m.grid.jumpToRowItem = [rowToShow, 0]
    end if
end sub

sub CancelLoad()
    if m.loadTask <> invalid
        m.loadTask.unobserveField("result")
        m.loadTask.control = "STOP"
        if m.loadTask.getParent() <> invalid then m.top.RemoveChild(m.loadTask)
        m.loadTask = invalid
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

' Menu open: Back dismisses it (nothing changes), and the arrow keys are kept
' inside the dropdown instead of leaking to the stack/Scene. Otherwise Down
' from the chips enters the results grid and Up from the grid returns.
function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    if m.menuGroup.visible
        if key = "back"
            CloseMenu()
            return true
        end if
        if key = "options"
            CloseMenu()
            return true
        end if
        if key = "up" or key = "down" or key = "left" or key = "right"
            return true
        end if
        return false
    end if

    ' The asterisk key is a one-press escape hatch: from anywhere in the
    ' results grid it drops focus back up onto the filter chips.
    if key = "options" and m.grid.HasFocus()
        m.chips.SetFocus(true)
        return true
    else if key = "down" and m.chips.HasFocus()
        m.grid.SetFocus(true)
        return true
    else if key = "up" and m.grid.HasFocus()
        m.chips.SetFocus(true)
        return true
    end if
    return false
end function