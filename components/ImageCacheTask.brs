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
end sub

sub RunCache()
    ImageCacheEnsureDir()
    while true
        msg = Wait(250, m.port)
        if m.top.stop = true then exit while
        if msg <> invalid and type(msg) = "roSGNodeEvent"
            field = msg.GetField()
            if field = "stop"
                if m.top.stop = true then exit while
            else if field = "enqueue"
                ImageCacheTaskOnEnqueue(m, m.top.enqueue, false)
            else if field = "enqueueHi"
                ImageCacheTaskOnEnqueue(m, m.top.enqueueHi, true)
            end if
        end if
        ImageCacheTaskDrain(m, m.top)
        if m.top.stop = true then exit while
    end while
end sub

