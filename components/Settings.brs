' The Settings screen, owning its whole visible region: the tab chips, the row
' list, and the detail panel. It keeps its own focus and handles its own keys,
' so none of its internals route through MainScene's flat onKeyEvent.
'
' Division of labour:
'   - up / down   the MarkupList moves focus natively. This reads itemFocused to
'                 skip section-header rows and refresh the detail panel.
'   - OK          the MarkupList fires itemSelected natively. This maps the row
'                 to { type, payload } and publishes it as the action field.
'   - left/right  re-render the active tab (moving focus reset to the top).
'   - back        returned false so MainScene owns leaving the screen.
'
' The current values the rows render from are pushed in by MainScene as the
' state field (MainScene is the source of truth and does persistence); this
' component never mutates app state itself, only reports actions.

sub init()
    m.list = m.top.FindNode("settingsList")

    m.tabBackgrounds = []
    m.tabLabels = []
    for index = 0 to 2
        m.tabBackgrounds.Push(m.top.FindNode("settingsTab" + index.ToStr() + "Bg"))
        m.tabLabels.Push(m.top.FindNode("settingsTab" + index.ToStr() + "Label"))
    end for
    m.tabIndicator = m.top.FindNode("settingsTabIndicator")
    m.detailEyebrow = m.top.FindNode("settingsDetailEyebrow")
    m.detailTitle = m.top.FindNode("settingsDetailTitle")
    m.detailValue = m.top.FindNode("settingsDetailValue")
    m.detailHint = m.top.FindNode("settingsDetailHint")

    m.list.ObserveField("itemFocused", "onItemFocused")
    m.list.ObserveField("itemSelected", "onItemSelected")

    m.suppressIndex = -1
    m.lastFocusIndex = -1
    m.settingsTabIndex = 0
    m.settingsRenderedTab = -1
    m.settingsFocusIndex = 0
    m.rows = []
    m.state = {}

    m.top.visible = false
end sub

' MainScene pushed a fresh set of current values: store them and re-render. The
' re-render keeps the active tab and the focused row, so a value change (after a
' toggle or a language cycle, say) updates the rows without jumping the cursor.
sub onStateChanged()
    m.state = m.top.state
    RenderSettings()
end sub

' MainScene asked the screen to take focus (having already made it visible and
' pushed state). Hand focus to the inner list so up/down and OK work.
sub onFocusRequest()
    m.list.SetFocus(true)
end sub

sub RenderSettings()
    rows = BuildSettingsRows()
    m.rows = rows

    content = CreateObject("roSGNode", "ContentNode")
    for each row in rows
        child = content.CreateChild("SettingsRowContent")
        child.title = row.title
        child.value = row.value
        child.rowKind = row.kind
        child.hint = row.hint
        child.selectable = SettingsRowSelectable(row)
        child.toggleOn = row.DoesExist("toggleOn") and row.toggleOn
    end for

    ' Switching sections starts at the top; re-rendering the section the user is
    ' already on (after a toggle, say) keeps them where they were.
    targetIndex = FocusTargetIndex(rows)

    m.list.content = content
    if m.list.itemFocused <> targetIndex
        m.suppressIndex = targetIndex
        m.list.JumpToItem = targetIndex
    end if
    m.settingsFocusIndex = targetIndex
    m.settingsRenderedTab = m.settingsTabIndex

    UpdateSettingsTabs()
    UpdateSettingsDetail(targetIndex)
    EmitScreenInfo()
end sub

' The row to land on after a render: the top of a freshly switched-to section,
' or the last focused row when re-rendering the section already on screen.
function FocusTargetIndex(rows as object) as integer
    if rows.Count() = 0 then return 0
    if m.settingsRenderedTab = m.settingsTabIndex
        targetIndex = m.settingsFocusIndex
        if targetIndex >= rows.Count() then targetIndex = rows.Count() - 1
        if targetIndex < 0 then targetIndex = 0
        if not SettingsRowSelectable(rows[targetIndex])
            targetIndex = NextSelectableSettingsIndex(rows, targetIndex, 1)
        end if
    else
        targetIndex = NextSelectableSettingsIndex(rows, -1, 1)
    end if
    if targetIndex < 0 then targetIndex = 0
    return targetIndex
