sub init()
    m.catalogList = m.top.FindNode("catalogList")
    m.primaryInfoList = m.top.FindNode("primaryInfoList")
    m.primaryInfoGroup = m.top.FindNode("primaryInfoGroup")
    m.discoverFilterGroup = m.top.FindNode("discoverFilterGroup")
    m.discoverGrid = m.top.FindNode("discoverGrid")
    m.discoverTypeLabel = m.top.FindNode("discoverTypeLabel")
    m.discoverCatalogLabel = m.top.FindNode("discoverCatalogLabel")
    m.discoverGenreLabel = m.top.FindNode("discoverGenreLabel")
    m.discoverTypeFocus = m.top.FindNode("discoverTypeFocus")
    m.discoverCatalogFocus = m.top.FindNode("discoverCatalogFocus")
    m.discoverGenreFocus = m.top.FindNode("discoverGenreFocus")

    m.catalogList.ObserveField("rowItemFocused", "onCatalogFocused")
    m.catalogList.ObserveField("rowItemSelected", "onCatalogSelected")
    m.primaryInfoList.ObserveField("itemSelected", "onPrimaryInfoSelected")
    m.discoverGrid.ObserveField("itemFocused", "onDiscoverGridFocused")
    m.discoverGrid.ObserveField("itemSelected", "onDiscoverGridSelected")

    m.catalogRows = []
    m.primaryActions = []
    m.stores = invalid
    m.lastCatalogPosition = invalid
    m.lastInfoIndex = 0
    m.lastChromeSignature = ""
    m.discoverFilterFocus = -1

    m.catalogList.visible = false
    m.primaryInfoGroup.visible = false
    m.discoverFilterGroup.visible = false
    m.discoverGrid.visible = false
end sub

' The stores are plain BrightScript objects with function members; Roku's field
' marshaller strips those out of an assocarray, so MainScene hands them over
' through a same-thread CallFunc, which passes objects by reference.
sub SetStores(stores as object)
    m.stores = stores
end sub

sub onModeChanged()
    BlurFocus()
    RenderCurrent(true)
end sub

sub onRevisionChanged()
    RenderCurrent(false)
end sub

sub onFocusRequest()
    if m.top.mode = "discover"
        m.catalogList.SetFocus(false)
        m.primaryInfoList.SetFocus(false)
        BlurDiscoverFilters()
        m.discoverGrid.SetFocus(true)
    else if m.top.mode = "library" and not m.stores.auth.isSignedIn()
        m.catalogList.SetFocus(false)
        m.primaryInfoList.SetFocus(true)
    else if m.top.mode = "board" or m.top.mode = "library"
        m.primaryInfoList.SetFocus(false)
        m.catalogList.SetFocus(true)
    else
        m.catalogList.SetFocus(false)
        m.primaryInfoList.SetFocus(false)
        m.discoverGrid.SetFocus(false)
    end if
end sub

sub BlurFocus()
    m.catalogList.SetFocus(false)
    m.primaryInfoList.SetFocus(false)
    m.discoverGrid.SetFocus(false)
    BlurDiscoverFilters()
end sub

sub RenderCurrent(needChrome as boolean)
    if m.stores = invalid then return

    m.catalogList.visible = false
    m.primaryInfoGroup.visible = false
    m.discoverFilterGroup.visible = false
    m.discoverGrid.visible = false

    if m.top.mode = "board"
        RenderBoardContent()
    else if m.top.mode = "library"
        RenderLibraryContent()
    else if m.top.mode = "discover"
        RenderDiscoverContent()
    else
        BlurFocus()
    end if

    if m.top.mode = "board" or m.top.mode = "library" or m.top.mode = "discover"
        if needChrome or ChromeSignature() <> m.lastChromeSignature
            EmitChrome()
            m.lastChromeSignature = ChromeSignature()
        end if
    end if
end sub

sub RenderBoardContent()
    m.primaryInfoGroup.visible = false
    m.catalogList.visible = true
    UpdateCatalogContent(m.stores.catalog.getBoardRows(), m.stores.catalog.getBoardNames())
end sub

sub RenderLibraryContent()
    if not m.stores.auth.isSignedIn()
        RenderInfoList([
            InfoAction(TrText("library.signedOut.title"), "none", invalid)
            InfoAction(TrText("library.signedOut.benefit1"), "none", invalid)
            InfoAction(TrText("library.signedOut.benefit2"), "none", invalid)
            InfoAction(TrText("library.signedOut.login"), "login", invalid)
        ])
        return
    end if

    libraryItems = m.stores.library.getLibraryItems()
    watchedItems = m.stores.library.getWatchedItems()
    rows = []
    names = []
    if libraryItems.Count() > 0
        rows.Push(libraryItems)
        names.Push(TrText("library.catalog.lastWatched"))
    end if
    if watchedItems.Count() > 0
        rows.Push(watchedItems)
        names.Push(TrText("library.catalog.previouslyWatched"))
    end if

    m.primaryInfoGroup.visible = false
    m.catalogList.visible = true
    UpdateCatalogContent(rows, names)
