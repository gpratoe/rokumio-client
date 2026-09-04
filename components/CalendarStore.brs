' CalendarStore.brs
'
' A single point of truth for the calendar domain: the dated episodes of every
' tracked series, the metadata round-trips that fill them (cinemeta), the
' request caps that keep those round-trips sane, and the rows the calendar
' list renders.
'
' MainScene still owns the calendar view - the list and its focus/echo
' handling (m.calendarRows / m.calendarFocusIndex / m.calendarSuppressIndex),
' UpdateCalendarDetail, and the CalendarRowSelectable / NextSelectableCalendarIndex
' helpers - and fires the request specs this store returns through the shared
' HTTP transport. The store owns all calendar state, both ways: load() returns
' the specs to fire, handleMetaResponse() accepts the raw response back.

function CreateCalendarStore() as object
    store = {
        _calendarEntries: []
        _calendarLoadedSeries: {}
        _calendarRequestActive: false
    }

    ' --- state accessors ------------------------------------------------------

    store.getEntries = function() as object
        return m._calendarEntries
    end function

    store.getRequestActive = function() as boolean
        return m._calendarRequestActive
    end function

    ' --- lifecycle ------------------------------------------------------------

    ' Drop every entry, loaded marker, and in-flight request when the user
    ' signs out; the next sign-in starts the calendar empty.
    store.reset = function()
        m._calendarEntries = []
        m._calendarLoadedSeries = {}
        m._calendarRequestActive = false
    end function

    ' --- network: the metadata round-trips ------------------------------------

    ' Walk the library and return request specs (url + id) for the series that
    ' still need their metadata loaded. Capped the same way the old scene code
    ' capped them: never track more than 24 series, never put more than 4
    ' requests in flight. MainScene fires each spec.
    store.load = function(libraryItems as object) as object
        specs = []
        if m.countTrackedSeries() >= 24 then return specs
        pending = m.countPendingRequests()
        for each item in libraryItems
            if SafeString(item, "type") = "series"
                id = SafeString(item, "id")
                if id <> "" and not m._calendarLoadedSeries.DoesExist(id)
                    m._calendarLoadedSeries[id] = "loading"
                    m._calendarRequestActive = true
                    pending = pending + 1
                    specs.Push({ url: CinemetaMetaUrl("series", id), id: "calendarMeta|" + id })
                end if
            end if
            if m.countTrackedSeries() >= 24 or pending >= 4 then exit for
        end for
        return specs
    end function

    ' Store the dated episodes of one series. Library items come in as an
    ' argument so this store never reaches into the library store; MainScene
    ' supplies them at the call site. Marks the series loaded, trims the whole
    ' calendar back to its slot budget, and clears the request-active flag when
    ' nothing is still in flight.
    store.handleMetaResponse = function(data as dynamic, seriesId as string, libraryItems as object) as dynamic
        if data <> invalid and data.DoesExist("meta") and data.meta <> invalid and data.meta.DoesExist("videos")
            seriesItem = invalid
            for each item in libraryItems
                if SafeString(item, "id") = seriesId
                    seriesItem = item
                    exit for
                end if
            end for
            if seriesItem <> invalid
                for each episode in data.meta.videos
                    released = SafeString(episode, "released")
                    if Len(released) >= 10
                        m._calendarEntries.Push({
                            date: Left(released, 10)
                            series: seriesItem
                            episode: episode
                        })
                    end if
                end for
            end if
        end if
        m._calendarLoadedSeries[seriesId] = "loaded"
        m.trimEntries()
        m._calendarRequestActive = m.hasPendingRequests()
        return invalid
    end function

    store.countPendingRequests = function() as integer
        count = 0
        for each id in m._calendarLoadedSeries
            if m._calendarLoadedSeries[id] = "loading" then count = count + 1
        end for
        return count
    end function

    store.countTrackedSeries = function() as integer
        count = 0
        for each id in m._calendarLoadedSeries
            count = count + 1
        end for
        return count
    end function

    store.hasPendingRequests = function() as boolean
        return m.countPendingRequests() > 0
    end function

    ' --- the rows the calendar list renders -----------------------------------

    ' The list slots (48) are split between upcoming and recent. Sort each half
    ' and keep only its top 24, oldest entries first when the trim reads the
    ' array top down.
    store.trimEntries = function() as dynamic
        if m._calendarEntries.Count() <= 48 then return invalid
        today = Left(CreateObject("roDateTime").ToISOString(), 10)
        upcoming = []
        recent = []
        for each entry in m._calendarEntries
            dateText = SafeString(entry, "date")
            if dateText >= today
                m.addSortedEntry(upcoming, entry, true, 24)
            else
                m.addSortedEntry(recent, entry, false, 24)
            end if
        end for

        trimmed = []
        for each entry in upcoming
            trimmed.Push(entry)
        end for
        for each entry in recent
            trimmed.Push(entry)
        end for
        m._calendarEntries = trimmed
        return invalid
    end function

    ' Insert an entry keeping `entries` sorted by date, then drop anything past
    ' maxCount so fitting the list slots never walks more than one column.
    store.addSortedEntry = function(entries as object, entry as object, ascending as boolean, maxCount as integer)
        entries.Push(entry)
        index = entries.Count() - 1
        while index > 0
            currentDate = SafeString(entries[index], "date")
            previousDate = SafeString(entries[index - 1], "date")
            shouldSwap = (ascending and currentDate < previousDate) or ((not ascending) and currentDate > previousDate)
            if not shouldSwap then exit while
            swap = entries[index - 1]
            entries[index - 1] = entries[index]
            entries[index] = swap
            index = index - 1
        end while
        if entries.Count() > maxCount then entries.Delete(maxCount)
    end function

    ' The signed-out calendar is three message rows plus the one focusable Log
    ' in button.
    store.buildSignedOutRows = function() as object
        return [
            m.messageRow(TrText("calendar.signedOut.title"))
            m.messageRow(TrText("calendar.signedOut.benefit1"))
            m.messageRow(TrText("calendar.signedOut.benefit2"))
            m.row("cta", TrText("calendar.signedOut.login"), "login", invalid)
        ]
    end function

    ' Build the action rows for the calendar list: empty-state copy when the
    ' library or the calendar itself is empty, then the upcoming / recent
    ' sections with their episode cards.
    store.buildActions = function(libraryItems as object) as object
        actions = []
        if libraryItems.Count() = 0
            actions.Push(m.messageRow(TrText("calendar.empty.noSeries")))
            actions.Push(m.messageRow(TrText("calendar.empty.addSeries")))
            return actions
        end if

        if m._calendarRequestActive and m._calendarEntries.Count() = 0
            actions.Push(m.messageRow(TrText("calendar.loading")))
            return actions
        end if

        if m._calendarEntries.Count() = 0
            actions.Push(m.messageRow(TrText("calendar.empty.noDates")))
            return actions
        end if

        today = Left(CreateObject("roDateTime").ToISOString(), 10)
        upcoming = []
        recent = []
        for each entry in m._calendarEntries
            dateText = SafeString(entry, "date")
            if dateText >= today
                m.addSortedEntry(upcoming, entry, true, 12)
            else
                m.addSortedEntry(recent, entry, false, 12)
            end if
        end for

        if upcoming.Count() > 0
            actions.Push(m.headerRow(TrText("calendar.section.upcoming")))
            for each entry in upcoming
                actions.Push(m.episodeRow(entry, today))
            end for
        end if

        if recent.Count() > 0
            actions.Push(m.headerRow(TrText("calendar.section.recent")))
            for each entry in recent
                actions.Push(m.episodeRow(entry, today))
            end for
        end if
        return actions
    end function

    ' Builds the card for one dated episode. Dates, titles, and descriptions
    ' belong to the add-on that returned them, so they are shown as they
    ' arrived; only the day number and short month are split out for the date
    ' chip.
    store.episodeRow = function(entry as object, today as string) as object
        episode = entry.episode
        series = entry.series
        dateText = SafeString(entry, "date")

        title = EpisodeTitle(episode)
        if title = "" then title = TrText("calendar.untitledEpisode")

        row = m.row("episode", title, "calendarEpisode", entry)
        row.dateText = dateText
        row.dayText = m.dayNumber(dateText)
        row.monthText = m.monthLabel(dateText)
        row.seriesName = SafeString(series, "name")
        row.episodeLabel = m.episodeLabel(episode)
        row.description = EpisodeDescription(episode)
        row.accent = dateText = today
        if row.accent
            row.statusText = TrText("calendar.status.today")
        else if dateText > today
            row.statusText = TrText("calendar.status.upcoming")
        else
            row.statusText = TrText("calendar.status.aired")
        end if
        row.metaText = m.entryMeta(row)

        row.thumbnailUrl = SafeString(episode, "thumbnail")
        if row.thumbnailUrl = "" then row.thumbnailUrl = SafeString(series, "poster")
        return row
    end function

    store.entryMeta = function(row as object) as string
        parts = []
        if row.episodeLabel <> "" then parts.Push(row.episodeLabel)
        if row.dateText <> "" then parts.Push(row.dateText)
        if row.statusText <> "" then parts.Push(row.statusText)
        return JoinStrings(parts, "    ")
    end function

    store.episodeLabel = function(episode as object) as string
        season = SafeString(episode, "season")
        number = SafeString(episode, "episode")
        if number = "" then number = SafeString(episode, "number")
        if season = "" and number = "" then return ""
        if season = "" then return "E" + number
        if number = "" then return "S" + season
        return "S" + season + "E" + number
    end function

    ' "2026-07-26" -> "26". Anything that is not an ISO date is passed through.
    store.dayNumber = function(dateText as string) as string
        if Len(dateText) < 10 then return dateText
        day = Int(Val(Mid(dateText, 9, 2)))
        if day < 1 or day > 31 then return dateText
        return day.ToStr()
    end function

    ' Short month name for the date chip. This is Stroku's own label rather
    ' than add-on text, so it follows the interface language.
    store.monthLabel = function(dateText as string) as string
        if Len(dateText) < 10 then return ""
        month = Int(Val(Mid(dateText, 6, 2)))
        if month < 1 or month > 12 then return ""
        keys = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        return TrText("calendar.month." + keys[month - 1])
    end function

    ' One-line summary of a dated episode, used for the footer bar under the
    ' list.
    store.entryTitle = function(entry as object) as string
        if entry = invalid then return ""
        episode = entry.episode
        series = entry.series
        return SafeString(entry, "date") + "    " + SafeString(series, "name") + "    " + EpisodeTitle(episode)
    end function

    ' --- row shape ------------------------------------------------------------

    ' One calendar row. Rows carry the same actionType/payload pair as
    ' InfoAction so both lists dispatch through onPrimaryInfoSelected. The
    ' view decides whether a row can take focus by reading kind / actionType
    ' (CalendarRowSelectable in MainScene).
    store.row = function(kind as string, title as string, actionType as string, payload as dynamic) as object
        return {
            kind: kind
            title: title
            actionType: actionType
            payload: payload
            dayText: ""
            monthText: ""
            seriesName: ""
            episodeLabel: ""
            metaText: ""
            dateText: ""
            thumbnailUrl: ""
            description: ""
            statusText: ""
            accent: false
        }
    end function

    ' Section captions and empty-state copy are inert: they occupy a row slot
    ' but can never take focus, so OK on the calendar always means "open a
    ' series".
    store.headerRow = function(title as string) as object
        return m.row("header", title, "none", invalid)
    end function

    store.messageRow = function(title as string) as object
        return m.row("message", title, "none", invalid)
    end function

    return store
end function