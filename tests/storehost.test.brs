' StoreHost adapter tests — the callFunc boundary between the screens and the
' stores.
'
' Roku casts callFunc arguments onto the adapter's declared parameter types, so
' a typed String parameter rejects the roInvalid a raw add-on catalog meta can
' carry with &h18 "Unable to cast" — the v0.3.1 channel-killer: one meta without
' an id or type anywhere in any installed add-on's catalog crashed Home in
' MakeRowNode on every launch, with no try/catch anywhere on the path. These
' suites run the REAL adapter functions with the invalid inputs the screens
' actually hand over; before the un-typing they died in the signature, not in
' an assertion.

sub Test_StoreHost_GlyphAdapter_ToleratesInvalid()
    Harness_Suite("StoreHost.LibraryWatchedGlyph survives a meta without id/type")
    store = LibraryStore(MockRegistry())
    m.stores = { library: store }

    Harness_Equal(LibraryWatchedGlyph(invalid, invalid), "", "no id, no type: no badge, no crash")
    Harness_Equal(LibraryWatchedGlyph("", "movie"), "", "blank id: no badge")
    Harness_Equal(LibraryWatchedGlyph(invalid, "series"), "", "no id: no badge even when the type says series")

    ' Coercion must not swallow real values: a watched id still answers through
    ' the adapter, and the type falling back stays the store's own rule.
    store.MarkWatchedIfFinished("ttQW", "ttQW", 800, 1000)
    Harness_Equal(LibraryWatchedGlyph("ttQW", "movie"), "eye", "a watched movie still answers GLYPH_WATCHED")
    Harness_Equal(LibraryWatchedGlyph("ttQW", invalid), "eye", "invalid type falls back to the whole-key watch check")
    Harness_Equal(LibraryWatchedGlyph("ttNE", "movie"), "", "an unwatched id still answers no badge")
    Harness_Equal(LibraryWatchedGlyph(ParseJson("777"), "movie"), "", "a numeric id coerces and answers as unwatched")

    m.stores = invalid
end sub

sub Test_StoreHost_ProgressAdapter_ToleratesInvalid()
    Harness_Suite("StoreHost.LibraryProgressFraction survives a meta without id")
    store = LibraryStore(MockRegistry())
    m.stores = { library: store }

    Harness_Ok(LibraryProgressFraction(invalid) = invalid, "no id: no bar, no crash")
    Harness_Ok(LibraryProgressFraction("") = invalid, "blank id: no bar")
    Harness_Ok(LibraryProgressFraction("ttNE") = invalid, "unknown id: no bar")

    store.SetPosition("ttQW:1:1", "ttQW", "series", 1, 1, "Pilot", "", 450, 1800)
    Harness_Equal(LibraryProgressFraction("ttQW"), 0.25, "a real position still answers the clamped fraction")

    m.stores = invalid
end sub

sub Test_StoreHost_SavedAdapters_TolerateInvalid()
    Harness_Suite("StoreHost saved-item adapters survive meta values that are not text")
    store = LibraryStore(MockRegistry())
    m.stores = { library: store }

    ' Reads: invalid degrades to a clean "no".
    Harness_Ok(not LibraryIsSaved(invalid), "IsSaved with no id is false, no crash")
    Harness_Ok(not LibraryRemoveSaved(invalid), "RemoveSaved with no id is false, no crash")
    Harness_Ok(LibraryResumeFor(invalid) = invalid, "ResumeFor with no id is no resume, no crash")

    ' Writes: the Details "+ Library" action feeds meta fields straight in; a
    ' meta without an id must refuse the save, not kill the channel.
    Harness_Ok(not LibraryAddSaved(invalid, "movie", "No Id"), "AddSaved with no id refuses")
    Harness_Ok(not LibraryIsSaved(""), "blank id is not saved")
    Harness_Ok(LibraryAddSaved("ttQW", invalid, "Ok"), "AddSaved with an id but no type still saves")
    Harness_Ok(LibraryIsSaved("ttQW"), "the real save landed")
    Harness_Ok(LibraryRemoveSaved("ttQW"), "the real save removes")
    Harness_Ok(not LibraryIsSaved("ttQW"), "and it is gone")

    m.stores = invalid
