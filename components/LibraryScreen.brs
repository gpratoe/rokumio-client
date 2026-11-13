' LibraryScreen — the saved library for the current session, in the same
' hero-led browse style as Discover. Two chips drive the grid: a content-type
' filter (All/Movies/Series/Channels) and a sort order (Recently added/A-Z/
' Z-A/Watched). OK on a chip opens a dropdown menu of that chip's options —
' Up/Down move, OK picks, Back dismisses without changing anything. The hero
' reflects the focused saved item; saved records are slim (name/poster/type),
' so the shared hero pipeline degrades gracefully — poster backdrop + title,
' with logo/description/rating/genres hidden when absent.
'
' Everything is served straight from LibraryStore, no tasks, nothing to load.
' The grid is re-sliced whenever a filter or sort changes and on every
' OnEnter/RefreshRows, so a save made on another screen (or a background
' library sync landing while this screen is top) shows up on the next build.

sub init()
    m.status = m.top.FindNode("libraryStatus")
    m.empty = m.top.FindNode("libraryEmpty")
    m.filterBar = m.top.FindNode("filterBar")
    m.grid = m.top.FindNode("libraryGrid")

    m.heroPoster = m.top.FindNode("heroPoster")
    m.heroScrim = m.top.FindNode("heroScrim")
    m.heroLogo = m.top.FindNode("heroLogo")
    m.heroTitle = m.top.FindNode("heroTitle")
    m.heroMeta = m.top.FindNode("heroMeta")
    m.heroRating = m.top.FindNode("heroRating")
    m.heroRatingText = m.top.FindNode("heroRatingText")
    m.heroGenres = m.top.FindNode("heroGenres")
    m.heroDescription = m.top.FindNode("heroDescription")
    m.heroTitleGrace = m.top.FindNode("heroTitleGrace")
    m.heroPosterFadeAnim = m.top.FindNode("heroPosterFadeAnim")
    m.filtersHint = m.top.FindNode("filtersHint")
    m.filtersHintFade = m.top.FindNode("filtersHintFade")

    HeroInitState()

    t = Theme()
    m.status.color = t.accent
    m.empty.color = t.textSecondary
    m.heroScrim.color = t.scrim
    m.heroTitle.color = t.textPrimary
    m.heroMeta.color = t.textSecondary
    m.heroRatingText.color = t.accentWarm
    m.heroGenres.color = t.textSecondary
    m.heroDescription.color = t.textPrimary
    m.grid.focusBitmapBlendColor = t.accentFocus

    m.filterBar.ObserveField("chipActivated", "onChipActivated")
    m.filterBar.ObserveField("optionPicked", "onOptionPicked")
    m.grid.ObserveField("rowItemSelected", "onResultSelected")
    m.grid.ObserveField("rowItemFocused", "onGridItemFocused")
    m.heroPoster.ObserveField("loadStatus", "HeroOnPosterStatus")
    m.heroLogo.ObserveField("loadStatus", "HeroOnLogoStatus")
    m.heroTitleGrace.ObserveField("fire", "HeroOnTitleGraceFire")

    m.chunk = 6
    ' Grid budget matches Discover: 6 standard poster tiles per row.
    m.rowWidth = 1800
    m.rowGap = 18
    m.typeFilter = "all"
    m.sort = "recent"
    m.items = []
    m.cinemetaAddress = ""
end sub

function OnEnter(params as object) as void
    RefreshTexts()
    if m.stores <> invalid
        addon = m.stores.addons.callFunc("AddonsGet", "com.linvo.cinemeta")
        if addon <> invalid then m.cinemetaAddress = addon.address
    end if

    if m.filterBar.callFunc("IsMenuOpen") then m.filterBar.callFunc("HideMenu")

    ' Re-slice every entry (like Addons/Settings): a save toggle on a Details
    ' screen — or a background sync landing while this screen is under another
    ' one — can change the saved set while we were away.
    SetChips()
    BuildRows()
    if m.items.Count() > 0
        m.grid.SetFocus(true)
        RefreshLibraryHeroFromFocus()
    else
        HeroClear()
        m.filterBar.callFunc("FocusChips")
    end if
    UpdateFiltersHint()
