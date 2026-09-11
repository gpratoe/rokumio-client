' HomeScreen — the stack bottom: continue watching first, then catalog rows.
'
' The body is a single RowList: Roku owns the whole grid physics — vertical row
' scrolling/clipping (no row is ever stranded past the screen edge), horizontal
' per-row tile scrolling, row labels, focus reporting and non-focused-row
' dimming. Each row item is a PosterTile (see its interface fields). OK on a
' poster publishes one pushRequest; the Scene does the stack work.
'
' Rows are served by the addon stores: each addon's manifest is resolved on
' demand, then every advertisable catalog is fetched and rendered as a row. On
' top sits a Continue Watching row built from the (local) LibraryStore whenever
' the user has entries — guests included, since that state is local. Rows that
' fail to load are skipped; on total failure the grid stays empty so a break in
' the fetch pipeline is unambiguous.
'
' Content is built lazily on first OnEnter, not in init(): init runs during
' CreateScene, before screen.Show(), and nodes created pre-Show can be dropped
' by the renderer. The catalog rows are fetched once and the grid is assembled
' exactly once; later visits either leave the tree alone (nothing changed) or
' refresh only the Continue Watching row in place (progress was made elsewhere).
' The RowList's own scroll + focus therefore survive every trip away and back.

sub init()
    m.catalog = m.top.FindNode("catalog")
    m.catalog.ObserveField("rowItemSelected", "onRowItemSelected")
    m.rail = m.top.FindNode("rail")
    m.rail.ObserveField("rowItemSelected", "onRailItemSelected")
    m.catalogRowsBuilt = false
    m.catalogRows = []
    m.gridRows = []
    m.gridBuilt = false
    m.cwSignature = ""
    m.railBuilt = false
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

' Fetch every advertisable catalog once. The result is the catalog-rows gallery
' the visible grid re-renders from; network only happens on first entry.
sub BuildCatalogRows()
    for each catalog in ResolveCatalogs()
        response = m.stores.catalog.Catalog(catalog.addonAddress, catalog.type, catalog.catalogId)
        if response.ok and response.metas <> invalid and response.metas.Count() > 0
            m.catalogRows.Push({
                addonAddress: catalog.addonAddress
                title: catalog.name
                metaType: catalog.type
                metas: response.metas
            })
        end if
    end for
    m.catalogRowsBuilt = true
end sub

' Assemble the visible grid once: Continue Watching (when the local library has
' entries) first, then the catalog rows. The content tree is set exactly once;
' later visits refresh only the live Continue Watching row in place (see
' RefreshContinueWatching) so the rest of the grid keeps the RowList's own
' scroll + focus.
sub BuildRows()
    m.gridRows = []
    cw = LibraryRow()
    if cw <> invalid then m.gridRows.Push(cw)
    for each row in m.catalogRows
        m.gridRows.Push(row)
    end for

    counts = {}
    for each row in m.gridRows
        count = counts[row.title]
        if count = invalid then count = 0
        counts[row.title] = count + 1
    end for

    content = CreateObject("roSGNode", "ContentNode")
    for r = 0 to m.gridRows.Count() - 1
        content.AppendChild(MakeRowNode(m.gridRows[r], counts))
    end for
    m.catalog.content = content
    if m.gridRows.Count() > 0 then m.catalog.numRows = m.gridRows.Count()
end sub

' Build the ContentNode for one grid row: a titled group of poster children.
' counts carries the merged name histogram so duplicated catalog labels get
' their type suffix (it is invalid for rows outside the first assembly, e.g. a
' freshly inserted Continue Watching row — the label is unique anyway).
function MakeRowNode(row as object, counts = invalid as object) as object
    node = CreateObject("roSGNode", "ContentNode")
    label = row.title
    if counts <> invalid and counts[label] > 1 then label = label + " " + TypeLabel(row.metaType)
    node.title = label
    for each meta in row.metas
        item = node.CreateChild("ContentNode")
        name = meta.name
        if name = invalid then name = ""
        item.title = name
        poster = meta.poster
        if poster <> invalid and poster <> "" then item.hdPosterUrl = poster
    end for
    return node
