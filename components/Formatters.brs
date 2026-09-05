' Pure display/formatting helpers shared by MainScene and the stores (read-only,

' stateless). These turn raw add-on/stream/episode/meta data into display strings

' and parse display strings back into display tokens. Split out of MainScene.brs

' and Helpers.brs during the Phase 6 utility strip.

function StreamCardTitle(stream as object) as string
    title = SafeString(stream, "title")
    if title = "" then title = SafeString(stream, "name")
    return FirstLine(title)
end function

function StreamSourceBadge(stream as object) as string
    name = SafeString(stream, "name")
    if name = "" then name = SafeString(stream, "title")
    firstLineText = FirstLine(name)
    return ExtractSourceTag(firstLineText)
end function

function StreamAddonName(stream as object) as string
    name = SafeString(stream, "name")
    if name = "" then name = SafeString(stream, "title")
    firstLineText = FirstLine(name)
    badge = ExtractSourceTag(firstLineText)
    if badge <> ""
        firstLineText = firstLineText.Replace(badge, "").Trim()
    end if
    if firstLineText <> "" then return firstLineText
    return SafeString(stream, "strokuAddonName")
end function

function StreamQuality(stream as object) as string
    name = SafeString(stream, "name")
    if name = "" then return "Direct"
    lines = name.Replace(Chr(13), "").Tokenize(Chr(10))
    if lines.Count() >= 2
        return lines[lines.Count() - 1].Trim()
    end if
    
    ' If only one line, let's see if we can extract quality from the title or filename
    title = SafeString(stream, "title")
    if title <> ""
        lowerTitle = LCase(title)
        if Instr(1, lowerTitle, "2160p") > 0 or Instr(1, lowerTitle, "4k") > 0
            return "2160p"
        else if Instr(1, lowerTitle, "1080p") > 0
            return "1080p"
        else if Instr(1, lowerTitle, "720p") > 0
            return "720p"
        else if Instr(1, lowerTitle, "480p") > 0
            return "480p"
        end if
    end if
    
    ' Check if the first line itself has quality info
    fLineText = lines[0].Trim()
    lowerFirst = LCase(fLineText)
    if Instr(1, lowerFirst, "2160p") > 0 or Instr(1, lowerFirst, "4k") > 0
        return "2160p"
    else if Instr(1, lowerFirst, "1080p") > 0
        return "1080p"
    else if Instr(1, lowerFirst, "720p") > 0
        return "720p"
    end if

    return "Direct"
end function

function StreamMetadataText(stream as object) as string
    metadataText = MetadataLineFromText(SafeString(stream, "title"))
    if metadataText <> "" then return metadataText

    metadataText = MetadataLineFromText(SafeString(stream, "description"))
    if metadataText <> "" then return metadataText

    metadataText = MetadataLineFromText(SafeString(stream, "name"))
    if metadataText <> "" then return metadataText

    if stream.DoesExist("behaviorHints") and stream.behaviorHints <> invalid
        hints = stream.behaviorHints
        metadataText = MetadataLineFromText(SafeString(hints, "bingeGroup"))
        if metadataText <> "" then return metadataText
    end if

    return ""
end function

function MetadataLineFromText(value as string) as string
    if value = "" then return ""
    normalized = value.Replace(Chr(13), "")
    for each line in normalized.Tokenize(Chr(10))
        candidate = line.Trim()
        if ExtractSize(candidate) <> "" or ExtractSeeders(candidate) <> ""
            return candidate
        end if
    end for
    return ""
end function

function ExtractSeeders(secondLineText as string) as string
    if secondLineText = "" then return ""
    tokens = secondLineText.Tokenize(" ")
    for i = 0 to tokens.Count() - 1
        token = tokens[i].Trim()
        lower = LCase(token)
        if Instr(1, token, Chr(128100)) > 0
            if i + 1 < tokens.Count() then return tokens[i+1].Trim()
        end if
        if lower = "seeds:" or lower = "seeders:" or lower = "peers:" or lower = "s:"
            if i + 1 < tokens.Count() then return tokens[i+1].Trim()
        end if
        if lower = "seeds" or lower = "seeders" or lower = "peers"
            if i > 0 then return tokens[i-1].Trim()
        end if
    end for
    if tokens.Count() >= 2 and IsNumericText(tokens[1])
        return tokens[1].Trim()
    end if
    return ""
