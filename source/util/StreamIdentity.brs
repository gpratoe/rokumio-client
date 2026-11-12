' Stable identity for remembering a selected stream without persisting the
' whole add-on response. Torrent provider ordering may move between requests,
' so provider + list index alone is not enough.
function StreamIdentity(stream as dynamic) as string
    if stream = invalid or Type(stream) <> "roAssociativeArray" then return ""

    hashValue = stream.Lookup("infoHash")
    if hashValue <> invalid and Type(hashValue) = "roString" and hashValue.Trim() <> ""
        fileIdx = -1
        idxValue = stream.Lookup("fileIdx")
        if idxValue <> invalid
            try
                fileIdx = Int(idxValue)
            catch notAnIndex
                fileIdx = -1
            end try
        end if
        return "torrent:" + LCase(hashValue.Trim()) + ":" + fileIdx.ToStr()
    end if

    urlValue = stream.Lookup("url")
    if urlValue <> invalid and Type(urlValue) = "roString" and urlValue.Trim() <> ""
        return "url:" + urlValue.Trim()
    end if
    return ""
end function
