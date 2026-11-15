 ' PosterLoader — SceneGraph wrapper around PosterLoaderCore.

sub init()
    m.retryTimer = m.top.FindNode("retryTimer")
    if m.retryTimer <> invalid then m.retryTimer.ObserveField("fire", "onRetryTimer")
    m.loadingTimer = m.top.FindNode("loadingTimer")
    if m.loadingTimer <> invalid then m.loadingTimer.ObserveField("fire", "onLoadingTimeout")

    m.loaderState = {
        top: m.top
        retryTimer: m.retryTimer
        loadingTimer: m.loadingTimer
        observedTarget: invalid
        requestedUri: ""
        retryCount: 0
        retryPending: false
        clearing: false
    }
end sub

sub onTargetChanged()
    PosterLoaderCore_OnTargetChanged(m.loaderState)
end sub

sub onUriChanged()
    PosterLoaderCore_OnUriChanged(m.loaderState)
end sub

sub Load(uri = invalid as dynamic)
    PosterLoaderCore_Load(m.loaderState, uri)
end sub

sub Retry()
    PosterLoaderCore_Retry(m.loaderState)
end sub

sub Clear()
    PosterLoaderCore_Clear(m.loaderState)
end sub

sub onTargetLoadStatus()
    PosterLoaderCore_OnTargetLoadStatus(m.loaderState)
end sub

sub onRetryTimer()
    PosterLoaderCore_OnRetryTimer(m.loaderState)
end sub

sub onLoadingTimeout()
    PosterLoaderCore_OnLoadingTimeout(m.loaderState)
end sub
