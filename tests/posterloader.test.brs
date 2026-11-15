 ' PosterLoaderCore behavior tests.

function PL_NewMockTimer(name as string, events as object) as object
    return {
        name: name
        control: ""
        duration: 0
        events: events
    }
end function

function PL_NewTarget(id as string, uri = "" as string, loadStatus = "" as string) as object
    return {
        id: id
        uri: uri
        loadStatus: loadStatus
        observed: []
        unobserved: []
        isSameNode: function(other as object) as boolean
            if other = invalid then return false
            if other.id = invalid then return false
            return m.id = other.id
        end function
    }
end function

function PL_NewState(opts = invalid as dynamic) as object
    events = []
    retryTimer = PL_NewMockTimer("retry", events)
    loadingTimer = PL_NewMockTimer("loading", events)
    target = invalid
    if opts <> invalid and opts.target <> invalid then target = opts.target
    uri = ""
    if opts <> invalid and opts.uri <> invalid then uri = opts.uri
    top = {
        uri: uri
        target: target
        retryEnabled: true
        maxRetries: 3
        retryDelayMs: 1200
        retryDelayMs2: 0
        retryDelayMs3: 0
        loadingTimeoutMs: 0
        status: "idle"
        loadStatus: ""
        ready: false
        retryCount: 0
    }
    if opts <> invalid
        if opts.retryEnabled <> invalid then top.retryEnabled = opts.retryEnabled
        if opts.maxRetries <> invalid then top.maxRetries = opts.maxRetries
        if opts.retryDelayMs <> invalid then top.retryDelayMs = opts.retryDelayMs
        if opts.retryDelayMs2 <> invalid then top.retryDelayMs2 = opts.retryDelayMs2
        if opts.retryDelayMs3 <> invalid then top.retryDelayMs3 = opts.retryDelayMs3
        if opts.loadingTimeoutMs <> invalid then top.loadingTimeoutMs = opts.loadingTimeoutMs
    end if
    state = PosterLoaderCore_DefaultState()
    state.top = top
    state.retryTimer = retryTimer
    state.loadingTimer = loadingTimer
    state.events = events
    state.observeLog = []
    state.unobserveLog = []
    return state
end function

sub PL_SetTargetStatus(target as object, status as string)
    target.loadStatus = status
end sub

sub Test_PosterLoader_InitialRequestLoadsAndBecomesReady()
    Harness_Suite("PosterLoader requests a new URI and becomes ready")
    target = PL_NewTarget("p")
    state = PL_NewState({ target: target, uri: "http://a/img.png" })

    PosterLoaderCore_OnUriChanged(state)

    Harness_Equal(target.uri, "http://a/img.png", "target uri set for new request")
    Harness_Equal(state.top.status, "loading", "status is loading after request")
    Harness_Ok(state.top.ready = false, "not ready while loading")

    PL_SetTargetStatus(target, "ready")
    PosterLoaderCore_OnTargetLoadStatus(state)

    Harness_Equal(state.top.status, "ready", "status becomes ready")
    Harness_Equal(state.top.loadStatus, "ready", "loadStatus mirrored")
    Harness_Ok(state.top.ready = true, "ready flag set")
    Harness_Equal(state.retryCount, 0, "no retries on success")
end sub

sub Test_PosterLoader_SameUriReadyIsNoOp()
    Harness_Suite("PosterLoader same URI ready is a no-op")
    target = PL_NewTarget("p", "http://a/img.png", "ready")
    state = PL_NewState({ target: target, uri: "http://a/img.png" })

    PosterLoaderCore_OnUriChanged(state)

    Harness_Equal(target.uri, "http://a/img.png", "uri unchanged")
    Harness_Equal(state.top.status, "ready", "status is ready")
    Harness_Ok(state.top.ready = true, "ready true for same-uri ready target")
    Harness_Equal(state.retryCount, 0, "no retry scheduled")
end sub

