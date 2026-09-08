' ChipTile — focusable label tile for the single-row RowLists (season chips,
' movie action buttons). Same field plumbing as PosterTile: RowList feeds the
' ContentNode through itemContent and drives focus through itemHasFocus /
' rowHasFocus. Text is read from itemContent.title.

sub init()
    m.border = m.top.FindNode("chipBorder")
    m.face = m.top.FindNode("chipFace")
    m.text = m.top.FindNode("chipText")

    m.top.ObserveField("itemContent", "onItemContentChanged")
    m.top.ObserveField("itemHasFocus", "onItemHasFocusChanged")
    m.top.ObserveField("rowHasFocus", "onRowHasFocusChanged")
end sub

sub onItemContentChanged()
    if m.top.itemContent = invalid then return
    m.text.text = m.top.itemContent.title
end sub

' Focused chip: mint border, brighter face, bright text and a small scale pop.
sub onItemHasFocusChanged()
    if m.top.itemHasFocus
        m.border.color = "0x5BEF95FF"
        m.face.color = "0x233329FF"
        m.text.color = "0xE9F2ECFF"
        m.top.scale = [1.05, 1.05]
    else
        m.border.color = "0x2BD67500"
        m.face.color = "0x0B110DFF"
        m.text.color = "0x8FA399FF"
        m.top.scale = [1.0, 1.0]
    end if
end sub

sub onRowHasFocusChanged()
    if m.top.rowHasFocus
        m.top.opacity = 1.0
    else
        m.top.opacity = 0.55
    end if
end sub