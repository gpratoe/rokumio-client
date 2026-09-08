' PlayerScreen — minimal video playback for a resolved stream URL.
'
' Plays the direct/HLS URL handed over by StreamsScreen, tracks position, and on
' Back (or exit) records where the user stopped through LibraryStore.SetPosition
' so Continue Watching / Resume can pick it up. Resume positions are stored in
' seconds and converted to/from the Video node's millisecond clock here.
'
' Params: { url, metaType, metaId, videoId, season, episode, position, name,
'           poster }.

sub init()
    m.video = m.top.FindNode("video")
    m.title = m.top.FindNode("playerTitle")
end sub

function SetStores(stores as object) as void
    m.stores = stores
end function

function OnEnter(params as object) as void
    if params = invalid or params.url = invalid then return
    m.playParams = params
    m.saved = false

    title = params.name
    if title = invalid then title = ""
    m.title.text = title

    m.video.enablePositionTracking = true
    m.video.contentUri = params.url
    if params.position <> invalid and params.position > 0
        m.video.position = params.position * 1000
    end if
    m.video.control = "play"
    m.top.SetFocus(true)
end function

' Back stops the video, records the position and lets the stack pop. OnExit also
' saves, guarded so the position is written once.
function OnBackPressed() as boolean
    m.video.control = "stop"
    SavePosition()
    return false
end function

function OnExit() as void
    SavePosition()
end function

sub BlurFocus()
end sub

sub SavePosition()
    if m.saved then return
    if m.playParams = invalid or m.playParams.videoId = invalid then return
    if m.stores = invalid or m.stores.library = invalid then return

    position = m.video.position
    duration = m.video.duration
    if position = invalid then position = 0
    if duration = invalid then duration = 0

    posSec = position \ 1000
    durSec = duration \ 1000
    m.stores.library.SetPosition(m.playParams.videoId, m.playParams.metaId, m.playParams.metaType, m.playParams.season, m.playParams.episode, m.playParams.name, m.playParams.poster, posSec, durSec)
    m.saved = true
end sub