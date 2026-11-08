' AddonsScreen — installed add-on manager.
'
' One AddonTile per add-on: logo, name, dimmed version, the add-on's scope and
' its description. The action on the right is part of the row model, not the
' markup, so the same tile can become a search result later (Uninstall here,
' Install there). The "Add add-on" entry uses the same tile and installs by
' fetching a manifest URL through a system KeyboardDialog.
'
' Removing any add-on — including a shipped built-in — requires a confirmation
' dialog; the builtin flag is passed to AddonsStore.Uninstall so a same-id
' mirror and its shipped seed are told apart. The list is rebuilt after every
' install/remove so it always reflects the store.
'
' Display metadata (description and logo) is retained by AddonsStore. Records
' stored before that existed are refreshed off the render thread by
' AddonMetadataTask while their tiles show a placeholder; successful results
' are persisted back through the store. Built-ins are virtual, so their fetched
' metadata lives in this screen's session cache.
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

    ' Decorative companion-app panel (see the XML comment). Coloured here rather
    ' than in markup so it follows Theme() like every other screen does.
    m.companionPlate = m.top.FindNode("companionPlate")
    m.companionTitle = m.top.FindNode("companionTitle")
    m.companionCaption = m.top.FindNode("companionCaption")
    m.setupHint = m.top.FindNode("setupHint")
    m.setupUrl = m.top.FindNode("setupUrl")

    t = Theme()
    m.title.color = t.accent
    m.sub.color = t.textSecondary
    m.status.color = t.accent
    m.companionPlate.color = t.screenBg
    m.companionTitle.color = t.accent
    m.companionCaption.color = t.textSecondary
    m.setupHint.color = t.textSecondary
    m.setupUrl.color = t.accent

    m.list.ObserveField("rowItemSelected", "onRowSelected")

    m.rows = []
    m.rowNodes = []
    m.metadataCache = {}
    m.metadataTask = invalid
    m.metadataFailures = 0
    m.installTask = invalid
end sub

' Address of the local setup page, forwarded from the Scene at launch. The two
' labels are born hidden so this screen never flashes an address that has not
' been published yet.
sub SetSetupAddress(url as dynamic)
    if url = invalid then return
    if url = "" then return
    m.setupUrl.text = url
    m.setupHint.visible = true
    m.setupUrl.visible = true
end sub

function OnEnter(params as object) as void
    RefreshTexts()
    m.title.text = Lang("addons", "title")
    m.companionTitle.text = Lang("addons", "companionTitle")
    m.companionCaption.text = Lang("addons", "companionCaption")
    m.setupHint.text = Lang("addons", "setupHint")
    CancelInstall()
    CancelMetadata()
    m.status.text = ""
    BuildRows()
    m.list.callFunc("SetListFocus")
    StartMetadataRefresh()
end function

function OnExit() as void
    CancelInstall()
    CancelMetadata()
end function

function OnBackPressed() as boolean
    return false
end function

sub BlurFocus()
end sub

