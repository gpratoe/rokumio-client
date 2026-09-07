' EpisodesStore unit tests.
'
' GetMeta talks to the add-on through the scripted transport; Seasons /
' EpisodesForSeason / ResolveVideoId are pure helpers over an already-fetched
' meta so they run without any transport round trip.

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
end sub