 ' PosterLoaderCore — testable state machine for PosterLoader component.
' Operates on an explicit state AA so unit tests can exercise behavior without
' SceneGraph runtime. Component provides state fields and timer/observation hooks.

function PosterLoaderCore_DefaultState() as object
    return {
        requestedUri: ""
        retryCount: 0
        retryPending: false
        clearing: false
        loadingWatchdogActive: false
        observedTarget: invalid
        events: []
    }
end function

function PosterLoaderCore_StringOf(value as dynamic) as string
    if value = invalid then return ""
    return value.ToStr()
end function

function PosterLoaderCore_SafeLoadStatus(target as object) as string
    if target = invalid then return ""
    status = target.loadStatus
    if status = invalid then return ""
    return PosterLoaderCore_StringOf(status)
end function

function PosterLoaderCore_SameNode(a as object, b as object) as boolean
    if a = invalid or b = invalid then return false
    if a.isSameNode <> invalid then return a.isSameNode(b)
    ' Avoid "=" on roSGNode types; identity unknown without isSameNode.
    return false
end function

sub PosterLoaderCore_SetState(state as object, status as string, loadStatus as string, ready as boolean)
    top = state.top
    if top = invalid then return
    if top.status = status and top.loadStatus = loadStatus and top.ready = ready then return
    top.status = status
    top.loadStatus = loadStatus
    top.ready = ready
end sub

sub PosterLoaderCore_LogEvent(state as object, event as object)
    if state.events = invalid then return
    state.events.Push(event)
end sub

sub PosterLoaderCore_StopRetryTimer(state as object)
    if state.retryTimer <> invalid and state.retryTimer.control <> invalid
        state.retryTimer.control = "stop"
        PosterLoaderCore_LogEvent(state, { type: "timer_stop", name: "retry" })
    end if
end sub

sub PosterLoaderCore_StopLoadingTimer(state as object)
    state.loadingWatchdogActive = false
    if state.loadingTimer <> invalid and state.loadingTimer.control <> invalid
        state.loadingTimer.control = "stop"
        PosterLoaderCore_LogEvent(state, { type: "timer_stop", name: "loading" })
    end if
end sub

sub PosterLoaderCore_StartRetryTimer(state as object, durationSec as dynamic)
    if durationSec = invalid then durationSec = 0
    if state.retryTimer <> invalid
        state.retryTimer.duration = durationSec
        state.retryTimer.control = "stop"
        state.retryTimer.control = "start"
        PosterLoaderCore_LogEvent(state, { type: "timer_start", name: "retry", duration: durationSec })
    end if
end sub

sub PosterLoaderCore_StartLoadingTimer(state as object)
    top = state.top
    if top = invalid then return
    timeoutMs = top.loadingTimeoutMs
    ' Disabled by default in app configs (0): watchdog timeout treated slow-but-progressing
    ' loads as failed and retried, causing churn; definitive loadStatus failures still retry.
    if timeoutMs = invalid or timeoutMs <= 0 then return
    ' Start watchdog once per loading phase; do not reset on repeated loading updates.
    if state.loadingWatchdogActive = true then return
    if state.loadingTimer <> invalid
        state.loadingWatchdogActive = true
        state.loadingTimer.duration = timeoutMs / 1000.0
        state.loadingTimer.control = "stop"
        state.loadingTimer.control = "start"
        PosterLoaderCore_LogEvent(state, { type: "timer_start", name: "loading", duration: state.loadingTimer.duration })
    end if
end sub

sub PosterLoaderCore_ForceLoad(state as object, uri as string)
    top = state.top
    if top = invalid then return
    target = top.target
    if target = invalid then return
    state.retryPending = false
    PosterLoaderCore_StopRetryTimer(state)
    PosterLoaderCore_StopLoadingTimer(state)
    state.clearing = true
    ' Clear first when reloading same URI to recover stuck/failed states.
    if PosterLoaderCore_StringOf(target.uri) = uri then target.uri = ""
    state.clearing = false
    target.uri = uri
    PosterLoaderCore_SetState(state, "loading", PosterLoaderCore_SafeLoadStatus(target), false)
    PosterLoaderCore_StartLoadingTimer(state)
end sub

