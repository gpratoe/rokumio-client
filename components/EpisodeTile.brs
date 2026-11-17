 ' EpisodeTile — wide episode card for EpisodesScreen's list.
'
' RowList feeds each item its ContentNode through `itemContent` and drives
' focus through `itemHasFocus`/`rowHasFocus`. Thumbnail loading is handled by
' PosterLoader (centralized URI/retry/stuck-loading recovery); presentation
' shows the artless unit until the thumbnail is ready.

sub init()
    m.border = m.top.FindNode("tileBorder")
    m.face = m.top.FindNode("tileFace")
    m.artless = m.top.FindNode("artless")
    m.poster = m.top.FindNode("poster")
    m.posterLoader = m.top.FindNode("posterLoader")
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

    if m.posterLoader <> invalid
        m.posterLoader.target = m.poster
        m.posterLoader.ObserveField("ready", "onPosterStateChanged")
        m.posterLoader.ObserveField("status", "onPosterStateChanged")
    end if

    m.top.ObserveField("itemContent", "onItemContentChanged")
    m.top.ObserveField("itemHasFocus", "onItemHasFocusChanged")
    m.top.ObserveField("rowHasFocus", "onRowHasFocusChanged")
end sub

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
    if m.top.itemContent <> invalid and m.top.itemContent.aired = false then m.top.opacity = 0.5 * m.top.opacity
end sub

sub onItemContentChanged()
    if m.top.itemContent = invalid then return
    poster = m.top.itemContent.hdPosterUrl
    if poster = invalid then poster = ""
    requestPoster = ""
    if poster <> "" then requestPoster = ResolveImageUri(poster)
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

    if m.posterLoader <> invalid
        if requestPoster = ""
            m.posterLoader.uri = ""
        else
            ' New item content should (re)request thumbnail; loader handles same-URI ready no-op.
            m.posterLoader.uri = ""
            m.posterLoader.uri = requestPoster
        end if
    end if
    ShowArtless()
    ApplyPosterPresentation()
    UpdateLook()
end sub

sub onItemHasFocusChanged()
    UpdateLook()
end sub

sub onRowHasFocusChanged()
    UpdateLook()
end sub

sub onPosterStateChanged()
    ApplyPosterPresentation()
end sub

sub ApplyPosterPresentation()
    if m.posterLoader = invalid then return
    uri = ""
    if m.top.itemContent <> invalid and m.top.itemContent.hdPosterUrl <> invalid then uri = ResolveImageUri(StringOf(m.top.itemContent.hdPosterUrl))
    if uri = ""
        ShowArtless()
        return
    end if
    if StringOf(m.posterLoader.uri) <> uri then return
    if m.posterLoader.ready = true or StringOf(m.posterLoader.status) = "ready"
        ShowPoster()
    else
        ShowArtless()
    end if
end sub


sub ShowArtless()
    if m.artless <> invalid then m.artless.visible = true
end sub

sub ShowPoster()
    if m.artless <> invalid then m.artless.visible = false
end sub

