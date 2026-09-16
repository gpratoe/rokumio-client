' librarywritepush tests — the two testable halves of the library write-back
' pipeline: the datastorePut wire format (through ScriptedTransport) and
' LibraryStore.BuildLibraryChangeItem (the merge that turns an add/remove toggle
' into a full LibraryItem to push). The LibraryWritePushTask worker itself runs
' its own Transport on a task thread (like WatchStatePushTask), so its HTTP
' cannot be injected here; MainScene's coalescing is pure orchestration with no
' runnable unit surface in the interpreter — the store merge and the wire format
' are the contracts that pin it, mirroring the watchstatepush suite.

' A datastoreGet library item shape (same family as the watchstatepush fixture) —
' the BuildLibraryChangeItem merge must preserve every field it does not
' overwrite.
function LibraryChangeItemFixture(metaId as string, metaType as string, name as string, mtime as string) as object
    return {
        _id: metaId
        type: metaType
        name: name
        poster: "https://img.example.com/" + metaId + ".png"
        removed: false
        temp: false
        _ctime: "2024-01-01T00:00:00Z"
        _mtime: mtime
        state: {
            timeOffset: 0
            duration: 0
            timesWatched: 3
            watched: invalid
        }
        behaviorHints: { defaultVideoId: invalid }
    }
end function

sub Test_LibraryWritePush_PostsDatastorePutWithoutTypeTag()
    Harness_Suite("datastorePut POST body carries authKey/collection/changes and no type tag")
    script = [
        {
            method: "POST"
            url: "https://api.strem.io/api/datastorePut"
            ok: true
            status: 200
            json: { result: { success: true } }
        }
    ]
    http = ScriptedTransport(script)
    item = { _id: "tt0133093", removed: false, temp: false }
    res = http.Post("https://api.strem.io/api/datastorePut", { authKey: "sk_test_key", collection: "libraryItem", changes: [item] })
    Harness_Ok(res.ok, "request succeeds")
    Harness_Ok(res.json.result.success, "result envelope reports success")
    Harness_Equal(http.log.Count(), 1, "one request logged")
    Harness_Equal(http.log[0].body.authKey, "sk_test_key", "request carries the authKey")
    Harness_Equal(http.log[0].body.collection, "libraryItem", "request targets the libraryItem collection")
    Harness_Equal(http.log[0].body.changes.Count(), 1, "one change entry")
    Harness_Equal(http.log[0].body.changes[0]._id, "tt0133093", "change entry is the library item")
    Harness_Equal(http.log[0].body.type, invalid, "no type tag on datastorePut")
end sub

sub Test_LibraryWritePush_AddClonesCachedItemAndFlagsSaved()
    Harness_Suite("BuildLibraryChangeItem clones the cached item with removed:false/temp:false for an add")
    items = []
    items.Push(LibraryChangeItemFixture("tt1234567", "series", "Breaking Bad", "2024-06-01T00:00:00Z"))
    store = LibraryStore(MockRegistry(), "stremio")
    store.SyncFromStremio(items)

    item = store.BuildLibraryChangeItem("tt1234567", "series", "Breaking Bad", "https://img.example.com/tt1234567.png", true, "2026-09-16T12:00:00Z")
    Harness_Ok(item <> invalid, "item built")
    Harness_Equal(item._id, "tt1234567", "meta id kept")
    Harness_Equal(item.type, "series", "type kept")
    Harness_Equal(item.removed, false, "add is removed:false")
    Harness_Equal(item.temp, false, "add is temp:false")
    Harness_Equal(item._mtime, "2026-09-16T12:00:00Z", "mtime stamped")
    Harness_Equal(item.state.timesWatched, 3, "untracked server field preserved")
    Harness_Equal(item.name, "Breaking Bad", "name carried")
end sub

sub Test_LibraryWritePush_RemoveFlagsRemoved()
    Harness_Suite("BuildLibraryChangeItem flags removed:true/temp:false for a remove")
    items = []
    items.Push(LibraryChangeItemFixture("tt0133093", "movie", "The Matrix", "2024-06-10T00:00:00Z"))
    store = LibraryStore(MockRegistry(), "stremio")
    store.SyncFromStremio(items)

    item = store.BuildLibraryChangeItem("tt0133093", "movie", "The Matrix", "https://img.example.com/tt0133093.png", false, "2026-09-16T12:00:00Z")
    Harness_Ok(item <> invalid, "item built")
    Harness_Equal(item.removed, true, "remove is removed:true")
    Harness_Equal(item.temp, false, "remove is temp:false (id stays, just marked removed)")
    Harness_Equal(item._mtime, "2026-09-16T12:00:00Z", "mtime stamped")
    Harness_Equal(item._id, "tt0133093", "meta id kept")
