' DetailsScreen — one screen for both content kinds.
'
' Movies render a hero (poster, name, type/year/rating, description) plus a chip
' row (Play, and an "add to library" toggle backed by LibraryStore) and push a
' stream selection on Play. Series render the same hero, then a chip row: a
' Resume chip for the saved position (falling back to "Play S1E1" when nothing
' is saved) and an "Episodes" chip that pushes the dedicated EpisodesScreen.
'
' One shared chips RowList serves both kinds — the chips differ, the plumbing
' doesn't. Each chip ContentNode maps to a stored action id, and a single
' selection observer dispatches on that id.
'
' Params: { addonAddress, meta } for a hero rendered from the catalog/CW data
' immediately (no fetch needed; series browsing happens on EpisodesScreen),
' plus an optional resume hint { videoId, season, episode, position } from the
' Continue-Watching row. When no hint arrives, the local LibraryStore supplies
' the most recent position for the meta, so a catalog-opened show still offers
' to pick up where the user left off.

sub init()
    m.heroPoster = m.top.FindNode("heroPoster")
    m.bgPoster = m.top.FindNode("bgPoster")
    m.detailName = m.top.FindNode("detailName")
    m.detailType = m.top.FindNode("detailType")
    m.detailDesc = m.top.FindNode("detailDesc")
    m.chipsRow = m.top.FindNode("chipsRow")

    m.chipsRow.ObserveField("rowItemSelected", "onChipSelected")
end sub

' Stores are class instances, which cannot cross components through an interface
' field, so the Scene hands them over with callFunc instead.
function SetStores(stores as object) as void
    m.stores = stores
end function

function OnEnter(params as object) as void
    ' Re-entry after a push (EpisodesScreen, streams, …): params is invalid and
    ' the screen Group (not a focus target) was handed focus by the stack. The
    ' chip RowList must take it back, or nothing inside is reachable.
    if params = invalid
        RestoreFocus()
        return
    end if
    m.params = params
    if params.meta = invalid then return
    meta = params.meta
    m.addonAddress = params.addonAddress
    m.meta = meta

    ' Resume hint: the Continue-Watching row passes its own; otherwise the local
    ' library stands in (catalog-opened shows still know where you stopped).
    m.resume = params.resume
    if m.resume = invalid and m.stores <> invalid and m.stores.library <> invalid
        m.resume = m.stores.library.ResumeFor(meta.id)
    end if

    m.detailName.text = meta.name
    RenderKind(meta)
    poster = meta.poster
    if poster = invalid then poster = ""
    m.heroPoster.uri = poster

    ' Cinemeta catalog metas carry a `background` artwork URL; fill the screen
    ' behind everything. Missing background leaves the flat theme base showing.
    bg = meta.background
    if bg = invalid then bg = ""
    m.bgPoster.uri = bg

    desc = meta.description
    if desc <> invalid then m.detailDesc.text = desc else m.detailDesc.text = ""

    if meta.type = "series"
        ShowSeries()
    else
        ShowMovie()
    end if
end function

' Re-entry: the shared chip RowList just needs focus back. m.meta/m.resume
' survive the push/pop, so a rebuild is not needed.
sub RestoreFocus()
    if m.meta = invalid then return
    m.chipsRow.SetFocus(true)
end sub

' The second header line: "{type} · {releaseInfo} · ★ {imdbRating}", with the
' movie runtime appended when the meta carries it (Cinemeta does).
sub RenderKind(meta as object)
    kind = TypeLabel(meta.type)
    if meta.releaseInfo <> invalid and meta.releaseInfo <> "" then kind = kind + " · " + meta.releaseInfo
    if meta.imdbRating <> invalid and meta.imdbRating <> "" then kind = kind + " · ★ " + meta.imdbRating
    if meta.runtime <> invalid and meta.type <> "series"
        runtime = FormatRuntime(meta.runtime)
        if runtime <> "" then kind = kind + " · " + runtime
    end if
    m.detailType.text = kind
end sub

' Runtime echoed straight from the meta JSON — Cinemeta ships plain minutes, so
' no parsing and no "2h 5m" conversion. Per-component function scope: duplicated
' from StreamsScreen, since Roku does not share globals across components.
function FormatRuntime(runtime as dynamic) as string
    if runtime = invalid then return ""
    return runtime.ToStr().Trim()
end function

' Series chips: Resume for the saved spot when there is one, otherwise a "Play
' S1E1" stand-in (no fetch happens on this screen; EpisodesScreen browses the
' real list), then "Episodes".
sub ShowSeries()
    actions = []
    if m.resume <> invalid and m.resume.season <> invalid and m.resume.episode <> invalid
        actions.Push({ action: "resume", title: "Resume S" + m.resume.season.ToStr() + "E" + m.resume.episode.ToStr() })
    else
        actions.Push({ action: "play", title: "Play S1E1" })
    end if
    actions.Push({ action: "episodes", title: "Episodes" })
    ShowChips(actions)
