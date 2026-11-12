' PrefRow — wide focusable row for the Settings list. Same field plumbing as
' every tile: RowList feeds the ContentNode through itemContent and drives focus
' through itemHasFocus / rowHasFocus. The left/bold title and the right/muted
' value come from itemContent.title / itemContent.description.
'
' The content node's OWN fields are watched too, because a screen that changes
' a setting writes the new value into the row's node rather than rebuilding
' the list — rebuilding it would reset the list's focus to the first row, and
' a setting that changes is not a reason to move the cursor.

sub init()
    m.face = m.top.FindNode("rowFace")
    m.title = m.top.FindNode("rowTitle")
    m.value = m.top.FindNode("rowValue")

    t = Theme()
    m.title.color = t.textPrimary
    m.value.color = t.textSecondary

    m.top.ObserveField("itemContent", "onItemContentChanged")
    m.top.ObserveField("itemHasFocus", "onItemHasFocusChanged")
    m.top.ObserveField("rowHasFocus", "onRowHasFocusChanged")
end sub

' Every inbound field change re-applies the whole look from the tile's current
' field values (see StreamTile.UpdateLook: RowList recycles items, so the look
' must be rebuilt on itemContent changes too, or a recycled tile carries stale
' dimming into a fresh row).
sub UpdateLook()
    t = Theme()
    if m.top.itemHasFocus
        m.face.color = t.textPrimary
        m.title.color = t.screenBg
        m.value.color = t.screenBg
    else
        m.face.color = t.tileFace
        m.title.color = t.textPrimary
        m.value.color = t.textSecondary
    end if
    if m.top.rowHasFocus then m.top.opacity = 1.0 else m.top.opacity = 0.55
end sub

sub onItemContentChanged()
    content = m.top.itemContent
    if content = invalid then return
    ' Watch the node's own fields, so a screen can write a new value into it
    ' and have the row repaint without the list being rebuilt. ObserveField
    ' watches a field of the node it is called on, and the callback runs in
    ' this component's scope.
    content.ObserveField("title", "onContentFieldChanged")
    content.ObserveField("description", "onContentFieldChanged")
    ApplyContent()
end sub

' A field of the content node changed: the title or the value is now
' different from what this row is showing.
sub onContentFieldChanged()
    ApplyContent()
end sub

sub ApplyContent()
    content = m.top.itemContent
    if content = invalid then return
    m.title.text = content.title
    value = content.description
    if value = invalid then value = ""
    m.value.text = value
    UpdateLook()
end sub

sub onItemHasFocusChanged()
    UpdateLook()
end sub

sub onRowHasFocusChanged()
    UpdateLook()
end sub
