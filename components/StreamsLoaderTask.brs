' StreamsLoaderTask — back the Streams screen's initial data load off the UI
' thread. Each add-on stream list rides the default request timeout; running it
' inside a Task means a hung add-on costs the worker thread, not a frozen
' channel. The screen already filtered the installed add-ons to those with the
' "stream" resource and built the left panel from its params (no meta fetch
' here), so only the stream addresses cross in. The stores are built fresh
' inside the task scope — no object created on the render thread is shared
' across the thread boundary.
sub init()
    m.top.functionName = "load"
end sub
sub load()
    print "[rokumio] StreamsLoaderTask load() starting"
    try
        http = Transport()
        playback = PlaybackStore(http)

        streams = []
        for each address in m.top.addonAddresses
            answer = playback.Streams(address, m.top.metaType, m.top.videoId)
            if answer.ok and answer.streams <> invalid
                for each stream in answer.streams
                    streams.Push(stream)
                end for
            end if
        end for

        m.top.result = { streams: streams }
        print "[rokumio] StreamsLoaderTask done, streams=" + streams.Count().ToStr()
    catch e
        print "[rokumio] StreamsLoaderTask error: " + e.message
        m.top.result = { streams: [], error: e.message }
    end try
end sub
