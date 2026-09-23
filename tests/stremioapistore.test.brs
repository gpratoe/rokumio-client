' stremioapistore tests — the account-contact point every sync/push/logout worker
' now delegates its HTTP to. The five Task workers build their own Transport on a
' worker thread, so their requests were never injectable in this interpreter.
' Consolidating the wire format and envelope unwrapping here — with a transport
' passed in as a constructor argument — finally makes every failure channel unit
' testable: success envelopes, error-envelope messages, transport failures, the
' per-call fallback wording and the blank-authKey short-circuit.

sub Test_StremioApiStore_LibraryGetSuccessCarriesWireFormat()
    Harness_Suite("LibraryGet POSTs datastoreGet with authKey/collection/all and no type tag, returning raw items")
    script = [
        { method: "POST", url: "https://api.strem.io/api/datastoreGet", ok: true, status: 200, json: { result: [{ _id: "tt0133093", name: "The Matrix" }] } }
    ]
    http = ScriptedTransport(script)
    store = StremioApiStore(http, "sk_test_key")
    res = store.LibraryGet()
    Harness_Ok(res.ok, "request succeeds")
    Harness_Equal(res.error, "", "no error on success")
    Harness_Equal(res.items.Count(), 1, "items returned")
    Harness_Equal(res.items[0]._id, "tt0133093", "raw item carried through")
    Harness_Equal(http.log.Count(), 1, "one request logged")
    Harness_Equal(http.log[0].body.authKey, "sk_test_key", "request carries the authKey")
    Harness_Equal(http.log[0].body.collection, "libraryItem", "request targets the libraryItem collection")
    Harness_Equal(http.log[0].body.all, true, "request pulls everything")
    Harness_Equal(http.log[0].body.type, invalid, "no type tag on datastoreGet")
end sub

sub Test_StremioApiStore_LibraryGetEmptyLibrarySucceeds()
    Harness_Suite("LibraryGet treats an empty result array as a successful empty sync")
    script = [
        { method: "POST", url: "https://api.strem.io/api/datastoreGet", ok: true, status: 200, json: { result: [] } }
    ]
    http = ScriptedTransport(script)
    store = StremioApiStore(http, "sk_test_key")
    res = store.LibraryGet()
    Harness_Ok(res.ok, "empty library is a success")
    Harness_Equal(res.items.Count(), 0, "empty items array")
    Harness_Equal(res.error, "", "no error")
end sub

sub Test_StremioApiStore_LibraryGetErrorEnvelopeSurfacesMessage()
    Harness_Suite("LibraryGet surfaces an error envelope's message")
    script = [
        { method: "POST", url: "https://api.strem.io/api/datastoreGet", ok: true, status: 200, json: { error: { code: 1, message: "Session does not exist" } } }
    ]
    http = ScriptedTransport(script)
    store = StremioApiStore(http, "sk_test_key")
    res = store.LibraryGet()
    Harness_Ok(not res.ok, "request reports failure")
    Harness_Equal(res.items.Count(), 0, "empty items on failure")
    Harness_Equal(res.error, "Session does not exist", "error message surfaced")
end sub

sub Test_StremioApiStore_LibraryGetNetworkFailureFallsBack()
    Harness_Suite("LibraryGet falls back to default wording on a transport failure")
    script = [
        { method: "POST", url: "https://api.strem.io/api/datastoreGet", ok: false, status: 0, json: invalid, error: "connection refused" }
    ]
    http = ScriptedTransport(script)
    store = StremioApiStore(http, "sk_test_key")
    res = store.LibraryGet()
    Harness_Ok(not res.ok, "request fails")
    Harness_Equal(res.items.Count(), 0, "empty items on failure")
    Harness_Equal(res.error, "Could not sync library", "fallback wording used")
end sub

sub Test_StremioApiStore_LibraryGetNonArrayResultFails()
    Harness_Suite("LibraryGet rejects a result envelope that is not a list")
    script = [
        { method: "POST", url: "https://api.strem.io/api/datastoreGet", ok: true, status: 200, json: { result: { nonsense: true } } }
    ]
    http = ScriptedTransport(script)
    store = StremioApiStore(http, "sk_test_key")
    res = store.LibraryGet()
    Harness_Ok(not res.ok, "non-array result is a failure")
    Harness_Equal(res.items.Count(), 0, "empty items")
    Harness_Equal(res.error, "Could not sync library", "fallback wording used")
end sub