end sub

sub RenderInfoList(actions as object)
    content = CreateObject("roSGNode", "ContentNode")
    m.primaryActions = actions
    for each action in actions
        child = content.CreateChild("ContentNode")
        child.title = action.title
    end for
    targetIndex = m.lastInfoIndex
    if targetIndex < 0 then targetIndex = 0
    if actions.Count() > 0 and targetIndex >= actions.Count() then targetIndex = actions.Count() - 1

    m.catalogList.visible = false
    m.primaryInfoGroup.visible = true
    m.primaryInfoList.content = content
    m.primaryInfoList.JumpToItem = targetIndex
end sub

sub UpdateCatalogContent(rows as object, names as object)
    root = CreateObject("roSGNode", "ContentNode")

    for rowIndex = 0 to rows.Count() - 1
        rowNode = root.CreateChild("ContentNode")
        rowNode.title = names[rowIndex]

        for each item in rows[rowIndex]
            itemNode = rowNode.CreateChild("ContentNode")
            itemNode.title = SafeString(item, "name")
            itemNode.HDPosterUrl = SafeString(item, "poster")
            itemNode.SDPosterUrl = SafeString(item, "poster")

            progress = m.stores.library.progressFor(SafeString(item, "id"))
            if progress > 0.0
                itemNode.AddFields({ progress: progress })
            end if
        end for
    end for

    m.catalogRows = rows
    m.catalogList.content = root

    position = m.lastCatalogPosition
    if position <> invalid and position.Count() >= 2
        row = position[0]
        col = position[1]
        if row >= 0 and row < rows.Count()
            if col >= 0 and col < rows[row].Count()
                m.catalogList.jumpToRowItem = position
            else if rows[row].Count() > 0
                m.catalogList.jumpToRowItem = [row, 0]
            end if
        end if
    end if
end sub

sub onCatalogFocused(event as object)
    item = GetCatalogItem(event.GetData())
    if item = invalid then return
    m.top.screenInfo = {
        heroTitle: SafeString(item, "name")
        heroDescription: HomeHeroDescription(item)
    }
end sub

sub onCatalogSelected(event as object)
    item = GetCatalogItem(event.GetData())
    if item = invalid then return

    if SafeString(item, "type") = "action"
        m.top.action = { type: "boardSeeAll", item: item }
        return
    end if

    if SafeString(item, "type") = "series"
        m.top.action = { type: "openSeriesEpisodes", item: item }
    else
        m.top.action = { type: "openMovieStreams", item: item }
    end if
end sub

sub onPrimaryInfoSelected(event as object)
    index = event.GetData()
    if index < 0 or index >= m.primaryActions.Count() then return

    action = m.primaryActions[index]
    m.top.action = { type: "infoAction", actionType: action.actionType, payload: action.payload }
end sub

function GetCatalogItem(position as object) as dynamic
    if position = invalid or position.Count() < 2 then return invalid
    rowIndex = position[0]
    itemIndex = position[1]
    if rowIndex < 0 or rowIndex >= m.catalogRows.Count() then return invalid
    if itemIndex < 0 or itemIndex >= m.catalogRows[rowIndex].Count() then return invalid
    return m.catalogRows[rowIndex][itemIndex]
end function

function InfoAction(title as string, actionType as string, payload as dynamic) as object
    return {
        title: title
        actionType: actionType
        payload: payload
    }
end function

sub EmitChrome()
    if m.top.mode = "board"
        m.top.screenInfo = {
            title: TrText("nav.board")
            subtitle: TrText("board.subtitle")
            heroTitle: TrText("nav.board")
            heroDescription: TrText("board.hero")
        }
    else if m.top.mode = "library"
        if not m.stores.auth.isSignedIn()
            m.top.screenInfo = {
                title: TrText("nav.library")
                subtitle: TrText("library.subtitle")
                heroTitle: TrText("nav.library")
                heroDescription: TrText("library.hero.signedOut")
            }
        else
            libraryItems = m.stores.library.getLibraryItems()
            watchedItems = m.stores.library.getWatchedItems()
            hero = TrText("library.hero.empty")
            if libraryItems.Count() > 0 or watchedItems.Count() > 0
                hero = TrText("library.hero.counts")
                hero = LocaleReplace(hero, "{saved}", libraryItems.Count().ToStr())
                hero = LocaleReplace(hero, "{watched}", watchedItems.Count().ToStr())
            end if
            m.top.screenInfo = {
                title: TrText("nav.library")
                subtitle: TrText("library.subtitle")
                heroTitle: TrText("nav.library")
                heroDescription: hero
            }
        end if
    else if m.top.mode = "discover"
        m.top.screenInfo = {
            title: TrText("nav.discover")
            subtitle: TrText("discover.subtitle")
            heroTitle: TrText("nav.discover")
            heroDescription: TrText("discover.hero")
        }
    end if
end sub

