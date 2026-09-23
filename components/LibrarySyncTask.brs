' LibrarySyncTask — pull the account's library items off the UI thread.
'
' A single datastoreGet through StremioApiStore and nothing else. The raw
' library item array is returned as-is; MainScene hands it to
' LibraryStore.SyncFromStremio, which owns all classification and mapping
' (continue watching / saved / stremioLibrary). The wire format and envelope
' rules are the store's (and are unit-tested there); this worker only exists to
' keep the HTTP off the render thread.

sub init()
    m.top.functionName = "sync"
end sub

sub sync()
    print "[rokumio] LibrarySyncTask starting"
    try
        store = StremioApiStore(Transport(), m.top.authKey)
        result = store.LibraryGet()
        print "[rokumio] LibrarySyncTask items=" + result.items.Count().ToStr() + " ok=" + result.ok.ToStr()
        m.top.result = result
    catch e
        print "[rokumio] LibrarySyncTask error: " + e.message
        m.top.result = { ok: false, items: [], error: e.message }
    end try
end sub