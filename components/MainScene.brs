sub init()
    m.uiRoot = m.top.FindNode("uiRoot")
    m.uiScaleGroup = m.top.FindNode("uiScaleGroup")
    m.uiScaleMessage = m.top.FindNode("uiScaleMessage")
    m.uiScaleFill = m.top.FindNode("uiScaleFill")
    m.uiScaleHandle = m.top.FindNode("uiScaleHandle")
    m.uiScaleValue = m.top.FindNode("uiScaleValue")
    m.coffeeGroup = m.top.FindNode("coffeeGroup")
    m.coffeeTitle = m.top.FindNode("coffeeTitle")
    m.coffeeMessage = m.top.FindNode("coffeeMessage")
    m.coffeeScanHint = m.top.FindNode("coffeeScanHint")
    m.coffeeDismissHint = m.top.FindNode("coffeeDismissHint")
    m.coffeeSwallowOk = false
    m.coffeeReturnedFromTopBar = false
    m.supportChipBg = m.top.FindNode("supportChipBg")
    m.supportChipLabel = m.top.FindNode("supportChipLabel")
    m.topBarFocus = -1
    m.catalogList = m.top.FindNode("catalogList")
    m.discoverGrid = m.top.FindNode("discoverGrid")
    m.navList = m.top.FindNode("navList")
    m.searchBar = m.top.FindNode("searchBar")
    m.searchPrompt = m.top.FindNode("searchPrompt")
    m.primaryTitle = m.top.FindNode("primaryTitle")
    m.primarySubtitle = m.top.FindNode("primarySubtitle")
    m.discoverFilterGroup = m.top.FindNode("discoverFilterGroup")
    m.discoverTypeLabel = m.top.FindNode("discoverTypeLabel")
    m.discoverCatalogLabel = m.top.FindNode("discoverCatalogLabel")
    m.discoverGenreLabel = m.top.FindNode("discoverGenreLabel")
    m.discoverTypeFocus = m.top.FindNode("discoverTypeFocus")
    m.discoverCatalogFocus = m.top.FindNode("discoverCatalogFocus")
    m.discoverGenreFocus = m.top.FindNode("discoverGenreFocus")
    m.primaryInfoGroup = m.top.FindNode("primaryInfoGroup")
    m.primaryInfoList = m.top.FindNode("primaryInfoList")
    m.calendarGroup = m.top.FindNode("calendarGroup")
    m.calendarList = m.top.FindNode("calendarList")
    m.calendarDetailPoster = m.top.FindNode("calendarDetailPoster")
    m.calendarDetailEyebrow = m.top.FindNode("calendarDetailEyebrow")
    m.calendarDetailTitle = m.top.FindNode("calendarDetailTitle")
    m.calendarDetailMeta = m.top.FindNode("calendarDetailMeta")
    m.calendarDetailDescription = m.top.FindNode("calendarDetailDescription")
    m.calendarDetailActionPill = m.top.FindNode("calendarDetailActionPill")
    m.calendarDetailAction = m.top.FindNode("calendarDetailAction")
    m.settingsScreen = m.top.FindNode("settingsScreen")
    m.addonsScreen = m.top.FindNode("addonsScreen")
    m.heroTitle = m.top.FindNode("heroTitle")
    m.heroDescription = m.top.FindNode("heroDescription")
    m.homeGroup = m.top.FindNode("homeGroup")
    m.episodeGroup = m.top.FindNode("episodeGroup")
    m.episodeBackground = m.top.FindNode("episodeBackground")
    m.episodeSeriesTitle = m.top.FindNode("episodeSeriesTitle")
    m.episodeSeriesMeta = m.top.FindNode("episodeSeriesMeta")
    m.episodeSeriesDescription = m.top.FindNode("episodeSeriesDescription")
    m.seasonGrid = m.top.FindNode("seasonGrid")
    m.episodeList = m.top.FindNode("episodeList")
    m.choiceGroup = m.top.FindNode("choiceGroup")
    m.choiceTitle = m.top.FindNode("choiceTitle")
    m.choiceList = m.top.FindNode("choiceList")
    m.streamList = m.top.FindNode("streamList")
    m.noStreamsGroup = m.top.FindNode("noStreamsGroup")
    m.noStreamsPoster = m.top.FindNode("noStreamsPoster")
    m.noStreamsMessage = m.top.FindNode("noStreamsMessage")
    m.noStreamsHint = m.top.FindNode("noStreamsHint")
    m.linkPollTimer = m.top.FindNode("linkPollTimer")
    m.spinner = m.top.FindNode("spinner")
    m.statusLabel = m.top.FindNode("statusLabel")
    m.statusBackdrop = m.top.FindNode("statusBackdrop")
    m.setupAddress = m.top.FindNode("setupAddress")
    m.video = m.top.FindNode("video")

    ' Tab identity is separate from the tab label: the label is translated, the id
    ' is not. Deriving one from the other would break navigation in every language
    ' but English.
    m.navIds = ["board", "discover", "library", "calendar", "addons", "settings"]
    m.activeTab = "board"
    m.navIndex = 0
    m.settingsTabIndex = 0
    ' m.settingsTabIndex is mirrored from the Settings component's screenInfo so
    ' the scene's * / options handler knows which settings section it is on.
    m.discoverFilterFocus = -1
    m.addonStore = CreateAddonStore()
    m.libraryStore = CreateLibraryStore()
    m.authStore = CreateAuthStore()
    m.catalogStore = CreateCatalogStore()
    ' Calendar data, its metadata round-trips, and the rows they produce live
    ' in one store. MainScene keeps only the calendar view: the list, its
    ' focus/echo handling, and the detail panel.
    m.calendarStore = CreateCalendarStore()
    m.calendarRows = []
    m.calendarFocusIndex = 0
    ' Index of a calendar row whose itemFocused notification this code caused; -1
    ' when the next notification is expected to be a genuine user move.
    m.calendarSuppressIndex = -1
    m.primaryActions = []
    m.libraryRows = [[]]
    m.catalogRows = m.catalogStore.getBoardRows()
    m.catalogNames = m.catalogStore.getBoardNames()
    m.selectedItem = invalid
    m.episodes = []
    m.visibleEpisodes = []
    m.seasons = []
    m.selectedSeasonIndex = -1
    m.seriesMeta = invalid
    m.streams = []
    m.selectedEpisodeIndex = 0
    m.selectedStreamIndex = 0
    m.streamReturnMode = "home"
    m.streamRequestSequence = 0
    m.activeStreamRequestId = ""
    m.streamRequestActive = false
    m.pendingStreamRequests = 0
    m.completedStreamRequests = 0
    m.streamRequestErrors = []
    m.addonLoadPending = 0
    m.addonReloadActive = false
    m.pendingStreamLookup = invalid
    m.subtitleRequestSequence = 0
    m.activeSubtitleRequestId = ""
    m.subtitleRequestActive = false
    m.pendingSubtitleRequests = 0
    m.completedSubtitleRequests = 0
    m.subtitleRequestErrors = []
    m.playbackContentType = ""
    m.playbackContentId = ""
    m.pendingStream = invalid
    m.subtitles = []
    m.pendingNextEpisode = invalid
    m.suppressVideoReturn = false
    m.playbackReturnMode = "home"
    m.choiceMode = ""
    m.choiceReturnMode = "home"
    m.episodeReturnMode = "home"
    m.episodeRequestActive = false
    m.screenMode = "home"
    m.addonLoadPending = 0
    m.pendingAddonDetails = invalid
    m.installedAddonDetailsIndex = -1
    ' Settings data + its registry persistence (interface, player, subtitle
    ' style, streaming server URL) live in one store. MainScene keeps only the
    ' scene-glue around them: dialogs, HTTP tasks, video pushes, chrome renders.
    m.settingsStore = CreateSettingsStore()
    m.tasks = []
    m.exitVideoDialog = invalid
    m.exitAppDialog = invalid

    m.navList.ObserveField("itemSelected", "onNavSelected")
    m.navList.ObserveField("itemFocused", "onNavFocused")
    m.primaryInfoList.ObserveField("itemSelected", "onPrimaryInfoSelected")
    m.settingsScreen.ObserveField("action", "onSettingsScreenAction")
    m.settingsScreen.ObserveField("screenInfo", "onSettingsScreenInfo")
    ' Addons reports its row activations and its focus escapes to the scene
    ' through the same action/screenInfo pair Settings uses; MainScene dispatches
    ' the row actions (their rows carry manifest payloads) and mirrors the shared
    ' chrome the component does not own.
    m.addonsScreen.ObserveField("action", "onAddonsScreenAction")
    m.addonsScreen.ObserveField("screenInfo", "onAddonsScreenInfo")
    ' Calendar rows carry the same actionType/payload pair, so they dispatch
    ' through the one selection handler as well.
    m.calendarList.ObserveField("itemSelected", "onPrimaryInfoSelected")
    m.calendarList.ObserveField("itemFocused", "onCalendarRowFocused")
    m.catalogList.ObserveField("rowItemFocused", "onCatalogFocused")
    m.catalogList.ObserveField("rowItemSelected", "onCatalogSelected")
    m.discoverGrid.ObserveField("itemFocused", "onDiscoverGridFocused")
    m.discoverGrid.ObserveField("itemSelected", "onDiscoverGridSelected")
    m.choiceList.ObserveField("itemSelected", "onChoiceSelected")
    m.choiceList.ObserveField("itemFocused", "onChoiceFocused")
    m.streamList.ObserveField("itemSelected", "onChoiceSelected")
    m.streamList.ObserveField("itemFocused", "onChoiceFocused")
    m.seasonGrid.ObserveField("itemSelected", "onSeasonSelected")
    m.episodeList.ObserveField("itemSelected", "onEpisodeSelected")
    m.video.ObserveField("state", "onVideoStateChanged")
    m.video.ObserveField("action", "onVideoAction")
    m.video.ObserveField("position", "onVideoPositionChanged")
    m.video.ObserveField("duration", "onVideoDurationChanged")
    m.top.ObserveField("configurationUrl", "onConfigurationUrlChanged")
    m.top.ObserveField("streamingServerUrl", "onStreamingServerUrlChanged")
    m.linkPollTimer.ObserveField("fire", "onLinkPollTimer")

    LoadAddonConfiguration()
    ' Load every stored preference (interface, player, subtitle style, streaming
    ' server) in one go; the store owns the registry.
    m.settingsStore.load()
    ' Must precede the first render: every label below reads the active language.
    SetLocaleLanguage(m.settingsStore.getInterfaceLanguage())
    ApplyStaticChromeText()
    ' The player is built with the scene, so its own init() ran before the stored
    ' language existed. Push it now.
    if m.video <> invalid then m.video.CallFunc("ApplyLocale", invalid)
    ' Must run before anything renders so the first frame is already laid out for
    ' this TV's design resolution.
    ApplyUiScaleSettings()
    LoadStremioAccount()
    InitializePrimaryShell()
    FetchBoardCatalogs()

    m.catalogList.SetFocus(true)
end sub

sub InitializePrimaryShell()
    UpdateNavContent()
    m.primaryActions = []
    ApplySubtitleStyle()
    RenderActiveTab(true)
end sub

' Rebuilt on every language change, so the labels follow the active language.
sub UpdateNavContent()
    content = CreateObject("roSGNode", "ContentNode")
    for each id in m.navIds
        child = content.CreateChild("ContentNode")
        child.title = TrText("nav." + id)
    end for
    m.navList.content = content
    m.navList.JumpToItem = m.navIndex
end sub

sub onNavFocused(event as object)
    index = event.GetData()
    if index >= 0 and index < m.navIds.Count()
        m.navIndex = index
    end if
end sub

sub onNavSelected(event as object)
    index = event.GetData()
    if index < 0 or index >= m.navIds.Count() then return
    tabName = m.navIds[index]
    if tabName = m.activeTab
        FocusActiveContent()
    else
        SetActiveTab(tabName, false)
        m.navList.SetFocus(true)
    end if
end sub

sub SetActiveTab(tabName as string, focusContent as boolean)
    m.activeTab = tabName
    for index = 0 to m.navIds.Count() - 1
        if m.navIds[index] = tabName
            m.navIndex = index
            exit for
        end if
    end for
    m.navList.JumpToItem = m.navIndex
    RenderActiveTab(focusContent)
    if tabName = "discover" and m.catalogStore.discoverRowsEmpty() and not m.catalogStore.isDiscoverRequestActive()
        FetchDiscoverCatalog()
    end if
end sub

' The top bar is the row above every screen's content: the search field and the
' support entry. Like the Discover filter row and the Addons chips, it is not a
' focusable node -- it is drawn from here and driven while the scene holds focus.
function TopBarItemCount() as integer
    return 2
end function

sub UpdateTopBar()
    if m.topBarFocus = 0
        m.searchBar.color = "0x7657FFFF"
        m.searchPrompt.color = "0xFFFFFFFF"
    else
        m.searchBar.color = "0x211F3AFF"
        m.searchPrompt.color = "0x918EA5FF"
    end if

    if m.topBarFocus = 1
        m.supportChipBg.color = "0x7657FFFF"
        m.supportChipLabel.color = "0xFFFFFFFF"
    else
        m.supportChipBg.color = "0x1B1934FF"
        m.supportChipLabel.color = "0xA9A6B8FF"
    end if
end sub

sub FocusTopBar(index as integer)
    m.topBarFocus = index
    UpdateTopBar()
    ' Every content list has to be blurred or it swallows OK and the arrows
    ' before onKeyEvent ever sees them.
    m.catalogList.SetFocus(false)
    m.discoverGrid.SetFocus(false)
    m.settingsScreen.SetFocus(false)
    m.calendarList.SetFocus(false)
    m.addonsScreen.SetFocus(false)
    m.primaryInfoList.SetFocus(false)
    m.top.SetFocus(true)
end sub

sub BlurTopBar()
    m.topBarFocus = -1
    UpdateTopBar()
end sub

sub ActivateTopBarItem(index as integer)
    if index = 0
        BlurTopBar()
        OpenSearch()
    else if index = 1
        m.coffeeReturnedFromTopBar = true
        BlurTopBar()
        OpenCoffeeSupport(false)
    end if
end sub

sub FocusActiveContent()
    if m.settingsScreen.visible
        RequestSettingsFocus()
    else if m.calendarGroup.visible
        m.calendarList.SetFocus(true)
    else if m.addonsScreen.visible
        RequestAddonsFocus()
    else if m.primaryInfoGroup.visible
        m.primaryInfoList.SetFocus(true)
    else if m.activeTab = "discover"
        m.discoverGrid.SetFocus(true)
    else
        m.catalogList.SetFocus(true)
    end if
end sub

sub RenderActiveTab(focusContent as boolean)
    ClearActiveStreamRequest()
    m.screenMode = "home"
    m.homeGroup.visible = true
    m.episodeGroup.visible = false
    m.choiceGroup.visible = false
    m.noStreamsGroup.visible = false
    m.uiScaleGroup.visible = false
    m.coffeeGroup.visible = false
    m.topBarFocus = -1
    UpdateTopBar()
    m.catalogList.visible = false
    m.catalogList.translation = ScaleUiXY(260, 164)
    m.discoverGrid.visible = false
    m.discoverFilterGroup.visible = false
    m.discoverFilterFocus = -1
    UpdateDiscoverFilterFocus()
    m.primaryInfoGroup.visible = false
    m.settingsScreen.visible = false
    m.calendarGroup.visible = false
    m.addonsScreen.visible = false
    m.primaryActions = []

    if m.activeTab = "board"
        RenderBoard(focusContent)
    else if m.activeTab = "discover"
        RenderDiscover(focusContent)
    else if m.activeTab = "library"
        RenderLibrary(focusContent)
    else if m.activeTab = "calendar"
        RenderCalendar(focusContent)
    else if m.activeTab = "addons"
        RenderAddons(focusContent)
    else if m.activeTab = "settings"
        RenderSettings(focusContent)
    end if
end sub

sub RenderBoard(focusContent as boolean)
    m.primaryTitle.text = TrText("nav.board")
    m.primarySubtitle.text = TrText("board.subtitle")
    m.heroTitle.text = TrText("nav.board")
    m.heroDescription.text = TrText("board.hero")
    m.catalogRows = m.catalogStore.getBoardRows()
    m.catalogNames = m.catalogStore.getBoardNames()
    m.catalogList.visible = true
    RebuildCatalog()
    if focusContent then m.catalogList.SetFocus(true)
end sub

sub RenderDiscover(focusContent as boolean)
    m.primaryTitle.text = TrText("nav.discover")
    m.primarySubtitle.text = TrText("discover.subtitle")
    m.heroTitle.text = TrText("nav.discover")
    m.heroDescription.text = TrText("discover.hero")
    m.catalogRows = m.catalogStore.getDiscoverRows()
    m.catalogNames = m.catalogStore.getDiscoverNames()
    m.discoverFilterGroup.visible = true
    m.catalogList.translation = ScaleUiXY(260, 230)
    UpdateDiscoverFilterLabels()
    m.discoverGrid.visible = true
    RebuildDiscoverGrid()
    if focusContent then m.discoverGrid.SetFocus(true)
end sub

sub RenderLibrary(focusContent as boolean)
    m.primaryTitle.text = TrText("nav.library")
    m.primarySubtitle.text = TrText("library.subtitle")
    if not m.authStore.isSignedIn()
        RenderInfoList([
            InfoAction(TrText("library.signedOut.title"), "none", invalid)
            InfoAction(TrText("library.signedOut.benefit1"), "none", invalid)
            InfoAction(TrText("library.signedOut.benefit2"), "none", invalid)
            InfoAction(TrText("library.signedOut.login"), "login", invalid)
        ], focusContent)
        m.heroTitle.text = TrText("nav.library")
        m.heroDescription.text = TrText("library.hero.signedOut")
        return
    end if

    m.libraryRows = []
    m.catalogNames = []
    libraryItems = m.libraryStore.getLibraryItems()
    watchedItems = m.libraryStore.getWatchedItems()
    if libraryItems.Count() > 0
        m.libraryRows.Push(libraryItems)
        m.catalogNames.Push(TrText("library.catalog.lastWatched"))
    end if
    if watchedItems.Count() > 0
        m.libraryRows.Push(watchedItems)
        m.catalogNames.Push(TrText("library.catalog.previouslyWatched"))
    end if
    m.catalogRows = m.libraryRows
    m.catalogList.visible = true
    m.heroTitle.text = TrText("nav.library")
    if libraryItems.Count() = 0 and watchedItems.Count() = 0
        m.heroDescription.text = TrText("library.hero.empty")
    else
        counts = TrText("library.hero.counts")
        counts = LocaleReplace(counts, "{saved}", libraryItems.Count().ToStr())
        counts = LocaleReplace(counts, "{watched}", watchedItems.Count().ToStr())
        m.heroDescription.text = counts
    end if
    RebuildCatalog()
    if focusContent then m.catalogList.SetFocus(true)
end sub

