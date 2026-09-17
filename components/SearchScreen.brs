' SearchScreen — Cinemeta title search, grouped by type.
'
' Entry shows a system KeyboardDialog (prefilled with the last query on
' re-search); OK kicks one SearchLoaderTask per type off the render thread, so
' movie and series search in parallel. Both rows are rendered immediately, each
' holding a placeholder tile whose own spinner marks it; as a type resolves its
' row fills with posters, or the placeholder swaps to "No X found." / "Search
' failed: …". Empty-looking groups are never dropped — the row itself says so.
' OK on a result pushes DetailsScreen exactly like a Home catalog tile. The *
' (options) key reopens the keyboard for another query.

sub init()
    m.status = m.top.FindNode("searchStatus")
    m.results = m.top.FindNode("searchResults")

    m.results.ObserveField("rowItemSelected", "onResultSelected")

    m.lastQuery = ""
    m.rows = []
    m.searchTasks = invalid
    m.cinemetaAddress = ""
end sub

' Stores are class instances, which cannot cross components through an interface
' field, so the Scene hands them over with callFunc instead.
function SetStores(stores as object) as void
    m.stores = stores
end function

function OnEnter(params as object) as void
    if m.stores <> invalid and m.stores.addons <> invalid
        addon = m.stores.addons.Get("com.linvo.cinemeta")
        if addon <> invalid then m.cinemetaAddress = addon.address
    end if

    ' A caller-supplied query (future rail-injected) runs immediately.
    if params <> invalid and params.query <> invalid and params.query <> ""
        RunSearch(params.query)
        return
    end if

    ' Re-entry after Details: results are still here, just take focus back.
    if m.rows.Count() > 0
        m.results.SetFocus(true)
        return
    end if

    ShowSearchDialog()
end function

function OnExit() as void
    CancelSearch()
end function

function OnBackPressed() as boolean
    return false
end function

sub BlurFocus()
end sub

' The query prompt. Prefilled with the last query so a re-search is an edit.
sub ShowSearchDialog()
    dialog = CreateObject("roSGNode", "KeyboardDialog")
    dialog.title = "Search"
    dialog.message = "Enter a movie or series title"
    dialog.text = m.lastQuery
    dialog.buttons = ["Search", "Cancel"]
    dialog.observeField("buttonSelected", "onSearchChoice")
    m.top.getScene().dialog = dialog
end sub

sub onSearchChoice()
    dialog = m.top.getScene().dialog
    if dialog <> invalid
        index = dialog.buttonSelected
        query = dialog.text
        m.top.getScene().dialog = invalid
        if index = 0
            RunSearch(query.Trim())
        else if m.rows.Count() > 0
            m.results.SetFocus(true)
        end if
    end if
end sub

' Kick the query off the render thread against the Cinemeta search catalog. One
' SearchLoaderTask per type runs in parallel; both rows render immediately (a
' spinner inside each placeholder tile marks its loading state) and the grid
' takes focus so the user can already move between rows while they load.
sub RunSearch(query as string)
    if m.cinemetaAddress = "" or query = ""
        m.status.text = "Type something to search."
        return
    end if

    CancelSearch()
    m.lastQuery = query
    m.status.text = "Searching…"

    m.rows = [
        { title: "Movies", metaType: "movie", metas: [], state: "loading", message: "" }
        { title: "Series", metaType: "series", metas: [], state: "loading", message: "" }
    ]
    m.searchTasks = {}
    RenderRows()

    m.results.jumpToRowItem = [0, 0]
    m.results.SetFocus(true)

    for each row in m.rows
        task = CreateObject("roSGNode", "SearchLoaderTask")
        task.id = "searchLoader" + row.metaType
        m.top.AppendChild(task)
        task.addonAddress = m.cinemetaAddress
        task.query = query
        task.metaType = row.metaType
        task.observeField("result", "onSearchLoaded")
        m.searchTasks[row.metaType] = task
        task.control = "RUN"
    end for
end sub

