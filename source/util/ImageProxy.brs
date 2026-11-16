' ImageProxy — optional dev/test URL rewrite for image requests.
'
' When enabled (global testImageProxyBase set), rewrites absolute http(s) image
' URLs to a local proxy (e.g. scripts/metahub-proxy.js) so failures/retries can
' be tested on-device: https://host/path -> <base>/__mh__/host/path.
' Disabled by default (returns original URI).

function ImageProxyBase() as string
    g = GetGlobalAA()
    if g = invalid then return ""
    globe = invalid
    if g.global <> invalid then globe = g.global
    if globe = invalid then return ""
    base = ""
    if globe.testImageProxyBase <> invalid then base = globe.testImageProxyBase
    if base = invalid then return ""
    b = base.ToStr()
    if b = "invalid" then return ""
    b = b.Trim()
    if b = "" then return ""
    if Right(b, 1) = "/" then b = Left(b, Len(b) - 1)
    return b
end function

function ProxyImageUri(uri as dynamic) as string
    s = StringOf(uri)
    base = ImageProxyBase()
    if s = "" or base = "" then return s

    lower = LCase(s)
    if Left(lower, 7) <> "http://" and Left(lower, 8) <> "https://" then return s
    schemeEnd = Instr(1, s, "://")
    if schemeEnd <= 0 then return s

    rest = Mid(s, schemeEnd + 3)
    slash = Instr(1, rest, "/")
    host = rest
    path = "/"
    if slash > 0
        host = Mid(rest, 1, slash - 1)
        path = Mid(rest, slash)
    end if
    if host = "" then return s

    return base + "/__mh__/" + host + path
end function