end function

sub onItemFocused(event as object)
    index = event.GetData()
    count = m.list.content.getChildCount()
    if index < 0 or index >= count
        m.settingsFocusIndex = -1
        return
    end if

    ' Echo from assigning content + jump after a render: ignore everything while
    ' armed and let the matching echo disarm it.
    if m.suppressIndex >= 0
        if index = m.suppressIndex
            m.suppressIndex = -1
            m.lastFocusIndex = index
            m.settingsFocusIndex = index
            UpdateSettingsDetail(index)
        end if
        return
    end if

    direction = 1
    if m.lastFocusIndex >= 0 and index < m.lastFocusIndex then direction = -1

    ' Section headers share the list; keep pushing focus past them in the
    ' direction the user was already heading.
    if RowIsHeader(index)
        target = NextSelectableIndex(index, direction)
        if target >= 0
            m.list.animateToItem = target
            m.lastFocusIndex = target
            m.settingsFocusIndex = target
            UpdateSettingsDetail(target)
        end if
        return
    end if

    m.lastFocusIndex = index
    m.settingsFocusIndex = index
    UpdateSettingsDetail(index)
end sub

sub onItemSelected(event as object)
    index = event.GetData()
    count = m.list.content.getChildCount()
    if index < 0 or index >= count then return

    row = m.rows[index]
    if row = invalid then return
    if not SettingsRowSelectable(row) then return
    m.top.action = {
        type: row.actionType
        payload: row.payload
    }
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    if key = "left"
        if m.settingsTabIndex > 0
            m.settingsTabIndex = m.settingsTabIndex - 1
            RenderSettings()
            return true
        end if
    else if key = "right"
        if m.settingsTabIndex < 2
            m.settingsTabIndex = m.settingsTabIndex + 1
            RenderSettings()
            return true
        end if
    else if key = "OK"
        ' Consume OK here. The list fires itemSelected (which dispatches the
        ' row's action) and then the same press bubbles up; if it reaches
        ' MainScene it sees the UI-scale overlay it just opened and closes it
        ' again. Swallowing it keeps row activation single-path.
        return true
    end if

    ' Everything else (up/down, OK, back) the MarkupList either handled natively
    ' (up/down/OK) or the scene decides (back).
    return false
end function

' --- header skipping --------------------------------------------------------

function RowIsHeader(index as integer) as boolean
    child = m.list.content.getChild(index)
    if child = invalid then return false
    return child.rowKind = "header"
end function

function NextSelectableIndex(fromIndex as integer, direction as integer) as integer
    index = fromIndex + direction
    while index >= 0 and index < m.list.content.getChildCount()
        if not RowIsHeader(index) then return index
        index = index + direction
    end while
    return -1
end function

' --- row building -----------------------------------------------------------

function BuildSettingsRows() as object
    if m.settingsTabIndex = 0 then return BuildGeneralSettingsRows()
    if m.settingsTabIndex = 1 then return BuildInterfaceSettingsRows()
    return BuildPlayerSettingsRows()
end function

