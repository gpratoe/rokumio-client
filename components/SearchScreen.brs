' SearchScreen — Cinemeta title search, grouped by type.
'
' Entry shows a system KeyboardDialog (prefilled with the last query on
' re-search); OK kicks SearchLoaderTask off the render thread. Anything the
' add-on's "search" catalog returns for movie and series becomes two poster
' rows (empty groups are dropped; both empty reads as "No results"). OK on a
' result pushes DetailsScreen exactly like a Home catalog tile. The * (options)
' key reopens the keyboard for another query.

sub init()
    m.status = m.top.FindNode("searchStatus")
    m.results = m.top.FindNode("searchResults")

    m.results.ObserveField("rowItemSelected", "onResultSelected")

    m.lastQuery = ""
    m.rows = []
    m.loadTask = invalid
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

' Kick the query off the render thread against the Cinemeta search catalog.
sub RunSearch(query as string)
    if m.cinemetaAddress = "" or query = ""
        m.status.text = "Type something to search."
        return
    end if
    if m.loadTask <> invalid then return

    m.lastQuery = query
    m.status.text = "Searching…"
    m.results.content = CreateObject("roSGNode", "ContentNode")
    m.results.numRows = 0

    task = CreateObject("roSGNode", "SearchLoaderTask")
    task.id = "searchLoader"
    m.top.AppendChild(task)
    task.addonAddress = m.cinemetaAddress
    task.query = query
    task.observeField("result", "onSearchLoaded")
    m.loadTask = task
    task.control = "RUN"
end sub

' The search finished. A stale result that landed after CancelSearch is dropped
' by the m.loadTask guard.
sub onSearchLoaded()
    if m.loadTask = invalid then return
    task = m.loadTask
    m.loadTask = invalid
    result = task.result
    task.unobserveField("result")
    if task.getParent() <> invalid then m.top.RemoveChild(task)

    m.rows = []
    if result <> invalid
        if result.error <> invalid and result.error <> "" then m.status.text = "Search failed: " + result.error
        if result.movies <> invalid and result.movies.Count() > 0
            m.rows.Push({ title: "Movies", metaType: "movie", metas: result.movies })
        end if
        if result.series <> invalid and result.series.Count() > 0
            m.rows.Push({ title: "Series", metaType: "series", metas: result.series })
        end if
    end if

    if m.rows.Count() = 0
        m.status.text = "No results for " + Chr(34) + m.lastQuery + Chr(34) + "."
        m.results.content = CreateObject("roSGNode", "ContentNode")
        m.results.numRows = 0
        return
    end if

    content = CreateObject("roSGNode", "ContentNode")
    for each row in m.rows
        item = content.CreateChild("ContentNode")
        item.title = row.title
        for each meta in row.metas
            entry = item.CreateChild("ContentNode")
            name = meta.name
            if name = invalid then name = ""
            entry.title = name
            poster = meta.poster
            if poster <> invalid and poster <> "" then entry.hdPosterUrl = poster
        end for
    end for
    m.results.content = content
    m.results.numRows = m.rows.Count()
    m.results.jumpToRowItem = [0, 0]
    m.status.text = ""
    m.results.SetFocus(true)
end sub

sub CancelSearch()
    if m.loadTask <> invalid
        m.loadTask.unobserveField("result")
        m.loadTask.control = "STOP"
        if m.loadTask.getParent() <> invalid then m.top.RemoveChild(m.loadTask)
        m.loadTask = invalid
    end if
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