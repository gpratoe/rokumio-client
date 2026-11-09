' ChipTile — focusable icon+label tile for the Details actions row. It is a
' standalone focusable Group (like the Home rail tiles), not a RowList item:
' focus and selection are handled by DetailsScreen's key handling, the same
' direct model the rail uses.

sub init()
    m.iconBg = m.top.FindNode("iconBg")
    m.icon = m.top.FindNode("chipIcon")
    m.text = m.top.FindNode("chipText")

    t = Theme()
    m.text.color = t.textPrimary
    m.top.ObserveField("focused", "onFocusedChanged")
    m.top.ObserveField("chipWidth", "onWidthChanged")
end sub

sub SetChip(title as string, iconUri as string, chipWidth as integer)
    m.text.text = title
    if iconUri <> ""
        m.icon.uri = iconUri
        m.icon.visible = true
        m.iconBg.visible = true
    else
        m.icon.visible = false
        m.iconBg.visible = false
    end if
    if title <> ""
        m.text.visible = true
        m.text.translation = [88, 20]
        m.text.width = chipWidth - 96
        m.iconBg.width = chipWidth - 8
    else
        m.text.visible = false
        m.iconBg.width = 72
    end if
    m.top.chipWidth = chipWidth
    ApplyState()
end sub

sub ApplyState()
    t = Theme()
    if m.top.focused
        m.iconBg.blendColor = t.textPrimary
        m.icon.blendColor = t.screenBg
        m.text.color = t.screenBg
    else
        m.iconBg.blendColor = t.tileFace
        m.icon.blendColor = t.textSecondary
        m.text.color = t.textPrimary
    end if
end sub

sub onWidthChanged()
    if m.top.chipWidth > 0
        if m.text.visible
            m.iconBg.width = m.top.chipWidth - 8
            m.text.width = m.top.chipWidth - 96
        else if m.icon.visible
            m.iconBg.width = 72
        end if
    end if
end sub

sub onFocusedChanged()
    ApplyState()
end sub