end sub

sub Test_LibraryWritePush_ReaddClearsRemovedFlag()
    Harness_Suite("BuildLibraryChangeItem re-adds the same id with removed:false")
    items = []
    fixture = LibraryChangeItemFixture("tt0133093", "movie", "The Matrix", "2024-06-10T00:00:00Z")
    fixture.removed = true
    items.Push(fixture)
    store = LibraryStore(MockRegistry(), "stremio")
    store.SyncFromStremio(items)

    item = store.BuildLibraryChangeItem("tt0133093", "movie", "The Matrix", "https://img.example.com/tt0133093.png", true, "2026-09-16T12:00:00Z")
    Harness_Ok(item <> invalid, "item built")
    Harness_Equal(item.removed, false, "re-add flips the cached removed flag back to false")
    Harness_Equal(item.temp, false, "temp stays false")
    Harness_Equal(item._id, "tt0133093", "id unchanged — same item, re-added")
end sub

sub Test_LibraryWritePush_UnknownMetaFallsBackToMinimal()
    Harness_Suite("BuildLibraryChangeItem builds a minimal record for metas the cache has never seen")
    store = LibraryStore(MockRegistry(), "stremio")
    item = store.BuildLibraryChangeItem("tt9999999", "movie", "New Arrival", "https://img.example.com/tt9999999.png", true, "2026-09-16T12:00:00Z")
    Harness_Ok(item <> invalid, "item built")
    Harness_Equal(item._id, "tt9999999", "meta id set")
    Harness_Equal(item.type, "movie", "type set")
    Harness_Equal(item.name, "New Arrival", "name set")
    Harness_Equal(item.poster, "https://img.example.com/tt9999999.png", "poster set")
    Harness_Equal(item.removed, false, "minimal add is removed:false")
    Harness_Equal(item.temp, false, "minimal add is temp:false")
    Harness_Equal(item._mtime, "2026-09-16T12:00:00Z", "mtime stamped")
end sub

sub Test_LibraryWritePush_DoesNotMutateCachedItem()
    Harness_Suite("BuildLibraryChangeItem leaves the cached copy untouched")
    items = []
    items.Push(LibraryChangeItemFixture("tt1234567", "series", "Breaking Bad", "2024-06-01T00:00:00Z"))
    store = LibraryStore(MockRegistry(), "stremio")
    store.SyncFromStremio(items)
    item = store.BuildLibraryChangeItem("tt1234567", "series", "Breaking Bad", "https://img.example.com/tt1234567.png", false, "2026-09-16T12:00:00Z")
    Harness_Ok(item <> invalid, "item built")
    Harness_Equal(item.removed, true, "built item carries the remove flag")
    cached = store.StremioLibraryItems()[0]
    Harness_Equal(cached.removed, false, "cached removed flag unchanged")
    Harness_Equal(cached._mtime, "2024-06-01T00:00:00Z", "cached mtime unchanged")
end sub

sub Test_LibraryWritePush_GuestSessionRefused()
    Harness_Suite("BuildLibraryChangeItem refuses a guest session")
    store = LibraryStore(MockRegistry())
    item = store.BuildLibraryChangeItem("tt0133093", "movie", "The Matrix", "https://img.example.com/tt0133093.png", true, "2026-09-16T12:00:00Z")
    Harness_Equal(item, invalid, "guest store returns invalid, never pushes")
end sub

sub Test_LibraryWritePush_TimestampAutoStampedWhenOmitted()
    Harness_Suite("BuildLibraryChangeItem stamps an ISO timestamp when now is not given")
    store = LibraryStore(MockRegistry(), "stremio")
    item = store.BuildLibraryChangeItem("tt0133093", "movie", "The Matrix", "https://img.example.com/tt0133093.png", true, "")
    Harness_Ok(item <> invalid, "item built")
    Harness_Ok(item._mtime <> "", "mtime auto-stamped")
end sub

sub Test_LibraryWritePush_MetaIdRequired()
    Harness_Suite("BuildLibraryChangeItem requires a meta id")
    store = LibraryStore(MockRegistry(), "stremio")
    Harness_Equal(store.BuildLibraryChangeItem("", "movie", "The Matrix", "", true, "2026-09-16T12:00:00Z"), invalid, "blank meta id refused")
end sub