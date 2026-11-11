' FilterBar — see FilterBar.xml for the interface and ownership split. The
' chips row and the dropdown are rebuilt from {raw,label} entries the screen
' hands over; the active chip is remembered so SetChips can preserve focus and
' ShowMenu hangs under the right chip. All geometry lives here so it cannot
' drift between the two screens that embed this component.
sub init()
    m.chips = m.top.FindNode("chips")
    m.menuGroup = m.top.FindNode("menuGroup")
    m.menuBackdrop = m.top.FindNode("menuBackdrop")
    m.menuList = m.top.FindNode("menuList")
    m.menuMore = m.top.FindNode("menuMore")

    t = Theme()
    m.menuBackdrop.color = t.tileFace
    if m.menuMore <> invalid then m.menuMore.blendColor = t.textSecondary

    m.chips.ObserveField("selection", "onChipPressed")

    m.top.focusable = true
    m.entries = []
    m.activeChip = 0
    m.menuOptions = []
    m.menuFocusIndex = 0
    m.menuScrollOffset = 0
    m.menuVisibleCount = 0
end sub

function ChipItemWidth() as integer
    w = m.top.chipItemWidth
    if w = invalid or w <= 0 then w = 260
    return w
end function

function ChipItemHeight() as integer
    h = m.top.chipItemHeight
    if h = invalid or h <= 0 then h = 72
    return h
end function

function MenuItemHeight() as integer
    h = m.top.menuItemHeight
    if h = invalid or h <= 0 then h = 56
    return h
end function

function ChipPitch() as integer
    return ChipItemWidth() + 16
end function

function MenuY() as integer
    return ChipItemHeight() + 8
end function

sub SetChipsRowFocusable(focusable as boolean)
    if m.chips = invalid then return
    m.chips.keysEnabled = focusable
    for i = 0 to m.chips.GetChildCount() - 1
        child = m.chips.GetChild(i)
        if child <> invalid then child.focusable = focusable
    end for
end sub

' Rebuild the chip row from {raw,label} entries. Chips keep a fixed width so
' the dropdown keeps hanging exactly under the chip that opened it. Focus is
' untouched — the screen decides where focus lands.
sub SetChips(entries as object)
    m.entries = entries
    if m.activeChip >= entries.Count() then m.activeChip = entries.Count() - 1

    w = ChipItemWidth()
    h = ChipItemHeight()
    chips = []
    for each entry in entries
        chips.Push({ title: entry.label, width: w, height: h })
    end for
    m.chips.callFunc("SetChips", chips)
end sub

' OK on a chip: publish the activated chip; the screen answers with ShowMenu.
sub onChipPressed()
    if m.menuGroup <> invalid and m.menuGroup.visible then return
    chip = m.chips.selection
    if chip < 0 or chip >= m.entries.Count() then return
    m.activeChip = chip
    m.top.chipActivated = chip
end sub

' The screen packed the chip's options and the index of the current value; the
' dropdown opens under the activating chip and pre-scrolls so whatever is
' focused is the value OK will commit.
sub ShowMenu(options as object, currentIndex as integer)
    if options = invalid then options = []
    m.menuOptions = options
    count = options.Count()
    if count <= 0
        HideMenu()
        return
    end if

    w = ChipItemWidth()
    h = MenuItemHeight()
    shown = count
    if shown > 9 then shown = 9
    menuTopY = m.top.translation[1] + MenuY()
    available = 1080 - menuTopY - 20
    if available < h + 4 then available = h + 4
    maxShown = Int(available / (h + 6))
    if maxShown < 1 then maxShown = 1
    if shown > maxShown then shown = maxShown
    m.menuVisibleCount = shown

    m.menuFocusIndex = currentIndex
    if m.menuFocusIndex < 0 then m.menuFocusIndex = 0
    if m.menuFocusIndex >= count then m.menuFocusIndex = count - 1

    m.menuScrollOffset = m.menuFocusIndex - shown + 1
    if m.menuScrollOffset < 0 then m.menuScrollOffset = 0
    maxOffset = count - shown
    if maxOffset < 0 then maxOffset = 0
    if m.menuScrollOffset > maxOffset then m.menuScrollOffset = maxOffset
    if m.menuFocusIndex < m.menuScrollOffset then m.menuScrollOffset = m.menuFocusIndex
    if m.menuFocusIndex >= m.menuScrollOffset + shown then m.menuScrollOffset = m.menuFocusIndex - shown + 1

    m.menuBackdrop.width = w
    BuildMenuSlots()
    UpdateMenuLayout()

    m.menuGroup.translation = [m.activeChip * ChipPitch(), MenuY()]
    m.menuGroup.visible = true
    SetChipsRowFocusable(false)
    m.top.focusable = true
    m.top.SetFocus(true)
    m.chips.callFunc("Blur")