' Rebuild the list: the add row first, then every installed add-on. Focus is
' restored to the row the user was on because installing, removing or adopting
' a result is not a reason to throw the cursor back to the top.
sub BuildRows()
    focusRow = 0
    if m.list.rowItemFocused <> invalid and m.list.rowItemFocused.Count() > 0 then focusRow = m.list.rowItemFocused[0]

    m.rows = []
    m.rows.Push({
        actionKey: "add"
        id: ""
        name: ""
        title: Lang("addons", "addRow")
        description: Lang("addons", "addRowValue")
        logo: "pkg:/images/puzzle.png"
        version: ""
        scope: ""
        actionLabel: Lang("addons", "addAction")
        address: ""
        builtin: false
        metadataPending: false
    })
    if m.stores <> invalid
        for each addon in m.stores.addons.callFunc("AddonsGetAll")
            ' Add-on records come from manifests an add-on supplied, so every
            ' displayed value is coerced rather than trusted to be a string.
            row = {
                actionKey: "uninstall"
                id: StringOf(addon.id)
                name: StringOf(addon.name)
                title: StringOf(addon.name)
                description: StringOf(addon.description)
                logo: StringOf(addon.logo)
                version: StringOf(addon.version)
                scope: AddonScopeLabel(addon.types)
                actionLabel: Lang("addons", "uninstallAction")
                address: StringOf(addon.address)
                builtin: (addon.builtin = true)
                metadataPending: MetadataNeeded(addon)
            }
            ApplyCachedMetadata(row)
            if row.metadataPending and row.description = ""
                row.description = Lang("addons", "loadingMetadata")
            end if
            if row.description = "" then row.description = Lang("addons", "noDescription")
            if row.logo = "" then row.logo = "pkg:/images/puzzle.png"
            m.rows.Push(row)
        end for
    end if

    content = CreateObject("roSGNode", "ContentNode")
    m.rowNodes = []
    for each row in m.rows
        entry = content.CreateChild("ContentNode")
        item = entry.CreateChild("AddonTileContent")
        PaintRowNode(item, row)
        m.rowNodes.Push(item)
    end for

    if focusRow >= m.rows.Count() then focusRow = m.rows.Count() - 1
    if focusRow < 0 then focusRow = 0
    m.list.focusRow = focusRow
    m.list.content = content

    installed = m.rows.Count() - 1
    if installed < 0 then installed = 0
    quantity = Fill(Lang("addons", "countMany"), { count: installed.ToStr() })
    if installed = 1 then quantity = Lang("addons", "countOne")
    m.sub.text = Fill(Lang("addons", "subtitle"), { count: quantity })
end sub

' Copy one row model into its AddonTileContent node. The tile watches those
' fields, so a metadata result repaints a row without rebuilding the list.
sub PaintRowNode(item as object, row as object)
    item.title = row.title
    item.description = row.description
    item.addonLogo = row.logo
    item.addonVersion = row.version
    item.addonScope = row.scope
    item.actionKey = row.actionKey
    item.actionLabel = row.actionLabel
end sub

sub onRowSelected()
    data = m.list.rowItemSelected
    if data = invalid or data.Count() < 2 then return
    index = data[0]
    if index < 0 or index >= m.rows.Count() then return
    row = m.rows[index]
    ' The action is data, not the row's identity: a future add-on search can
    ' hand the same tile an "install" action without touching the screen.
    if row.actionKey = "add"
        ShowAddDialog()
    else if row.actionKey = "uninstall"
        ShowRemoveConfirm(row)
    end if
end sub

' --- metadata refresh ------------------------------------------------------

' A logo that is an SVG cannot be rendered by Roku's Poster, so it needs an
' off-thread PNG candidate resolution even when its other metadata is cached.
function LogoNeedsResolution(logo as dynamic) as boolean
    url = StringOf(logo).Trim()
    if url = "" then return false
    path = url
    queryStart = url.InStr("?")
    if queryStart > 0 then path = url.Left(queryStart - 1)
    if path.Len() < 4 then return false
    return LCase(path.Right(4)) = ".svg"
end function

' True when this row has no display metadata yet. A cached success is final for
' this screen session; an unreachable manifest is retried on the next entry.
function MetadataNeeded(addon as object) as boolean
    address = StringOf(addon.address)
    if address = "" then return false
    if m.metadataCache[address] <> invalid then return false
    if addon.metadataFetched <> true then return true
    return LogoNeedsResolution(addon.logo)
end function

sub ApplyCachedMetadata(row as object)
    cached = m.metadataCache[row.address]
    if cached = invalid then return
    row.metadataPending = false
    if cached.ok <> true then return
    description = StringOf(cached.description)
    if description <> "" then row.description = description
    logo = StringOf(cached.logo)
    if logo <> "" then row.logo = logo
    version = StringOf(cached.version)
    if version <> "" then row.version = version
