' AddonMetadataTask — refresh optional tile metadata off the render thread.
' Results stream one add-on at a time so the screen can fill in tiles while a
' slow manifest is still being fetched for another add-on.

sub init()
    m.top.functionName = "load"
end sub

sub load()
    try
        httpClient = Transport()
        catalog = CatalogStore(httpClient)
        for each addon in m.top.addons
            if addon = invalid or addon.address = invalid or addon.address = "" then continue for
            answer = catalog.Manifest(addon.address)
            result = {
                done: false
                id: addon.id
                address: addon.address
                ok: answer.ok
                description: ""
                logo: ""
                version: ""
            }
            if answer.ok and answer.manifest <> invalid
                result.description = answer.manifest.description
                result.logo = ResolveLogoUrl(answer.manifest.logo, httpClient)
                result.version = answer.manifest.version
            else
                result.error = answer.error
            end if
            m.top.result = result
        end for
        m.top.result = { done: true }
    catch e
        m.top.result = { done: true, error: e.message }
    end try
end sub

' Roku cannot render SVG logos. When a manifest ships one, probe a few likely
' PNG siblings and use the first that is actually served as an image. If none
' of them exists, return "" so the tile falls back to the generic add-on icon.
function ResolveLogoUrl(rawLogo as dynamic, httpClient as object) as string
    url = StringOf(rawLogo).Trim()
    if url = "" then return ""

    path = url
    query = ""
    queryStart = url.InStr("?")
    if queryStart > 0
        path = url.Left(queryStart - 1)
        query = url.Mid(queryStart)
    end if
    if path.Len() < 4 or LCase(path.Right(4)) <> ".svg" then return url

    parts = path.Tokenize("/")
    directory = ""
    if parts.Count() > 1
        for i = 0 to parts.Count() - 2
            directory = directory + parts[i] + "/"
        end for
    end if

    candidates = []
    candidates.Push(path.Left(path.Len() - 4) + ".png" + query)
    candidates.Push(directory + "logo.png" + query)
    candidates.Push(directory + "icon.png" + query)

    for each candidate in candidates
        if CheckImageUrl(candidate, httpClient) then return candidate
    end for
    return ""
end function

function CheckImageUrl(url as string, httpClient as object) as boolean
    if url = "" then return false
    result = httpClient.Head(url, 5000)
    if result = invalid or result.status <> 200 then return false
    headers = result.responseHeaders
    if headers <> invalid
        contentType = LCase(StringOf(headers["content-type"]))
        if contentType <> "" and contentType.InStr("image/") < 0 then return false
    end if
    return true
end function
