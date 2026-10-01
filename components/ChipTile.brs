' ChipTile — focusable label tile for the single-row RowLists (season chips,
' movie action buttons). Same field plumbing as PosterTile: RowList feeds the
' ContentNode through itemContent and drives focus through itemHasFocus /
' rowHasFocus. Text is read from itemContent.title.

sub init()
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
        m.face.color = t.itemFace
        m.text.color = t.textPrimary
    else
        m.face.color = t.tileFace
        m.text.color = t.textSecondary
    end if
    if m.top.rowHasFocus then m.top.opacity = 1.0 else m.top.opacity = 0.55
end sub

sub onItemContentChanged()
    content = m.top.itemContent
    if content = invalid then return
    m.text.text = content.title

    if content.width <> invalid
        m.face.width = content.width
        m.text.width = content.width - 8
    end if

    if content.chipHeight <> invalid
        m.face.height = content.height
        m.text.height = content.height - 8
    end if
    UpdateLook()
end sub

sub onItemHasFocusChanged()
    UpdateLook()
end sub

sub onRowHasFocusChanged()
    UpdateLook()
end sub