end sub

sub StartMetadataRefresh()
    if m.stores = invalid then return
    pending = []
    seen = {}
    for each row in m.rows
        if row.metadataPending <> true then continue for
        address = StringOf(row.address)
        if address = "" or seen[address] = true then continue for
        seen[address] = true
        pending.Push({ id: row.id, address: address })
    end for
    if pending.Count() = 0 then return

    m.metadataFailures = 0
    m.metadataTask = AsyncTask_Launch(m.top, "AddonMetadataTask", "onMetadataResult", { addons: pending }, "addonsMetadata")
end sub

sub onMetadataResult()
    if m.metadataTask = invalid then return
    task = m.metadataTask
    result = task.result
    if result = invalid then return

    if result.done = true
        m.metadataTask = invalid
        AsyncTask_Reap(task, m.top, false)
        if StringOf(result.error) <> "" then m.metadataFailures = m.metadataFailures + 1
        FinishMetadataRefresh()
        return
    end if

    address = StringOf(result.address)
    if address = "" then return
    if result.ok = true
        description = StringOf(result.description)
        logo = StringOf(result.logo)
        version = StringOf(result.version)
        m.metadataCache[address] = { ok: true, description: description, logo: logo, version: version }
        if m.stores <> invalid
            m.stores.addons.callFunc("AddonsUpdateDisplayMetadata", StringOf(result.id), address, description, logo, version)
        end if
        ApplyMetadataToRows(address)
    else
        m.metadataFailures = m.metadataFailures + 1
        MarkMetadataFailed(address)
    end if
end sub

sub ApplyMetadataToRows(address as string)
    cached = m.metadataCache[address]
    for i = 0 to m.rows.Count() - 1
        row = m.rows[i]
        if row.address <> address then continue for
        row.metadataPending = false
        if cached <> invalid
            description = StringOf(cached.description)
            if description <> "" then row.description = description
            logo = StringOf(cached.logo)
            if logo <> "" then row.logo = logo
            version = StringOf(cached.version)
            if version <> "" then row.version = version
        end if
        if row.description = "" then row.description = Lang("addons", "noDescription")
        if row.logo = "" then row.logo = "pkg:/images/puzzle.png"
        PaintRowNode(m.rowNodes[i], row)
    end for
end sub

sub MarkMetadataFailed(address as string)
    for i = 0 to m.rows.Count() - 1
        row = m.rows[i]
        if row.address <> address then continue for
        row.metadataPending = false
        if row.description = "" or row.description = Lang("addons", "loadingMetadata")
            row.description = Lang("addons", "noDescription")
        end if
        if row.logo = "" then row.logo = "pkg:/images/puzzle.png"
        PaintRowNode(m.rowNodes[i], row)
    end for
end sub

' The worker has ended. Any row still pending lost its result (or the task was
' cancelled); leave it on the no-description fallback rather than a spinner-like
' "loading" line that will never change. Failures land as a toast.
sub FinishMetadataRefresh()
    for i = 0 to m.rows.Count() - 1
        row = m.rows[i]
        if row.metadataPending <> true then continue for
        row.metadataPending = false
        if row.description = "" or row.description = Lang("addons", "loadingMetadata")
            row.description = Lang("addons", "noDescription")
        end if
        PaintRowNode(m.rowNodes[i], row)
    end for
    if m.metadataFailures > 0
        Notify(Lang("addons", "metadataUnavailable"), "error")
    end if
end sub

sub CancelMetadata()
    if m.metadataTask <> invalid
        task = m.metadataTask
        m.metadataTask = invalid
        AsyncTask_Reap(task, m.top, true)
    end if
end sub

