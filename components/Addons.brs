' The Addons screen, owning its whole visible region: the chip row of filters and
' actions, the card list, and the detail panel. It keeps its own focus and handles
' its own keys, so none of its internals route through MainScene's flat onKeyEvent
' (the same contract the Settings component uses).
'
' Division of labour:
'   - up / down   the MarkupList moves focus natively. At the top row UP bubbles
'                 out and MainScene directs it to the top bar or back into the
'                 chip row.
'   - left/right  on the chip row cycle the focused chip; on the card list they
'                 bubble out so MainScene can move to the nav rail.
'   - OK          fires ItemSelected natively for a card; on a chip it maps the
'                 chip to { type, payload } and publishes it as the action field.
'   - back        returned false when on the card list so MainScene owns leaving
'                 the screen; on the chip row it moves focus back to the list.
'
' The data the screen renders is pushed in by MainScene as the state field
' (MainScene is the source of truth and owns all fetching, persistence and the
' scene-level dialogs); this component never mutates app state itself, only
' reports actions. The focus escapes that target MainScene-owned chrome (the top
' bar and nav rail) are reported as actions too.

sub init()
    m.list = m.top.FindNode("addonList")

    m.addonChipBgs = []
    m.addonChipLabels = []
    for index = 0 to 4
        m.addonChipBgs.Push(m.top.FindNode("addonChip" + index.ToStr() + "Bg"))
        m.addonChipLabels.Push(m.top.FindNode("addonChip" + index.ToStr() + "Label"))
    end for
    m.detailEyebrow = m.top.FindNode("addonDetailEyebrow")
    m.detailTitle = m.top.FindNode("addonDetailTitle")
    m.detailValue = m.top.FindNode("addonDetailValue")
    m.detailHint = m.top.FindNode("addonDetailHint")
    m.detailSource = m.top.FindNode("addonDetailSource")
    m.detailActionPill = m.top.FindNode("addonDetailActionPill")
    m.detailAction = m.top.FindNode("addonDetailAction")

    m.list.ObserveField("itemFocused", "onItemFocused")
    m.list.ObserveField("itemSelected", "onItemSelected")

    m.addonChipIndex = -1
    m.addonFocusIndex = 0
    m.addonEntries = []
    m.state = {}

    m.top.visible = false
end sub

' MainScene pushed a fresh set of data (filter, query, installed addons, catalog).
' Store it and re-render. The render is focus-neutral: it never steals focus from
' the chip row or resets the cursor, so a background catalog response or a filter
' change drawn from a focused chip keeps the user where they are.
sub onStateChanged()
    previousFilter = addonFilter()
    m.state = m.top.state
    if previousFilter <> addonFilter() and previousFilter <> ""
        ' Switching Installed/All is a fresh list, so the cursor starts at the top.
        m.addonFocusIndex = 0
    end if
    RenderAddons()
end sub

' MainScene asked the screen to take focus (having already made it visible and
' pushed state). Hand focus to the inner list so up/down and OK work.
sub onFocusRequest()
    FocusAddonList()
end sub

' MainScene routes the user up into the chip row from the card list. Highlight
' the row and hand keyboard focus to the root so the chip key ring takes over:
' Left/Right move through chips, Up leaves to the top bar, Down/back return to
' the list. Left/Right also work directly from the list via bubbling below, so
' the chips are reachable from either focus state.
sub FocusChips()
    if m.addonChipIndex < 0 then m.addonChipIndex = 0
    UpdateAddonChips()
    m.list.SetFocus(false)
    m.top.SetFocus(true)
end sub

sub RenderAddons()
    entries = BuildAddonEntries()
    m.addonEntries = entries

    content = CreateObject("roSGNode", "ContentNode")
    for each entry in entries
        child = content.CreateChild("AddonCardContent")
        child.rowKind = entry.kind
        ' Manifest text: name, version, types and description are passed through
        ' exactly as the add-on author wrote them.
        child.title = entry.name
        child.description = entry.description
        child.version = entry.version
        child.types = entry.types
        child.logoUri = entry.logo
        child.badge = entry.badge
        child.badgeKind = entry.badgeKind
        child.selectable = entry.actionType <> "none"
    end for

    ' A background collection response re-renders the screen underneath the user,
    ' so a refresh keeps whatever card was focused.
    targetIndex = m.addonFocusIndex
    if entries.Count() = 0
        targetIndex = 0
    else if targetIndex >= entries.Count()
        targetIndex = entries.Count() - 1
    end if
    if targetIndex < 0 then targetIndex = 0
    m.addonFocusIndex = targetIndex
    m.list.content = content
    m.list.JumpToItem = targetIndex
    UpdateAddonDetail(targetIndex)

    UpdateAddonChips()
    EmitScreenInfo()
