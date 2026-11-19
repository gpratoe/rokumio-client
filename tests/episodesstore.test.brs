' EpisodesStore unit tests.
'
' GetMeta talks to the add-on through the scripted transport; Seasons /
' EpisodesForSeason / ResolveVideoId / NeedsMetaFetch / MergeMeta are pure
' helpers over an already-fetched meta so they run without any transport round trip.

function SeriesMetaFixture() as object
    return {
        id: "tt1234567"
        type: "series"
        name: "Test Series"
        videos: [
            { id: "tt1234567:1:1", name: "Pilot", season: 1, episode: 1 }
            { id: "tt1234567:1:2", name: "Second", season: 1, episode: 2 }
            { id: "tt1234567:2:1", name: "S2E1", season: 2, episode: 1 }
        ]
    }
end function

sub Test_Episodes_GetMetaMovie()
    Harness_Suite("EpisodesStore.GetMeta fetches a movie meta")
    address = "https://v3-cinemeta.strem.io"
    script = [
        {
            method: "GET"
            url: address + "/meta/movie/tt0133093.json"
            ok: true
            status: 200
            json: { meta: { id: "tt0133093", type: "movie", name: "The Matrix" } }
            error: ""
        }
    ]
    store = EpisodesStore(ScriptedTransport(script))
    result = store.GetMeta(address, "movie", "tt0133093")

    Harness_Ok(result.ok, "meta ok")
    Harness_Equal(result.meta.name, "The Matrix", "meta parsed")
end sub

sub Test_Episodes_GetMetaSeries()
    Harness_Suite("EpisodesStore.GetMeta fetches a series meta")
    address = "https://v3-cinemeta.strem.io"
    script = [
        {
            method: "GET"
            url: address + "/meta/series/tt1234567.json"
            ok: true
            status: 200
            json: { meta: SeriesMetaFixture() }
            error: ""
        }
    ]
    store = EpisodesStore(ScriptedTransport(script))
    result = store.GetMeta(address, "series", "tt1234567")

    Harness_Ok(result.ok, "meta ok")
    Harness_Equal(result.meta.videos.Count(), 3, "videos parsed")
end sub

sub Test_Episodes_RejectsSeriesWithoutVideos()
    Harness_Suite("EpisodesStore.GetMeta rejects a series with no videos")
    script = [
        { method: "GET", ok: true, status: 200, json: { meta: { id: "tt0000000", type: "series", name: "Empty" } }, error: "" }
    ]
    store = EpisodesStore(ScriptedTransport(script))
    result = store.GetMeta("https://addon.example.com", "series", "tt0000000")

    Harness_Ok(not result.ok, "meta rejected")
    Harness_Equal(result.error, "series meta missing videos", "error names the missing videos")
end sub

sub Test_Episodes_Seasons()
    Harness_Suite("EpisodesStore.Seasons lists distinct seasons sorted")
    store = EpisodesStore(ScriptedTransport([]))
    seasons = store.Seasons(SeriesMetaFixture())

    Harness_Equal(seasons.Count(), 2, "two seasons")
    Harness_Equal(seasons[0], 1, "first season is 1")
    Harness_Equal(seasons[1], 2, "second season is 2")
end sub

sub Test_Episodes_EpisodesForSeason()
    Harness_Suite("EpisodesStore.EpisodesForSeason filters by season")
    store = EpisodesStore(ScriptedTransport([]))
    first = store.EpisodesForSeason(SeriesMetaFixture(), 1)
    second = store.EpisodesForSeason(SeriesMetaFixture(), 2)

    Harness_Equal(first.Count(), 2, "season 1 has two episodes")
    Harness_Equal(first[1].episode, 2, "episode numbers intact")
    Harness_Equal(second.Count(), 1, "season 2 has one episode")
    Harness_Equal(second[0].name, "S2E1", "episode names intact")
end sub

sub Test_Episodes_ResolveVideoId()
    Harness_Suite("EpisodesStore.ResolveVideoId builds the stream-id convention")
    store = EpisodesStore(ScriptedTransport([]))

    Harness_Equal(store.ResolveVideoId("tt1234567", 1, 1), "tt1234567:1:1", "movie/episode id shape")
    Harness_Equal(store.ResolveVideoId("tt1234567", 12, 4), "tt1234567:12:4", "double-digit season/episode")
    Harness_Equal(store.ResolveVideoId("tt1234567", 1, invalid), "", "invalid episode yields no id, no crash")
    Harness_Equal(store.ResolveVideoId("tt1234567", invalid, 1), "", "invalid season yields no id, no crash")
    Harness_Equal(store.ResolveVideoId(invalid, 1, 1), "", "invalid series id yields no id, no crash")
