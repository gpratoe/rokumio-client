' AddonsScreen — installed add-on manager (Streams-style rich cards).
'
' A full-width RowList of AddonCards: "Add add-on" first, then each installed
' add-on. Hybrid install: local browser setup URL shown in the header and in
' the add-options dialog; manual manifest entry uses the keyboard dialog.
' Metadata/install/remove flows and account-sync signals are preserved.

sub init()
    m.bg = m.top.FindNode("addonsBg")
    m.title = m.top.FindNode("addonsTitle")
    m.setupHeader = m.top.FindNode("setupHeader")
    m.status = m.top.FindNode("addonsStatus")
    m.list = m.top.FindNode("addonsList")
    m.addChipRow = m.top.FindNode("addChipRow")

    t = Theme()
    m.bg.color = "0x000000FF"
    m.title.color = t.textPrimary
    m.status.color = t.accent
    if m.setupHeader <> invalid
        m.setupHeader.drawingStyles = {
            "default": { "fontUri": "font:SmallSystemFont", "color": t.textSecondary }
            "url": { "fontUri": "font:SmallSystemFont", "color": t.accent }
        }
    end if

    m.list.ObserveField("rowItemSelected", "onRowSelected")
    m.addChipRow.ObserveField("selection", "onAddChipSelected")

    m.rows = []
    m.metadataCache = {}
    m.metadataTask = invalid
    m.metadataFailures = 0
    m.installTask = invalid
    m.setupAddress = ""
    m.addOptionsDialog = invalid
end sub

sub SetSetupAddress(url as dynamic)
    if url = invalid then return
    if url = "" then return
    m.setupAddress = url
    UpdateSetupHeader()
end sub

sub UpdateSetupHeader()
    if m.setupHeader = invalid then return
    hasSetup = m.setupAddress <> invalid and m.setupAddress <> ""
    m.setupHeader.visible = hasSetup
    if hasSetup
        prefix = Lang("addons", "browserInstallPrefix")
        m.setupHeader.text = prefix + "<url>" + m.setupAddress + "</url>"
    else
        m.setupHeader.text = ""
    end if
end sub

function OnEnter(params as object) as void
    RefreshTexts()
    m.title.text = Lang("addons", "title")
    UpdateSetupHeader()
    BuildAddChip()
    CancelInstall()
    CancelMetadata()
    m.status.text = ""
    BuildRows(false)
    if m.addChipRow <> invalid then m.addChipRow.callFunc("FocusChip", 0)
    StartMetadataRefresh()
end function

function OnExit() as void
    CancelInstall()
    CancelMetadata()
end function

function OnBackPressed() as boolean
    return false
end function

sub BuildAddChip()
    if m.addChipRow = invalid then return
    m.addChipRow.callFunc("SetChips", [{
        title: Lang("addons", "addRow")
        icon: "pkg:/images/add.png"
        active: false
    }])
end sub

sub RestoreFocus()
    if m.addChipRow <> invalid
        m.addChipRow.callFunc("FocusChip", 0)
    else if m.rows.Count() > 0 and m.list <> invalid
        m.list.SetFocus(true)
    end if
end sub

sub EmptyList()
    content = CreateObject("roSGNode", "ContentNode")
    m.list.content = content
    m.list.numRows = 0
end sub

sub BuildRows(preserveFocus = true as boolean)
    focusRow = 0
    if preserveFocus and m.list.rowItemFocused <> invalid and m.list.rowItemFocused.Count() > 0
        focusRow = m.list.rowItemFocused[0]
    end if

    m.rows = []
    if m.stores <> invalid
        for each addon in m.stores.addons.callFunc("AddonsGetAll")
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
    for each row in m.rows
        rowNode = content.CreateChild("ContentNode")
        item = rowNode.CreateChild("TileContent")
        PaintRowNode(item, row)
    end for

    if m.rows.Count() = 0
        EmptyList()
        return
    end if

    if focusRow >= m.rows.Count() then focusRow = m.rows.Count() - 1
    if focusRow < 0 then focusRow = 0

    m.list.content = content
    m.list.numRows = m.rows.Count()
    m.list.jumpToRowItem = [focusRow, 0]
    if m.top.screenActive and preserveFocus and not ChipHoldingFocus() then m.list.SetFocus(true)
end sub

sub PaintRowNode(item as object, row as object)
    item.title = StringOf(row.title)
    item.description = StringOf(row.description)
    item.addonLogo = StringOf(row.logo)
    item.addonVersion = StringOf(row.version)
    item.addonScope = StringOf(row.scope)
    item.actionKey = StringOf(row.actionKey)
    item.actionLabel = StringOf(row.actionLabel)
end sub

function GetFocusedIndex() as integer
    if m.list.rowItemFocused <> invalid and m.list.rowItemFocused.Count() > 0
        return m.list.rowItemFocused[0]
    end if
    return 0
end function

function ChipHoldingFocus() as boolean
    if m.addChipRow = invalid then return false
    return m.addChipRow.callFunc("HoldingFocus") = true
end function

sub onAddChipSelected()
    ShowAddOptionsDialog()
end sub

sub onRowSelected()
    data = m.list.rowItemSelected
    if data = invalid or data.Count() < 1 then return
    index = data[0]
    if index < 0 or index >= m.rows.Count() then return
    row = m.rows[index]
    if row.actionKey = "uninstall"
        ShowRemoveConfirm(row)
    end if
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "down" and ChipHoldingFocus()
        if m.rows.Count() > 0
            m.addChipRow.callFunc("Blur")
            m.list.SetFocus(true)
            return true
        end if
    else if key = "up" and m.list.hasFocus()
        idx = GetFocusedIndex()
        if idx <= 0 and m.addChipRow <> invalid
            m.addChipRow.callFunc("FocusChip", 0)
            return true
        end if
    end if
    return false