sub Test_StremioApiStore_LibraryPutSuccessCarriesWireFormat()
    Harness_Suite("LibraryPut POSTs datastorePut with authKey/collection/one change and no type tag")
    script = [
        { method: "POST", url: "https://api.strem.io/api/datastorePut", ok: true, status: 200, json: { result: { success: true } } }
    ]
    http = ScriptedTransport(script)
    store = StremioApiStore(http, "sk_test_key")
    res = store.LibraryPut({ _id: "tt0133093" }, "Could not write watch state")
    Harness_Ok(res.ok, "request succeeds")
    Harness_Equal(res.error, "", "no error on success")
    Harness_Equal(http.log.Count(), 1, "one request logged")
    Harness_Equal(http.log[0].body.authKey, "sk_test_key", "request carries the authKey")
    Harness_Equal(http.log[0].body.collection, "libraryItem", "request targets the libraryItem collection")
    Harness_Equal(http.log[0].body.changes.Count(), 1, "one change entry")
    Harness_Equal(http.log[0].body.changes[0]._id, "tt0133093", "change entry is the library item")
    Harness_Equal(http.log[0].body.type, invalid, "no type tag on datastorePut")
end sub

sub Test_StremioApiStore_LibraryPutErrorEnvelopeSurfacesMessage()
    Harness_Suite("LibraryPut surfaces an error envelope's message")
    script = [
        { method: "POST", url: "https://api.strem.io/api/datastorePut", ok: true, status: 200, json: { error: { code: 1, message: "Invalid authKey" } } }
    ]
    http = ScriptedTransport(script)
    store = StremioApiStore(http, "sk_test_key")
    res = store.LibraryPut({ _id: "tt0133093" }, "Could not write watch state")
    Harness_Ok(not res.ok, "request reports failure")
    Harness_Equal(res.error, "Invalid authKey", "error message surfaced")
end sub

sub Test_StremioApiStore_LibraryPutNetworkFailureKeepsCallerWording()
    Harness_Suite("LibraryPut falls back to the caller's wording on a transport failure")
    script = [
        { method: "POST", url: "https://api.strem.io/api/datastorePut", ok: false, status: 0, json: invalid, error: "connection refused" }
    ]
    http = ScriptedTransport(script)
    store = StremioApiStore(http, "sk_test_key")
    watch = store.LibraryPut({ _id: "tt0133093" }, "Could not write watch state")
    Harness_Equal(watch.ok, false, "watch-state write fails")
    Harness_Equal(watch.error, "Could not write watch state", "watch-state wording kept")
    change = store.LibraryPut({ _id: "tt0133093" }, "Could not write library change")
    Harness_Equal(change.ok, false, "library change write fails")
    Harness_Equal(change.error, "Could not write library change", "library change wording kept")
end sub

sub Test_StremioApiStore_AddonCollectionGetSuccessCarriesWireFormat()
    Harness_Suite("AddonCollectionGet POSTs the type-tagged body and maps descriptors from the envelope")
    script = [
        { method: "POST", url: "https://api.strem.io/api/addonCollectionGet", ok: true, status: 200, json: { result: { addons: [{ transportUrl: "https://cdn.example.com/manifest.json", manifest: { id: "com.example" } }] } } }
    ]
    http = ScriptedTransport(script)
    store = StremioApiStore(http, "sk_test_key")
    res = store.AddonCollectionGet()
    Harness_Ok(res.ok, "request succeeds")
    Harness_Equal(res.error, "", "no error on success")
    Harness_Equal(res.descriptors.Count(), 1, "one descriptor")
    Harness_Equal(res.descriptors[0].transportUrl, "https://cdn.example.com/manifest.json", "transport URL mapped")
    Harness_Equal(res.descriptors[0].manifest.id, "com.example", "manifest mapped")
    Harness_Equal(http.log.Count(), 1, "one request logged")
    Harness_Equal(http.log[0].body.type, "AddonCollectionGet", "request carries the type tag")
    Harness_Equal(http.log[0].body.authKey, "sk_test_key", "request carries the authKey")
    Harness_Equal(http.log[0].body.update, true, "request forces an update")
end sub

sub Test_StremioApiStore_AddonCollectionGetMissingTransportFallsBackToBlank()
    Harness_Suite("AddonCollectionGet maps a missing transport URL to a blank string")
    script = [
        { method: "POST", url: "https://api.strem.io/api/addonCollectionGet", ok: true, status: 200, json: { result: { addons: [{ manifest: { id: "com.naked" } }] } } }
    ]
    http = ScriptedTransport(script)
    store = StremioApiStore(http, "sk_test_key")
    res = store.AddonCollectionGet()
    Harness_Ok(res.ok, "request succeeds")
    Harness_Equal(res.descriptors.Count(), 1, "one descriptor")
    Harness_Equal(res.descriptors[0].transportUrl, "", "blank transport URL")
    Harness_Equal(res.descriptors[0].manifest.id, "com.naked", "manifest mapped")
