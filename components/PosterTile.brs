' PosterTile — custom list-item component used by the Home focus spike.
'
' MarkupGrid/RowList feed each item its ContentNode through the interface field
' `itemContent` and drive focus through `itemHasFocus`/`rowHasFocus` (they never
' touch `content` or `focused`). The content is a "title" string of the form
' "R{row}C{col}:{name}", enough to read the visible tile text. No assets: the
' "poster" is a Rectangle.

sub init()
    m.tileBg = m.top.FindNode("tileBg")
    m.tileBorder = m.top.FindNode("tileBorder")

    m.label = CreateObject("roSGNode", "Label")
    m.label.width = 136
    m.label.height = 40
    m.label.font = "font:SmallSystemFont"
    m.label.color = "0x8FA399FF"
    m.label.horizAlign = "center"
    m.label.vertAlign = "center"
    m.label.truncate = "none"
    m.label.translation = [7, 85]
    m.top.AppendChild(m.label)

    m.top.ObserveField("itemContent", "onItemContentChanged")
    m.top.ObserveField("itemHasFocus", "onItemHasFocusChanged")
    m.top.ObserveField("rowHasFocus", "onRowHasFocusChanged")
end sub

' Focus must read as "this tile is selected" from the couch: a thick mint frame,
' a brightened face, a bright label and a slight scale pop. Unfocused tiles stay
' dark and flat so the active one owns the row.
sub onItemHasFocusChanged()
    if m.top.itemHasFocus
        m.tileBorder.color = "0x5BEF95FF"
        m.tileBg.color = "0x18231CFF"
        m.label.color = "0xE9F2ECFF"
        m.top.scale = [1.1, 1.1]
    else
        m.tileBorder.color = "0x2BD67500"
        m.tileBg.color = "0x0B110DFF"
        m.label.color = "0x8FA399FF"
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
    m.label.text = TileNameFor(m.top.itemContent.title)
end sub

' The human-readable name is the part after "R{r}C{c}:".
function TileNameFor(title as string) as string
    if title = invalid then return ""
    parts = title.Split(":")
    if parts.Count() < 2 then return ""
    return parts[1]
end function