' EpisodeTile — wide episode card for EpisodesScreen's list.
'
' RowList feeds each item its ContentNode through `itemContent` and drives
' focus through `itemHasFocus`/`rowHasFocus`. The artwork comes from the
' episode's thumbnail (hdPosterUrl); a cell is either artwork or the artless
' unit (a thumbnail-sized face plus the S#E#/name text), never a blend:
' ShowArtless/ShowPoster swap them as a unit on the thumbnail's own
' loadStatus. Poster.loadStatus is none / loading / ready / failed — "ready"
' is the success value, and there is no "loaded"; see the Poster field
' reference.
'
' The card look at focus time is the chip look: focus does not invert the
' content — it lifts the plate one step under a white hairline ring. Idle
' keeps the soft hairline.

sub init()
    m.border = m.top.FindNode("tileBorder")
    m.face = m.top.FindNode("tileFace")
    m.artless = m.top.FindNode("artless")
    m.poster = m.top.FindNode("poster")
    m.tileBg = m.top.FindNode("tileBg")
    m.titleText = m.top.FindNode("titleText")
    m.watchedBadgeGroup = m.top.FindNode("watchedBadgeGroup")
    m.watchedPlate = m.top.FindNode("watchedPlate")
    m.watchedBadge = m.top.FindNode("watchedBadge")
    m.epTitle = m.top.FindNode("epTitle")
    m.epDate = m.top.FindNode("epDate")
    m.epSynopsis = m.top.FindNode("epSynopsis")

    t = Theme()
    m.tileBg.color = t.tileFace
    m.titleText.color = t.textPrimary
    m.epTitle.color = t.textPrimary
    m.epSynopsis.color = t.textSecondary
    m.watchedPlate.color = t.glyphPlate

    m.top.ObserveField("itemContent", "onItemContentChanged")
    m.top.ObserveField("itemHasFocus", "onItemHasFocusChanged")
    m.top.ObserveField("rowHasFocus", "onRowHasFocusChanged")
    m.poster.ObserveField("loadStatus", "onPosterLoadStatus")
end sub

' Every focus observer re-applies the whole look from the tile's current field
' values. RowList recycles item components for new cells and content swaps, and
' those observers only fire on value *changes* — on a recycle nothing may change
' except itemContent, so unless the look is rebuilt there a tile carries stale
' dimming (opacity 0.55) into a fresh RowList on another screen/media.
sub UpdateLook()
    t = Theme()
    if m.top.itemHasFocus
        m.border.blendColor = t.textWhite
        m.face.blendColor = t.tileFaceFocus
    else
        m.border.blendColor = t.borderSoft
        m.face.blendColor = t.tileFace
    end if
    if m.top.rowHasFocus then m.top.opacity = 1.0 else m.top.opacity = 0.55
    ' Episodes that haven't aired yet are dimmed further (still visible, but
    ' clearly not watchable). Missing aired is treated as aired so non-episode
    ' screens keep their current look.
    if m.top.itemContent <> invalid and m.top.itemContent.aired = false then m.top.opacity = 0.5 * m.top.opacity
end sub

sub onItemContentChanged()
    if m.top.itemContent = invalid then return
    poster = m.top.itemContent.hdPosterUrl
    if poster = invalid then poster = ""
    m.poster.uri = poster
    label = m.top.itemContent.title
    if label = invalid then label = ""
    m.epTitle.text = label
    m.titleText.text = label
    overview = m.top.itemContent.description
    if overview = invalid then overview = ""
    m.epSynopsis.text = overview
    dateLabel = m.top.itemContent.dateLabel
    if dateLabel = invalid or dateLabel = ""
        m.epDate.visible = false
    else
        t = Theme()
        if m.top.itemContent.dateUpcoming then m.epDate.color = t.accentInfo else m.epDate.color = t.accentWarm
        m.epDate.text = dateLabel
        m.epDate.visible = true
    end if
    if m.top.itemContent.watched = true
        m.watchedBadge.uri = "pkg:/images/eye.png"
        m.watchedBadgeGroup.visible = true
    else
        m.watchedBadgeGroup.visible = false
    end if
    ' Forced rather than read back from loadStatus: the uri was just set, so
    ' this cell is artless whatever the status field still reports from the
    ' previous one.
    ShowArtless()
    ' A uri set to something already cached can settle before the observer ever
    ' fires, so re-read the status now instead of trusting the callback alone.
    if m.poster.loadStatus = "ready" or m.poster.loadStatus = "failed" then onPosterLoadStatus()
    UpdateLook()
end sub

' The mark for focus walks: no extra work beyond the shared look, but listed
' explicitly because the RowList drives both fields and either may arrive alone
' on a recycle.
sub onItemHasFocusChanged()
    UpdateLook()
end sub

sub onRowHasFocusChanged()
    UpdateLook()
end sub

sub onPosterLoadStatus()
    if m.poster.loadStatus = "ready" then ShowPoster() else ShowArtless()
end sub

' The artless unit: the face plus the title. The poster is left alone on purpose
' — it is visible from the start and paints nothing until it has a bitmap, so
' there is nothing to hide.
sub ShowArtless()
    m.artless.visible = true
end sub

' The thumbnail has painted, so the face must stop rendering rather than sit
' behind the artwork where it still shows through on unfocused rows. Only this
' group is hidden; hiding the poster itself would deadlock the load against the
' gate waiting on it.
sub ShowPoster()
    m.artless.visible = false
end sub