end sub

sub BuildMenuSlots()
    while m.menuList.GetChildCount() > 0
        m.menuList.RemoveChildIndex(0)
    end while
    w = ChipItemWidth()
    h = MenuItemHeight()
    for i = 0 to m.menuVisibleCount - 1
        tile = m.menuList.CreateChild("ChipTile")
        tile.focusable = false
        tile.translation = [0, i * (h + 6)]
        tile.flat = true
        tile.callFunc("SetChip", "", "", w, false, h)
        tile.rowFocused = true
    end for
end sub

sub UpdateMenuLayout()
    w = ChipItemWidth()
    h = MenuItemHeight()
    shown = m.menuVisibleCount
    count = m.menuOptions.Count()
    hasMore = (m.menuScrollOffset + shown) < count
    extra = 0
    if hasMore then extra = 22
    m.menuBackdrop.height = shown * h + (shown - 1) * 6 + 4 + extra
    if m.menuMore <> invalid
        m.menuMore.visible = hasMore
        if hasMore
            m.menuMore.translation = [Int((w - 24) / 2), shown * h + (shown - 1) * 6 + 2]
        end if
    end if
    RenderMenu()
end sub

sub RenderMenu()
    w = ChipItemWidth()
    h = MenuItemHeight()
    count = m.menuOptions.Count()
    for i = 0 to m.menuVisibleCount - 1
        tile = m.menuList.GetChild(i)
        if tile = invalid then exit for
        optionIndex = m.menuScrollOffset + i
        if optionIndex >= 0 and optionIndex < count
            option = m.menuOptions[optionIndex]
            label = ""
            if option <> invalid and option.label <> invalid then label = option.label
            tile.flat = true
            tile.callFunc("SetChip", label, "", w, false, h)
            tile.visible = true
            tile.rowFocused = true
            tile.focused = (optionIndex = m.menuFocusIndex)
        else
            tile.visible = false
            tile.focused = false
        end if
    end for
end sub

sub MoveMenuFocus(delta as integer)
    count = m.menuOptions.Count()
    if count <= 0 then return
    nextIndex = m.menuFocusIndex + delta
    if nextIndex < 0 then nextIndex = 0
    if nextIndex >= count then nextIndex = count - 1
    if nextIndex = m.menuFocusIndex then return
    m.menuFocusIndex = nextIndex
    if m.menuFocusIndex < m.menuScrollOffset
        m.menuScrollOffset = m.menuFocusIndex
    else if m.menuFocusIndex >= m.menuScrollOffset + m.menuVisibleCount
        m.menuScrollOffset = m.menuFocusIndex - m.menuVisibleCount + 1
    end if
    UpdateMenuLayout()
end sub

' Dismiss the dropdown and hand focus back to the chips.
sub HideMenu()
    m.menuGroup.visible = false
    m.menuOptions = []
    while m.menuList <> invalid and m.menuList.GetChildCount() > 0
        m.menuList.RemoveChildIndex(0)
    end while
    SetChipsRowFocusable(true)
    m.chips.callFunc("FocusChip", m.activeChip)
end sub

sub FocusChips()
    SetChipsRowFocusable(true)
    m.chips.callFunc("FocusChip", m.activeChip)
end sub

sub BlurChips()
    m.chips.callFunc("Blur")
end sub

function FocusIsOnChips() as boolean
    return m.chips.callFunc("HoldingFocus")
end function

function IsMenuOpen() as boolean
    return m.menuGroup.visible
end function

' Menu open: Back/options dismisses (nothing changes). Up/Down move focus in
' the manual list; OK picks; Left/Right are consumed.
function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    if m.menuGroup.visible
        if key = "back" or key = "options"
            HideMenu()
            return true
        else if key = "up"
            MoveMenuFocus(-1)
            return true
        else if key = "down"
            MoveMenuFocus(1)
            return true
        else if key = "OK"
            if m.menuOptions <> invalid and m.menuFocusIndex >= 0 and m.menuFocusIndex < m.menuOptions.Count()
                pick = { chip: m.activeChip, index: m.menuFocusIndex }
                HideMenu()
                m.top.optionPicked = pick
            end if
            return true
        else if key = "left" or key = "right"
            return true
        end if
        return false
    end if
    return false
end function