sub Test_PosterLoader_FailedLoadRetriesWithEscalatingDelays()
    Harness_Suite("PosterLoader retries failed loads with configured delays")
    target = PL_NewTarget("p")
    state = PL_NewState({
        target: target
        uri: "http://a/img.png"
        maxRetries: 3
        retryDelayMs: 1500
        retryDelayMs2: 4000
        retryDelayMs3: 8000
    })

    PosterLoaderCore_OnUriChanged(state)
    PL_SetTargetStatus(target, "failed")
    PosterLoaderCore_OnTargetLoadStatus(state)

    Harness_Equal(state.top.status, "failed", "failed after first load failure")
    Harness_Equal(state.retryCount, 1, "retry count incremented")
    Harness_Equal(state.retryTimer.duration, 1.5, "first retry uses retryDelayMs")

    PosterLoaderCore_OnRetryTimer(state)
    Harness_Equal(target.uri, "http://a/img.png", "retry reloads requested uri")
    PL_SetTargetStatus(target, "failed")
    PosterLoaderCore_OnTargetLoadStatus(state)
    Harness_Equal(state.retryCount, 2, "second retry scheduled")
    Harness_Equal(state.retryTimer.duration, 4.0, "second retry uses retryDelayMs2")

    PosterLoaderCore_OnRetryTimer(state)
    PL_SetTargetStatus(target, "failed")
    PosterLoaderCore_OnTargetLoadStatus(state)
    Harness_Equal(state.retryCount, 3, "third retry scheduled")
    Harness_Equal(state.retryTimer.duration, 8.0, "third retry uses retryDelayMs3")

    PosterLoaderCore_OnRetryTimer(state)
    PL_SetTargetStatus(target, "failed")
    PosterLoaderCore_OnTargetLoadStatus(state)
    Harness_Equal(state.retryCount, 3, "retry count capped at maxRetries")
    Harness_Ok(state.retryPending = false, "no pending retry after exhaustion")
    Harness_Equal(state.top.status, "failed", "remains failed after retries exhausted")
end sub

sub Test_PosterLoader_LoadingTimeoutTriggersRetry()
    Harness_Suite("PosterLoader loading timeout triggers retry policy")
    target = PL_NewTarget("p")
    state = PL_NewState({
        target: target
        uri: "http://a/img.png"
        loadingTimeoutMs: 12000
        retryDelayMs: 1500
        maxRetries: 3
    })

    PosterLoaderCore_OnUriChanged(state)
    Harness_Equal(state.top.status, "loading", "loading after request")
    Harness_Equal(state.loadingTimer.duration, 12.0, "loading watchdog started")

    ' Repeated loading status updates should not reset an active watchdog timer.
    PL_SetTargetStatus(target, "loading")
    PosterLoaderCore_OnTargetLoadStatus(state)
    Harness_Ok(state.loadingWatchdogActive = true, "watchdog remains active on repeated loading status")

    PosterLoaderCore_OnLoadingTimeout(state)

    Harness_Equal(state.top.status, "failed", "stuck loading treated as failed")
    Harness_Equal(state.retryCount, 1, "timeout schedules retry")
    Harness_Equal(state.retryTimer.duration, 1.5, "retry timer uses retry delay")
    Harness_Ok(state.retryPending = true, "retry pending after timeout")
end sub

sub Test_PosterLoader_ClearResetsStateAndTarget()
    Harness_Suite("PosterLoader Clear resets request and target")
    target = PL_NewTarget("p", "http://a/img.png", "loading")
    state = PL_NewState({ target: target, uri: "http://a/img.png", loadingTimeoutMs: 5000 })

    PosterLoaderCore_OnUriChanged(state)
    state.retryCount = 2
    state.retryPending = true
    state.top.retryCount = 2

    PosterLoaderCore_Clear(state)

    Harness_Equal(state.requestedUri, "", "requestedUri cleared")
    Harness_Equal(state.top.uri, "", "top uri cleared")
    Harness_Equal(target.uri, "", "target uri cleared")
    Harness_Equal(state.retryCount, 0, "retryCount reset")
    Harness_Equal(state.top.retryCount, 0, "top retryCount reset")
    Harness_Ok(state.retryPending = false, "retryPending reset")
    Harness_Equal(state.top.status, "idle", "status idle after clear")
    Harness_Equal(state.top.loadStatus, "", "loadStatus cleared")
    Harness_Ok(state.top.ready = false, "ready false after clear")
end sub

