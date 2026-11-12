' Hero.brs — the shared hero render pipeline used by browse screens (Home,
' Discover, Library). It drives the standard hero node set — poster/scrim/mask,
' logo/title, meta/rating/genres/description — so a focused item's artwork and
' details stay prominent at 10-foot distance (tvOS 10-foot UI) without each
' screen reimplementing the logo grace/fade/layout machinery.
'
' Contract (the screen owns the markup/timers/anims and wires observers; this
' script owns the state + rendering over them):
'   Nodes  : m.heroPoster, m.heroLogo, m.heroTitle, m.heroMeta,
'            m.heroRating, m.heroRatingText, m.heroGenres, m.heroDescription
'   Timers : m.heroTitleGrace        (fires onHeroTitleGraceFire / HeroOnTitleGraceFire)
'   Anims  : m.heroPosterFadeAnim    (fades poster in on ready)
'   State  : m.heroPosterPendingUri, m.heroLogoUri, m.heroLogoGraceUri,
'            m.heroLogoFallbackUri, m.heroLayoutMode, m.heroFocusKey
'
' Screens include this file, initialize the state fields, observe
' heroPoster.loadStatus / heroLogo.loadStatus / heroTitleGrace.fire to the
' HeroOn* handlers (or their own wrappers), and feed focused metas through
' HeroRender(meta, fallbackMetaType).

sub HeroInitState()
    m.heroPosterPendingUri = ""
    m.heroLogoUri = ""
    m.heroLogoGraceUri = ""
    m.heroLogoFallbackUri = ""
    m.heroLayoutMode = "title"
    m.heroFocusKey = ""
end sub

sub HeroClear()
    m.heroFocusKey = ""
    m.heroLogoUri = ""
    m.heroLogoGraceUri = ""
    m.heroLogoFallbackUri = ""
    if m.heroTitleGrace <> invalid then m.heroTitleGrace.control = "stop"
    if m.heroPosterFadeAnim <> invalid then m.heroPosterFadeAnim.control = "stop"
    m.heroPosterPendingUri = ""
    if m.heroPoster <> invalid
        m.heroPoster.uri = ""
        m.heroPoster.opacity = 1
        m.heroPoster.visible = false
    end if
    if m.heroLogo <> invalid and m.heroLogo.uri <> "" then m.heroLogo.uri = ""
    if m.heroTitle <> invalid then m.heroTitle.text = ""
    if m.heroMeta <> invalid then m.heroMeta.text = ""
    if m.heroRatingText <> invalid then m.heroRatingText.text = ""
    if m.heroRating <> invalid then m.heroRating.visible = false
    if m.heroGenres <> invalid
        m.heroGenres.text = ""
        m.heroGenres.visible = false
    end if
    if m.heroDescription <> invalid
        m.heroDescription.text = ""
        m.heroDescription.visible = false
    end if
    HeroApplyLayout("title", false)
end sub