end function

' The top row when the user has watched something: one tile per local
' continue-watching entry, carrying its resume hint so Details can reopen on
' the right spot. Items are synthesized catalog metas.
function LibraryRow() as dynamic
    if m.stores = invalid or m.stores.library = invalid then return invalid
    entries = m.stores.library.ContinueWatching()
    if entries = invalid or entries.Count() = 0 then return invalid
    metas = []
    for each entry in entries
        metas.Push({
            id: entry.metaId
            type: entry.metaType
            name: entry.name
            poster: entry.poster
            videoId: entry.videoId
            season: entry.season
            episode: entry.episode
            position: entry.position
        })
    end for
    return { source: "library", title: "Continue Watching", metaType: "", metas: metas }
end function

function ContinueWatchingSignature() as string
    if m.stores = invalid or m.stores.library = invalid then return ""
    entries = m.stores.library.ContinueWatching()
    if entries = invalid or entries.Count() = 0 then return ""
    parts = []
    for each entry in entries
        parts.Push(entry.metaId + "|" + entry.videoId + "|" + entry.season.toStr() + "|" + entry.episode.toStr() + "|" + entry.position.toStr())
    end for
    parts.Sort("i")
    return parts.Join(";")
end function

' Live-update the Continue Watching row after progress was made elsewhere,
' without touching the rest of the grid. The catalog rows' nodes stay bit-for-bit
' intact, so the RowList's own scroll + focus survive the visit; only the top
' row's posters/titles change. A row appearing (first watch) or disappearing
' (history cleared) is handled by inserting/removing precisely that one row —
' which may clamp focus to the top, an acceptable reset confined to those rare
' transitions.
sub RefreshContinueWatching()
    if m.catalog.content = invalid then return
    content = m.catalog.content
    haveCw = m.gridRows.Count() > 0 and m.gridRows[0].source = "library"
    live = LibraryRow()
    if live <> invalid
        if haveCw
            SyncContinueWatchingRow(content.GetChild(0), live.metas)
            m.gridRows[0] = live
        else
            content.InsertChild(MakeRowNode(live, invalid), 0)
            m.gridRows.Insert(0, live)
            m.catalog.numRows = m.gridRows.Count()
        end if
    else if haveCw
        content.RemoveChildIndex(0)
        m.gridRows.Delete(0)
        m.catalog.numRows = m.gridRows.Count()
    end if
end sub

' Refresh a row node's poster children to match a fresh meta list, reusing the
' existing child nodes by index so the RowList sees no structural change in the
' common case: no flicker, and focus holds even when entries reorder (a watched
' title rises to the front). Surplus children are trimmed from the tail.
sub SyncContinueWatchingRow(node as object, metas as object)
    existing = node.getChildCount()
    for c = 0 to metas.Count() - 1
        item = invalid
        if c < existing
            item = node.GetChild(c)
        else
            item = node.CreateChild("ContentNode")
        end if
        name = metas[c].name
        if name = invalid then name = ""
        item.title = name
        poster = metas[c].poster
        if poster <> invalid and poster <> "" then item.hdPosterUrl = poster else item.hdPosterUrl = invalid
    end for
    while node.getChildCount() > metas.Count()
        node.RemoveChildIndex(node.getChildCount() - 1)
    end while
end sub

' Where the meta for a library-sourced tile comes from. The library records no
' addon origin, so the Cinemeta built-in (the meta authority) is the default.
function MetaAddress() as string
    if m.stores = invalid or m.stores.addons = invalid then return ""
    addon = m.stores.addons.Get("com.linvo.cinemeta")
    if addon = invalid then return ""
    return addon.address
end function

' Row-label suffix for duplicated catalog names.
function TypeLabel(metaType as string) as string
    if metaType = "movie" then return "Movies"
    if metaType = "series" then return "Series"
    return metaType
end function