end sub

sub Test_StremioApiStore_AddonCollectionGetErrorEnvelopeSurfacesMessage()
    Harness_Suite("AddonCollectionGet surfaces an error envelope's message")
    script = [
        { method: "POST", url: "https://api.strem.io/api/addonCollectionGet", ok: true, status: 200, json: { error: { code: 1, message: "Session does not exist" } } }
    ]
    http = ScriptedTransport(script)
    store = StremioApiStore(http, "sk_test_key")
    res = store.AddonCollectionGet()
    Harness_Ok(not res.ok, "request reports failure")
    Harness_Equal(res.descriptors.Count(), 0, "empty descriptors on failure")
    Harness_Equal(res.error, "Session does not exist", "error message surfaced")
end sub

sub Test_StremioApiStore_AddonCollectionGetNetworkFailureFallsBack()
    Harness_Suite("AddonCollectionGet falls back on a transport failure")
    script = [
        { method: "POST", url: "https://api.strem.io/api/addonCollectionGet", ok: false, status: 0, json: invalid, error: "connection refused" }
    ]
    http = ScriptedTransport(script)
    store = StremioApiStore(http, "sk_test_key")
    res = store.AddonCollectionGet()
    Harness_Ok(not res.ok, "request fails")
    Harness_Equal(res.descriptors.Count(), 0, "empty descriptors")
    Harness_Equal(res.error, "Could not sync addons", "fallback wording used")
end sub

sub Test_StremioApiStore_AddonCollectionGetMissingAddonsFails()
    Harness_Suite("AddonCollectionGet rejects an envelope missing the addons list")
    script = [
        { method: "POST", url: "https://api.strem.io/api/addonCollectionGet", ok: true, status: 200, json: { result: { lastModified: "2026-09-15T00:00:00Z" } } }
    ]
    http = ScriptedTransport(script)
    store = StremioApiStore(http, "sk_test_key")
    res = store.AddonCollectionGet()
    Harness_Ok(not res.ok, "missing addons is a failure")
    Harness_Equal(res.descriptors.Count(), 0, "empty descriptors")
    Harness_Equal(res.error, "Could not sync addons", "fallback wording used")
end sub

sub Test_StremioApiStore_LogoutSuccessCarriesWireFormat()
    Harness_Suite("Logout POSTs /api/logout with authKey and the Logout type tag")
    script = [
        { method: "POST", url: "https://api.strem.io/api/logout", ok: true, status: 200, json: { result: { success: true } } }
    ]
    http = ScriptedTransport(script)
    store = StremioApiStore(http, "sk_test_key")
    res = store.Logout()
    Harness_Ok(res.ok, "request succeeds")
    Harness_Equal(res.error, "", "no error on success")
    Harness_Equal(http.log.Count(), 1, "one request logged")
    Harness_Equal(http.log[0].body.authKey, "sk_test_key", "request carries the authKey")
    Harness_Equal(http.log[0].body.type, "Logout", "request carries the type tag")
end sub

sub Test_StremioApiStore_LogoutErrorEnvelopeSurfacesMessage()
    Harness_Suite("Logout surfaces an error envelope's message")
    script = [
        { method: "POST", url: "https://api.strem.io/api/logout", ok: true, status: 200, json: { error: { code: 1, message: "Session does not exist" } } }
    ]
    http = ScriptedTransport(script)
    store = StremioApiStore(http, "sk_test_key")
    res = store.Logout()
    Harness_Ok(not res.ok, "request reports failure")
    Harness_Equal(res.error, "Session does not exist", "error message surfaced")
end sub

sub Test_StremioApiStore_LogoutNetworkFailureFallsBack()
    Harness_Suite("Logout falls back on a transport failure")
    script = [
        { method: "POST", url: "https://api.strem.io/api/logout", ok: false, status: 0, json: invalid, error: "connection refused" }
    ]
    http = ScriptedTransport(script)
    store = StremioApiStore(http, "sk_test_key")
    res = store.Logout()
    Harness_Ok(not res.ok, "request fails")
    Harness_Equal(res.error, "Could not log out of the account", "fallback wording used")
end sub

sub Test_StremioApiStore_LogoutBlankAuthKeyShortCircuits()
    Harness_Suite("Logout with a blank authKey short-circuits to success without a request")
    http = ScriptedTransport([])
    store = StremioApiStore(http, "")
    res = store.Logout()
    Harness_Ok(res.ok, "nothing to revoke is a success")
    Harness_Equal(res.error, "", "no error")
    Harness_Equal(http.log.Count(), 0, "no request attempted")
end sub