' Render the hero for one meta. Degrades gracefully: missing fields stay hidden
' and a missing logo falls back to the title layout, so slim records (e.g.
' saved library items that only carry name/poster/type) still produce a valid
' hero. background falls back to poster when no dedicated background art exists.
' fallbackMetaType is used when the meta carries no type of its own (catalog
' context).
sub HeroRender(meta as object, fallbackMetaType = "" as string)
    if meta = invalid then return
    title = StringOf(meta.name)
    if title.Trim() = "" then title = StringOf(meta.title)
    if title.Trim() = "" then title = ""
    description = StringOf(meta.description)
    if description.Trim() = "" then description = StringOf(meta.overview)
    metaType = StringOf(meta.type)
    if metaType = "" then metaType = StringOf(meta.metaType)
    if metaType = "" then metaType = fallbackMetaType
    kind = HeroTypeLabel(metaType)
    releaseInfo = StringOf(meta.releaseInfo)
    if releaseInfo <> "" and kind <> "" then kind = kind + " · " + releaseInfo
    if releaseInfo <> "" and kind = "" then kind = releaseInfo
    ratingKey = "imdb" + "Rating"
    rating = StringOf(meta[ratingKey])
    runtime = FormatRuntime(meta.runtime)
    if runtime <> "" and metaType <> "series"
        if kind <> "" then kind = kind + " · " + runtime else kind = runtime
    end if
    genres = HeroGenresText(meta.genres)
    if title.Len() > 44 then title = Left(title, 41) + "..."
    if description.Len() > 150 then description = Left(description, 147) + "..."

    logo = StringOf(meta.logo)
    background = StringOf(meta.background)
    if background = "" then background = StringOf(meta.poster)
    currentLogoUri = m.heroLogo.uri
    currentLogoReady = currentLogoUri <> "" and currentLogoUri = m.heroLogoUri and m.heroLogo.loadStatus = "ready"
    sameLogoReady = logo <> "" and logo = currentLogoUri and currentLogoReady and logo = m.heroLogoUri

    if m.heroTitle.text <> title then m.heroTitle.text = title
    if m.heroMeta.text <> kind then m.heroMeta.text = kind
    if m.heroRatingText.text <> rating then m.heroRatingText.text = rating
    ratingVisible = rating.Trim() <> ""
    if m.heroRating.visible <> ratingVisible then m.heroRating.visible = ratingVisible
    if m.heroGenres.text <> genres then m.heroGenres.text = genres
    genresVisible = genres <> ""
    if m.heroGenres.visible <> genresVisible then m.heroGenres.visible = genresVisible
    if m.heroDescription.text <> description then m.heroDescription.text = description
    descVisible = description.Trim() <> ""
    if m.heroDescription.visible <> descVisible then m.heroDescription.visible = descVisible

    if background = ""
        m.heroPosterPendingUri = ""
        if m.heroPosterFadeAnim <> invalid then m.heroPosterFadeAnim.control = "stop"
        m.heroPoster.opacity = 1
        if m.heroPoster.uri <> "" then m.heroPoster.uri = ""
        m.heroPoster.visible = false
    else if m.heroPoster.uri <> background
        m.heroPosterPendingUri = background
        if m.heroPosterFadeAnim <> invalid then m.heroPosterFadeAnim.control = "stop"
        m.heroPoster.opacity = 0
        m.heroPoster.uri = background
        m.heroPoster.visible = true
    else
        m.heroPosterPendingUri = background
        m.heroPoster.visible = true
        if m.heroPoster.loadStatus = "ready" or m.heroPoster.loadStatus = "failed"
            if m.heroPosterFadeAnim <> invalid then m.heroPosterFadeAnim.control = "stop"
            m.heroPoster.opacity = 1
        end if
    end if

    if logo = ""
        m.heroLogoUri = ""
        m.heroLogoGraceUri = ""
        m.heroLogoFallbackUri = ""
        if m.heroTitleGrace <> invalid then m.heroTitleGrace.control = "stop"
        if m.heroLogo.uri <> "" then m.heroLogo.uri = ""
        HeroApplyLayout("title", true)
        return
    end if

    if sameLogoReady
        m.heroLogoGraceUri = ""
        m.heroLogoFallbackUri = ""
        if m.heroTitleGrace <> invalid then m.heroTitleGrace.control = "stop"
        m.heroLogo.visible = true
        m.heroTitle.visible = false
        return
    end if

    logoChanged = logo <> m.heroLogoUri
    if logoChanged
        m.heroLogoUri = logo
        m.heroLogoGraceUri = ""
        m.heroLogoFallbackUri = ""
        if m.heroTitleGrace <> invalid then m.heroTitleGrace.control = "stop"
        m.heroLogo.uri = logo
    end if

    if m.heroLogoFallbackUri = logo
        HeroShowTitleFallback()
        return
    end if

    if logoChanged or m.heroLogoGraceUri <> logo
        m.heroLogoGraceUri = logo
        m.heroLogoFallbackUri = ""
        if m.heroTitleGrace <> invalid
            m.heroTitleGrace.control = "stop"
            m.heroTitleGrace.control = "start"
        end if
    end if

    if m.heroLayoutMode = "wide"
        m.heroLogo.visible = false
        m.heroTitle.visible = false
    else
        HeroApplyLayout("title", false)
    end if
end sub

