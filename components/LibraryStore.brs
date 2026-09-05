' LibraryStore.brs
'
' A single point of truth for the user's Stremio library: the fetched library
' items keyed by id, the two derived catalog lists (currently watching vs.
' previously watched), the pure rules for labelling/toggling items, and the
' network round-trips that fill and mutate that state (datastoreGet /
' datastorePut).
'
' It is a plain associative-array "class" in Roku's documented style: the
' instance captures its fields through m, and MainScene owns one instance
' (m.libraryStore) that it asks for data and hands operations to.
'
' Like the settings and add-on stores, it owns no dialogs and no scene chrome
' (status labels, renders, focus). It DOES return request specs for MainScene to
' fire through the shared HTTP transport, and it accepts raw responses back via
' the handle* methods. The Stremio auth key is NOT stored here -- it lives in the
' auth domain (MainScene for now, its own store in Phase 2) and is passed in as
' an argument where a request needs it.

function CreateLibraryStore() as object
    store = {
        _libraryById: {}
        _libraryItems: []
        _watchedItems: []
    }

    ' --- state accessors ------------------------------------------------------

    store.getLibraryItems = function() as object
        return m._libraryItems
    end function

    store.getWatchedItems = function() as object
        return m._watchedItems
    end function

    store.hasById = function(id as string) as boolean
        return m._libraryById.DoesExist(id)
    end function

    store.getById = function(id as string) as object
        if not m._libraryById.DoesExist(id) then return invalid
        return m._libraryById[id]
    end function

    ' Raw entries (with state) for stores that read watch progress. All
    ' entries are returned (including temp/removed) so auto-added items keep
    ' their watched-progress data, mirroring the getById() contract.
    store.getRawLibraryItems = function() as object
        raw = []
        for each id in m._libraryById
            raw.Push(m._libraryById[id])
        end for
        return raw
    end function

    ' --- state lifecycle ------------------------------------------------------

    ' Wipe all library state (used when the Stremio account is disconnected).
    store.clear = function()
        m._libraryById = {}
        m._libraryItems = []
        m._watchedItems = []
    end function

    ' Replace (or create) the entry for an id, then rebuild the derived lists.
    ' Used by the playback domain when it advances watch progress.
    store.upsertById = function(id as string, libraryItem as object)
        m._libraryById[id] = libraryItem
        m.rebuildCatalog()
    end function

    ' Rebuild _libraryItems/_watchedItems from the authoritative _libraryById map.
    store.rebuildCatalog = function()
        m._libraryItems = []
        m._watchedItems = []

        for each id in m._libraryById
            libraryItem = m._libraryById[id]
            removed = false
            if libraryItem.DoesExist("removed") then removed = libraryItem.removed
            if not removed
                catalogItem = m.LibraryCatalogItem(libraryItem)
                temp = false
                if libraryItem.DoesExist("temp") then temp = libraryItem.temp
                if not temp then m._libraryItems.Push(catalogItem)
                if m.HasWatchedActivity(libraryItem) then m._watchedItems.Push(catalogItem)
            end if
        end for

        m.SortByLastWatched(m._libraryItems)
        m.SortByLastWatched(m._watchedItems)
    end function

    store.LibraryCatalogItem = function(libraryItem as object) as object
        return {
            id: SafeString(libraryItem, "_id")
            name: SafeString(libraryItem, "name")
            type: SafeString(libraryItem, "type")
            poster: SafeString(libraryItem, "poster")
            description: TrText("library.savedDescription")
            libraryItem: libraryItem
        }
    end function

    store.HasWatchedActivity = function(libraryItem as object) as boolean
        if libraryItem = invalid then return false
        if not libraryItem.DoesExist("state") or libraryItem.state = invalid then return false

        state = libraryItem.state
        if SafeString(state, "lastWatched") <> "" then return true
        if state.DoesExist("timeOffset") and state.timeOffset > 0 then return true
        if state.DoesExist("timesWatched") and state.timesWatched > 0 then return true
        return false
    end function

    store.SortByLastWatched = sub(items as object)
        if items = invalid or items.Count() < 2 then return

        for i = 0 to items.Count() - 2
            for j = i + 1 to items.Count() - 1
                if m.LastWatchedSortKey(items[j]) > m.LastWatchedSortKey(items[i])
                    swap = items[i]
                    items[i] = items[j]
                    items[j] = swap
                end if
            end for
        end for
    end sub

    store.LastWatchedSortKey = function(item as object) as string
        if item = invalid or not item.DoesExist("libraryItem") or item.libraryItem = invalid then return ""

        libraryItem = item.libraryItem
        if libraryItem.DoesExist("state") and libraryItem.state <> invalid
            lastWatched = SafeString(libraryItem.state, "lastWatched")
            if lastWatched <> "" then return lastWatched
        end if

        return SafeString(libraryItem, "_mtime")
    end function

    ' --- network: fetch the library (datastoreGet) ----------------------------

    store.fetch = function(authKey as string) as object
        return {
            url: "https://api.strem.io/api/datastoreGet"
            id: "libraryGet|all"
            body: {
                authKey: authKey
                collection: "libraryItem"
                ids: []
                all: true
            }
        }
    end function

    ' Process a datastoreGet response. Returns true when the response was usable
    ' and the state was rebuilt; false when it was rejected (caller shows the
    ' error status).
    store.handleGetResponse = function(data as dynamic) as boolean
        if data = invalid or data.DoesExist("error") or not data.DoesExist("result") then return false

        m._libraryById = {}
        for each libraryItem in data.result
            id = SafeString(libraryItem, "_id")
            if id <> "" then m._libraryById[id] = libraryItem
        end for
        m.rebuildCatalog()
        return true
    end function

    ' --- network: add/remove a library item (datastorePut) --------------------

    ' Build the toggle for a selected catalog item. Returns { mode:"login" } when
    ' the user is signed out (caller starts the link flow), otherwise
    ' { mode:"put", message, request } where request is what MainScene fires.
    store.toggle = function(selectedItem as object, authKey as string) as object
        if selectedItem = invalid then return { mode: "none" }
        if authKey = "" then return { mode: "login" }

        id = SafeString(selectedItem, "id")
        removeItem = false
        if m._libraryById.DoesExist(id)
            existing = m._libraryById[id]
            removeItem = not existing.DoesExist("removed") or not existing.removed
        end if

        change = m.buildLibraryChange(selectedItem, removeItem)
        action = "Adding"
        if removeItem then action = "Removing"

        return {
            mode: "put"
            message: action + " " + SafeString(selectedItem, "name") + "..."
            request: {
                url: "https://api.strem.io/api/datastorePut"
                id: "libraryPut|" + id
                body: {
                    authKey: authKey
                    collection: "libraryItem"
                    changes: [change]
                }
            }
        }
    end function

    ' Build the payload for the silent progress save from the playback domain.
    store.buildProgressPut = function(authKey as string, id as string, libraryItem as object) as object
        return {
            url: "https://api.strem.io/api/datastorePut"
            id: "libraryPutSilent|" + id
            body: {
                authKey: authKey
                collection: "libraryItem"
                changes: [libraryItem]
            }
        }
    end function

    ' Process a datastorePut response; true when it succeeded.
    store.handlePutResponse = function(data as dynamic) as boolean
        if data = invalid or data.DoesExist("error") or not data.DoesExist("result") then return false
        return true
    end function

    ' --- pure rules -----------------------------------------------------------

    ' The toggle label shown on a catalog item: Connect when signed out, Remove
    ' when it is already in the library, otherwise Add.
    store.libraryActionLabel = function(item as dynamic, authKey as string) as string
        if authKey = "" then return TrText("library.action.connect")
        if item <> invalid
            id = SafeString(item, "id")
            if m._libraryById.DoesExist(id)
                libraryItem = m._libraryById[id]
                if not libraryItem.DoesExist("removed") or not libraryItem.removed
                    return TrText("library.action.remove")
                end if
            end if
        end if
        return TrText("library.action.add")
    end function

    store.buildLibraryChange = function(item as object, removed as boolean) as object
        id = SafeString(item, "id")
        now = CreateObject("roDateTime").ToISOString()
        if m._libraryById.DoesExist(id)
            change = m._libraryById[id]
            change.removed = removed
            change.temp = false
            change._mtime = now
            return change
        end if

        return {
            _id: id
            name: SafeString(item, "name")
            type: SafeString(item, "type")
            poster: SafeString(item, "poster")
            posterShape: "poster"
            removed: removed
            temp: false
            _ctime: now
            _mtime: now
            state: {
                lastWatched: invalid
                timeWatched: 0
                timeOffset: 0
                overallTimeWatched: 0
                timesWatched: 0
                flaggedWatched: 0
                duration: 0
                video_id: invalid
                watched: invalid
                noNotif: false
            }
            behaviorHints: {
                defaultVideoId: invalid
                featuredVideoId: invalid
                hasScheduledVideos: false
            }
        }
    end function

    return store
end function
