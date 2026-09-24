' StremioLibraryCodec unit tests — direct, registry-free coverage of the pure
' wire-shape functions that LibraryStore delegates to. The store-level suites
' (watchstatepush / librarywritepush / librarysync) exercise the same code
' through the adapters; these pin the codec on its own, so a regression in the
' adapter wiring and a regression in the mapping logic fail independently.

function CodecItemFixture(metaId as string, options = invalid as dynamic) as object
    item = {
        _id: metaId
        type: "series"
        name: "Fixture " + metaId
        poster: "https://img.example.com/" + metaId + ".png"
        removed: false
        temp: false
        _mtime: "2024-01-01T00:00:00Z"
        state: {
            timeOffset: 0
            duration: 0
            timesWatched: 0
            watched: invalid
        }
    }
    if options <> invalid
        if options.type <> invalid then item.type = options.type
        if options.removed <> invalid then item.removed = options.removed
        if options.temp <> invalid then item.temp = options.temp
        if options.timeOffset <> invalid then item.state.timeOffset = options.timeOffset
        if options.duration <> invalid then item.state.duration = options.duration
        if options.videoId <> invalid then item.state.video_id = options.videoId
        if options.timesWatched <> invalid then item.state.timesWatched = options.timesWatched
        if options.flaggedWatched <> invalid then item.state.flaggedWatched = options.flaggedWatched
        if options.watched <> invalid then item.state.watched = options.watched
        if options.extra <> invalid then item[options.extraKey] = options.extra
    end if
    return item
end function

sub Test_StremioLibraryCodec_ClassifiesItems()
    Harness_Suite("ParseLibraryItem classifies cw/saved/watched/bitfield as the store expects")
    codec = StremioLibraryCodec()

    ' A normal in-progress series episode.
    entry = codec.ParseLibraryItem(CodecItemFixture("tt1:1:1", {
        timeOffset: 312000
    }))
    Harness_Ok(entry <> invalid, "valid series episode parses")
    Harness_Ok(entry.cw, "in-progress episode continues watching")
    Harness_Ok(entry.saved, "non-removed item is saved")
    Harness_Equal(entry.metaId, "tt1:1:1", "meta id travels through")
    Harness_Equal(entry.season, 1, "season decoded from video id")
    Harness_Equal(entry.episode, 1, "episode decoded from video id")
    Harness_Equal(entry.position, 312000, "position is raw ms")

    ' flaggedWatched / timesWatched mark the whole item watched; the raw bitfield
    ' is kept whole for EpisodesScreen.
    watched = codec.ParseLibraryItem(CodecItemFixture("tt9:1:1", {
        timeOffset: 0
        timesWatched: 4
        watched: "tt9:1:1:2:eNpUAA=="
    }))
    Harness_Ok(watched.watchedFlag, "timesWatched marks the item watched")
    Harness_Ok(not watched.inProgress, "reset position is not in progress")
    Harness_Equal(watched.bitfield, "tt9:1:1:2:eNpUAA==", "raw watched bitfield preserved")

    ' A movie (no season/episode) parses with zero season/episode.
    movie = codec.ParseLibraryItem(CodecItemFixture("tt5", { type: "movie" }))
    Harness_Ok(movie <> invalid, "movie parses")
    Harness_Equal(movie.metaType, "movie", "movie type survives")
    Harness_Ok(not movie.cw, "no position means not continue watching")
    Harness_Ok(movie.saved, "movie is saved")
end sub

sub Test_StremioLibraryCodec_RejectsInvalidItems()
    Harness_Suite("ParseLibraryItem rejects invalid and unresolvable items")
    codec = StremioLibraryCodec()
    Harness_Equal(codec.ParseLibraryItem(invalid), invalid, "invalid input yields invalid")
    Harness_Equal(codec.ParseLibraryItem("not an item"), invalid, "non-AA input yields invalid")
    noId = CodecItemFixture("tt1:1:1")
    noId._id = ""
    Harness_Equal(codec.ParseLibraryItem(noId), invalid, "empty meta id yields invalid")
    twoPart = CodecItemFixture("tt2", { videoId: "tt2:5" })
    item = codec.ParseLibraryItem(twoPart)
    Harness_Equal(item, invalid, "video id with a malformed part count yields invalid")
end sub

