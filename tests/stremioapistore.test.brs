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
    Harness_Suite("Logout POSTs /api/logout with only the authKey")
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
    Harness_Equal(http.log[0].body.type, invalid, "endpoint path identifies logout; no type tag is sent")
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

sub Test_StremioApiStore_IsSessionRevokedOnSessionMissing()
    Harness_Suite("IsSessionRevoked flags the Session does not exist envelope")
    store = StremioApiStore(ScriptedTransport([]), "sk_test_key")
    res = { ok: true, json: { error: { code: 1, message: "Session does not exist" } } }
    Harness_Ok(store.IsSessionRevoked(res), "session-deleted error detected")
end sub

sub Test_StremioApiStore_IsSessionRevokedVariants()
    Harness_Suite("IsSessionRevoked flags revoke-style wording regardless of case")
    store = StremioApiStore(ScriptedTransport([]), "sk_test_key")
    cases = [
        { message: "session has expired", got: false }
        { message: "Logged out: this session is no longer active", got: false }
        { message: "SESSION REVOKED from the account", got: false }
        { message: "session not found", got: false }
    ]
    for i = 0 to cases.Count() - 1
        res = { ok: true, json: { error: { code: 1, message: cases[i].message } } }
        cases[i].got = store.IsSessionRevoked(res)
    end for
    Harness_Equal(cases[0].got, true, "expired detected")
    Harness_Equal(cases[1].got, true, "logged out detected")
    Harness_Equal(cases[2].got, true, "upper-case revoked detected")
    Harness_Equal(cases[3].got, true, "not found detected")
end sub

sub Test_StremioApiStore_IsSessionRevokedGenericErrorFalse()
    Harness_Suite("IsSessionRevoked leaves generic server errors alone")
    store = StremioApiStore(ScriptedTransport([]), "sk_test_key")
    generic = { ok: true, json: { error: { code: 1, message: "Internal server error" } } }
    Harness_Equal(store.IsSessionRevoked(generic), false, "generic error not a revocation")
    invalidAuth = { ok: true, json: { error: { code: 1, message: "Invalid authKey" } } }
    Harness_Equal(store.IsSessionRevoked(invalidAuth), false, "unrelated auth wording ignored")
end sub

sub Test_StremioApiStore_IsSessionRevokedFailuresFalse()
    Harness_Suite("IsSessionRevoked is never true for non-error responses")
    store = StremioApiStore(ScriptedTransport([]), "sk_test_key")
    success = { ok: true, json: { result: { success: true } } }
    Harness_Equal(store.IsSessionRevoked(success), false, "success envelope ignored")
    network = { ok: false, status: 0, json: invalid, error: "connection refused" }
    Harness_Equal(store.IsSessionRevoked(network), false, "transport failure ignored")
    blank = { ok: true, json: { result: {} } }
    Harness_Equal(store.IsSessionRevoked(blank), false, "no error envelope ignored")
end sub

sub Test_StremioApiStore_LibraryGetTagsRevokedSession()
    Harness_Suite("LibraryGet flags a revoked-session error envelope for the caller")
    script = [
        { method: "POST", url: "https://api.strem.io/api/datastoreGet", ok: true, status: 200, json: { error: { code: 1, message: "Session does not exist" } } }
    ]
    http = ScriptedTransport(script)
    store = StremioApiStore(http, "sk_test_key")
    res = store.LibraryGet()
    Harness_Ok(not res.ok, "request reports failure")
    Harness_Equal(res.revokedSession, true, "revoked-session flag set")
end sub

sub Test_StremioApiStore_LibraryGetSuccessNotTagged()
    Harness_Suite("LibraryGet makes the revoked-session flag explicit on success")
    script = [
        { method: "POST", url: "https://api.strem.io/api/datastoreGet", ok: true, status: 200, json: { result: [] } }
    ]
    http = ScriptedTransport(script)
    store = StremioApiStore(http, "sk_test_key")
    res = store.LibraryGet()
    Harness_Ok(res.ok, "request succeeds")
    Harness_Equal(res.revokedSession, false, "not a revoked session")
end sub

sub Test_StremioApiStore_AddonGetTagsRevokedSession()
    Harness_Suite("AddonCollectionGet flags a revoked-session error envelope for the caller")
    script = [
        { method: "POST", url: "https://api.strem.io/api/addonCollectionGet", ok: true, status: 200, json: { error: { code: 1, message: "Session does not exist" } } }
    ]
    http = ScriptedTransport(script)
    store = StremioApiStore(http, "sk_test_key")
    res = store.AddonCollectionGet()
    Harness_Ok(not res.ok, "request reports failure")
    Harness_Equal(res.revokedSession, true, "revoked-session flag set")
