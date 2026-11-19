' ImageCacheTask — background byte prefetch for remote images.
'
' Thin Task wrapper: the download/eviction logic lives in
' source/util/ImageCacheRuntime.brs (source scope, outside the
' components/*.brs render-thread static checks). This component only owns the
' Task wiring and event loop.

sub init()
    m.top.functionName = "RunCache"
    m.port = CreateObject("roMessagePort")
    m.top.ObserveFieldScoped("enqueue", m.port)
    m.top.ObserveFieldScoped("enqueueHi", m.port)
    m.top.ObserveFieldScoped("stop", m.port)
    ImageCacheTaskInit(m)
    ImageCacheInitMemoryMonitoring(m, m.port)
end sub

sub ImageCacheConsumePendingEnqueues()
    ' Consume accumulated pending batches. Producers append to these fields;
    ' take-and-clear here so bursts (e.g. per-item enrichment completions) are
    ' not lost while downloads are in progress.
    hiReplace = (m.top.enqueueHiReplace = true)
    hi = m.top.enqueueHi
    if hi <> invalid and type(hi) = "roArray" and hi.Count() > 0
        m.top.enqueueHi = []
        m.top.enqueueHiReplace = false
        ImageCacheTaskOnEnqueue(m, hi, true, hiReplace)
    else if hiReplace
        m.top.enqueueHi = []
        m.top.enqueueHiReplace = false
        ImageCacheTaskOnEnqueue(m, [], true, true)
    end if
    lo = m.top.enqueue
    if lo <> invalid and type(lo) = "roArray" and lo.Count() > 0
        m.top.enqueue = []
        ImageCacheTaskOnEnqueue(m, lo, false, false)
    end if
end sub

sub RunCache()
    ImageCacheEnsureDir()
    while true
        msg = Wait(250, m.port)
        if m.top.stop = true then exit while
        if msg <> invalid
            msgType = type(msg)
            if msgType = "roSGNodeEvent"
                field = msg.GetField()
                if field = "stop"
                    if m.top.stop = true then exit while
                end if
            else if msgType = "roDeviceInfoEvent"
                ImageCacheHandleDeviceInfoEvent(m, msg)
            end if
        end if
        ' Periodic memory-pressure evaluation (hysteretic recovery / poll fallback).
        ImageCacheEvaluateMemoryPressure(m, invalid, false, "poll")
        ' Always ingest pending batches (event-driven and/or accumulated).
        ImageCacheConsumePendingEnqueues()
        ImageCacheTaskDrain(m, m.top)
        if m.top.stop = true then exit while
    end while
end sub

