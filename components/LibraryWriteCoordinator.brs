' LibraryWriteCoordinator — the one serialized account-library write path.
'
' The player position, watched marks, and add/remove membership edits all
' resolve, commit to the local account cache, and push through this one pump.
' The three edits share the dangerous part: a build reads and updates the same
' cached library item, and two simultaneous writes can each clone a stale copy
' and have the later one undo the earlier. One worker at a time is the
' invariant; this component owns its pending slots, timer, worker, and result
' lifecycle together.
'
' MainScene still owns screen observation and hands the resulting plain data
' here. The StoreHost crosses the component boundary as a node reference, never
' as a store instance.

sub init()
    m.storeHost = invalid
    m.watchStatePump = m.top.FindNode("watchStatePump")
    m.watchStatePump.ObserveField("fire", "onWatchStatePumpFire")

    ' Initialize every slot and guard before an event can read it. On device,
    ' testing an unassigned invalid value as a boolean throws &h18 on the
    ' render thread; the interpreter does not catch that class of mistake.
    m.pushing = false
    m.task = invalid
    m.inFlight = invalid
    m.lastPacketKey = ""
    m.pendingWatchState = invalid
    m.pendingWatchedChange = invalid
    m.pendingLibraryChange = invalid
end sub

' MainScene constructs the one StoreHost and hands its node over once. Never
' pass a store class instance here: Roku would copy it and strip its methods.
sub SetStoreHost(host as object)
    m.storeHost = host
end sub

' The player's Video state observer reports through MainScene. Only accept
' account-session updates, read the packet from the StoreHost-owned buffer,
' ignore an identical position, then defer the write by one timer tick. No
' task node is created on the Video observer's transition stack.
sub OnWatchStateUpdate()
    if m.storeHost = invalid then return
    if m.storeHost.callFunc("AuthGetSession") <> "stremio" then return
    packet = m.storeHost.callFunc("WatchLatest")
    if packet = invalid then return
    videoId = packet.videoId
    if videoId = invalid or videoId = "" then return
    if packet.position = invalid then return
    key = videoId + "|" + packet.position.ToStr()
    if m.lastPacketKey = key then return
    m.lastPacketKey = key
    m.pendingWatchState = packet
    ScheduleWatchStatePush()
end sub

' Details' add/remove toggle: retain only the newest pending membership change.
sub OnLibraryChange(change as dynamic)
    if m.storeHost = invalid then return
    if m.storeHost.callFunc("AuthGetSession") <> "stremio" then return
    if change = invalid then return
    m.pendingLibraryChange = change
    Pump()
end sub

' Episodes' watched/unwatched edit. The packet carries the ordered episode-id
' list and series identity so the store can author the complete account
' bitfield, including a series the account has never seen.
sub OnWatchedChange(change as dynamic)
    if m.storeHost = invalid then return
    if m.storeHost.callFunc("AuthGetSession") <> "stremio" then return
    if change = invalid then return
    m.pendingWatchedChange = change
    Pump()
end sub

' A watch-state change must leave the Video observer before creating a Task
' node: the event arrives during an OS playback transition, and appending a
' node there froze playback on device. The one-shot timer coalesces a burst of
' position reports into one launch.
sub ScheduleWatchStatePush()
    if m.watchStatePump = invalid
        ' A missing timer is a wiring defect, not a reason to drop the user's
        ' state. Keep the existing fallback; the contract test pins the timer
        ' so this is unreachable in a correctly wired component.
        Pump()
        return
    end if
    m.watchStatePump.control = "stop"
    m.watchStatePump.control = "start"
end sub

sub onWatchStatePumpFire()
    Pump()
end sub

' Drain one edit at a time. Store builds commit into the cached library before
' the worker starts; one in-flight write ensures each build sees the previous
' write's committed state instead of racing a stale clone.
sub Pump()
    if m.pushing then return
    if m.storeHost = invalid then return
    job = NextWrite()
    if job = invalid then return
    task = AsyncTask_Launch(m.top, "LibraryPutTask", "onWriteResult", {
        authKey: m.storeHost.callFunc("AuthGetAuthKey")
        item: job.item
    }, "libraryPutTask")
    m.task = task
    m.inFlight = job
    m.pushing = true
end sub

' Highest priority first: a fresh position supersedes stale positions; then
' watched marks; then membership changes. Each slot holds only unstarted work.
function NextWrite() as dynamic
    if m.pendingWatchState <> invalid
        packet = m.pendingWatchState
        m.pendingWatchState = invalid
        item = m.storeHost.callFunc("LibraryBuildWatchStateItem", packet)
        if item <> invalid then return { item: item, kind: "watchState" }
    end if
    if m.pendingWatchedChange <> invalid
        change = m.pendingWatchedChange
        m.pendingWatchedChange = invalid
        item = m.storeHost.callFunc("LibraryBuildWatchedStateItem", change)
        if item <> invalid then return { item: item, kind: "watched" }
    end if
    if m.pendingLibraryChange <> invalid
        change = m.pendingLibraryChange
        m.pendingLibraryChange = invalid
        item = m.storeHost.callFunc("LibraryBuildLibraryChangeItem", change.metaId, change.metaType, change.name, change.poster, change.added)
        if item <> invalid then return { item: item, kind: "libraryChange" }
    end if
    return invalid
end function

' One push settled. Reap it, release the single-flight guard, then drain any
' edit that arrived while the worker was in flight.
sub onWriteResult()
    task = m.task
    m.task = invalid
    m.pushing = false
    if task <> invalid then AsyncTask_Reap(task, m.top, false)
    m.inFlight = invalid
    Pump()
end sub