end sub
' The pull also carries the collection in the official wire shape — the exact
' payload addonCollectionSet sends back. Extras the server adds (installType,
' transportName) are dropped, matching what stremio-core's own
' deserialize-reserialize cycle does before it pushes.
sub Test_StremioApiStore_AddonCollectionGetCarriesRawEntries()
    Harness_Suite("AddonCollectionGet returns collection entries in the official set shape")
    script = [
        { method: "POST", url: "https://api.strem.io/api/addonCollectionGet", ok: true, status: 200, json: { result: { addons: [
            { manifest: { id: "com.example" }, transportUrl: "https://cdn.example.com/manifest.json", flags: { official: true } },
            { manifest: { id: "com.extra" }, transportUrl: "https://extra.example.com/manifest.json", installType: "add", transportName: "HTTP" },
            { manifest: { id: "com.dup" }, transportUrl: "https://dup.example.com/manifest.json" },
            { manifest: { id: "com.dup" }, transportUrl: "https://dup.example.com/manifest.json" },
            { manifest: { id: "com.naked" } }
        ] } } }
    ]
    http = ScriptedTransport(script)
    store = StremioApiStore(http, "sk_test_key")
    res = store.AddonCollectionGet()
    Harness_Ok(res.ok, "request succeeds")
    Harness_Equal(res.raw.Count(), 3, "entries deduped by transportUrl and unusable ones dropped")
    Harness_Equal(res.raw[0].flags.official, true, "official flag carried")
    Harness_Equal(res.raw[0].flags.protected, false, "missing protected flag defaults false")
    Harness_Equal(res.raw[1].installType, invalid, "installType machine field dropped")
    Harness_Equal(res.raw[1].flags.official, false, "missing flags default to non-official")
    Harness_Equal(res.raw[2].manifest.id, "com.dup", "first duplicate wins")
end sub

sub Test_StremioApiStore_AddonCollectionSetCarriesWireFormat()
    Harness_Suite("AddonCollectionSet POSTs the type-tagged body with the addons array and reads result.success")
    addons = [{ manifest: { id: "com.example" }, transportUrl: "https://cdn.example.com/manifest.json", flags: { official: true, protected: false } }]
    script = [
        { method: "POST", url: "https://api.strem.io/api/addonCollectionSet", ok: true, status: 200, json: { result: { success: true } } }
    ]
    http = ScriptedTransport(script)
    store = StremioApiStore(http, "sk_test_key")
    res = store.AddonCollectionSet(addons)
    Harness_Ok(res.ok, "set succeeds")
    Harness_Equal(res.error, "", "no error on success")
    Harness_Equal(res.revokedSession, false, "not a revoked session")
    Harness_Equal(http.log.Count(), 1, "one request logged")
    Harness_Equal(http.log[0].url, "https://api.strem.io/api/addonCollectionSet", "targets the collection-set endpoint")
    Harness_Equal(http.log[0].body.type, "AddonCollectionSet", "request carries the type tag")
    Harness_Equal(http.log[0].body.authKey, "sk_test_key", "request carries the authKey")
    Harness_Equal(http.log[0].body.addons.Count(), 1, "payload carries the addons array")
    Harness_Equal(http.log[0].body.addons[0].manifest.id, "com.example", "manifest passes through verbatim")
    Harness_Equal(http.log[0].body.addons[0].flags.official, true, "flags pass through verbatim")
end sub

sub Test_StremioApiStore_AddonCollectionSetErrorEnvelopeSurfacesMessage()
    Harness_Suite("AddonCollectionSet surfaces an error envelope's message")
    script = [
        { method: "POST", url: "https://api.strem.io/api/addonCollectionSet", ok: true, status: 200, json: { error: { code: 1, message: "Collection rejected" } } }
    ]
    http = ScriptedTransport(script)
    store = StremioApiStore(http, "sk_test_key")
    res = store.AddonCollectionSet([{ manifest: { id: "com.example" }, transportUrl: "https://x/manifest.json", flags: { official: false, protected: false } }])
    Harness_Ok(not res.ok, "set reports failure")
    Harness_Equal(res.error, "Collection rejected", "error message surfaced")
    Harness_Equal(res.revokedSession, false, "generic failure not marked revoked")
end sub

sub Test_StremioApiStore_AddonCollectionSetTagsRevokedSession()
    Harness_Suite("AddonCollectionSet flags a revoked-session error envelope for the caller")
    script = [
        { method: "POST", url: "https://api.strem.io/api/addonCollectionSet", ok: true, status: 200, json: { error: { code: 1, message: "Session expired" } } }
    ]
    http = ScriptedTransport(script)
    store = StremioApiStore(http, "sk_test_key")
    res = store.AddonCollectionSet([])
    Harness_Ok(not res.ok, "set reports failure")
    Harness_Equal(res.revokedSession, true, "revoked-session flag set")
end sub

sub Test_StremioApiStore_AddonCollectionSetTransportFailureFallsBack()
    Harness_Suite("AddonCollectionSet falls back to default wording on a transport failure")
    script = [
        { method: "POST", url: "https://api.strem.io/api/addonCollectionSet", ok: false, status: 0, json: invalid, error: "connection refused" }
    ]
    http = ScriptedTransport(script)
    store = StremioApiStore(http, "sk_test_key")
    res = store.AddonCollectionSet([])
    Harness_Ok(not res.ok, "set reports failure")
    Harness_Equal(res.error, "Could not update the account's add-ons", "fallback wording kept")
    Harness_Equal(res.revokedSession, false, "transport failure not marked revoked")
end sub
