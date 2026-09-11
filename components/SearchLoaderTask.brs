' SearchLoaderTask — back the search screen's query off the UI thread. Both
' type searches (movies, series) ride the default request timeout; running them
' inside a Task means a hung add-on costs the worker thread, not a frozen
' channel. The store is built fresh inside the task scope — no object created on
' the render thread is shared across the thread boundary.
sub init()
    m.top.functionName = "search"
end sub
sub search()
    print "[rokumio] SearchLoaderTask search() starting"
    try
        http = Transport()
        catalog = CatalogStore(http)

        movies = []
        series = []
        if m.top.addonAddress <> "" and m.top.query <> ""
            answer = catalog.Search(m.top.addonAddress, "movie", m.top.query)
            if answer.ok and answer.metas <> invalid then movies = answer.metas
            answer = catalog.Search(m.top.addonAddress, "series", m.top.query)
            if answer.ok and answer.metas <> invalid then series = answer.metas
        end if

        m.top.result = { movies: movies, series: series }
        print "[rokumio] SearchLoaderTask done, movies=" + movies.Count().ToStr() + " series=" + series.Count().ToStr()
    catch e
        print "[rokumio] SearchLoaderTask error: " + e.message
        m.top.result = { movies: [], series: [], error: e.message }
    end try
end sub