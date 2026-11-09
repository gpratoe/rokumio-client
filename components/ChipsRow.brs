' ChipsRow — one horizontal row of focusable ChipTiles as a standalone
' Group (the nav-rail model, not a RowList). Tiles are plain children; the
' row moves focus with field writes and SetFocus, and Left/Right/OK are
' answered here so every chips row navigates the same way without each
' screen re-plumbing the keys. Focus moves without RowList binding
' overhead, which is what keeps the tiles lighting up instantly.

sub init()
    m.focusedIndex = -1
end sub

' Rebuild the row from [{title, icon, width, active}] entries. Tile widths
' come from the entry when given, otherwise they are estimated from the
' label (icon-only chips stay square). The focused chip survives the
' rebuild; if the row held actual focus before it, the new tile at that
' index takes it back, so a rebuild triggered while the row is live does
' not drop the user's cursor. The screen decides when focus starts: SetChips
' itself only repaints.
sub SetChips(entries as object)
    count = entries.Count()
    if m.focusedIndex >= count then m.focusedIndex = count - 1
    held = HoldingFocus()

    while m.top.GetChildCount() > 0
        m.top.RemoveChildIndex(0)
    end while

    x = 0
    for each entry in entries
        tile = m.top.CreateChild("ChipTile")
        tile.focusable = true
        tile.translation = [x, 0]
        width = ChipWidth(entry)
        tile.callFunc("SetChip", ChipTitle(entry), ChipIcon(entry), width, ChipActive(entry))
        x = x + width + 16
    end for

    if held
        Paint(m.focusedIndex)
        if m.focusedIndex >= 0 then m.top.GetChild(m.focusedIndex).SetFocus(true)
    else
        for i = 0 to m.top.GetChildCount() - 1
            m.top.GetChild(i).focused = false
            m.top.GetChild(i).rowFocused = false
        end for
    end if
end sub

' Put the focus ring on chip `index`; an index out of range keeps the
' remembered one (or the first chip) so the screen can hand the row focus
' with FocusChip(-1) and land wherever it left off.
sub FocusChip(index as integer)
    if m.top.GetChildCount() = 0 then return
    if index < 0 or index >= m.top.GetChildCount() then index = m.focusedIndex
    if index < 0 or index >= m.top.GetChildCount() then index = 0
    Paint(index)
    m.top.GetChild(index).SetFocus(true)
end sub

' Drop the ring: the screen is handing focus elsewhere. The remembered
' index survives so a later FocusChip(-1) lands back on this chip.
sub Blur()
    for i = 0 to m.top.GetChildCount() - 1
        m.top.GetChild(i).focused = false
        m.top.GetChild(i).rowFocused = false
    end for
end sub

function Selected() as integer
    return m.focusedIndex
end function

' True when the focused tile also holds actual device focus — the screen's
' signal that Down should leave the row.
function HoldingFocus() as boolean
    if m.focusedIndex < 0 or m.focusedIndex >= m.top.GetChildCount() then return false
    return m.top.GetChild(m.focusedIndex).HasFocus()
end function

sub Paint(index as integer)
    if m.focusedIndex >= 0 and m.focusedIndex < m.top.GetChildCount()
        m.top.GetChild(m.focusedIndex).focused = false
    end if
    m.focusedIndex = index
    for i = 0 to m.top.GetChildCount() - 1
        m.top.GetChild(i).rowFocused = true
    end for
    m.top.GetChild(index).focused = true
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if m.top.GetChildCount() = 0 then return false
    if key = "left"
        return Move(-1)
    else if key = "right"
        return Move(1)
    else if key = "OK"
        return SelectFocused()
    end if
    return false
end function

function Move(delta as integer) as boolean
    if m.focusedIndex < 0 then return false
    nextIndex = m.focusedIndex + delta
    if nextIndex < 0 or nextIndex >= m.top.GetChildCount() then return true
    Paint(nextIndex)
    m.top.GetChild(nextIndex).SetFocus(true)
    return true
end function

function SelectFocused() as boolean
    if m.focusedIndex < 0 or m.focusedIndex >= m.top.GetChildCount() then return false
    m.top.selection = m.focusedIndex
    return true
end function

function ChipTitle(entry as object) as string
    if entry.title <> invalid then return entry.title
    return ""
end function

function ChipIcon(entry as object) as string
    if entry.icon <> invalid then return entry.icon
    return ""
end function

function ChipActive(entry as object) as boolean
    return entry.active = true
end function

' A chip's width: the icon area plus the measured label. Icon-only chips
' stay square; an entry the screen sized itself with wins.
function ChipWidth(entry as object) as integer
    if entry.width <> invalid and entry.width > 0 then return entry.width
    title = ChipTitle(entry)
    if title = "" then return 80
    return 130 + title.Len() * 19
end function