end sub

' --- intercepted keys -------------------------------------------------------

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    ' Left/Right move through the chip row whether the chip row itself is
    ' focused or the card list below it is (the MarkupList bubbles these up).
    if key = "left"
        if m.addonChipIndex > 0
            m.addonChipIndex = m.addonChipIndex - 1
            UpdateAddonChips()
            return true
        end if
        ' Leftmost chip: fall out of the toolbar to the nav rail.
        BlurChips()
        m.top.action = { type: "focusNavRail" }
        return true
    else if key = "right"
        if m.addonChipIndex < 0
            ' Enter the chips from the card list: highlight chip 0 and move
            ' keyboard focus to the chips so there is exactly ONE focus target.
            FocusChips()
            return true
        else if m.addonChipIndex < AddonChips().Count() - 1
            m.addonChipIndex = m.addonChipIndex + 1
            UpdateAddonChips()
            return true
        end if
    end if

    ' The remaining keys only make sense once the chip row has focus.
    if m.addonChipIndex >= 0
        if key = "OK"
            ActivateAddonChip(m.addonChipIndex)
            return true
        else if key = "down" or key = "back"
            FocusAddonList()
            return true
        else if key = "up"
            ' Same ladder as every other screen: the row above the toolbar is the
            ' top bar, which MainScene owns and focuses.
            BlurChips()
            m.top.action = { type: "focusTopBar" }
            return true
        end if
    end if

    ' On the card list: up/down are handled natively by the MarkupList; left
    ' reaches the nav rail and back leaves the screen, both owned by MainScene.
    return false
end function

' --- chip row ---------------------------------------------------------------

' The toolbar. The two filters and the three actions share one focus ring, which
' is what makes the row reachable with UP from the card list.
function AddonChips() as object
    return [
        AddonChip(TrText("addons.filter.installed"), "addonFilterInstalled")
        AddonChip(TrText("addons.filter.all"), "addonFilterAll")
        AddonChip(TrText("addons.add"), "addAddon")
        AddonChip(TrText("addons.search"), "addonSearch")
        ' Reload lived in the removed Streaming settings tab; the Addons screen is
        ' the only place installed manifests are managed now.
        AddonChip(TrText("addons.reload"), "reloadAddons")
    ]
end function

function AddonChip(label as string, actionType as string) as object
    return {
        label: label
        actionType: actionType
    }
end function

sub UpdateAddonChips()
    chips = AddonChips()
    for index = 0 to m.addonChipBgs.Count() - 1
        background = m.addonChipBgs[index]
        label = m.addonChipLabels[index]
        if background <> invalid and label <> invalid and index < chips.Count()
            chip = chips[index]
            label.text = chip.label
            focused = index = m.addonChipIndex
            selected = false
            if chip.actionType = "addonFilterInstalled" then selected = addonFilter() = "installed"
            if chip.actionType = "addonFilterAll" then selected = addonFilter() = "all"

            if chip.actionType = "addAddon"
                ' Stremio reserves one green primary action for adding an add-on.
                if focused
                    background.color = "0x3FCB96FF"
                else
                    background.color = "0x2E9E76FF"
                end if
                label.color = "0xFFFFFFFF"
            else if focused
                background.color = "0x7657FFFF"
                label.color = "0xFFFFFFFF"
            else if selected
                background.color = "0x2A2450FF"
                label.color = "0xC7BCFFFF"
            else
                background.color = "0x1B1934FF"
                label.color = "0xA9A6B8FF"
            end if
        end if
    end for
end sub

sub BlurChips()
    m.addonChipIndex = -1
    UpdateAddonChips()
end sub

sub FocusAddonList()
    BlurChips()
    m.list.SetFocus(true)
end sub

sub ActivateAddonChip(index as integer)
    chips = AddonChips()
    if index < 0 or index >= chips.Count() then return
    actionType = chips[index].actionType
    if actionType = "addonFilterInstalled" or actionType = "addonFilterAll"
        m.top.action = { type: actionType, payload: invalid }
    else
        m.top.action = { type: actionType, payload: invalid }
    end if
end sub

' --- card list --------------------------------------------------------------

sub onItemFocused(event as object)
    index = event.GetData()
    if index < 0 or index >= m.addonEntries.Count() then return
    m.addonFocusIndex = index
    UpdateAddonDetail(index)
end sub