end function

function OnExit() as void
end function

function OnBackPressed() as boolean
    return false
end function

sub BlurFocus()
    if m.heroTitleGrace <> invalid then m.heroTitleGrace.control = "stop"
    if m.heroPosterFadeAnim <> invalid then m.heroPosterFadeAnim.control = "stop"
    if m.filtersHint <> invalid then m.filtersHint.visible = false
end sub

' The Scene's poke when a background library sync lands while this screen is
' top. Same rebuild as entry — idempotent; leaving the focus where it is keeps
' an in-flight re-slice from stealing navigation.
function RefreshRows() as void
    gridHadFocus = m.grid.HasFocus()
    BuildRows()
    if m.items.Count() > 0
        if gridHadFocus then RefreshLibraryHeroFromFocus()
    else
        HeroClear()
    end if
    UpdateFiltersHint()
end function

' --- filter chips (data) ----------------------------------------------------

' The chip row itself lives in FilterBar; the screen owns the values
' (m.typeFilter/m.sort) and their labels. Chips show the active selection
' directly (like Discover), rebuilt on every pick.
sub SetChips()
    entries = [
        { raw: m.typeFilter, label: TypeLabel(m.typeFilter) }
        { raw: m.sort, label: SortLabel(m.sort) }
    ]
    m.filterBar.callFunc("SetChips", entries)
end sub

function TypeLabel(typeFilter as string) as string
    if typeFilter = "movie" then return Lang("common", "movies")
    if typeFilter = "series" then return Lang("common", "series")
    if typeFilter = "channel" then return Lang("common", "channels")
    return Lang("common", "all")
end function

function SortLabel(sort as string) as string
    if sort = "az" then return Lang("library", "sortAz")
    if sort = "za" then return Lang("library", "sortZa")
    if sort = "watched" then return Lang("common", "watched")
    return Lang("common", "recentlyAdded")
end function

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
            { raw: "all", label: Lang("common", "all") }
            { raw: "movie", label: Lang("common", "movies") }
            { raw: "series", label: Lang("common", "series") }
            { raw: "channel", label: Lang("common", "channels") }
        ]
    else if chip = 1
        options = [
            { raw: "recent", label: Lang("common", "recentlyAdded") }
            { raw: "az", label: Lang("library", "sortAz") }
            { raw: "za", label: Lang("library", "sortZa") }
            { raw: "watched", label: Lang("common", "watched") }
        ]
    end if
    return options
end function

function CurrentOptionIndex(chip as integer) as integer
    options = OptionsFor(chip)
    for i = 0 to options.Count() - 1
        if chip = 0 and options[i].raw = m.typeFilter then return i
        if chip = 1 and options[i].raw = m.sort then return i
    end for
    return 0
end function

sub onOptionPicked()
    pick = m.filterBar.optionPicked
    if pick = invalid or pick.chip = invalid or pick.index = invalid then return
    chip = pick.chip
    options = OptionsFor(chip)
    index = pick.index
    if index < 0 or index >= options.Count() then return
    option = options[index]

    if chip = 0
        if option.raw = m.typeFilter then m.filterBar.callFunc("HideMenu") : return
        m.typeFilter = option.raw
    else if chip = 1
        if option.raw = m.sort then m.filterBar.callFunc("HideMenu") : return
        m.sort = option.raw
    end if

    m.filterBar.callFunc("HideMenu")
    SetChips()
    BuildRows()
    if m.items.Count() > 0
        RefreshLibraryHeroFromFocus()
    else
        HeroClear()
    end if
    UpdateFiltersHint()
end sub

