' HomeScreen — M1 focus spike and the stack bottom.
'
' The body is a single RowList: Roku owns the whole grid physics — vertical row
' scrolling/clipping (no row is ever stranded past the screen edge), horizontal
' per-row tile scrolling, row labels, focus reporting and non-focused-row
' dimming. Each row item is a PosterTile (see its interface fields). OK on a
' poster publishes one pushRequest; the Scene does the stack work.
'
' M3 replaces the placeholder rows with real catalog data; the list mechanics
' stay.
'
' Content is built lazily on first OnEnter, not in init(): init runs during
' CreateScene, before screen.Show(), and nodes created pre-Show can be dropped
' by the renderer. Building post-Show keeps every dynamic node on a live branch.

sub init()
    m.catalog = m.top.FindNode("catalog")
    m.catalog.ObserveField("rowItemSelected", "onRowItemSelected")
    m.rowsBuilt = false
    m.rowsData = [
        { title: "Continue Watching", names: ["Dune: Part Two", "Severance", "The Bear", "Shogun", "Silo", "Hacks", "True Detective", "Cunk on Earth"] }
        { title: "Because you watched Blade Runner", names: ["Ex Machina", "Arrival", "Her", "Oppenheimer", "The Creator", "Gattaca", "Moon", "Annihilation"] }
        { title: "Top Movies", names: ["Parasite", "Everything Everywhere", "Interstellar", "Whiplash", "Mad Max: Fury Road", "The Revenant", "Come and See", "Yi Yi"] }
    ]
end sub

' One content tree for the whole list: a child per row (its `title` becomes the
' row label) with one item child per poster. Item titles keep the
' "R{row}C{col}:{name}" form that PosterTile uses for its label.
sub BuildRows()
    content = CreateObject("roSGNode", "ContentNode")
    for r = 0 to m.rowsData.Count() - 1
        data = m.rowsData[r]
        row = content.CreateChild("ContentNode")
        row.title = data.title
        for c = 0 to 7
            item = row.CreateChild("ContentNode")
            item.title = "R" + r.ToStr() + "C" + c.ToStr() + ":" + data.names[c mod data.names.Count()]
        end for
    end for
    m.catalog.content = content
    m.rowsBuilt = true
end sub

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
    if row < 0 or index < 0 then return
    names = m.rowsData[row].names
    name = names[index mod names.Count()]
    m.top.pushRequest = {
        screen: "dummyDetail"
        params: {
            row: row
            index: index
            title: name
        }
    }
end sub