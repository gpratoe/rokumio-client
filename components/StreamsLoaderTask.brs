' StreamsLoaderTask — back the Streams screen's initial data load off the UI
' thread. The meta fetch and each add-on stream list ride the default request
' timeout; running them inside a Task means a hung add-on costs the worker
' thread, not a frozen channel. The screen already filtered the installed
' add-ons to those with the "stream" resource, so only their addresses come
' in. The stores are built fresh inside the task scope — no object created on
' the render thread is shared across the thread boundary.
sub init()
    m.top.functionName = "load"
end sub
sub load()
    print "[rokumio] StreamsLoaderTask load() starting"
    try
        http = Transport()
        playback = PlaybackStore(http)

        meta = invalid
        if m.top.metaAddress <> "" and m.top.metaType <> "" and m.top.metaId <> ""
            episodes = EpisodesStore(http)
            answer = episodes.GetMeta(m.top.metaAddress, m.top.metaType, m.top.metaId)
            if answer.ok then meta = answer.meta
        end if

        streams = []
        for each address in m.top.addonAddresses
            answer = playback.Streams(address, m.top.metaType, m.top.videoId)
            if answer.ok and answer.streams <> invalid
                for each stream in answer.streams
                    streams.Push(stream)
                end for
            end if
        end for

        m.top.result = { meta: meta, streams: streams }
        print "[rokumio] StreamsLoaderTask done, streams=" + streams.Count().ToStr()
    catch e
        print "[rokumio] StreamsLoaderTask error: " + e.message
        m.top.result = { meta: invalid, streams: [], error: e.message }
    end try
end sub
