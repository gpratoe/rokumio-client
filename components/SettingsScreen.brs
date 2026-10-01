' SettingsScreen — app preferences.
'
' One column of PrefRows backed by SettingsStore: streaming server address
' (edited through a system KeyboardDialog), UI language (cycled on OK), plus a
' Test-server row that hearts the configured streaming server so a playback
' dead-end is caught before pressing play. Every value is rebuilt on entry so
' the rows always reflect the persisted values.

sub init()
    m.title = m.top.FindNode("settingsTitle")
    m.sub = m.top.FindNode("settingsSub")
    m.status = m.top.FindNode("settingsStatus")
    m.list = m.top.FindNode("settingsList")

    t = Theme()
    m.title.color = t.accent
    m.sub.color = t.textSecondary
    m.status.color = t.accent

    m.list.ObserveField("rowItemSelected", "onRowSelected")

    m.rows = []
    m.languages = ["en", "es", "fr", "de", "it", "pt"]
    m.heartbeatTask = invalid
end sub

function OnEnter(params as object) as void
    CancelTestServer()
    BuildRows()
    m.status.text = ""
    m.list.SetFocus(true)
end function

function OnExit() as void
    CancelTestServer()
end function

function OnBackPressed() as boolean
    return false
end function

sub BlurFocus()
end sub

' Rebuild the row list from the live SettingsStore values. The session row is
' first so it is the handiest action: a guest is offered the Stremio login, a
' stremio user their email + logout. The rest follow in fixed order.
sub BuildRows()
    m.rows = []
    if m.stores <> invalid and m.stores.auth.callFunc("AuthGetSession") = "stremio"
        m.rows.Push({
            action: "logout"
            title: "Log out"
            value: SessionValue()
        })
    else
        m.rows.Push({
            action: "login"
            title: "Log in with Stremio"
            value: "Sign in to sync addons and library"
        })
    end if
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
    m.list.jumpToRowItem = [0, 0]
end sub

' The signed-in-account label for the logout row. Prefer the profile email;
' fall back to a neutral label when the fetch that fills it is still running or
' the profile is otherwise absent.
function SessionValue() as string
    if m.stores <> invalid
        user = m.stores.auth.callFunc("AuthGetUser")
        if user <> invalid and user.email <> invalid and user.email <> "" then return user.email
    end if
    return "Signed in with Stremio"
end function

function ServerValue() as string
    if m.stores = invalid then return "—"
    address = m.stores.settings.callFunc("SettingsGetServerAddress")
    if address = "" then return "not set"
    return address
end function

function LanguageValue() as string
    if m.stores <> invalid then return m.stores.settings.callFunc("SettingsGetLanguage")
    return ""
end function

sub onRowSelected()
    data = m.list.rowItemSelected
    if data = invalid or data.Count() < 2 then return
    index = data[0]
    if index < 0 or index >= m.rows.Count() then return
    action = m.rows[index].action
    if action = "login"
        SignIn()
    else if action = "logout"
        SignOut()
    else if action = "server"
        EditServer()
    else if action = "language"
        CycleLanguage()
    else if action = "testServer"
        TestServer()
    end if
end sub

' The session actions hand off to the Scene, the only place that owns auth.
' Publishing through pushRequest keeps this screen a pure reporter — the Scene
' runs the link-code flow or the logout confirm/teardown.
sub SignIn()
    m.top.pushRequest = { action: "login" }
end sub

sub SignOut()
    m.top.pushRequest = { action: "logout" }
end sub

' Open the streaming server editor. Empty input clears the address (clearing is
' a deliberate action); anything else is validated by SettingsStore.
sub EditServer()
    dialog = CreateObject("roSGNode", "StandardKeyboardDialog")
    ' A StandardDialog takes its colours from its own palette field and, with
    ' none set, from whatever is higher in the scene graph. Nothing in this app
    ' sets one — the Scene included — so without this the prompt comes up in
    ' Roku's default grey over a themed app. Same palette the exit and support
    ' dialogs already ask for.
    dialog.title = "Streaming server address"
    ' message is an ARRAY of strings on StandardKeyboardDialog. A bare string is
    ' a wrong-typed field set: discarded with a warning, leaving the prompt with
    ' no help text under the title and nothing on screen to explain why.
    dialog.message = ["e.g. http://192.168.1.5:4141 — leave empty and OK to clear"]
    dialog.text = ""
    if m.stores <> invalid then dialog.text = m.stores.settings.callFunc("SettingsGetServerAddress")
    dialog.buttons = ["OK", "Cancel"]
    dialog.observeField("buttonSelected", "onServerChoice")
    ' Caret after the address rather than at 0, so editing it does not start by
    ' arrowing past the whole value. Before the dialog is shown: the internal
    ' edit box is built at CreateObject time, so this is the earliest the setting
    ' can land. See ApplyServerKeyboard.
    ApplyServerKeyboard(dialog)
    m.top.getScene().dialog = dialog
end sub

