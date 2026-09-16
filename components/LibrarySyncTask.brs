' LibrarySyncTask — pull the account's library items off the UI thread.
'
' One POST datastoreGet and nothing else. The raw library item array is returned
' as-is; MainScene hands it to LibraryStore.SyncFromStremio, which owns all
' classification and mapping (continue watching / saved / stremioLibrary).
'
' Wire format (verified against the live API): the datastoreGet POST carries NO
' type tag — {"authKey":...,"collection":"libraryItem","all":true} — and every
' response is envelope-wrapped: {"result":[...]} on success. A bad authKey
' answers an error envelope; that surfaces as a failed result here, never a
' crash.

sub init()
    m.top.functionName = "sync"
end sub

sub sync()
    print "[rokumio] LibrarySyncTask starting"
    try
        http = Transport()
        res = http.Post("https://api.strem.io/api/datastoreGet", { authKey: m.top.authKey, collection: "libraryItem", all: true })
        if res.ok and res.json <> invalid
            print "[rokumio] LibrarySyncTask body=" + FormatJson(res.json)
        else
            print "[rokumio] LibrarySyncTask failed ok=" + res.ok.ToStr() + " error='" + res.error + "'"
        end if
        items = invalid
        if res.ok and res.json <> invalid then items = res.json.result
        if items = invalid or Type(items) <> "roArray"
            error = "Could not sync library"
            if res.ok and res.json <> invalid and res.json.error <> invalid and res.json.error.message <> invalid
                error = res.json.error.message
            end if
            m.top.result = { ok: false, items: [], error: error }
            return
        end if
        print "[rokumio] LibrarySyncTask items=" + items.Count().ToStr()
        m.top.result = { ok: true, items: items, error: "" }
    catch e
        print "[rokumio] LibrarySyncTask error: " + e.message
        m.top.result = { ok: false, items: [], error: e.message }
    end try
end sub