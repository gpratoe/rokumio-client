' MetaLoader fallback tests.
'
' MetaLoaderTryCandidates tries ordered addon addresses until one returns usable
' meta. It must fall through on failures and unusable series meta, dedupe
' candidates, and degrade gracefully without crashing when nothing works.

sub Test_MetaLoaderTryCandidates_ReturnsFirstUsable()
    Harness_Suite("MetaLoaderTryCandidates returns the first usable meta")
    firstUrl = "https://a.example.com/meta/movie/tt100.json"
    secondUrl = "https://b.example.com/meta/movie/tt100.json"
    script = [
        { method: "GET", url: firstUrl, ok: true, status: 200, json: { meta: { id: "tt100", type: "movie", name: "First" } }, error: "" }
        { method: "GET", url: secondUrl, ok: true, status: 200, json: { meta: { id: "tt100", type: "movie", name: "Second" } }, error: "" }
    ]
    transport = ScriptedTransport(script)
    store = EpisodesStore(transport)

    result = MetaLoaderTryCandidates(["https://a.example.com", "https://b.example.com"], "movie", "tt100", store)

    Harness_Ok(result.ok, "first usable candidate succeeds")
    Harness_Ok(result.meta <> invalid, "usable meta returned")
    Harness_Equal(result.meta.name, "First", "first candidate wins")
    Harness_Equal(transport.log.Count(), 1, "stops after first usable candidate")
    Harness_Equal(transport.log[0].url, firstUrl, "only first candidate requested")
end sub

sub Test_MetaLoaderTryCandidates_FallsThroughOnFailure()
    Harness_Suite("MetaLoaderTryCandidates falls through when a candidate fails")
    firstUrl = "https://bad.example.com/meta/movie/tt200.json"
    secondUrl = "https://good.example.com/meta/movie/tt200.json"
    script = [
        { method: "GET", url: firstUrl, ok: false, status: 500, json: invalid, error: "server error" }
        { method: "GET", url: secondUrl, ok: true, status: 200, json: { meta: { id: "tt200", type: "movie", name: "Good" } }, error: "" }
    ]
    transport = ScriptedTransport(script)
    store = EpisodesStore(transport)

    result = MetaLoaderTryCandidates(["https://bad.example.com", "https://good.example.com"], "movie", "tt200", store)

    Harness_Ok(result.ok, "fallback candidate succeeds")
    Harness_Equal(result.meta.name, "Good", "usable fallback meta returned")
    Harness_Equal(transport.log.Count(), 2, "failed candidate then fallback tried")
    Harness_Equal(transport.log[0].url, firstUrl, "first failing candidate requested")
    Harness_Equal(transport.log[1].url, secondUrl, "fallback candidate requested")
end sub

sub Test_MetaLoaderTryCandidates_FallsThroughOnSeriesMetaWithoutVideos()
    Harness_Suite("MetaLoaderTryCandidates falls through on unusable series meta without videos")
    firstUrl = "https://novideos.example.com/meta/series/tt300.json"
    secondUrl = "https://withvideos.example.com/meta/series/tt300.json"
    script = [
        { method: "GET", url: firstUrl, ok: true, status: 200, json: { meta: { id: "tt300", type: "series", name: "No Videos" } }, error: "" }
        { method: "GET", url: secondUrl, ok: true, status: 200, json: { meta: { id: "tt300", type: "series", name: "Has Videos", videos: [{ id: "tt300:1:1", season: 1, episode: 1, name: "Pilot" }] } }, error: "" }
    ]
    transport = ScriptedTransport(script)
    store = EpisodesStore(transport)

    result = MetaLoaderTryCandidates(["https://novideos.example.com", "https://withvideos.example.com"], "series", "tt300", store)

    Harness_Ok(result.ok, "usable series candidate succeeds")
    Harness_Equal(result.meta.name, "Has Videos", "series meta with videos returned")
    Harness_Equal(result.meta.videos.Count(), 1, "returned series meta includes episode videos")
    Harness_Equal(transport.log.Count(), 2, "unusable series meta causes fallback")
    Harness_Equal(transport.log[0].url, firstUrl, "candidate without videos tried first")
    Harness_Equal(transport.log[1].url, secondUrl, "candidate with videos tried next")
end sub