end sub

sub ShowMovie()
    actions = []
    actions.Push({ action: "play", title: "Play" })
    actions.Push({ action: "library", title: LibraryActionLabel() })
    ShowChips(actions)
end sub

' Fill the shared chips row and remember the action id per chip so the single
' selection observer can dispatch.
sub ShowChips(actions as object)
    m.chips = actions
    root = CreateObject("roSGNode", "ContentNode")
    row = root.CreateChild("ContentNode")
    for each chip in actions
        item = row.CreateChild("ContentNode")
        item.title = chip.title
    end for
    m.chipsRow.content = root
    m.chipsRow.jumpToRowItem = [0, 0]
    m.chipsRow.SetFocus(true)
end sub

sub onChipSelected()
    data = m.chipsRow.rowItemSelected
    if data = invalid or data.Count() < 2 then return
    index = data[1]
    if m.chips = invalid or index < 0 or index >= m.chips.Count() then return
    action = m.chips[index].action
    if action = "resume"
        ResumeEpisode()
    else if action = "play"
        PlayMedia()
    else if action = "episodes"
        OpenEpisodes()
    else if action = "library"
        ToggleLibrary()
    end if
end sub

' Resume sends the user into stream selection for the saved episode. The Streams
' screen is the picker; this push carries the full context for it.
sub ResumeEpisode()
    if m.resume = invalid or m.stores = invalid then return
    videoId = m.stores.episodes.ResolveVideoId(m.meta.id, m.resume.season, m.resume.episode)
    m.top.pushRequest = {
        screen: "streamsScreen"
        params: {
            addonAddress: m.addonAddress
            metaType: "series"
            metaId: m.meta.id
            videoId: videoId
            season: m.resume.season
            episode: m.resume.episode
            position: ResumePosition()
            name: m.meta.name
            poster: m.meta.poster
            logo: m.meta.logo
        }
    }
end sub

' The generic Play action: for a movie it is the only play path; for a series it
' covers the no-resume "Play S1E1" fallback. Both push stream selection.
sub PlayMedia()
    if m.stores = invalid then return
    if m.meta.type = "series"
        m.top.pushRequest = {
            screen: "streamsScreen"
            params: {
                addonAddress: m.addonAddress
                metaType: "series"
                metaId: m.meta.id
                videoId: m.stores.episodes.ResolveVideoId(m.meta.id, 1, 1)
                season: 1
                episode: 1
                position: ResumePosition()
            name: m.meta.name
            poster: m.meta.poster
            logo: m.meta.logo
            }
        }
    else
        m.top.pushRequest = {
            screen: "streamsScreen"
            params: {
                addonAddress: m.addonAddress
                metaType: "movie"
                metaId: m.meta.id
                videoId: m.meta.id
                position: ResumePosition()
                name: m.meta.name
                poster: m.meta.poster
                logo: m.meta.logo
            }
        }
    end if
end sub

sub OpenEpisodes()
    m.top.pushRequest = {
        screen: "episodesScreen"
        params: {
            addonAddress: m.addonAddress
            meta: { id: m.meta.id, type: m.meta.type, name: m.meta.name, poster: m.meta.poster, background: m.meta.background, logo: m.meta.logo }
            resume: m.resume
        }
    }
end sub

' Keep an accurate resume for the current meta: the saved position when the user
' came back from a spot, else zero (a brand-new start).
function ResumePosition() as integer
    if m.resume <> invalid and m.resume.position <> invalid then return m.resume.position
    return 0
end function

sub ToggleLibrary()
    if m.stores = invalid then return
    if m.stores.library.IsSaved(m.meta.id)
        m.stores.library.RemoveSaved(m.meta.id)
    else
        m.stores.library.AddSaved(m.meta.id, m.meta.type, m.meta.name, m.meta.poster, m.meta.logo)
    end if
    label = LibraryActionLabel()
    for i = 0 to m.chips.Count() - 1
        if m.chips[i].action = "library"
            if m.chipsRow.content <> invalid and m.chipsRow.content.GetChildCount() > 0
                row = m.chipsRow.content.GetChild(0)
                if row <> invalid and i < row.GetChildCount() then row.GetChild(i).title = label
            end if
            exit for
        end if
    end for
end sub

function LibraryActionLabel() as string
    if m.stores <> invalid and m.stores.library.IsSaved(m.meta.id) then return "In library"
    return "Add to library"
end function

function TypeLabel(metaType as string) as string
    if metaType = "movie" then return "Movie"
    if metaType = "series" then return "Series"
    return metaType
end function

function OnExit() as void
end function

function OnBackPressed() as boolean
    return false
end function

sub BlurFocus()
end sub