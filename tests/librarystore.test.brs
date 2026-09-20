' LibraryStore unit tests.
'
' Pure registry-backed store — no transport. Covers saved items (add/remove/
' list) and continue-watching upsert + ordering through a fake registry: the
' array keeps newest-first across reloads, so a fresh write always lands on top.

sub Test_Library_AddAndListSaved()
    Harness_Suite("LibraryStore stores saved items newest first")
    store = LibraryStore(MockRegistry())
    Harness_Ok(store.AddSaved("tt0111161", "movie", "The Shawshank Redemption"), "add first")
    Harness_Ok(store.AddSaved("tt0133093", "movie", "The Matrix", "poster.png"), "add second")
    Harness_Ok(not store.AddSaved("tt0111161", "movie", "The Shawshank Redemption"), "duplicate refused")
    Harness_Ok(not store.AddSaved("", "movie", "No Id"), "blank id refused")

    items = store.SavedItems()
    Harness_Equal(items.Count(), 2, "two saved")
    Harness_Equal(items[0].metaId, "tt0133093", "newest first")
    Harness_Ok(items[0].Lookup("logo") = invalid, "no logo stored")
    Harness_Ok(store.IsSaved("tt0111161"), "is saved")
end sub

sub Test_Library_RemoveSaved()
    Harness_Suite("LibraryStore removes saved items")
    store = LibraryStore(MockRegistry())
    store.AddSaved("tt0111161", "movie", "The Shawshank Redemption")
    Harness_Ok(store.RemoveSaved("tt0111161"), "remove present id")
    Harness_Ok(not store.IsSaved("tt0111161"), "gone after remove")
    Harness_Ok(not store.RemoveSaved("tt0000000"), "remove missing id is false")
end sub

sub Test_Library_ContinueWatchingOrdering()
    Harness_Suite("LibraryStore continue-watching upserts and orders")
    store = LibraryStore(MockRegistry())

    store.SetPosition("tt0133093", "tt0133093", "movie", 0, 0, "The Matrix")
    store.SetPosition("tt1234567:1:1", "tt1234567", "series", 1, 1, "Pilot")
    store.SetPosition("tt1234567:1:1", "tt1234567", "series", 1, 1, "Pilot", "https://img.png", 90, 1800)

    list = store.ContinueWatching()
    Harness_Equal(list.Count(), 2, "two entries")
    Harness_Equal(list[0].videoId, "tt1234567:1:1", "updated entry is most recent")
    Harness_Equal(list[0].position, 90, "position updated")
    Harness_Equal(list[0].duration, 1800, "duration carried")
    Harness_Ok(list[0].Lookup("logo") = invalid, "no logo stored")
    Harness_Equal(store.Position("tt0133093"), 0, "other entry still at zero")
    Harness_Ok(store.IsWatching("tt0133093"), "is watching")
    Harness_Ok(not store.IsWatching("tt9999999"), "not watching a fresh id")
end sub

sub Test_Library_RemovePosition()
    Harness_Suite("LibraryStore removes a continue-watching entry")
    store = LibraryStore(MockRegistry())
    store.SetPosition("tt0133093", "tt0133093", "movie", 0, 0, "The Matrix", "", 300, 3600)
    Harness_Ok(store.RemovePosition("tt0133093"), "remove present position")
    Harness_Equal(store.ContinueWatching().Count(), 0, "list empty after remove")
    Harness_Ok(not store.RemovePosition("tt0133093"), "remove missing position is false")
end sub

sub Test_Library_ResumeFor()
    Harness_Suite("LibraryStore.ResumeFor returns the most recent entry for a meta")
    store = LibraryStore(MockRegistry())
    Harness_Ok(store.ResumeFor("tt0000000") = invalid, "nothing watched is invalid")
    Harness_Ok(store.ResumeFor("") = invalid, "blank id is invalid")

    store.SetPosition("tt0133093", "tt0133093", "movie", 0, 0, "The Matrix")
    store.SetPosition("tt1234567:1:1", "tt1234567", "series", 1, 1, "Pilot")
    store.SetPosition("tt1234567:2:1", "tt1234567", "series", 2, 1, "Cool Hand Luke")

    resume = store.ResumeFor("tt1234567")
    Harness_Ok(resume <> invalid, "found an entry")
    Harness_Equal(resume.videoId, "tt1234567:2:1", "most recent episode wins")
    Harness_Equal(resume.season, 2, "season carried")
    Harness_Equal(resume.episode, 1, "episode carried")
    Harness_Ok(store.ResumeFor("tt0133093").videoId = "tt0133093", "movie entry found")