function ChromeSignature() as string
    if m.top.mode = "board" then return "board"
    if m.top.mode = "library"
        if not m.stores.auth.isSignedIn() then return "library:signedOut"
        return "library:signedIn:" + m.stores.library.getLibraryItems().Count().ToStr() + ":" + m.stores.library.getWatchedItems().Count().ToStr()
    end if
    if m.top.mode = "discover" then return "discover"
    return ""
end function

' --- discover ----------------------------------------------------------------

sub RenderDiscoverContent()
    m.catalogList.visible = false
    m.primaryInfoGroup.visible = false
    m.discoverFilterGroup.visible = true
    m.discoverGrid.visible = true
    UpdateDiscoverFilterLabels()
    RebuildDiscoverGrid()
end sub

sub UpdateDiscoverFilterLabels()
    m.discoverTypeLabel.text = DiscoverTypeLabel(m.stores.catalog.getDiscoverType())
    m.discoverCatalogLabel.text = m.stores.catalog.getDiscoverCatalog()
    m.discoverGenreLabel.text = m.stores.catalog.getDiscoverGenre()
    UpdateDiscoverFilterFocus()
end sub

sub UpdateDiscoverFilterFocus()
    m.discoverTypeFocus.visible = m.discoverFilterFocus = 0
    m.discoverCatalogFocus.visible = m.discoverFilterFocus = 1
    m.discoverGenreFocus.visible = m.discoverFilterFocus = 2
end sub

sub FocusFilters()
    if m.top.mode <> "discover" then return
    if m.discoverFilterFocus < 0 then m.discoverFilterFocus = 0
    UpdateDiscoverFilterFocus()
    m.discoverGrid.SetFocus(false)
    m.top.SetFocus(true)
end sub

sub BlurDiscoverFilters()
    m.discoverFilterFocus = -1
    UpdateDiscoverFilterFocus()
end sub

sub RebuildDiscoverGrid()
    content = CreateObject("roSGNode", "ContentNode")
    discoverRows = m.stores.catalog.getDiscoverRows()
    if discoverRows <> invalid and discoverRows.Count() > 0
        for each row in discoverRows
            if row = invalid then continue for
            for each item in row
                if item <> invalid and SafeString(item, "type") <> "action"
                    itemNode = content.CreateChild("ContentNode")
                    itemNode.title = SafeString(item, "name")
                    itemNode.HDPosterUrl = SafeString(item, "poster")
                    itemNode.SDPosterUrl = SafeString(item, "poster")
                    progress = m.stores.library.progressFor(SafeString(item, "id"))
                    if progress > 0.0
                        itemNode.AddFields({ progress: progress })
                    end if
                end if
            end for
        end for
    end if
    m.discoverGrid.content = content
end sub

function GetDiscoverGridItem(index as integer) as dynamic
    discoverRows = m.stores.catalog.getDiscoverRows()
    if index < 0 or discoverRows = invalid or discoverRows.Count() = 0 then return invalid
    visibleIndex = -1
    for each row in discoverRows
        if row = invalid then continue for
        for each item in row
            if item <> invalid and SafeString(item, "type") <> "action"
                visibleIndex = visibleIndex + 1
                if visibleIndex = index then return item
            end if
        end for
    end for
    return invalid
end function

sub onDiscoverGridFocused(event as object)
    item = GetDiscoverGridItem(event.GetData())
    if item = invalid then return
    info = {
        heroTitle: SafeString(item, "name")
        heroDescription: HomeHeroDescription(item)
    }
    meta = SafeString(item, "type")
    year = SafeString(item, "releaseInfo")
    if year = "" then year = SafeString(item, "year")
    if year <> "" then meta = meta + "  " + year
    if meta <> "" then info.subtitle = meta
    m.top.screenInfo = info
end sub

sub onDiscoverGridSelected(event as object)
    item = GetDiscoverGridItem(event.GetData())
    if item = invalid then return
    if SafeString(item, "type") = "series"
        m.top.action = { type: "openSeriesEpisodes", item: item }
    else
        m.top.action = { type: "openMovieStreams", item: item }
    end if
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if m.top.mode <> "discover" then return false

    if m.discoverFilterFocus >= 0
        if key = "left"
            if m.discoverFilterFocus > 0
                m.discoverFilterFocus = m.discoverFilterFocus - 1
                UpdateDiscoverFilterFocus()
            else
                BlurDiscoverFilters()
                m.top.action = { type: "focusNavRail" }
            end if
            return true
        else if key = "right"
            if m.discoverFilterFocus < 2
                m.discoverFilterFocus = m.discoverFilterFocus + 1
                UpdateDiscoverFilterFocus()
            end if
            return true
        else if key = "OK"
            m.top.action = { type: "cycleDiscoverFilter", filterIndex: m.discoverFilterFocus }
            return true
        else if key = "down" or key = "back"
            BlurDiscoverFilters()
            m.discoverGrid.SetFocus(true)
            return true
        else if key = "up"
            BlurDiscoverFilters()
            m.top.action = { type: "focusTopBar" }
            return true
        end if
    end if

    return false
end function
