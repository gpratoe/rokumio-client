' HomeScreen — M1 focus spike and the stack bottom.
'
' The body is a single RowList: Roku owns the whole grid physics — vertical row
' scrolling/clipping (no row is ever stranded past the screen edge), horizontal
' per-row tile scrolling, row labels, focus reporting and non-focused-row
' dimming. Each row item is a PosterTile (see its interface fields). OK on a
' poster publishes one pushRequest; the Scene does the stack work.
'
' Rows are served by the addon stores: each addon's manifest is resolved on
' demand, then every advertised catalog is fetched and rendered as a row. Rows
' that fail to load are skipped; on total failure the grid stays empty so a
' break in the fetch pipeline is unambiguous.
'
' Content is built lazily on first OnEnter, not in init(): init runs during
' CreateScene, before screen.Show(), and nodes created pre-Show can be dropped
' by the renderer. Building post-Show keeps every dynamic node on a live branch.

sub init()
    m.catalog = m.top.FindNode("catalog")
    m.catalog.ObserveField("rowItemSelected", "onRowItemSelected")
    m.rowsBuilt = false
    m.rows = []
end sub

' Stores are class instances, which cannot cross components through an interface
' field, so the Scene hands them over with callFunc instead.
function SetStores(stores as object) as void
    m.stores = stores
end function

' Collect {addonAddress, type, catalogId, name} for every advertisable catalog.
' Built-ins carry catalogs = invalid until their manifest is fetched, so the
' manifest is resolved here on demand; addons serving no catalogs (e.g.
' OpenSubtitles v3) contribute nothing.
'
' Catalogs whose required extras we cannot supply are skipped: a plain browse
' only sends skip=0, so rows that need a library (Cinemeta's last-videos,
' calendar-videos) or a chosen genre (year/"New") stay off the Home grid — the
' same rows Stremio itself omits for a guest.
function ResolveCatalogs() as object
    catalogs = []
    for each addon in m.stores.addons.GetAll()
        list = addon.catalogs
        if list = invalid or Type(list) <> "roArray"
            result = m.stores.catalog.Manifest(addon.address)
            if result.ok and result.manifest.catalogs <> invalid then list = result.manifest.catalogs
        end if
        if list <> invalid and Type(list) = "roArray"
            for each catalog in list
                if CatalogBrowsable(catalog)
                    catalogs.Push({
                        addonAddress: addon.address
                        type: catalog.type
                        catalogId: catalog.id
                        name: catalog.name
                    })
                end if
            end for
        end if
    end for
    return catalogs
end function

' A catalog is browsable when none of its required extras demand more than the
' plain skip=0 browse supplies.
function CatalogBrowsable(catalog as object) as boolean
    required = catalog.extraRequired
    if required <> invalid and Type(required) = "roArray"
        for each name in required
            if name <> "skip" then return false
        end for
    end if
    extras = catalog.extra
    if extras <> invalid and Type(extras) = "roArray"
        for each extra in extras
            if extra.isRequired = true and extra.name <> "skip" then return false
        end for
    end if
    return true
end function

' One content tree for the whole list: a child per row (its `title` becomes the
' row label) with one item child per poster. Items carry the artwork through
' hdPosterUrl (mapped from the addon meta's poster field). Catalog names repeat
' across meta types ("Popular" for both movies and series), so a name that
' occurs more than once is disambiguated with its type label.
sub BuildRows()
    for each catalog in ResolveCatalogs()
        response = m.stores.catalog.Catalog(catalog.addonAddress, catalog.type, catalog.catalogId)
        if response.ok and response.metas <> invalid and response.metas.Count() > 0
            m.rows.Push({ title: catalog.name, metaType: catalog.type, metas: response.metas })
        end if
    end for

    counts = {}
    for each row in m.rows
        count = counts[row.title]
        if count = invalid then count = 0
        counts[row.title] = count + 1
    end for

    content = CreateObject("roSGNode", "ContentNode")
    for r = 0 to m.rows.Count() - 1
        row = content.CreateChild("ContentNode")
        label = m.rows[r].title
        if counts[label] > 1 then label = label + " " + TypeLabel(m.rows[r].metaType)
        row.title = label
        metas = m.rows[r].metas
        for c = 0 to metas.Count() - 1
            item = row.CreateChild("ContentNode")
            name = metas[c].name
            if name = invalid then name = ""
            item.title = name
            poster = metas[c].poster
            if poster <> invalid and poster <> "" then item.hdPosterUrl = poster
        end for
    end for
    m.catalog.content = content
    if m.rows.Count() > 0 then m.catalog.numRows = m.rows.Count()
    m.rowsBuilt = true
end sub

' Row-label suffix for duplicated catalog names.
function TypeLabel(metaType as string) as string
    if metaType = "movie" then return "Movies"
    if metaType = "series" then return "Series"
    return metaType
end function

function OnEnter(params as object) as void
    if not m.rowsBuilt then BuildRows()
    m.catalog.SetFocus(true)
end function

function OnExit() as void
end function

function OnBackPressed() as boolean
    return false
end function

sub BlurFocus()
end sub

' rowItemSelected is a field observer, so this receives the roSGNodeEvent. Its
' data is a [row, itemIndex] pair; the selected name comes from the row's own
' data (the tiles only know their parsed label).
sub onRowItemSelected(event as object)
    data = event.GetData()
    if data = invalid or data.Count() < 2 then return
    row = data[0]
    index = data[1]
    if row < 0 or index < 0 or m.stores = invalid then return
    if row >= m.rows.Count() then return
    metas = m.rows[row].metas
    if index >= metas.Count() then return
    m.top.pushRequest = {
        screen: "dummyDetail"
        params: {
            row: row
            index: index
            title: metas[index].name
        }
    }
end sub