end sub

sub Test_Library_PersistsViaRegistry()
    Harness_Suite("LibraryStore persists saved + positions across reloads")
    registry = MockRegistry()
    first = LibraryStore(registry)
    first.AddSaved("tt0111161", "movie", "The Shawshank Redemption")
    first.SetPosition("tt0133093", "tt0133093", "movie", 0, 0, "The Matrix", "", 120, 2400)
    first.SetPosition("tt1234567:1:1", "tt1234567", "series", 1, 1, "Pilot", "", 45, 1500)

    second = LibraryStore(registry)
    saved = second.SavedItems()
    watching = second.ContinueWatching()
    Harness_Equal(saved.Count(), 1, "saved restored")
    Harness_Equal(watching.Count(), 2, "positions restored")
    Harness_Equal(second.Position("tt0133093"), 120, "position value restored")
    Harness_Equal(watching[0].videoId, "tt1234567:1:1", "reloaded array keeps newest first")

    second.SetPosition("tt9999999", "tt9999999", "movie", 0, 0, "Brand New")
    Harness_Equal(second.ContinueWatching()[0].videoId, "tt9999999", "new write lands on top")
end sub

sub Test_Library_InMemoryOnlyWithoutRegistry()
    Harness_Suite("LibraryStore works without a registry")
    store = LibraryStore()
    Harness_Ok(store.AddSaved("tt0111161", "movie", "The Shawshank Redemption"), "in-memory add works")
    Harness_Equal(store.SavedItems().Count(), 1, "in-memory list works")

    empty = LibraryStore(MockRegistry())
    Harness_Equal(empty.SavedItems().Count(), 0, "fresh registry starts empty")
end sub

sub Test_Library_PruneSeriesEpisodes()
    Harness_Suite("LibraryStore prune previous episode entries on set")
    store = LibraryStore(MockRegistry())
    store.SetPosition("tt1234567:1:1", "tt1234567", "series", 1, 1, "Pilot")
    store.SetPosition("tt1234567:2:1", "tt1234567", "series", 2, 1, "Cool Hand Luke")
    store.SetPosition("tt0133093", "tt0133093", "movie", 0, 0, "The Matrix")
    list = store.ContinueWatching()
    Harness_Equal(list.Count(), 2, "one series tile + one movie")
    Harness_Equal(list[0].videoId, "tt0133093", "movie most recent")
    Harness_Equal(list[1].videoId, "tt1234567:2:1", "series entry is the latest episode")
    Harness_Ok(not store.IsWatching("tt1234567:1:1"), "old episode pruned")
    Harness_Ok(store.IsWatching("tt1234567:2:1"), "new episode retained")
end sub

sub Test_Library_CapContinueWatching()
    Harness_Suite("LibraryStore caps continue-watching at MAX_CONTINUE_WATCHING")
    store = LibraryStore(MockRegistry())
    for i = 1 to 12
        store.SetPosition("tt" + i.ToStr(), "tt" + i.ToStr(), "movie", 0, 0, "Movie " + i.ToStr())
    end for
    list = store.ContinueWatching()
    Harness_Equal(list.Count(), 8, "capped to eight")
    Harness_Equal(list[0].videoId, "tt12", "newest first")
    Harness_Equal(list[7].videoId, "tt5", "oldest retained is the 8th newest")
end sub

sub Test_Library_ContinueWatchingReturnsCopy()
    Harness_Suite("ContinueWatching hands back a copy so callers can scan it safely")
    store = LibraryStore(MockRegistry())
    store.SetPosition("tt0133093", "tt0133093", "movie", 0, 0, "The Matrix", "", 100, 1000)
    store.SetPosition("tt1234567:1:1", "tt1234567", "series", 1, 1, "Pilot", "", 200, 1000)

    snapshot = store.ContinueWatching()
    Harness_Equal(snapshot.Count(), 2, "two entries")

    ' A caller mutating the returned array must not disturb the store's own
    ' stack: ContinueWatching is a snapshot, not the live m.positions alias.
    snapshot.Clear()
    Harness_Equal(snapshot.Count(), 0, "returned array cleared")
    Harness_Equal(store.ContinueWatching().Count(), 2, "store stack untouched by caller mutation")

    ' Mirror HomeScreen.LibraryRow: loop the result and call a helper that
    ' itself walks m.positions on every entry. The copy keeps the outer loop
    ' intact, so every entry is seen (a live alias drops all but the first).
    seen = 0
    for each entry in store.ContinueWatching()
        store.ProgressFraction(entry.metaId)
        seen = seen + 1
    end for
    Harness_Equal(seen, 2, "nested progress scan sees every entry")