sub Test_PosterLoader_TargetSwapReevaluatesAndObserves()
    Harness_Suite("PosterLoader target changes rebind observation and re-evaluate")
    target1 = PL_NewTarget("p1", "http://a/img.png", "ready")
    target2 = PL_NewTarget("p2", "http://a/img.png", "")
    state = PL_NewState({ target: target1, uri: "http://a/img.png" })

    PosterLoaderCore_OnTargetChanged(state)
    PosterLoaderCore_OnUriChanged(state)
    Harness_Ok(state.observeLog.Count() > 0, "initial target observed")

    state.top.target = target2
    PosterLoaderCore_OnTargetChanged(state)

    Harness_Ok(state.unobserveLog.Count() > 0, "previous target unobserved")
    Harness_Ok(state.observeLog.Count() > 1, "new target observed")
    Harness_Equal(target2.uri, "http://a/img.png", "new target receives requested uri")
    Harness_Equal(state.top.status, "loading", "new target starts loading when not ready")
end sub

sub Test_PosterLoader_IgnoresStaleStatusForOldUri()
    Harness_Suite("PosterLoader ignores stale target status for non-requested URI")
    target = PL_NewTarget("p", "http://new/img.png", "loading")
    state = PL_NewState({ target: target, uri: "http://new/img.png" })

    PosterLoaderCore_OnUriChanged(state)
    Harness_Equal(state.top.status, "loading", "loading for current request")

    ' Simulate stale callback context: target still points to new uri but callback
    ' should be ignored if uri mismatches requestedUri.
    state.requestedUri = "http://other/img.png"
    PL_SetTargetStatus(target, "ready")
    PosterLoaderCore_OnTargetLoadStatus(state)

    Harness_Equal(state.top.status, "loading", "status unchanged for stale status update")
    Harness_Ok(state.top.ready = false, "ready unchanged for stale status update")
end sub

sub Test_PosterLoader_LoadingTimeoutRecoversIfReady()
    Harness_Suite("PosterLoader loading timeout recovers quietly if target is ready")
    target = PL_NewTarget("p")
    state = PL_NewState({
        target: target
        uri: "http://a/img.png"
        loadingTimeoutMs: 12000
        retryDelayMs: 1500
        maxRetries: 3
    })

    PosterLoaderCore_OnUriChanged(state)
    PL_SetTargetStatus(target, "ready")
    PosterLoaderCore_OnLoadingTimeout(state)

    Harness_Equal(state.top.status, "ready", "timeout recovers to ready when target is ready")
    Harness_Ok(state.top.ready = true, "ready flag set on timeout recovery")
    Harness_Equal(state.retryCount, 0, "no retry scheduled when ready at timeout")
    Harness_Ok(state.retryPending = false, "no retry pending when ready at timeout")
end sub

sub Test_PosterLoader_TimeoutIgnoredAfterUriChange()
    Harness_Suite("PosterLoader loading timeout is ignored when request context no longer matches")
    target = PL_NewTarget("p")
    state = PL_NewState({
        target: target
        uri: "http://a/img.png"
        loadingTimeoutMs: 12000
        retryDelayMs: 1500
        maxRetries: 3
    })

    PosterLoaderCore_OnUriChanged(state)
    state.top.uri = "http://b/img.png"
    PosterLoaderCore_OnUriChanged(state)
    ' New request becomes ready normally.
    PL_SetTargetStatus(target, "ready")
    PosterLoaderCore_OnTargetLoadStatus(state)
    Harness_Equal(state.top.status, "ready", "new request is ready")

    ' Simulate a stale timeout callback with mismatched requestedUri context.
    state.requestedUri = "http://a/img.png"
    PosterLoaderCore_OnLoadingTimeout(state)

    Harness_Equal(state.top.status, "ready", "stale timeout does not change ready state")
    Harness_Equal(state.retryCount, 0, "stale timeout does not schedule retry")
    Harness_Ok(state.retryPending = false, "stale timeout does not set retry pending")
end sub

sub Test_PosterLoader_ClearDuringRetryPendingPreventsReload()
    Harness_Suite("PosterLoader clear during retry pending prevents reload")
    target = PL_NewTarget("p")
    state = PL_NewState({
        target: target
        uri: "http://a/img.png"
        retryDelayMs: 1500
        maxRetries: 3
    })

    PosterLoaderCore_OnUriChanged(state)
    PL_SetTargetStatus(target, "failed")
    PosterLoaderCore_OnTargetLoadStatus(state)
    Harness_Ok(state.retryPending = true, "retry scheduled after failure")

    PosterLoaderCore_Clear(state)
    target.uri = ""
    PosterLoaderCore_OnRetryTimer(state)

    Harness_Equal(state.top.status, "idle", "state remains idle after cleared retry timer")
    Harness_Equal(target.uri, "", "target uri not reloaded after clear")
    Harness_Ok(state.retryPending = false, "retry pending cleared")
