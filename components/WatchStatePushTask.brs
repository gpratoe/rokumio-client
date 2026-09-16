' WatchStatePushTask — push one library item's watch state to the account.
'
' One POST datastorePut and nothing else. The full LibraryItem to write rides in
' m.top.item (built by LibraryStore.BuildWatchStateItem, which owns the merge
' into the freshest cached copy); this task only sends it. Success is the
' envelope's {result:{success:true}}; an error envelope or a transport failure
' surfaces as a failed result here, never a crash.

sub init()
    m.top.functionName = "push"
end sub

sub push()
    print "[rokumio] WatchStatePushTask starting"
    try
        http = Transport()
        res = http.Post("https://api.strem.io/api/datastorePut", { authKey: m.top.authKey, collection: "libraryItem", changes: [m.top.item] })
        if res.ok and res.json <> invalid
            print "[rokumio] WatchStatePushTask body=" + FormatJson(res.json)
        else
            print "[rokumio] WatchStatePushTask failed ok=" + res.ok.ToStr() + " error='" + res.error + "'"
        end if
        success = false
        if res.ok and res.json <> invalid and res.json.result <> invalid and res.json.result.success = true then success = true
        if success
            print "[rokumio] WatchStatePushTask success"
            m.top.result = { ok: true, error: "" }
            return
        end if
        error = "Could not write watch state"
        if res.ok and res.json <> invalid and res.json.error <> invalid and res.json.error.message <> invalid
            error = res.json.error.message
        end if
        print "[rokumio] WatchStatePushTask failed: " + error
        m.top.result = { ok: false, error: error }
    catch e
        print "[rokumio] WatchStatePushTask error: " + e.message
        m.top.result = { ok: false, error: e.message }
    end try
end sub