end sub

sub Test_Library_SwitchSessionSeparatesData()
    Harness_Suite("LibraryStore session switch isolates guest and stremio libraries")
    registry = MockRegistry()
    store = LibraryStore(registry)
    store.AddSaved("tt0111161", "movie", "The Shawshank Redemption")
    store.SetPosition("tt0133093", "tt0133093", "movie", 0, 0, "The Matrix", "", 120, 2400)

    store.SwitchSession("stremio")
    Harness_Equal(store.SavedItems().Count(), 0, "stremio session starts empty")
    Harness_Equal(store.ContinueWatching().Count(), 0, "no stremio positions")

    store.SwitchSession("guest")
    Harness_Equal(store.SavedItems().Count(), 1, "guest library restored")
    Harness_Equal(store.ContinueWatching().Count(), 1, "guest positions restored")
    Harness_Equal(store.Position("tt0133093"), 120, "guest position value restored")

    reopened = LibraryStore(registry, "stremio")
    Harness_Equal(reopened.SavedItems().Count(), 0, "stremio registry keys stayed empty")
end sub

sub Test_Library_StremioSessionPersistsOwnKey()
    Harness_Suite("LibraryStore stremio session persists continue-watching only")
    registry = MockRegistry()
    store = LibraryStore(registry, "stremio")
    store.AddSaved("tt0111161", "movie", "The Shawshank Redemption")
    store.SetPosition("tt0133093", "tt0133093", "movie", 0, 0, "The Matrix", "", 120, 2400)

    Harness_Equal(store.SavedItems().Count(), 1, "saved items live in memory for the live session")

    reopened = LibraryStore(registry, "stremio")
    Harness_Equal(reopened.SavedItems().Count(), 0, "saved items are not persisted for a stremio session")
    Harness_Equal(reopened.ContinueWatching().Count(), 1, "continue-watching persists across reloads")
    Harness_Equal(reopened.Position("tt0133093"), 120, "position value restored")

    guest = LibraryStore(registry)
    Harness_Equal(guest.SavedItems().Count(), 0, "guest library unaffected by the stremio save")
end sub

sub Test_Library_GuestSavedCapEvictsOldest()
    Harness_Suite("guest saved library caps at MAX_GUEST_SAVED, evicting the oldest")
    store = LibraryStore(MockRegistry())
    for i = 1 to 105
        store.AddSaved("tt" + Pad3(i), "movie", "Movie " + i.ToStr())
    end for

    items = store.SavedItems()
    Harness_Equal(items.Count(), 100, "capped at one hundred")
    Harness_Equal(items[0].metaId, "tt105", "newest kept first")
    Harness_Equal(items[99].metaId, "tt006", "oldest retained is the 100th newest")
    Harness_Ok(not store.IsSaved("tt001"), "oldest evicted")
    Harness_Ok(not store.IsSaved("tt005"), "pre-cap items beyond the window evicted")
end sub

sub Test_Library_GuestCapPersists()
    Harness_Suite("the guest saved cap survives a registry reload")
    registry = MockRegistry()
    store = LibraryStore(registry)
    for i = 1 to 105
        store.AddSaved("tt" + Pad3(i), "movie", "Movie " + i.ToStr())
    end for

    reopened = LibraryStore(registry)
    items = reopened.SavedItems()
    Harness_Equal(items.Count(), 100, "reloaded list stays capped at one hundred")
    Harness_Equal(items[0].metaId, "tt105", "newest retained across reload")
    Harness_Ok(not reopened.IsSaved("tt001"), "evicted oldest still absent after reload")
end sub

sub Test_Library_StremioSavedUncapped()
    Harness_Suite("stremio session saved library is never capped")
    store = LibraryStore(MockRegistry(), "stremio")
    for i = 1 to 120
        store.AddSaved("tt" + Pad3(i), "movie", "Movie " + i.ToStr())
    end for
    Harness_Equal(store.SavedItems().Count(), 120, "stremio add past the guest cap is kept")

    synced = LibraryStore(MockRegistry(), "stremio")
    items = []
    for i = 1 to 120
        items.Push(LibraryItemFixture("tt" + Pad3(i), "movie", "Movie " + i.ToStr(), "2024-06-" + Pad2(120 - i)))
    end for
    synced.SyncFromStremio(items)
    Harness_Equal(synced.SavedItems().Count(), 120, "synced salvaged library not clamped to the device cap")
