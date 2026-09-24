' LibraryWritePushTask — push one library add/remove to the account.
'
' A single datastorePut through StremioApiStore and nothing else. The full
' LibraryItem to write rides in m.top.item (built by
' LibraryStore.BuildLibraryChangeItem, which owns the merge into the freshest
' cached copy); this worker only sends it off the render thread. The envelope
' rules are the store's (and are unit-tested there).

sub init()
    m.top.functionName = "push"
end sub

sub push()
    try
        store = StremioApiStore(Transport(), m.top.authKey)
        result = store.LibraryPut(m.top.item, "Could not write library change")
        m.top.result = result
    catch e
        m.top.result = { ok: false, error: e.message }
    end try
end sub