end sub

sub Test_Episodes_OrderedSeasons()
    Harness_Suite("EpisodesStore.OrderedSeasons keeps ascending seasons with specials last")
    store = EpisodesStore(ScriptedTransport([]))
    order = store.OrderedSeasons([0, 1, 2])
    Harness_Equal(order.Count(), 3, "all seasons survive")
    Harness_Equal(order[0], 1, "real seasons first")
    Harness_Equal(order[1], 2, "real seasons ascending")
    Harness_Equal(order[2], 0, "specials last")
    Harness_Equal(store.OrderedSeasons([]).Count(), 0, "empty input stays empty")
    Harness_Equal(store.OrderedSeasons([0]).Count(), 1, "a specials-only series still lists the special")
end sub

sub Test_Episodes_OrderedVideoIds()
    Harness_Suite("EpisodesStore.OrderedVideoIds returns the bitfield-indexing episode order")
    meta = {
        id: "tt1234567"
        type: "series"
        videos: [
            { id: "tt1234567:2:1", name: "S2E1", season: 2, episode: 1 }
            { id: "tt1234567:0:1", name: "Special", season: 0, episode: 1 }
            { id: "tt1234567:1:1", name: "Pilot", season: 1, episode: 1 }
            { id: "tt1234567:1:2", name: "Second", season: 1, episode: 2 }
        ]
    }
    store = EpisodesStore(ScriptedTransport([]))
    ids = store.OrderedVideoIds("tt1234567", meta)
    Harness_Equal(ids.Count(), 3, "specials are skipped")
    Harness_Equal(ids[0], "tt1234567:1:1", "season 1 first episode first")
    Harness_Equal(ids[1], "tt1234567:1:2", "episode order kept")
    Harness_Equal(ids[2], "tt1234567:2:1", "season 2 after season 1")
    Harness_Equal(store.OrderedVideoIds("tt1234567", invalid).Count(), 0, "missing meta yields an empty list")
    Harness_Equal(store.OrderedVideoIds("", meta).Count(), 0, "blank seriesId yields an empty list")
end sub

sub Test_Episodes_SeriesDataGroupsOnceInDisplayOrder()
    Harness_Suite("EpisodesStore.SeriesData groups a series and derives the bitfield order")
    meta = {
        id: "tt1234567"
        type: "series"
        videos: [
            { id: "tt1234567:2:1", name: "S2E1", season: 2, episode: 1 }
            { id: "tt1234567:0:1", name: "Special", season: 0, episode: 1 }
            { id: "tt1234567:1:1", name: "Pilot", season: 1, episode: 1 }
            { id: "tt1234567:1:2", name: "Second", season: 1, episode: 2 }
        ]
    }
    store = EpisodesStore(ScriptedTransport([]))
    data = store.SeriesData("tt1234567", meta)

    Harness_Equal(data.seasons.Count(), 3, "all seasons, including specials")
    Harness_Equal(data.seasons[0], 1, "regular seasons start in ascending order")
    Harness_Equal(data.seasons[1], 2, "second regular season follows")
    Harness_Equal(data.seasons[2], 0, "specials stay last")
    Harness_Equal(data.runs.Count(), data.seasons.Count(), "one grouped run per season")
    Harness_Equal(data.runs[0].season, 1, "run order matches season order")
    Harness_Equal(data.runs[0].episodes.Count(), 2, "season one grouped in one pass")
    Harness_Equal(data.runs[0].episodes[0].name, "Pilot", "original within-season order is preserved")
    Harness_Equal(data.runs[1].episodes[0].name, "S2E1", "season two is grouped")
    Harness_Equal(data.runs[2].episodes[0].name, "Special", "special episode is grouped last")
    Harness_Equal(data.orderedVideoIds.Count(), 3, "specials do not enter the bitfield order")
    Harness_Equal(data.orderedVideoIds[0], "tt1234567:1:1", "bitfield ids follow display order")
    Harness_Equal(data.orderedVideoIds[1], "tt1234567:1:2", "all of season one precedes season two")
    Harness_Equal(data.orderedVideoIds[2], "tt1234567:2:1", "season two follows season one")
    Harness_Equal(store.SeriesData("tt1234567", invalid).seasons.Count(), 0, "invalid meta gives an empty result")
    Harness_Equal(store.SeriesData("", meta).orderedVideoIds.Count(), 0, "blank id gives no bitfield ids")
