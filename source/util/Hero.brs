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
    m.heroPosterSourceUri = ""
    m.heroLogoUri = ""
    m.heroLogoGraceUri = ""
    m.heroLogoFallbackUri = ""
    m.heroLayoutMode = "title"
    m.heroFocusKey = ""
    if m.heroPosterPrev <> invalid
        m.heroPosterPrev.opacity = 0
        m.heroPosterPrev.visible = false
        m.heroPosterPrev.uri = ""
    end if
    if m.heroPosterPrevFadeOutAnim <> invalid then m.heroPosterPrevFadeOutAnim.control = "stop"
end sub

function HeroPosterUri() as string
    if m.heroPosterLoader <> invalid then return StringOf(m.heroPosterLoader.uri)
    if m.heroPoster = invalid then return ""
    return StringOf(m.heroPoster.uri)
end function

sub HeroSetPosterUri(uri as string)
    if m.heroPosterLoader <> invalid
        m.heroPosterLoader.uri = uri
    else if m.heroPoster <> invalid
        m.heroPoster.uri = uri
    end if
end sub

function HeroPosterReady(uri = "" as string) as boolean
    if uri <> "" and HeroPosterUri() <> uri then return false
    if m.heroPosterLoader <> invalid
        return m.heroPosterLoader.ready = true or StringOf(m.heroPosterLoader.status) = "ready"
    end if
    if m.heroPoster = invalid then return false
    return StringOf(m.heroPoster.loadStatus) = "ready"
end function

function HeroPosterFailed(uri = "" as string) as boolean
    if uri <> "" and HeroPosterUri() <> uri then return false
    if m.heroPosterLoader <> invalid
        return StringOf(m.heroPosterLoader.status) = "failed"
    end if
    if m.heroPoster = invalid then return false
    return StringOf(m.heroPoster.loadStatus) = "failed"
end function

function HeroPosterStatus(uri = "" as string) as string
    if uri <> "" and HeroPosterUri() <> uri then return ""
    if m.heroPosterLoader <> invalid then return StringOf(m.heroPosterLoader.status)
    if m.heroPoster = invalid then return ""
    return StringOf(m.heroPoster.loadStatus)
end function

function HeroLogoUri() as string
    if m.heroLogoLoader <> invalid then return StringOf(m.heroLogoLoader.uri)
    if m.heroLogo = invalid then return ""
    return StringOf(m.heroLogo.uri)
end function

sub HeroSetLogoUri(uri as string)
    if m.heroLogoLoader <> invalid
        m.heroLogoLoader.uri = uri
    else if m.heroLogo <> invalid
        m.heroLogo.uri = uri
    end if
end sub

function HeroLogoReady(uri = "" as string) as boolean
    if uri <> "" and HeroLogoUri() <> uri then return false
    if m.heroLogoLoader <> invalid
        return m.heroLogoLoader.ready = true or StringOf(m.heroLogoLoader.status) = "ready"
    end if
    if m.heroLogo = invalid then return false
    return StringOf(m.heroLogo.loadStatus) = "ready"
end function

function HeroLogoFailed(uri = "" as string) as boolean
    if uri <> "" and HeroLogoUri() <> uri then return false
    if m.heroLogoLoader <> invalid
        return StringOf(m.heroLogoLoader.status) = "failed"
    end if
    if m.heroLogo = invalid then return false
    return StringOf(m.heroLogo.loadStatus) = "failed"
end function

function HeroLogoStatus(uri = "" as string) as string
    if uri <> "" and HeroLogoUri() <> uri then return ""
    if m.heroLogoLoader <> invalid then return StringOf(m.heroLogoLoader.status)
    if m.heroLogo = invalid then return ""
    return StringOf(m.heroLogo.loadStatus)
end function

sub HeroSetFillUri(uri as string)
    if m.heroFill <> invalid and m.heroFill.uri <> uri then m.heroFill.uri = uri
    if m.heroFill1 <> invalid and m.heroFill1.uri <> uri then m.heroFill1.uri = uri
    if m.heroFill2 <> invalid and m.heroFill2.uri <> uri then m.heroFill2.uri = uri
end sub

function HeroRequestUri(source as dynamic) as string
    src = StringOf(source)
    if src = "" then return ""
    return ProxyImageUri(src)
end function