end sub

sub Test_StoreHost_MarkAdapters_TolerateInvalid()
    Harness_Suite("StoreHost mark/state adapters survive meta values that are not text")
    store = LibraryStore(MockRegistry())
    m.stores = { library: store }

    ' Every writer is a no-op on a non-text id, not a cast crash — the marks
    ' path (Episodes badges) runs on every episode list the user opens.
    LibraryMarkAllIfDone(invalid, true, true)
    LibraryMarkAllIfDone("", true, true)
    LibraryMarkEpisodeWatched(invalid, invalid)
    LibraryMarkEpisodeUnwatched(invalid, invalid)
    LibraryMarkUpToWatched(invalid, [], 0)
    LibraryMarkUpToUnwatched(invalid, [], 0)
    LibraryMarkWatchedIfFinished(invalid, invalid, 900, 1000)
    LibraryMarkWatchedIfFinished("ttQW", invalid, 900, 1000)
    Harness_Ok(store.IsWatched("ttQW"), "a meta id alone still records the watch when it is text")

    fresh = LibraryStore(MockRegistry())
    m.stores.library = fresh
    LibraryMarkWatchedIfFinished(invalid, "ttQW:1:2", 900, 1000)
    Harness_Ok(fresh.IsWatched("ttQW:1:2"), "a video id alone still records the watch when it is text")
    LibraryMarkEpisodeWatched("ttQW", "ttQW:1:1")
    Harness_Ok(fresh.IsWatched("ttQW:1:1"), "a real mark still lands through the adapter")

    m.stores = invalid
end sub

sub Test_StoreHost_EpisodeMarkAdapters_TolerateInvalid()
    Harness_Suite("StoreHost episode-mark adapters survive a meta without id")
    store = LibraryStore(MockRegistry(), "stremio")
    m.stores = { library: store }
    ep = { name: "Pilot", season: 1, episode: 2, released: "2020-04-01" }

    mark = LibraryEpisodeMark(invalid, 1, ep, [], "2024-06-01T00:00:00Z")
    Harness_Ok(mark <> invalid and not mark.aired and not mark.watched, "no id: a safe mark, no crash")

    marks = LibraryEpisodeMarks(invalid, 1, [ep], [], "2024-06-01T00:00:00Z")
    Harness_Ok(marks <> invalid and marks.Count() = 1 and not marks[0].aired, "no id: safe marks for the run")

    runMarks = LibraryEpisodeMarksForSeries(invalid, [{ season: 1, episodes: [ep] }], [], "2024-06-01T00:00:00Z")
    Harness_Ok(runMarks <> invalid and runMarks.Count() = 1, "no id: safe marks for the series")

    ' The real path still answers through the adapter: aired is decodable and
    ' the watched bit comes from the store once the id is text.
    mark = LibraryEpisodeMark("ttQW", 1, ep, [], "2024-06-01T00:00:00Z")
    Harness_Ok(mark.aired, "a real id still decodes the airdate")
    Harness_Ok(not mark.watched, "an unwatched real id still answers unwatched")

    m.stores = invalid
end sub