sub PosterLoaderCore_HandleFailure(state as object, status as string)
    top = state.top
    PosterLoaderCore_SetState(state, "failed", status, false)
    if top = invalid then return
    if not (top.retryEnabled = true) then return
    maxRetries = top.maxRetries
    if maxRetries <> invalid and maxRetries >= 0 and state.retryCount >= maxRetries then return
    if state.retryPending then return

    state.retryCount = state.retryCount + 1
    top.retryCount = state.retryCount
    delayMs = top.retryDelayMs
    if state.retryCount = 2 and top.retryDelayMs2 <> invalid and top.retryDelayMs2 > 0 then delayMs = top.retryDelayMs2
    if state.retryCount >= 3 and top.retryDelayMs3 <> invalid and top.retryDelayMs3 > 0 then delayMs = top.retryDelayMs3
    if delayMs = invalid or delayMs < 0 then delayMs = 0
    state.retryPending = true
    PosterLoaderCore_StartRetryTimer(state, delayMs / 1000.0)
end sub

sub PosterLoaderCore_ApplyRequest(state as object)
    top = state.top
    if top = invalid then return
    target = top.target
    uri = PosterLoaderCore_StringOf(state.requestedUri)
    top.retryCount = state.retryCount

    if target = invalid
        PosterLoaderCore_SetState(state, "idle", "", false)
        return
    end if

    if uri = ""
        if PosterLoaderCore_StringOf(target.uri) <> ""
            state.clearing = true
            target.uri = ""
            state.clearing = false
        end if
        PosterLoaderCore_SetState(state, "idle", PosterLoaderCore_SafeLoadStatus(target), false)
        return
    end if

    status = PosterLoaderCore_SafeLoadStatus(target)
    if PosterLoaderCore_StringOf(target.uri) = uri
        if status = "ready"
            ' Same URI already ready: no-op to avoid flash/reload.
            PosterLoaderCore_SetState(state, "ready", status, true)
            return
        else if status = "loading"
            PosterLoaderCore_SetState(state, "loading", status, false)
            PosterLoaderCore_StartLoadingTimer(state)
            return
        else if status = "failed"
            PosterLoaderCore_HandleFailure(state, status)
            return
        else
            ' none/unknown/transient: if no retry pending, treat as needing load.
            if not state.retryPending then PosterLoaderCore_ForceLoad(state, uri)
            return
        end if
    end if

    ' Different URI (or target not yet pointing at requested URI): start load.
    PosterLoaderCore_ForceLoad(state, uri)
end sub

sub PosterLoaderCore_OnTargetChanged(state as object)
    top = state.top
    if top = invalid then return
    target = top.target
    if state.observedTarget <> invalid and (target = invalid or not PosterLoaderCore_SameNode(state.observedTarget, target))
        if state.unobserveLog <> invalid then state.unobserveLog.Push(state.observedTarget)
        if state.observedTarget.UnobserveField <> invalid then state.observedTarget.UnobserveField("loadStatus")
    end if
    if target <> invalid and (state.observedTarget = invalid or not PosterLoaderCore_SameNode(state.observedTarget, target))
        if state.observeLog <> invalid then state.observeLog.Push(target)
        if target.ObserveField <> invalid then target.ObserveField("loadStatus", "onTargetLoadStatus")
    end if
    state.observedTarget = target
    PosterLoaderCore_ApplyRequest(state)
end sub

sub PosterLoaderCore_OnUriChanged(state as object)
    top = state.top
    if top = invalid then return
    state.requestedUri = PosterLoaderCore_StringOf(top.uri)
    state.retryCount = 0
    state.retryPending = false
    PosterLoaderCore_StopRetryTimer(state)
    PosterLoaderCore_StopLoadingTimer(state)
    PosterLoaderCore_ApplyRequest(state)
end sub

sub PosterLoaderCore_Load(state as object, uri = invalid as dynamic)
    top = state.top
    if top = invalid then return
    if uri <> invalid
        top.uri = PosterLoaderCore_StringOf(uri)
        return
    end if
    state.requestedUri = PosterLoaderCore_StringOf(top.uri)
    state.retryCount = 0
    state.retryPending = false
    PosterLoaderCore_StopRetryTimer(state)
    PosterLoaderCore_StopLoadingTimer(state)
    PosterLoaderCore_ApplyRequest(state)
end sub