' Calendar is its own screen: a list of dated episode cards beside a detail panel
' that follows focus. It deliberately does not go through RenderInfoList, which
' other screens still use as a plain text list.
sub RenderCalendar(focusContent as boolean)
    m.primaryTitle.text = TrText("calendar.title")
    m.primarySubtitle.text = TrText("calendar.subtitle")
    m.catalogList.visible = false
    m.primaryInfoGroup.visible = false
    m.settingsScreen.visible = false
    m.calendarGroup.visible = true

    m.heroTitle.text = TrText("calendar.title")
    if not m.authStore.isSignedIn()
        m.heroDescription.text = TrText("calendar.hero.signedOut")
        RenderCalendarRows(m.calendarStore.buildSignedOutRows(), focusContent)
        return
    end if

    LoadCalendarEntries()
    actions = m.calendarStore.buildActions(m.libraryStore.getLibraryItems())
    m.heroDescription.text = TrFormat("calendar.hero.count", m.calendarStore.getEntries().Count())
    RenderCalendarRows(actions, focusContent)
end sub

sub RenderCalendarRows(rows as object, focusContent as boolean)
    m.calendarRows = rows
    ' The calendar list shares onPrimaryInfoSelected, which dispatches on
    ' m.primaryActions.
    m.primaryActions = rows

    content = CreateObject("roSGNode", "ContentNode")
    for each row in rows
        child = content.CreateChild("CalendarCardContent")
        child.rowKind = row.kind
        child.title = row.title
        child.dayText = row.dayText
        child.monthText = row.monthText
        child.seriesName = row.seriesName
        ' row.episodeLabel is not copied: the card shows it inside metaText, and
        ' the detail panel reads it off the row rather than off the content node.
        child.metaText = row.metaText
        child.thumbnailUrl = row.thumbnailUrl
        child.accent = row.accent
        child.selectable = CalendarRowSelectable(row)
    end for

    ' A background metadata response re-renders the screen underneath the user,
    ' so a refresh keeps whatever row was focused; entering the tab starts on the
    ' first row that can take focus.
    if rows.Count() = 0
        targetIndex = 0
    else if not focusContent
        targetIndex = m.calendarFocusIndex
        if targetIndex >= rows.Count() then targetIndex = rows.Count() - 1
        if targetIndex < 0 then targetIndex = 0
        if not CalendarRowSelectable(rows[targetIndex])
            targetIndex = NextSelectableCalendarIndex(rows, targetIndex, 1)
        end if
    else
        targetIndex = NextSelectableCalendarIndex(rows, -1, 1)
    end if
    if targetIndex < 0 then targetIndex = 0

    ' Assigning content and JumpToItem both echo back as itemFocused, so the row
    ' this code chose is suppressed once. The Settings component follows the same
    ' pattern; a boolean flag cannot work here because SceneGraph delivers field
    ' notifications on the message loop after the assigning code returns.
    m.calendarFocusIndex = targetIndex
    m.calendarSuppressIndex = targetIndex
    m.calendarList.content = content
    m.calendarList.JumpToItem = targetIndex
    UpdateCalendarDetail(targetIndex)
    if focusContent then m.calendarList.SetFocus(true)
end sub

function CalendarRowSelectable(row as object) as boolean
    if row = invalid then return false
    if row.kind = "header" or row.kind = "message" then return false
    return row.actionType <> "none"
end function

' Finds the next row that can take focus, searching in `direction` first and then
' back the other way, so a list that starts or ends with a caption still lands
' somewhere sensible.
function NextSelectableCalendarIndex(rows as object, fromIndex as integer, direction as integer) as integer
    index = fromIndex + direction
    while index >= 0 and index < rows.Count()
        if CalendarRowSelectable(rows[index]) then return index
        index = index + direction
    end while

    index = fromIndex - direction
    while index >= 0 and index < rows.Count()
        if CalendarRowSelectable(rows[index]) then return index
        index = index - direction
    end while

    return -1
end function

sub onCalendarRowFocused(event as object)
    index = event.GetData()
    if index < 0 or index >= m.calendarRows.Count() then return

    ' Echoes from the render, not moves the user made. RenderCalendarRows assigns
    ' `content` and then `JumpToItem`, and SceneGraph delivers a notification for
    ' each, in that order, after the sub returns -- so a boolean flag cleared on
    ' the next line is already false when the first one lands. Only the second
    ' notification names the row the render chose; the first is the list resetting
    ' to row 0, and accepting it would leave m.calendarFocusIndex and the detail
    ' panel describing a row that does not have focus. Both are ignored, and the
    ' one that matches disarms the token. Only RenderCalendarRows arms it: the
    ' skip below issues a single JumpToItem whose echo is safe to run through the
    ' normal path, so no path can leave a token armed with nothing to consume it.
    if m.calendarSuppressIndex >= 0
        if index = m.calendarSuppressIndex
            m.calendarSuppressIndex = -1
            m.calendarFocusIndex = index
        end if
        return
    end if

    ' Captions live in the same list, so focus is pushed past them in whichever
    ' direction the user was already moving. Re-entering this handler for `target`
    ' recomputes the same result, which is why the jump needs no token.
    if not CalendarRowSelectable(m.calendarRows[index])
        direction = 1
        if index < m.calendarFocusIndex then direction = -1
        target = NextSelectableCalendarIndex(m.calendarRows, index, direction)
        if target >= 0
            m.calendarFocusIndex = target
            ' See the Settings component: this list is fixedFocus too, so a skip
            ' has to animate or the content teleports and the list appears to
            ' lurch.
            m.calendarList.animateToItem = target
            UpdateCalendarDetail(target)
            return
        end if
    end if

    m.calendarSuppressIndex = -1
    m.calendarFocusIndex = index
    UpdateCalendarDetail(index)
end sub

sub UpdateCalendarDetail(index as integer)
    if index < 0 or index >= m.calendarRows.Count()
        m.calendarDetailPoster.uri = ""
        m.calendarDetailEyebrow.text = UCase(TrText("calendar.title"))
        m.calendarDetailTitle.text = ""
        m.calendarDetailMeta.text = ""
        m.calendarDetailDescription.text = TrText("calendar.detail.empty")
        m.calendarDetailAction.text = ""
        m.calendarDetailActionPill.visible = false
        return
    end if

    row = m.calendarRows[index]
    m.calendarDetailPoster.uri = row.thumbnailUrl
    m.calendarDetailTitle.text = row.title
    m.calendarDetailDescription.text = row.description

    if row.kind = "episode"
        m.calendarDetailEyebrow.text = UCase(row.statusText) + "    " + row.dateText
        m.calendarDetailMeta.text = row.seriesName + "    " + row.episodeLabel
        m.calendarDetailAction.text = TrText("calendar.action.openSeries")
        m.calendarDetailActionPill.visible = true
        ' The footer bar names whatever is focused, the same as every other screen.
        m.heroDescription.text = m.calendarStore.entryTitle(row.payload)
    else if row.kind = "cta"
        m.calendarDetailEyebrow.text = UCase(TrText("calendar.detail.notSignedIn"))
        m.calendarDetailTitle.text = TrText("calendar.signedOut.title")
        m.calendarDetailMeta.text = ""
        m.calendarDetailDescription.text = TrText("calendar.signedOut.detail")
        m.calendarDetailAction.text = TrText("calendar.action.login")
        m.calendarDetailActionPill.visible = true
    else
        ' Captions and empty-state copy: the panel describes the screen rather
        ' than repeating the row, because neither row can be acted on.
        m.calendarDetailEyebrow.text = UCase(TrText("calendar.title"))
        m.calendarDetailTitle.text = ""
        m.calendarDetailMeta.text = ""
        m.calendarDetailDescription.text = row.title
        m.calendarDetailAction.text = ""
        m.calendarDetailActionPill.visible = false
    end if
end sub

' Addons is its own screen, fully self-contained in the Addons component. MainScene
' only shows it, keeps the few data values it is the source of truth for, and
' dispatches the actions the component reports; all rendering, focus and keys live
' inside the component.
sub RenderAddons(focusContent as boolean)
    m.catalogList.visible = false
    m.primaryInfoGroup.visible = false
    m.addonsScreen.visible = true

    if m.addonStore.getFilter() = "all" and not m.addonStore.catalogLoaded() and not m.addonStore.catalogRequestActive()
        spec = m.addonStore.requestCatalog()
        StartRequest(spec.url, spec.id)
    end if

    PushAddonsState()
    if focusContent then RequestAddonsFocus()
end sub

' MainScene is the source of truth for the data the Addons screen renders (filter,
' search query, installed manifests and the loaded collection). The AddonStore
' holds that data; push a snapshot into the component on every change.
sub PushAddonsState()
    m.addonsScreen.state = m.addonStore.getState()
end sub

' Ask the Addons component to take focus (it routes to its inner list).
sub RequestAddonsFocus()
    m.addonsScreen.focusRequest = not m.addonsScreen.focusRequest
end sub

' An addon row or chip was activated, or the component needs to escape focus to
' scene-owned chrome. The focus escapes are handled here; the rest dispatches
' through the shared addon action handler, which pushes fresh state back so the
' rows reflect any change.
sub onAddonsScreenAction(event as object)
    action = event.GetData()
    if action = invalid then return
    if action.type = "focusTopBar"
        FocusTopBar(0)
    else if action.type = "focusNavRail"
        m.navList.SetFocus(true)
    else
        DispatchAddonAction(action.type, action.payload)
    end if
end sub

' The Addons component finished rendering; update the shared chrome (header and
' hero) it does not own.
sub onAddonsScreenInfo(event as object)
    info = event.GetData()
    if info = invalid then return
    m.primaryTitle.text = info.title
    m.primarySubtitle.text = info.subtitle
    m.heroTitle.text = info.heroTitle
    m.heroDescription.text = info.heroDescription
end sub

sub DispatchAddonAction(actionType as string, payload as dynamic)
    if actionType = "addonFilterInstalled"
        m.addonStore.setFilter("installed")
        m.addonStore.clearSearchQuery()
        ' Activating a chip must not steal focus away from the chip row.
        RenderAddons(false)
    else if actionType = "addonFilterAll"
        m.addonStore.setFilter("all")
        m.addonStore.clearSearchQuery()
        RenderAddons(false)
    else if actionType = "addAddon"
        OpenAddonConfiguration()
    else if actionType = "addonSearch"
        OpenAddonSearch()
    else if actionType = "reloadAddons"
        ReloadAddons()
    else if actionType = "installedAddon"
        ShowInstalledAddonDetails(payload)
    else if actionType = "builtinAddon" or actionType = "remoteAddon"
        ShowAddonDetails(payload)
    end if
end sub

sub RenderSettings(focusContent as boolean)
    m.catalogList.visible = false
    m.primaryInfoGroup.visible = false
    m.settingsScreen.visible = true
    PushSettingsState()
    if focusContent then RequestSettingsFocus()
end sub

' MainScene is the source of truth for the values the Settings screen renders.
' Push them into the component; the component re-renders on change.
sub PushSettingsState()
    state = m.settingsStore.getState()
    ' Stremio auth is not a settings preference (separate domain), so its signed-in
    ' flag is added here by MainScene rather than living in the settings store.
    state.authSignedIn = m.authStore.isSignedIn()
    m.settingsScreen.state = state
end sub

' Ask the Settings component to take focus (it routes to its inner list).
sub RequestSettingsFocus()
    m.settingsScreen.focusRequest = not m.settingsScreen.focusRequest
end sub

' A settings row was activated. Dispatch through the shared action handler, then
' push fresh state back so the rows reflect any value that changed.
sub onSettingsScreenAction(event as object)
    action = event.GetData()
    if action = invalid then return
    ActivateAction(action.type, action.payload)
    PushSettingsState()
end sub

' The Settings component finished rendering; update the shared chrome it does not
' own and mirror the active tab for the scene's options handler.
sub onSettingsScreenInfo(event as object)
    info = event.GetData()
    if info = invalid then return
    m.settingsTabIndex = info.tabIndex
    m.primaryTitle.text = info.title
    m.primarySubtitle.text = info.subtitle
    m.heroTitle.text = info.heroTitle
    m.heroDescription.text = info.heroDescription
end sub

function InfoAction(title as string, actionType as string, payload as dynamic) as object
    return {
        title: title
        actionType: actionType
        payload: payload
    }
end function

sub UpdateDiscoverFilterLabels()
    if m.discoverTypeLabel = invalid then return
    m.discoverTypeLabel.text = DiscoverTypeLabel(m.catalogStore.getDiscoverType())
    m.discoverCatalogLabel.text = m.catalogStore.getDiscoverCatalog()
    m.discoverGenreLabel.text = m.catalogStore.getDiscoverGenre()
    UpdateDiscoverFilterFocus()
end sub

sub UpdateDiscoverFilterFocus()
    if m.discoverTypeFocus = invalid then return
    m.discoverTypeFocus.visible = m.discoverFilterFocus = 0
    m.discoverCatalogFocus.visible = m.discoverFilterFocus = 1
    m.discoverGenreFocus.visible = m.discoverFilterFocus = 2
end sub

function DiscoverTypeLabel(value as string) as string
    if value = "movie" then return TrText("discover.type.movie")
    if value = "series" then return TrText("discover.type.series")
    if value = "channel" then return TrText("discover.type.channel")
    return value
end function

sub FocusDiscoverFilters()
    if m.activeTab <> "discover" then return
    if m.discoverFilterFocus < 0 then m.discoverFilterFocus = 0
    UpdateDiscoverFilterFocus()
    m.discoverGrid.SetFocus(false)
    m.top.SetFocus(true)
end sub

sub BlurDiscoverFilters()
    m.discoverFilterFocus = -1
    UpdateDiscoverFilterFocus()
end sub

sub RenderInfoList(actions as object, focusContent as boolean)
    content = CreateObject("roSGNode", "ContentNode")
    m.primaryActions = actions
    for each action in actions
        child = content.CreateChild("ContentNode")
        child.title = action.title
    end for
    targetIndex = 0
    if not focusContent
        targetIndex = m.primaryInfoList.itemFocused
        if targetIndex < 0 then targetIndex = 0
        if actions.Count() > 0 and targetIndex >= actions.Count() then targetIndex = actions.Count() - 1
    end if
    m.catalogList.visible = false
    m.primaryInfoGroup.visible = true
    m.primaryInfoList.content = content
    m.primaryInfoList.JumpToItem = targetIndex
    if focusContent then m.primaryInfoList.SetFocus(true)
end sub

sub onPrimaryInfoSelected(event as object)
    index = event.GetData()
    if index < 0 or index >= m.primaryActions.Count() then return

    action = m.primaryActions[index]
    ActivateAction(action.actionType, action.payload)
end sub

