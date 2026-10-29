' ImportCoordinator — one sequential import queue for deep links and the setup page.
'
' The coordinator owns its one-import slot, counters, sequential install task,
' and task lifecycle. It does not own store policy or UI: successful records
' are handed to MainScene's existing account-install gateway, and the finished
' plain-data summary returns to MainScene for settings application, dialog
' presentation and screen refreshes.

sub init()
    m.scene = invalid
    m.import = invalid
end sub

' MainScene owns both the StoreHost and the scene-level side effects. Only its
' node reference crosses this boundary; no store instance or callback AA does.
sub SetScene(scene as object)
    m.scene = scene
end sub

function IsBusy() as boolean
    return m.import <> invalid
end function

' Start the shared import. False means an import is already in flight or the
' caller supplied no usable queue; true means the queue was accepted.
function StartImport(addons as object, settings as dynamic) as boolean
    if m.import <> invalid then return false
    if addons = invalid or Type(addons) <> "roArray" then return false

    m.import = {
        pending: []
        added: 0
        skipped: 0
        failed: 0
        failures: []
        task: invalid
        settings: settings
        requested: addons.Count()
    }
    for each url in addons
        m.import.pending.Push(url)
    end for
    Pump()
    return true
end function

' Start the next manifest fetch, or report completion when the queue is empty.
sub Pump()
    if m.import = invalid then return
    if m.import.task <> invalid then return
    if m.import.pending.Count() > 0
        url = m.import.pending.Shift()
        m.import.task = AsyncTask_Launch(m.top, "AddonsInstallTask", "onInstallResult", { address: url }, "deepLinkInstall")
        return
    end if
    Finish()
end sub

' One manifest fetch settled. AddonsInstallTask validates without the live
' registry, so the actual duplicate gate is MainScene's AddonsStore.Register
' gateway. Count added, skipped, or failed, then keep draining sequentially.
sub onInstallResult()
    if m.import = invalid or m.import.task = invalid then return
    task = m.import.task
    m.import.task = invalid
    result = task.result
    AsyncTask_Reap(task, m.top, false)

    resultId = ""
    resultError = ""
    if result <> invalid
        if result.id <> invalid then resultId = result.id
        if result.error <> invalid then resultError = result.error
    end if

    if result <> invalid and result.ok and result.record <> invalid
        registered = false
        if m.scene <> invalid
            registered = m.scene.callFunc("ImportRegisterAddon", result.record, result.transportUrl, result.manifest)
        end if
        if registered
            m.import.added = m.import.added + 1
        else
            m.import.skipped = m.import.skipped + 1
        end if
    else
        m.import.failed = m.import.failed + 1
        ' The add-on's error remains raw server text; the UI translates only
        ' its own fallback copy when it renders the summary.
        m.import.failures.Push({ id: resultId, error: resultError })
    end if
    Pump()
end sub

' Hand off plain summary data and release the slot before calling out, so a
' later deep link cannot observe a completed import as still busy.
sub Finish()
    if m.import = invalid then return
    summary = m.import
    m.import = invalid
    if m.scene <> invalid then m.scene.callFunc("ImportFinished", summary)
end sub
