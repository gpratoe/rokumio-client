' HomeRowsScreen — choose which installed add-on catalogs appear on Home.
'
' Catalog declarations come from add-on manifests. CatalogSourcesTask resolves
' missing manifests away from the render thread; this screen owns only the
' remote-control picker, while SettingsStore owns the persisted hidden set.

sub init()
    m.status = m.top.FindNode("homeRowsStatus")
    m.list = m.top.FindNode("homeRowsList")
    m.panelTitle = m.top.FindNode("homeRowsPanelTitle")
    m.panelBody = m.top.FindNode("homeRowsPanelBody")
    m.panelStatus = m.top.FindNode("homeRowsPanelStatus")

    palette = Theme()
    m.status.color = palette.accent
    m.panelPlate = m.top.FindNode("homeRowsPlate")
    m.panelPlate.color = palette.tileFace
    m.panelTitle.color = palette.textPrimary
    m.panelBody.color = palette.textSecondary
    m.panelStatus.color = palette.textSecondary

    m.list.ObserveField("rowItemSelected", "onRowSelected")
    m.list.ObserveField("rowItemFocused", "onRowFocused")
    m.rows = []
    m.focusedRow = -1
    m.sourcesTask = invalid
    m.loading = false
    m.loadFailed = false
end sub

function OnEnter(params as object) as void
    RefreshTexts()
    CancelSources()
    m.rows = []
    m.focusedRow = -1
    m.loading = true
    m.loadFailed = false
    m.status.text = Lang("homeRows", "loading")
    ClearList()
    UpdatePanel()
    StartCatalogDiscovery()
    m.list.callFunc("SetListFocus")
end function

function OnExit() as void
    CancelSources()
end function

function OnBackPressed() as boolean
    return false
end function

sub ClearList()
    content = CreateObject("roSGNode", "ContentNode")
    m.list.focusRow = 0
    m.list.content = content
end sub

' Send only plain add-on descriptors to the shared background manifest resolver.
sub StartCatalogDiscovery()
    if m.stores = invalid
        m.loading = false
        m.loadFailed = true
        m.status.text = Lang("homeRows", "loadFailed")
        UpdatePanel()
        return
    end if

    addons = m.stores.addons.callFunc("AddonsGetAll")
    if addons = invalid then addons = []
    packets = []
    for each addon in addons
        if addon.address = invalid or addon.address = "" then continue for
        name = addon.name
        if name = invalid then name = ""
        packets.Push({
            address: addon.address
            name: name
            resources: addon.resources
            catalogs: addon.catalogs
        })
    end for

    m.sourcesTask = AsyncTask_Launch(m.top, "CatalogSourcesTask", "onSourcesLoaded", {
        addons: packets
    }, "homeRowsSources")
end sub

' The shared source task may first notify its empty alwaysNotify result. Wait for
' its explicit done marker so that notification cannot tear down a live worker.
sub onSourcesLoaded(event as object)
    if m.sourcesTask = invalid or event = invalid then return
    result = event.GetData()
    if result = invalid or result.done <> true then return

    task = m.sourcesTask
    m.sourcesTask = invalid
    AsyncTask_Reap(task, m.top, false)
    m.loading = false

    if result.sources = invalid or Type(result.sources) <> "roArray"
        m.loadFailed = true
        m.status.text = Lang("homeRows", "loadFailed")
        UpdatePanel()
        return
    end if

    m.rows = CatalogRowsFromSources(result.sources)
    m.loadFailed = result.error <> invalid and result.error <> ""
    BuildRows()

    if m.loadFailed
        if m.rows.Count() > 0
            m.status.text = Lang("homeRows", "partialLoad")
        else
            m.status.text = Lang("homeRows", "loadFailed")
        end if
    else if m.rows.Count() = 0
        m.status.text = Lang("homeRows", "noCatalogs")
    else
        m.status.text = ""
    end if
end sub

' Convert resolved manifests to exactly the same browsable-catalog set Home uses.
function CatalogRowsFromSources(sources as object) as object
    rows = []
    for each source in sources
        if source.catalogs = invalid or Type(source.catalogs) <> "roArray" then continue for
        address = source.address
        if address = invalid or address = "" then continue for
        addonName = source.name
        if addonName = invalid or addonName = "" then addonName = Lang("common", "unknown")

        for each catalog in source.catalogs
            if not HomeCatalogBrowsable(catalog) then continue for
            if CatalogAlreadyListed(rows, address, catalog.type, catalog.id) then continue for
            rows.Push({
                addonAddress: address
                addonName: addonName
                catalogId: catalog.id
                metaType: catalog.type
                title: m.stores.addons.callFunc("AddonsCatalogTitle", catalog, addonName)
            })
        end for
    end for
    return rows