sub Test_MetaLoaderTryCandidates_DedupesAndSkipsEmpty()
    Harness_Suite("MetaLoaderTryCandidates dedupes addresses and skips empty entries")
    goodUrl = "https://good.example.com/meta/movie/tt400.json"
    script = [
        { method: "GET", url: goodUrl, ok: true, status: 200, json: { meta: { id: "tt400", type: "movie", name: "Good" } }, error: "" }
    ]
    transport = ScriptedTransport(script)
    store = EpisodesStore(transport)

    result = MetaLoaderTryCandidates(["", "  ", invalid, "https://good.example.com", "https://good.example.com", " https://good.example.com "], "movie", "tt400", store)

    Harness_Ok(result.ok, "usable candidate found despite empty/duplicate entries")
    Harness_Equal(result.meta.name, "Good", "correct usable meta returned")
    Harness_Equal(transport.log.Count(), 1, "each non-empty address tried only once")
    Harness_Equal(transport.log[0].url, goodUrl, "deduped candidate requested once")
end sub

sub Test_MetaLoaderTryCandidates_AllFailReturnsLastError()
    Harness_Suite("MetaLoaderTryCandidates returns the last failure when all candidates fail")
    firstUrl = "https://one.example.com/meta/movie/tt500.json"
    secondUrl = "https://two.example.com/meta/series/tt500.json"
    script = [
        { method: "GET", url: firstUrl, ok: false, status: 404, json: invalid, error: "not found" }
        { method: "GET", url: secondUrl, ok: true, status: 200, json: { meta: { id: "tt500", type: "series", name: "No Episodes" } }, error: "" }
    ]
    transport = ScriptedTransport(script)
    store = EpisodesStore(transport)

    result = MetaLoaderTryCandidates(["https://one.example.com", "https://two.example.com"], "series", "tt500", store)

    Harness_Ok(not result.ok, "all candidates unusable results in failure")
    Harness_Equal(result.meta, invalid, "no usable meta returned")
    Harness_Equal(result.error, "series meta missing videos", "last candidate error preserved")
    Harness_Equal(transport.log.Count(), 2, "every candidate attempted before failing gracefully")
end sub

sub Test_MetaLoaderTryCandidates_EmptyOrInvalidAddressesReturnDefaultError()
    Harness_Suite("MetaLoaderTryCandidates handles empty or invalid candidate lists gracefully")
    transport = ScriptedTransport([])
    store = EpisodesStore(transport)

    emptyResult = MetaLoaderTryCandidates([], "movie", "tt600", store)
    Harness_Ok(not emptyResult.ok, "empty candidate list fails gracefully")
    Harness_Equal(emptyResult.error, "meta type or id missing", "empty candidate list returns default meta error")
    Harness_Equal(emptyResult.meta, invalid, "empty candidate list returns no meta")

    invalidResult = MetaLoaderTryCandidates(invalid, "movie", "tt600", store)
    Harness_Ok(not invalidResult.ok, "invalid candidate list fails gracefully")
    Harness_Equal(invalidResult.error, "meta type or id missing", "invalid candidate list returns default meta error")
    Harness_Equal(invalidResult.meta, invalid, "invalid candidate list returns no meta")
    Harness_Equal(transport.log.Count(), 0, "no network request attempted for empty/invalid candidates")
end sub

sub Test_MetaLoaderTryCandidates_MissingStoreReturnsUnavailable()
    Harness_Suite("MetaLoaderTryCandidates fails gracefully when no store is available")
    result = MetaLoaderTryCandidates(["https://a.example.com"], "movie", "tt700", invalid)

    Harness_Ok(not result.ok, "missing store fails gracefully")
    Harness_Equal(result.meta, invalid, "missing store returns no meta")
    Harness_Equal(result.error, "meta store unavailable", "missing store reports unavailable store")
end sub

sub Test_MetaLoaderTryCandidates_HandlesInvalidAddressEntriesWithoutCrash()
    Harness_Suite("MetaLoaderTryCandidates tolerates invalid address entries without crashing")
    goodUrl = "https://good.example.com/meta/movie/tt800.json"
    script = [
        { method: "GET", url: goodUrl, ok: true, status: 200, json: { meta: { id: "tt800", type: "movie", name: "Recovered" } }, error: "" }
    ]
    transport = ScriptedTransport(script)
    store = EpisodesStore(transport)

    result = MetaLoaderTryCandidates([invalid, 123, {}, "https://good.example.com"], "movie", "tt800", store)

    Harness_Ok(result.ok, "valid candidate still resolves after invalid entries")
    Harness_Equal(result.meta.name, "Recovered", "usable meta returned despite malformed candidate entries")
    Harness_Equal(transport.log.Count(), 1, "only the valid non-empty candidate is requested")
end sub
