' ChipTile — focusable label tile for the single-row RowLists (season chips,
' movie action buttons). Same field plumbing as PosterTile: RowList feeds the
' ContentNode through itemContent and drives focus through itemHasFocus /
' rowHasFocus. Text is read from itemContent.title.

sub init()
    m.border = m.top.FindNode("chipBorder")
    m.face = m.top.FindNode("chipFace")
    m.text = m.top.FindNode("chipText")

    t = Theme()
    m.text.color = t.textSecondary

    m.top.ObserveField("itemContent", "onItemContentChanged")
    m.top.ObserveField("itemHasFocus", "onItemHasFocusChanged")
    m.top.ObserveField("rowHasFocus", "onRowHasFocusChanged")
end sub

' Every inbound field change re-applies the whole look from the tile's current
' field values. RowList recycles item components for new cells and content
' swaps, and rowHasFocus/itemHasFocus only fire on value *changes* — on a
' recycle nothing may change except itemContent, so unless the look is rebuilt
' there a tile carries stale dimming (opacity 0.55) into a fresh RowList on
' another screen/media.
sub UpdateLook()
    t = Theme()
    if m.top.itemHasFocus
        m.border.color = t.accentFocus
        m.face.color = t.itemFace
        m.text.color = t.textPrimary
        m.top.scale = [1.05, 1.05]
    else
        m.border.color = t.accentClear
        m.face.color = t.tileFace
        m.text.color = t.textSecondary
        m.top.scale = [1.0, 1.0]
    end if
    if m.top.rowHasFocus then m.top.opacity = 1.0 else m.top.opacity = 0.55
end sub

sub onItemContentChanged()
    if m.top.itemContent = invalid then return
    m.text.text = m.top.itemContent.title
    UpdateLook()
end sub

sub onItemHasFocusChanged()
    UpdateLook()
end sub

sub onRowHasFocusChanged()
    UpdateLook()
end sub