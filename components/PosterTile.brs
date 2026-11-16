 ' PosterTile — custom list-item component used by the Home catalog rows.
'
' MarkupGrid/RowList feed each item its ContentNode through the interface field
' `itemContent` and drive focus through `itemHasFocus`/`rowHasFocus` (they never
' touch `content` or `focused`). Artwork is loaded via PosterLoader (centralized
' URI assignment, retry, stuck-loading recovery) and presentation is driven by
' loader state: artless (face/title) is shown until the poster is ready.

sub init()
    m.artless = m.top.FindNode("artless")
    m.poster = m.top.FindNode("poster")
    m.posterLoader = m.top.FindNode("posterLoader")
    m.tileBg = m.top.FindNode("tileBg")
    m.titleText = m.top.FindNode("titleText")

    m.progressTrack = m.top.FindNode("progressTrack")
    m.progressFill = m.top.FindNode("progressFill")
    m.watchedBadge = m.top.FindNode("watchedBadge")
    m.watchedPlate = m.top.FindNode("watchedPlate")
    m.watchedGlyph = m.top.FindNode("watchedGlyph")

    m.seeMoreGroup = m.top.FindNode("seeMoreGroup")
    m.seeMoreBg = m.top.FindNode("seeMoreBg")
    m.seeMorePlus = m.top.FindNode("seeMorePlus")
    m.seeMoreLabel = m.top.FindNode("seeMoreLabel")

    t = Theme()
    m.tileBg.color = t.tileFace
    m.titleText.color = t.textPrimary
    m.progressTrack.color = t.progressTrack
    m.progressFill.color = t.progressFill
    m.watchedPlate.color = t.glyphPlate
    if m.seeMoreBg <> invalid then m.seeMoreBg.color = t.tileFace
    if m.seeMorePlus <> invalid then m.seeMorePlus.color = t.accent
    if m.seeMoreLabel <> invalid then m.seeMoreLabel.color = t.textSecondary

    m.lastReloadNonce = 0
    m.requestedPosterUri = ""

    if m.posterLoader <> invalid
        m.posterLoader.target = m.poster
        m.posterLoader.ObserveField("ready", "onPosterStateChanged")
        m.posterLoader.ObserveField("status", "onPosterStateChanged")
    end if

    m.top.ObserveField("itemContent", "onItemContentChanged")
    m.top.ObserveField("itemHasFocus", "onItemHasFocusChanged")
    m.top.ObserveField("rowHasFocus", "onRowHasFocusChanged")

    ApplyTileSize()
end sub

sub ApplyTileSize()
    if m.poster = invalid then return

    w = m.top.width
    h = m.top.height
    if w = invalid or h = invalid then return
    if w <= 0 or h <= 0 then return

    m.poster.width = w
    m.poster.height = h
    m.poster.loadWidth = w
    m.poster.loadHeight = h
    m.tileBg.width = w
    m.tileBg.height = h
    m.titleText.width = w - 24
    m.titleText.height = h - 16
    m.progressTrack.width = w
    m.progressTrack.translation = [0, h - 8]
    m.progressFill.translation = [0, h - 8]
    m.progressFill.width = w
    m.watchedBadge.translation = [w - 62, 8]
    if m.seeMoreGroup <> invalid
        m.seeMoreBg.width = w
        m.seeMoreBg.height = h
        m.seeMorePlus.width = w
        m.seeMorePlus.translation = [0, Int(h * 0.22)]
        m.seeMorePlus.height = Int(h * 0.45)
        m.seeMoreLabel.width = w - 24
        m.seeMoreLabel.translation = [12, Int(h * 0.62)]
        m.seeMoreLabel.height = Int(h * 0.2)
    end if

    if w = 270 and h = 405
        m.titleText.translation = [18, 8]
    else
        m.titleText.translation = [12, 8]
    end if

    if m.top.itemContent <> invalid then UpdateOverlays()
end sub

sub UpdateLook()
    if m.top.rowHasFocus then m.top.opacity = 1.0 else m.top.opacity = 0.55
end sub

