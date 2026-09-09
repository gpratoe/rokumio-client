' SettingsScreen — app preferences.
'
' One column of PrefRows backed by SettingsStore: streaming server address
' (edited through a system KeyboardDialog), UI language and UI scale (cycled on
' OK), plus a Test-server row that hearts the configured streaming server so a
' playback dead-end is caught before pressing play. Every value is rebuilt on
' entry so the rows always reflect the persisted values. A successful scale
' change flips scaleChanged, which MainScene observes to reapply the live
' uiRoot scale.

sub init()
    m.title = m.top.FindNode("settingsTitle")
    m.sub = m.top.FindNode("settingsSub")
    m.status = m.top.FindNode("settingsStatus")
    m.list = m.top.FindNode("settingsList")

    m.list.ObserveField("rowItemSelected", "onRowSelected")

    m.rows = []
    m.languages = ["en", "es", "fr", "de", "it", "pt"]
    m.scales = [100, 125, 150]
end sub

' Stores are class instances, which cannot cross components through an interface
' field, so the Scene hands them over with callFunc instead.
function SetStores(stores as object) as void
    m.stores = stores
end function

function OnEnter(params as object) as void
    BuildRows()
    m.status.text = ""
    m.list.SetFocus(true)
end function

function OnExit() as void
end function

function OnBackPressed() as boolean
    return false
end function

sub BlurFocus()
end sub

' Rebuild the row list from the live SettingsStore values.
sub BuildRows()
    m.rows = []
    m.rows.Push({
        action: "server"
        title: "Streaming server"
        value: ServerValue()
    })
    m.rows.Push({
        action: "language"
        title: "Language"
        value: LanguageValue()
    })
    m.rows.Push({
        action: "scale"
        title: "UI scale"
        value: ScaleValue()
    })
    m.rows.Push({
        action: "testServer"
        title: "Test server"
        value: "Check streaming server"
    })

    content = CreateObject("roSGNode", "ContentNode")
    for each row in m.rows
        entry = content.CreateChild("ContentNode")
        item = entry.CreateChild("ContentNode")
        item.title = row.title
        item.description = row.value
    end for
    m.list.content = content
    m.list.numRows = m.rows.Count()
    m.list.jumpToRowItem = [0, 0]
end sub

function ServerValue() as string
    if m.stores = invalid or m.stores.settings = invalid then return "—"
    address = m.stores.settings.GetServerAddress()
    if address = "" then return "not set"
    return address
end function

function LanguageValue() as string
    if m.stores <> invalid and m.stores.settings <> invalid then return m.stores.settings.GetLanguage()
    return ""
end function

function ScaleValue() as string
    if m.stores <> invalid and m.stores.settings <> invalid then return m.stores.settings.GetUiScale().ToStr() + "%"
    return ""
end function

sub onRowSelected()
    data = m.list.rowItemSelected
    if data = invalid or data.Count() < 2 then return
    index = data[0]
    if index < 0 or index >= m.rows.Count() then return
    action = m.rows[index].action
    if action = "server"
        EditServer()
    else if action = "language"
        CycleLanguage()
    else if action = "scale"
        CycleScale()
    else if action = "testServer"
        TestServer()
    end if
end sub

' Open the streaming server editor. Empty input clears the address (clearing is
' a deliberate action); anything else is validated by SettingsStore.
sub EditServer()
    dialog = CreateObject("roSGNode", "KeyboardDialog")
    dialog.title = "Streaming server address"
    dialog.message = "e.g. http://192.168.1.5:4141 — leave empty and OK to clear"
    dialog.text = ""
    if m.stores <> invalid and m.stores.settings <> invalid then dialog.text = m.stores.settings.GetServerAddress()
    dialog.buttons = ["OK", "Cancel"]
    dialog.observeField("buttonSelected", "onServerChoice")
    m.top.getScene().dialog = dialog
end sub

sub onServerChoice()
    dialog = m.top.getScene().dialog
    if dialog <> invalid
        index = dialog.buttonSelected
        chosen = dialog.text
        m.top.getScene().dialog = invalid
        if index = 0
            if chosen = invalid or chosen.Trim() = ""
                m.stores.settings.ClearServerAddress()
                m.status.text = "Server address cleared."
            else if m.stores.settings.SetServerAddress(chosen)
                m.stores.settings.Save()
                m.status.text = "Server address updated."
            else
                m.status.text = "Invalid address — use http://host[:port]"
            end if
            BuildRows()
        end if
    end if
    m.list.SetFocus(true)
end sub

' Cycle the language row's options forward.
sub CycleLanguage() as void
    current = m.stores.settings.GetLanguage()
    index = 0
    for i = 0 to m.languages.Count() - 1
        if m.languages[i] = current then index = i
    end for
    nextLanguage = m.languages[(index + 1) mod m.languages.Count()]
    if m.stores.settings.SetLanguage(nextLanguage)
        m.stores.settings.Save()
        BuildRows()
    end if
end sub

' UI scale: cycle 100/125/150 (all within SettingsStore's 0-200 bounds). On
' success, flip scaleChanged so MainScene reapplies uiRoot.scale live.
sub CycleScale() as void
    current = m.stores.settings.GetUiScale()
    index = 0
    for i = 0 to m.scales.Count() - 1
        if m.scales[i] = current then index = i
    end for
    nextScale = m.scales[(index + 1) mod m.scales.Count()]
    if m.stores.settings.SetUiScale(nextScale)
        m.stores.settings.Save()
        m.status.text = "UI scale updated."
        m.top.scaleChanged = not m.top.scaleChanged
        BuildRows()
    end if
end sub

' Report the streaming server's reachability through the status line. Verifying
' the address before trying to play a torrent stream turns a 90-second playback
' dead-end into a quick, obvious check.
sub TestServer() as void
    if m.stores = invalid or m.stores.settings = invalid or m.stores.playback = invalid then return
    address = m.stores.settings.GetServerAddress()
    if address = ""
        m.status.text = "Set a streaming server address first."
        return
    end if

    m.status.text = "Testing server…"
    result = m.stores.playback.Heartbeat(address)
    print "[rokumio] TestServer '" + address + "'/heartbeat -> ok=" + result.ok.ToStr() + " alive=" + result.alive.ToStr() + " error='" + result.error + "'"
    if result.alive
        m.status.text = "Server OK."
    else
        m.status.text = "Server unreachable: " + result.error
    end if
end sub