' One type's search landed (or failed). The task reports which type via its
' metaType; the two searches are independent, so this can arrive in any order.
' A stale result that landed after CancelSearch is dropped by the slot guard —
' the whole map is invalid (cancel), or the slot was cleared (already applied).
' Only that type's row re-renders; the other keeps its spinner.
sub onSearchLoaded(event as object)
    if m.searchTasks = invalid then return
    task = event.GetRoSGNode()
    if task = invalid then return
    kind = task.metaType
    if kind = invalid or kind = "" then return
    slot = m.searchTasks[kind]
    if slot = invalid then return
    m.searchTasks[kind] = invalid

    row = RowForType(kind)
    if row = invalid then return

    result = task.result
    if result <> invalid and result.metas <> invalid and result.metas.Count() > 0
        row.metas = result.metas
        row.state = "loaded"
    else if result <> invalid and result.error <> invalid and result.error <> ""
        row.state = "error"
        row.message = result.error
    else
        row.state = "empty"
    end if

    task.unobserveField("result")
    if task.getParent() <> invalid then m.top.RemoveChild(task)

    RenderRows()
    UpdateSearchStatus()
end sub

function RowForType(metaType as string) as dynamic
    for each row in m.rows
        if row.metaType = metaType then return row
    end for
    return invalid
end function

' Rebuild the whole grid from m.rows. Each row always exists: a loaded row gets
' its poster tiles, a loading/empty/error row a single placeholder tile whose
' text states what's going on. The loading state is carried to the tile through
' a loadState field, so PosterTile spins its own BusySpinner — the indicator is
' part of the row item, not a floating overlay.
sub RenderRows()
    content = CreateObject("roSGNode", "ContentNode")
    for each row in m.rows
        rowNode = content.CreateChild("ContentNode")
        rowNode.title = row.title
        if row.state = "loaded"
            for each meta in row.metas
                entry = rowNode.CreateChild("TileContent")
                name = meta.name
                if name = invalid then name = ""
                entry.title = name
                poster = meta.poster
                if poster <> invalid and poster <> "" then entry.hdPosterUrl = poster
                glyph = ""
                if m.stores <> invalid and m.stores.library <> invalid then glyph = m.stores.library.WatchedGlyph(meta.id, meta.type)
                if glyph <> "" then entry.watchedGlyph = glyph
            end for
        else
            entry = rowNode.CreateChild("TileContent")
            entry.title = PlaceholderTitle(row)
            entry.addFields({ loadState: row.state })
        end if
    end for
    m.results.content = content
    m.results.numRows = m.rows.Count()
end sub

' The placeholder tile's text: nothing while loading (the spinner says that),
' a "No X found." line for a clean empty result, or the failure for an error.
function PlaceholderTitle(row as object) as string
    if row.state = "empty"
        return "No " + row.title + " found for " + Chr(34) + m.lastQuery + Chr(34) + "."
    else if row.state = "error"
        return "Search failed: " + row.message
    end if
    return ""
end function

' The status line: "Searching…" while any type is still resolving, clears when
' both settle (per-row placeholders carry each group's outcome).
sub UpdateSearchStatus()
    if m.searchTasks = invalid then return
    pending = 0
    for each key in m.searchTasks
        if m.searchTasks[key] <> invalid then pending = pending + 1
    end for
    if pending > 0
        m.status.text = "Searching…"
    else
        m.status.text = ""
    end if
end sub

sub CancelSearch()
    if m.searchTasks <> invalid
        for each key in m.searchTasks
            task = m.searchTasks[key]
            if task <> invalid
                task.unobserveField("result")
                task.control = "STOP"
                if task.getParent() <> invalid then m.top.RemoveChild(task)
            end if
        end for
    end if
    m.searchTasks = invalid
end sub

' A result opens DetailsScreen through the same one-action channel Home uses for
' a catalog tile: full meta + the Cinemeta address.
sub onResultSelected()
    data = m.results.rowItemSelected
    if data = invalid or data.Count() < 2 then return
    row = data[0]
    index = data[1]
    if row < 0 or index < 0 then return
    if row >= m.rows.Count() then return
    metas = m.rows[row].metas
    if index >= metas.Count() then return
    m.top.pushRequest = {
        screen: "detailsScreen"
        params: {
            addonAddress: m.cinemetaAddress
            meta: metas[index]
        }
    }
end sub

' The * (options) button reopens the query prompt, prefilled. Everything else
' falls through to the stack (Back pops, arrows move inside the results list).
function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if key = "options"
        ShowSearchDialog()
        return true
    end if
    return false
end function
