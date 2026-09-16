' AddonSyncTask — pull the account's addon collection off the UI thread.
'
' One POST addonCollectionGet and nothing else. The descriptors (transport URL
' + manifest, straight from the API) are returned as-is; MainScene adopts each
' one through AddonsStore, which stays the single writer for installed records.
'
' Wire format (verified live against the API + stremio-core): the body carries
' the type tag — {"type":"AddonCollectionGet","authKey":...,"update":true} —
' and every response is envelope-wrapped: {"result":{"addons":[...],"lastModified":...}}
' on success. A bad authKey answers an error envelope; that surfaces as a failed
' result here, never a crash.

sub init()
    m.top.functionName = "sync"
end sub

sub sync()
    print "[rokumio] AddonSyncTask starting"
    try
        http = Transport()
        res = http.Post("https://api.strem.io/api/addonCollectionGet", { type: "AddonCollectionGet", authKey: m.top.authKey, update: true })
        if res.ok and res.json <> invalid
            print "[rokumio] AddonSyncTask body=" + FormatJson(res.json)
        else
            print "[rokumio] AddonSyncTask failed ok=" + res.ok.ToStr() + " error='" + res.error + "'"
        end if
        result = invalid
        if res.ok and res.json <> invalid then result = res.json.result
        if result = invalid or result.addons = invalid or Type(result.addons) <> "roArray"
            error = "Could not sync addons"
            if res.ok and res.json <> invalid and res.json.error <> invalid and res.json.error.message <> invalid
                error = res.json.error.message
            end if
            m.top.result = { ok: false, descriptors: [], error: error }
            return
        end if
        descriptors = []
        for each addon in result.addons
            packet = { transportUrl: "", manifest: invalid }
            if addon.transportUrl <> invalid then packet.transportUrl = addon.transportUrl
            if addon.manifest <> invalid then packet.manifest = addon.manifest
            descriptors.Push(packet)
        end for
        print "[rokumio] AddonSyncTask descriptors=" + descriptors.Count().ToStr()
        m.top.result = { ok: true, descriptors: descriptors, error: "" }
    catch e
        print "[rokumio] AddonSyncTask error: " + e.message
        m.top.result = { ok: false, descriptors: [], error: e.message }
    end try
end sub