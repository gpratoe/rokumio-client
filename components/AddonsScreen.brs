' AddonsScreen — installed add-on manager.
'
' One column of PrefRows: an "Add add-on" row on top (installs by fetching a
' manifest URL through a system KeyboardDialog), then one row per installed
' add-on from AddonsStore.GetAll(). Removing a non-built-in requires a
' confirmation dialog; protected built-ins are read-only. The list is rebuilt
' after every install/remove so it always reflects the store.
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

    m.list.ObserveField("rowItemSelected", "onRowSelected")

    m.rows = []
    m.installTask = invalid
end sub

' Stores are class instances, which cannot cross components through an interface
' field, so the Scene hands them over with callFunc instead.
function SetStores(stores as object) as void
    m.stores = stores
end function

function OnEnter(params as object) as void
    CancelInstall()
    BuildRows()
    m.status.text = ""
    m.list.SetFocus(true)
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
    if m.stores <> invalid and m.stores.addons <> invalid
        for each addon in m.stores.addons.GetAll()
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
    m.list.numRows = m.rows.Count()
    m.list.jumpToRowItem = [0, 0]
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
    dialog = CreateObject("roSGNode", "KeyboardDialog")
    dialog.title = "Add add-on"
    dialog.message = "Enter the add-on's manifest URL, e.g. https://example.com/manifest.json"
    dialog.text = ""
    dialog.buttons = ["OK", "Cancel"]
    dialog.observeField("buttonSelected", "onAddChoice")
    m.top.getScene().dialog = dialog
end sub

sub onAddChoice()
    dialog = m.top.getScene().dialog
    if dialog <> invalid
        index = dialog.buttonSelected
        address = dialog.text
        m.top.getScene().dialog = invalid
        if index = 0
            StartInstall(address.Trim())
        end if
    end if
    m.list.SetFocus(true)
end sub

' Kick the manifest fetch off the render thread. AddonsInstallTask runs
' AddonsStore.Install against a registry-less store and returns the installed
' record (or a validation/fetch error); the real store adopts it on success.
sub StartInstall(address as string)
    if m.stores = invalid or m.stores.addons = invalid then return
    if m.installTask <> invalid then return
    if address = ""
        m.status.text = "Could not install: no addon address"
        return
    end if

    m.status.text = "Installing…"
    task = CreateObject("roSGNode", "AddonsInstallTask")
    task.id = "addonsInstall"
    m.top.AppendChild(task)
    task.address = address
    task.observeField("result", "onInstallResult")
    m.installTask = task
    task.control = "RUN"
end sub

' The install finished. A stale result that landed after CancelInstall (or
' exit) is dropped by the m.installTask guard. Success adopts the returned
' record through the real store (duplicate rule enforced again there).
sub onInstallResult()
    if m.installTask = invalid then return
    task = m.installTask
    m.installTask = invalid
    result = task.result
    task.unobserveField("result")
    if task.getParent() <> invalid then m.top.RemoveChild(task)

    if result <> invalid and result.ok and result.record <> invalid
        if m.stores <> invalid and m.stores.addons.Register(result.record)
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
        m.installTask.unobserveField("result")
        m.installTask.control = "STOP"
        if m.installTask.getParent() <> invalid then m.top.RemoveChild(m.installTask)
        m.installTask = invalid
    end if
end sub

' Confirm removal of a non-built-in add-on. Built-ins are protected and just
' report back, so removing the seeded Torrentio (or anything else) is always a
' deliberate two-step action.
sub ShowRemoveConfirm(row as object)
    if row.builtin = true
        m.status.text = row.name + " is a protected built-in and cannot be removed."
        return
    end if
    m.pendingRow = row
    nodeType = "StandardMessageDialog"
    dialog = CreateObject("roSGNode", nodeType)
    dialog.title = "Remove " + row.name + "?"
    dialog.message = "You can add it back at any time from this screen."
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
            removed = m.stores.addons.Uninstall(m.pendingRow.id)
            if removed
                m.status.text = "Removed " + m.pendingRow.name + "."
            else
                m.status.text = "Could not remove " + m.pendingRow.name + "."
            end if
            BuildRows()
        end if
    end if
    m.list.SetFocus(true)
end sub