end sub

' A complete meta (all hero fields present) never needs a fetch; a slim catalog
' record missing any of them does. A meta without a fetchable id/type cannot be
' topped up, so it is "no fetch" too.
sub Test_Episodes_NeedsMetaFetch()
    Harness_Suite("EpisodesStore.NeedsMetaFetch flags only sparse metas")
    store = EpisodesStore(ScriptedTransport([]))

    Harness_Ok(not store.NeedsMetaFetch(invalid), "invalid meta: no fetch")
    Harness_Ok(not store.NeedsMetaFetch({}), "empty meta: no fetch")
    Harness_Ok(not store.NeedsMetaFetch({ id: "tt1", name: "No type" }), "missing type: no fetch")
    Harness_Ok(not store.NeedsMetaFetch({ type: "movie", name: "No id" }), "missing id: no fetch")

    complete = {
        id: "tt1234567"
        type: "series"
        name: "Series"
        description: "A summary"
        releaseInfo: "2023"
        imdbRating: "8.1"
        background: "https://example.com/bg.jpg"
        poster: "https://example.com/poster.jpg"
    }
    Harness_Ok(not store.NeedsMetaFetch(complete), "complete meta: no fetch")

    sparse = { id: "tt1234567", type: "movie", name: "Movie" }
    Harness_Ok(store.NeedsMetaFetch(sparse), "slim catalog meta: fetch")

    Harness_Ok(store.NeedsMetaFetch({ id: "tt1", type: "movie", name: "M", description: "ok" }), "missing poster: fetch")
    Harness_Ok(store.NeedsMetaFetch({ id: "tt1", type: "movie", name: "M", poster: "url", description: "ok", releaseInfo: "2023", imdbRating: "8" }), "missing background: fetch")
    Harness_Ok(store.NeedsMetaFetch({ id: "tt1", type: "movie", name: "M", poster: "url", description: "ok", releaseInfo: "", imdbRating: "8", background: "bg" }), "empty releaseInfo: fetch")
end sub

