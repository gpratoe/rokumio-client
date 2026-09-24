' TimeUtil unit tests.
'
' The date helpers are pure calendar logic over strings (NowIso is the only
' platform call, guarded and unused by anything that passes an explicit nowIso),
' so they run fully in the interpreter and cannot diverge from a device.

sub Test_TimeUtil_EpisodeAiredGates()
    Harness_Suite("EpisodeAired gates not-yet-aired episodes")
    time = TimeUtil()
    now = "2026-09-16T00:00:00.000Z"
    past = { released: "2026-08-05T08:00:00.000Z" }
    today = { released: "2026-09-16T08:00:00.000Z" }
    future = { released: "2026-09-30T08:00:00.000Z", name: "TBA " }
    Harness_Ok(time.EpisodeAired(past, now), "past episode aired")
    Harness_Ok(time.EpisodeAired(today, now), "today's episode aired")
    Harness_Ok(not time.EpisodeAired(future, now), "future episode not aired")
    Harness_Ok(not time.EpisodeAired({ firstAired: "2026-10-07T08:00:00.000Z" }, now), "firstAired fallback respected")
    Harness_Ok(time.EpisodeAired({}, now), "no date means aired")
    Harness_Ok(time.EpisodeAired({ released: "2026-08-05" }, now), "bare date aired")
    Harness_Ok(time.EpisodeAired({ released: "rubbish" }, now), "malformed date means aired")
    Harness_Ok(time.EpisodeAired(invalid, now), "invalid episode means aired")
    Harness_Ok(time.EpisodeAired({ released: "1960-01-01T00:00:00.000Z" }, ""), "past episode aired with no clock")
    Harness_Ok(not time.EpisodeAired({ released: "2100-01-01T00:00:00.000Z" }, invalid), "future episode still unaired with invalid clock")
end sub

sub Test_TimeUtil_IsCalendarDateShape()
    Harness_Suite("IsCalendarDate accepts well-formed dates only")
    time = TimeUtil()
    Harness_Ok(time.IsCalendarDate("2026-09-16"), "full YYYY-MM-DD accepted")
    Harness_Ok(not time.IsCalendarDate("2026-09"), "too short rejected")
    Harness_Ok(not time.IsCalendarDate("2026-9-16"), "non-padded month rejected")
    Harness_Ok(not time.IsCalendarDate("2026/09/16"), "non-dash separators rejected")
    Harness_Ok(not time.IsCalendarDate("abcdefghij"), "non-digit characters rejected")
    Harness_Ok(not time.IsCalendarDate(""), "empty rejected")
end sub

sub Test_TimeUtil_NowIsoShape()
    Harness_Suite("NowIso returns an ISO timestamp or empty when the clock is unavailable")
    time = TimeUtil()
    now = time.NowIso()
    Harness_Ok(Type(now) = "String", "NowIso returns a string")
    Harness_Ok(now = "" or now.Len() >= 20, "NowIso is an ISO timestamp or empty")
end sub