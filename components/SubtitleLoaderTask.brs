' SubtitleLoaderTask — fetch the caption tracks for the playing video off the
' UI thread. The screen already picked the add-on that advertises the
' "subtitles" resource, so only its address comes in. The store + transport are
' built fresh inside the task scope — no object created on the render thread is
' shared across the thread boundary. The result never gates playback: subtitles
' attach whenever they arrive, before or after the stream starts.
sub init()
    m.top.functionName = "load"
end sub
sub load()
    print "[rokumio] SubtitleLoaderTask starting"
    try
        http = Transport()
        store = SubtitlesStore(http)
        answer = store.Subtitles(m.top.addonAddress, m.top.metaType, m.top.videoId)
        if answer.ok
            m.top.result = { ok: true, subtitles: answer.subtitles, error: "" }
        else
            print "[rokumio] SubtitleLoaderTask error: " + answer.error
            m.top.result = { ok: false, subtitles: [], error: answer.error }
        end if
    catch e
        print "[rokumio] SubtitleLoaderTask error: " + e.message
        m.top.result = { ok: false, subtitles: [], error: e.message }
    end try
end sub