end sub

sub Test_Library_ViewFiltersByType()
    Harness_Suite("LibraryView filters saved items by movie/series")
    store = LibraryStore(MockRegistry())
    store.AddSaved("tt001", "movie", "Movie A")
    store.AddSaved("tt002", "series", "Series B")
    store.AddSaved("tt003", "movie", "Movie C")

    all = store.LibraryView("all", "recent")
    Harness_Equal(all.Count(), 3, "all filter keeps everything")
    Harness_Equal(all[0].metaId, "tt003", "all + recent is newest first")

    movies = store.LibraryView("movie", "recent")
    Harness_Equal(movies.Count(), 2, "movie filter keeps only movies")
    Harness_Equal(movies[0].metaId, "tt003", "movie filter keeps recent order")
    Harness_Equal(movies[1].metaId, "tt001", "movie filter keeps both movies")

    series = store.LibraryView("series", "recent")
    Harness_Equal(series.Count(), 1, "series filter keeps only series")
    Harness_Equal(series[0].metaId, "tt002", "series filter picks the series")
end sub

sub Test_Library_ViewSortsByName()
    Harness_Suite("LibraryView sorts saved items A-Z and Z-A")
    store = LibraryStore(MockRegistry())
    store.AddSaved("tt001", "movie", "coral")
    store.AddSaved("tt002", "movie", "Apple")
    store.AddSaved("tt003", "movie", "banana")

    az = store.LibraryView("all", "az")
    Harness_Equal(az[0].name, "Apple", "a-z case-insensitive first")
    Harness_Equal(az[1].name, "banana", "a-z second")
    Harness_Equal(az[2].name, "coral", "a-z last")

    za = store.LibraryView("all", "za")
    Harness_Equal(za[0].name, "coral", "z-a first")
    Harness_Equal(za[1].name, "banana", "z-a second")
    Harness_Equal(za[2].name, "Apple", "z-a last")
end sub

sub Test_Library_ViewSortsWatchedFirst()
    Harness_Suite("LibraryView watched sort floats watched items first")
    store = LibraryStore(MockRegistry())
    store.AddSaved("tt001", "movie", "Unwatched A")
    store.AddSaved("tt002", "movie", "Watched Oldest")
    store.AddSaved("tt003", "movie", "Watched Newest")
    store.AddSaved("tt004", "movie", "Unwatched B")
    store.SetPosition("tt002", "tt002", "movie", 0, 0, "Watched Oldest", "", 30, 1000)
    store.SetPosition("tt003", "tt003", "movie", 0, 0, "Watched Newest", "", 60, 1000)

    watched = store.LibraryView("all", "watched")
    Harness_Equal(watched.Count(), 4, "watched sort keeps everything")
    Harness_Equal(watched[0].metaId, "tt003", "most recently watched first")
    Harness_Equal(watched[1].metaId, "tt002", "older watched second")
    Harness_Equal(watched[2].name, "Unwatched A", "unwatched sorted by name")
    Harness_Equal(watched[3].name, "Unwatched B", "unwatched sorted by name")
end sub

sub Test_Library_ViewDoesNotMutateStore()
    Harness_Suite("LibraryView never rearranges the stored saved order")
    store = LibraryStore(MockRegistry())
    store.AddSaved("tt001", "movie", "Zulu")
    store.AddSaved("tt002", "movie", "Alpha")
    store.AddSaved("tt003", "movie", "Mike")

    store.LibraryView("all", "az")

    items = store.SavedItems()
    Harness_Equal(items[0].metaId, "tt003", "stored order still newest first")
    Harness_Equal(items[1].metaId, "tt002", "stored order unchanged")
    Harness_Equal(items[2].metaId, "tt001", "stored order unchanged")
end sub

