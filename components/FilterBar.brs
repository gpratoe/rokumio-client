' FilterBar — see FilterBar.xml for the interface and ownership split. The
' chips row and the dropdown are rebuilt from {raw,label} entries the screen
' hands over; the active chip is remembered so SetChips can preserve focus and
' ShowMenu hangs under the right chip. All geometry lives here so it cannot
' drift between the two screens that embed this component.
sub init()
    m.chips = m.top.FindNode("chips")
    m.menuGroup = m.top.FindNode("menuGroup")
    m.menuBackdrop = m.top.FindNode("menuBackdrop")
    m.menu = m.top.FindNode("menu")

    t = Theme()
    m.menuBackdrop.color = t.dropdownBg
    m.menu.focusBitmapBlendColor = t.accentFocus

    m.chips.ObserveField("selection", "onChipPressed")
    m.menu.ObserveField("rowItemSelected", "onMenuPressed")

    m.entries = []
    m.activeChip = 0
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
    chip = m.chips.selection
    if chip < 0 or chip >= m.entries.Count() then return
    m.activeChip = chip
    m.top.chipActivated = chip
end sub

' The screen packed the chip's options and the index of the current value; the
' dropdown opens under the activating chip and pre-scrolls so whatever is
' focused is the value OK will commit.
sub ShowMenu(options as object, currentIndex as integer)
    w = ChipItemWidth()
    h = MenuItemHeight()
    m.menu.itemSize = [w, h]
    m.menu.rowItemSize = [[w, h]]

    content = CreateObject("roSGNode", "ContentNode")
    for each option in options
        row = content.CreateChild("ContentNode")
        item = row.CreateChild("ChipContent")
        item.title = option.label
        item.width = w
        item.height = h
    end for
    m.menu.content = content

    shown = options.Count()
    if shown > 9 then shown = 9
    m.menu.numRows = shown
    m.menuBackdrop.width = w
    m.menuBackdrop.height = shown * h + (shown - 1) * 6 + 4

    ' Hang the menu under the activating chip, not always the first one.
    m.menuGroup.translation = [m.activeChip * ChipPitch(), MenuY()]

    m.menuGroup.visible = true
    m.menu.jumpToRowItem = [currentIndex, 0]
    m.menu.SetFocus(true)
    ' The dropdown has the focus now; the chips drop their ring so the row
    ' does not look focused while it is not.
    m.chips.callFunc("Blur")
end sub

' OK inside the dropdown: publish {chip, index} so the screen commits its own
' effect (the re-pick-current-value rule lives with the screen, which knows the
' current raw values).
sub onMenuPressed()
    data = m.menu.rowItemSelected
    if data = invalid or data.Count() < 2 then return
    index = data[0]
    if index < 0 then return
    m.top.optionPicked = { chip: m.activeChip, index: index }
end sub

' Dismiss the dropdown and hand focus back to the chips.
sub HideMenu()
    m.menuGroup.visible = false
    m.chips.callFunc("FocusChip", m.activeChip)
end sub

sub FocusChips()
    m.chips.callFunc("FocusChip", m.activeChip)
end sub

function FocusIsOnChips() as boolean
    return m.chips.callFunc("HoldingFocus")
end function

function IsMenuOpen() as boolean
    return m.menuGroup.visible
end function

' Menu open: Back/options dismisses (nothing changes) and the arrow keys are
' kept inside the dropdown instead of leaking to the screen/Scene. With the
' menu closed, keys fall through to the embedding screen.
function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    if m.menuGroup.visible
        if key = "back"
            HideMenu()
            return true
        end if
        if key = "options"
            HideMenu()
            return true
        end if
        if key = "up" or key = "down" or key = "left" or key = "right"
            return true
        end if
        return false
    end if
    return false
end function
