' SearchLoaderTask — back one search-catalog query off the UI thread. The screen
' spawns one task per meta type ("movie", "series"), so both type searches run in
' parallel and each publishes its own { metas, metaType } as soon as that one
' catalog answers; a hung add-on costs a worker thread, not a frozen channel. The
' store is built fresh in the task scope — no object created on the render thread
' is shared across the thread boundary.
sub init()
    m.top.functionName = "search"
end sub
sub search()
    print "[rokumio] SearchLoaderTask search() starting type=" + m.top.metaType
    try
        http = Transport()
        catalog = CatalogStore(http)

        metas = []
        error = ""
        if m.top.addonAddress <> "" and m.top.query <> ""
            answer = catalog.Search(m.top.addonAddress, m.top.metaType, m.top.query)
            if answer.ok and answer.metas <> invalid
                metas = answer.metas
            else if answer.error <> invalid and answer.error <> ""
                error = answer.error
            end if
        end if

        result = { metas: metas, metaType: m.top.metaType, error: error }
        m.top.result = result
        print "[rokumio] SearchLoaderTask done, type=" + m.top.metaType + " metas=" + metas.Count().ToStr()
    catch e
        print "[rokumio] SearchLoaderTask error: " + e.message
        m.top.result = { metas: [], metaType: m.top.metaType, error: e.message }
    end try
end sub