sub Test_Library_ViewFiltersWatchedSeriesByMetaId()
    Harness_Suite("watched sort counts a series watched through its episode position")
    store = LibraryStore(MockRegistry())
    store.AddSaved("tt001", "movie", "A Movie")
    store.AddSaved("tt002", "series", "B Series")
    store.SetPosition("tt002:1:1", "tt002", "series", 1, 1, "Episode One", "", 45, 1500)

    watched = store.LibraryView("all", "watched")
    Harness_Equal(watched[0].metaId, "tt002", "series with an episode position floats first")
    Harness_Equal(watched[1].metaId, "tt001", "unwatched movie follows")
end sub

sub Test_Library_MarkWatchedThreshold()
    Harness_Suite("MarkWatchedIfFinished honors the 70% watched threshold")
    store = LibraryStore(MockRegistry())
    store.MarkWatchedIfFinished("ttQW1", "ttQW1", 600, 1000)
    Harness_Ok(not store.IsWatched("ttQW1"), "below threshold is not watched")
    store.MarkWatchedIfFinished("ttQW2", "ttQW2", 700, 1000)
    Harness_Ok(store.IsWatched("ttQW2"), "at threshold is watched")
    store.MarkWatchedIfFinished("ttQW3", "ttQW3", 9000, 10000)
    Harness_Ok(store.IsWatched("ttQW3"), "above threshold is watched")
    store.MarkWatchedIfFinished("ttQW4", "ttQW4", 5000, 0)
    Harness_Ok(not store.IsWatched("ttQW4"), "zero duration is ignored")
    store.MarkWatchedIfFinished("ttQW5", "", 8000, 10000)
    Harness_Ok(store.IsWatched("ttQW5"), "blank videoId keys by the meta id")
end sub

sub Test_Library_MarkWatchedEpisodeKey()
    Harness_Suite("MarkWatchedIfFinished keys episodes by videoId, idempotently")
    store = LibraryStore(MockRegistry())
    store.MarkWatchedIfFinished("ttQW", "ttQW:2:3", 800, 1000)
    Harness_Ok(store.EpisodeWatched("ttQW", 2, 3, []), "episode is marked")
    Harness_Ok(not store.EpisodeWatched("ttQW", 2, 4, []), "a neighbor episode is not marked")
    Harness_Ok(not store.IsWatched("ttQW"), "an episode mark is not a movie mark")
    store.MarkWatchedIfFinished("ttQW", "ttQW:2:3", 900, 1000)
    Harness_Ok(store.EpisodeWatched("ttQW", 2, 3, []), "re-mark stays watched")
    Harness_Equal(store.watched.Count(), 1, "re-mark does not duplicate the entry")
end sub

sub Test_Library_MarkSeriesDone()
    Harness_Suite("MarkSeriesDone persists a whole-series flag idempotently")
    store = LibraryStore(MockRegistry())
    Harness_Ok(not store.EpisodeWatched("ttQW", 1, 1, []), "episode not watched before done")
    store.MarkSeriesDone("ttQW")
    Harness_Ok(store.EpisodeWatched("ttQW", 1, 1, []), "done marks every episode")
    Harness_Ok(store.EpisodeWatched("ttQW", 99, 99, []), "done marks episodes outside a list")
    Harness_Equal(store.SeriesStatus("ttQW"), "done", "series status is done")
    store.MarkSeriesDone("ttQW")
    Harness_Equal(store.watched.Count(), 1, "series-done is idempotent")
end sub

sub Test_Library_SeriesStatusLocal()
    Harness_Suite("SeriesStatus reads local state and defaults to none")
    fresh = LibraryStore(MockRegistry())
    Harness_Equal(fresh.SeriesStatus(""), "none", "blank id is none")
    Harness_Equal(fresh.SeriesStatus("ttQW"), "none", "fresh series is none")

    finished = LibraryStore(MockRegistry())
    finished.MarkWatchedIfFinished("ttQW", "ttQW:1:2", 800, 1000)
    Harness_Equal(finished.SeriesStatus("ttQW"), "progress", "a finished episode counts as in progress")

    playing = LibraryStore(MockRegistry())
    playing.SetPosition("ttQW:1:1", "ttQW", "series", 1, 1, "Pilot", "", 500, 1000)
    Harness_Equal(playing.SeriesStatus("ttQW"), "progress", "an active position counts as in progress")

    started = LibraryStore(MockRegistry())
    started.SetPosition("ttQW:1:1", "ttQW", "series", 1, 1, "Pilot", "", 0, 1000)
    Harness_Equal(started.SeriesStatus("ttQW"), "none", "a zero position is not in progress")

    aged = LibraryStore(MockRegistry())
    aged.SetPosition("ttQW:1:3", "ttQW", "series", 1, 3, "Third", "", 900, 1000)
    aged.MarkWatchedIfFinished("ttQW", "ttQW:1:3", 900, 1000)
    aged.RemovePosition("ttQW:1:3")
    Harness_Equal(aged.SeriesStatus("ttQW"), "progress", "finished episode survives the CW entry aging out")

    done = LibraryStore(MockRegistry())
    done.MarkWatchedIfFinished("ttQW", "ttQW:1:2", 800, 1000)
    done.MarkSeriesDone("ttQW")
    Harness_Equal(done.SeriesStatus("ttQW"), "done", "series-done is done and beats progress")