end function

function ExtractSize(secondLineText as string) as string
    if secondLineText = "" then return ""
    tokens = secondLineText.Tokenize(" ")
    for i = 0 to tokens.Count() - 1
        token = tokens[i].Trim()
        lower = LCase(token)
        if Instr(1, token, Chr(128190)) > 0
            if i + 1 < tokens.Count()
                nextToken = tokens[i+1].Trim()
                if IsSizeUnit(nextToken)
                    return nextToken
                end if
                if i + 2 < tokens.Count() and IsSizeUnit(tokens[i+2])
                    return nextToken + " " + tokens[i+2].Trim()
                end if
                return nextToken
            end if
        end if
        if IsSizeUnit(token)
            firstChar = Left(token, 1)
            if firstChar >= "0" and firstChar <= "9"
                return token
            else if i > 0
                return tokens[i-1].Trim() + " " + token
            end if
        end if
    end for
    return ""
end function

function IsSizeUnit(token as string) as boolean
    lower = LCase(token)
    return Right(lower, 2) = "gb" or Right(lower, 2) = "mb" or Right(lower, 2) = "kb" or Right(lower, 3) = "gib" or Right(lower, 3) = "mib" or Right(lower, 3) = "kib"
end function

function ExtractTracker(secondLineText as string, addonName as string) as string
    if secondLineText = "" then return addonName
    tokens = secondLineText.Tokenize(" ")
    for i = 0 to tokens.Count() - 1
        token = tokens[i].Trim()
        lower = LCase(token)
        if Instr(1, token, Chr(9881)) > 0
            if i + 1 < tokens.Count() then return tokens[i+1].Trim()
        end if
        if lower = "tracker:" or lower = "provider:" or lower = "p:"
            if i + 1 < tokens.Count() then return tokens[i+1].Trim()
        end if
    end for
    for i = 0 to tokens.Count() - 1
        if IsSizeUnit(tokens[i])
            for j = i + 1 to tokens.Count() - 1
                candidate = tokens[j].Trim()
                if candidate <> "" and HasAlphaNumeric(candidate) and not IsNumericText(candidate) and not IsMetadataLabel(candidate)
                    return candidate
                end if
            end for
        end if
    end for
    return addonName
end function

function IsMetadataLabel(value as string) as boolean
    lower = LCase(value)
    return lower = "seeds" or lower = "seeders" or lower = "peers" or lower = "seeds:" or lower = "seeders:" or lower = "peers:" or lower = "tracker:" or lower = "provider:" or lower = "size:" or lower = "s:" or lower = "p:"
end function

function IsNumericText(value as string) as boolean
    if value = "" then return false
    hasDigit = false
    for i = 1 to Len(value)
        char = Mid(value, i, 1)
        if char >= "0" and char <= "9"
            hasDigit = true
        else if char <> "." and char <> ","
            return false
        end if
    end for
    return hasDigit
end function

function HasAlphaNumeric(value as string) as boolean
    for i = 1 to Len(value)
        char = Mid(value, i, 1)
        if char >= "0" and char <= "9" then return true
        if char >= "A" and char <= "Z" then return true
        if char >= "a" and char <= "z" then return true
    end for
    return false
end function

function FirstLine(value as string) as string
    if value = "" then return ""
    normalized = value.Replace(Chr(13), "")
    parts = normalized.Tokenize(Chr(10))
    if parts.Count() = 0 then return ""
    return parts[0].Trim()
end function

function ExtractSourceTag(line as string) as string
    if line = "" then return ""
    bracketEnd = Instr(1, line, "]")
    if bracketEnd > 1 and Left(line, 1) = "["
        return Left(line, bracketEnd)
    end if
    return ""
end function

function LastNonEmptyLine(value as string) as string
    result = ""
    normalized = value.Replace(Chr(13), "")
    for each line in normalized.Tokenize(Chr(10))
        if line.Trim() <> "" then result = line.Trim()
    end for
    return result