sub onItemHasFocusChanged()
    UpdateLook()
end sub

sub onRowHasFocusChanged()
    UpdateLook()
end sub

sub onItemContentChanged()
    if m.top.itemContent = invalid then return
    if m.top.itemContent.seeMore = true
        m.requestedPosterUri = ""
        if m.posterLoader <> invalid then m.posterLoader.uri = ""
        m.artless.visible = false
        if m.progressTrack <> invalid then m.progressTrack.visible = false
        if m.progressFill <> invalid then m.progressFill.visible = false
        if m.watchedBadge <> invalid then m.watchedBadge.visible = false
        if m.seeMoreGroup <> invalid
            m.seeMoreGroup.visible = true
            if m.seeMoreLabel <> invalid then m.seeMoreLabel.text = m.top.itemContent.title
        end if
        UpdateLook()
        return
    end if
    if m.seeMoreGroup <> invalid then m.seeMoreGroup.visible = false

    loading = m.top.itemContent.loadState = "loading"
    if loading
        m.requestedPosterUri = ""
        if m.posterLoader <> invalid then m.posterLoader.uri = ""
        m.titleText.text = m.top.itemContent.title
        ShowArtless()
        UpdateOverlays()
        UpdateLook()
        return
    end if

    poster = m.top.itemContent.hdPosterUrl
    if poster = invalid then poster = ""
    requestPoster = ""
    if poster <> "" then requestPoster = ProxyImageUri(poster)
    nonce = 0
    if m.top.itemContent.reloadNonce <> invalid then nonce = m.top.itemContent.reloadNonce
    forceReload = nonce <> 0 and nonce <> m.lastReloadNonce
    if forceReload then m.lastReloadNonce = nonce

    prevUri = m.requestedPosterUri
    m.titleText.text = m.top.itemContent.title
    UpdateOverlays()

    if requestPoster = ""
        m.requestedPosterUri = ""
        if m.posterLoader <> invalid then m.posterLoader.uri = ""
        ShowArtless()
    else
        if forceReload or prevUri <> requestPoster
            m.requestedPosterUri = requestPoster
            if m.posterLoader <> invalid
                ' Force a fresh request even for same URI on explicit reload.
                m.posterLoader.callFunc("Clear")
                m.posterLoader.callFunc("Load", requestPoster)
            end if
            ShowArtless()
        else
            ' Same requested URI: keep presentation based on current loader state.
            m.requestedPosterUri = requestPoster
            ApplyPosterPresentation()
        end if
    end if
    UpdateLook()
end sub

sub onPosterStateChanged()
    ApplyPosterPresentation()
end sub

sub ApplyPosterPresentation()
    if m.posterLoader = invalid then return
    if m.requestedPosterUri = "" then
        ShowArtless()
        return
    end if
    ' Ignore stale loader updates from a previous request.
    if StringOf(m.posterLoader.uri) <> m.requestedPosterUri then return
    if m.posterLoader.ready = true or StringOf(m.posterLoader.status) = "ready"
        ShowPoster()
    else
        ' loading/failed (including retries exhausted) keeps artless/title visible.
        ShowArtless()
    end if
end sub

sub ShowArtless()
    if m.artless <> invalid then m.artless.visible = true
end sub

sub ShowPoster()
    if m.artless <> invalid then m.artless.visible = false
end sub

sub UpdateOverlays()
    if m.top.itemContent = invalid then return
    progress = m.top.itemContent.progress
    if progress <> invalid and progress > 0 and progress <= 1
        m.progressFill.width = m.poster.width * progress
        m.progressTrack.visible = true
        m.progressFill.visible = true
    else
        m.progressFill.width = m.poster.width
        m.progressTrack.visible = false
        m.progressFill.visible = false
    end if

    glyph = m.top.itemContent.watchedGlyph
    if glyph = "eye" or glyph = "clock"
        m.watchedGlyph.uri = "pkg:/images/" + glyph + ".png"
        m.watchedBadge.visible = true
    else
        m.watchedBadge.visible = false
    end if
end sub