sub HeroSetFillVisible(visible as boolean)
    if m.heroFill <> invalid then m.heroFill.visible = visible
    if m.heroFill1 <> invalid then m.heroFill1.visible = visible
    if m.heroFill2 <> invalid then m.heroFill2.visible = visible
end sub

sub HeroStopPosterPrevFade(clearNode = true as boolean)
    if m.heroPosterPrevFadeOutAnim <> invalid then m.heroPosterPrevFadeOutAnim.control = "stop"
    if m.heroPosterPrev = invalid then return
    m.heroPosterPrev.opacity = 0
    m.heroPosterPrev.visible = false
    if clearNode then m.heroPosterPrev.uri = ""
end sub

sub HeroPreparePosterCrossfade(newRequestUri as string)
    ' Keep previous ready hero image on a secondary poster while the next loads/fades in.
    ' This avoids blank gaps without decoding multiple new images at once.
    if m.heroPosterPrev = invalid or m.heroPoster = invalid then return
    if newRequestUri = "" then return
    currUri = HeroPosterUri()
    if currUri = "" or currUri = newRequestUri then return
    if not HeroPosterReady(currUri) then return

    HeroStopPosterPrevFade(false)
    m.heroPosterPrev.uri = currUri
    m.heroPosterPrev.opacity = 1
    m.heroPosterPrev.visible = true
    if m.heroPosterPrevFadeOutAnim <> invalid
        m.heroPosterPrevFadeOutAnim.control = "start"
    else
        HeroStopPosterPrevFade(true)
    end if
end sub

sub HeroOnPosterPrevFadeOutState()
    if m.heroPosterPrevFadeOutAnim = invalid then return
    if m.heroPosterPrevFadeOutAnim.state <> "stopped" then return
    HeroStopPosterPrevFade(true)
end sub

sub HeroClear()
    m.heroFocusKey = ""
    m.heroLogoUri = ""
    m.heroLogoGraceUri = ""
    m.heroLogoFallbackUri = ""
    if m.heroTitleGrace <> invalid then m.heroTitleGrace.control = "stop"
    if m.heroPosterFadeAnim <> invalid then m.heroPosterFadeAnim.control = "stop"
    HeroStopPosterPrevFade(true)
    m.heroPosterPendingUri = ""
    m.heroPosterSourceUri = ""
    HeroSetPosterUri("")
    if m.heroPoster <> invalid
        m.heroPoster.opacity = 1
        m.heroPoster.visible = false
    end if
    HeroSetFillUri("")
    HeroSetFillVisible(false)
    HeroSetLogoUri("")
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
' hero. background falls back to poster when no dedicated background art exists
' unless posterFallback is false (Home prefers no backdrop over a stretched
' poster). fallbackMetaType is used when the meta carries no type of its own
' (catalog context).
sub HeroRender(meta as object, fallbackMetaType = "" as string, posterFallback = true as boolean)
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
    if description.Len() > 220 then description = Left(description, 217) + "..."

    logo = StringOf(meta.logo)
    background = StringOf(meta.background)
    if background = "" and posterFallback then background = StringOf(meta.poster)
    currentLogoUri = HeroLogoUri()
    currentLogoReady = currentLogoUri <> "" and currentLogoUri = m.heroLogoUri and HeroLogoReady(m.heroLogoUri)
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
        m.heroPosterSourceUri = ""
        m.heroPosterPendingUri = ""
        if m.heroPosterFadeAnim <> invalid then m.heroPosterFadeAnim.control = "stop"
        HeroStopPosterPrevFade(true)
        if m.heroPoster <> invalid then m.heroPoster.opacity = 1
        HeroSetPosterUri("")
        if m.heroPoster <> invalid then m.heroPoster.visible = false
        HeroSetFillUri("")
        HeroSetFillVisible(false)
    else
        if background <> m.heroPosterSourceUri
            m.heroPosterSourceUri = background
        end if
        requestUri = HeroRequestUri(background)
        currentPosterUri = HeroPosterUri()
        if currentPosterUri <> requestUri
            HeroPreparePosterCrossfade(requestUri)
            m.heroPosterPendingUri = requestUri
            if m.heroPosterFadeAnim <> invalid then m.heroPosterFadeAnim.control = "stop"
            if m.heroPoster <> invalid then m.heroPoster.opacity = 0
            HeroSetPosterUri(requestUri)
            if m.heroPoster <> invalid then m.heroPoster.visible = true
            HeroSetFillUri(requestUri)
            HeroSetFillVisible(true)
        else
            m.heroPosterPendingUri = requestUri
            if m.heroPoster <> invalid then m.heroPoster.visible = true
            HeroSetFillUri(requestUri)
            HeroSetFillVisible(true)
            if HeroPosterReady(requestUri) or HeroPosterFailed(requestUri)
                if m.heroPosterFadeAnim <> invalid then m.heroPosterFadeAnim.control = "stop"
                if m.heroPoster <> invalid then m.heroPoster.opacity = 1
            end if
        end if
    end if

    if logo = ""
        m.heroLogoUri = ""
        m.heroLogoGraceUri = ""
        m.heroLogoFallbackUri = ""
        if m.heroTitleGrace <> invalid then m.heroTitleGrace.control = "stop"
        HeroSetLogoUri("")
        HeroApplyLayout("title", true)
        return
    end if

    if sameLogoReady
        m.heroLogoGraceUri = ""
        m.heroLogoFallbackUri = ""
        if m.heroTitleGrace <> invalid then m.heroTitleGrace.control = "stop"
        if m.heroLogo <> invalid then m.heroLogo.visible = true
        if m.heroTitle <> invalid then m.heroTitle.visible = false
        return
    end if

    logoChanged = logo <> m.heroLogoUri
    if logoChanged
        m.heroLogoUri = logo
        m.heroLogoGraceUri = ""
        m.heroLogoFallbackUri = ""
        if m.heroTitleGrace <> invalid then m.heroTitleGrace.control = "stop"
        HeroSetLogoUri(logo)
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
        if m.heroLogo <> invalid then m.heroLogo.visible = false
        if m.heroTitle <> invalid then m.heroTitle.visible = false
    else
        HeroApplyLayout("title", false)
    end if
