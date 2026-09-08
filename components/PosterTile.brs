' PosterTile — custom list-item component used by the Home catalog rows.
'
' MarkupGrid/RowList feed each item its ContentNode through the interface field
' `itemContent` and drive focus through `itemHasFocus`/`rowHasFocus` (they never
' touch `content` or `focused`). The artwork comes from the item's
' hdPosterUrl (mapped from the addon meta's poster); tiles with no image show
' the plain background. No tile text: the poster art is the label.

sub init()
    m.poster = m.top.FindNode("poster")
    m.tileBg = m.top.FindNode("tileBg")
    m.tileBorder = m.top.FindNode("tileBorder")

    m.top.ObserveField("itemContent", "onItemContentChanged")
    m.top.ObserveField("itemHasFocus", "onItemHasFocusChanged")
    m.top.ObserveField("rowHasFocus", "onRowHasFocusChanged")
end sub

' Focus must read as "this tile is selected" from the couch: a thick mint frame,
' a brightened face and a slight scale pop. Unfocused tiles stay dark and flat so
' the active one owns the row.
sub onItemHasFocusChanged()
    if m.top.itemHasFocus
        m.tileBorder.color = "0x5BEF95FF"
        m.tileBg.color = "0x18231CFF"
        m.top.scale = [1.1, 1.1]
    else
        m.tileBorder.color = "0x2BD67500"
        m.tileBg.color = "0x0B110DFF"
        m.top.scale = [1.0, 1.0]
    end if
end sub

' A whole row dims when its list row loses focus (user moved to another row),
' reinforcing which row the "selected" indicator sits in.
sub onRowHasFocusChanged()
    if m.top.rowHasFocus
        m.top.opacity = 1.0
    else
        m.top.opacity = 0.55
    end if
end sub

sub onItemContentChanged()
    if m.top.itemContent = invalid then return
    m.poster.uri = m.top.itemContent.hdPosterUrl
end sub