function OnEnter(params as object) as void
    if not m.railBuilt then BuildRail()
    if not m.catalogRowsBuilt then BuildCatalogRows()
    sig = ContinueWatchingSignature()
    if not m.gridBuilt
        BuildRows()
        m.gridBuilt = true
    else if sig <> m.cwSignature
        RefreshContinueWatching()
    end if
    m.cwSignature = sig
    m.catalog.SetFocus(true)
end function

function OnExit() as void
end function

function OnBackPressed() as boolean
    return false
end function

' Remember where the grid sits when another screen takes focus. ScreenStack
' calls BlurFocus on every push; nothing needs saving because the content tree
' is never replaced after first entry, so the RowList keeps its own scroll +
' focus across every trip away and back.
sub BlurFocus()
end sub

' The left rail: a fixed one-column icon menu. Built once (nodes created in init
' can be dropped pre-Show, so it happens on first OnEnter like the catalog).
sub BuildRail()
    entries = [
        { glyph: "pkg:/images/discover.png", screen: "discoverScreen" }
        { glyph: "pkg:/images/search.png", screen: "searchScreen" }
        { glyph: "pkg:/images/settings.png", screen: "settingsScreen" }
        { glyph: "pkg:/images/puzzle.png", screen: "addonsScreen" }
    ]
    m.railEntries = entries
    content = CreateObject("roSGNode", "ContentNode")
    for each entry in entries
        row = content.CreateChild("ContentNode")
        item = row.CreateChild("ContentNode")
        item.title = entry.glyph
    end for
    m.rail.content = content
    m.rail.numRows = entries.Count()
    m.railBuilt = true
end sub

' OK on a rail icon: an action request the Scene pushes as a stack screen.
sub onRailItemSelected()
    data = m.rail.rowItemSelected
    if data = invalid or data.Count() < 2 then return
    row = data[0]
    if row < 0 or m.railEntries = invalid or row >= m.railEntries.Count() then return
    m.top.pushRequest = {
        screen: m.railEntries[row].screen
        params: {}
    }
end sub

' Cross-focus between the rail and the catalog grid. Left from the grid enters
' the rail; Right from the rail enters the grid. Whether a RowList at its left
' edge lets Left bubble here is device-dependent — if the grid swallows it, the
' fallback is starting Home focus on the rail. Verify on-device.
function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "right" and m.rail.HasFocus()
        m.catalog.SetFocus(true)
        return true
    else if key = "left" and m.catalog.HasFocus()
        m.rail.SetFocus(true)
        return true
    end if
    return false
end function

' rowItemSelected is a field observer, so this receives the roSGNodeEvent. Its
' data is a [row, itemIndex] pair; the selected name comes from the row's own
' data (the tiles only know their parsed label). A catalog tile opens Details
' for its meta. A Continue-Watching tile adds the resume hint and, like any
' other tile, fetches its full meta from the Cinemeta built-in by id first (the
' local record stores only what the Home row shows — id, name, poster, resume)
' so Details renders the same full hero as a catalog-opened title. On fetch
' failure the slim record falls back, so the row still opens.
sub onRowItemSelected(event as object)
    data = event.GetData()
    if data = invalid or data.Count() < 2 then return
    row = data[0]
    index = data[1]
    if row < 0 or index < 0 or m.stores = invalid then return
    if row >= m.gridRows.Count() then return
    metas = m.gridRows[row].metas
    if index >= metas.Count() then return

    item = metas[index]
    if m.gridRows[row].source = "library"
        meta = {
            id: item.id
            type: item.type
            name: item.name
            poster: item.poster
        }
        answer = m.stores.episodes.GetMeta(MetaAddress(), item.type, item.id)
        if answer.ok and answer.meta <> invalid then meta = answer.meta
        m.top.pushRequest = {
            screen: "detailsScreen"
            params: {
                addonAddress: MetaAddress()
                meta: meta
                resume: {
                    videoId: item.videoId
                    season: item.season
                    episode: item.episode
                    position: item.position
                }
            }
        }
    else
        m.top.pushRequest = {
            screen: "detailsScreen"
            params: {
                addonAddress: m.gridRows[row].addonAddress
                meta: item
            }
        }
    end if
end sub