end sub

sub HeroOnPosterStatus()
    if m.heroPoster = invalid then return
    if HeroPosterUri() <> m.heroPosterPendingUri then return
    if HeroPosterReady(m.heroPosterPendingUri)
        if m.heroPosterFadeAnim <> invalid
            m.heroPosterFadeAnim.control = "stop"
            m.heroPoster.opacity = 0
            m.heroPosterFadeAnim.control = "start"
        else
            m.heroPoster.opacity = 1
        end if
    else if HeroPosterFailed(m.heroPosterPendingUri)
        if m.heroPosterFadeAnim <> invalid then m.heroPosterFadeAnim.control = "stop"
        m.heroPoster.opacity = 1
    end if
end sub

sub HeroOnLogoStatus()
    if HeroLogoUri() <> m.heroLogoUri then return
    if HeroLogoReady(m.heroLogoUri)
        if m.heroTitleGrace <> invalid then m.heroTitleGrace.control = "stop"
        m.heroLogoGraceUri = ""
        m.heroLogoFallbackUri = ""
        HeroFitLogo()
    else if HeroLogoFailed(m.heroLogoUri)
        if m.heroTitleGrace <> invalid then m.heroTitleGrace.control = "stop"
        m.heroLogoGraceUri = ""
        m.heroLogoFallbackUri = m.heroLogoUri
        HeroShowTitleFallback()
    end if
end sub

sub HeroOnTitleGraceFire()
    if m.heroLogoUri = "" then return
    if HeroLogoUri() <> m.heroLogoUri then return
    if HeroLogoReady(m.heroLogoUri) then return
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
    m.heroLogo.translation = [162, 48]
    m.heroLogo.width = 820
    m.heroLogo.height = 460
    m.heroMeta.translation = [166, 192]
    m.heroRating.translation = [166, 232]
    m.heroGenres.translation = [166, 283]
    m.heroDescription.translation = [166, 333]
    m.heroDescription.width = 620
    m.heroDescription.height = 185
end sub

sub HeroFitLogo()
    fit = HeroFit(m.heroLogo.bitmapWidth, m.heroLogo.bitmapHeight)
    if fit = invalid then return
    logoWidth = fit.width
    logoHeight = fit.height

    m.heroLogo.width = logoWidth
    m.heroLogo.height = logoHeight
    m.heroLayoutMode = "wide"
    m.heroLogo.translation = [162, 46 + Int((190 - logoHeight) / 2)]
    m.heroMeta.translation = [166, 250]
    m.heroRating.translation = [166, 292]
    m.heroGenres.translation = [166, 336]
    m.heroDescription.translation = [166, 378]
    m.heroDescription.width = 620
    m.heroDescription.height = 175
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