sub onItemSelected(event as object)
    index = event.GetData()
    if index < 0 or index >= m.addonEntries.Count() then return
    entry = m.addonEntries[index]
    if entry.actionType = "none" then return
    m.top.action = {
        type: entry.actionType
        payload: entry.payload
    }
end sub

' --- detail panel -----------------------------------------------------------

sub UpdateAddonDetail(index as integer)
    if addonFilter() = "all"
        m.detailEyebrow.text = UCase(TrText("addons.filter.all"))
    else
        m.detailEyebrow.text = UCase(TrText("addons.filter.installed"))
    end if

    if index < 0 or index >= m.addonEntries.Count()
        ClearAddonDetail()
        return
    end if

    entry = m.addonEntries[index]
    if entry.kind = "message"
        ClearAddonDetail()
        m.detailHint.text = entry.description
        return
    end if

    m.detailTitle.text = entry.name
    value = entry.version
    if entry.types <> ""
        if value <> "" then value = value + "    "
        value = value + entry.types
    end if
    m.detailValue.text = value
    m.detailHint.text = entry.description
    m.detailSource.text = entry.source
    m.detailAction.text = AddonDetailActionLabel(entry)
    m.detailActionPill.visible = true
end sub

sub ClearAddonDetail()
    m.detailTitle.text = ""
    m.detailValue.text = ""
    m.detailHint.text = ""
    m.detailSource.text = ""
    m.detailAction.text = ""
    m.detailActionPill.visible = false
end sub

' What OK does on the focused card. Stremio puts Uninstall and Share on the card
' itself; a remote cannot move sideways inside a list row, so the panel advertises
' them and OK opens the dialog that carries them.
function AddonDetailActionLabel(entry as object) as string
    if entry.actionType = "installedAddon"
        return "OK    " + UCase(TrText("common.share")) + "  /  " + UCase(TrText("common.uninstall"))
    end if
    return "OK    " + UCase(TrText("common.install"))
end function

' --- screen info (shared chrome) ---------------------------------------------

