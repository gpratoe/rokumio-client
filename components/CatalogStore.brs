' CatalogStore.brs
'
' A single point of truth for the content catalog domain: the board rows
' (home tab), the discover rows + filter state (discover tab), the search
' result rows, and the network round-trips that fill them (cinemeta /
' channels / public-domain add-on catalog URLs).
'
' MainScene still owns all rendering (RebuildCatalog, RebuildDiscoverGrid,
' the filter labels and focus) and picks which catalog feeds the grid each
' tab via m.catalogRows / m.catalogNames. This store returns request specs
' (url + id) for MainScene to fire through the shared HTTP transport, and it
' accepts raw responses back via handleCatalogResponse / handleSearchMetaResponse.

function CreateCatalogStore() as object
    store = {
        ' Board = the home tab card rows.
        _boardRows: [[], [], [], [], [], []]
        _boardNames: ["Popular - Movie", "Popular - Series", "Featured - Movie", "Featured - Series", "YouTube - Channel", "Public Domain Movies - Movie"]
        ' Discover = the filter-driven tab; also hosts search result rows.
        _discoverRows: [[]]
        _discoverNames: ["Movie - Popular"]
        _discoverRequestActive: false
        ' Discover filter values stay canonical (untranslated) here so the
        ' URL builder and the dialog labels never see localized text.
        _discoverType: "movie"
        _discoverCatalog: "Popular"
        _discoverGenre: "None"
        _discoverTypes: ["movie", "series", "channel"]
        _discoverCatalogs: ["Popular", "Featured", "New"]
        _discoverGenres: ["None", "Action", "Adventure", "Animation", "Biography", "Comedy", "Crime", "Drama", "Fantasy", "Horror", "Mystery", "Romance", "Sci-Fi", "Thriller"]
    }

    ' --- state accessors ------------------------------------------------------

    store.getBoardRows = function() as object
        return m._boardRows
    end function

    store.getBoardNames = function() as object
        return m._boardNames
    end function

    store.getDiscoverRows = function() as object
        return m._discoverRows
    end function

    store.getDiscoverNames = function() as object
        return m._discoverNames
    end function

    store.isDiscoverRequestActive = function() as boolean
        return m._discoverRequestActive
    end function

    store.setDiscoverRequestActive = function(flag as boolean)
        m._discoverRequestActive = flag
    end function

    store.getDiscoverType = function() as string
        return m._discoverType
    end function

    store.setDiscoverType = function(value as string)
        m._discoverType = value
    end function

    store.getDiscoverCatalog = function() as string
        return m._discoverCatalog
    end function

    store.setDiscoverCatalog = function(value as string)
        m._discoverCatalog = value
    end function

    store.getDiscoverGenre = function() as string
        return m._discoverGenre
    end function

    store.setDiscoverGenre = function(value as string)
        m._discoverGenre = value
    end function

    store.getDiscoverTypes = function() as object
        return m._discoverTypes
    end function

    store.getDiscoverCatalogs = function() as object
        return m._discoverCatalogs
    end function

    store.getDiscoverGenres = function() as object
        return m._discoverGenres
    end function

    ' --- lifecycle ------------------------------------------------------------

    ' Reset the board rows to placeholders (home screen reload).
    store.resetBoard = function()
        m._boardRows = [[], [], [], [], [], []]
    end function

    ' True when every discover row is empty (drives the auto-fetch when the
    ' user lands on the discover tab with nothing loaded).
    store.discoverRowsEmpty = function() as boolean
        if m._discoverRows = invalid or m._discoverRows.Count() = 0 then return true
        for each row in m._discoverRows
            if row <> invalid and row.Count() > 0 then return false
        end for
        return true
    end function

    ' --- network: the home board catalogs -------------------------------------

    ' Request specs for all six board rows. MainScene fires each one.
    store.fetchBoardCatalogs = function() as object
        return [
            { url: "https://v3-cinemeta.strem.io/catalog/movie/top.json", id: "boardCatalog|0" }
            { url: "https://v3-cinemeta.strem.io/catalog/series/top.json", id: "boardCatalog|1" }
            { url: "https://v3-cinemeta.strem.io/catalog/movie/imdbRating.json", id: "boardCatalog|2" }
            { url: "https://v3-cinemeta.strem.io/catalog/series/imdbRating.json", id: "boardCatalog|3" }
            { url: "https://v3-channels.strem.io/catalog/channel/top.json", id: "boardCatalog|4" }
            { url: "https://caching.stremio.net/publicdomainmovies.now.sh/catalog/movie/publicdomainmovies.json", id: "boardCatalog|5" }
        ]
    end function

    ' --- network: the discover catalog ----------------------------------------

    ' Reset the discover rows to a single placeholder row titled from the
    ' current filters, mark a request active, and return its request spec.
    store.restartDiscoverCatalog = function() as object
        m._discoverRows = [[]]
        rowTitle = DiscoverTypeLabel(m._discoverType) + " - " + m._discoverCatalog
        if m._discoverGenre <> "None" and m._discoverGenre <> "Genre"
            rowTitle = rowTitle + " - " + m._discoverGenre
        end if
        m._discoverNames = [rowTitle]
        m._discoverRequestActive = true
        return m.buildDiscoverCatalog()
    end function

    store.buildDiscoverCatalog = function() as object
        catalogId = "top"
        if m._discoverCatalog = "Featured"
            catalogId = "imdbRating"
        else if m._discoverCatalog = "New"
            catalogId = "year"
        end if

        if m._discoverType = "channel"
            return {
                url: "https://v3-channels.strem.io/catalog/channel/top.json"
                id: "discoverCatalog|0"
            }
        end if

        extra = ""
        if m._discoverGenre <> "None" and m._discoverGenre <> "Genre"
            extra = "/genre=" + EncodeUrlComponent(m._discoverGenre)
        end if
        return {
            url: "https://v3-cinemeta.strem.io/catalog/" + m._discoverType + "/" + catalogId + extra + ".json"
            id: "discoverCatalog|0"
        }
    end function

    ' --- network: search ------------------------------------------------------

    ' Set up the discover rows for a search (IMDb-ID lookup or named search)
    ' and return the request specs MainScene will fire. The query routing
    ' (magnet/tvdb/url detection) stays in MainScene.
    store.beginSearch = function(imdbId as boolean, query as string) as object
        if imdbId
            m._discoverRows = [[], []]
            m._discoverNames = ["IMDb ID - Movie", "IMDb ID - Series"]
            m._discoverRequestActive = true
            return [
                { url: CinemetaMetaUrl("movie", query), id: "searchMeta|0" }
                { url: CinemetaMetaUrl("series", query), id: "searchMeta|1" }
            ]
        end if

        m._discoverRows = [[], []]
        m._discoverNames = ["Search Suggestions - Movie", "Search Suggestions - Series"]
        m._discoverRequestActive = true
        encodedQuery = EncodeUrlComponent(query)
        return [
            { url: "https://v3-cinemeta.strem.io/catalog/movie/top/search=" + encodedQuery + ".json", id: "search|0" }
            { url: "https://v3-cinemeta.strem.io/catalog/series/top/search=" + encodedQuery + ".json", id: "search|1" }
        ]
    end function

    ' --- network: response processing -----------------------------------------

    ' Store a catalog row into the board or discover list. "board" appends the
    ' see-all action to its row first; any other target is a discover/search
    ' row and clears the discover request-active flag.
    store.handleCatalogResponse = function(data as dynamic, rowIndex as integer, target as string) as dynamic
        if data = invalid or not data.DoesExist("metas") or data.metas = invalid then return invalid

        items = []
        for each item in data.metas
            items.Push(item)
        end for

        if target = "board"
            action = {
                id: "seeall:" + rowIndex.ToStr()
                name: TrText("board.seeAll")
                type: "action"
                poster: ""
                description: TrText("board.seeAll.description")
                rowIndex: rowIndex
            }
            items.Push(action)
            if rowIndex >= 0 and rowIndex < m._boardRows.Count()
                m._boardRows[rowIndex] = items
            end if
        else
            m._discoverRequestActive = false
            if rowIndex >= 0 and rowIndex < m._discoverRows.Count()
                m._discoverRows[rowIndex] = items
            end if
        end if
    end function

    ' Store a single meta result (IMDb-ID search) into a discover row.
    ' Returns true when a row was stored.
    store.handleSearchMetaResponse = function(data as dynamic, rowIndex as integer) as boolean
        if rowIndex < 0 or rowIndex >= m._discoverRows.Count() then return false
        if data = invalid or not data.DoesExist("meta") or data.meta = invalid then return false
        m._discoverRows[rowIndex] = [data.meta]
        m._discoverRequestActive = false
        return true
    end function

    return store
end function