function BuildGeneralSettingsRows() as object
    rows = [SettingHeader(TrText("settings.general.header.account"))]

    if not m.state.authSignedIn
        rows.Push(SettingRow(TrText("settings.general.stremioAccount"), TrText("settings.general.notConnected"), "login", invalid, "action", TrText("settings.general.stremioAccount.hintSignedOut")))
    else
        rows.Push(SettingRow(TrText("settings.general.stremioAccount"), TrText("settings.general.connected"), "none", invalid, "info", TrText("settings.general.stremioAccount.hintConnected")))
        rows.Push(SettingRow(TrText("settings.general.refreshLibrary"), "", "refreshLibrary", invalid, "action", TrText("settings.general.refreshLibrary.hint")))
        rows.Push(SettingRow(TrText("settings.general.disconnect"), "", "disconnect", invalid, "action", TrText("settings.general.disconnect.hint")))
    end if

    rows.Push(SettingHeader(TrText("settings.general.header.streaming")))
    rows.Push(SettingRow(TrText("settings.general.streamingServer"), m.state.streamingServerDisplay, "streamingServer", invalid, "action", TrText("settings.general.streamingServer.hint")))
    rows.Push(SettingRow(TrText("settings.general.testStreamingServer"), "", "testStreamingServer", invalid, "action", TrText("settings.general.testStreamingServer.hint")))
    if m.state.streamingServerConfigured
        rows.Push(SettingRow(TrText("settings.general.clearStreamingServer"), "", "clearStreamingServer", invalid, "action", TrText("settings.general.clearStreamingServer.hint")))
    end if

    rows.Push(SettingHeader(TrText("settings.general.header.about")))
    rows.Push(SettingRow(TrText("settings.general.appVersion"), AppVersionValue(), "none", invalid, "info", TrText("settings.general.appVersion.hint")))
    rows.Push(SettingRow(TrText("settings.general.channelBuild"), AppBuildValue(), "none", invalid, "info", TrText("settings.general.channelBuild.hint")))

    rows.Push(SettingHeader(TrText("settings.general.header.help")))
    rows.Push(SettingRow(TrText("settings.general.support"), "", "settingsLink", "support", "action", TrText("settings.general.support.hint")))
    rows.Push(SettingRow(TrText("settings.general.source"), "", "settingsLink", "source", "action", TrText("settings.general.source.hint")))
    rows.Push(SettingRow(TrText("settings.general.terms"), "", "settingsLink", "terms", "action", TrText("settings.general.terms.hint")))
    rows.Push(SettingRow(TrText("settings.general.privacy"), "", "settingsLink", "privacy", "action", TrText("settings.general.privacy.hint")))
    rows.Push(SettingRow(TrText("settings.general.coffee"), "", "settingsLink", "coffee", "action", TrText("settings.general.coffee.hint")))
    return rows
end function

function BuildInterfaceSettingsRows() as object
    blurValue = TrText("common.off")
    if m.state.blurUnwatched then blurValue = TrText("common.on")

    ' The pill colour follows the boolean, never the label: "Activado" and "Ein"
    ' are not "on", so reading the state back out of the translated value would
    ' draw every toggle as off in five of the six languages.
    blurRow = SettingRow(TrText("settings.interface.blurUnwatched"), blurValue, "toggleBlurUnwatched", invalid, "toggle", TrText("settings.interface.blurUnwatched.hint"))
    blurRow.toggleOn = m.state.blurUnwatched

    return [
        SettingHeader(TrText("settings.interface.header.appearance"))
        ' Each language is shown in its own name, the way every platform picker does
        ' it -- someone who has landed in the wrong language has to be able to read
        ' their way out of it.
        SettingRow(TrText("settings.interface.language"), TrOption("language.native", m.state.interfaceLanguage), "interfaceLanguage", invalid, "option", TrText("settings.interface.language.hint"))
        SettingRow(TrText("settings.interface.uiScale"), m.state.uiScalePercent.ToStr() + "%", "uiScale", invalid, "option", TrText("settings.interface.uiScale.hint"))
        SettingRow(TrText("settings.interface.display"), m.state.displayDescription, "uiScale", invalid, "info", TrText("settings.interface.display.hint"))
        SettingHeader(TrText("settings.interface.header.episodes"))
        blurRow
    ]
end function

function BuildPlayerSettingsRows() as object
    return [
        SettingHeader(TrText("settings.player.header.subtitles"))
        SettingRow(TrText("settings.player.defaultLanguage"), TrOption("language", m.state.defaultSubtitleLanguage), "defaultSubtitleLanguage", invalid, "option", TrText("settings.player.defaultLanguage.hint"))
        SettingRow(TrText("settings.player.textSize"), TrOption("subtitle.size", m.state.subtitleTextSize), "subtitleSettings", invalid, "option", TrText("settings.player.textSize.hint"))
        SettingRow(TrText("settings.player.textColor"), TrOption("subtitle.color", m.state.subtitleTextColor), "subtitleSettings", invalid, "option", TrText("settings.player.textColor.hint"))
        SettingRow(TrText("settings.player.background"), TrOption("subtitle.backdrop", m.state.subtitleBackdropOpacity), "subtitleSettings", invalid, "option", TrText("settings.player.background.hint"))
        SettingRow(TrText("settings.player.outlineColor"), TrOption("subtitle.color", m.state.subtitleOutlineColor), "subtitleOutlineColor", invalid, "option", TrText("settings.player.outlineColor.hint"))
        SettingHeader(TrText("settings.player.header.audio"))
        SettingRow(TrText("settings.player.defaultAudio"), TrOption("language", m.state.defaultAudioTrack), "defaultAudioTrack", invalid, "option", TrText("settings.player.defaultAudio.hint"))
    ]
