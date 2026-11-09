' ChipTile — focusable icon+label tile for the single-row RowLists (season
' chips, movie action buttons). Same field plumbing as PosterTile: RowList
' feeds the ContentNode through itemContent and drives focus through
' itemHasFocus / rowHasFocus. Text is read from itemContent.title; an
' optional icon from itemContent.icon.

sub init()
    m.iconBg = m.top.FindNode("iconBg")
    m.icon = m.top.FindNode("chipIcon")
    m.text = m.top.FindNode("chipText")

    t = Theme()
    m.text.color = t.textPrimary

    m.top.ObserveField("itemContent", "onItemContentChanged")
    m.top.ObserveField("itemHasFocus", "onItemHasFocusChanged")
    m.top.ObserveField("rowHasFocus", "onRowHasFocusChanged")
end sub

sub UpdateLook()
    t = Theme()
    if m.top.itemHasFocus
        m.iconBg.color = t.textPrimary
        m.icon.blendColor = t.screenBg
        m.text.color = t.screenBg
    else
        m.iconBg.color = t.tileFace
        m.icon.blendColor = t.textSecondary
        m.text.color = t.textPrimary
    end if
    if m.top.rowHasFocus then m.top.opacity = 1.0 else m.top.opacity = 0.55
end sub

sub onItemContentChanged()
    content = m.top.itemContent
    if content = invalid then return
    ApplyContent(content)
    UpdateLook()
end sub

sub ApplyContent(content as object)
    if content.HasField("icon") and content.icon <> invalid and content.icon <> ""
        m.icon.uri = content.icon
        m.icon.visible = true
        m.iconBg.visible = true
    else
        m.icon.visible = false
        m.iconBg.visible = false
    end if

    m.text.text = content.title
    if content.title <> invalid and content.title <> ""
        m.text.visible = true
    else
        m.text.visible = false
    end if

    if content.width <> invalid
        if m.text.visible
            m.iconBg.width = content.width - 8
            m.text.translation = [88, 20]
            m.text.width = content.width - 96
        else if m.icon.visible
            m.iconBg.width = 72
            m.text.width = 0
        else
            m.text.translation = [8, 16]
            m.text.width = content.width - 16
        end if
    end if

    if content.HasField("icon") then content.ObserveField("icon", "onIconChanged")
end sub

sub onIconChanged()
    content = m.top.itemContent
    if content = invalid then return
    ApplyContent(content)
    UpdateLook()
end sub

sub onItemHasFocusChanged()
    UpdateLook()
end sub

sub onRowHasFocusChanged()
    UpdateLook()
end sub