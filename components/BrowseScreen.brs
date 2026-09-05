sub init()
    m.catalogList = m.top.FindNode("catalogList")
    m.primaryInfoList = m.top.FindNode("primaryInfoList")
    m.primaryInfoGroup = m.top.FindNode("primaryInfoGroup")

    m.catalogList.ObserveField("rowItemFocused", "onCatalogFocused")
    m.catalogList.ObserveField("rowItemSelected", "onCatalogSelected")
    m.primaryInfoList.ObserveField("itemSelected", "onPrimaryInfoSelected")

    m.catalogRows = []
    m.primaryActions = []
    m.stores = invalid
    m.lastCatalogPosition = invalid
    m.lastInfoIndex = 0
    m.lastChromeSignature = ""

    m.catalogList.visible = false
    m.primaryInfoGroup.visible = false
end sub

' The stores are plain BrightScript objects with function members; Roku's field
' marshaller strips those out of an assocarray, so MainScene hands them over
' through a same-thread CallFunc, which passes objects by reference.
sub SetStores(stores as object)
    m.stores = stores
end sub

sub onModeChanged()
    RenderCurrent(true)
end sub

sub onRevisionChanged()
    RenderCurrent(false)
end sub

sub onFocusRequest()
    if m.top.mode = "library" and not m.stores.auth.isSignedIn()
        m.catalogList.SetFocus(false)
        m.primaryInfoList.SetFocus(true)
    else if m.top.mode = "board" or m.top.mode = "library"
        m.primaryInfoList.SetFocus(false)
        m.catalogList.SetFocus(true)
    else
        m.catalogList.SetFocus(false)
        m.primaryInfoList.SetFocus(false)
    end if
end sub

sub BlurFocus()
    m.catalogList.SetFocus(false)
    m.primaryInfoList.SetFocus(false)
end sub

sub RenderCurrent(needChrome as boolean)
    if m.stores = invalid then return

    if m.top.mode = "board"
        RenderBoardContent()
    else if m.top.mode = "library"
        RenderLibraryContent()
    else
        m.catalogList.visible = false
        m.primaryInfoGroup.visible = false
        m.catalogList.SetFocus(false)
        m.primaryInfoList.SetFocus(false)
    end if

    if m.top.mode = "board" or m.top.mode = "library"
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
    end if
end sub

function ChromeSignature() as string
    if m.top.mode = "board" then return "board"
    if m.top.mode = "library"
        if not m.stores.auth.isSignedIn() then return "library:signedOut"
        return "library:signedIn:" + m.stores.library.getLibraryItems().Count().ToStr() + ":" + m.stores.library.getWatchedItems().Count().ToStr()
    end if
    return ""
end function