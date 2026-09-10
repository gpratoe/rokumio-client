' LibraryStore unit tests.
'
' Pure registry-backed store — no transport. Covers saved items (add/remove/
' list), continue-watching upsert + ordering, and persistence through the fake
' registry: sequence numbers survive a reload, so a fresh instance keeps
' "most recent first" and ranks a brand-new write above everything loaded.

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
    Harness_Equal(watching[0].videoId, "tt1234567:1:1", "reloaded order keeps most recent first")

    second.SetPosition("tt9999999", "tt9999999", "movie", 0, 0, "Brand New")
    Harness_Equal(second.ContinueWatching()[0].videoId, "tt9999999", "new write ranks above loaded seqs")
end sub

sub Test_Library_InMemoryOnlyWithoutRegistry()
    Harness_Suite("LibraryStore works without a registry")
    store = LibraryStore()
    Harness_Ok(store.AddSaved("tt0111161", "movie", "The Shawshank Redemption"), "in-memory add works")
    Harness_Equal(store.SavedItems().Count(), 1, "in-memory list works")

    empty = LibraryStore(MockRegistry())
    Harness_Equal(empty.SavedItems().Count(), 0, "fresh registry starts empty")
end sub