' Merged meta starts from the fetched record and lets any non-empty field from
' the provided record win, so nothing the caller passed is lost. Empty-string
' provided fields give way to fetched values. Neither input is mutated.
sub Test_Episodes_MergeMeta()
    Harness_Suite("EpisodesStore.MergeMeta fills gaps without losing provided values")
    store = EpisodesStore(ScriptedTransport([]))

    fetched = {
        description: "Fetched description"
        releaseInfo: "2023"
        imdbRating: "8.6"
        background: "https://example.com/bg.jpg"
        poster: "https://example.com/poster.jpg"
    }

    slim = { id: "tt1234567", type: "movie", name: "Mock Movie" }
    merged = store.MergeMeta(slim, fetched)
    Harness_Equal(merged.id, "tt1234567", "provided id kept")
    Harness_Equal(merged.type, "movie", "provided type kept")
    Harness_Equal(merged.name, "Mock Movie", "provided name kept")
    Harness_Equal(merged.description, "Fetched description", "missing description filled")
    Harness_Equal(merged.releaseInfo, "2023", "missing releaseInfo filled")
    Harness_Equal(merged.imdbRating, "8.6", "missing imdbRating filled")
    Harness_Equal(merged.background, "https://example.com/bg.jpg", "missing background filled")
    Harness_Equal(merged.poster, "https://example.com/poster.jpg", "missing poster filled")

    fetchedWithRuntime = { description: "Fetched description", releaseInfo: "2023", imdbRating: "8.6", background: "bg", poster: "poster", runtime: 121 }
    keep = store.MergeMeta({ id: "tt1", name: "Kept", description: "provided wins", runtime: "" }, fetchedWithRuntime)
    Harness_Equal(keep.description, "provided wins", "non-empty provided value wins over fetched")
    Harness_Equal(keep.runtime, 121, "empty provided value gives way to fetched")
    Harness_Equal(keep.id, "tt1", "provided id kept in override case")
    Harness_Equal(keep.imdbRating, "8.6", "fetched fields still fill gaps")

    fromFetchedOnly = store.MergeMeta(invalid, fetched)
    Harness_Equal(fromFetchedOnly.description, "Fetched description", "fetched-only merge keeps fetched")

    fromProvidedOnly = store.MergeMeta({ id: "tt9", type: "movie", name: "Alone" }, invalid)
    Harness_Equal(fromProvidedOnly.id, "tt9", "provided-only merge keeps provided")
    Harness_Equal(fromProvidedOnly.name, "Alone", "provided-only merge keeps name")

    ' Real Cinemeta metas carry object fields like `links`; those must never be
    ' compared against a blank string (Type Mismatch crash) and the provided
    ' value wins over the fetched one.
    providedLinks = [{ name: "Watch Now", category: "watch", url: "https://example.com/watch" }]
    fetched = { description: "Fetched", links: [{ name: "Fetched Link", category: "other" }] }
    withLinks = store.MergeMeta({ id: "tt7", name: "Linked", links: providedLinks }, fetched)
    Harness_Equal(withLinks.links.Count(), 1, "provided links kept (no type-mismatch crash)")
    Harness_Equal(withLinks.links[0].name, "Watch Now", "provided object value wins over fetched")
    Harness_Equal(withLinks.description, "Fetched", "fetched string still fills a gap")

    fetchedWithLinks = { description: "Fetched", links: [{ name: "Fetched Link", category: "other" }], videos: [] }
    fromFetchedLinks = store.MergeMeta({ id: "tt8", name: "No Links" }, fetchedWithLinks)
    Harness_Equal(fromFetchedLinks.links.Count(), 1, "fetched object field survives when provided lacks it")
    Harness_Ok(fromFetchedLinks.videos <> invalid and Type(fromFetchedLinks.videos) = "roArray", "fetched array survives")

    Harness_Equal(slim.description, invalid, "provided input not mutated")
    Harness_Equal(fetched.name, invalid, "fetched input not mutated")
end sub

' Add-on JSON is not obliged to honour the meta spec's types, and Cinemeta does
' not: it answers imdbRating with the NUMBER 8.1. `8.1 = ""` is "Type Mismatch.
' Operator '=' can't be applied to 'roFloat' and 'String'" on the device, thrown
' straight out of the screen that asked — the crash these guards exist for. A
' value that is a number is a value the hero renders ("8.1"), so it counts as
' present; it is never compared raw and never treated as a gap to refetch.
sub Test_Episodes_NumericMetaFieldsDoNotThrow()
    Harness_Suite("EpisodesStore tolerates numeric add-on field values")
    store = EpisodesStore(ScriptedTransport([]))

    completeButNumeric = {
        id: "tt1234567"
        type: "series"
        name: "Series"
        description: "A summary"
        releaseInfo: 2023
        imdbRating: 8.1
        background: "https://example.com/bg.jpg"
        poster: "https://example.com/poster.jpg"
    }
    Harness_Ok(not store.NeedsMetaFetch(completeButNumeric), "numeric rating/releaseInfo: complete, no fetch")

    zeroRating = { id: "tt1", type: "movie", description: "d", releaseInfo: "2023", imdbRating: 0, background: "bg", poster: "p" }
    Harness_Ok(not store.NeedsMetaFetch(zeroRating), "a 0 rating is present, not a gap")

    ' id and type become a URL path and a typed argument, so only real strings can
    ' carry them: a numeric one is "nothing a fetch can improve", not a crash.
    Harness_Ok(not store.NeedsMetaFetch({ id: 1234, type: "movie", name: "N" }), "numeric id: no fetch")
    Harness_Ok(not store.NeedsMetaFetch({ id: "tt1", type: 8, name: "N" }), "numeric type: no fetch")
    Harness_Ok(store.NeedsMetaFetch({ id: "tt1", type: "movie", imdbRating: 8.1, description: "d", releaseInfo: "2023", poster: "p" }), "a numeric field is still not a background: fetch")

    numericProvided = store.MergeMeta({ id: "tt5", name: "Numeric", imdbRating: 8.1, runtime: 121 }, { description: "Fetched", imdbRating: "8.6" })
    Harness_Equal(numericProvided.imdbRating, 8.1, "provided numeric rating wins over the fetched one")
    Harness_Equal(numericProvided.description, "Fetched", "fetched string still fills the gap")
    Harness_Equal(numericProvided.runtime, 121, "provided numeric runtime kept")