sub HeroOnPosterStatus()
    if m.heroPoster = invalid then return
    if m.heroPoster.uri <> m.heroPosterPendingUri then return
    status = m.heroPoster.loadStatus
    if status = "ready"
        if m.heroPosterFadeAnim <> invalid
            m.heroPosterFadeAnim.control = "stop"
            m.heroPoster.opacity = 0
            m.heroPosterFadeAnim.control = "start"
        else
            m.heroPoster.opacity = 1
        end if
    else if status = "failed"
        if m.heroPosterFadeAnim <> invalid then m.heroPosterFadeAnim.control = "stop"
        m.heroPoster.opacity = 1
    end if
end sub

sub HeroOnLogoStatus()
    if m.heroLogo.uri <> m.heroLogoUri then return
    if m.heroLogo.loadStatus = "ready"
        if m.heroTitleGrace <> invalid then m.heroTitleGrace.control = "stop"
        m.heroLogoGraceUri = ""
        m.heroLogoFallbackUri = ""
        HeroFitLogo()
    else if m.heroLogo.loadStatus = "failed"
        if m.heroTitleGrace <> invalid then m.heroTitleGrace.control = "stop"
        m.heroLogoGraceUri = ""
        m.heroLogoFallbackUri = m.heroLogoUri
        HeroShowTitleFallback()
    end if
end sub

sub HeroOnTitleGraceFire()
    if m.heroLogoUri = "" then return
    if m.heroLogo.uri <> m.heroLogoUri then return
    if m.heroLogo.loadStatus = "ready" then return
    m.heroLogoGraceUri = ""
    m.heroLogoFallbackUri = m.heroLogoUri
    HeroShowTitleFallback()
end sub

sub HeroShowTitleFallback()
    m.heroLogo.visible = false
    m.heroTitle.visible = true
    if m.heroLayoutMode = "tall"
        HeroApplyLayout("title", true)
    else if m.heroLayoutMode <> "wide"
        HeroApplyLayout("title", true)
    end if
end sub

sub HeroApplyLayout(mode as string, showTitle = true as boolean)
    if mode = "tall" or mode = "wide" then return
    m.heroLayoutMode = "title"
    m.heroLogo.visible = false
    m.heroTitle.visible = showTitle
    m.heroLogo.translation = [162, 72]
    m.heroLogo.width = 820
    m.heroLogo.height = 460
    m.heroMeta.translation = [166, 216]
    m.heroRating.translation = [166, 256]
    m.heroGenres.translation = [166, 307]
    m.heroDescription.translation = [166, 357]
    m.heroDescription.width = 860
    m.heroDescription.height = 150
end sub

sub HeroFitLogo()
    fit = HeroFit(m.heroLogo.bitmapWidth, m.heroLogo.bitmapHeight)
    if fit = invalid then return
    logoWidth = fit.width
    logoHeight = fit.height

    m.heroLogo.width = logoWidth
    m.heroLogo.height = logoHeight
    if fit.tall
        m.heroLayoutMode = "tall"
        m.heroLogo.translation = [162, Int((540 - logoHeight) / 2)]
        contentX = 162 + logoWidth + 48
        m.heroMeta.translation = [contentX, 110]
        m.heroRating.translation = [contentX, 158]
        m.heroGenres.translation = [contentX, 206]
        m.heroDescription.translation = [contentX, 256]
        m.heroDescription.width = 1920 - contentX - 160
        m.heroDescription.height = 260
    else
        m.heroLayoutMode = "wide"
        m.heroLogo.translation = [162, 70 + Int((190 - logoHeight) / 2)]
        m.heroMeta.translation = [166, 274]
        m.heroRating.translation = [166, 316]
        m.heroGenres.translation = [166, 360]
        m.heroDescription.translation = [166, 402]
        m.heroDescription.width = 1000
        m.heroDescription.height = 138
    end if
    m.heroLogo.visible = true
    m.heroTitle.visible = false
end sub

sub HeroResetLogoLayout()
    HeroApplyLayout("title", true)
end sub

' Localized content-type label for the hero meta line. Shared so browse
' screens don't each duplicate it (Home/Discover keep their own copies until
' they migrate onto this helper).
function HeroTypeLabel(metaType as dynamic) as string
    t = ""
    if metaType <> invalid then t = metaType
    if t = "movie" then return Lang("common", "kindMovie")
    if t = "series" then return Lang("common", "kindSeries")
    if t = "channel" or t = "tv" then return Lang("search", "tvChannel")
    return t
end function