' A manifest may declare any type name; the known ones use the app's own
' vocabulary and anything else is title-cased as the manifest wrote it.
function AddonScopeLabel(types as dynamic) as string
    if types = invalid or Type(types) <> "roArray" then return Lang("addons", "scopeOther")
    labels = []
    seen = {}
    for each declared in types
        value = LCase(StringOf(declared).Trim())
        if value = "" then continue for
        label = AddonTypeLabel(value)
        if seen[label] = true then continue for
        seen[label] = true
        labels.Push(label)
    end for
    if labels.Count() = 0 then return Lang("addons", "scopeOther")
    return labels.Join(" · ")
end function

function AddonTypeLabel(metaType as string) as string
    if metaType = "movie" then return Lang("common", "movies")
    if metaType = "series" then return Lang("common", "series")
    if metaType = "channel" or metaType = "tv" then return Lang("common", "channels")
    if metaType = "other" then return Lang("addons", "scopeOther")
    return UCase(metaType.Left(1)) + metaType.Mid(1)
end function

' --- install / remove ------------------------------------------------------

' Install flow: a KeyboardDialog whose OK kicks AddonsInstallTask.
sub ShowAddDialog()
    dialog = CreateObject("roSGNode", "StandardKeyboardDialog")
    ' Palette and the array-shaped message are the two things that differ from
    ' the legacy node. See the same block in SettingsScreen for why each one
    ' fails quietly rather than loudly.
    dialog.title = Lang("addons", "addRow")
    dialog.message = [Lang("addons", "addDialogHelp")]
    dialog.text = ""
    dialog.buttons = [Lang("common", "ok"), Lang("common", "cancel")]
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
        ' StandardDialog's own dismissal, and the one the exit confirm already
        ' uses: setting close makes the scene drop the node from the dialog slot
        ' by itself. Both values are read above before anything is torn down.
        dialog.close = true
        if index = 0
            StartInstall(address.Trim())
        end if
    end if
    m.list.callFunc("SetListFocus")
end sub

sub Notify(text as string, kind = "info" as string)
    scene = m.top.getScene()
    if scene <> invalid then scene.callFunc("Notify", text, kind)
end sub

' Kick the manifest fetch off the render thread. AddonsInstallTask runs
' AddonsStore.Install against a registry-less store and returns the installed
' record (or a validation/fetch error); the real store adopts it on success.
sub StartInstall(address as string)
    if m.stores = invalid then return
    if m.installTask <> invalid then return

    m.status.text = Lang("addons", "statusInstalling")
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
            ' The account learns about the install the same way it learns
            ' about a removal (see onRemoveChoice): the descriptor rides to
            ' MainScene, which mutates the mirror and pumps one collection
            ' put. Nothing to sync from the screen's side.
            m.top.addonInstalled = { transportUrl: result.transportUrl, manifest: result.manifest }
            Notify(Fill(Lang("addons", "statusInstalled"), { id: result.id }))
        else
            Notify(Lang("addons", "statusInstallDuplicate"))
        end if
    else
        error = ""
        if result <> invalid and result.error <> invalid then error = result.error
        Notify(Fill(Lang("addons", "statusInstallFailed"), { error: error }), "error")
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
    dialog.title = Fill(Lang("addons", "removeDialogTitle"), { name: row.name })
    dialog.message = [Lang("addons", "removeDialogMessage")]
    dialog.buttons = [Lang("addons", "removeButton"), Lang("common", "cancel")]
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
                ' The account learns about the removal too — a device-only
                ' removal would be resurrected by the next launch sync, which
                ' is exactly why MainScene receives this rep. A removal that
                ' lands without a put (guest session, mirror unknown, id the
                ' account never had) is reported from MainScene on its fault
                ' strip; the local state is final either way.
                if m.pendingRow.builtin = false then m.top.addonRemoved = { id: m.pendingRow.id }
                Notify(Fill(Lang("addons", "statusRemoved"), { name: m.pendingRow.name }))
            else
                Notify(Fill(Lang("addons", "statusRemoveFailed"), { name: m.pendingRow.name }), "error")
            end if
            BuildRows()
        end if
    end if
    m.list.callFunc("SetListFocus")
end sub
