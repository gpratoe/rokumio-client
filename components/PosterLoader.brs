' PosterLoader — centralizes Poster URI loading, loadStatus observation, and
' retry/recovery so screens don't each reimplement same-URI, failed/stuck, and
' flash-prone handling.
'
' It manages assignment of `m.target.uri` for the requested `m.top.uri`.
' Callers own presentation (visibility, opacity, animations, fit/layout,
' fallbacks) by observing `status`/`ready`/`loadStatus` and/or `target.loadStatus`.

sub init()
    m.retryTimer = m.top.FindNode("retryTimer")
    m.retryTimer.ObserveField("fire", "onRetryTimer")
    m.observedTarget = invalid
    m.requestedUri = ""
    m.retryCount = 0
    m.retryPending = false
    m.clearing = false
end sub

sub onTargetChanged()
    target = m.top.target
    if m.observedTarget <> invalid and (target = invalid or not SameNode(m.observedTarget, target))
        m.observedTarget.UnobserveField("loadStatus")
    end if
    if target <> invalid and (m.observedTarget = invalid or not SameNode(m.observedTarget, target))
        target.ObserveField("loadStatus", "onTargetLoadStatus")
    end if
    m.observedTarget = target
    ' Re-evaluate current request against the new target.
    ApplyRequest()
end sub

function SameNode(a as object, b as object) as boolean
    if a = invalid or b = invalid then return false
    ' roSGNode identity comparison: same node reference compares equal.
    return a.isSameNode(b)
end function

sub onUriChanged()
    m.requestedUri = StringOf(m.top.uri)
    m.retryCount = 0
    m.retryPending = false
    StopRetryTimer()
    ApplyRequest()
end sub

' Imperative: request/load a specific URI (or current field if omitted/invalid).
sub Load(uri = invalid as dynamic)
    if uri <> invalid
        m.top.uri = StringOf(uri)
        return
    end if
    m.requestedUri = StringOf(m.top.uri)
    m.retryCount = 0
    m.retryPending = false
    StopRetryTimer()
    ApplyRequest()
end sub

' Imperative: retry the current requested URI immediately (if any).
sub Retry()
    if m.requestedUri = "" then return
    m.retryPending = false
    StopRetryTimer()
    ForceLoad(m.requestedUri)
end sub

' Imperative: clear request and target URI/state.
sub Clear()
    m.requestedUri = ""
    m.top.uri = ""
    m.retryCount = 0
    m.retryPending = false
    StopRetryTimer()
    target = m.top.target
    if target <> invalid
        m.clearing = true
        target.uri = ""
        m.clearing = false
    end if
    SetState("idle", "", false)
end sub

sub ApplyRequest()
    target = m.top.target
    uri = m.requestedUri
    m.top.retryCount = m.retryCount

    if target = invalid
        if uri = ""
            SetState("idle", "", false)
        else
            SetState("idle", "", false)
        end if
        return
    end if

    if uri = ""
        if StringOf(target.uri) <> ""
            m.clearing = true
            target.uri = ""
            m.clearing = false
        end if
        SetState("idle", SafeLoadStatus(target), false)
        return
    end if

    status = SafeLoadStatus(target)
    if StringOf(target.uri) = uri
        if status = "ready"
            ' Same URI already ready: no-op to avoid flash/reload.
            SetState("ready", status, true)
            return
        else if status = "loading"
            SetState("loading", status, false)
            return
        else if status = "failed"
            HandleFailure(status)
            return
        else
            ' none/unknown/transient: if no retry pending, treat as needing load.
            if not m.retryPending then ForceLoad(uri)
            return
        end if
    end if

    ' Different URI (or target not yet pointing at requested URI): start load.
    ForceLoad(uri)
end sub

sub ForceLoad(uri as string)
    target = m.top.target
    if target = invalid then return
    m.retryPending = false
    StopRetryTimer()
    m.clearing = true
    ' Clear first when reloading same URI to recover stuck/failed states.
    if StringOf(target.uri) = uri then target.uri = ""
    m.clearing = false
    target.uri = uri
    SetState("loading", SafeLoadStatus(target), false)
end sub

sub onTargetLoadStatus()
    if m.clearing then return
    target = m.top.target
    if target = invalid then return
    uri = m.requestedUri
    status = SafeLoadStatus(target)

    ' Ignore status updates not relevant to the current request.
    if uri = ""
        if StringOf(target.uri) = "" then SetState("idle", status, false)
        return
    end if
    if StringOf(target.uri) <> uri then return

    if status = "ready"
        m.retryPending = false
        StopRetryTimer()
        SetState("ready", status, true)
    else if status = "failed"
        HandleFailure(status)
    else if status = "loading"
        m.retryPending = false
        StopRetryTimer()
        SetState("loading", status, false)
    else
        ' none or unknown: keep current non-ready state; ApplyRequest/Retry can recover.
        SetState("loading", status, false)
    end if
end sub

sub HandleFailure(status as string)
    SetState("failed", status, false)
    if not m.top.retryEnabled then return
    maxRetries = m.top.maxRetries
    if maxRetries <> invalid and maxRetries >= 0 and m.retryCount >= maxRetries then return
    if m.retryPending then return

    m.retryCount = m.retryCount + 1
    m.top.retryCount = m.retryCount
    delayMs = m.top.retryDelayMs
    if delayMs = invalid or delayMs < 0 then delayMs = 0
    m.retryTimer.duration = delayMs / 1000.0
    m.retryPending = true
    m.retryTimer.control = "stop"
    m.retryTimer.control = "start"
end sub

sub onRetryTimer()
    m.retryPending = false
    if m.requestedUri = "" then return
    target = m.top.target
    if target = invalid then return
    ' Only retry if still relevant and not already ready.
    if StringOf(target.uri) = m.requestedUri and SafeLoadStatus(target) = "ready"
        SetState("ready", "ready", true)
        return
    end if
    ForceLoad(m.requestedUri)
end sub

sub StopRetryTimer()
    if m.retryTimer <> invalid then m.retryTimer.control = "stop"
end sub

function SafeLoadStatus(target as object) as string
    if target = invalid then return ""
    status = target.loadStatus
    if status = invalid then return ""
    return StringOf(status)
end function

function StringOf(value as dynamic) as string
    if value = invalid then return ""
    return value.ToStr()
end function

sub SetState(status as string, loadStatus as string, ready as boolean)
    if m.top.status = status and m.top.loadStatus = loadStatus and m.top.ready = ready then return
    m.top.status = status
    m.top.loadStatus = loadStatus
    m.top.ready = ready
end sub
