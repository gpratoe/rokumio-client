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