sub Test_StoreHost_EpisodesIdAdapters_TolerateInvalid()
    Harness_Suite("StoreHost Episodes id adapters survive a meta without id")
    ' The Details play/resume path feeds m.meta.id into these; the push tripwires
    ' keep idless metas off Details, so these adapters are the layer behind the
    ' tripwire — the crash class must be dead there too, not merely fenced.
    store = EpisodesStore(ScriptedTransport([]))
    m.stores = { episodes: store }

    Harness_Equal(EpisodesResolveVideoId(invalid, 1, 2), "", "no id resolves no video, no crash")
    Harness_Equal(EpisodesResolveVideoId("", 1, 2), "", "blank id resolves no video")
    Harness_Equal(EpisodesResolveVideoId("ttQW", 1, 2), "ttQW:1:2", "a real id still builds the video id")
    Harness_Equal(EpisodesResolveVideoId("ttQW", 1, invalid), "", "invalid episode resolves no video, no crash")
    Harness_Equal(EpisodesResolveVideoId("ttQW", invalid, 2), "", "invalid season resolves no video, no crash")
    Harness_Equal(EpisodesResolveVideoId("ttQW", invalid, invalid), "", "invalid season and episode resolve no video, no crash")

    Harness_Equal(EpisodesEpisodeVideoId("ttQW", { id: "ttQW:3:4", season: 3, episode: 4 }), "ttQW:3:4", "episode helper prefers the video's own id")
    Harness_Equal(EpisodesEpisodeVideoId("ttQW", { season: 1, episode: 2 }), "ttQW:1:2", "episode helper falls back to valid season/episode")
    Harness_Equal(EpisodesEpisodeVideoId("ttQW", { season: 1, episode: invalid }), "", "episode helper returns empty when episode is unresolvable")

    sel = EpisodesResolveEpisodeSelection("ttQW", { id: "ttQW:5:6" })
    Harness_Ok(sel <> invalid and sel.videoId = "ttQW:5:6" and sel.season = 5 and sel.episode = 6, "selection recovers ordinals from a canonical video id")
    malformedSel = EpisodesResolveEpisodeSelection("ttQW", { season: 1, episode: invalid })
    Harness_Ok(malformedSel = invalid, "selection is invalid when the episode cannot be addressed")

    playable = EpisodesFirstPlayableEpisodeSelection("ttQW", { videos: [{ season: 1, episode: invalid }, { id: "ttQW:1:2", season: 1, episode: 2 }] })
    Harness_Ok(playable <> invalid and playable.videoId = "ttQW:1:2", "first playable selection skips malformed leading videos")
    Harness_Ok(EpisodesFirstPlayableEpisodeSelection("ttQW", { videos: [{ season: 1, episode: invalid }] }) = invalid, "no playable selection when every video is malformed")

    Harness_Ok(EpisodesSeriesData(invalid, { videos: [] }) <> invalid, "no id: SeriesData answers the empty shape, no crash")
    empty = EpisodesSeriesData(invalid, { videos: [{ season: 1, episode: 1, id: "ttQW:1:1" }] })
    Harness_Equal(empty.orderedVideoIds.Count(), 0, "no id: no ordered video ids are built from it")

    Harness_Ok(EpisodesOrderedVideoIds(invalid, { videos: [{ season: 1, episode: 1 }] }) <> invalid, "no id: OrderedVideoIds answers empty, no crash")
    Harness_Equal(EpisodesOrderedVideoIds("ttQW", { videos: [{ season: 1, episode: 2 }] }).Count(), 1, "a real id still orders the run")
    Harness_Equal(EpisodesOrderedVideoIds("ttQW", { videos: [{ season: 1, episode: 2 }] })[0], "ttQW:1:2", "the ordered id carries the series id")

    m.stores = invalid
end sub

sub Test_StoreHost_AddonsMetaAddresses_Bridge()
    Harness_Suite("StoreHost.AddonsMetaAddresses forwards meta provider selection")
    addons = AddonsStore(ScriptedTransport([]), invalid)
    outcome = addons.InstallFromDescriptor("https://bridge-source.example.com/manifest.json", {
        id: "com.example.bridge"
        name: "Bridge Source"
        version: "1.0.0"
        types: ["movie", "series"]
        catalogs: []
        resources: ["catalog"]
    })
    Harness_Ok(outcome.ok, "catalog-only source installed for bridge test")
    m.stores = { addons: addons }

    source = addons.Get("com.example.bridge").address
    cinemeta = addons.Get("com.linvo.cinemeta").address
    addresses = AddonsMetaAddresses("movie", "tt12345", source)

    Harness_Equal(addresses.Count(), 1, "bridge returns eligible meta candidates")
    Harness_Equal(addresses[0], cinemeta, "bridge selects Cinemeta fallback for catalog-only source")

    m.stores = invalid
end sub