end sub

sub Test_PosterLoader_RetryDisabledOrMaxZeroDoesNotSchedule()
    Harness_Suite("PosterLoader failure is terminal when retries disabled or maxRetries is zero")
    target = PL_NewTarget("p")
    state = PL_NewState({
        target: target
        uri: "http://a/img.png"
        retryEnabled: false
        maxRetries: 3
    })

    PosterLoaderCore_OnUriChanged(state)
    PL_SetTargetStatus(target, "failed")
    PosterLoaderCore_OnTargetLoadStatus(state)

    Harness_Equal(state.top.status, "failed", "failed when retries disabled")
    Harness_Equal(state.retryCount, 0, "no retry count increment when retries disabled")
    Harness_Ok(state.retryPending = false, "no retry pending when retries disabled")

    target2 = PL_NewTarget("p2")
    state2 = PL_NewState({
        target: target2
        uri: "http://b/img.png"
        retryEnabled: true
        maxRetries: 0
    })
    PosterLoaderCore_OnUriChanged(state2)
    PL_SetTargetStatus(target2, "failed")
    PosterLoaderCore_OnTargetLoadStatus(state2)

    Harness_Equal(state2.top.status, "failed", "failed when maxRetries is zero")
    Harness_Equal(state2.retryCount, 0, "no retry count increment when maxRetries is zero")
    Harness_Ok(state2.retryPending = false, "no retry pending when maxRetries is zero")
end sub

sub Test_PosterLoader_ExhaustedFailuresDoNotReschedule()
    Harness_Suite("PosterLoader exhausted failures do not reschedule retries")
    target = PL_NewTarget("p")
    state = PL_NewState({
        target: target
        uri: "http://a/img.png"
        retryDelayMs: 100
        maxRetries: 1
    })

    PosterLoaderCore_OnUriChanged(state)
    PL_SetTargetStatus(target, "failed")
    PosterLoaderCore_OnTargetLoadStatus(state)
    Harness_Equal(state.retryCount, 1, "retry scheduled once")

    PosterLoaderCore_OnRetryTimer(state)
    PL_SetTargetStatus(target, "failed")
    PosterLoaderCore_OnTargetLoadStatus(state)
    Harness_Equal(state.retryCount, 1, "retry count stays at max")
    Harness_Ok(state.retryPending = false, "no retry pending after exhaustion")

    ' Extra failure callbacks after exhaustion must not schedule/restart retries.
    PL_SetTargetStatus(target, "failed")
    PosterLoaderCore_OnTargetLoadStatus(state)
    Harness_Equal(state.retryCount, 1, "extra failure does not increment retry count")
    Harness_Ok(state.retryPending = false, "extra failure does not schedule retry")
end sub

sub Test_PosterLoader_RetryTimerIgnoredAfterUriChange()
    Harness_Suite("PosterLoader retry timer does not regress a new ready request")
    target = PL_NewTarget("p")
    state = PL_NewState({
        target: target
        uri: "http://a/img.png"
        retryDelayMs: 1500
        maxRetries: 3
    })

    PosterLoaderCore_OnUriChanged(state)
    PL_SetTargetStatus(target, "failed")
    PosterLoaderCore_OnTargetLoadStatus(state)
    Harness_Ok(state.retryPending = true, "retry scheduled for original request")

    state.top.uri = "http://b/img.png"
    PosterLoaderCore_OnUriChanged(state)
    PL_SetTargetStatus(target, "ready")
    PosterLoaderCore_OnTargetLoadStatus(state)
    Harness_Equal(state.top.status, "ready", "new request is ready")

    ' Even if a stale retry callback fires, it must not reload/regress current ready state.
    PosterLoaderCore_OnRetryTimer(state)

    Harness_Equal(target.uri, "http://b/img.png", "target uri remains current request")
    Harness_Equal(state.top.status, "ready", "ready state unchanged by stale retry callback")
    Harness_Ok(state.top.ready = true, "ready flag unchanged by stale retry callback")
end sub
