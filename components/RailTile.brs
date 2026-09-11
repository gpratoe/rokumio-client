' RailTile — square icon tile for the Home left rail. Same field plumbing as
' every tile: RowList feeds seed the ContentNode through itemContent and drive
' focus through itemHasFocus / rowHasFocus. The glyph is read from
' itemContent.title.

sub init()
    m.border = m.top.FindNode("railBorder")
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
        m.top.scale = [1.08, 1.08]
        m.glyph.blendColor = "0x2BD675FF"
    else
        m.glyph.blendColor = "0x8FA399FF"
        m.top.scale = [1.0, 1.0]
    end if
    if m.top.rowHasFocus then m.top.opacity = 1.0 else m.top.opacity = 0.30
end sub

sub onItemContentChanged()
    if m.top.itemContent = invalid then return
    m.glyph.uri = m.top.itemContent.title
    UpdateLook()
end sub

sub onItemHasFocusChanged()
    UpdateLook()
end sub

sub onRowHasFocusChanged()
    UpdateLook()
end sub