' A settings row is activated exactly once, from here. The scrollable settings
' list owns its OK press and reports it through its itemSelected observer; onKeyEvent
' must NOT also dispatch it. When the old onKeyEvent branch duplicated this call the
' same OK ran the row's action twice (language cycle skipped languages, toggles
' flipped twice), because itemSelected fires first and the identical press then
' reached onKeyEvent too. Keep activation single-path: only this observer calls
' ActivateSettingsRow. This feels like a hacky fix so a refactor may be called for in the future.
sub ActivateAction(actionType as string, payload as dynamic)
    if actionType = "login"
        BeginStremioLink()
    else if actionType = "refreshLibrary"
        ShowStatus(TrText("status.refreshingLibrary"), true)
        FetchLibrary()
    else if actionType = "disconnect"
        DisconnectStremio()
        RenderActiveTab(true)
    else if actionType = "subtitleSettings"
        OpenSubtitleSettings()
    else if actionType = "settingsLink"
        OpenSettingsLink(payload)
    else if actionType = "interfaceLanguage"
        CycleInterfaceLanguage()
    else if actionType = "uiScale"
        OpenUiScaleSlider()
    else if actionType = "toggleBlurUnwatched"
        m.settingsStore.setBlurUnwatched(not m.settingsStore.getBlurUnwatched())
        m.settingsStore.saveInterfacePreferences()
    else if actionType = "defaultSubtitleLanguage"
        CycleDefaultSubtitleLanguage()
    else if actionType = "subtitleOutlineColor"
        CycleSubtitleOutlineColor()
    else if actionType = "defaultAudioTrack"
        CycleDefaultAudioTrack()
    else if actionType = "streamingServer"
        OpenStreamingServerConfiguration()
    else if actionType = "testStreamingServer"
        TestStreamingServer()
    else if actionType = "clearStreamingServer"
        m.settingsStore.setStreamingServerUrl("")
        m.settingsStore.saveStreamingServerConfig()
        HideStatus()
        ShowStatus(TrText("status.server.cleared"), false)
    else if actionType = "calendarEpisode"
        OpenCalendarEpisode(payload)
    end if
end sub

sub HandleAddonCatalogResponse(data as object)
    m.addonStore.handleCatalogResponse(data)
    if m.activeTab = "addons" then RenderAddons(false)
end sub

sub ShowAddonDetails(addon as object)
    if addon = invalid or not addon.DoesExist("manifest") then return
    manifest = addon.manifest
    dialog = CreateObject("roSGNode", "Dialog")
    dialog.title = SafeString(manifest, "name")
    ' Labels are Stroku's; the values are manifest text and stay as the add-on
    ' author wrote them.
    dialog.message = TrText("dialog.addon.version") + " " + SafeString(manifest, "version") + Chr(10) + TrText("dialog.addon.types") + " " + AddonTypesLabel(manifest) + Chr(10) + TrText("dialog.addon.resources") + " " + AddonResourcesLabel(manifest) + Chr(10) + Chr(10) + SafeString(manifest, "description")
    url = SafeString(addon, "url")
    if url <> ""
        dialog.message = dialog.message + Chr(10) + Chr(10) + TrText("dialog.addon.manifest") + " " + url
        dialog.buttons = [TrText("common.install"), TrText("common.done")]
        m.pendingAddonDetails = addon
        dialog.ObserveField("buttonSelected", "onAddonDetailsButton")
    else
        dialog.buttons = [TrText("common.done")]
    end if
    m.top.dialog = dialog
end sub

sub onAddonDetailsButton(event as object)
    button = event.GetData()
    if button = 0 and m.pendingAddonDetails <> invalid
        url = SafeString(m.pendingAddonDetails, "url")
        if url <> "" then VerifyAddonConfiguration(url, "Verifying Stremio add-on...")
    end if
    m.pendingAddonDetails = invalid
end sub

sub ShowInstalledAddonDetails(index as integer)
    installed = m.addonStore.getInstalled()
    if index < 0 or index >= installed.Count() then return
    addon = installed[index]
    manifest = addon.manifest
    dialog = CreateObject("roSGNode", "Dialog")
    dialog.title = SafeString(manifest, "name")
    ' Host only, never the configured URL: it can embed a debrid key, and this
    ' dialog is just an overview. Share is the deliberate path for the full URL.
    dialog.message = TrText("dialog.addon.version") + " " + SafeString(manifest, "version") + Chr(10) + TrText("dialog.addon.types") + " " + AddonTypesLabel(manifest) + Chr(10) + TrText("dialog.addon.resources") + " " + AddonResourcesLabel(manifest) + Chr(10) + Chr(10) + SafeString(manifest, "description") + Chr(10) + Chr(10) + TrText("dialog.addon.manifest") + " " + AddonSourceLabel(addon.url)
    dialog.buttons = [TrText("common.share"), TrText("common.uninstall"), TrText("common.done")]
    m.installedAddonDetailsIndex = index
    dialog.ObserveField("buttonSelected", "onInstalledAddonDetailsButton")
    m.top.dialog = dialog
end sub

sub onInstalledAddonDetailsButton(event as object)
    button = event.GetData()
    index = m.installedAddonDetailsIndex
    m.installedAddonDetailsIndex = -1
    if button = 0
        ShareAddon(index)
    else if button = 1
        UninstallAddon(index)
    end if
end sub

sub LoadCalendarEntries()
    specs = m.calendarStore.load(m.libraryStore.getLibraryItems())
    for each spec in specs
        StartRequest(spec.url, spec.id)
    end for
end sub

sub HandleCalendarMetaResponse(data as object, seriesId as string)
    m.calendarStore.handleMetaResponse(data, seriesId, m.libraryStore.getLibraryItems())
    if m.activeTab = "calendar" and m.screenMode = "home" and not m.calendarStore.getRequestActive() then RenderCalendar(false)
end sub

sub OpenCalendarEpisode(entry as object)
    if entry = invalid then return
    if entry.DoesExist("series")
        OpenSeriesEpisodes(entry.series)
    end if
end sub

sub OpenAddonSearch()
    dialog = CreateObject("roSGNode", "KeyboardDialog")
    dialog.title = TrText("dialog.addonSearch.title")
    if m.addonStore.getFilter() = "all"
        dialog.message = TrText("dialog.addonSearch.messageAll")
        if not m.addonStore.catalogLoaded() and not m.addonStore.catalogRequestActive()
            spec = m.addonStore.requestCatalog()
            StartRequest(spec.url, spec.id)
        end if
    else
        dialog.message = TrText("dialog.addonSearch.messageInstalled")
    end if
    dialog.buttons = [TrText("common.search"), TrText("common.cancel")]
    dialog.ObserveField("buttonSelected", "onAddonSearchButton")
    m.addonSearchDialog = dialog
    m.top.dialog = dialog
end sub

sub onAddonSearchButton(event as object)
    button = event.GetData()
    if button <> 0
        m.addonSearchDialog.close = true
        return
    end if

    query = LCase(m.addonSearchDialog.text.Trim())
    m.addonSearchDialog.close = true
    ' The query is a filter over the same card list, not a separate results
    ' screen: the Addons component applies it and its hero line reports it.
    m.addonStore.setSearchQuery(query)
    RenderAddons(true)
end sub

sub UninstallAddon(index as integer)
    installed = m.addonStore.getInstalled()
    if index < 0 or index >= installed.Count() then return
    addonName = SafeString(installed[index].manifest, "name")
    m.addonStore.removeByIndex(index)
    m.addonStore.saveUrls()
    RenderAddons(true)
    ShowStatus(addonName + " was removed.", false)
end sub

sub ShareAddon(index as integer)
    installed = m.addonStore.getInstalled()
    if index < 0 or index >= installed.Count() then return
    url = installed[index].url
    dialog = CreateObject("roSGNode", "Dialog")
    dialog.title = TrText("dialog.shareAddon.title")
    ' Sharing is the one place the full URL is the point, so it is shown -- unless
    ' the URL carries a debrid key, in which case putting it on a TV screen hands
    ' the account to anyone watching or to whoever the user reads it out to.
    if m.addonStore.AddonUrlLooksPrivate(url)
        dialog.message = TrText("dialog.shareAddon.privateHidden") + Chr(10) + Chr(10) + AddonSourceLabel(url)
    else
        dialog.message = TrText("dialog.shareAddon.manifestUrl") + Chr(10) + url + Chr(10) + Chr(10) + TrText("dialog.shareAddon.warning")
    end if
    dialog.buttons = [TrText("common.done")]
    m.top.dialog = dialog
end sub

' The Reload chip re-fetches every configured manifest. The spinner it raises is
' cleared by CompleteAddonLoad once the last response lands; without a request to
' wait for there would be nothing to clear it, so that case reports instead.
sub ReloadAddons()
    m.addonStore.reload()
    m.addonReloadActive = false
    LoadAddonConfiguration()
    if m.addonLoadPending <= 0
        if m.activeTab = "addons" then RenderAddons(false)
        ShowStatus(TrText("addons.empty"), false)
        return
    end if
    m.addonReloadActive = true
    ShowStatus(TrText("status.reloadingAddons"), true)
end sub

sub OpenDiscoverFilters()
    dialog = CreateObject("roSGNode", "Dialog")
    dialog.title = TrText("dialog.discoverFilters.title")
    dialog.message = TrText("dialog.discoverFilters.message")
    ' Display only. The CatalogStore's discover filter values stay canonical so
    ' NextOption and the catalog requests never see a translation.
    dialog.buttons = [
        TrFormat("dialog.discoverFilters.type", m.catalogStore.getDiscoverType())
        TrFormat("dialog.discoverFilters.catalog", m.catalogStore.getDiscoverCatalog())
        TrFormat("dialog.discoverFilters.genre", m.catalogStore.getDiscoverGenre())
        TrText("dialog.discoverFilters.apply")
        TrText("common.cancel")
    ]
    dialog.ObserveField("buttonSelected", "onDiscoverFilterButton")
    m.discoverFilterDialog = dialog
    m.top.dialog = dialog
end sub

sub onDiscoverFilterButton(event as object)
    button = event.GetData()
    m.discoverFilterDialog.close = true
    if button = 0
        CycleDiscoverFilter(0)
        OpenDiscoverFilters()
    else if button = 1
        CycleDiscoverFilter(1)
        OpenDiscoverFilters()
    else if button = 2
        CycleDiscoverFilter(2)
        OpenDiscoverFilters()
    else if button = 3
        FetchDiscoverCatalog()
    end if
end sub

sub CycleDiscoverFilter(filterIndex as integer)
    if filterIndex = 0
        m.catalogStore.setDiscoverType(NextOption(m.catalogStore.getDiscoverTypes(), m.catalogStore.getDiscoverType()))
        if m.catalogStore.getDiscoverType() = "channel"
            m.catalogStore.setDiscoverGenre("None")
        end if
    else if filterIndex = 1
        m.catalogStore.setDiscoverCatalog(NextOption(m.catalogStore.getDiscoverCatalogs(), m.catalogStore.getDiscoverCatalog()))
    else if filterIndex = 2
        if m.catalogStore.getDiscoverType() = "channel"
            m.catalogStore.setDiscoverGenre("None")
        else
            m.catalogStore.setDiscoverGenre(NextOption(m.catalogStore.getDiscoverGenres(), m.catalogStore.getDiscoverGenre()))
        end if
    end if
    UpdateDiscoverFilterLabels()
    FetchDiscoverCatalog()
end sub

' Maps the 1920x1080 design layout onto whatever design resolution this Roku
' reports, then applies the user's manual scale on top of it.
'
' Roku picks the design resolution from the manifest's ui_resolutions and the
' device: HD-only players report 1280x720, FHD players report 1920x1080. Without
' this pass the FHD-authored layout overflows an HD design resolution, which is
' what makes the UI look zoomed in and cropped on those TVs.
sub ApplyUiScaleSettings()
    resolution = DisplayDesignResolution()
    scale = ComputeUiScale(resolution.width, resolution.height, resolution.name, m.settingsStore.getUiScalePercent())

    PublishUiScaleValue("uiScaleGeometry", scale.geometry)
    PublishUiScaleValue("uiScaleFont", scale.font)
    PublishUiScaleValue("uiScaleOffsetX", scale.offsetX)
    PublishUiScaleValue("uiScaleOffsetY", scale.offsetY)

    displayDescription = Int(resolution.width).ToStr() + "x" + Int(resolution.height).ToStr()
    if resolution.name <> "" then displayDescription = displayDescription + " " + resolution.name
    m.settingsStore.setDisplayDescription(displayDescription)

    ' Paint the letterbox margins left by a reduced manual scale in the app colour
    ' instead of the Roku default background image.
    m.top.backgroundURI = ""
    m.top.backgroundColor = "0x0C0B19FF"

    m.uiRoot.translation = [scale.offsetX, scale.offsetY]
    EnsureUiScale(m.uiRoot)

    ' The video surface always fills the display; only its overlays are scaled.
    m.video.translation = [0, 0]
    m.video.width = resolution.width
    m.video.height = resolution.height
    m.video.CallFunc("ApplyUiScale", invalid)
end sub

function DisplayDesignResolution() as object
    result = {
        width: UiDesignWidth()
        height: UiDesignHeight()
        name: "FHD"
    }

    resolution = m.top.currentDesignResolution
    if resolution <> invalid and resolution.DoesExist("width") and resolution.DoesExist("height")
        if resolution.width > 0 and resolution.height > 0
            result.width = resolution.width
            result.height = resolution.height
            if resolution.DoesExist("resolution") and resolution.resolution <> invalid
                result.name = UCase(resolution.resolution)
            else
                result.name = ""
            end if
            return result
        end if
    end if

    ' Older firmware and odd device reports fall back to roDeviceInfo.
    deviceInfo = CreateObject("roDeviceInfo")
    uiResolution = deviceInfo.GetUIResolution()
    if uiResolution <> invalid and uiResolution.DoesExist("width") and uiResolution.DoesExist("height")
        if uiResolution.width > 0 and uiResolution.height > 0
            result.width = uiResolution.width
            result.height = uiResolution.height
            result.name = ""
            if uiResolution.DoesExist("name") and uiResolution.name <> invalid
                result.name = UCase(uiResolution.name)
            end if
        end if
    end if

    return result
end function

sub PublishUiScaleValue(fieldName as string, value as float)
    if m.global = invalid then return
    if not m.global.hasField(fieldName) then m.global.addField(fieldName, "float", false)
    m.global.setField(fieldName, value)
end sub

sub OpenUiScaleSlider()
    m.settingsStore.setUiScaleSavedPercent(m.settingsStore.getUiScalePercent())
    m.settingsStore.setUiScalePendingPercent(m.settingsStore.getUiScalePercent())
    m.settingsStore.setUiScaleReturnMode(m.activeTab)
    m.uiScaleGroup.visible = true
    m.screenMode = "uiScale"
    m.uiScaleMessage.text = TrFormat("uiScale.message", m.settingsStore.getDisplayDescription())
    UpdateUiScaleSlider()

    ' The settings screen keeps focus unless it is blurred first, and then it
    ' swallows OK and the arrows before onKeyEvent ever sees them.
    m.primaryInfoList.SetFocus(false)
    m.settingsScreen.SetFocus(false)
    m.top.SetFocus(true)
end sub

' swallowOpeningOk is set by callers whose OK press still has to bubble up to
' onKeyEvent after this returns. The settings list fires itemSelected first and
' the same press then reaches onKeyEvent with the panel already open, which would
' close it again; the top bar drives onKeyEvent directly and has nothing to
' swallow. The UI scale slider never hit this because it opens on focus, not OK.
sub OpenCoffeeSupport(swallowOpeningOk as boolean)
    m.coffeeReturnMode = m.activeTab
    m.coffeeSwallowOk = swallowOpeningOk
    ' Authored in English in the XML so the layout stays readable there; every
    ' open rewrites them, which is what makes the panel follow UI Language.
    m.coffeeTitle.text = TrText("dialog.link.coffee.title")
    m.coffeeMessage.text = TrText("dialog.link.coffee.message")
    m.coffeeScanHint.text = TrText("dialog.link.coffee.scanHint")
    m.coffeeDismissHint.text = TrText("dialog.link.coffee.dismissHint")
    m.coffeeGroup.visible = true
    m.screenMode = "coffee"

    ' Same reason as the UI scale slider: the settings screen swallows OK and back
    ' before onKeyEvent sees them unless it is blurred first.
    m.primaryInfoList.SetFocus(false)
    m.settingsScreen.SetFocus(false)
    m.top.SetFocus(true)
end sub

sub CloseCoffeeSupport()
    m.coffeeGroup.visible = false
    m.coffeeSwallowOk = false
    m.screenMode = "home"
    ' Opened from the top bar, the panel returns there rather than diving into the
    ' content list: the viewer never left the top bar to begin with.
    returnToTopBar = m.coffeeReturnedFromTopBar
    m.coffeeReturnedFromTopBar = false
    SetActiveTab(m.coffeeReturnMode, not returnToTopBar)
    if returnToTopBar then FocusTopBar(1)
end sub

sub UpdateUiScaleSlider()
    minPercent = UiScaleMinPercent()
    maxPercent = UiScaleMaxPercent()
    pendingPercent = m.settingsStore.getUiScalePendingPercent()
    fraction = (pendingPercent - minPercent) / (maxPercent - minPercent)
    if fraction < 0.0 then fraction = 0.0
    if fraction > 1.0 then fraction = 1.0

    trackWidth = 1080
    fillWidth = trackWidth * fraction
    m.uiScaleFill.width = ScaleUi(fillWidth)
    m.uiScaleHandle.translation = ScaleUiXY(420 + fillWidth - 12, 504)

    label = pendingPercent.ToStr() + "%"
    if pendingPercent = UiScaleDefaultPercent() then label = label + "    " + TrText("uiScale.automaticFit")
    m.uiScaleValue.text = label
end sub

sub SetUiScalePercent(percent as integer)
    if percent < UiScaleMinPercent() then percent = UiScaleMinPercent()
    if percent > UiScaleMaxPercent() then percent = UiScaleMaxPercent()
    if percent = m.settingsStore.getUiScalePendingPercent() then return

    m.settingsStore.setUiScalePendingPercent(percent)
    m.settingsStore.setUiScalePercent(percent)
    ApplyUiScaleSettings()
    UpdateUiScaleSlider()
end sub

sub CloseUiScaleSlider(save as boolean)
    if save
        m.settingsStore.saveInterfacePreferences()
    else if m.settingsStore.getUiScalePercent() <> m.settingsStore.getUiScaleSavedPercent()
        m.settingsStore.setUiScalePercent(m.settingsStore.getUiScaleSavedPercent())
        m.settingsStore.setUiScalePendingPercent(m.settingsStore.getUiScaleSavedPercent())
        ApplyUiScaleSettings()
    end if

    m.uiScaleGroup.visible = false
    m.screenMode = "home"
    ' Re-rendering rebinds every visible list card, which is how recycled item
    ' components pick up a scale that changed after they were created.
    SetActiveTab(m.settingsStore.getUiScaleReturnMode(), false)
    m.top.SetFocus(false)
    FocusActiveContent()
end sub

sub LoadStremioAccount()
    if m.authStore.load() <> ""
        FetchLibrary()
    end if
end sub

sub LoadAddonConfiguration()
    m.addonStore.load()
    urls = m.addonStore.getManifestUrls()
    m.addonLoadPending = urls.Count()
    for index = 0 to urls.Count() - 1
        StartRequest(urls[index], "addonLoad|" + index.ToStr())
    end for
end sub

sub FetchBoardCatalogs()
    reqs = m.catalogStore.fetchBoardCatalogs()
    for each req in reqs
        StartRequest(req.url, req.id)
    end for
end sub

sub FetchDiscoverCatalog()
    req = m.catalogStore.restartDiscoverCatalog()
    if m.activeTab = "discover"
        m.catalogRows = m.catalogStore.getDiscoverRows()
        m.catalogNames = m.catalogStore.getDiscoverNames()
        UpdateDiscoverFilterLabels()
        RebuildDiscoverGrid()
    end if
    StartRequest(req.url, req.id)
end sub

sub SearchCatalogs(query as string)
    query = query.Trim()
    if query = "" then return

    lowerQuery = LCase(query)
    if Left(lowerQuery, 7) = "magnet:"
        ShowStatus(TrText("status.search.magnetUnsupported"), false)
        return
    end if
    if Left(lowerQuery, 5) = "tvdb:"
        ShowStatus(TrText("status.search.tvdbUnsupported"), false)
        return
    end if
    if Left(lowerQuery, 8) = "https://" and Right(lowerQuery, 14) = "/manifest.json"
        VerifyAddonConfiguration(query, TrText("status.verifyingAddon"))
        return
    end if
    if Left(lowerQuery, 7) = "http://" or Left(lowerQuery, 8) = "https://"
        PlayExternal({ url: query, title: "External stream" })
        return
    end if

    if IsImdbId(lowerQuery)
        reqs = m.catalogStore.beginSearch(true, lowerQuery)
        m.searchPrompt.text = "Results for " + Chr(34) + query + Chr(34)
        SetActiveTab("discover", true)
        ShowStatus(TrText("status.search.resolvingImdb"), true)
    else
        reqs = m.catalogStore.beginSearch(false, query)
        m.searchPrompt.text = "Results for " + Chr(34) + query + Chr(34)
        SetActiveTab("discover", true)
        ShowStatus(TrText("status.search.searchingCatalogs"), true)
    end if
    for each req in reqs
        StartRequest(req.url, req.id)
    end for
end sub

sub LoadHomeCatalogs()
    m.catalogStore.resetBoard()
    m.catalogRows = m.catalogStore.getBoardRows()
    m.catalogNames = m.catalogStore.getBoardNames()
    m.searchPrompt.text = TrText("dialog.search.title")
    RebuildCatalog()
    FetchBoardCatalogs()
end sub

sub StartRequest(url as string, requestId as string)
    task = CreateObject("roSGNode", "HttpTask")
    task.url = url
    task.requestId = requestId
    task.ObserveField("response", "onHttpResponse")
    m.tasks.Push(task)
    task.control = "RUN"
end sub

sub StartStreamRequest(url as string, requestId as string)
    task = CreateObject("roSGNode", "HttpTask")
    task.url = url
    task.requestId = requestId
    task.timeoutMs = 45000
    task.ObserveField("response", "onHttpResponse")
    m.tasks.Push(task)
    task.control = "RUN"
end sub

sub StartPostRequest(url as string, requestId as string, body as object)
    task = CreateObject("roSGNode", "HttpTask")
    task.url = url
    task.requestId = requestId
    task.method = "POST"
    task.body = FormatJson(body)
    task.ObserveField("response", "onHttpResponse")
    m.tasks.Push(task)
    task.control = "RUN"
end sub

sub onHttpResponse(event as object)
    response = event.GetData()
    if response = invalid then return

    parts = response.requestId.Tokenize("|")
    requestType = parts[0]

    if requestType = "streams"
        activePrefix = m.activeStreamRequestId + "|"
        if not m.streamRequestActive or Left(response.requestId, Len(activePrefix)) <> activePrefix
            return
        end if
    else if requestType = "subtitles"
        activePrefix = m.activeSubtitleRequestId + "|"
        if not m.subtitleRequestActive or Left(response.requestId, Len(activePrefix)) <> activePrefix
            return
        end if
    end if

    if not response.ok
        if requestType = "catalog" or requestType = "search" or requestType = "boardCatalog" or requestType = "discoverCatalog"
            if requestType = "discoverCatalog" then m.catalogStore.setDiscoverRequestActive(false)
            ShowStatus(response.error, false)
        else if requestType = "config"
            m.addonStore.clearPendingAddonUrl()
            ShowStatus(TrFormat("status.addon.verifyFailed", response.error), false)
        else if requestType = "addonLoad"
            CompleteAddonLoad()
            return
        else if requestType = "addonCatalog"
            m.addonStore.setCatalogRequestActive(false)
            if m.activeTab = "addons" then RenderAddons(false)
            ShowStatus(TrFormat("status.addon.collectionFailed", response.error), false)
        else if requestType = "calendarMeta"
            HandleCalendarMetaResponse(invalid, parts[1])
        else if requestType = "searchMeta"
            HandleSearchMetaResponse(invalid, Val(parts[1]))
        else if requestType = "meta" and m.episodeReturnMode = "home"
            m.episodeRequestActive = false
            ShowEpisodeLoadError("Could not load episodes. " + response.error)
        else if requestType = "linkCreate"
            ShowStatus(TrFormat("status.link.startFailed", response.error), false)
        else if requestType = "linkRead"
            return
        else if requestType = "libraryGet" or requestType = "libraryPut"
            ShowStatus(TrFormat("status.library.requestFailed", response.error), false)
        else if requestType = "libraryPutSilent"
            print "[Stroku] Silent library update failed: " ; response.error
        else if requestType = "streams"
            HandleStreamRequestError(response.error)
        else if requestType = "subtitles"
            HandleSubtitleRequestError(response.error)
        else if requestType = "serverTest"
            HideStatus()
            ShowStatus(TrFormat("status.server.failed", response.error), false)
        else
            ShowStatus(response.error, false)
        end if
        return
    end if

    if requestType = "catalog" or requestType = "boardCatalog"
        HideStatus()
        HandleCatalogResponse(response.data, Val(parts[1]), "board")
    else if requestType = "discoverCatalog"
        HideStatus()
        HandleCatalogResponse(response.data, Val(parts[1]), "discover")
    else if requestType = "search"
        HideStatus()
        HandleCatalogResponse(response.data, Val(parts[1]), "search")
    else if requestType = "meta"
        HideStatus()
        HandleMetaResponse(response.data)
    else if requestType = "streams"
        HandleStreamsResponse(response.data, Val(parts[2]))
    else if requestType = "subtitles"
        HandleSubtitlesResponse(response.data, Val(parts[2]))
    else if requestType = "config"
        result = m.addonStore.handleVerifyResponse(response.data)
        if result.valid
            HideStatus()
            if m.activeTab = "addons" then RenderAddons(true)
            ShowStatus(result.name + " was added and verified.", false)
        else
            ShowStatus(TrText("status.addon.unsupportedResource"), false)
        end if
    else if requestType = "addonLoad"
        HandleLoadedAddon(response.data, Val(parts[1]))
    else if requestType = "addonCatalog"
        HandleAddonCatalogResponse(response.data)
    else if requestType = "calendarMeta"
        HandleCalendarMetaResponse(response.data, parts[1])
    else if requestType = "searchMeta"
        HideStatus()
        HandleSearchMetaResponse(response.data, Val(parts[1]))
    else if requestType = "linkCreate"
        HandleLinkCreateResponse(response.data)
    else if requestType = "linkRead"
        HandleLinkReadResponse(response.data)
    else if requestType = "libraryGet"
        HandleLibraryResponse(response.data)
    else if requestType = "libraryPut"
        HandleLibraryPutResponse(response.data)
    else if requestType = "libraryPutSilent"
        print "[Stroku] Silent library update succeeded"
    else if requestType = "serverTest"
        HideStatus()
        ShowStatus(TrText("status.server.ok"), false)
    end if
end sub

sub HandleSubtitleRequestError(message as string)
    if not m.subtitleRequestActive then return
    m.subtitleRequestErrors.Push(message)
    m.completedSubtitleRequests = m.completedSubtitleRequests + 1
    if m.completedSubtitleRequests < m.pendingSubtitleRequests then return

    ClearActiveSubtitleRequest()
    HideStatus()
    PlayPendingStream()
end sub

sub HandleStreamRequestError(message as string)
    if not m.streamRequestActive then return
    m.streamRequestErrors.Push(message)
    m.completedStreamRequests = m.completedStreamRequests + 1
    if m.completedStreamRequests < m.pendingStreamRequests then return

    ClearActiveStreamRequest()
    if m.streams.Count() > 0
        HideStatus()
        if m.pendingNextEpisode <> invalid
            streamIndex = m.selectedStreamIndex
            if streamIndex < 0 or streamIndex >= m.streams.Count() then streamIndex = 0
            m.selectedStreamIndex = streamIndex
            FindSubtitles(m.streams[streamIndex])
            return
        end if
        ShowChoices("Choose a stream (" + m.streams.Count().ToStr() + ")", BuildStreamContent(), "streams", m.streamReturnMode)
    else
        RecoverFromNextEpisodeFailure()
        ShowNoStreamsScreen("No add-on returned a direct playable stream. " + message)
    end if
end sub

sub OpenSearch()
    dialog = CreateObject("roSGNode", "KeyboardDialog")
    dialog.title = TrText("dialog.search.title")
    dialog.message = TrText("dialog.search.message")
    dialog.buttons = [TrText("common.search"), TrText("common.cancel")]
    dialog.ObserveField("buttonSelected", "onSearchButton")
    m.searchDialog = dialog
    m.top.dialog = dialog
end sub

sub onSearchButton(event as object)
    button = event.GetData()
    if button <> 0
        m.searchDialog.close = true
        return
    end if

    query = m.searchDialog.text.Trim()
    if query = ""
        m.searchDialog.message = TrText("dialog.search.empty")
        return
    end if

    m.searchDialog.close = true
    SearchCatalogs(query)
end sub

sub HandleCatalogResponse(data as object, rowIndex as integer, target as string)
    m.catalogStore.handleCatalogResponse(data, rowIndex, target)
    if target = "board"
        if m.activeTab = "board"
            m.catalogRows = m.catalogStore.getBoardRows()
            RebuildCatalog()
        end if
    else
        if m.activeTab = "discover"
            m.catalogRows = m.catalogStore.getDiscoverRows()
            RebuildDiscoverGrid()
        end if
    end if
end sub

sub HandleSearchMetaResponse(data as object, rowIndex as integer)
    if not m.catalogStore.handleSearchMetaResponse(data, rowIndex) then return
    if m.activeTab = "discover"
        m.catalogRows = m.catalogStore.getDiscoverRows()
        RebuildDiscoverGrid()
    end if
end sub

function IsImdbId(value as string) as boolean
    if Len(value) < 4 then return false
    if Left(value, 2) <> "tt" then return false
    for index = 3 to Len(value)
        digit = Mid(value, index, 1)
        if digit < "0" or digit > "9" then return false
    end for
    return true
end function

sub RebuildCatalog()
    root = CreateObject("roSGNode", "ContentNode")

    for rowIndex = 0 to m.catalogRows.Count() - 1
        rowNode = root.CreateChild("ContentNode")
        rowNode.title = m.catalogNames[rowIndex]

        for each item in m.catalogRows[rowIndex]
            itemNode = rowNode.CreateChild("ContentNode")
            itemNode.title = SafeString(item, "name")
            itemNode.HDPosterUrl = SafeString(item, "poster")
            itemNode.SDPosterUrl = SafeString(item, "poster")

            ' Check if we have progress for this item
            id = SafeString(item, "id")
            progress = 0.0
            if m.libraryStore.hasById(id)
                libraryItem = m.libraryStore.getById(id)
                if libraryItem.DoesExist("state") and libraryItem.state <> invalid
                    state = libraryItem.state
                    if state.DoesExist("timeOffset") and state.DoesExist("duration")
                        offset = state.timeOffset
                        dur = state.duration
                        if offset > 0 and dur > 0
                            progress = offset / dur
                        end if
                    end if
                end if
            end if
            if progress > 0.0 and progress < 0.9
                itemNode.AddFields({ progress: progress })
            end if
        end for
    end for

    m.catalogList.content = root
    if m.screenMode = "home" and m.catalogList.visible and not m.navList.HasFocus() and not m.primaryInfoList.HasFocus() and not m.settingsScreen.HasFocus() and m.discoverFilterFocus < 0
        m.catalogList.SetFocus(true)
    end if
end sub

sub RebuildDiscoverGrid()
    content = CreateObject("roSGNode", "ContentNode")
    discoverRows = m.catalogStore.getDiscoverRows()
    if discoverRows <> invalid and discoverRows.Count() > 0
        for each item in discoverRows[0]
            if SafeString(item, "type") <> "action"
                itemNode = content.CreateChild("ContentNode")
                itemNode.title = SafeString(item, "name")
                itemNode.HDPosterUrl = SafeString(item, "poster")
                itemNode.SDPosterUrl = SafeString(item, "poster")
                id = SafeString(item, "id")
                progress = 0.0
                if m.libraryStore.hasById(id)
                    libraryItem = m.libraryStore.getById(id)
                    if libraryItem.DoesExist("state") and libraryItem.state <> invalid
                        state = libraryItem.state
                        if state.DoesExist("timeOffset") and state.DoesExist("duration")
                            offset = state.timeOffset
                            dur = state.duration
                            if offset > 0 and dur > 0 then progress = offset / dur
                        end if
                    end if
                end if
                if progress > 0.0 and progress < 0.9
                    itemNode.AddFields({ progress: progress })
                end if
            end if
        end for
    end if
    m.discoverGrid.content = content
end sub

function GetDiscoverGridItem(index as integer) as dynamic
    discoverRows = m.catalogStore.getDiscoverRows()
    if index < 0 or discoverRows = invalid or discoverRows.Count() = 0 then return invalid
    visibleIndex = -1
    for each item in discoverRows[0]
        if SafeString(item, "type") <> "action"
            visibleIndex = visibleIndex + 1
            if visibleIndex = index then return item
        end if
    end for
    return invalid
end function

sub onDiscoverGridFocused(event as object)
    if m.discoverFilterFocus >= 0 then return
    item = GetDiscoverGridItem(event.GetData())
    if item = invalid then return
    m.heroTitle.text = SafeString(item, "name")
    m.heroDescription.text = HomeHeroDescription(item)
    meta = SafeString(item, "type")
    year = SafeString(item, "releaseInfo")
    if year = "" then year = SafeString(item, "year")
    if year <> "" then meta = meta + "  " + year
    if meta <> "" then m.primarySubtitle.text = meta
end sub

sub onDiscoverGridSelected(event as object)
    if m.discoverFilterFocus >= 0 then return
    item = GetDiscoverGridItem(event.GetData())
    if item = invalid then return
    if SafeString(item, "type") = "series"
        OpenSeriesEpisodes(item)
    else
        OpenMovieStreams(item)
    end if
end sub

sub onCatalogFocused(event as object)
    position = event.GetData()
    item = GetCatalogItem(position)
    if item = invalid then return

    m.heroTitle.text = SafeString(item, "name")
    m.heroDescription.text = HomeHeroDescription(item)
    if m.activeTab = "discover" and SafeString(item, "type") <> "action"
        meta = SafeString(item, "type")
        year = SafeString(item, "releaseInfo")
        if year = "" then year = SafeString(item, "year")
        if year <> "" then meta = meta + "  " + year
        if meta <> "" then m.primarySubtitle.text = meta
    end if
end sub

sub onCatalogSelected(event as object)
    item = GetCatalogItem(event.GetData())
    if item = invalid then return

    if SafeString(item, "type") = "action"
        OpenBoardSeeAll(item)
        return
    end if

    if SafeString(item, "type") = "series"
        OpenSeriesEpisodes(item)
    else
        OpenMovieStreams(item)
    end if
end sub

sub OpenMovieStreams(item as object)
    ClearActiveStreamRequest()
    m.selectedItem = item
    m.episodes = []
    FindStreams(SafeString(item, "type"), SafeString(item, "id"), SafeString(item, "name"), "home")
end sub

sub OpenBoardSeeAll(item as object)
    rowIndex = 0
    if item.DoesExist("rowIndex") then rowIndex = item.rowIndex

    if rowIndex = 1 or rowIndex = 3
        m.catalogStore.setDiscoverType("series")
    else if rowIndex = 4
        m.catalogStore.setDiscoverType("channel")
    else
        m.catalogStore.setDiscoverType("movie")
    end if

    if rowIndex = 2 or rowIndex = 3
        m.catalogStore.setDiscoverCatalog("Featured")
    else
        m.catalogStore.setDiscoverCatalog("Popular")
    end if

    m.catalogStore.setDiscoverGenre("Genre")
    SetActiveTab("discover", true)
    FetchDiscoverCatalog()
end sub

sub OpenSeriesEpisodes(item as object)
    ClearActiveStreamRequest()
    m.selectedItem = item
    m.episodes = []
    m.visibleEpisodes = []
    m.seasons = []
    m.selectedSeasonIndex = -1
    m.seriesMeta = invalid
    m.selectedEpisodeIndex = 0
    m.episodeReturnMode = "home"
    m.choiceReturnMode = "home"
    m.choiceMode = "loading"
    m.episodeRequestActive = true
    m.choiceTitle.text = TrFormat("episodes.loadingFor", SafeString(item, "name"))

    content = CreateObject("roSGNode", "ContentNode")
    child = content.CreateChild("ContentNode")
    child.title = TrText("episodes.loading")
    m.streamList.visible = false
    m.choiceList.visible = true
    m.choiceList.content = content

    m.homeGroup.visible = false
    m.episodeGroup.visible = false
    m.choiceGroup.visible = true
    m.noStreamsGroup.visible = false
    m.screenMode = "episodeLoading"
    m.top.SetFocus(true)

    StartRequest(CinemetaMetaUrl("series", SafeString(item, "id")), "meta|series")
end sub

function HomeHeroDescription(item as object) as string
    description = SafeString(item, "description")
    if SafeString(item, "type") = "movie"
        hint = "Streams load automatically"
        if description <> "" then return description + "    " + hint
        return hint
    end if
    return description
end function

function GetCatalogItem(position as object) as dynamic
    if position = invalid or position.Count() < 2 then return invalid
    rowIndex = position[0]
    itemIndex = position[1]
    if rowIndex < 0 or rowIndex >= m.catalogRows.Count() then return invalid
    if itemIndex < 0 or itemIndex >= m.catalogRows[rowIndex].Count() then return invalid
    return m.catalogRows[rowIndex][itemIndex]
end function

function CinemetaMetaUrl(contentType as string, id as string) as string
    return "https://v3-cinemeta.strem.io/meta/" + contentType + "/" + id + ".json"
end function

sub HandleMetaResponse(data as object)
    if not m.episodeRequestActive then return
    m.episodeRequestActive = false

    if data.DoesExist("meta") and data.meta <> invalid and data.meta.DoesExist("videos")
        m.seriesMeta = data.meta
        m.episodes = data.meta.videos
    end if

    if m.episodes.Count() > 0
        ShowEpisodeScreen()
    else
        ShowEpisodeLoadError("No episodes were returned.")
    end if
end sub

sub ShowEpisodeScreen()
    BuildSeasons()
    if m.seasons.Count() = 0
        ShowEpisodeLoadError("No episodes were returned.")
        return
    end if

    if m.selectedSeasonIndex < 0 or m.selectedSeasonIndex >= m.seasons.Count()
        m.selectedSeasonIndex = 0
        for index = 0 to m.seasons.Count() - 1
            if m.seasons[index] = 1
                m.selectedSeasonIndex = index
                exit for
            end if
        end for
    end if

    meta = m.seriesMeta
    if meta = invalid then meta = m.selectedItem
    m.episodeBackground.uri = SafeString(meta, "background")
    m.episodeSeriesTitle.text = SafeString(meta, "name")
    m.episodeSeriesMeta.text = SeriesMetaLine(meta)
    m.episodeSeriesDescription.text = SafeString(meta, "description")

    m.homeGroup.visible = false
    m.choiceGroup.visible = false
    m.noStreamsGroup.visible = false
    m.episodeGroup.visible = true
    m.screenMode = "episodes"
    RebuildSeasonGrid()
    RebuildEpisodeList()
    m.seasonGrid.SetFocus(true)
end sub

sub BuildSeasons()
    m.seasons = []
    seen = {}
    for each episode in m.episodes
        season = 0
        if episode.DoesExist("season") then season = episode.season
        key = season.ToStr()
        if not seen.DoesExist(key)
            seen[key] = true
            m.seasons.Push(season)
        end if
    end for
    m.seasons.Sort()
end sub

sub RebuildSeasonGrid()
    content = CreateObject("roSGNode", "ContentNode")
    for index = 0 to m.seasons.Count() - 1
        child = content.CreateChild("ContentNode")
        season = m.seasons[index]
        if season = 0
            child.title = TrText("episodes.specials")
        else
            child.title = TrFormat("episodes.season", season)
        end if
        if index = m.selectedSeasonIndex
            child.shortDescriptionLine1 = "selected"
        end if
    end for
    m.seasonGrid.content = content
    m.seasonGrid.JumpToItem = m.selectedSeasonIndex
end sub

sub RebuildEpisodeList()
    m.visibleEpisodes = []
    content = CreateObject("roSGNode", "ContentNode")
    selectedSeason = m.seasons[m.selectedSeasonIndex]

    ' Look up watched indices and last watched info for the series
    watchedIndices = []
    currentVideoId = invalid
    currentTimeOffset = 0
    currentDuration = 0

    seriesId = SafeString(m.selectedItem, "id")
    if m.libraryStore.hasById(seriesId)
        libraryItem = m.libraryStore.getById(seriesId)
        if libraryItem.DoesExist("state") and libraryItem.state <> invalid
            state = libraryItem.state
            if state.DoesExist("watched") and state.watched <> invalid and state.watched <> ""
                info = DecodeWatchedBitfield(state.watched)
                if info <> invalid and info.watchedIndices <> invalid
                    watchedIndices = info.watchedIndices
                end if
            end if
            if state.DoesExist("video_id") then currentVideoId = state.video_id
            if state.DoesExist("timeOffset") then currentTimeOffset = state.timeOffset
            if state.DoesExist("duration") then currentDuration = state.duration
        end if
    end if

    episodeFullIndex = -1
    for each episode in m.episodes
        episodeFullIndex = episodeFullIndex + 1
        season = 0
        if episode.DoesExist("season") then season = episode.season
        if season = selectedSeason
            isWatched = false
            for each idx in watchedIndices
                if idx = episodeFullIndex
                    isWatched = true
                    exit for
                end if
            end for

            progress = 0.0
            episodeId = SafeString(episode, "id")
            if currentVideoId <> invalid and currentVideoId = episodeId
                if currentTimeOffset > 0 and currentDuration > 0
                    progress = currentTimeOffset / currentDuration
                end if
            end if

            m.visibleEpisodes.Push(episode)
            child = content.CreateChild("EpisodeContent")
            
            title = EpisodeTitle(episode)
            if isWatched then title = "✓ " + title
            
            child.title = title
            child.description = EpisodeDescription(episode)
            child.HDPosterUrl = SafeString(episode, "thumbnail")
            child.SDPosterUrl = SafeString(episode, "thumbnail")
            child.episodeLabel = EpisodeNumber(episode).ToStr() + "."
            released = SafeString(episode, "released")
            if Len(released) >= 10 then child.shortDescriptionLine1 = Left(released, 10)
            
            if progress > 0.0 and progress < 0.9
                child.progress = progress
            end if
            if m.settingsStore.getBlurUnwatched() and not isWatched
                child.AddFields({ blurThumbnail: true })
            end if
        end if
    end for

    m.episodeList.content = content
    if m.selectedEpisodeIndex < 0 or m.selectedEpisodeIndex >= m.visibleEpisodes.Count()
        m.selectedEpisodeIndex = 0
    end if
    m.episodeList.JumpToItem = m.selectedEpisodeIndex
end sub

sub onSeasonSelected(event as object)
    index = event.GetData()
    if index < 0 or index >= m.seasons.Count() then return
    m.selectedSeasonIndex = index
    m.selectedEpisodeIndex = 0
    RebuildSeasonGrid()
    RebuildEpisodeList()
    m.episodeList.SetFocus(true)
end sub

sub onEpisodeSelected(event as object)
    index = event.GetData()
    if index < 0 or index >= m.visibleEpisodes.Count() then return
    m.selectedEpisodeIndex = index
    episode = m.visibleEpisodes[index]
    FindStreams("series", SafeString(episode, "id"), EpisodeTitle(episode), "episodes")
end sub

sub ShowEpisodeLoadError(message as string)
    content = CreateObject("roSGNode", "ContentNode")
    child = content.CreateChild("ContentNode")
    child.title = message
    m.choiceTitle.text = "Episodes unavailable"
    m.streamList.visible = false
    m.choiceList.visible = true
    m.choiceList.content = content
    m.choiceMode = "error"
    m.choiceReturnMode = "home"
    m.choiceGroup.visible = true
    m.episodeGroup.visible = false
    m.homeGroup.visible = false
    m.screenMode = "choices"
    m.top.SetFocus(true)
end sub

sub FindStreams(contentType as string, id as string, title as string, returnMode as string)
    m.playbackTitle = title
    m.playbackContentType = contentType
    m.playbackContentId = id
    m.streamReturnMode = returnMode

    if m.addonLoadPending > 0
        m.pendingStreamLookup = {
            contentType: contentType
            id: id
            title: title
            returnMode: returnMode
        }
        ShowStatus(TrText("status.streams.loadingAddons"), true)
        return
    end if

    matchingAddons = []
    installed = m.addonStore.getInstalled()
    for index = 0 to installed.Count() - 1
        if m.addonStore.AddonSupports(installed[index].manifest, "stream", contentType, id)
            matchingAddons.Push(index)
        end if
    end for

    if matchingAddons.Count() = 0
        ShowNoStreamsScreen("No installed add-on can provide a playable stream for this title. Press * to add or configure a stream add-on, then try again.")
        return
    end if

    ShowStatus(TrFormat("status.streams.finding", matchingAddons.Count()), true)
    m.streamRequestSequence = m.streamRequestSequence + 1
    m.activeStreamRequestId = "streams|" + m.streamRequestSequence.ToStr()
    m.streamRequestActive = true
    m.pendingStreamRequests = matchingAddons.Count()
    m.completedStreamRequests = 0
    m.streamRequestErrors = []
    m.streams = []

    for each addonIndex in matchingAddons
        addon = installed[addonIndex]
        url = addon.baseUrl + "/stream/" + contentType + "/" + id + ".json"
        requestId = m.activeStreamRequestId + "|" + addonIndex.ToStr()
        StartStreamRequest(url, requestId)
    end for
end sub

sub ClearActiveStreamRequest()
    m.streamRequestActive = false
    m.activeStreamRequestId = ""
    m.pendingStreamRequests = 0
    m.completedStreamRequests = 0
end sub

sub HandleStreamsResponse(data as object, addonIndex as integer)
    if not m.streamRequestActive then return
    addonName = "Unknown add-on"
    installed = m.addonStore.getInstalled()
    if addonIndex >= 0 and addonIndex < installed.Count()
        addonName = SafeString(installed[addonIndex].manifest, "name")
    end if

    if data <> invalid and data.DoesExist("streams") and data.streams <> invalid
        for each stream in data.streams
            directUrl = DirectStreamUrl(stream)
            if directUrl <> ""
                stream.strokuAddonName = addonName
                m.streams.Push(stream)
            else if stream <> invalid and stream.DoesExist("infoHash")
                ' Torrent-only results have no direct URL. They are listed so the
                ' user can see them, and played back through the dedicated
                ' streaming server when one is configured.
                stream.rokumioTorrent = true
                stream.strokuAddonName = addonName
                m.streams.Push(stream)
            end if
        end for
    end if

    m.completedStreamRequests = m.completedStreamRequests + 1
    if m.completedStreamRequests < m.pendingStreamRequests then return

    ClearActiveStreamRequest()
    HideStatus()
    if m.pendingNextEpisode = invalid then m.selectedStreamIndex = 0

    if m.streams.Count() = 0
        RecoverFromNextEpisodeFailure()
        ShowNoStreamsScreen("The installed add-ons returned no playable streams.")
        return
    end if

    if m.pendingNextEpisode <> invalid
        streamIndex = m.selectedStreamIndex
        if streamIndex < 0 or streamIndex >= m.streams.Count() then streamIndex = 0
        m.selectedStreamIndex = streamIndex
        if DirectStreamUrl(m.streams[streamIndex]) <> ""
            FindSubtitles(m.streams[streamIndex])
            return
        end if
        if m.streams[streamIndex].rokumioTorrent
            serverUrl = m.settingsStore.StreamingServerStreamUrl(m.streams[streamIndex])
            if serverUrl <> ""
                m.streams[streamIndex].url = serverUrl
                FindSubtitles(m.streams[streamIndex])
                return
            end if
        end if
    end if

    ShowChoices("Choose a stream (" + m.streams.Count().ToStr() + ")", BuildStreamContent(), "streams", m.streamReturnMode)
end sub

function DirectStreamUrl(stream as dynamic) as string
    if stream = invalid then return ""
    if Type(stream) <> "roAssociativeArray" and Type(stream) <> "AssociativeArray" then return ""
    if not stream.DoesExist("url") or stream.url = invalid then return ""
    return stream.url.ToStr().Trim()
end function

sub ShowChoices(title as string, content as object, mode as string, returnMode as string)
    m.noStreamsGroup.visible = false
    m.choiceMode = mode
    m.choiceReturnMode = returnMode
    m.choiceTitle.text = title

    if mode = "streams"
        m.choiceList.visible = false
        m.streamList.visible = true
        m.streamList.content = content
        m.streamList.JumpToItem = 0
    else
        m.choiceList.visible = true
        m.streamList.visible = false
        m.choiceList.content = content
        m.choiceList.JumpToItem = 0
    end if

    m.choiceGroup.visible = true
    m.episodeGroup.visible = false
    m.homeGroup.visible = false
    m.screenMode = "choices"

    if mode = "streams"
        m.streamList.SetFocus(true)
    else
        m.choiceList.SetFocus(true)
    end if
end sub

sub ShowNoStreamsScreen(message as string)
    HideStatus()
    m.noStreamsPoster.uri = SafeString(m.selectedItem, "poster")
    m.noStreamsMessage.text = message
    m.noStreamsHint.text = "BACK: Catalog                              *: CONFIGURE ADD-ONS"
    if m.streamReturnMode = "episodes"
        m.noStreamsHint.text = "BACK: Episodes                              *: CONFIGURE ADD-ONS"
    end if

    m.homeGroup.visible = false
    m.episodeGroup.visible = false
    m.choiceGroup.visible = false
    m.noStreamsGroup.visible = true
    m.screenMode = "noStreams"
    m.top.SetFocus(true)
end sub

sub onChoiceFocused(event as object)
    index = event.GetData()
    if m.choiceMode <> "streams" or index < 0 or index >= m.streams.Count() then return
end sub

sub onChoiceSelected(event as object)
    index = event.GetData()
    if index < 0 then return

    if m.choiceMode = "streams"
        if index >= m.streams.Count() then return
        m.selectedStreamIndex = index
        m.playbackReturnMode = "streams"
        stream = m.streams[index]
        if DirectStreamUrl(stream) = ""
            if stream.rokumioTorrent
                serverUrl = m.settingsStore.StreamingServerStreamUrl(stream)
                if serverUrl <> ""
                    stream.url = serverUrl
                    FindSubtitles(stream)
                    return
                end if
            end if
            ShowStatus(TrText("status.streams.torrentNotPlayable"), false)
            return
        end if
        FindSubtitles(stream)
    end if
end sub

sub FindSubtitles(stream as object)
    matchingAddons = []
    installed = m.addonStore.getInstalled()
    for index = 0 to installed.Count() - 1
        if m.addonStore.AddonSupports(installed[index].manifest, "subtitles", m.playbackContentType, m.playbackContentId)
            matchingAddons.Push(index)
        end if
    end for

    m.pendingStream = stream
    m.subtitles = []
    if matchingAddons.Count() = 0
        PlayStream(stream, m.playbackTitle, [])
        return
    end if

    ShowStatus(TrFormat("status.subtitles.finding", matchingAddons.Count()), true)
    m.subtitleRequestSequence = m.subtitleRequestSequence + 1
    m.activeSubtitleRequestId = "subtitles|" + m.subtitleRequestSequence.ToStr()
    m.subtitleRequestActive = true
    m.pendingSubtitleRequests = matchingAddons.Count()
    m.completedSubtitleRequests = 0
    m.subtitleRequestErrors = []

    for each addonIndex in matchingAddons
        addon = installed[addonIndex]
        url = addon.baseUrl + "/subtitles/" + m.playbackContentType + "/" + m.playbackContentId + ".json"
        requestId = m.activeSubtitleRequestId + "|" + addonIndex.ToStr()
        StartRequest(url, requestId)
    end for
end sub

sub ClearActiveSubtitleRequest()
    m.subtitleRequestActive = false
    m.activeSubtitleRequestId = ""
    m.pendingSubtitleRequests = 0
    m.completedSubtitleRequests = 0
end sub

sub HandleSubtitlesResponse(data as object, addonIndex as integer)
    if not m.subtitleRequestActive then return
    addonName = "Unknown add-on"
    installed = m.addonStore.getInstalled()
    if addonIndex >= 0 and addonIndex < installed.Count()
        addonName = SafeString(installed[addonIndex].manifest, "name")
    end if

    if data.DoesExist("subtitles") and data.subtitles <> invalid
        for each subtitle in data.subtitles
            if SafeString(subtitle, "url") <> ""
                subtitle.strokuAddonName = addonName
                m.subtitles.Push(subtitle)
            end if
        end for
    end if

    m.completedSubtitleRequests = m.completedSubtitleRequests + 1
    if m.completedSubtitleRequests < m.pendingSubtitleRequests then return

    ClearActiveSubtitleRequest()
    HideStatus()
    PlayPendingStream()
end sub

sub PlayPendingStream()
    if m.pendingStream = invalid then return
    stream = m.pendingStream
    m.pendingStream = invalid
    PlayStream(stream, m.playbackTitle, m.subtitles)
end sub

sub PlayStream(stream as object, title as string, subtitles as object)
    ' Check for resume progress
    resumeOffsetSec = 0
    libraryItemId = m.playbackContentId
    if m.playbackContentType = "series"
        parts = m.playbackContentId.Split(":")
        libraryItemId = parts[0]
    end if

    if m.libraryStore.hasById(libraryItemId)
        libraryItem = m.libraryStore.getById(libraryItemId)
        if libraryItem.DoesExist("state") and libraryItem.state <> invalid
            state = libraryItem.state
            if state.DoesExist("video_id") and state.video_id = m.playbackContentId
                if state.DoesExist("timeOffset") and state.DoesExist("duration")
                    offset = state.timeOffset / 1000
                    dur = state.duration / 1000
                    if offset > 10 and dur > 0 and offset < 0.9 * dur
                        resumeOffsetSec = offset
                    end if
                end if
            end if
        end if
    end if

    if resumeOffsetSec > 0
        m.pendingPlayStream = stream
        m.pendingPlayTitle = title
        m.pendingPlaySubtitles = subtitles
        m.pendingPlayOffset = resumeOffsetSec

        dialog = CreateObject("roSGNode", "Dialog")
        dialog.title = TrText("dialog.resume.title")
        dialog.message = TrFormat("dialog.resume.message", FormatPlaybackTime(resumeOffsetSec))
        dialog.buttons = [TrText("dialog.resume.resume"), TrText("dialog.resume.startOver")]
        dialog.ObserveField("buttonSelected", "onResumeDialogButton")
        m.resumeDialog = dialog
        m.top.dialog = dialog
    else
        StartPlayback(stream, title, subtitles, 0)
    end if
end sub

sub onResumeDialogButton(event as object)
    buttonIdx = event.GetData()
    m.resumeDialog.close = true
    m.resumeDialog = invalid

    offset = 0
    if buttonIdx = 0
        offset = m.pendingPlayOffset
    end if

    StartPlayback(m.pendingPlayStream, m.pendingPlayTitle, m.pendingPlaySubtitles, offset)
end sub

sub StartPlayback(stream as object, title as string, subtitles as object, startOffsetSec as integer)
    m.lastVideoPosition = startOffsetSec
    m.lastVideoDuration = 0
    content = CreateObject("roSGNode", "ContentNode")
    content.url = stream.url
    content.title = title
    if startOffsetSec > 0
        content.playStart = startOffsetSec
    end if
    playbackHeaders = {}
    subtitleOptions = []

    streamFormat = DetectStreamFormat(stream.url)
    if streamFormat <> "" then content.streamFormat = streamFormat

    if stream.DoesExist("behaviorHints") and stream.behaviorHints <> invalid
        hints = stream.behaviorHints
        if hints.DoesExist("proxyHeaders") and hints.proxyHeaders <> invalid
            proxyHeaders = hints.proxyHeaders
            if proxyHeaders.DoesExist("request") and proxyHeaders.request <> invalid
                playbackHeaders = proxyHeaders.request
            end if
        end if
    end if

    subtitleTracks = []
    languageCounts = {}
    for each subtitle in subtitles
        subtitleUrl = SafeString(subtitle, "url")
        subtitleLanguage = SafeString(subtitle, "lang")
        language = SubtitleLanguageName(subtitleLanguage)
        count = 1
        if languageCounts.DoesExist(language) then count = languageCounts[language] + 1
        languageCounts[language] = count
        label = language + " " + count.ToStr()
        addonName = SafeString(subtitle, "strokuAddonName")
        if addonName <> "" then label = label + " | " + addonName
        subtitleTracks.Push({
            Language: subtitleLanguage
            Description: label
            TrackName: subtitleUrl
        })
        subtitleOptions.Push({
            label: label
            language: language
            trackName: subtitleUrl
        })
    end for
    if subtitleTracks.Count() > 0
        if content.GetFieldType("subtitleTracks") = "array"
            content.subtitleTracks = subtitleTracks
        end if
    end if
    m.video.subtitleTrack = ""
    m.video.globalCaptionMode = "Off"
    m.video.audioTrack = ""
    m.video.selectedSubtitleIndex = -1
    m.video.subtitlesEnabledByDefault = m.settingsStore.getSubtitlesEnabledByDefault()
    m.video.subtitleDefaultMode = m.settingsStore.getSubtitleDefaultMode()
    m.video.defaultSubtitleLanguage = m.settingsStore.getDefaultSubtitleLanguage()
    m.video.lastSubtitleSelection = m.settingsStore.getLastSubtitleSelection()
    m.video.defaultAudioTrack = m.settingsStore.getDefaultAudioTrack()
    m.video.subtitleSyncOffset = LoadSubtitleSyncOffset()
    m.video.hasNextEpisode = HasNextEpisode()
    ApplySubtitleStyle()

    m.choiceGroup.visible = false
    m.noStreamsGroup.visible = false
    m.episodeGroup.visible = false
    m.homeGroup.visible = false
    HideStatus()
    m.video.content = content
    m.video.subtitleOptions = subtitleOptions
    m.video.visible = true
    m.video.SetFocus(true)
    m.screenMode = "video"
    m.video.SetHeaders(playbackHeaders)
    if m.video.GetFieldType("seamlessAudioTrackSelection") = "boolean"
        m.video.seamlessAudioTrackSelection = true
    end if
    m.video.control = "play"
    m.pendingNextEpisode = invalid
end sub

sub PlayExternal(args as object)
    if args = invalid or not args.DoesExist("url") then return
    stream = { url: args.url }
    title = "External stream"
    if args.DoesExist("title") then title = args.title
    m.playbackReturnMode = "home"
    PlayStream(stream, title, [])
end sub

sub onVideoAction(event as object)
    action = event.GetData()
    if action = invalid or not action.DoesExist("type") then return
    if action.type = "close"
        ConfirmExitVideo()
    else if action.type = "next"
        PlayNextEpisode()
    else if action.type = "subtitleSyncOffset"
        if action.DoesExist("offset") then SaveSubtitleSyncOffset(action.offset)
    else if action.type = "subtitleSelection"
        if action.DoesExist("selection")
            m.settingsStore.setLastSubtitleSelection(action.selection)
            m.settingsStore.savePlayerPreferences()
        end if
    end if
end sub

function SubtitleSyncContentKey() as string
    if m.playbackContentId = "" then return ""
    if m.playbackContentType = "series"
        parts = m.playbackContentId.Split(":")
        if parts.Count() > 0 then return parts[0]
    end if
    return m.playbackContentId
end function

function LoadSubtitleSyncOffset() as float
    key = SubtitleSyncContentKey()
    if key = "" then return 0.0

    offsets = LoadSubtitleSyncOffsets()
    if offsets.DoesExist(key)
        return Val(offsets[key].ToStr())
    end if
    return 0.0
end function

sub SaveSubtitleSyncOffset(offset as float)
    key = SubtitleSyncContentKey()
    if key = "" then return

    offsets = LoadSubtitleSyncOffsets()
    if Abs(offset) < 0.01
        if offsets.DoesExist(key) then offsets.Delete(key)
    else
        offsets[key] = offset
    end if

    section = CreateObject("roRegistrySection", "Rokumio")
    section.Write("subtitleSyncOffsets", FormatJson(offsets))
    section.Flush()
end sub

function LoadSubtitleSyncOffsets() as object
    section = CreateObject("roRegistrySection", "Rokumio")
    if section.Exists("subtitleSyncOffsets")
        parsed = ParseJson(section.Read("subtitleSyncOffsets"))
        if parsed <> invalid then return parsed
    end if
    return {}
end function

sub ConfirmExitVideo()
    if m.exitVideoDialog <> invalid then return
    m.video.control = "pause"
    dialog = CreateObject("roSGNode", "Dialog")
    dialog.title = TrText("dialog.exitVideo.title")
    dialog.message = TrText("dialog.exitVideo.message")
    dialog.buttons = [TrText("dialog.exitVideo.stop"), TrText("dialog.exitVideo.keep")]
    dialog.ObserveField("buttonSelected", "onExitVideoDialogButton")
    m.exitVideoDialog = dialog
    m.top.dialog = dialog
end sub

sub onExitVideoDialogButton(event as object)
    buttonIndex = event.GetData()
    m.exitVideoDialog.close = true
    m.exitVideoDialog = invalid
    if buttonIndex = 0
        m.video.control = "stop"
    else
        m.video.control = "resume"
        m.video.SetFocus(true)
    end if
end sub

function HasNextEpisode() as boolean
    return NextEpisodeLocation() <> invalid
end function

function NextEpisodeLocation() as dynamic
    if m.playbackContentType <> "series" then return invalid
    currentId = m.playbackContentId
    foundCurrent = false
    for seasonIndex = 0 to m.seasons.Count() - 1
        season = m.seasons[seasonIndex]
        episodeIndex = 0
        for each episode in m.episodes
            episodeSeason = 0
            if episode.DoesExist("season") then episodeSeason = episode.season
            if episodeSeason = season
                if foundCurrent
                    return {
                        episode: episode
                        seasonIndex: seasonIndex
                        episodeIndex: episodeIndex
                    }
                end if
                if SafeString(episode, "id") = currentId then foundCurrent = true
                episodeIndex = episodeIndex + 1
            end if
        end for
    end for
    return invalid
end function

sub PlayNextEpisode()
    location = NextEpisodeLocation()
    if location = invalid then return

    m.pendingNextEpisode = location
    m.suppressVideoReturn = true
    m.video.control = "stop"
    m.video.visible = false
    m.selectedSeasonIndex = location.seasonIndex
    m.selectedEpisodeIndex = location.episodeIndex
    episode = location.episode
    FindStreams("series", SafeString(episode, "id"), EpisodeTitle(episode), "episodes")
end sub

sub RecoverFromNextEpisodeFailure()
    if m.pendingNextEpisode = invalid then return
    m.pendingNextEpisode = invalid
    ShowEpisodeScreen()
    m.episodeList.SetFocus(true)
end sub

sub onVideoStateChanged(event as object)
    state = event.GetData()
    if m.suppressVideoReturn and (state = "finished" or state = "stopped")
        m.suppressVideoReturn = false
        savedPos = 0
        if m.lastVideoPosition <> invalid then savedPos = Int(m.lastVideoPosition)
        dur = 0
        if m.video.duration <> invalid and m.video.duration > 0
            dur = Int(m.video.duration)
        else if m.lastVideoDuration <> invalid
            dur = Int(m.lastVideoDuration)
        end if
        SavePlaybackProgress(savedPos, dur, false)
        return
    end if
    if state = "playing"
        m.lastProgressSaveTime = 0
    else if state = "error"
        errorText = m.video.errorMsg
        if errorText = invalid or errorText = ""
            errorText = "The Roku could not play this file. Try another release or codec."
        end if
        m.video.visible = false
        ReturnFromVideo()
        ShowStatus(errorText, false)
    else if state = "finished" or state = "stopped"
        isFinished = (state = "finished")
        savedPos = 0
        if not isFinished and m.lastVideoPosition <> invalid
            savedPos = Int(m.lastVideoPosition)
        end if
        dur = 0
        if m.video.duration <> invalid and m.video.duration > 0
            dur = Int(m.video.duration)
        else if m.lastVideoDuration <> invalid
            dur = Int(m.lastVideoDuration)
        end if
        SavePlaybackProgress(savedPos, dur, isFinished)

        m.video.visible = false
        ReturnFromVideo()

        if m.screenMode = "episodes"
            RebuildEpisodeList()
        else if m.screenMode = "home"
            RebuildCatalog()
        end if
    end if
end sub

sub ReturnFromVideo()
    if m.playbackReturnMode = "streams" and m.streams.Count() > 0
        ShowChoices("Choose a stream (" + m.streams.Count().ToStr() + ")", BuildStreamContent(), "streams", m.streamReturnMode)
        if m.selectedStreamIndex >= 0 and m.selectedStreamIndex < m.streams.Count()
            m.streamList.JumpToItem = m.selectedStreamIndex
        end if
    else
        RenderActiveTab(true)
    end if
end sub

sub OpenSettings()
    dialog = CreateObject("roSGNode", "Dialog")
    dialog.title = TrText("dialog.quickActions.title")
    addonLabel = TrText("dialog.quickActions.addAddon")
    if m.addonStore.manifestUrlCount() > 0
        addonLabel = TrFormat("dialog.quickActions.addAddonCount", m.addonStore.manifestUrlCount())
    end if
    if not m.authStore.isSignedIn()
        dialog.message = TrText("dialog.quickActions.messageSignedOut")
        dialog.buttons = [TrText("dialog.quickActions.connect"), addonLabel, TrText("dialog.subtitle.title"), TrText("common.cancel")]
    else
        dialog.message = TrText("dialog.quickActions.messageConnected")
        dialog.buttons = [TrText("dialog.quickActions.refreshLibrary"), TrText("dialog.quickActions.disconnect"), addonLabel, TrText("dialog.subtitle.title"), TrText("common.cancel")]
    end if
    dialog.ObserveField("buttonSelected", "onSettingsButton")
    m.settingsDialog = dialog
    m.top.dialog = dialog
end sub

sub onSettingsButton(event as object)
    button = event.GetData()
    authenticated = m.authStore.isSignedIn()
    m.settingsDialog.close = true

    if not authenticated
        if button = 0
            BeginStremioLink()
        else if button = 1
            OpenAddonConfiguration()
        else if button = 2
            OpenSubtitleSettings()
        end if
    else
        if button = 0
            ShowStatus(TrText("status.refreshingLibrary"), true)
            FetchLibrary()
        else if button = 1
            DisconnectStremio()
        else if button = 2
            OpenAddonConfiguration()
        else if button = 3
            OpenSubtitleSettings()
        end if
    end if
end sub

sub OpenSubtitleSettings()
    dialog = CreateObject("roSGNode", "Dialog")
    dialog.title = TrText("dialog.subtitle.title")
    dialog.message = TrText("dialog.subtitle.message")
    ' Display only. m.subtitle* stay canonical English so the registry and the
    ' NextOption comparisons below never see a translated value.
    defaultSubtitleLabel = TrText("common.off")
    if m.settingsStore.getSubtitlesEnabledByDefault() then defaultSubtitleLabel = TrText("common.on")
    dialog.buttons = [
        TrFormat("dialog.subtitle.defaultChoice", TrOption("subtitle.mode", m.settingsStore.getSubtitleDefaultMode()))
        TrFormat("dialog.subtitle.enableByDefault", defaultSubtitleLabel)
        TrFormat("dialog.subtitle.preset", TrOption("subtitle.preset", m.settingsStore.getSubtitleRenderMode()))
        TrFormat("dialog.subtitle.position", TrOption("subtitle.position", m.settingsStore.getSubtitlePosition()))
        TrFormat("dialog.subtitle.font", TrOption("subtitle.font", m.settingsStore.getSubtitleFont()))
        TrFormat("dialog.subtitle.textSize", TrOption("subtitle.size", m.settingsStore.getSubtitleTextSize()))
        TrFormat("dialog.subtitle.textColor", TrOption("subtitle.color", m.settingsStore.getSubtitleTextColor()))
        TrFormat("dialog.subtitle.backdrop", TrOption("subtitle.backdrop", m.settingsStore.getSubtitleBackdropOpacity()))
        TrText("common.done")
    ]
    dialog.ObserveField("buttonSelected", "onSubtitleSettingsButton")
    m.subtitleSettingsDialog = dialog
    m.top.dialog = dialog
end sub

sub onSubtitleSettingsButton(event as object)
    button = event.GetData()
    m.subtitleSettingsDialog.close = true
    if button = 0
        m.settingsStore.setSubtitleDefaultMode(NextOption(["Default language", "Last selected"], m.settingsStore.getSubtitleDefaultMode()))
    else if button = 1
        m.settingsStore.setSubtitlesEnabledByDefault(not m.settingsStore.getSubtitlesEnabledByDefault())
    else if button = 2
        m.settingsStore.setSubtitleRenderMode(NextOption(["Below video", "Native"], m.settingsStore.getSubtitleRenderMode()))
    else if button = 3
        m.settingsStore.setSubtitlePosition(NextOption(["Bottom bar", "Low", "Higher"], m.settingsStore.getSubtitlePosition()))
    else if button = 4
        m.settingsStore.setSubtitleFont(NextOption(["Default", "Sans Serif Proportional", "Serif Proportional", "Casual", "Small Caps"], m.settingsStore.getSubtitleFont()))
    else if button = 5
        m.settingsStore.setSubtitleTextSize(NextOption(["Small", "Medium", "Large"], m.settingsStore.getSubtitleTextSize()))
    else if button = 6
        m.settingsStore.setSubtitleTextColor(NextOption(["White", "Yellow", "Cyan", "Green", "Black"], m.settingsStore.getSubtitleTextColor()))
    else if button = 7
        m.settingsStore.setSubtitleBackdropOpacity(NextOption(["Off", "25%", "50%", "75%", "100%"], m.settingsStore.getSubtitleBackdropOpacity()))
    else
        return
    end if

    m.settingsStore.saveSubtitlePreferences()
    ApplySubtitleStyle()
    OpenSubtitleSettings()
end sub

sub ApplySubtitleStyle()
    m.video.subtitlesEnabledByDefault = m.settingsStore.getSubtitlesEnabledByDefault()
    m.video.subtitleDefaultMode = m.settingsStore.getSubtitleDefaultMode()
    m.video.subtitleRenderMode = m.settingsStore.getSubtitleRenderMode()
    m.video.customSubtitleTextSize = m.settingsStore.getSubtitleTextSize()
    m.video.customSubtitleTextColor = m.settingsStore.getSubtitleTextColor()
    m.video.customSubtitleBackdropOpacity = m.settingsStore.getSubtitleBackdropOpacity()
    m.video.customSubtitlePosition = m.settingsStore.getSubtitlePosition()
    ' Outline colour and font are drawn by the player's own subtitle labels. The
    ' Video node has no settable caption style: Roku owns system captions, so an
    ' assignment here would be silently discarded.
    m.video.customSubtitleOutlineColor = m.settingsStore.getSubtitleOutlineColor()
    m.video.customSubtitleFont = m.settingsStore.getSubtitleFont()
end sub

sub OpenSettingsLink(kind as string)
    ' The support link is the one link a viewer is expected to act on, so it gets
    ' a scannable code instead of a URL they would have to copy off the screen.
    if kind = "coffee"
        OpenCoffeeSupport(true)
        return
    end if

    dialog = CreateObject("roSGNode", "Dialog")
    ' The address and the URLs are identifiers, not prose: they stay exactly as
    ' authored in every language.
    if kind = "support"
        dialog.title = TrText("dialog.link.support.title")
        dialog.message = TrText("dialog.link.support.message") + Chr(10) + "https://github.com/gpratoe/rokumio-client/issues"
    else if kind = "source"
        dialog.title = TrText("dialog.link.source.title")
        dialog.message = TrText("dialog.link.source.message") + Chr(10) + "https://github.com/gpratoe/rokumio-client"
    else if kind = "terms"
        dialog.title = TrText("dialog.link.terms.title")
        dialog.message = TrText("dialog.link.terms.message") + Chr(10) + "https://www.stremio.com/tos"
    else
        dialog.title = TrText("dialog.link.privacy.title")
        dialog.message = TrText("dialog.link.privacy.message") + Chr(10) + "https://www.stremio.com/privacy"
    end if
    dialog.buttons = [TrText("common.done")]
    m.top.dialog = dialog
end sub

sub CycleInterfaceLanguage()
    m.settingsStore.setInterfaceLanguage(NextOption(LocaleLanguages(), m.settingsStore.getInterfaceLanguage()))
    m.settingsStore.saveInterfacePreferences()
    ' Publish before re-rendering, and rebuild the nav too: the language change has
    ' to reach every surface at once, not just the row that triggered it.
    SetLocaleLanguage(m.settingsStore.getInterfaceLanguage())
    UpdateNavContent()
    ApplyStaticChromeText()
    ' The playback overlay is a sibling of the nav, not a child of it, so it has
    ' to be told separately.
    if m.video <> invalid then m.video.CallFunc("ApplyLocale", invalid)
    RenderSettings(true)
end sub

' Labels that MainScene.xml authors once and no render pass ever rewrites. They
' are authored in English so the layout stays readable in the XML; this is what
' makes them follow UI Language, at startup and on every change.
sub ApplyStaticChromeText()
    ApplyChromeLabel("searchPrompt", TrText("dialog.search.title"))
    ApplyChromeLabel("noStreamsTitle", TrText("noStreams.title"))
    ApplyChromeLabel("noStreamsConfigureHint", TrText("noStreams.configureHint"))
    ApplyChromeLabel("uiScaleTitle", TrText("settings.interface.uiScale"))
    ApplyChromeLabel("supportChipLabel", TrText("topbar.support"))
end sub

sub ApplyChromeLabel(id as string, text as string)
    node = m.top.FindNode(id)
    if node <> invalid then node.text = text
end sub

sub CycleDefaultSubtitleLanguage()
    m.settingsStore.setDefaultSubtitleLanguage(NextOption(["English", "Spanish", "French", "German", "Italian", "Portuguese", "None"], m.settingsStore.getDefaultSubtitleLanguage()))
    m.settingsStore.savePlayerPreferences()
    RenderSettings(true)
end sub

sub CycleSubtitleOutlineColor()
    m.settingsStore.setSubtitleOutlineColor(NextOption(["White", "Black", "Yellow", "Cyan", "Green"], m.settingsStore.getSubtitleOutlineColor()))
    m.settingsStore.savePlayerPreferences()
    ApplySubtitleStyle()
    RenderSettings(true)
end sub

sub CycleDefaultAudioTrack()
    m.settingsStore.setDefaultAudioTrack(NextOption(["English", "Original", "Spanish", "French", "German", "Any"], m.settingsStore.getDefaultAudioTrack()))
    m.settingsStore.savePlayerPreferences()
    RenderSettings(true)
end sub

sub BeginStremioLink()
    ShowStatus(TrText("status.link.creating"), true)
    req = m.authStore.buildLinkCreate()
    StartRequest(req.url, req.id)
end sub

sub HandleLinkCreateResponse(data as object)
    result = m.authStore.handleLinkCreateResponse(data)
    if not result.success
        ShowStatus(result.message, false)
        return
    end if

    HideStatus()
    dialog = CreateObject("roSGNode", "Dialog")
    dialog.title = TrText("dialog.connect.title")
    ' One key per line, each carrying its own {0}, so a language can put the URL
    ' or the code wherever its word order needs it. The line break travels with
    ' the URL so the address keeps a line of its own.
    dialog.message = TrFormat("dialog.connect.openUrl", Chr(10) + m.authStore.getLinkUrl()) + Chr(10) + Chr(10) + TrFormat("dialog.connect.code", m.authStore.getLinkCode()) + Chr(10) + TrText("dialog.connect.waiting")
    dialog.buttons = [TrText("common.cancel")]
    dialog.ObserveField("buttonSelected", "onLinkDialogButton")
    m.linkDialog = dialog
    m.top.dialog = dialog
    m.linkPollTimer.control = "start"
end sub

sub onLinkDialogButton(event as object)
    m.linkPollTimer.control = "stop"
    m.authStore.cancelLink()
    m.linkDialog.close = true
end sub

sub onLinkPollTimer()
    if not m.authStore.hasActiveLink() then return
    req = m.authStore.buildLinkRead()
    StartRequest(req.url, req.id)
end sub

sub HandleLinkReadResponse(data as object)
    authKey = m.authStore.handleLinkReadResponse(data)
    if authKey = "" then return

    m.linkPollTimer.control = "stop"
    if m.linkDialog <> invalid then m.linkDialog.close = true
    ShowStatus(TrText("status.link.connected"), true)
    FetchLibrary()
end sub

sub DisconnectStremio()
    m.authStore.disconnect()
    m.libraryStore.clear()
    m.calendarStore.reset()
    m.libraryRows = [[]]
    RenderActiveTab(true)
    ShowStatus(TrText("status.link.disconnected"), false)
end sub

sub FetchLibrary()
    if not m.authStore.isSignedIn() then return
    req = m.libraryStore.fetch(m.authStore.getAuthKey())
    StartPostRequest(req.url, req.id, req.body)
end sub

sub HandleLibraryResponse(data as object)
    if not m.libraryStore.handleGetResponse(data)
        ShowStatus(TrText("status.library.rejected"), false)
        return
    end if

    if m.activeTab = "library"
        RenderLibrary(false)
    else
        RebuildCatalog()
    end if
    HideStatus()
    if m.screenMode = "episodes"
        m.episodeList.SetFocus(true)
    end if
end sub

sub HandleLibraryPutResponse(data as object)
    if not m.libraryStore.handlePutResponse(data)
        ShowStatus(TrText("status.library.updateFailed"), false)
        return
    end if
    ShowStatus(TrText("status.library.updated"), true)
    FetchLibrary()
end sub

sub OpenAddonConfiguration()
    dialog = CreateObject("roSGNode", "KeyboardDialog")
    dialog.title = TrText("dialog.manifest.title")
    dialog.message = TrText("dialog.manifest.message")
    dialog.text = ""
    dialog.buttons = ["Save", "Cancel"]
    dialog.ObserveField("buttonSelected", "onConfigurationButton")
    m.keyboardDialog = dialog
    m.top.dialog = dialog
end sub

sub ShowSetupAddress(args as object)
    if args = invalid or not args.DoesExist("url") or args.url = ""
        m.setupAddress.text = "Phone setup unavailable. Press * to configure."
        return
    end if

    m.setupAddress.text = "Phone setup: " + args.url
end sub

sub onConfigurationUrlChanged(event as object)
    url = event.GetData().Trim()
    if not IsValidManifestUrl(url)
        ShowStatus(TrText("status.addon.invalidUrlFromPhone"), false)
        return
    end if

    VerifyAddonConfiguration(url, "Verifying add-on received from your phone...")
end sub

sub onConfigurationButton(event as object)
    button = event.GetData()
    if button <> 0
        m.keyboardDialog.close = true
        return
    end if

    url = m.keyboardDialog.text.Trim()
    if not IsValidManifestUrl(url)
        m.keyboardDialog.message = "Enter a complete HTTPS URL ending in /manifest.json."
        return
    end if

    m.keyboardDialog.close = true
    VerifyAddonConfiguration(url, "Verifying Stremio add-on...")
end sub

function IsValidManifestUrl(url as string) as boolean
    return Left(LCase(url), 8) = "https://" and Right(LCase(url), 14) = "/manifest.json"
end function

sub OpenStreamingServerConfiguration()
    dialog = CreateObject("roSGNode", "KeyboardDialog")
    dialog.title = TrText("dialog.streamingServer.title")
    dialog.message = TrText("dialog.streamingServer.message")
    dialog.text = m.settingsStore.getStreamingServerUrl()
    dialog.buttons = ["Save", "Cancel"]
    dialog.ObserveField("buttonSelected", "onStreamingServerButton")
    m.keyboardDialog = dialog
    m.top.dialog = dialog
end sub

sub onStreamingServerButton(event as object)
    button = event.GetData()
    if button <> 0
        m.keyboardDialog.close = true
        return
    end if

    url = NormalizeStreamingServerUrl(m.keyboardDialog.text)
    if not IsValidStreamingServerUrl(url)
        m.keyboardDialog.message = TrText("dialog.streamingServer.invalid")
        return
    end if

    m.keyboardDialog.close = true
    m.settingsStore.setStreamingServerUrl(url)
    m.settingsStore.saveStreamingServerConfig()
    RenderSettings(true)
    TestStreamingServer()
end sub

sub onStreamingServerUrlChanged(event as object)
    url = NormalizeStreamingServerUrl(event.GetData())
    if not IsValidStreamingServerUrl(url)
        ShowStatus(TrText("status.server.invalidFromPhone"), false)
        return
    end if

    m.settingsStore.setStreamingServerUrl(url)
    m.settingsStore.saveStreamingServerConfig()
    TestStreamingServer()
end sub

sub TestStreamingServer()
    if not m.settingsStore.StreamingServerConfigured() then return
    ShowStatus(TrText("status.server.testing"), true)
    StartServerTestRequest()
end sub

sub StartServerTestRequest()
    task = CreateObject("roSGNode", "HttpTask")
    task.url = m.settingsStore.getStreamingServerUrl() + "/heartbeat"
    task.requestId = "serverTest"
    task.timeoutMs = 8000
    task.ObserveField("response", "onHttpResponse")
    m.tasks.Push(task)
    task.control = "RUN"
end sub

sub VerifyAddonConfiguration(url as string, message as string)
    spec = m.addonStore.verify(url)
    ShowStatus(message, true)
    StartRequest(spec.url, spec.id)
end sub

sub HandleLoadedAddon(manifest as object, urlIndex as integer)
    m.addonStore.handleManifestLoadResponse(manifest, urlIndex)
    if m.activeTab = "addons" then RenderAddons(false)
    CompleteAddonLoad()
end sub

sub CompleteAddonLoad()
    if m.addonLoadPending > 0 then m.addonLoadPending = m.addonLoadPending - 1

    ' A reload raised a spinner that only the last response can clear, including
    ' the response that failed.
    if m.addonLoadPending <= 0 and m.addonReloadActive
        m.addonReloadActive = false
        HideStatus()
        if m.activeTab = "addons" then RenderAddons(false)
    end if

    if m.addonLoadPending > 0 or m.pendingStreamLookup = invalid then return

    lookup = m.pendingStreamLookup
    m.pendingStreamLookup = invalid
    FindStreams(lookup.contentType, lookup.id, lookup.title, lookup.returnMode)
end sub

sub ShowStatus(message as string, spinning as boolean)
    m.statusLabel.text = message
    m.statusLabel.visible = true
    m.statusBackdrop.visible = true
    m.spinner.visible = spinning
end sub

sub HideStatus()
    m.statusLabel.visible = false
    m.statusBackdrop.visible = false
    m.spinner.visible = false
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    if m.exitVideoDialog <> invalid or m.exitAppDialog <> invalid
        return false
    end if

    if m.screenMode = "coffee"
        swallow = m.coffeeSwallowOk
        m.coffeeSwallowOk = false
        if key = "OK" and swallow then return true
        if key = "OK" or key = "back"
            CloseCoffeeSupport()
        end if
        return true
    end if

    if m.screenMode = "uiScale"
        if key = "left"
            SetUiScalePercent(m.settingsStore.getUiScalePendingPercent() - UiScaleStepPercent())
        else if key = "right"
            SetUiScalePercent(m.settingsStore.getUiScalePendingPercent() + UiScaleStepPercent())
        else if key = "options"
            SetUiScalePercent(UiScaleDefaultPercent())
        else if key = "OK"
            CloseUiScaleSlider(true)
        else if key = "back"
            CloseUiScaleSlider(false)
        end if
        return true
    end if

    if key = "options" and m.screenMode <> "video"
        if m.screenMode = "episodes" or (m.screenMode = "choices" and m.choiceMode = "streams")
            result = m.libraryStore.toggle(m.selectedItem, m.authStore.getAuthKey())
            if result.mode = "login"
                BeginStremioLink()
            else if result.mode = "put"
                ShowStatus(result.message, true)
                StartPostRequest(result.request.url, result.request.id, result.request.body)
            end if
        else if m.screenMode = "noStreams"
            OpenAddonConfiguration()
        else if m.activeTab = "discover"
            OpenDiscoverFilters()
        else if m.activeTab = "addons"
            OpenAddonConfiguration()
        else if m.activeTab = "settings"
            if m.settingsTabIndex = 2
                OpenSubtitleSettings()
            else
                OpenSettings()
            end if
        else
            OpenSettings()
        end if
        return true
    end if

    if m.screenMode = "home"
        if m.topBarFocus >= 0
            if key = "left" and m.topBarFocus > 0
                m.topBarFocus = m.topBarFocus - 1
                UpdateTopBar()
            else if key = "left"
                ' Leftmost item: fall out of the top bar to the nav rail, the
                ' same way the Addons chip row does.
                BlurTopBar()
                m.navList.SetFocus(true)
            else if key = "right" and m.topBarFocus < TopBarItemCount() - 1
                m.topBarFocus = m.topBarFocus + 1
                UpdateTopBar()
            else if key = "OK"
                ActivateTopBarItem(m.topBarFocus)
            else if key = "down" or key = "back"
                BlurTopBar()
                FocusActiveContent()
            end if
            return true
        else if m.activeTab = "discover" and m.discoverFilterFocus >= 0
            if key = "left" and m.discoverFilterFocus > 0
                m.discoverFilterFocus = m.discoverFilterFocus - 1
                UpdateDiscoverFilterFocus()
                return true
            else if key = "right" and m.discoverFilterFocus < 2
                m.discoverFilterFocus = m.discoverFilterFocus + 1
                UpdateDiscoverFilterFocus()
                return true
            else if key = "OK"
                CycleDiscoverFilter(m.discoverFilterFocus)
                return true
            else if key = "down"
                BlurDiscoverFilters()
                m.discoverGrid.SetFocus(true)
                return true
            else if key = "back"
                BlurDiscoverFilters()
                m.discoverGrid.SetFocus(true)
                return true
            else if key = "up"
                BlurDiscoverFilters()
                FocusTopBar(0)
                return true
            end if
        else if key = "left" and not m.navList.HasFocus()
            m.navList.SetFocus(true)
            return true
        else if key = "right" and m.navList.HasFocus()
            if m.settingsScreen.visible
                RequestSettingsFocus()
            else if m.calendarGroup.visible
                m.calendarList.SetFocus(true)
            else if m.addonsScreen.visible
                ' RequestAddonsFocus routes to the component's inner list, keeping
                ' the Addons chip row and card list inside the component.
                RequestAddonsFocus()
            else if m.primaryInfoGroup.visible
                m.primaryInfoList.SetFocus(true)
            else if m.activeTab = "discover"
                m.discoverGrid.SetFocus(true)
            else
                m.catalogList.SetFocus(true)
            end if
            return true
        else if key = "up" and not m.navList.HasFocus()
            if m.activeTab = "discover"
                FocusDiscoverFilters()
                return true
            end if
            if m.activeTab = "addons" and m.addonsScreen.visible
                m.addonsScreen.callFunc("FocusChips")
                return true
            end if
            FocusTopBar(0)
            return true
        end if
    else if m.screenMode = "episodes"
        if key = "down" and m.seasonGrid.HasFocus()
            m.episodeList.SetFocus(true)
            return true
        else if key = "up" and m.episodeList.HasFocus()
            m.seasonGrid.SetFocus(true)
            return true
        else if key = "left" and m.seasonGrid.HasFocus() and m.selectedSeasonIndex > 0
            m.selectedSeasonIndex = m.selectedSeasonIndex - 1
            m.selectedEpisodeIndex = 0
            RebuildSeasonGrid()
            RebuildEpisodeList()
            return true
        else if key = "right" and m.seasonGrid.HasFocus() and m.selectedSeasonIndex < m.seasons.Count() - 1
            m.selectedSeasonIndex = m.selectedSeasonIndex + 1
            m.selectedEpisodeIndex = 0
            RebuildSeasonGrid()
            RebuildEpisodeList()
            return true
        else if key = "left" and m.episodeList.HasFocus() and m.selectedSeasonIndex > 0
            m.selectedSeasonIndex = m.selectedSeasonIndex - 1
            m.selectedEpisodeIndex = 0
            RebuildSeasonGrid()
            RebuildEpisodeList()
            return true
        else if key = "right" and m.episodeList.HasFocus() and m.selectedSeasonIndex < m.seasons.Count() - 1
            m.selectedSeasonIndex = m.selectedSeasonIndex + 1
            m.selectedEpisodeIndex = 0
            RebuildSeasonGrid()
            RebuildEpisodeList()
            return true
        end if
    end if

    if key = "back"
        if m.statusLabel.visible and not m.spinner.visible
            HideStatus()
            if m.screenMode = "choices" then m.choiceList.SetFocus(true)
            return true
        end if

        if m.streamRequestActive
            ClearActiveStreamRequest()
            HideStatus()
            if m.screenMode = "episodes"
                m.episodeList.SetFocus(true)
            else
                m.top.SetFocus(true)
            end if
            return true
        end if

        if m.pendingStreamLookup <> invalid
            m.pendingStreamLookup = invalid
            HideStatus()
            m.top.SetFocus(true)
            return true
        end if

        if m.subtitleRequestActive
            ClearActiveSubtitleRequest()
            HideStatus()
            ShowChoices("Choose a stream (" + m.streams.Count().ToStr() + ")", BuildStreamContent(), "streams", m.streamReturnMode)
            m.streamList.JumpToItem = m.selectedStreamIndex
            return true
        end if

        if m.screenMode = "video"
            ConfirmExitVideo()
            return true
        else if m.screenMode = "choices" or m.screenMode = "episodeLoading"
            m.choiceGroup.visible = false
            if m.choiceReturnMode = "home"
                m.episodeRequestActive = false
                HideStatus()
                RenderActiveTab(true)
            else if m.choiceReturnMode = "episodes"
                ShowEpisodeScreen()
                m.episodeList.SetFocus(true)
            else
                RenderActiveTab(true)
            end if
            return true
        else if m.screenMode = "noStreams"
            m.noStreamsGroup.visible = false
            if m.streamReturnMode = "episodes"
                ShowEpisodeScreen()
                m.episodeList.SetFocus(true)
            else
                RenderActiveTab(true)
            end if
            return true
        else if m.screenMode = "episodes"
            HideStatus()
            m.episodeGroup.visible = false
            RenderActiveTab(true)
            return true
        else if m.screenMode = "home"
            if m.activeTab <> "board"
                SetActiveTab("board", true)
            else
                ConfirmExitApp()
            end if
            return true
        else if m.statusLabel.visible
            HideStatus()
            return true
        end if
    end if

    return false
end function

function StreamLabels() as object
    labels = []
    for each stream in m.streams
        labels.Push(StreamListLabel(stream))
    end for
    return labels
end function

function NextOption(options as object, currentValue as string) as string
    for index = 0 to options.Count() - 1
        if options[index] = currentValue
            return options[(index + 1) mod options.Count()]
        end if
    end for
    return options[0]
end function

function SubtitleLanguageName(code as string) as string
    names = {
        eng: "English"
        spa: "Spanish"
        fre: "French"
        fra: "French"
        ger: "German"
        deu: "German"
        ita: "Italian"
        por: "Portuguese"
        dut: "Dutch"
        nld: "Dutch"
        pol: "Polish"
        rus: "Russian"
        ukr: "Ukrainian"
        tur: "Turkish"
        ara: "Arabic"
        chi: "Chinese"
        zho: "Chinese"
        jpn: "Japanese"
        kor: "Korean"
        hin: "Hindi"
        swe: "Swedish"
        nor: "Norwegian"
        dan: "Danish"
        fin: "Finnish"
        cze: "Czech"
        ces: "Czech"
        rum: "Romanian"
        ron: "Romanian"
        hun: "Hungarian"
        gre: "Greek"
        ell: "Greek"
        heb: "Hebrew"
    }
    normalized = LCase(code)
    if names.DoesExist(normalized) then return names[normalized]
    if code = "" then return TrText("common.unknown")
    return UCase(code)
end function

function SeriesMetaLine(meta as object) as string
    parts = []
    runtime = SafeString(meta, "runtime")
    releaseInfo = SafeString(meta, "releaseInfo")
    rating = SafeString(meta, "imdbRating")
    if runtime <> "" then parts.Push(runtime)
    if releaseInfo <> "" then parts.Push(releaseInfo)
    if rating <> "" then parts.Push("IMDb " + rating)
    if meta <> invalid and meta.DoesExist("genres") and meta.genres <> invalid
        for each genre in meta.genres
            if parts.Count() >= 6 then exit for
            parts.Push(genre)
        end for
    end if
    return JoinStrings(parts, "  |  ")
end function

function EpisodeTitle(episode as object) as string
    title = SafeString(episode, "name")
    if title = "" then title = SafeString(episode, "title")
    return title
end function

function EpisodeDescription(episode as object) as string
    description = SafeString(episode, "overview")
    if description = "" then description = SafeString(episode, "description")
    return description
end function

function EpisodeNumber(episode as object) as integer
    if episode <> invalid and episode.DoesExist("episode") then return episode.episode
    if episode <> invalid and episode.DoesExist("number") then return episode.number
    return 0
end function

function StreamListLabel(stream as object) as string
    quality = LastNonEmptyLine(SafeString(stream, "name"))
    if quality = "" then quality = LastNonEmptyLine(SafeString(stream, "title"))
    if quality = "" then quality = "Direct stream"
    metadata = TorrentMetadataLine(SafeString(stream, "title"))
    addonName = SafeString(stream, "strokuAddonName")
    if metadata <> "" then quality = quality + " | " + metadata
    if addonName <> "" then quality = quality + " | " + addonName
    return quality
end function

function StreamDetails(stream as object) as string
    title = SafeString(stream, "title")
    if title = "" then title = SafeString(stream, "name")

    details = ReplaceNewlines(title)
    addonName = SafeString(stream, "strokuAddonName")
    if addonName <> "" then details = addonName + Chr(10) + details
    if stream.DoesExist("behaviorHints") and stream.behaviorHints <> invalid
        hints = stream.behaviorHints
        if hints.DoesExist("bingeGroup") and hints.bingeGroup <> invalid
            groupDetails = hints.bingeGroup.Replace("|", " | ")
            if groupDetails <> "" then details = details + Chr(10) + groupDetails
        end if
    end if
    return details
end function

function BuildStreamContent() as object
    content = CreateObject("roSGNode", "ContentNode")
    for each stream in m.streams
        child = content.CreateChild("ContentNode")
        child.addFields({
            sourceBadge: "",
            addonName: "",
            quality: "",
            seeds: "",
            sizeText: "",
            tracker: ""
        })
        child.title = StreamCardTitle(stream)
        child.sourceBadge = StreamSourceBadge(stream)
        addonNameText = StreamAddonName(stream)
        child.addonName = addonNameText
        child.quality = StreamQuality(stream)
        
        metadataText = StreamMetadataText(stream)
        child.seeds = ExtractSeeders(metadataText)
        child.sizeText = ExtractSize(metadataText)
        child.tracker = ExtractTracker(metadataText, addonNameText)
    end for
    return content
end function

function StreamMetadataText(stream as object) as string
    metadataText = MetadataLineFromText(SafeString(stream, "title"))
    if metadataText <> "" then return metadataText

    metadataText = MetadataLineFromText(SafeString(stream, "description"))
    if metadataText <> "" then return metadataText

    metadataText = MetadataLineFromText(SafeString(stream, "name"))
    if metadataText <> "" then return metadataText

    if stream.DoesExist("behaviorHints") and stream.behaviorHints <> invalid
        hints = stream.behaviorHints
        metadataText = MetadataLineFromText(SafeString(hints, "bingeGroup"))
        if metadataText <> "" then return metadataText
    end if

    return ""
end function

function MetadataLineFromText(value as string) as string
    if value = "" then return ""
    normalized = value.Replace(Chr(13), "")
    for each line in normalized.Tokenize(Chr(10))
        candidate = line.Trim()
        if ExtractSize(candidate) <> "" or ExtractSeeders(candidate) <> ""
            return candidate
        end if
    end for
    return ""
end function

function StreamCardTitle(stream as object) as string
    title = SafeString(stream, "title")
    if title = "" then title = SafeString(stream, "name")
    return FirstLine(title)
end function

function StreamSourceBadge(stream as object) as string
    name = SafeString(stream, "name")
    if name = "" then name = SafeString(stream, "title")
    firstLineText = FirstLine(name)
    return ExtractSourceTag(firstLineText)
end function

function StreamAddonName(stream as object) as string
    name = SafeString(stream, "name")
    if name = "" then name = SafeString(stream, "title")
    firstLineText = FirstLine(name)
    badge = ExtractSourceTag(firstLineText)
    if badge <> ""
        firstLineText = firstLineText.Replace(badge, "").Trim()
    end if
    if firstLineText <> "" then return firstLineText
    return SafeString(stream, "strokuAddonName")
end function

function StreamQuality(stream as object) as string
    name = SafeString(stream, "name")
    if name = "" then return "Direct"
    lines = name.Replace(Chr(13), "").Tokenize(Chr(10))
    if lines.Count() >= 2
        return lines[lines.Count() - 1].Trim()
    end if
    
    ' If only one line, let's see if we can extract quality from the title or filename
    title = SafeString(stream, "title")
    if title <> ""
        lowerTitle = LCase(title)
        if Instr(1, lowerTitle, "2160p") > 0 or Instr(1, lowerTitle, "4k") > 0
            return "2160p"
        else if Instr(1, lowerTitle, "1080p") > 0
            return "1080p"
        else if Instr(1, lowerTitle, "720p") > 0
            return "720p"
        else if Instr(1, lowerTitle, "480p") > 0
            return "480p"
        end if
    end if
    
    ' Check if the first line itself has quality info
    fLineText = lines[0].Trim()
    lowerFirst = LCase(fLineText)
    if Instr(1, lowerFirst, "2160p") > 0 or Instr(1, lowerFirst, "4k") > 0
        return "2160p"
    else if Instr(1, lowerFirst, "1080p") > 0
        return "1080p"
    else if Instr(1, lowerFirst, "720p") > 0
        return "720p"
    end if

    return "Direct"
end function

function ExtractSeeders(secondLineText as string) as string
    if secondLineText = "" then return ""
    tokens = secondLineText.Tokenize(" ")
    for i = 0 to tokens.Count() - 1
        token = tokens[i].Trim()
        lower = LCase(token)
        if Instr(1, token, Chr(128100)) > 0
            if i + 1 < tokens.Count() then return tokens[i+1].Trim()
        end if
        if lower = "seeds:" or lower = "seeders:" or lower = "peers:" or lower = "s:"
            if i + 1 < tokens.Count() then return tokens[i+1].Trim()
        end if
        if lower = "seeds" or lower = "seeders" or lower = "peers"
            if i > 0 then return tokens[i-1].Trim()
        end if
    end for
    if tokens.Count() >= 2 and IsNumericText(tokens[1])
        return tokens[1].Trim()
    end if
    return ""
end function

function ExtractSize(secondLineText as string) as string
    if secondLineText = "" then return ""
    tokens = secondLineText.Tokenize(" ")
    for i = 0 to tokens.Count() - 1
        token = tokens[i].Trim()
        lower = LCase(token)
        if Instr(1, token, Chr(128190)) > 0
            if i + 1 < tokens.Count()
                nextToken = tokens[i+1].Trim()
                if IsSizeUnit(nextToken)
                    return nextToken
                end if
                if i + 2 < tokens.Count() and IsSizeUnit(tokens[i+2])
                    return nextToken + " " + tokens[i+2].Trim()
                end if
                return nextToken
            end if
        end if
        if IsSizeUnit(token)
            firstChar = Left(token, 1)
            if firstChar >= "0" and firstChar <= "9"
                return token
            else if i > 0
                return tokens[i-1].Trim() + " " + token
            end if
        end if
    end for
    return ""
end function

function IsSizeUnit(token as string) as boolean
    lower = LCase(token)
    return Right(lower, 2) = "gb" or Right(lower, 2) = "mb" or Right(lower, 2) = "kb" or Right(lower, 3) = "gib" or Right(lower, 3) = "mib" or Right(lower, 3) = "kib"
end function

function ExtractTracker(secondLineText as string, addonName as string) as string
    if secondLineText = "" then return addonName
    tokens = secondLineText.Tokenize(" ")
    for i = 0 to tokens.Count() - 1
        token = tokens[i].Trim()
        lower = LCase(token)
        if Instr(1, token, Chr(9881)) > 0
            if i + 1 < tokens.Count() then return tokens[i+1].Trim()
        end if
        if lower = "tracker:" or lower = "provider:" or lower = "p:"
            if i + 1 < tokens.Count() then return tokens[i+1].Trim()
        end if
    end for
    for i = 0 to tokens.Count() - 1
        if IsSizeUnit(tokens[i])
            for j = i + 1 to tokens.Count() - 1
                candidate = tokens[j].Trim()
                if candidate <> "" and HasAlphaNumeric(candidate) and not IsNumericText(candidate) and not IsMetadataLabel(candidate)
                    return candidate
                end if
            end for
        end if
    end for
    return addonName
end function

function IsMetadataLabel(value as string) as boolean
    lower = LCase(value)
    return lower = "seeds" or lower = "seeders" or lower = "peers" or lower = "seeds:" or lower = "seeders:" or lower = "peers:" or lower = "tracker:" or lower = "provider:" or lower = "size:" or lower = "s:" or lower = "p:"
end function

function IsNumericText(value as string) as boolean
    if value = "" then return false
    hasDigit = false
    for i = 1 to Len(value)
        char = Mid(value, i, 1)
        if char >= "0" and char <= "9"
            hasDigit = true
        else if char <> "." and char <> ","
            return false
        end if
    end for
    return hasDigit
end function

function HasAlphaNumeric(value as string) as boolean
    for i = 1 to Len(value)
        char = Mid(value, i, 1)
        if char >= "0" and char <= "9" then return true
        if char >= "A" and char <= "Z" then return true
        if char >= "a" and char <= "z" then return true
    end for
    return false
end function

function FirstLine(value as string) as string
    if value = "" then return ""
    normalized = value.Replace(Chr(13), "")
    parts = normalized.Tokenize(Chr(10))
    if parts.Count() = 0 then return ""
    return parts[0].Trim()
end function

function SecondLine(value as string) as string
    if value = "" then return ""
    normalized = value.Replace(Chr(13), "")
    parts = normalized.Tokenize(Chr(10))
    if parts.Count() < 2 then return ""
    return parts[1].Trim()
end function

function ExtractSourceTag(line as string) as string
    if line = "" then return ""
    bracketEnd = Instr(1, line, "]")
    if bracketEnd > 1 and Left(line, 1) = "["
        return Left(line, bracketEnd)
    end if
    return ""
end function

function LastNonEmptyLine(value as string) as string
    result = ""
    normalized = value.Replace(Chr(13), "")
    for each line in normalized.Tokenize(Chr(10))
        if line.Trim() <> "" then result = line.Trim()
    end for
    return result
end function

function TorrentMetadataLine(value as string) as string
    normalized = value.Replace(Chr(13), "")
    lines = normalized.Tokenize(Chr(10))
    if lines.Count() < 2 then return ""

    tokens = lines[1].Tokenize(" ")
    if tokens.Count() < 5 then return lines[1]

    result = "Seeds " + tokens[1] + " | " + tokens[3] + " " + tokens[4]
    if tokens.Count() > 6 then result = result + " | " + tokens[6]
    return result
end function

function PadNumber(value as integer) as string
    if value < 10 then return "0" + value.ToStr()
    return value.ToStr()
end function

function DetectStreamFormat(url as string) as string
    cleanUrl = LCase(url)
    queryIndex = Instr(1, cleanUrl, "?")
    if queryIndex > 0 then cleanUrl = Left(cleanUrl, queryIndex - 1)
    if Right(cleanUrl, 5) = ".m3u8" then return "hls"
    if Right(cleanUrl, 4) = ".mpd" then return "dash"
    if Right(cleanUrl, 4) = ".mkv" then return "mkv"
    if Right(cleanUrl, 4) = ".mp4" or Right(cleanUrl, 4) = ".m4v" then return "mp4"
    return ""
end function

function EncodeUrlComponent(value as string) as string
    result = ""
    for index = 1 to Len(value)
        character = Mid(value, index, 1)
        code = Asc(character)
        isAlphaNumeric = (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122)
        if isAlphaNumeric or character = "-" or character = "_" or character = "." or character = "~"
            result = result + character
        else
            result = result + "%" + ByteToHex(code)
        end if
    end for
    return result
end function

function ByteToHex(value as integer) as string
    digits = "0123456789ABCDEF"
    high = Int(value / 16)
    low = value mod 16
    return Mid(digits, high + 1, 1) + Mid(digits, low + 1, 1)
end function

sub ConfirmExitApp()
    if m.exitAppDialog <> invalid then return
    dialog = CreateObject("roSGNode", "Dialog")
    dialog.title = TrText("dialog.exitApp.title")
    dialog.message = TrText("dialog.exitApp.message")
    dialog.buttons = [TrText("dialog.exitApp.exit"), TrText("dialog.exitApp.stay")]
    dialog.ObserveField("buttonSelected", "onExitAppDialogButton")
    m.exitAppDialog = dialog
    m.top.dialog = dialog
end sub

sub onExitAppDialogButton(event as object)
    buttonIndex = event.GetData()
    m.exitAppDialog.close = true
    m.exitAppDialog = invalid
    if buttonIndex = 0
        m.top.exitApp = true
    else
        m.catalogList.SetFocus(true)
    end if
end sub

sub onVideoDurationChanged(event as object)
    duration = event.GetData()
    if duration <> invalid and duration > 0
        m.lastVideoDuration = duration
    end if
end sub

sub onVideoPositionChanged(event as object)
    position = event.GetData()
    if position <> invalid and position > 0
        m.lastVideoPosition = position
    end if
    if m.lastProgressSaveTime = invalid then m.lastProgressSaveTime = 0
    if Abs(position - m.lastProgressSaveTime) >= 30
        m.lastProgressSaveTime = position
        dur = 0
        if m.video.duration <> invalid and m.video.duration > 0
            dur = m.video.duration
        else if m.lastVideoDuration <> invalid
            dur = m.lastVideoDuration
        end if
        SavePlaybackProgress(Int(position), Int(dur), false)
    end if
end sub

sub SavePlaybackProgress(positionSec as integer, durationSec as integer, isFinished as boolean)
    if not m.authStore.isSignedIn() then return
    if m.playbackContentId = "" then return

    seriesOrMovieId = m.playbackContentId
    if m.playbackContentType = "series"
        parts = m.playbackContentId.Split(":")
        seriesOrMovieId = parts[0]
    end if

    libraryItem = invalid
    if m.libraryStore.hasById(seriesOrMovieId)
        libraryItem = m.libraryStore.getById(seriesOrMovieId)
    else if m.selectedItem <> invalid
        libraryItem = m.libraryStore.buildLibraryChange(m.selectedItem, false)
        libraryItem.temp = true
    end if

    if libraryItem = invalid then return

    if not libraryItem.DoesExist("state") or libraryItem.state = invalid
        libraryItem.state = {
            lastWatched: invalid
            timeWatched: 0
            timeOffset: 0
            overallTimeWatched: 0
            timesWatched: 0
            flaggedWatched: 0
            duration: 0
            video_id: invalid
            watched: invalid
            noNotif: false
        }
    end if
    state = libraryItem.state

    now = CreateObject("roDateTime").ToISOString()
    positionMs = positionSec * 1000
    durationMs = durationSec * 1000

    state.lastWatched = now
    state.video_id = m.playbackContentId
    state.duration = durationMs

    completed = isFinished
    if not completed and durationSec > 0
        if positionSec > 0.9 * durationSec
            completed = true
        end if
    end if

    if completed
        state.timeOffset = 0
        if m.playbackContentType = "movie"
            state.watched = m.playbackContentId
            state.timesWatched = state.timesWatched + 1
        else if m.playbackContentType = "series"
            episodeIndex = -1
            for i = 0 to m.episodes.Count() - 1
                if m.episodes[i].id = m.playbackContentId
                    episodeIndex = i
                    exit for
                end if
            end for

            if episodeIndex >= 0
                watchedIndices = []
                lastSeason = 0
                lastEpisode = 0
                
                episode = m.episodes[episodeIndex]
                if episode.DoesExist("season") then lastSeason = episode.season
                if episode.DoesExist("episode") then lastEpisode = episode.episode
                if lastEpisode = 0 and episode.DoesExist("number") then lastEpisode = episode.number

                if state.DoesExist("watched") and state.watched <> invalid and state.watched <> ""
                    info = DecodeWatchedBitfield(state.watched)
                    if info <> invalid and info.watchedIndices <> invalid
                        watchedIndices = info.watchedIndices
                    end if
                end if

                found = false
                for each idx in watchedIndices
                    if idx = episodeIndex
                        found = true
                        exit for
                    end if
                end for
                if not found
                    watchedIndices.Push(episodeIndex)
                end if

                state.watched = EncodeWatchedBitfield(seriesOrMovieId, lastSeason, lastEpisode, m.episodes.Count(), watchedIndices)
            end if
        end if
    else
        state.timeOffset = positionMs
    end if

    libraryItem._mtime = now
    m.libraryStore.upsertById(seriesOrMovieId, libraryItem)

    req = m.libraryStore.buildProgressPut(m.authStore.getAuthKey(), seriesOrMovieId, libraryItem)
    StartPostRequest(req.url, req.id, req.body)
end sub

function CreateBitReader(bytes as object) as object
    return {
        bytes: bytes
        byteIdx: 0
        bitIdx: 0
        ReadBit: function() as integer
            if m.byteIdx >= m.bytes.Count() then return 0
            bit = Int(m.bytes[m.byteIdx] / (2 ^ m.bitIdx)) mod 2
            m.bitIdx = m.bitIdx + 1
            if m.bitIdx = 8
                m.bitIdx = 0
                m.byteIdx = m.byteIdx + 1
            end if
            return bit
        end function
        ReadBits: function(n as integer) as integer
            val = 0
            for i = 0 to n - 1
                val = val + m.ReadBit() * (2 ^ i)
            end for
            return val
        end function
    }
end function

function BuildHuffmanTable(lengths as object) as object
    maxLen = 0
    for each l in lengths
        if l > maxLen then maxLen = l
    end for

    blCount = []
    for i = 0 to maxLen
        blCount.Push(0)
    end for
    for each l in lengths
        if l > 0 then blCount[l] = blCount[l] + 1
    end for

    code = 0
    nextCode = []
    for i = 0 to maxLen
        nextCode.Push(0)
    end for
    for bits = 1 to maxLen
        code = (code + blCount[bits - 1]) * 2
        nextCode[bits] = code
    end for

    table = {}
    for symbol = 0 to lengths.Count() - 1
        l = lengths[symbol]
        if l > 0
            c = nextCode[l]
            nextCode[l] = nextCode[l] + 1
            table[l.ToStr() + "-" + c.ToStr()] = symbol
        end if
    end for
    return { table: table, maxLen: maxLen }
end function

function DecodeSymbol(reader as object, huff as object) as integer
    code = 0
    for len = 1 to huff.maxLen
        bit = reader.ReadBit()
        code = (code * 2) + bit
        key = len.ToStr() + "-" + code.ToStr()
        if huff.table.DoesExist(key)
            return huff.table[key]
        end if
    end for
    return -1
end function

function GetLength(reader as object, code as integer) as integer
    if code < 257 or code > 285 then return 0
    if code <= 264 then return code - 254
    if code = 285 then return 258

    extraBits = Int((code - 261) / 4)
    base = 0
    if extraBits = 1
        base = 11 + (code - 265) * 2
    else if extraBits = 2
        base = 19 + (code - 269) * 4
    else if extraBits = 3
        base = 35 + (code - 273) * 8
    else if extraBits = 4
        base = 67 + (code - 277) * 16
    else if extraBits = 5
        base = 131 + (code - 281) * 32
    end if

    return base + reader.ReadBits(extraBits)
end function

function GetDistance(reader as object, code as integer) as integer
    if code < 0 or code > 29 then return 0
    if code <= 3 then return code + 1

    extraBits = Int(code / 2) - 1
    base = 0
    if extraBits = 1
        base = 5 + (code - 4) * 2
    else if extraBits = 2
        base = 9 + (code - 6) * 4
    else if extraBits = 3
        base = 17 + (code - 8) * 8
    else if extraBits = 4
        base = 33 + (code - 10) * 16
    else if extraBits = 5
        base = 65 + (code - 12) * 32
    else if extraBits = 6
        base = 129 + (code - 14) * 64
    else if extraBits = 7
        base = 257 + (code - 16) * 128
    else if extraBits = 8
        base = 513 + (code - 18) * 256
    else if extraBits = 9
        base = 1025 + (code - 20) * 512
    else if extraBits = 10
        base = 2049 + (code - 22) * 1024
    else if extraBits = 11
        base = 4097 + (code - 24) * 2048
    else if extraBits = 12
        base = 8193 + (code - 26) * 4096
    else if extraBits = 13
        base = 16385 + (code - 28) * 8192
    end if

    return base + reader.ReadBits(extraBits)
end function

function InflateDeflate(bytes as object) as object
    reader = CreateBitReader(bytes)
    out = CreateObject("roByteArray")

    bfinal = 0
    while bfinal = 0
        bfinal = reader.ReadBit()
        btype = reader.ReadBits(2)

        if btype = 0
            reader.bitIdx = 0
            if reader.byteIdx + 4 <= reader.bytes.Count()
                len = reader.bytes[reader.byteIdx] + reader.bytes[reader.byteIdx + 1] * 256
                reader.byteIdx = reader.byteIdx + 4
                for i = 0 to len - 1
                    if reader.byteIdx < reader.bytes.Count()
                        out.Push(reader.bytes[reader.byteIdx])
                        reader.byteIdx = reader.byteIdx + 1
                    end if
                end for
            else
                bfinal = 1
            end if
        else if btype = 1 or btype = 2
            litHuff = invalid
            distHuff = invalid

            if btype = 1
                lengths = []
                for i = 0 to 143: lengths.Push(8): end for
                for i = 144 to 255: lengths.Push(9): end for
                for i = 256 to 279: lengths.Push(7): end for
                for i = 280 to 287: lengths.Push(8): end for
                litHuff = BuildHuffmanTable(lengths)

                distLengths = []
                for i = 0 to 31: distLengths.Push(5): end for
                distHuff = BuildHuffmanTable(distLengths)
            else
                numLit = reader.ReadBits(5) + 257
                numDist = reader.ReadBits(5) + 1
                numLen = reader.ReadBits(4) + 4

                codeLenOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
                codeLenLengths = []
                for i = 0 to 18: codeLenLengths.Push(0): end for
                for i = 0 to numLen - 1
                    codeLenLengths[codeLenOrder[i]] = reader.ReadBits(3)
                end for

                codeLenHuff = BuildHuffmanTable(codeLenLengths)

                lengths = []
                while lengths.Count() < numLit + numDist
                    sym = DecodeSymbol(reader, codeLenHuff)
                    if sym < 0
                        exit while
                    else if sym <= 15
                        lengths.Push(sym)
                    else if sym = 16
                        prev = 0
                        if lengths.Count() > 0 then prev = lengths[lengths.Count() - 1]
                        rep = reader.ReadBits(2) + 3
                        for j = 0 to rep - 1: lengths.Push(prev): end for
                    else if sym = 17
                        rep = reader.ReadBits(3) + 3
                        for j = 0 to rep - 1: lengths.Push(0): end for
                    else if sym = 18
                        rep = reader.ReadBits(7) + 11
                        for j = 0 to rep - 1: lengths.Push(0): end for
                    end if
                end while

                litLengths = []
                for i = 0 to numLit - 1: litLengths.Push(lengths[i]): end for
                litHuff = BuildHuffmanTable(litLengths)

                distLengths = []
                for i = 0 to numDist - 1: distLengths.Push(lengths[numLit + i]): end for
                distHuff = BuildHuffmanTable(distLengths)
            end if

            while true
                sym = DecodeSymbol(reader, litHuff)
                if sym < 0 or sym = 256
                    exit while
                else if sym < 256
                    out.Push(sym)
                else
                    len = GetLength(reader, sym)
                    distSym = DecodeSymbol(reader, distHuff)
                    dist = GetDistance(reader, distSym)
                    startIdx = out.Count() - dist
                    for j = 0 to len - 1
                        out.Push(out[startIdx + j])
                    end for
                end if
            end while
        else
            bfinal = 1
        end if
    end while

    return out
end function

function ZlibInflate(bytes as object) as object
    if bytes.Count() < 6 then return CreateObject("roByteArray")
    deflateBytes = CreateObject("roByteArray")
    for i = 2 to bytes.Count() - 5
        deflateBytes.Push(bytes[i])
    end for
    return InflateDeflate(deflateBytes)
end function

function ZlibDeflateNoCompression(bytes as object) as object
    out = CreateObject("roByteArray")
    out.Push(120)
    out.Push(1)
    out.Push(1)

    L = bytes.Count()
    out.Push(L mod 256)
    out.Push(Int(L / 256) mod 256)

    NL = 65535 - L
    out.Push(NL mod 256)
    out.Push(Int(NL / 256) mod 256)

    for i = 0 to L - 1
        out.Push(bytes[i])
    end for

    adlerA = 1
    adlerB = 0
    for i = 0 to L - 1
        adlerA = (adlerA + bytes[i]) mod 65521
        adlerB = (adlerB + adlerA) mod 65521
    end for

    out.Push(Int(adlerB / 256) mod 256)
    out.Push(adlerB mod 256)
    out.Push(Int(adlerA / 256) mod 256)
    out.Push(adlerA mod 256)

    return out
end function

function DecodeWatchedBitfield(watchedStr as string) as object
    parts = watchedStr.Split(":")
    if parts.Count() < 5 then return invalid

    sid = parts[0]
    lastSeason = Val(parts[1])
    lastEpisode = Val(parts[2])
    N = Val(parts[3])
    b64 = parts[4]

    ba = CreateObject("roByteArray")
    ba.FromBase64String(b64)
    decompressed = ZlibInflate(ba)

    watchedIndices = []
    powersOfTwo = [1, 2, 4, 8, 16, 32, 64, 128]
    for i = 0 to N - 1
        byteIdx = Int(i / 8)
        bitIdx = i mod 8
        isWatched = false
        if byteIdx < decompressed.Count()
            isWatched = (decompressed[byteIdx] And powersOfTwo[bitIdx]) <> 0
        end if
        if isWatched
            watchedIndices.Push(i)
        end if
    end for

    return {
        sid: sid
        lastSeason: lastSeason
        lastEpisode: lastEpisode
        N: N
        watchedIndices: watchedIndices
    }
end function

function EncodeWatchedBitfield(sid as string, lastSeason as integer, lastEpisode as integer, N as integer, watchedIndices as object) as string
    numBytes = Int((N + 7) / 8)
    ba = CreateObject("roByteArray")
    for j = 0 to numBytes - 1
        ba.Push(0)
    end for

    powersOfTwo = [1, 2, 4, 8, 16, 32, 64, 128]
    for each i in watchedIndices
        if i >= 0 and i < N
            byteIdx = Int(i / 8)
            bitIdx = i mod 8
            ba[byteIdx] = ba[byteIdx] Or powersOfTwo[bitIdx]
        end if
    end for

    compressed = ZlibDeflateNoCompression(ba)
    b64 = compressed.ToBase64String()

    return sid + ":" + lastSeason.ToStr() + ":" + lastEpisode.ToStr() + ":" + N.ToStr() + ":" + b64
end function

function FormatPlaybackTime(seconds as dynamic) as string
    total = Int(seconds)
    if total < 0 then total = 0
    hours = Int(total / 3600)
    minutes = Int((total mod 3600) / 60)
    remainingSeconds = total mod 60

    minuteText = minutes.ToStr()
    secondText = remainingSeconds.ToStr()
    if Len(secondText) = 1 then secondText = "0" + secondText
    if hours > 0
        if Len(minuteText) = 1 then minuteText = "0" + minuteText
        return hours.ToStr() + ":" + minuteText + ":" + secondText
    end if
    return minuteText + ":" + secondText
end function
