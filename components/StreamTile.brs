' StreamTile — wide stream card for StreamsScreen's list.
'
' RowList feeds each item its ContentNode through `itemContent` and drives focus
' through `itemHasFocus`/`rowHasFocus`. The primary line is the stream name
' (e.g. "4k DV | HDR10+"); the lines below are the stream title split
' at its embedded line feeds (release / file / peers-size / languages). The
' description field carries the whole multi-line title, split right here into
' however many rows the card fits — never pre-mapped onto fixed fields. Every
' text line is a ScrollingLabel: addon data is untrusted and any line can be
' wider than the card. Only the focused card scrolls — overflowing lines on it
' ellipsize and loop inside the card; unfocused cards render the line full-width,
' statically clipped to the card's edge (the scroll pass ScrollingLabel does on
' every text-set is kept from firing by giving those labels a maxWidth no text
' can reach).

sub init()
    m.border = m.top.FindNode("tileBorder")
    m.face = m.top.FindNode("tileFace")
    m.title = m.top.FindNode("tileTitle")
    m.lines = []
    for i = 1 to 5
        m.lines.Push(m.top.FindNode("tileLine" + i.ToStr()))
    end for

    t = Theme()
    m.title.color = t.textPrimary
    m.lines[0].color = t.textPrimary
    for i = 1 to m.lines.Count() - 1
        m.lines[i].color = t.textSecondary
    end for

    ' The whole card renders in OpenSansEmoji: a monochrome face that covers the
    ' stream names' Latin AND emoji glyphs ("👤 412 💾 54.2 GB", flag emojis, …)
    ' in one font, since Roku's bundled system fonts carry no emoji and
    ' Segmentation by markup would force per-glyph detection. Mixing regular and
    ' emoji characters on one line needs no fallback — the font has both.
    SetCardFont()

    m.top.ObserveField("itemContent", "onItemContentChanged")
    m.top.ObserveField("itemHasFocus", "onItemHasFocusChanged")
    m.top.ObserveField("rowHasFocus", "onRowHasFocusChanged")
end sub

' Create one shared Font node per card size — title (32) and body lines (27) —
' from the bundled OpenSansEmoji font and hang them on the
' labels. Two nodes cover all six; assigning the same Font to several labels is
' fine, and keeping them as children holds them for the tile's lifetime.
sub SetCardFont()
    titleSize = 32
    bodySize = 27
    m.cardTitleFont = CreateObject("roSGNode", "Font")
    m.cardTitleFont.uri = "pkg:/fonts/opensansemoji.ttf"
    m.cardTitleFont.size = titleSize
    m.cardBodyFont = CreateObject("roSGNode", "Font")
    m.cardBodyFont.uri = "pkg:/fonts/opensansemoji.ttf"
    m.cardBodyFont.size = bodySize
    m.top.AppendChild(m.cardTitleFont)
    m.top.AppendChild(m.cardBodyFont)
    m.title.font = m.cardTitleFont
    for each line in m.lines
        line.font = m.cardBodyFont
    end for
end sub

' Every inbound field change re-applies the whole look from the tile's current
' field values. RowList recycles item components for new cells and content
' swaps, and rowHasFocus/itemHasFocus only fire on value *changes* — on a
' recycle nothing may change except itemContent, so unless the look is rebuilt
' there a tile carries stale dimming (opacity 0.55) into a fresh RowList on
' another screen/media.
sub UpdateLook()
    t = Theme()
    if m.top.itemHasFocus
        m.border.color = t.accentFocus
        m.face.color = t.itemFace
    else
        m.border.color = t.accentClear
        m.face.color = t.tileFace
    end if
    if m.top.rowHasFocus then m.top.opacity = 1.0 else m.top.opacity = 0.55
    ' ScrollingLabel triggers its ellipsize+scroll pass the moment text is set
    ' on it — even with repeatCount=0. Gating on focus uses BOTH knobs: the
    ' focused card gets maxWidth 1040 (overflow -> real scroll loop) and
    ' repeatCount -1; every other card gets maxWidth 100000 (text never exceeds
    ' it, so nothing triggers — the line renders static and full-width, clipped
    ' to the card by its clippingRect) and repeatCount 0.
    if m.top.itemHasFocus
        scrollPC = 1040
        repeatCount = -1
    else
        scrollPC = 100000
        repeatCount = 0
    end if
    m.title.maxWidth = scrollPC
    m.title.repeatCount = repeatCount
    for each line in m.lines
        line.maxWidth = scrollPC
        line.repeatCount = repeatCount
    end for
end sub

sub onItemContentChanged()
    if m.top.itemContent = invalid then return
    m.title.text = m.top.itemContent.title
    description = m.top.itemContent.description
    if description = invalid then description = ""
    pieces = description.Split(chr(10))
    for i = 0 to m.lines.Count() - 1
        text = ""
        if pieces <> invalid and i < pieces.Count() then text = pieces[i]
        m.lines[i].text = text
    end for
    UpdateLook()
end sub

sub onItemHasFocusChanged()
    UpdateLook()
end sub

sub onRowHasFocusChanged()
    UpdateLook()
end sub