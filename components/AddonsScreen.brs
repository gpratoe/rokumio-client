' AddonsScreen — installed add-on manager.
'
' One column of PrefRows: an "Add add-on" row on top (installs by fetching a
' manifest URL through a system KeyboardDialog), then one row per add-on from
' AddonsStore.GetAll(). Removing any add-on — including a shipped built-in —
' requires a confirmation dialog; the builtin flag is passed to
' AddonsStore.Uninstall so a same-id mirror and its shipped seed are told
' apart. The list is rebuilt after every install/remove so it always reflects
' the store.
'
' The manifest fetch happens on AddonsInstallTask (off the render thread — the
' request can park up to the 15s default timeout). The task validates against a
' registry-less store and returns the installed record; on success the real
' store adopts it through AddonsStore.Register, which applies the same duplicate
' rule and persists. "Installing…" sits on the status line while it runs; a
' stale result that lands after exit/cancel is dropped by the m.installTask
' guard.

sub init()
    m.title = m.top.FindNode("addonsTitle")
    m.sub = m.top.FindNode("addonsSub")
    m.status = m.top.FindNode("addonsStatus")
    m.list = m.top.FindNode("addonsList")

    t = Theme()
    m.title.color = t.accent
    m.sub.color = t.textSecondary
    m.status.color = t.accent

    m.list.ObserveField("rowItemSelected", "onRowSelected")

    m.rows = []
    m.installTask = invalid
end sub

function OnEnter(params as object) as void
    CancelInstall()
    BuildRows()
    m.status.text = ""
    m.list.callFunc("SetListFocus")
end function

function OnExit() as void
    CancelInstall()
end function

function OnBackPressed() as boolean
    return false
end function

sub BlurFocus()
end sub

' Rebuild the list: the add row first, then every installed add-on.
sub BuildRows()
    m.rows = []
    m.rows.Push({
        action: "add"
        title: "Add add-on"
        value: "Install by add-on URL"
    })
    if m.stores <> invalid
        for each addon in m.stores.addons.callFunc("AddonsGetAll")
            value = addon.address
            if addon.builtin = true then value = "Built-in · " + value
            m.rows.Push({
                action: "addon"
                id: addon.id
                name: addon.name
                builtin: addon.builtin
                title: addon.name
                value: value
            })
        end for
    end if

    content = CreateObject("roSGNode", "ContentNode")
    for each row in m.rows
        entry = content.CreateChild("ContentNode")
        item = entry.CreateChild("ContentNode")
        item.title = row.title
        item.description = row.value
    end for
    m.list.content = content

    installed = m.rows.Count() - 1
    if installed < 0 then installed = 0
    quantity = installed.ToStr() + " add-ons"
    if installed = 1 then quantity = "1 add-on"
    m.sub.text = "OK adds or removes an add-on, Back returns to Home · " + quantity
end sub

sub onRowSelected()
    data = m.list.rowItemSelected
    if data = invalid or data.Count() < 2 then return
    index = data[0]
    if index < 0 or index >= m.rows.Count() then return
    row = m.rows[index]
    if row.action = "add"
        ShowAddDialog()
    else
        ShowRemoveConfirm(row)
    end if
end sub

' Install flow: a KeyboardDialog whose OK kicks AddonsInstallTask.
sub ShowAddDialog()
    dialog = CreateObject("roSGNode", "StandardKeyboardDialog")
    ' Palette and the array-shaped message are the two things that differ from
    ' the legacy node. See the same block in SettingsScreen for why each one
    ' fails quietly rather than loudly.
    dialog.palette = AppPalette()
    dialog.title = "Add add-on"
    dialog.message = ["Enter the add-on's manifest URL, e.g. https://example.com/manifest.json"]
    dialog.text = ""
    dialog.buttons = ["OK", "Cancel"]
    dialog.observeField("buttonSelected", "onAddChoice")
    ' Full word dictation, and the caret the dialog does not place for itself.
    ' Before the dialog is shown: the internal edit box is built at CreateObject
    ' time, so this is the earliest the setting can land. See ApplyAddKeyboard.
    ApplyAddKeyboard(dialog)
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
sub ApplyAddKeyboard(dialog as object) as void
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

sub onAddChoice()
    dialog = m.top.getScene().dialog
    if dialog <> invalid
        index = dialog.buttonSelected
        address = dialog.text
        ' StandardDialog's own dismissal, and the one ConfirmExitDialog already
        ' uses: setting close makes the scene drop the node from the dialog slot
        ' by itself. Both values are read above before anything is torn down.
        dialog.close = true
        if index = 0
            StartInstall(address.Trim())
        end if
    end if
    m.list.callFunc("SetListFocus")
end sub

' Kick the manifest fetch off the render thread. AddonsInstallTask runs
' AddonsStore.Install against a registry-less store and returns the installed
' record (or a validation/fetch error); the real store adopts it on success.
sub StartInstall(address as string)
    if m.stores = invalid then return
    if m.installTask <> invalid then return

    m.status.text = "Installing…"
    task = AsyncTask_Launch(m.top, "AddonsInstallTask", "onInstallResult", { address: address }, "addonsInstall")
    m.installTask = task
end sub

' The install finished. A stale result that landed after CancelInstall (or
' exit) is dropped by the m.installTask guard. Success adopts the returned
' record through the real store (duplicate rule enforced again there).
sub onInstallResult()
    if m.installTask = invalid then return
    task = m.installTask
    m.installTask = invalid
    result = task.result
    AsyncTask_Reap(task, m.top, false)

    if result <> invalid and result.ok and result.record <> invalid
        if m.stores <> invalid and m.stores.addons.callFunc("AddonsRegister", result.record)
            m.status.text = "Installed " + result.id + "."
        else
            m.status.text = "Could not install: addon already installed"
        end if
    else
        error = ""
        if result <> invalid and result.error <> invalid then error = result.error
        m.status.text = "Could not install: " + error
    end if
    BuildRows()
end sub

sub CancelInstall()
    if m.installTask <> invalid
        task = m.installTask
        m.installTask = invalid
        AsyncTask_Reap(task, m.top, true)
    end if
end sub

' Confirm removal of any add-on. Built-ins are shipped defaults, not sacred:
' the device is the user's, so they get the same two-step confirmation and the
' builtin flag disambiguates a shipped seed from a same-id installed mirror.
sub ShowRemoveConfirm(row as object)
    m.pendingRow = row
    nodeType = "StandardMessageDialog"
    dialog = CreateObject("roSGNode", nodeType)
    dialog.title = "Remove " + row.name + "?"
    dialog.message = ["You can add it back at any time from this screen."]
    dialog.buttons = ["Remove", "Cancel"]
    dialog.observeField("buttonSelected", "onRemoveChoice")
    m.top.getScene().dialog = dialog
end sub

sub onRemoveChoice()
    dialog = m.top.getScene().dialog
    if dialog <> invalid
        index = dialog.buttonSelected
        m.top.getScene().dialog = invalid
        if index = 0 and m.pendingRow <> invalid
            removed = m.stores.addons.callFunc("AddonsUninstall", m.pendingRow.id, m.pendingRow.builtin)
            if removed
                m.status.text = "Removed " + m.pendingRow.name + "."
            else
                m.status.text = "Could not remove " + m.pendingRow.name + "."
            end if
            BuildRows()
        end if
    end if
    m.list.callFunc("SetListFocus")
end sub