sub Test_StremioLibraryCodec_BuildWatchStateMerges()
    Harness_Suite("BuildWatchStateItem clones the cached copy and overwrites only watch state")
    codec = StremioLibraryCodec()
    cache = [
        CodecItemFixture("tt1:1:1", {
            timeOffset: 0
            videoId: "tt1:1:1"
            timesWatched: 3
        })
    ]
    packet = {
        metaId: "tt1:1:1"
        videoId: "tt1:1:1"
        position: 438000
        duration: 1200000
        metaType: "series"
        name: "Fixture tt1:1:1"
        poster: "https://img.example.com/tt1:1:1.png"
    }
    built = codec.BuildWatchStateItem("stremio", cache, "2024-06-01T00:00:00Z", packet)
    Harness_Ok(built <> invalid, "build succeeds for a cached item")
    Harness_Equal(built.state.timeOffset, 438000, "position overwritten")
    Harness_Equal(built.state.duration, 1200000, "duration overwritten")
    Harness_Equal(built.state.lastWatched, "2024-06-01T00:00:00Z", "lastWatched stamped")
    Harness_Equal(built.state.timesWatched, 3, "server-authored timesWatched survives")
    Harness_Equal(built.removed, false, "membership flags survive untouched")
    Harness_Equal(built._mtime, "2024-06-01T00:00:00Z", "_mtime stamped")
    Harness_Equal(cache[0].state.timeOffset, 0, "the cache itself is never mutated")
end sub

sub Test_StremioLibraryCodec_BuildWatchStateFallbackAndDefaults()
    Harness_Suite("BuildWatchStateItem falls back to temp for unknown metas and defaults the video id")
    codec = StremioLibraryCodec()
    built = codec.BuildWatchStateItem("stremio", [], "2024-06-01T00:00:00Z", {
        metaId: "tt9"
        position: 2000
        duration: 4000
    })
    Harness_Ok(built <> invalid, "unknown meta still builds a temp entry")
    Harness_Equal(built.removed, true, "temp entry is removed")
    Harness_Equal(built.temp, true, "temp entry is temp")
    Harness_Equal(built.state.video_id, "tt9", "video id defaults to the meta id")
    Harness_Equal(built.state.timeOffset, 2000, "position survives the fallback")
    Harness_Equal(codec.BuildWatchStateItem("guest", [], "2024-06-01T00:00:00Z", {
        metaId: "tt9"
    }), invalid, "guest session refuses to build")
    Harness_Equal(codec.BuildWatchStateItem("stremio", [], "2024-06-01T00:00:00Z", invalid), invalid, "invalid packet is refused")
end sub

sub Test_StremioLibraryCodec_BuildLibraryChange()
    Harness_Suite("BuildLibraryChangeItem toggles membership flags and falls back to a minimal record")
    codec = StremioLibraryCodec()
    cache = [CodecItemFixture("tt1:1:1")]
    added = codec.BuildLibraryChangeItem("stremio", cache, "2024-06-01T00:00:00Z", "tt1:1:1", "series", "Fixture tt1:1:1", "https://img.example.com/tt1:1:1.png", true)
    Harness_Equal(added.removed, false, "add clears removed")
    Harness_Equal(added.temp, false, "add clears temp")
    Harness_Equal(added._mtime, "2024-06-01T00:00:00Z", "add stamps _mtime")
    Harness_Ok(added.state <> invalid, "untracked state survives the clone")

    removed = codec.BuildLibraryChangeItem("stremio", cache, "2024-06-02T00:00:00Z", "tt1:1:1", "series", "Fixture tt1:1:1", "https://img.example.com/tt1:1:1.png", false)
    Harness_Equal(removed.removed, true, "remove flags removed")
    Harness_Equal(removed.temp, false, "remove stays a permanent removal")
    Harness_Equal(removed._mtime, "2024-06-02T00:00:00Z", "remove stamps _mtime")

    fresh = codec.BuildLibraryChangeItem("stremio", [], "2024-06-03T00:00:00Z", "ttX", "movie", "Brand New", "", false)
    Harness_Equal(fresh.removed, true, "unknown meta falls back to removed")
    Harness_Equal(fresh.temp, false, "fallback is a real removal, not temp")
    Harness_Equal(fresh.name, "Brand New", "fallback carries the toggle's name")
    Harness_Equal(codec.BuildLibraryChangeItem("guest", cache, "2024-06-01T00:00:00Z", "tt1:1:1", "series", "", "", true), invalid, "guest session refuses to build")
end sub