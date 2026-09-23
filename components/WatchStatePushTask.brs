' WatchStatePushTask — push one library item's watch state to the account.
'
' A single datastorePut through StremioApiStore and nothing else. The full
' LibraryItem to write rides in m.top.item (built by
' LibraryStore.BuildWatchStateItem, which owns the merge into the freshest
' cached copy); this worker only sends it off the render thread. The envelope
' rules are the store's (and are unit-tested there).

sub init()
    m.top.functionName = "push"
end sub

sub push()
    print "[rokumio] WatchStatePushTask starting"
    try
        store = StremioApiStore(Transport(), m.top.authKey)
        result = store.LibraryPut(m.top.item, "Could not write watch state")
        print "[rokumio] WatchStatePushTask ok=" + result.ok.ToStr() + " error='" + result.error + "'"
        m.top.result = result
    catch e
        print "[rokumio] WatchStatePushTask error: " + e.message
        m.top.result = { ok: false, error: e.message }
    end try
end sub