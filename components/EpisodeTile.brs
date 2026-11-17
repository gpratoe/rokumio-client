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

    m.requestedPosterUri = ""
    m.requestedOriginalUri = ""
    m.posterReady = false
    m.swapPending = false

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

' Resolve at display time so a cache miss->hit (remote -> tmp:/) for the same
' image can be treated as equivalent and not reloaded.
function ThumbnailDisplayUri(originalUri as dynamic) as string
    s = StringOf(originalUri)
    if s = "" then return ""
    return ResolveImageUri(s)
end function

sub onItemContentChanged()
    if m.top.itemContent = invalid then return

    original = m.top.itemContent.hdPosterUrl
    if original = invalid then original = ""
    requestPoster = ThumbnailDisplayUri(original)

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

    prevUri = m.requestedPosterUri
    prevOriginal = m.requestedOriginalUri

    if requestPoster = ""
        m.requestedPosterUri = ""
        m.requestedOriginalUri = ""
        m.posterReady = false
        m.swapPending = false
        if m.posterLoader <> invalid then m.posterLoader.uri = ""
        ShowArtless()
    else
        sameImage = false
        if prevUri = requestPoster
            sameImage = true
        else if prevOriginal <> "" and StringOf(prevOriginal) = StringOf(original) and ImageCacheSameResolvedUri(original, prevUri, requestPoster)
            sameImage = true
        else if ImageCacheSameResolvedUri(original, prevUri, requestPoster) and m.posterReady
            sameImage = true
        end if

        if sameImage
            ' Same underlying image (including remote -> cached tmp flip). Keep
            ' current presentation; do not clear/reload to avoid flash.
            m.requestedPosterUri = requestPoster
            m.requestedOriginalUri = original
            m.swapPending = false
            ApplyPosterPresentation()
        else
            hadReady = m.posterReady = true
            m.requestedPosterUri = requestPoster
            m.requestedOriginalUri = original
            m.posterReady = false
            ' Genuine swap: keep previous visual until new is ready to avoid
            ' artless flash. No Clear() so prior frame can remain while loading.
            m.swapPending = hadReady
            if m.posterLoader <> invalid then m.posterLoader.callFunc("Load", requestPoster)
            if not m.swapPending then ShowArtless()
            if not m.swapPending then ApplyPosterPresentation()
        end if
    end if

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
    if m.requestedPosterUri = ""
        ShowArtless()
        return
    end if
    ' Ignore stale loader updates from a previous request.
    if StringOf(m.posterLoader.uri) <> m.requestedPosterUri then return
    status = StringOf(m.posterLoader.status)
    if m.posterLoader.ready = true or status = "ready"
        m.posterReady = true
        m.swapPending = false
        ShowPoster()
    else if status = "failed"
        m.posterReady = false
        m.swapPending = false
        ShowArtless()
    else
        ' Loading/transient. During a swap keep previous visual to avoid flash.
        if not m.swapPending then ShowArtless()
    end if
end sub

sub ShowArtless()
    if m.artless <> invalid then m.artless.visible = true
end sub

sub ShowPoster()
    if m.artless <> invalid then m.artless.visible = false
end sub