' Configures the dialog's internal VoiceTextEditBox, which StandardKeyboardDialog
' builds for itself and which is therefore reached through the dialog rather than
' owned here. The box exists as soon as the node is created — confirmed on
' device — so this is called inline and needs nothing to wait for.
'
' No try, deliberately. A throw here prints the offending field and line to the
' device console, and the console is where this is read. The previous version
' swallowed the error, which is how a caret fix that never took became
' indistinguishable from one that did.
sub ApplyServerKeyboard(dialog as object) as void
    if dialog = invalid then return
    editor = dialog.textEditBox
    if editor = invalid then return

    ' Dictation mode, and the reason voice came out one letter at a time.
    ' DynamicKeyboard builds its internal edit box with voiceEntryType
    ' "alphanumeric" — letter-by-letter, meant for street addresses — which
    ' beats the node class default of "generic". The dialog's own
    ' keyboardDomain defaults to "generic" too but does not reach this field.
    ' "generic" is full word input, which is what a text prompt wants. First, so
    ' it lands even if the caret write below is the thing being rejected.
    editor.voiceEntryType = "generic"
    ' Caret after the text rather than at 0, so backspace and the left arrow have
    ' something to act on: a caret parked at 0 makes both of them no-ops by
    ' definition while typing still appends, which from the outside is
    ' indistinguishable from a dead keyboard.
    editor.cursorPosition = Len(dialog.text)
end sub

sub onServerChoice()
    dialog = m.top.getScene().dialog
    if dialog <> invalid
        index = dialog.buttonSelected
        chosen = dialog.text
        ' StandardDialog's own dismissal, and the one ConfirmExitDialog already
        ' uses: setting close makes the scene drop the node from the dialog slot
        ' by itself. Both values are read above before anything is torn down.
        dialog.close = true
        if index = 0
            if chosen = invalid or chosen.Trim() = ""
                m.stores.settings.callFunc("SettingsClearServerAddress")
                m.status.text = "Server address cleared."
            else if m.stores.settings.callFunc("SettingsSetServerAddress", chosen)
                m.status.text = "Server address updated."
            else
                m.status.text = "Invalid address — use http://host[:port]"
            end if
            ' Every branch above ends in a write, so the result is the same
            ' question on all of them: did the registry take it? Asked here
            ' rather than after each setter because the store saves itself now
            ' and there is no per-setter answer to check.
            if m.stores.settings.callFunc("SettingsSaveFailed") then m.status.text = m.status.text + " — not saved"
            ReportSaveFault()
            BuildRows()
        end if
    end if
    m.list.SetFocus(true)
end sub

' Mirrors the store's last write result into the Scene's fault strip, clearing
' it on the next success. The status line says what just happened on this
' screen; the strip is what a refused write looks like from anywhere else in the
' app, including after the user has navigated away — which is the only place a
' setting that did not save can be noticed, since nothing about it is wrong
' until the next launch.
sub ReportSaveFault()
    if m.stores = invalid then return
    failed = m.stores.settings.callFunc("SettingsSaveFailed")
    scene = m.top.getScene()
    if scene <> invalid then scene.callFunc("ReportStoreFault", "settings could not be saved", failed)
end sub

' Cycle the language row's options forward.
sub CycleLanguage() as void
    current = m.stores.settings.callFunc("SettingsGetLanguage")
    index = 0
    for i = 0 to m.languages.Count() - 1
        if m.languages[i] = current then index = i
    end for
    nextLanguage = m.languages[(index + 1) mod m.languages.Count()]
    if m.stores.settings.callFunc("SettingsSetLanguage", nextLanguage)
        ReportSaveFault()
        BuildRows()
    end if
end sub

' Report the streaming server's reachability through the status line. Verifying
' the address before trying to play a torrent stream turns a 90-second playback
' dead-end into a quick, obvious check. The heartbeat rides the default request
' timeout, so it runs through HeartbeatTask — a dead address costs the worker
' thread, not a frozen Settings screen.
sub TestServer() as void
    if m.stores = invalid then return
    address = m.stores.settings.callFunc("SettingsGetServerAddress")
    if address = ""
        m.status.text = "Set a streaming server address first."
        return
    end if
    if m.heartbeatTask <> invalid then return

    m.status.text = "Testing server…"
    task = AsyncTask_Launch(m.top, "HeartbeatTask", "onTestServerResult", { address: address }, "heartbeatTask")
    m.heartbeatTask = task
end sub

' The heartbeat finished. A stale result that landed after CancelTestServer is
' dropped by the m.heartbeatTask guard.
sub onTestServerResult()
    if m.heartbeatTask = invalid then return
    task = m.heartbeatTask
    m.heartbeatTask = invalid
    result = task.result
    AsyncTask_Reap(task, m.top, false)

    if result.alive
        m.status.text = "Server OK."
    else
        m.status.text = "Server unreachable: " + result.error
    end if
end sub

sub CancelTestServer()
    if m.heartbeatTask <> invalid
        task = m.heartbeatTask
        m.heartbeatTask = invalid
        AsyncTask_Reap(task, m.top, true)
    end if
end sub
