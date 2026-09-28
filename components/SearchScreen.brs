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

    t = Theme()
    m.top.FindNode("searchTitle").color = t.accent
    m.top.FindNode("searchSub").color = t.textSecondary
    m.status.color = t.accent
    m.results.rowLabelTextColor = t.textSecondary
    m.results.rowLabelOffset = [0,10]
    m.results.focusBitmapBlendColor = t.accent

    m.results.ObserveField("rowItemSelected", "onResultSelected")

    m.lastQuery = ""
    m.rows = []
    m.searchTasks = invalid
    m.cinemetaAddress = ""
end sub

function OnEnter(params as object) as void
    if m.stores <> invalid
        addon = m.stores.addons.callFunc("AddonsGet", "com.linvo.cinemeta")
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

' The query prompt. Starts empty, so each search is a fresh prompt rather than an
' edit of the last one.
sub ShowSearchDialog()
    dialog = CreateObject("roSGNode", "StandardKeyboardDialog")
    ' Palette and the array-shaped message are the two things that differ from
    ' the legacy node. See the same block in SettingsScreen for why each one
    ' fails quietly rather than loudly.
    dialog.palette = AppPalette()
    dialog.title = "Search"
    dialog.message = ["Enter a movie or series title"]
    ' Starts empty. Each search is a fresh prompt rather than an edit of the last
    ' one, so there is no stale query sitting in the box inviting a re-run of
    ' what was searched before. m.lastQuery is still recorded below and is what
    ' the "no results" message names.
    dialog.text = ""
    dialog.buttons = ["Search", "Cancel"]
    dialog.observeField("buttonSelected", "onSearchChoice")
    ' Before the dialog is shown, and that ordering is load bearing. The edit
    ' box is built as soon as the node is created, so this is the earliest the
    ' voice setting can land and the dictation UI is not listening yet. It was
    ' an observer firing at registration that got there before; a direct call at
    ' this point in the sequence is the same moment without the extra field.
    ApplySearchKeyboard(dialog)
    m.top.getScene().dialog = dialog
end sub

' Configures the dialog's internal VoiceTextEditBox, which StandardKeyboardDialog
' builds for itself and which is therefore reached through the dialog rather than
' owned here. The box exists as soon as the node is created — confirmed on
' device, where it is already a roSGNode:VoiceTextEditBox before the dialog is
' ever displayed — so this is called inline and needs nothing to wait for.
'
' No try, deliberately. A throw here prints the offending field and line to the
' device console, and the console is where this is read. The previous version
' swallowed the error, which is how a caret fix that never took became
' indistinguishable from one that did.
sub ApplySearchKeyboard(dialog as object) as void
    if dialog = invalid then return
    editor = dialog.textEditBox
    if editor = invalid then return

    ' Full word input, and the reason voice stopped being letter-by-letter:
    ' DynamicKeyboard builds its internal edit box with voiceEntryType
    ' "alphanumeric", meant for street addresses, and that beats the node class
    ' default of "generic". The dialog's own keyboardDomain defaults to
    ' "generic" too but does not reach this field. VERIFIED WORKING on device.
    editor.voiceEntryType = "generic"
    ' Caret after the text rather than at 0. A caret parked at 0 makes backspace
    ' and the left arrow no-ops by definition while typing still appends, which
    ' from the outside is indistinguishable from a dead keyboard.
    editor.cursorPosition = Len(dialog.text)
end sub

sub onSearchChoice()
    dialog = m.top.getScene().dialog
    if dialog <> invalid
        index = dialog.buttonSelected
        query = dialog.text
        ' StandardDialog's own dismissal, and the one ConfirmExitDialog already
        ' uses: setting close makes the scene drop the node from the dialog slot
        ' by itself. Both values are read above before anything is torn down.
        dialog.close = true
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
        task = AsyncTask_Launch(m.top, "SearchLoaderTask", "onSearchLoaded", {
            addonAddress: m.cinemetaAddress
            query: query
            metaType: row.metaType
        }, "searchLoader" + row.metaType)
        m.searchTasks[row.metaType] = task
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
    AsyncTask_Reap(task, m.top, false)
    if result <> invalid and result.metas <> invalid and result.metas.Count() > 0
        row.metas = result.metas
        row.state = "loaded"
    else if result <> invalid and result.error <> invalid and result.error <> ""
        row.state = "error"
        row.message = result.error
    else
        row.state = "empty"
    end if

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
                if m.stores <> invalid then glyph = m.stores.library.callFunc("LibraryWatchedGlyph", meta.id, meta.type)
                entry.watchedGlyph = glyph
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
            if task <> invalid then AsyncTask_Reap(task, m.top, true)
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
