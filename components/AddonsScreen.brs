' AddonsScreen — installed add-on manager.
'
' One column of PrefRows: an "Add add-on" row on top (installs by fetching a
' manifest URL through a system KeyboardDialog, AddonsStore.Install), then one
' row per installed add-on from AddonsStore.GetAll(). Removing a non-built-in
' requires a confirmation dialog; protected built-ins are read-only. The list is
' rebuilt after every install/remove so it always reflects the store.

sub init()
    m.title = m.top.FindNode("addonsTitle")
    m.sub = m.top.FindNode("addonsSub")
    m.status = m.top.FindNode("addonsStatus")
    m.list = m.top.FindNode("addonsList")

    m.list.ObserveField("rowItemSelected", "onRowSelected")

    m.rows = []
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

' Install flow: a KeyboardDialog whose OK feeds AddonsStore.Install.
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
            result = m.stores.addons.Install(address.Trim())
            if result.ok
                m.status.text = "Installed " + result.id + "."
            else
                m.status.text = "Could not install: " + result.error
            end if
            BuildRows()
        end if
    end if
    m.list.SetFocus(true)
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
    nodeType = "MessageDialog"
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