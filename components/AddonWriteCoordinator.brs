' AddonWriteCoordinator — serialize whole-account add-on collection writes.
'
' The account endpoint replaces the complete collection. The StoreHost's
' AddonsStore mirror is the authoritative payload, and a stamp detects whether
' it changed while a PUT was in flight. Only one worker may be active; when it
' settles, a changed stamp schedules one more PUT of the newest mirror.
'
' MainScene remains the one gateway for local add-on changes and owns fault
' presentation/session recovery. This component owns the worker and its
' single-flight lifecycle.

sub init()
    m.storeHost = invalid
    m.scene = invalid
    m.pushing = false
    m.task = invalid
    m.writeStamp = 0
end sub

' Inject only node references. Store instances are plain classes whose methods
' Roku strips when copied across a component boundary.
sub SetDependencies(storeHost as object, scene as object)
    m.storeHost = storeHost
    m.scene = scene
end sub

' Pump one collection replacement. If another local edit changes the mirror
' while this flight is active, onWriteResult notices the stamp and re-pumps.
sub Pump()
    if m.pushing then return
    if m.storeHost = invalid then return
    if m.storeHost.callFunc("AuthGetSession") <> "stremio" then return

    addons = m.storeHost.callFunc("AddonsAccountPutAddons")
    if addons = invalid
        ' A missing mirror means the pull did not establish the account's full
        ' collection. Refuse to send a partial payload that could delete
        ' un-importable add-ons from the user's account.
        return
    end if

    m.writeStamp = m.storeHost.callFunc("AddonsAccountStamp")
    task = AsyncTask_Launch(m.top, "AddonsWriteTask", "onWriteResult", {
        authKey: m.storeHost.callFunc("AuthGetAuthKey")
        payload: { addons: addons }
    }, "addonWriteTask")
    m.task = task
    m.pushing = true
end sub

' The whole-collection PUT settled. Reap it, handle session/fault outcomes
' through MainScene's existing authority, and send a follow-up only if the
' mirror moved while the request was in flight.
sub onWriteResult()
    if m.task = invalid then return
    result = m.task.result
    if result = invalid then return

    task = m.task
    m.task = invalid
    m.pushing = false
    AsyncTask_Reap(task, m.top, false)

    if result.revokedSession = true
        if m.scene <> invalid then m.scene.callFunc("HandleRevokedSession")
        return
    end if
    if not result.ok
        reason = "unknown error"
        if result.error <> invalid and result.error <> "" then reason = result.error
        if m.scene <> invalid then m.scene.callFunc("ReportAddonWriteFault", "addon change failed: " + reason)
        return
    end if

    print "[addons] collection put landed"
    if m.storeHost.callFunc("AddonsAccountStamp") <> m.writeStamp then Pump()
end sub
