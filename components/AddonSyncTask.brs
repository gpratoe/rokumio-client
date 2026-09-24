' AddonSyncTask — pull the account's addon collection off the UI thread.
'
' A single addonCollectionGet through StremioApiStore and nothing else. The
' descriptors (transport URL + manifest, straight from the API) are returned
' as-is; MainScene adopts each one through AddonsStore, which stays the single
' writer for installed records. The wire format and envelope rules are the
' store's (and are unit-tested there); this worker only exists to keep the HTTP
' off the render thread.

sub init()
    m.top.functionName = "sync"
end sub

sub sync()
    try
        store = StremioApiStore(Transport(), m.top.authKey)
        result = store.AddonCollectionGet()
        m.top.result = result
    catch e
        m.top.result = { ok: false, descriptors: [], error: e.message }
    end try
end sub