' Keep MainScene's shared chrome (the header and hero labels, which live outside
' this component) in sync with the active filter and search query.
sub EmitScreenInfo()
    hero = TrText("addons.hero.installed")
    if searchQuery() <> ""
        hero = TrFormat("addons.searchResult", searchQuery())
    else if addonFilter() = "all"
        hero = TrText("addons.hero.all")
    end if
    m.top.screenInfo = {
        title: TrText("addons.title")
        subtitle: TrText("addons.footer")
        heroTitle: TrText("addons.title")
        heroDescription: hero
    }
end sub

' --- state accessors ----------------------------------------------------------

function addonFilter() as string
    if m.state.DoesExist("addonFilter") then return m.state.addonFilter
    return "installed"
end function

function searchQuery() as string
    if m.state.DoesExist("addonSearchQuery") then return m.state.addonSearchQuery
    return ""
end function

function installedAddons() as object
    if m.state.DoesExist("addons") then return m.state.addons
    return []
end function

function catalogAddons() as object
    if m.state.DoesExist("catalog") then return m.state.catalog
    return []
end function

function catalogLoaded() as boolean
    if m.state.DoesExist("catalogLoaded") then return m.state.catalogLoaded
    return false
end function

function catalogRequestActive() as boolean
    if m.state.DoesExist("catalogRequestActive") then return m.state.catalogRequestActive
    return false
end function

' --- entry building -----------------------------------------------------------

' One row of the Addons list. The Installed filter lists configured manifests;
' the All filter lists the built-in catalog followed by whatever the Stremio
' collection returned.
function BuildAddonEntries() as object
    entries = []
    query = LCase(searchQuery())

    if addonFilter() = "installed"
        if installedAddons().Count() = 0
            entries.Push(AddonMessageEntry(TrText("addons.empty"), "addAddon"))
            return entries
        end if
        for index = 0 to installedAddons().Count() - 1
            entry = InstalledAddonEntry(index)
            if AddonEntryMatches(entry, query) then entries.Push(entry)
        end for
        if entries.Count() = 0 then entries.Push(AddonMessageEntry(TrText("addons.empty"), "addAddon"))
        return entries
    end if

    for each addon in DefaultAddonCatalog()
        entry = CatalogAddonEntry(addon, "builtinAddon")
        if AddonEntryMatches(entry, query) then entries.Push(entry)
    end for

    if catalogLoaded()
        for index = 0 to catalogAddons().Count() - 1
            entry = CatalogAddonEntry(catalogAddons()[index], "remoteAddon")
            if AddonEntryMatches(entry, query) then entries.Push(entry)
            ' Unfiltered browsing is capped so the list stays navigable; a search
            ' is allowed to reach the whole collection.
            if query = "" and index >= 24 then exit for
        end for
    else if catalogRequestActive()
        entries.Push(AddonMessageEntry(TrText("addons.loadingCollection"), "none"))
    else
        entries.Push(AddonMessageEntry(TrText("addons.loadCollection"), "addonFilterAll"))
    end if

    return entries
end function

function AddonEntry(kind as string, actionType as string, payload as dynamic) as object
    return {
        kind: kind
        actionType: actionType
        payload: payload
        name: ""
        version: ""
        types: ""
        description: ""
        logo: ""
        badge: ""
        badgeKind: "available"
        source: ""
    }
end function

' The empty, loading and "load the collection" rows share the card slot so the
' screen never falls back to a bare label.
function AddonMessageEntry(text as string, actionType as string) as object
    entry = AddonEntry("message", actionType, invalid)
    entry.description = text
    return entry
end function

function InstalledAddonEntry(index as integer) as object
    addon = installedAddons()[index]
    manifest = addon.manifest
    entry = AddonEntry("addon", "installedAddon", index)
    entry.name = SafeString(manifest, "name")
    entry.version = AddonVersionLabel(manifest)
    entry.types = AddonTypesLabel(manifest)
    entry.description = ReplaceNewlines(SafeString(manifest, "description"))
    entry.logo = SafeString(manifest, "logo")
    entry.badge = TrText("addons.filter.installed")
    entry.badgeKind = "installed"
    entry.source = AddonSourceLabel(SafeString(addon, "url"))
    return entry
end function

function CatalogAddonEntry(addon as object, actionType as string) as object
    manifest = addon.manifest
    entry = AddonEntry("addon", actionType, addon)
    entry.name = SafeString(manifest, "name")
    entry.version = AddonVersionLabel(manifest)
    entry.types = SafeString(addon, "summaryTypes")
    if entry.types = "" then entry.types = AddonTypesLabel(manifest)
    entry.description = ReplaceNewlines(SafeString(manifest, "description"))
    entry.logo = SafeString(manifest, "logo")
    entry.source = AddonSourceLabel(SafeString(addon, "url"))
    if IsAddonInstalled(SafeString(manifest, "id"))
        entry.badge = TrText("addons.filter.installed")
        entry.badgeKind = "installed"
    else
        entry.badge = TrText("common.install")
        entry.badgeKind = "available"
    end if
    return entry
end function

function IsAddonInstalled(addonId as string) as boolean
    if addonId = "" then return false
    for each installed in installedAddons()
        if SafeString(installed.manifest, "id") = addonId then return true
    end for
    return false
end function

function AddonVersionLabel(manifest as object) as string
    version = SafeString(manifest, "version")
    if version = "" then return ""
    return "v." + version
end function

function AddonEntryMatches(entry as object, query as string) as boolean
    if query = "" then return true
    haystack = LCase(entry.name + " " + entry.types + " " + entry.description)
    return Instr(1, haystack, query) > 0
end function

function DefaultAddonCatalog() as object
    return [
        AddonCatalogEntry("https://v3-cinemeta.strem.io/manifest.json", "com.linvo.cinemeta", "Cinemeta", "3.0.14", "Movie & Series", "The official addon for movie and series catalogs")
        AddonCatalogEntry("https://v3-channels.strem.io/manifest.json", "org.stremio.youtube", "YouTube", "1.30.7", "Channel", "Watch your favourite YouTube channels ad-free")
        AddonCatalogEntry("https://watchhub.strem.io/manifest.json", "com.stremio.watchhub", "WatchHub", "1.15.0", "Movie & Series", "Find where to stream movies and shows")
        AddonCatalogEntry("https://caching.stremio.net/publicdomainmovies.now.sh/manifest.json", "org.publicdomainmovies", "Public Domain Movies", "1.0.0", "Movie", "Torrents for public domain movies")
        AddonCatalogEntry("https://opensubtitles-v3.strem.io/manifest.json", "org.stremio.opensubtitlesv3", "OpenSubtitles v3", "1.0.0", "Movie & Series", "OpenSubtitles v3 Addon for Stremio")
        AddonCatalogEntry("", "com.stremio.localfiles", "Local Files (without catalog support)", "1.10.0", "Movie, Series & Other", "Finds playable local files on devices that support local file access")
    ]
end function

function AddonCatalogEntry(url as string, id as string, name as string, version as string, types as string, description as string) as object
    return {
        url: url
        manifest: {
            id: id
            name: name
            version: version
            description: description
            types: types.Split(" & ")
            resources: []
            catalogs: []
        }
        summaryTypes: types
    }
end function
