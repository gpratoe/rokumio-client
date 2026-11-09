' ChipTile — focusable icon+label tile. Two drivers share one tile and one
' paint: standalone rows (ChipsRow writes fields and calls SetChip) and
' RowLists (the FilterBar dropdown feeds itemContent — the same fields as
' PosterTile). Focus lights the tile white either way; `active` paints the
' selected chip in the accent so a row and the list under it can agree
' about which one is showing even when focus is elsewhere.

sub init()
    m.iconBg = m.top.FindNode("iconBg")
    m.icon = m.top.FindNode("chipIcon")
    m.text = m.top.FindNode("chipText")
    m.active = false
    m.tileWidth = 0
    t = Theme()
    m.text.color = t.textPrimary
    m.top.ObserveField("itemContent", "onItemContentChanged")
    m.top.ObserveField("focused", "onStateChanged")
    m.top.ObserveField("rowFocused", "onStateChanged")
    m.top.ObserveField("chipWidth", "onWidthChanged")
    m.top.ObserveField("itemHasFocus", "onStateChanged")
    m.top.ObserveField("rowHasFocus", "onStateChanged")
end sub

' Standalone entry point (ChipsRow).
sub SetChip(title as string, iconUri as string, chipWidth as integer, isActive = false as boolean)
    ApplyContent(title, iconUri, isActive, chipWidth)
end sub

sub ApplyContent(title as string, iconUri as string, isActive as boolean, tileWidth as integer)
    hasIcon = iconUri <> ""
    if hasIcon then m.icon.uri = iconUri
    m.text.text = title
    m.active = isActive
    m.tileWidth = tileWidth
    ApplyLayout(hasIcon, title <> "")
    ApplyState()
end sub

sub ApplyLayout(hasIcon as boolean, hasText as boolean)
    m.icon.visible = hasIcon
    m.iconBg.visible = true
    if hasIcon and hasText
        m.iconBg.width = m.tileWidth - 8
        m.text.translation = [88, 20]
        m.text.width = m.tileWidth - 96
        m.text.visible = true
    else if hasIcon
        m.iconBg.width = 72
        m.text.width = 0
        m.text.visible = false
    else
        m.iconBg.width = m.tileWidth - 8
        m.text.translation = [8, 16]
        m.text.width = m.tileWidth - 16
        m.text.visible = true
    end if
end sub

sub ApplyState()
    t = Theme()
    focused = (m.top.focused = true) or (m.top.itemHasFocus = true)
    rowLit = focused or (m.top.rowFocused = true) or (m.top.rowHasFocus = true)
    if focused
        m.iconBg.blendColor = t.textPrimary
        m.icon.blendColor = t.screenBg
        m.text.color = t.screenBg
    else if m.active
        m.iconBg.blendColor = t.accentDim
        m.icon.blendColor = t.textPrimary
        m.text.color = t.accent
    else
        m.iconBg.blendColor = t.tileFace
        m.icon.blendColor = t.textSecondary
        m.text.color = t.textPrimary
    end if
    if rowLit then m.top.opacity = 1.0 else m.top.opacity = 0.55
end sub

sub onStateChanged()
    ApplyState()
end sub

sub onWidthChanged()
    if m.top.chipWidth > 0
        m.tileWidth = m.top.chipWidth
        ApplyLayout(m.icon.visible, m.text.visible and m.text.text <> "")
        ApplyState()
    end if
end sub

' RowList entry point (the FilterBar dropdown): the content node carries
' title / icon / width / active the same way ChipContent defines them.
sub onItemContentChanged()
    content = m.top.itemContent
    if content = invalid then return
    iconUri = ""
    if content.HasField("icon") and content.icon <> invalid then iconUri = content.icon
    title = ""
    if content.title <> invalid then title = content.title
    active = content.HasField("active") and content.active = true
    if content.width <> invalid
        ApplyContent(title, iconUri, active, content.width)
    else
        ApplyContent(title, iconUri, active, m.tileWidth)
    end if
end sub
