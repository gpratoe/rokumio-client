' PlaybackStore.brs
'
' A single point of truth for the playback domain: resolving which add-ons
' can stream or subtitle a title, collecting the results, and driving the
' next-episode and resume-progress flow.
'
' MainScene still owns the playback view - the stream/choice lists, the
' video node, the resume dialog, the no-streams screen, and the focus
' handling. It reads the store for data, fires the request specs it
' returns through the shared HTTP transport, and decides what screen to
' show next.

function CreatePlaybackStore(addonStore as object, libraryStore as object) as object
    store = {
        _playbackContentType: "",
        _playbackContentId: "",
        _playbackTitle: "",
        _streamReturnMode: "home",
        _streams: [],
        _subtitles: [],
        _pendingStream: invalid,
        _activeStreamRequestId: "",
        _streamRequestActive: false,
        _pendingStreamRequests: 0,
        _completedStreamRequests: 0,
        _streamRequestErrors: [],
        _activeSubtitleRequestId: "",
        _subtitleRequestActive: false,
        _pendingSubtitleRequests: 0,
        _completedSubtitleRequests: 0,
        _subtitleRequestErrors: [],
        _addonStore: addonStore,
        _libraryStore: libraryStore
    }

    ' --- state accessors ------------------------------------------------------

    store.playbackContentType = function() as string
        return m._playbackContentType
    end function

    store.playbackContentId = function() as string
        return m._playbackContentId
    end function

    store.playbackTitle = function() as string
        return m._playbackTitle
    end function

    store.streamReturnMode = function() as string
        return m._streamReturnMode
    end function

    store.streams = function() as object
        return m._streams
    end function

    store.subtitles = function() as object
        return m._subtitles
    end function

    store.pendingStream = function() as object
        return m._pendingStream
    end function

    store.activeStreamRequestId = function() as string
        return m._activeStreamRequestId
    end function

    store.isStreamRequestActive = function() as boolean
        return m._streamRequestActive
    end function

    store.setStreamRequestActive = function(flag as boolean)
        m._streamRequestActive = flag
    end function

    store.streamRequestErrors = function() as object
        return m._streamRequestErrors
    end function

    store.isSubtitleRequestActive = function() as boolean
        return m._subtitleRequestActive
    end function

    store.setSubtitleRequestActive = function(flag as boolean)
        m._subtitleRequestActive = flag
    end function

    store.activeSubtitleRequestId = function() as string
        return m._activeSubtitleRequestId
    end function

    store.setActiveSubtitleRequestId = function(id as string)
        m._activeSubtitleRequestId = id
    end function

    ' Wipe the whole playback domain (used when the Stremio account is
    ' disconnected, mirroring LibraryStore.clear / CalendarStore.reset).
    store.reset = function()
        m._playbackContentType = ""
        m._playbackContentId = ""
        m._playbackTitle = ""
        m._streamReturnMode = "home"
        m._streams = []
        m._subtitles = []
        m._pendingStream = invalid
        m._activeStreamRequestId = ""
        m._streamRequestActive = false
        m._pendingStreamRequests = 0
        m._completedStreamRequests = 0
        m._streamRequestErrors = []
        m._activeSubtitleRequestId = ""
        m._subtitleRequestActive = false
        m._pendingSubtitleRequests = 0
        m._completedSubtitleRequests = 0
        m._subtitleRequestErrors = []
    end function

    ' --- stream requests ------------------------------------------------------

    ' Prepare the store to resolve streams for one title. Resets the stream
    ' state, records the title metadata, and returns the per-addon request
    ' specs MainScene will fire through the shared transport.
    store.findStreamsForEpisode = function(contentType as string, id as string, title as string, returnMode as string, installedAddons as object) as object
        m._playbackContentType = contentType
        m._playbackContentId = id
        m._playbackTitle = title
        m._streamReturnMode = returnMode
        m._streams = []
        m._completedStreamRequests = 0
        m._streamRequestErrors = []

        matchingAddons = []
        for index = 0 to installedAddons.Count() - 1
            if m._addonStore.AddonSupports(installedAddons[index].manifest, "stream", contentType, id)
                matchingAddons.Push(index)
            end if
        end for

        if matchingAddons.Count() = 0
            m._streamRequestActive = false
            return []
        end if

        m._pendingStreamRequests = matchingAddons.Count()
        specs = []
        for each addonIndex in matchingAddons
            addon = installedAddons[addonIndex]
            url = addon.baseUrl + "/stream/" + contentType + "/" + id + ".json"
            specs.Push({ url: url, addonIndex: addonIndex })
        end for
        return specs
    end function

    store.setActiveStreamRequestId = function(id as string)
        m._activeStreamRequestId = id
    end function

    store.clearStreamRequest = function()
        m._activeStreamRequestId = ""
        m._streamRequestActive = false
        m._pendingStreamRequests = 0
        m._completedStreamRequests = 0
    end function

    ' Accept one stream response. Returns {finished: true} once every
    ' expected response has arrived so the scene can decide what to show.
    store.handleStreamsResponse = function(data as object, addonIndex as integer, installedAddons as object) as object
        if not m._streamRequestActive then return { finished: true }
        addonName = "Unknown add-on"
        if addonIndex >= 0 and addonIndex < installedAddons.Count()
            addonName = SafeString(installedAddons[addonIndex].manifest, "name")
        end if

        if data <> invalid and data.DoesExist("streams") and data.streams <> invalid
            for each stream in data.streams
                directUrl = DirectStreamUrl(stream)
                if directUrl <> ""
                    stream.strokuAddonName = addonName
                    m._streams.Push(stream)
                else if stream <> invalid and stream.DoesExist("infoHash")
                    stream.rokumioTorrent = true
                    stream.strokuAddonName = addonName
                    m._streams.Push(stream)
                end if
            end for
        end if

        m._completedStreamRequests = m._completedStreamRequests + 1
        return { finished: m._completedStreamRequests >= m._pendingStreamRequests }
    end function

    store.addStreamRequestError = function(message as string)
        m._streamRequestErrors.Push(message)
    end function

    store.handleStreamRequestError = function(message as string) as object
        if not m._streamRequestActive then return { finished: true }
        m._streamRequestErrors.Push(message)
        m._completedStreamRequests = m._completedStreamRequests + 1
        return { finished: m._completedStreamRequests >= m._pendingStreamRequests }
    end function

    ' --- subtitle requests ----------------------------------------------------

    ' Prepare the store to resolve subtitles for the current title. Resets
    ' the subtitle state, records the pending stream, and returns the
    ' per-addon request specs MainScene will fire.
    store.findSubtitlesFor = function(stream as object, installedAddons as object) as object
        m._pendingStream = stream
        m._subtitles = []
        m._completedSubtitleRequests = 0
        m._subtitleRequestErrors = []
        m._subtitleRequestActive = true

        matchingAddons = []
        for index = 0 to installedAddons.Count() - 1
            if m._addonStore.AddonSupports(installedAddons[index].manifest, "subtitles", m._playbackContentType, m._playbackContentId)
                matchingAddons.Push(index)
            end if
        end for

        if matchingAddons.Count() = 0
            m._subtitleRequestActive = false
            return []
        end if

        m._pendingSubtitleRequests = matchingAddons.Count()
        specs = []
        for each addonIndex in matchingAddons
            addon = installedAddons[addonIndex]
            url = addon.baseUrl + "/subtitles/" + m._playbackContentType + "/" + m._playbackContentId + ".json"
            specs.Push({ url: url, addonIndex: addonIndex })
        end for
        return specs
    end function

    store.clearSubtitleRequest = function()
        m._activeSubtitleRequestId = ""
        m._subtitleRequestActive = false
        m._pendingSubtitleRequests = 0
        m._completedSubtitleRequests = 0
    end function

    ' Accept one subtitle response. Returns {finished: true} once every
    ' expected response has arrived so the scene can play the pending stream.
    store.handleSubtitlesResponse = function(data as object, addonIndex as integer, installedAddons as object) as object
        if not m._subtitleRequestActive then return { finished: true }
        addonName = "Unknown add-on"
        if addonIndex >= 0 and addonIndex < installedAddons.Count()
            addonName = SafeString(installedAddons[addonIndex].manifest, "name")
        end if
        if data.DoesExist("subtitles") and data.subtitles <> invalid
            for each subtitle in data.subtitles
                if SafeString(subtitle, "url") <> ""
                    subtitle.strokuAddonName = addonName
                    m._subtitles.Push(subtitle)
                end if
            end for
        end if

        m._completedSubtitleRequests = m._completedSubtitleRequests + 1
        return { finished: m._completedSubtitleRequests >= m._pendingSubtitleRequests }
    end function

    store.handleSubtitleRequestError = function(message as string) as object
        if not m._subtitleRequestActive then return { finished: true }
        m._subtitleRequestErrors.Push(message)
        m._completedSubtitleRequests = m._completedSubtitleRequests + 1
        return { finished: m._completedSubtitleRequests >= m._pendingSubtitleRequests }
    end function

    store.playPendingStream = function() as object
        if m._pendingStream = invalid then return invalid
        stream = m._pendingStream
        m._pendingStream = invalid
        return { stream: stream, title: m._playbackTitle, subtitles: m._subtitles }
    end function

' Compute the resume offset for the given playback content id, or 0 to
    ' start from the beginning. The content id is split for series to find
    ' the base library item.
    store.computeResumeOffset = function(playbackContentId as string, libraryItems as object) as float
        if playbackContentId = "" then return 0.0
        if m._playbackContentType <> "series" then return 0.0

        parts = playbackContentId.Split(":")
        lookupId = parts[0]
        if lookupId = "" then return 0.0

        ' Find library item by searching the passed libraryItems array
        libraryItem = invalid
        for each item in libraryItems
            if SafeString(item, "_id") = lookupId
                libraryItem = item
                exit for
            end if
        end for

        if libraryItem = invalid or not libraryItem.DoesExist("state") or libraryItem.state = invalid then return 0.0
        state = libraryItem.state
        if not state.DoesExist("video_id") or state.video_id <> playbackContentId then return 0.0
        if not state.DoesExist("timeOffset") or not state.DoesExist("duration") then return 0.0

        timeOffset = state.timeOffset
        duration = state.duration
        if timeOffset > 10 and duration > 0 and timeOffset < 0.9 * duration
            return timeOffset / 1000
        end if
        return 0.0
    end function

return store
end function