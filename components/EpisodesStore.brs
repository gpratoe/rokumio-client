' EpisodesStore.brs
'
' A single point of truth for the series/episode domain: the meta that
' describes a series, its episode list, the derived season grid and the
' filtered episode list (season + watched progress).
'
' MainScene still owns the episode view - the season grid, the episode
' list, the node tree, focus, and the loading/error screens. It reads
' the store for data and fires the request spec it returns through the
' shared HTTP transport.

function CreateEpisodesStore() as object
    store = {
        _selectedItem: invalid
        _episodes: []
        _seriesMeta: invalid
        _seasons: []
        _selectedSeasonIndex: -1
        _selectedEpisodeIndex: -1
        _episodeRequestActive: false
    }

    ' --- state accessors ------------------------------------------------------

    store.selectedItem = function() as object
        return m._selectedItem
    end function

    store.episodes = function() as object
        return m._episodes
    end function

    store.seriesMeta = function() as object
        return m._seriesMeta
    end function

    store.seasons = function() as object
        return m._seasons
    end function

    store.selectedSeasonIndex = function() as integer
        return m._selectedSeasonIndex
    end function

    store.selectedEpisodeIndex = function() as integer
        return m._selectedEpisodeIndex
    end function

    store.episodeRequestActive = function() as boolean
        return m._episodeRequestActive
    end function

    store.setEpisodeRequestActive = function(flag as boolean)
        m._episodeRequestActive = flag
    end function

    ' Wipe the whole series/episode domain (used when the Stremio account is
    ' disconnected, mirroring LibraryStore.clear / CalendarStore.reset).
    store.reset = function()
        m._selectedItem = invalid
        m._episodes = []
        m._seriesMeta = invalid
        m._seasons = []
        m._selectedSeasonIndex = -1
        m._selectedEpisodeIndex = -1
        m._episodeRequestActive = false
    end function

    ' --- lifecycle ------------------------------------------------------------

    ' Prepare the store to load a series. Resets the episode state, marks
    ' a request in flight, and returns the request spec MainScene will fire.
    store.openSeries = function(item as object) as object
        m._selectedItem = item
        m._episodes = []
        m._seriesMeta = invalid
        m._seasons = []
        m._selectedSeasonIndex = -1
        m._selectedEpisodeIndex = -1
        m._episodeRequestActive = true
        return { url: CinemetaMetaUrl("series", SafeString(item, "id")), id: "meta|series" }
    end function

    ' Accept the meta response, store the series meta and episode list,
    ' clear the request-active flag, and tell the scene whether there are
    ' episodes to show.
    store.handleMetaResponse = function(data as object) as object
        m._episodeRequestActive = false
        if data.DoesExist("meta") and data.meta <> invalid and data.meta.DoesExist("videos")
            m._seriesMeta = data.meta
            m._episodes = data.meta.videos
        end if
        return { hasEpisodes: m._episodes.Count() > 0 }
    end function

    ' --- derived data ---------------------------------------------------------

    ' Build the sorted list of unique season numbers from the loaded
    ' episodes. Returns the array so the scene can assign it to
    ' m.seasons and jump to the right row.
    store.buildSeasons = function() as object
        seasons = []
        seen = {}
        for each episode in m._episodes
            season = 0
            if episode.DoesExist("season") then season = episode.season
            key = season.ToStr()
            if not seen.DoesExist(key)
                seen[key] = true
                seasons.Push(season)
            end if
        end for
        seasons.Sort()
        m._seasons = seasons
        return seasons
    end function

    ' Build the episode list visible in the currently selected season,
    ' enriched with watched-progress information from the library.
    ' Returns the array so the scene can assign it to m.visibleEpisodes
    ' and render the cards.
    store.buildVisibleEpisodes = function(seriesId as string, libraryItems as object, blurUnwatched as boolean) as object
        visible = []
        selectedSeason = invalid
        if m._selectedSeasonIndex >= 0 and m._selectedSeasonIndex < m._seasons.Count()
            selectedSeason = m._seasons[m._selectedSeasonIndex]
        end if
        if selectedSeason = invalid then return visible

        watchedIndices = []
        currentVideoId = invalid
        currentTimeOffset = 0
        currentDuration = 0

        ' Find library item by searching the passed libraryItems array
        libraryItem = invalid
        for each item in libraryItems
            if SafeString(item, "_id") = seriesId
                libraryItem = item
                exit for
            end if
        end for

        if libraryItem <> invalid and libraryItem.DoesExist("state") and libraryItem.state <> invalid
            state = libraryItem.state
            if state.DoesExist("watched") and state.watched <> invalid and state.watched <> ""
                info = DecodeWatchedBitfield(state.watched)
                if info <> invalid and info.watchedIndices <> invalid
                    watchedIndices = info.watchedIndices
                end if
            end if
            if state.DoesExist("video_id") then currentVideoId = state.video_id
            if state.DoesExist("timeOffset") then currentTimeOffset = state.timeOffset
            if state.DoesExist("duration") then currentDuration = state.duration
        end if

        episodeFullIndex = -1
        for each episode in m._episodes
            episodeFullIndex = episodeFullIndex + 1
            season = 0
            if episode.DoesExist("season") then season = episode.season
            if season = selectedSeason
                isWatched = false
                for each idx in watchedIndices
                    if idx = episodeFullIndex
                        isWatched = true
                        exit for
                    end if
                end for

                progress = 0.0
                episodeId = SafeString(episode, "id")
                if currentVideoId <> invalid and currentVideoId = episodeId
                    if currentTimeOffset > 0 and currentDuration > 0
                        progress = currentTimeOffset / currentDuration
                    end if
                end if

                episode.BlushThumbnail = blurUnwatched and not isWatched
                episode.IsWatched = isWatched
                episode.Progress = progress
                visible.Push(episode)
            end if
        end for

        m._visibleEpisodes = visible
        return visible
    end function

    ' --- selection ------------------------------------------------------------

    store.setSelectedSeasonIndex = function(index as integer)
        m._selectedSeasonIndex = index
        m._selectedEpisodeIndex = -1
    end function

    store.setSelectedEpisodeIndex = function(index as integer)
        m._selectedEpisodeIndex = index
    end function

    ' --- next episode ---------------------------------------------------------

    ' Returns the next episode after the one currently playing, or invalid
    ' if playback is not a series or there is no next episode.
    store.nextEpisodeLocation = function(playingContentId as string) as object
        if m._episodes.Count() = 0 then return invalid
        foundCurrent = false
        for seasonIndex = 0 to m._seasons.Count() - 1
            season = m._seasons[seasonIndex]
            episodeIndex = 0
            for each episode in m._episodes
                episodeSeason = 0
                if episode.DoesExist("season") then episodeSeason = episode.season
                if episodeSeason = season
                    if foundCurrent
                        return {
                            episode: episode
                            seasonIndex: seasonIndex
                            episodeIndex: episodeIndex
                        }
                    end if
                    if SafeString(episode, "id") = playingContentId then foundCurrent = true
                    episodeIndex = episodeIndex + 1
                end if
            end for
        end for
        return invalid
    end function

    store.hasNextEpisode = function(playingContentId as string) as boolean
        return m.nextEpisodeLocation(playingContentId) <> invalid
    end function

    return store
end function