' AddonTile — multi-line add-on card for the Add-ons manager.
' The displayed action comes from itemContent, while AddonsScreen dispatches the
' matching action key. Search results can therefore use the same tile later.

sub init()
    m.face = m.top.FindNode("tileFace")
    m.logoBg = m.top.FindNode("logoBg")
    m.logo = m.top.FindNode("addonLogo")
    m.name = m.top.FindNode("addonName")
    m.version = m.top.FindNode("addonVersion")
    m.scope = m.top.FindNode("addonScope")
    m.description = m.top.FindNode("addonDescription")
    m.action = m.top.FindNode("addonAction")
    m.isPlaceholder = true

    t = Theme()
    m.name.color = t.textPrimary
    m.version.color = t.textSecondary
    m.logo.blendColor = "0xFFFFFFFF"

    m.top.ObserveField("itemContent", "onItemContentChanged")
    m.top.ObserveField("itemHasFocus", "onFocusChanged")
    m.top.ObserveField("rowHasFocus", "onFocusChanged")
    m.logo.ObserveField("loadStatus", "onLogoLoadStatus")
    UpdateLook()
end sub

sub onItemContentChanged()
    content = m.top.itemContent
    if content = invalid then return
    for each field in ["title", "description", "addonLogo", "addonVersion", "addonScope", "actionLabel"]
        content.ObserveField(field, "onContentChanged")
    end for
    ApplyContent()
end sub

sub onContentChanged()
    ApplyContent()
end sub

function IsPlaceholderLogo(uri as dynamic) as boolean
    value = StringOf(uri).Trim()
    if value = "" then return true
    if value = "pkg:/images/puzzle.png" then return true
    if value.InStr("puzzle.png") >= 0 then return true
    return false
end function

sub ApplyContent()
    content = m.top.itemContent
    if content = invalid then return
    m.name.text = content.title
    m.version.text = content.addonVersion
    m.description.text = content.description
    m.scope.text = content.addonScope
    m.action.text = content.actionLabel
    rawLogo = ""
    if content.addonLogo <> invalid then rawLogo = StringOf(content.addonLogo).Trim()
    m.isPlaceholder = IsPlaceholderLogo(rawLogo)
    m.logo.uri = RokuLogoUri(rawLogo)

    UpdateLook()
end sub

sub onLogoLoadStatus()
    status = m.logo.loadStatus
    if status = "failed"
        m.isPlaceholder = true
        UpdateLook()
    else if status = "ready"
        content = m.top.itemContent
        if content <> invalid
            rawLogo = ""
            if content.addonLogo <> invalid then rawLogo = StringOf(content.addonLogo).Trim()
            m.isPlaceholder = IsPlaceholderLogo(rawLogo)
        end if
        UpdateLook()
    end if
end sub

sub onFocusChanged()
    UpdateLook()
end sub

sub UpdateLook()
    palette = Theme()
    logoFailed = false
    if m.logo <> invalid and m.logo.loadStatus = "failed" then logoFailed = true
    showPlaceholder = m.isPlaceholder or logoFailed
    if m.top.itemHasFocus
        m.face.color = palette.textPrimary
        m.name.color = palette.screenBg
        m.version.color = palette.screenBg
        m.scope.color = palette.screenBg
        m.description.color = palette.screenBg
        m.action.color = palette.screenBg
        if m.logoBg <> invalid then m.logoBg.blendColor = palette.tileFaceFocus
        m.logo.blendColor = "0xFFFFFFFF"
    else
        m.face.color = palette.tileFace
        m.name.color = palette.textPrimary
        m.version.color = palette.textSecondary
        m.scope.color = palette.textSecondary
        m.description.color = palette.textSecondary
        m.action.color = palette.textSecondary
        if m.logoBg <> invalid then m.logoBg.blendColor = palette.tileFaceFocus
        m.logo.blendColor = "0xFFFFFFFF"
    end if
    if m.top.rowHasFocus then m.top.opacity = 1.0 else m.top.opacity = 0.55
end sub

' Roku's Poster cannot decode SVG. Many add-ons publish an SVG logo, so try
' the same URL with a .png suffix first; the Poster's failedBitmapUri already
' falls back to the generic add-on icon when that candidate is missing.
function RokuLogoUri(uri as dynamic) as string
    value = StringOf(uri).Trim()
    if value = "" then return ""
    path = value
    queryStart = value.InStr("?")
    if queryStart >= 0 then path = value.Left(queryStart)
    if path.Len() < 4 then return value
    if LCase(path.Right(4)) <> ".svg" then return value
    return value.Left(path.Len() - 4) + ".png" + value.Mid(path.Len())
end function