sub PosterLoaderCore_Retry(state as object)
    if PosterLoaderCore_StringOf(state.requestedUri) = "" then return
    state.retryPending = false
    PosterLoaderCore_StopRetryTimer(state)
    PosterLoaderCore_StopLoadingTimer(state)
    PosterLoaderCore_ForceLoad(state, PosterLoaderCore_StringOf(state.requestedUri))
end sub

sub PosterLoaderCore_Clear(state as object)
    top = state.top
    state.requestedUri = ""
    if top <> invalid then top.uri = ""
    state.retryCount = 0
    if top <> invalid then top.retryCount = 0
    state.retryPending = false
    PosterLoaderCore_StopRetryTimer(state)
    PosterLoaderCore_StopLoadingTimer(state)
    target = invalid
    if top <> invalid then target = top.target
    if target <> invalid
        state.clearing = true
        target.uri = ""
        state.clearing = false
    end if
    PosterLoaderCore_SetState(state, "idle", "", false)
end sub

sub PosterLoaderCore_OnTargetLoadStatus(state as object)
    if state.clearing then return
    top = state.top
    if top = invalid then return
    target = top.target
    if target = invalid then return
    uri = PosterLoaderCore_StringOf(state.requestedUri)
    status = PosterLoaderCore_SafeLoadStatus(target)

    ' Ignore status updates not relevant to the current request.
    if uri = ""
        if PosterLoaderCore_StringOf(target.uri) = "" then PosterLoaderCore_SetState(state, "idle", status, false)
        return
    end if
    if PosterLoaderCore_StringOf(target.uri) <> uri then return

    if status = "ready"
        state.retryPending = false
        PosterLoaderCore_StopRetryTimer(state)
        PosterLoaderCore_StopLoadingTimer(state)
        PosterLoaderCore_SetState(state, "ready", status, true)
    else if status = "failed"
        PosterLoaderCore_StopLoadingTimer(state)
        PosterLoaderCore_HandleFailure(state, status)
    else if status = "loading"
        state.retryPending = false
        PosterLoaderCore_StopRetryTimer(state)
        PosterLoaderCore_SetState(state, "loading", status, false)
        PosterLoaderCore_StartLoadingTimer(state)
    else
        ' none or unknown: keep current non-ready state; ApplyRequest/Retry can recover.
        ' Treat as loading and ensure watchdog is running, but do not reset an active one.
        state.retryPending = false
        PosterLoaderCore_StopRetryTimer(state)
        PosterLoaderCore_SetState(state, "loading", status, false)
        PosterLoaderCore_StartLoadingTimer(state)
    end if
end sub

sub PosterLoaderCore_OnRetryTimer(state as object)
    state.retryPending = false
    if PosterLoaderCore_StringOf(state.requestedUri) = "" then return
    top = state.top
    if top = invalid then return
    target = top.target
    if target = invalid then return
    ' Only retry if still relevant and not already ready.
    if PosterLoaderCore_StringOf(target.uri) = PosterLoaderCore_StringOf(state.requestedUri) and PosterLoaderCore_SafeLoadStatus(target) = "ready"
        PosterLoaderCore_SetState(state, "ready", "ready", true)
        return
    end if
    PosterLoaderCore_ForceLoad(state, PosterLoaderCore_StringOf(state.requestedUri))
end sub

sub PosterLoaderCore_OnLoadingTimeout(state as object)
    ' Consume watchdog fire; if a new loading phase is valid it will be started explicitly.
    ' Disabled in app configs (loadingTimeoutMs=0): kept for explicit opt-in cases, but
    ' timing-based retries churned on slow/latency-heavy networks in practice.
    PosterLoaderCore_StopLoadingTimer(state)
    if PosterLoaderCore_StringOf(state.requestedUri) = "" then return
    top = state.top
    if top = invalid then return
    target = top.target
    if target = invalid then return
    if PosterLoaderCore_StringOf(target.uri) <> PosterLoaderCore_StringOf(state.requestedUri) then return
    status = PosterLoaderCore_SafeLoadStatus(target)
    if status = "ready" then
        ' Recovered/ready at timeout: treat as ready without noisy retry-path logging.
        PosterLoaderCore_SetState(state, "ready", status, true)
        return
    end if
    ' Stuck loading: treat as failed and apply retry policy.
    PosterLoaderCore_HandleFailure(state, "failed")
end sub
