' Shared Home-catalog rules used by both the picker and Home loader.

sub Test_HomeCatalogBrowsableRules()
    Harness_Suite("Home catalogs require only the default skip extra")
    catalog = { type: "movie", id: "top", extraRequired: ["skip"] }
    Harness_Ok(HomeCatalogBrowsable(catalog), "skip-only catalog can be browsed")

    catalog.extraRequired = ["genre"]
    Harness_Ok(not HomeCatalogBrowsable(catalog), "a required genre is not browsable from Home")

    catalog.extraRequired = []
    catalog.extra = [{ name: "token", isRequired: true }]
    Harness_Ok(not HomeCatalogBrowsable(catalog), "a required extra blocks Home browsing")

    catalog.extra = [{ name: "skip", isRequired: true }]
    Harness_Ok(HomeCatalogBrowsable(catalog), "a required skip remains browsable")
    Harness_Ok(not HomeCatalogBrowsable({ type: "movie", id: "" }), "catalogs without an id cannot be selected")
end sub

sub Test_HomeCatalogHiddenUsesExactTuple()
    Harness_Suite("Home catalog exclusions match address, type and id")
    hidden = [{
        addonAddress: "https://catalog.example/addon?token=a|b"
        metaType: "movie"
        catalogId: "top"
    }]

    Harness_Ok(HomeCatalogIsHidden("https://catalog.example/addon?token=a|b", "movie", "top", hidden), "the matching tuple is hidden")
    Harness_Ok(not HomeCatalogIsHidden("https://catalog.example/addon?token=a|b", "series", "top", hidden), "a different type remains visible")
    Harness_Ok(not HomeCatalogIsHidden("https://catalog.example/addon", "movie", "top", hidden), "a different address remains visible")
    Harness_Ok(not HomeCatalogIsHidden("https://catalog.example/addon?token=a|b", "movie", "latest", hidden), "a different catalog remains visible")
end sub

sub Test_HomeMetaOpenable()
    Harness_Suite("HomeMetaOpenable gates tiles on a usable id")
    ' The crash class this guards: a v0.3.1 user's add-on shipped a catalog
    ' meta with no id, and Home died rendering its tile on every launch. A meta
    ' without an id has nothing to open (Details, streams, save/resume are all
    ' addressed by it), so it must not be rendered at all.
    Harness_Ok(HomeMetaOpenable({ id: "tt0111161", type: "movie", name: "Ok" }), "a real id opens")
    Harness_Ok(not HomeMetaOpenable({ type: "movie", name: "No id" }), "a missing id does not")
    Harness_Ok(not HomeMetaOpenable({ id: invalid, type: "movie" }), "an invalid id does not — the reported crash shape")
    Harness_Ok(not HomeMetaOpenable({ id: "", type: "movie" }), "a blank id does not")
    Harness_Ok(not HomeMetaOpenable({ id: 12345, type: "movie" }), "a numeric id does not — the protocol requires text")
    Harness_Ok(not HomeMetaOpenable(invalid), "an invalid meta does not")
    Harness_Ok(not HomeMetaOpenable("tt0111161"), "a bare string is not a meta")
    ' An id with no type still opens: type only steers the details flow, the id
    ' is what everything is addressed by.
    Harness_Ok(HomeMetaOpenable({ id: "yt_id:x" }), "an id without a type opens")
end sub

sub Test_FilterOpenableMetas()
    Harness_Suite("FilterOpenableMetas splits a raw meta list in one place")
    ' The shape every screen filters: some good ids mixed with every malformed
    ' id the broken add-on shipped — missing, null, blank, numeric.
    metas = [
        { id: "tt0111161", type: "movie" }
        { type: "movie" }
        { id: invalid, type: "movie" }
        { id: "", type: "movie" }
        { id: 12345, type: "movie" }
        { id: "tt0133093", type: "movie" }
    ]
    filtered = FilterOpenableMetas(metas)
    Harness_Equal(filtered.openable.Count(), 2, "the two usable metas survive the filter")
    Harness_Equal(filtered.dropped, 4, "the four unusable metas are counted as dropped")
    Harness_Equal(filtered.openable[0].id, "tt0111161", "order is preserved for the survivors")

    ' Degenerate inputs degrade to an empty result, not an error.
    empty = FilterOpenableMetas(invalid)
    Harness_Ok(empty.openable <> invalid and empty.openable.Count() = 0 and empty.dropped = 0, "an invalid list answers the empty shape")
    Harness_Ok(FilterOpenableMetas([]).dropped = 0, "an empty list drops nothing")

    allGood = FilterOpenableMetas([{ id: "a" }, { id: "b" }])
    Harness_Ok(allGood.dropped = 0 and allGood.openable.Count() = 2, "a clean list passes through untouched")
end sub
