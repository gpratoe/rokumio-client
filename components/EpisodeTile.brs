' EpisodeTile — landscape episode cell for EpisodesScreen's season rows.
'
' RowList/RowList feed each item its ContentNode through the interface field
' `itemContent` and drive focus through `itemHasFocus`/`rowHasFocus`. The
' artwork comes from the episode's thumbnail (hdPosterUrl). Cells without art —
' no thumbnail URL, or one that failed to load — fall back to the S#E#/name
' text so the tile is never a blank face.

sub init()
    m.poster = m.top.FindNode("poster")
    m.tileBg = m.top.FindNode("tileBg")
    m.tileBorder = m.top.FindNode("tileBorder")
    m.titleText = m.top.FindNode("titleText")

    m.top.ObserveField("itemContent", "onItemContentChanged")
    m.top.ObserveField("itemHasFocus", "onItemHasFocusChanged")
    m.top.ObserveField("rowHasFocus", "onRowHasFocusChanged")
    m.poster.ObserveField("loadStatus", "onPosterLoadStatus")
end sub

' Every focus observer re-applies the whole look from the tile's current field
' values. RowList recycles item components for new cells and content swaps, and
' those observers only fire on value *changes* — on a recycle nothing may change
' except itemContent, so unless the look is rebuilt there a tile carries stale
' dimming (opacity 0.55) into a fresh row on another screen/media.
sub UpdateLook()
    if m.top.itemHasFocus
        m.tileBorder.color = "0x5BEF95FF"
        m.tileBg.color = "0x18231CFF"
    else
        m.tileBorder.color = "0x2BD67500"
        m.tileBg.color = "0x0B110DFF"
    end if
    if m.top.rowHasFocus then m.top.opacity = 1.0 else m.top.opacity = 0.55
end sub

sub onItemHasFocusChanged()
    UpdateLook()
end sub

' A whole row dims when its list row loses focus (user moved to another season),
' reinforcing which season's tile is selected.
sub onRowHasFocusChanged()
    UpdateLook()
end sub

sub onItemContentChanged()
    if m.top.itemContent = invalid then return
    poster = m.top.itemContent.hdPosterUrl
    if poster = invalid then poster = ""
    m.poster.uri = poster
    m.titleText.text = m.top.itemContent.title
    UpdateFallback()
    UpdateLook()
end sub

sub onPosterLoadStatus()
    UpdateFallback()
end sub

' The fallback text is shown only while no workable art is available: no URL,
' or a URL whose load errored out.
sub UpdateFallback()
    status = m.poster.loadStatus
    hasArt = m.poster.uri <> invalid and m.poster.uri <> "" and status <> "error"
    m.titleText.visible = not hasArt
end sub