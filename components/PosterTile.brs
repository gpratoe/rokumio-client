' PosterTile — custom list-item component used by the Home catalog rows.
'
' MarkupGrid/RowList feed each item its ContentNode through the interface field
' `itemContent` and drive focus through `itemHasFocus`/`rowHasFocus` (they never
' touch `content` or `focused`). The artwork comes from the item's
' hdPosterUrl (mapped from the addon meta's poster). Tiles without art — no
' poster URL, or one that failed to load — fall back to the title text so the
' tile is never a blank face. A tile with art shows the poster only.
'
' Two optional overlays ride on itemContent and render nothing until a screen
' provides them: `progress` (0..1) draws the bottom continue-watching bar, and
' `watchedGlyph` ("eye" | "clock") draws the top-right badge. Screens that
' set neither are pixel-identical to before.

sub init()
    m.poster = m.top.FindNode("poster")
    m.tileBg = m.top.FindNode("tileBg")
    m.tileBorder = m.top.FindNode("tileBorder")
    m.titleText = m.top.FindNode("titleText")
    m.loadSpinner = m.top.FindNode("loadSpinner")
    m.progressTrack = m.top.FindNode("progressTrack")
    m.progressFill = m.top.FindNode("progressFill")
    m.watchedGlyph = m.top.FindNode("watchedGlyph")

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
        m.top.scale = [1.1, 1.1]
    else
        m.tileBorder.color = "0x2BD67500"
        m.tileBg.color = "0x0B110DFF"
        m.top.scale = [1.0, 1.0]
    end if
    if m.top.rowHasFocus then m.top.opacity = 1.0 else m.top.opacity = 0.55
end sub

sub onItemHasFocusChanged()
    UpdateLook()
end sub

' A whole row dims when its list row loses focus (user moved to another row),
' reinforcing which row the "selected" indicator sits in.
sub onRowHasFocusChanged()
    UpdateLook()
end sub

sub onItemContentChanged()
    if m.top.itemContent = invalid then return
    loading = m.top.itemContent.loadState = "loading"
    if loading
        m.loadSpinner.visible = true
        m.loadSpinner.spinning = true
        m.poster.uri = ""
        m.titleText.text = m.top.itemContent.title
        m.titleText.visible = false
        UpdateOverlays()
        UpdateLook()
        return
    end if

    ' Only Search sets loadState, and it defaults off here — every other screen
    ' that reuses PosterTile is unaffected. A recycled tile must not carry a
    ' spinning-but-hidden spinner into its next cell, so always stop it when not
    ' loading.
    m.loadSpinner.spinning = false
    m.loadSpinner.visible = false

    poster = m.top.itemContent.hdPosterUrl
    if poster = invalid then poster = ""
    m.poster.uri = poster
    m.titleText.text = m.top.itemContent.title
    UpdateOverlays()
    UpdateFallback()
    UpdateLook()
end sub

' The progress bar and watched glyph are driven entirely by optional
' itemContent fields, so a tile reused without them (or recycled onto one
' without them) never shows a stale overlay.
sub UpdateOverlays()
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
        m.watchedGlyph.visible = true
    else
        m.watchedGlyph.visible = false
    end if
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