end function

' A duplicate manifest entry with the same identity is one selectable Home row.
function CatalogAlreadyListed(rows as object, addonAddress as string, metaType as string, catalogId as string) as boolean
    for each row in rows
        if row.addonAddress = addonAddress and row.metaType = metaType and row.catalogId = catalogId then return true
    end for
    return false
end function

sub BuildRows()
    content = CreateObject("roSGNode", "ContentNode")
    for each row in m.rows
        entry = content.CreateChild("ContentNode")
        item = entry.CreateChild("HomeCatalogContent")
        item.title = CatalogRowTitle(row)
        item.description = RowDescription(row)
        item.visibleOnHome = IsCatalogVisible(row)
    end for
    m.list.focusRow = 0
    m.list.content = content
    UpdatePanel()
    if m.rows.Count() > 0 then m.list.callFunc("SetListFocus")
end sub

function CatalogRowTitle(row as object) as string
    return row.title + " · " + row.addonName
end function

function RowDescription(row as object) as string
    return VisibilityLabel(row)
end function

function IsCatalogVisible(row as object) as boolean
    if m.stores = invalid then return true
    return m.stores.settings.callFunc("SettingsIsHomeCatalogVisible", row.addonAddress, row.metaType, row.catalogId)
end function

sub onRowFocused()
    data = m.list.rowItemFocused
    if data = invalid or data.Count() < 1 then return
    m.focusedRow = data[0]
    UpdatePanel()
end sub

sub UpdatePanel()
    if m.focusedRow >= 0 and m.focusedRow < m.rows.Count()
        row = m.rows[m.focusedRow]
        m.panelTitle.text = row.title
        m.panelBody.text = Fill(Lang("homeRows", "panelProvider"), { addon: row.addonName })
        m.panelStatus.text = VisibilityLabel(row)
        m.panelStatus.color = VisibilityColor(row)
        return
    end if

    m.panelTitle.text = Lang("homeRows", "emptyTitle")
    m.panelStatus.text = ""
    if m.loading
        m.panelBody.text = Lang("homeRows", "loading")
    else if m.loadFailed
        m.panelBody.text = Lang("homeRows", "loadFailed")
    else if m.rows.Count() = 0
        m.panelBody.text = Lang("homeRows", "noCatalogs")
    else
        m.panelBody.text = Lang("homeRows", "selectHint")
    end if
end sub

function VisibilityLabel(row as object) as string
    if IsCatalogVisible(row) then return Lang("homeRows", "shown")
    return Lang("homeRows", "hidden")
end function

function VisibilityColor(row as object) as string
    palette = Theme()
    if IsCatalogVisible(row) then return palette.accent
    return palette.textSecondary
end function

sub onRowSelected()
    data = m.list.rowItemSelected
    if data = invalid or data.Count() < 1 then return
    index = data[0]
    if index < 0 or index >= m.rows.Count() or m.stores = invalid then return

    row = m.rows[index]
    visible = IsCatalogVisible(row)
    accepted = m.stores.settings.callFunc("SettingsSetHomeCatalogVisible", row.addonAddress, row.metaType, row.catalogId, not visible)
    if not accepted
        scene = m.top.getScene()
        if scene <> invalid then scene.callFunc("Notify", Lang("homeRows", "toggleFailed"), "error")
        return
    end if

    m.focusedRow = index
    contentRow = m.list.content.GetChild(index)
    if contentRow <> invalid and contentRow.GetChildCount() > 0
        item = contentRow.GetChild(0)
        item.description = RowDescription(row)
        item.visibleOnHome = not visible
    end if
    ReportSettingsSaveFault()
    UpdatePanel()
end sub

' A refused registry write lands as a Scene toast; the setting remains
' active for this session.
sub ReportSettingsSaveFault()
    if m.stores = invalid then return
    failed = m.stores.settings.callFunc("SettingsSaveFailed")
    scene = m.top.getScene()
    if scene <> invalid and failed then scene.callFunc("Notify", "settings could not be saved", "error")
end sub

sub CancelSources()
    if m.sourcesTask = invalid then return
    task = m.sourcesTask
    m.sourcesTask = invalid
    AsyncTask_Reap(task, m.top, true)
end sub