' --- grid -------------------------------------------------------------------

sub BuildRows()
    if m.stores = invalid then
        m.items = []
    else
        m.items = m.stores.library.callFunc("LibraryLibraryView", m.typeFilter, m.sort)
    end if

    ' Canonical cell size per type so tiles/decode targets stay consistent across screens.
    size = TileCellSize(m.typeFilter)
    m.chunk = TileColumns(m.rowWidth, size[0], m.rowGap)
    if m.chunk < 1 then m.chunk = 1

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
            if item.metaType <> invalid and LCase(item.metaType) = "channel" then tile.watchedGlyph = ""
            TileWatchFields(tile, item.metaId, item.metaType)
        end for
    end for
    m.grid.content = content
    m.grid.itemSize = [m.rowWidth, size[1]]
    m.grid.rowItemSize = [size]
    m.grid.rowHeights = [size[1]]
    if m.items.Count() > 0
        m.grid.numRows = (m.items.Count() + m.chunk - 1) / m.chunk
    else
        m.grid.numRows = 0
    end if

    if m.items.Count() = 0
        m.status.text = ""
        if m.typeFilter = "channel"
            m.empty.text = Lang("library", "emptyChannels")
        else
            m.empty.text = Lang("library", "emptyLibrary")
        end if
        m.empty.visible = true
    else
        m.status.text = ""
        m.empty.text = ""
        m.empty.visible = false
    end if
end sub

sub TileWatchFields(tile as object, metaId as dynamic, metaType as dynamic)
    if m.stores = invalid then return
    fraction = m.stores.library.callFunc("LibraryProgressFraction", metaId)
    tile.progress = 0
    if fraction <> invalid then tile.progress = fraction
    glyph = m.stores.library.callFunc("LibraryWatchedGlyph", metaId, metaType)
    tile.watchedGlyph = glyph
end sub

' --- hero -------------------------------------------------------------------

sub onGridItemFocused()
    data = m.grid.rowItemFocused
    if data = invalid or data.Count() < 2 then return
    UpdateLibraryHero(data)
    UpdateFiltersHint()
end sub

sub RefreshLibraryHeroFromFocus()
    data = m.grid.rowItemFocused
    if data <> invalid and data.Count() >= 2
        flat = data[0] * m.chunk + data[1]
        if flat >= 0 and flat < m.items.Count()
            RenderLibraryHero(m.items[flat])
            return
        end if
    end if
    if m.items.Count() > 0
        RenderLibraryHero(m.items[0])
    else
        HeroClear()
    end if
end sub

sub UpdateLibraryHero(position as object)
    if position = invalid or position.Count() < 2 then return
    flat = position[0] * m.chunk + position[1]
    if flat < 0 or flat >= m.items.Count()
        if m.items.Count() > 0 then RenderLibraryHero(m.items[0])
        return
    end if
    RenderLibraryHero(m.items[flat])
end sub

' Saved items are slim (name/poster/metaType/posterShape); the shared hero
' falls back to the poster as backdrop and to a title-only layout when there
' is no logo/description/rating/genres, so the hero degrades gracefully.
sub RenderLibraryHero(item as object)
    if item = invalid then return
    meta = {
        name: item.name
        title: item.name
        poster: item.poster
        type: item.metaType
    }
    HeroRender(meta)
end sub

' The asterisk-key hint: shown only while grid focus is past the first row
' (Up is consumed by the RowList) and the grid holds focus.
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

' --- selection --------------------------------------------------------------

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

function CinemetaAddress() as string
    if m.stores = invalid then return ""
    addon = m.stores.addons.callFunc("AddonsGet", "com.linvo.cinemeta")
    if addon = invalid then return ""
    return addon.address
end function

' Focus travel between the chips and the results grid. The dropdown's own keys
' are handled inside FilterBar; with the menu closed Down from the chips enters
' the results grid and Up from the grid returns.
function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

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
