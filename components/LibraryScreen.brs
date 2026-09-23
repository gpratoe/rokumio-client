' LibraryScreen — the saved library for the current session. Two chips drive the
' grid: a content-type filter (All/Movies/Series) and a sort order (Recently
' added/A-Z/Z-A/Watched). OK on a chip opens a dropdown menu of that chip's
' options — Up/Down move, OK picks, Back dismisses without changing anything —
' so a wrong pick is an instant undo, never a full cycle. The layout is
' DiscoverScreen's: chips + dropdown above a poster grid, but everything is
' served straight from LibraryStore, no tasks, nothing to load.
'
' The grid is re-sliced whenever a filter or sort changes and on every
' OnEnter/RefreshRows, so a save made on another screen (or a background library
' sync landing while this screen is top) shows up on the next build. A filter
' change keeps the focus on the chips (close the menu, pick a new one); with a
' non-empty view the entry re-focuses the results so OK opens Details like any
' other tile.

sub init()
    m.status = m.top.FindNode("libraryStatus")
    m.header = m.top.FindNode("libraryHeader")
    m.chips = m.top.FindNode("libraryChips")
    m.grid = m.top.FindNode("libraryGrid")
    m.menuGroup = m.top.FindNode("libraryMenuGroup")
    m.menuBackdrop = m.top.FindNode("libraryMenuBackdrop")
    m.menu = m.top.FindNode("libraryMenu")

    m.chips.ObserveField("rowItemSelected", "onChipSelected")
    m.menu.ObserveField("rowItemSelected", "onMenuSelected")
    m.grid.ObserveField("rowItemSelected", "onResultSelected")

    m.chunk = 6
    m.chipsX = 150
    m.chipPitch = 272
    m.typeFilter = "all"
    m.sort = "recent"
    m.items = []
    m.chipEntries = []
    m.menuOptions = []
    m.activeChip = 0
    m.cinemetaAddress = ""
end sub

function OnEnter(params as object) as void
    if m.stores <> invalid and m.stores.addons <> invalid
        addon = m.stores.addons.Get("com.linvo.cinemeta")
        if addon <> invalid then m.cinemetaAddress = addon.address
    end if

    if m.menuGroup.visible then CloseMenu()

    ' Re-slice every entry (like Addons/Settings): a save toggle on a Details
    ' screen — or a background sync landing while this screen is under another
    ' one — can change the saved set while we were away.
    BuildChips()
    BuildRows()
    if m.items.Count() > 0
        m.grid.SetFocus(true)
    else
        m.chips.SetFocus(true)
    end if
end function

function OnExit() as void
end function

function OnBackPressed() as boolean
    return false
end function

sub BlurFocus()
end sub

' The Scene's poke when a background library sync lands while this screen is
' top (the relaunched-stremio-session case). Same rebuild as entry — idempotent;
' the grid content is replaced so the freshly synced saved set shows up.
' Leaving the focus where it is keeps an in-flight re-slice from stealing
' navigation.
function RefreshRows() as void
    BuildRows()
end function

' --- chips ------------------------------------------------------------------

' The chips show "Type · All"-style labels so each chip's role is readable; the
' focused chip's value lives raw in m.typeFilter/m.sort. Rebuilt on every pick
' so the label always reflects the active value.
sub BuildChips()
    entries = [
        { raw: m.typeFilter, label: "Type · " + TypeLabel(m.typeFilter) }
        { raw: m.sort, label: "Sort · " + SortLabel(m.sort) }
    ]
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

function TypeLabel(typeFilter as string) as string
    if typeFilter = "movie" then return "Movies"
    if typeFilter = "series" then return "Series"
    return "All"
end function

function SortLabel(sort as string) as string
    if sort = "az" then return "A-Z"
    if sort = "za" then return "Z-A"
    if sort = "watched" then return "Watched"
    return "Recently added"
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

    ' Hang the dropdown under the activating chip (260px tiles, 12px gap), like
    ' DiscoverScreen does, so the menu x walks with the chip index.
    m.menuGroup.translation = [m.chipsX + chip * m.chipPitch, 300]

    m.menuGroup.visible = true
    m.menu.jumpToRowItem = [CurrentOptionIndex(), 0]
    m.menu.SetFocus(true)
end sub

function OptionsFor(chip as integer) as object
    options = []
    if chip = 0
        options = [
            { raw: "all", label: "All" }
            { raw: "movie", label: "Movies" }
            { raw: "series", label: "Series" }
        ]
    else if chip = 1
        options = [
            { raw: "recent", label: "Recently added" }
            { raw: "az", label: "A-Z" }
            { raw: "za", label: "Z-A" }
            { raw: "watched", label: "Watched" }
        ]
    end if
    return options
end function

function CurrentOptionIndex() as integer
    for i = 0 to m.menuOptions.Count() - 1
        if m.menuOptions[i].raw = m.typeFilter or m.menuOptions[i].raw = m.sort then return i
    end for
    return 0
