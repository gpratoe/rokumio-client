' StreamTile — wide stream card for StreamsScreen's list.
'
' RowList feeds each item its ContentNode through `itemContent` and drives focus
' through `itemHasFocus`/`rowHasFocus`. The primary line is the stream name
' (e.g. "4k DV | HDR10+"); the lines below are the stream title split
' at its embedded line feeds (release / file / peers-size / languages). The
' description field carries the whole multi-line title, split right here into
' however many rows the card fits — never pre-mapped onto fixed fields.

sub init()
    m.border = m.top.FindNode("tileBorder")
    m.face = m.top.FindNode("tileFace")
    m.title = m.top.FindNode("tileTitle")
    m.lines = []
    for i = 1 to 5
        m.lines.Push(m.top.FindNode("tileLine" + i.ToStr()))
    end for

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
    if m.top.itemHasFocus
        m.border.color = "0x5BEF95FF"
        m.face.color = "0x233329FF"
    else
        m.border.color = "0x2BD67500"
        m.face.color = "0x0B110DFF"
    end if
    if m.top.rowHasFocus then m.top.opacity = 1.0 else m.top.opacity = 0.55
end sub

sub onItemContentChanged()
    if m.top.itemContent = invalid then return
    m.title.text = m.top.itemContent.title
    description = m.top.itemContent.description
    if description = invalid then description = ""
    pieces = description.Split(chr(10))
    for i = 0 to m.lines.Count() - 1
        text = ""
        if pieces <> invalid and i < pieces.Count() then text = pieces[i]
        m.lines[i].text = text
    end for
    UpdateLook()
end sub

sub onItemHasFocusChanged()
    UpdateLook()
end sub

sub onRowHasFocusChanged()
    UpdateLook()
end sub