end function

function EpisodeTitle(episode as object) as string
    title = SafeString(episode, "name")
    if title = "" then title = SafeString(episode, "title")
    return title
end function

function EpisodeDescription(episode as object) as string
    description = SafeString(episode, "overview")
    if description = "" then description = SafeString(episode, "description")
    return description
end function

function SeriesMetaLine(meta as object) as string
    parts = []
    runtime = SafeString(meta, "runtime")
    releaseInfo = SafeString(meta, "releaseInfo")
    rating = SafeString(meta, "imdbRating")
    if runtime <> "" then parts.Push(runtime)
    if releaseInfo <> "" then parts.Push(releaseInfo)
    if rating <> "" then parts.Push("IMDb " + rating)
    if meta <> invalid and meta.DoesExist("genres") and meta.genres <> invalid
        for each genre in meta.genres
            if parts.Count() >= 6 then exit for
            parts.Push(genre)
        end for
    end if
    return JoinStrings(parts, "  |  ")
end function

function EpisodeNumber(episode as object) as integer
    if episode <> invalid and episode.DoesExist("episode") then return episode.episode
    if episode <> invalid and episode.DoesExist("number") then return episode.number
    return 0
end function

function HomeHeroDescription(item as object) as string
    description = SafeString(item, "description")
    if SafeString(item, "type") = "movie"
        hint = "Streams load automatically"
        if description <> "" then return description + "    " + hint
        return hint
    end if
    return description
end function

function DiscoverTypeLabel(value as string) as string
    if value = "movie" then return TrText("discover.type.movie")
    if value = "series" then return TrText("discover.type.series")
    if value = "channel" then return TrText("discover.type.channel")
    return value
end function

function SubtitleLanguageName(code as string) as string
    names = {
        eng: "English"
        spa: "Spanish"
        fre: "French"
        fra: "French"
        ger: "German"
        deu: "German"
        ita: "Italian"
        por: "Portuguese"
        dut: "Dutch"
        nld: "Dutch"
        pol: "Polish"
        rus: "Russian"
        ukr: "Ukrainian"
        tur: "Turkish"
        ara: "Arabic"
        chi: "Chinese"
        zho: "Chinese"
        jpn: "Japanese"
        kor: "Korean"
        hin: "Hindi"
        swe: "Swedish"
        nor: "Norwegian"
        dan: "Danish"
        fin: "Finnish"
        cze: "Czech"
        ces: "Czech"
        rum: "Romanian"
        ron: "Romanian"
        hun: "Hungarian"
        gre: "Greek"
        ell: "Greek"
        heb: "Hebrew"
    }
    normalized = LCase(code)
    if names.DoesExist(normalized) then return names[normalized]
    if code = "" then return TrText("common.unknown")
    return UCase(code)
end function

function DetectStreamFormat(url as string) as string
    cleanUrl = LCase(url)
    queryIndex = Instr(1, cleanUrl, "?")
    if queryIndex > 0 then cleanUrl = Left(cleanUrl, queryIndex - 1)
    if Right(cleanUrl, 5) = ".m3u8" then return "hls"
    if Right(cleanUrl, 4) = ".mpd" then return "dash"
    if Right(cleanUrl, 4) = ".mkv" then return "mkv"
    if Right(cleanUrl, 4) = ".mp4" or Right(cleanUrl, 4) = ".m4v" then return "mp4"
    return ""
end function

function FormatPlaybackTime(seconds as dynamic) as string
    total = Int(seconds)
    if total < 0 then total = 0
    hours = Int(total / 3600)
    minutes = Int((total mod 3600) / 60)
    remainingSeconds = total mod 60

    minuteText = minutes.ToStr()
    secondText = remainingSeconds.ToStr()
    if Len(secondText) = 1 then secondText = "0" + secondText
    if hours > 0
        if Len(minuteText) = 1 then minuteText = "0" + minuteText
        return hours.ToStr() + ":" + minuteText + ":" + secondText
    end if
    return minuteText + ":" + secondText
end function