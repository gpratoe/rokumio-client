' HomeCatalogRow — a catalog picker row with a color-coded visibility state.
' Kept separate from PrefRow so this catalog-specific color treatment does not
' change the look of unrelated Settings or Add-ons rows.

sub init()
    m.face = m.top.FindNode("rowFace")
    m.title = m.top.FindNode("rowTitle")
    m.visibility = m.top.FindNode("rowVisibility")
    m.visibleOnHome = true

    m.top.ObserveField("itemContent", "onItemContentChanged")
    m.top.ObserveField("itemHasFocus", "onFocusChanged")
    m.top.ObserveField("rowHasFocus", "onFocusChanged")
    UpdateLook()
end sub

sub onItemContentChanged()
    content = m.top.itemContent
    if content = invalid then return
    content.ObserveField("title", "onContentChanged")
    content.ObserveField("description", "onContentChanged")
    content.ObserveField("visibleOnHome", "onContentChanged")
    ApplyContent()
end sub

sub onContentChanged()
    ApplyContent()
end sub

sub ApplyContent()
    content = m.top.itemContent
    if content = invalid then return
    m.title.text = content.title
    m.visibility.text = content.description
    m.visibleOnHome = content.visibleOnHome
    UpdateLook()
end sub

sub onFocusChanged()
    UpdateLook()
end sub

sub UpdateLook()
    palette = Theme()
    if m.top.itemHasFocus
        m.face.color = palette.itemFace
    else
        m.face.color = palette.tileFace
    end if

    m.title.color = palette.textPrimary
    if m.visibleOnHome
        m.visibility.color = palette.accent
    else
        m.visibility.color = palette.accentWarm
    end if
    if m.top.rowHasFocus then m.top.opacity = 1.0 else m.top.opacity = 0.55
end sub