end function

' --- metadata refresh ------------------------------------------------------

function LogoNeedsResolution(logo as dynamic) as boolean
    url = StringOf(logo).Trim()
    if url = "" then return false
    path = url
    queryStart = url.InStr("?")
    if queryStart > 0 then path = url.Left(queryStart - 1)
    if path.Len() < 4 then return false
    return LCase(path.Right(4)) = ".svg"
end function

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
    content = m.list.content
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
        PaintRowByIndex(i, row)
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
        PaintRowByIndex(i, row)
    end for
end sub

sub FinishMetadataRefresh()
    for i = 0 to m.rows.Count() - 1
        row = m.rows[i]
        if row.metadataPending <> true then continue for
        row.metadataPending = false
        if row.description = "" or row.description = Lang("addons", "loadingMetadata")
            row.description = Lang("addons", "noDescription")
        end if
        PaintRowByIndex(i, row)
    end for
    if m.metadataFailures > 0
        Notify(Lang("addons", "metadataUnavailable"), "error")
    end if
end sub

sub PaintRowByIndex(index as integer, row as object)
    content = m.list.content
    if content = invalid then return
    if index < 0 or index >= content.getChildCount() then return
    rowNode = content.getChild(index)
    if rowNode = invalid then return
    item = invalid
    if rowNode.getChildCount() > 0 then item = rowNode.getChild(0)
    if item = invalid then return
    PaintRowNode(item, row)
end sub

sub CancelMetadata()
    if m.metadataTask <> invalid
        task = m.metadataTask
        m.metadataTask = invalid
        AsyncTask_Reap(task, m.top, true)
    end if
end sub

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

' --- install (hybrid) ------------------------------------------------------

sub ShowAddOptionsDialog()
    dialog = CreateObject("roSGNode", "AddAddonDialog")
    texts = {
        title: Lang("addons", "addDialogTitle")
        browserInstallPrefix: Lang("addons", "browserInstallPrefix")
        manualButton: Lang("addons", "manualInstallButton")
        closeButton: Lang("common", "cancel")
        manualInstallOnly: Lang("addons", "manualInstallOnly")
    }
    dialog.callFunc("Configure", m.setupAddress, texts)
    dialog.observeField("buttonSelected", "onAddOptionsChoice")
    m.addOptionsDialog = dialog
    m.top.getScene().dialog = dialog
end sub

sub onAddOptionsChoice()
    dialog = m.addOptionsDialog
    if dialog = invalid then dialog = m.top.getScene().dialog
    index = -1
    if dialog <> invalid then index = dialog.buttonSelected
    m.addOptionsDialog = invalid
    if index = 0
        if m.top.getScene().dialog <> invalid then m.top.getScene().dialog = invalid
        ShowManualAddDialog()
    else
        if m.top.getScene().dialog <> invalid then m.top.getScene().dialog = invalid
        RestoreFocus()
    end if
end sub

sub ShowManualAddDialog()
    dialog = CreateObject("roSGNode", "StandardKeyboardDialog")
    dialog.title = Lang("addons", "addRow")
    dialog.message = [Lang("addons", "addDialogHelp")]
    dialog.text = ""
    dialog.buttons = [Lang("common", "ok"), Lang("common", "cancel")]
    dialog.observeField("buttonSelected", "onAddChoice")
    ApplyAddKeyboard(dialog)
    m.top.getScene().dialog = dialog
end sub

sub ApplyAddKeyboard(dialog as object) as void
    if dialog = invalid then return
    editor = dialog.textEditBox
    if editor = invalid then return
    editor.voiceEntryType = "generic"
    editor.cursorPosition = Len(dialog.text)
end sub

sub onAddChoice()
    dialog = m.top.getScene().dialog
    if dialog <> invalid
        index = dialog.buttonSelected
        address = dialog.text
        dialog.close = true
        if index = 0
            StartInstall(address.Trim())
        end if
    end if
    RestoreFocus()
end sub

sub Notify(text as string, kind = "info" as string)
    scene = m.top.getScene()
    if scene <> invalid then scene.callFunc("Notify", text, kind)
end sub

sub StartInstall(address as string)
    if m.stores = invalid then return
    if m.installTask <> invalid then return

    m.status.text = Lang("addons", "statusInstalling")
    task = AsyncTask_Launch(m.top, "AddonsInstallTask", "onInstallResult", { address: address }, "addonsInstall")
    m.installTask = task
end sub

sub onInstallResult()
    if m.installTask = invalid then return
    task = m.installTask
    m.installTask = invalid
    result = task.result
    AsyncTask_Reap(task, m.top, false)

    if result <> invalid and result.ok and result.record <> invalid
        if m.stores <> invalid and m.stores.addons.callFunc("AddonsRegister", result.record)
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
    m.status.text = ""
    BuildRows(true)
    StartMetadataRefresh()
end sub

sub CancelInstall()
    if m.installTask <> invalid
        task = m.installTask
        m.installTask = invalid
        AsyncTask_Reap(task, m.top, true)
    end if
end sub

' --- remove ----------------------------------------------------------------

sub ShowRemoveConfirm(row as object)
    m.pendingRow = row
    dialog = CreateObject("roSGNode", "StandardMessageDialog")
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
                if m.pendingRow.builtin = false then m.top.addonRemoved = { id: m.pendingRow.id }
                Notify(Fill(Lang("addons", "statusRemoved"), { name: m.pendingRow.name }))
            else
                Notify(Fill(Lang("addons", "statusRemoveFailed"), { name: m.pendingRow.name }), "error")
            end if
            BuildRows(true)
            StartMetadataRefresh()
        end if
    end if
    RestoreFocus()
end sub