end sub

sub Test_Library_EpisodeAired()
    Harness_Suite("EpisodeAired gates not-yet-aired episodes")
    store = LibraryStore(MockRegistry())
    now = "2026-09-16T00:00:00.000Z"
    past = { released: "2026-08-05T08:00:00.000Z" }
    today = { released: "2026-09-16T08:00:00.000Z" }
    future = { released: "2026-09-30T08:00:00.000Z", name: "TBA " }
    Harness_Ok(store.EpisodeAired(past, now), "past episode aired")
    Harness_Ok(store.EpisodeAired(today, now), "today's episode aired")
    Harness_Ok(not store.EpisodeAired(future, now), "future episode not aired")
    Harness_Ok(not store.EpisodeAired({ firstAired: "2026-10-07T08:00:00.000Z" }, now), "firstAired fallback respected")
    Harness_Ok(store.EpisodeAired({}, now), "no date means aired")
    Harness_Ok(store.EpisodeAired({ released: "2026-08-05" }, now), "bare date aired")
    Harness_Ok(store.EpisodeAired({ released: "rubbish" }, now), "malformed date means aired")
    Harness_Ok(store.EpisodeAired(invalid, now), "invalid episode means aired")
    Harness_Ok(store.EpisodeAired({ released: "1960-01-01T00:00:00.000Z" }, ""), "past episode aired with no clock")
    Harness_Ok(not store.EpisodeAired({ released: "2100-01-01T00:00:00.000Z" }, invalid), "future episode still unaired with invalid clock")
end sub

sub Test_Library_ProgressFor()
    Harness_Suite("ProgressFor returns the raw resume position for a meta")
    store = LibraryStore(MockRegistry())
    Harness_Ok(store.ProgressFor("") = invalid, "blank id is invalid")
    Harness_Ok(store.ProgressFor("ttQW") = invalid, "never watched is invalid")
    store.SetPosition("ttQW:1:1", "ttQW", "series", 1, 1, "Pilot", "", 90000, 1800000)
    progress = store.ProgressFor("ttQW")
    Harness_Ok(progress <> invalid, "progress found")
    Harness_Equal(progress.position, 90000, "position ms carried")
    Harness_Equal(progress.duration, 1800000, "duration ms carried")
end sub

sub Test_Library_ProgressFraction()
    Harness_Suite("ProgressFraction returns the clamped bar fraction for a meta")
    store = LibraryStore(MockRegistry())
    Harness_Ok(store.ProgressFraction("") = invalid, "blank id is invalid")
    Harness_Ok(store.ProgressFraction("ttQW") = invalid, "never watched is invalid")
    store.SetPosition("ttQW:1:1", "ttQW", "series", 1, 1, "Pilot", "", 450, 1800)
    Harness_Equal(store.ProgressFraction("ttQW"), 0.25, "resume position maps to position/duration")
    store.SetPosition("ttQW:1:1", "ttQW", "series", 1, 1, "Pilot", "", 3000, 1800)
    Harness_Equal(store.ProgressFraction("ttQW"), 1, "past-the-end clamps to one")
    store.AddSaved("ttQW2", "movie", "Zero Duration")
    store.SetPosition("ttQW2", "ttQW2", "movie", 0, 0, "Zero Duration", "", 300, 0)
    Harness_Ok(store.ProgressFraction("ttQW2") = invalid, "zero duration has no bar")
end sub

