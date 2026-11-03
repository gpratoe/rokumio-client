' AccountSyncCoordinator — order and own the two account pulls.
'
' Add-on and library pulls start at login/relaunch, but the device has a low
' ceiling for new concurrent connections. The library pull waits behind the
' add-on pull. This component owns that ordering and both Task lifecycles;
' MainScene adopts results, paints faults, refreshes screens and handles the
' navigation for a revoked session.

sub init()
    m.storeHost = invalid
    m.scene = invalid
    m.addonTask = invalid
    m.libraryTask = invalid
    m.pendingLibrarySync = false
end sub

' Inject node references only. Store class instances cannot cross a component
' boundary because Roku copies their associative arrays and strips methods.
sub SetDependencies(storeHost as object, scene as object)
    m.storeHost = storeHost
    m.scene = scene
end sub

' Pull the complete account add-on collection. The result and its finished
' sentinel are both observed: an alwaysNotify result may first notify while
' invalid, and only the sentinel's true value proves a missing result is a
' worker failure.
sub StartAddonSync()
    if m.addonTask <> invalid then return
    fields = {}
    if m.storeHost <> invalid then fields.authKey = m.storeHost.callFunc("AuthGetAuthKey")
    m.addonTask = AsyncTask_Launch(m.top, "AddonSyncTask", "onAddonResult", fields, "addonSyncTask", "onAddonFinished")
end sub

' Start the library pull unless the add-on pull is in flight. Deferral keeps
' the launch request burst under the device's low concurrent-connection limit.
sub StartLibrarySync()
    if m.addonTask <> invalid
        m.pendingLibrarySync = true
        return
    end if
    LaunchLibrarySync()
end sub

sub LaunchLibrarySync()
    if m.libraryTask <> invalid then return
    fields = {}
    if m.storeHost <> invalid then fields.authKey = m.storeHost.callFunc("AuthGetAuthKey")
    m.libraryTask = AsyncTask_Launch(m.top, "LibrarySyncTask", "onLibraryResult", fields, "librarySyncTask")
end sub

sub PumpPendingLibrarySync()
    if m.pendingLibrarySync <> true then return
    m.pendingLibrarySync = false
    LaunchLibrarySync()
end sub

' A revoked session can be reported by another coordinator (for example the
' collection writer), not just these pulls. MainScene cancels this deferred
' launch before it tears the account session down.
sub CancelPendingLibrarySync()
    m.pendingLibrarySync = false
end sub

sub onAddonResult()
    task = m.addonTask
    if task = invalid then return
    result = task.result
    ' alwaysNotify's initial empty notification is not a result. Keep the task
    ' observed; its packet or the finished sentinel will arrive later.
    if result = invalid then return

    m.addonTask = invalid
    AsyncTask_Reap(task, m.top, false)
    if m.scene <> invalid then m.scene.callFunc("ClearAddonSyncFaults")

    if result.revokedSession = true
        m.pendingLibrarySync = false
        if m.scene <> invalid then m.scene.callFunc("HandleRevokedSession")
        return
    end if

    if m.scene <> invalid then m.scene.callFunc("AdoptAddonSyncResult", result)
    PumpPendingLibrarySync()
end sub

sub onAddonFinished()
    task = m.addonTask
    if task = invalid then return
    ' Notification arrival is not task completion: the sentinel starts false
    ' and can notify while the worker is still running.
    if task.finished <> true then return

    m.addonTask = invalid
    stage = "unknown"
    if task.stage <> invalid and task.stage <> "" then stage = task.stage
    AsyncTask_Reap(task, m.top, false)
    if m.scene <> invalid
        m.scene.callFunc("ClearAddonSyncFaults")
        print "[addons] sync worker finished with NO result (stage: " ; stage ; ")"
        m.scene.callFunc("ReportAddonSyncFault", "addon sync: the worker finished with no result (stage: " + stage + ")")
    end if
    PumpPendingLibrarySync()
end sub

sub onLibraryResult()
    task = m.libraryTask
    m.libraryTask = invalid
    if task = invalid then return
    result = task.result
    AsyncTask_Reap(task, m.top, false)

    if result <> invalid and result.revokedSession = true
        m.pendingLibrarySync = false
        if m.scene <> invalid then m.scene.callFunc("HandleRevokedSession")
        return
    end if
    if m.scene <> invalid then m.scene.callFunc("ApplyLibrarySyncResult", result)
end sub
