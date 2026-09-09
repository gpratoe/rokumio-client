' RailTile — square icon tile for the Home left rail. Same field plumbing as
' every tile: RowList feeds seed the ContentNode through itemContent and drive
' focus through itemHasFocus / rowHasFocus. The glyph is read from
' itemContent.title.

sub init()
    m.border = m.top.FindNode("railBorder")
    m.face = m.top.FindNode("railFace")
    m.glyph = m.top.FindNode("railGlyph")

    m.top.ObserveField("itemContent", "onItemContentChanged")
    m.top.ObserveField("itemHasFocus", "onItemHasFocusChanged")
    m.top.ObserveField("rowHasFocus", "onRowHasFocusChanged")
end sub

' Every inbound field change re-applies the whole look from the tile's current
' field values (see StreamTile.UpdateLook: RowList recycles items, so the look
' must be rebuilt on itemContent changes too, or a recycled tile carries stale
' dimming into a fresh row).
sub UpdateLook()
    if m.top.itemHasFocus
        m.border.color = "0x5BEF95FF"
        m.face.color = "0x233329FF"
        m.glyph.color = "0xE9F2ECFF"
        m.top.scale = [1.08, 1.08]
    else
        m.border.color = "0x2BD67500"
        m.face.color = "0x0B110DFF"
        m.glyph.color = "0x8FA399FF"
        m.top.scale = [1.0, 1.0]
    end if
    if m.top.rowHasFocus then m.top.opacity = 1.0 else m.top.opacity = 0.55
end sub

sub onItemContentChanged()
    if m.top.itemContent = invalid then return
    m.glyph.text = m.top.itemContent.title
    UpdateLook()
end sub

sub onItemHasFocusChanged()
    UpdateLook()
end sub

sub onRowHasFocusChanged()
    UpdateLook()
end sub