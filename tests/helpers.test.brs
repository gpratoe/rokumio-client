' Helpers — StringOf/FormatRuntime unit tests.
'
' Add-on JSON is where these values come from, so every fixture is parsed with
' ParseJson rather than written as a literal: the point of StringOf is that a
' number, a boolean or a container arriving where text belongs becomes text (or
' nothing) instead of a runtime Type Mismatch in whatever render path touched
' it first.

sub Test_Helpers_StringOf_PassesStringsThrough()
    Harness_Suite("Helpers.StringOf leaves a real string alone")
    Harness_Equal(StringOf("8.1"), "8.1", "a string passes through untouched")
    Harness_Equal(StringOf(""), "", "an empty string stays empty")
    Harness_Equal(StringOf("Kodi · 1080p"), "Kodi · 1080p", "punctuation survives")
end sub

sub Test_Helpers_StringOf_CoercesNumbers()
    Harness_Suite("Helpers.StringOf renders add-on numbers the way the spec says")
    ' The interpreter spells a parsed number "Float"/"Integer"; a device reports
    ' the "ro" spellings for the same values. The helper reads neither — it goes
    ' through ToStr() — so these assertions hold on both.
    Harness_Equal(StringOf(ParseJson("8.1")), "8.1", "a JSON float renders as itself")
    Harness_Equal(StringOf(ParseJson("8.10")), "8.1", "a trailing zero is not echoed")
    Harness_Equal(StringOf(ParseJson("8.0")), "8", "an integral float loses the tail")
    Harness_Equal(StringOf(ParseJson("8")), "8", "a JSON int renders")
    Harness_Equal(StringOf(ParseJson("121")), "121", "minutes render")
end sub

sub Test_Helpers_StringOf_CoercesBooleans()
    Harness_Suite("Helpers.StringOf renders booleans")
    Harness_Equal(StringOf(ParseJson("true")), "true", "true")
    Harness_Equal(StringOf(ParseJson("false")), "false", "false")
end sub

sub Test_Helpers_StringOf_EmptiesWhatHasNoText()
    Harness_Suite("Helpers.StringOf has no text for a non-text")
    ' invalid is first because ToStr answers the literal "invalid" for it, and
    ' the word would be wrong on screen.
    Harness_Equal(StringOf(invalid), "", "invalid is empty, not the word invalid")
    Harness_Equal(StringOf(ParseJson(chr(123) + QuoteString("a") + ":1" + chr(125))), "", "an associative array is empty")
    Harness_Equal(StringOf(ParseJson("[1,2]")), "", "an array is empty")
end sub

sub Test_Helpers_StringOf_KeepsTheHeaderLineAlive()
    Harness_Suite("Helpers.StringOf survives the concatenation that crashed")
    ' The bug this whole file exists for: kind + " · ★ " + imdbRating threw
    ' "Type Mismatch. Operator '+' can't be applied to 'String' and 'Float'"
    ' the moment an add-on answered the rating with the JSON number 8.1.
    meta = { imdbRating: ParseJson("8.1"), releaseInfo: ParseJson("2024") }
    line = "Movie · " + StringOf(meta.releaseInfo) + " · ★ " + StringOf(meta.imdbRating)
    Harness_Equal(line, "Movie · 2024 · ★ 8.1", "the header builds instead of throwing")

    ' And a container in the rating slot degrades to nothing rather than taking
    ' the line down.
    broken = { imdbRating: ParseJson(chr(123) + chr(125)) }
    line2 = "★ " + StringOf(broken.imdbRating)
    Harness_Equal(line2, "★ ", "an object rating renders nothing")
end sub

sub Test_Helpers_FormatRuntime()
    Harness_Suite("Helpers.FormatRuntime echoes the runtime or nothing")
    ' Runtime is plain minutes from Cinemeta — no parsing, no "2h 5m".
    Harness_Equal(FormatRuntime(ParseJson("121")), "121", "minutes echo straight")
    Harness_Equal(FormatRuntime(ParseJson("120.0")), "120", "an integral float loses the tail")
    Harness_Equal(FormatRuntime("121"), "121", "a string runtime passes through")
    Harness_Equal(FormatRuntime(invalid), "", "no runtime is empty")
end sub

sub Test_Helpers_GenreLabel_TranslatesAndFallsBack()
    Harness_Suite("Helpers.GenreLabel translates known genres and falls back")
    m._texts = {
        genres: {
            Action: "Acción"
            "Reality-TV": "Telerrealidad"
        }
    }
    m._textsEn = {
        genres: {
            Action: "Action"
            Drama: "Drama"
        }
    }

    Harness_Equal(GenreLabel("Action"), "Acción", "current language translation wins")
    Harness_Equal(GenreLabel("Drama"), "Drama", "falls back to English texts when missing in current language")
    Harness_Equal(GenreLabel("Custom-Genre"), "Custom-Genre", "unknown genre falls back to original string")
    Harness_Equal(GenreLabel(""), "", "empty genre stays empty")

    m._texts = invalid
    m._textsEn = invalid
end sub

sub Test_Helpers_HeroGenresText_UsesTranslationsAndFallback()
    Harness_Suite("Helpers.HeroGenresText joins translated genres and keeps fallbacks")
    m._texts = {
        genres: {
            Action: "Acción"
            Comedy: "Comedia"
            New: "Nuevo"
        }
    }
    m._textsEn = {
        genres: {
            Drama: "Drama"
        }
    }

    line = HeroGenresText(["Action", "Comedy", "Indie", "New"])
    Harness_Equal(line, "Acción  ·  Comedia  ·  Indie  ·  Nuevo", "mixes translated and original genres")
    Harness_Equal(HeroGenresText([]), "", "empty list returns empty string")
    Harness_Equal(HeroGenresText(invalid), "", "invalid input returns empty string")

    m._texts = invalid
    m._textsEn = invalid
end sub