end function

' OK inside the dropdown commits the highlighted option, then re-slices the
' grid. The menu lays one option per row, so rowItemSelected is [optionRow, 0].
' Re-picking the current value just closes the menu. A fresh slice (filter or
' sort) always rebuilds from the store, so the new ordering cannot be stale.
sub onMenuSelected()
    data = m.menu.rowItemSelected
    if data = invalid or data.Count() < 2 then return
    index = data[0]
    if index < 0 or index >= m.menuOptions.Count() then return
    option = m.menuOptions[index]

    if m.activeChip = 0
        if option.raw = m.typeFilter then CloseMenu() : return
        m.typeFilter = option.raw
    else if m.activeChip = 1
        if option.raw = m.sort then CloseMenu() : return
        m.sort = option.raw
    end if

    CloseMenu()
    BuildChips()
    BuildRows()
end sub

' Dismiss the dropdown and hand focus back to the chips. Called on Back (no
' change) and after a pick (the pick already committed above).
sub CloseMenu()
    m.menuGroup.visible = false
    m.chips.SetFocus(true)
end sub

' --- grid -------------------------------------------------------------------

' Re-slice the saved library through LibraryStore with the current type filter
' and sort, then lay each item out as a poster row of m.chunk tiles. The grid is
' rebuilt on entry, on RefreshRows, and on every filter/sort pick; the selection
' always reflects the active filter. An empty view shows the hint on the status
' line and entry parks focus on the chips (the grid has nothing to focus; the
' hint explains why and how to fix it).
sub BuildRows()
    if m.stores = invalid or m.stores.library = invalid then
        m.items = []
    else
        m.items = m.stores.library.LibraryView(m.typeFilter, m.sort)
    end if

    content = CreateObject("roSGNode", "ContentNode")
    for r = 0 to (m.items.Count() - 1) / m.chunk
        row = content.CreateChild("ContentNode")
        for c = 0 to m.chunk - 1
            flat = r * m.chunk + c
            if flat >= m.items.Count() then exit for
            item = m.items[flat]
            tile = row.CreateChild("TileContent")
            name = item.name
            if name = invalid then name = ""
            tile.title = name
            poster = item.poster
            if poster <> invalid and poster <> "" then tile.hdPosterUrl = poster
            TileWatchFields(tile, item.metaId, item.metaType)
        end for
    end for
    m.grid.content = content
    if m.items.Count() > 0
        m.grid.numRows = (m.items.Count() + m.chunk - 1) / m.chunk
    else
        m.grid.numRows = 0
    end if

    m.header.text = LibraryLabel()
    if m.items.Count() = 0
        m.status.text = "Your library is empty. Add movies and series from a title's details screen."
    else
        m.status.text = ""
    end if
end sub

' Paint the watched overlays on one saved-library tile: the continue-watching
' bar from ProgressFraction, and the coarse glyph by WatchedGlyph (eye for a
' finished movie/series, clock for an in-progress one).
sub TileWatchFields(tile as object, metaId as dynamic, metaType as dynamic)
    if m.stores = invalid or m.stores.library = invalid then return
    fraction = m.stores.library.ProgressFraction(metaId)
    tile.progress = 0
    if fraction <> invalid then tile.progress = fraction
    glyph = m.stores.library.WatchedGlyph(metaId, metaType)
    tile.watchedGlyph = glyph
end sub

' The human summary of the current view, e.g. "All · Recently added".
function LibraryLabel() as string
    return TypeLabel(m.typeFilter) + " · " + SortLabel(m.sort)
end function

' --- selection --------------------------------------------------------------

' A result opens DetailsScreen through the same one-action channel Home, Search
' and Discover use: the slim saved record + the Cinemeta address. The full hero
' is top-filled by DetailsScreen.MaybeRefreshMeta exactly as a Search/Discover
' slim tile would be, so a record missing its original addon still opens.
sub onResultSelected()
    data = m.grid.rowItemSelected
    if data = invalid or data.Count() < 2 then return
    flat = data[0] * m.chunk + data[1]
    if flat < 0 or flat >= m.items.Count() then return
    item = m.items[flat]
    m.top.pushRequest = {
        screen: "detailsScreen"
        params: {
            addonAddress: m.cinemetaAddress
            meta: {
                id: item.metaId
                type: item.metaType
                name: item.name
                poster: item.poster
            }
        }
    }
end sub

' Where the meta for a saved tile comes from. The library records no addon
' origin, so the Cinemeta built-in (the meta authority) is the default,
' mirroring Home's MetaAddress.
function CinemetaAddress() as string
    if m.stores = invalid or m.stores.addons = invalid then return ""
    addon = m.stores.addons.Get("com.linvo.cinemeta")
    if addon = invalid then return ""
    return addon.address
end function

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