end sub

sub Test_Episodes_EpisodeVideoId_PrefersOwnIdAndFallsBack()
    Harness_Suite("EpisodesStore.EpisodeVideoId follows Stremio's id-first model")
    store = EpisodesStore(ScriptedTransport([]))

    Harness_Equal(store.EpisodeVideoId("tt1234567", { id: "tt1234567:2:3", season: 2, episode: 3 }), "tt1234567:2:3", "prefers the video's own id")
    Harness_Equal(store.EpisodeVideoId("tt1234567", { season: 1, episode: 4 }), "tt1234567:1:4", "falls back to valid season/episode")
    Harness_Equal(store.EpisodeVideoId("tt1234567", { season: 1, episode: invalid }), "", "invalid episode is not addressable")
    Harness_Equal(store.EpisodeVideoId("tt1234567", { season: invalid, episode: 4 }), "", "invalid season is not addressable")
    Harness_Equal(store.EpisodeVideoId("tt1234567", invalid), "", "missing video is not addressable")
end sub

sub Test_Episodes_ResolveEpisodeSelection_RecoversOrdinals()
    Harness_Suite("EpisodesStore.ResolveEpisodeSelection returns id and ordinals")
    store = EpisodesStore(ScriptedTransport([]))

    sel = store.ResolveEpisodeSelection("tt1234567", { id: "tt1234567:3:7" })
    Harness_Ok(sel <> invalid and sel.videoId = "tt1234567:3:7" and sel.season = 3 and sel.episode = 7, "recovers ordinals from a canonical video id")

    fallback = store.ResolveEpisodeSelection("tt1234567", { season: 2, episode: 5 })
    Harness_Ok(fallback <> invalid and fallback.videoId = "tt1234567:2:5" and fallback.season = 2 and fallback.episode = 5, "builds id and keeps ordinals when fields are valid")

    Harness_Ok(store.ResolveEpisodeSelection("tt1234567", { season: 2, episode: invalid }) = invalid, "unresolvable episode yields no selection")
end sub

sub Test_Episodes_FirstPlayableEpisodeSelection_SkipsMalformed()
    Harness_Suite("EpisodesStore.FirstPlayableEpisodeSelection picks the first addressable episode")
    store = EpisodesStore(ScriptedTransport([]))
    meta = {
        videos: [
            { season: 1, episode: invalid }
            { id: "tt1234567:1:2", season: 1, episode: 2 }
            { season: 1, episode: 3 }
        ]
    }
    sel = store.FirstPlayableEpisodeSelection("tt1234567", meta)
    Harness_Ok(sel <> invalid and sel.videoId = "tt1234567:1:2" and sel.episode = 2, "skips malformed leading video and returns first playable selection")

    badOnly = { videos: [{ season: 1, episode: invalid }, { season: invalid, episode: 1 }] }
    Harness_Ok(store.FirstPlayableEpisodeSelection("tt1234567", badOnly) = invalid, "returns invalid when no episode is addressable")
end sub

sub Test_Episodes_OrderedIdsSkipMalformedEpisodes()
    Harness_Suite("EpisodesStore ordered ids skip episodes without a canonical id")
    store = EpisodesStore(ScriptedTransport([]))
    meta = {
        id: "tt1234567"
        type: "series"
        videos: [
            { season: 1, episode: 1 }
            { season: 1, episode: invalid }
            { season: 1, episode: 2 }
        ]
    }
    ids = store.OrderedVideoIds("tt1234567", meta)
    Harness_Equal(ids.Count(), 2, "malformed episode is excluded from ordered ids")
    Harness_Equal(ids[0], "tt1234567:1:1", "first valid episode kept")
    Harness_Equal(ids[1], "tt1234567:1:2", "later valid episode kept")

    data = store.SeriesData("tt1234567", meta)
    Harness_Equal(data.orderedVideoIds.Count(), 2, "series data ordered ids skip malformed episodes")
    Harness_Equal(data.runs[0].episodes.Count(), 3, "display grouping still keeps the original episode entries")
end sub