sub Test_Library_WatchedGlyph()
    Harness_Suite("WatchedGlyph maps watched state to a single glyph token per tile")
    store = LibraryStore(MockRegistry())
    Harness_Equal(store.WatchedGlyph("", "movie"), "", "blank id draws no badge")
    Harness_Equal(store.WatchedGlyph("ttQW", "movie"), "", "unwatched movie draws no badge")
    store.MarkWatchedIfFinished("ttQW", "ttQW", 800, 1000)
    Harness_Equal(store.WatchedGlyph("ttQW", "movie"), "eye", "watched movie uses GLYPH_WATCHED")
    Harness_Equal(store.WatchedGlyph("ttQW", ""), "eye", "missing type still watches by the whole-key check")

    guestSeries = LibraryStore(MockRegistry())
    guestSeries.SetPosition("ttQW:1:1", "ttQW", "series", 1, 1, "Pilot", "", 500, 1000)
    Harness_Equal(guestSeries.WatchedGlyph("ttQW", "series"), "clock", "guest in-progress series uses GLYPH_PROGRESS")
    guestSeries.MarkSeriesDone("ttQW")
    Harness_Equal(guestSeries.WatchedGlyph("ttQW", "series"), "eye", "guest done series uses GLYPH_WATCHED")
    untouched = LibraryStore(MockRegistry())
    Harness_Equal(untouched.WatchedGlyph("ttQW", "series"), "", "fresh guest series draws no badge")

    account = LibraryStore(MockRegistry(), "stremio")
    items = []
    items.Push(LibraryItemFixture("ttGLP", "series", "In Progress", "2024-06-01T00:00:00Z", { timesWatched: 0, timeOffset: 1000 }))
    items.Push(LibraryItemFixture("ttGLD", "series", "Done", "2024-06-02T00:00:00Z"))
    account.SyncFromStremio(items)
    Harness_Equal(account.WatchedGlyph("ttGLP", "series"), "clock", "in-progress series uses GLYPH_PROGRESS")
    Harness_Equal(account.WatchedGlyph("ttGLD", "series"), "eye", "done series uses GLYPH_WATCHED")
    Harness_Equal(account.WatchedGlyph("ttGLD", "movie"), "eye", "movie-type lookup reuses the same watched key")
    Harness_Equal(account.WatchedGlyph("ttGLP", "movie"), "", "in-progress series seen as a movie draws no badge")
end sub

sub Test_Library_WatchedPersistsAcrossReloads()
    Harness_Suite("guest watched state persists across reloads")
    registry = MockRegistry()
    first = LibraryStore(registry)
    first.MarkWatchedIfFinished("ttQW", "ttQW", 800, 1000)
    first.MarkWatchedIfFinished("ttQW2", "ttQW2:1:5", 900, 1000)
    first.MarkSeriesDone("ttQW3")

    second = LibraryStore(registry)
    Harness_Ok(second.IsWatched("ttQW"), "movie watch restored")
    Harness_Ok(second.EpisodeWatched("ttQW2", 1, 5, []), "episode watch restored")
    Harness_Ok(second.EpisodeWatched("ttQW3", 4, 2, []), "series-done restored")
    raw = registry.Read("library")
    parsed = ParseJson(raw)
    Harness_Equal(parsed.watched.Count(), 3, "watched map written to the guest key")
end sub

sub Test_Library_StremioWatchedIsDisplayOnly()
    Harness_Suite("stremio watched is in-memory only, never persisted")
    registry = MockRegistry()
    store = LibraryStore(registry, "stremio")
    store.MarkWatchedIfFinished("ttQW", "ttQW", 800, 1000)
    Harness_Ok(store.IsWatched("ttQW"), "watch is recorded during the live session")
    raw = registry.Read("stremio_library")
    parsed = ParseJson(raw)
    Harness_Ok(parsed <> invalid, "stremio key written")
    Harness_Ok(parsed.watched = invalid, "watched not persisted to the stremio key")

    reopened = LibraryStore(registry, "stremio")
    Harness_Ok(not reopened.IsWatched("ttQW"), "watch does not survive the reload")
end sub

sub Test_Library_WatchedSwitchSessionSeparates()
    Harness_Suite("SwitchSession isolates watched state per session")
    registry = MockRegistry()
    store = LibraryStore(registry)
    store.MarkWatchedIfFinished("ttQW", "ttQW", 800, 1000)

    store.SwitchSession("stremio")
    Harness_Ok(not store.IsWatched("ttQW"), "stremio session starts without local watches")
    Harness_Ok(not store.EpisodeWatched("ttQW", 1, 1, []), "stremio session has no local episodes")

    store.SwitchSession("guest")
    Harness_Ok(store.IsWatched("ttQW"), "guest watches restored after switching back")
end sub