end function

' One settings row, carrying the same actionType/payload pair MainScene's
' dispatcher expects.
function SettingRow(title as string, value as string, actionType as string, payload as dynamic, kind as string, hint as string) as object
    return {
        title: title
        value: value
        actionType: actionType
        payload: payload
        kind: kind
        hint: hint
    }
end function

function SettingHeader(title as string) as object
    return SettingRow(title, "", "none", invalid, "header", "")
end function

function SettingsRowSelectable(row as object) as boolean
    if row = invalid then return false
    if row.kind = "header" then return false
    return row.actionType <> "none"
end function

' Finds the next row that can take focus, searching in `direction` first and then
' back the other way, so a section that starts or ends with a header still lands
' somewhere sensible.
function NextSelectableSettingsIndex(rows as object, fromIndex as integer, direction as integer) as integer
    index = fromIndex + direction
    while index >= 0 and index < rows.Count()
        if SettingsRowSelectable(rows[index]) then return index
        index = index + direction
    end while

    index = fromIndex - direction
    while index >= 0 and index < rows.Count()
        if SettingsRowSelectable(rows[index]) then return index
        index = index - direction
    end while

    return -1
end function

' --- tabs and detail --------------------------------------------------------

sub UpdateSettingsTabs()
    for index = 0 to m.tabBackgrounds.Count() - 1
        background = m.tabBackgrounds[index]
        label = m.tabLabels[index]
        if background <> invalid and label <> invalid
            label.text = TrText("settings.tab." + LCase(SettingsTabName(index)))
            if index = m.settingsTabIndex
                background.color = "0x7657FFFF"
                label.color = "0xFFFFFFFF"
            else
                background.color = "0x1B1934FF"
                label.color = "0xA9A6B8FF"
            end if
        end if
    end for

    m.tabIndicator.translation = ScaleUiXY(260 + m.settingsTabIndex * 334, 210)
end sub

function SettingsTabName(index as integer) as string
    tabs = ["general", "interface", "player"]
    return tabs[index]
end function

sub UpdateSettingsDetail(index as integer)
    m.detailEyebrow.text = UCase(TrText("settings.tab." + SettingsTabName(m.settingsTabIndex)))
    if index < 0 or index >= m.rows.Count()
        m.detailTitle.text = ""
        m.detailValue.text = ""
        m.detailHint.text = ""
        return
    end if

    row = m.rows[index]
    m.detailTitle.text = row.title
    m.detailValue.text = row.value
    m.detailHint.text = row.hint
end sub

function SettingsTabSummary() as string
    texts = [
        TrText("settings.summary.general")
        TrText("settings.summary.interface")
        TrText("settings.summary.player")
    ]
    return texts[m.settingsTabIndex]
end function

function SettingsTabDescription() as string
    if m.settingsTabIndex = 0 then return TrText("settings.description.general")
    if m.settingsTabIndex = 1 then return TrText("settings.description.interface")
    return TrText("settings.description.player")
end function

' Keep MainScene's shared chrome (the header and hero labels, which live outside
' this component) in sync with the active tab. MainScene also mirrors tabIndex
' so its * / options handler knows which settings section it is on.
sub EmitScreenInfo()
    m.top.screenInfo = {
        tabIndex: m.settingsTabIndex
        title: "Settings"
        subtitle: SettingsTabSummary()
        heroTitle: "Settings"
        heroDescription: SettingsTabDescription()
    }
end sub

' --- helpers shared with other screens --------------------------------------

function AppVersionValue() as string
    app = CreateObject("roAppInfo")
    return app.GetVersion()
end function

function AppBuildValue() as string
    info = CreateObject("roAppInfo")
    if info = invalid then return TrText("common.unknown")
    id = info.GetID()
    if id = invalid or id = "" then id = TrText("common.unknown")
    if info.IsDev() then return id + "    " + TrText("settings.general.development")
    return id
end function
