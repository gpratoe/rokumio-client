' ImageCache — local byte cache for remote images (prefetch, no pre-decode).
'
' Remote http(s) image bytes can be downloaded ahead of time into tmp:/ and
' served back as local file URIs so Posters/PosterLoaders decode from local
' storage on a miss-free hit. Texture memory is unchanged: a Poster still
' decodes on load; this only saves the network round trip.
'
' Resolve is deterministic and read-only: the cache path is derived from a hash
' of the effective request URL, so a render-thread resolve is just a cheap path
' derivation + existence check with no shared mutable state. Downloads and
' eviction are owned by ImageCacheTask (off the UI thread).

function ImageCacheDir() as string
    return "tmp:/imgcache"
end function

' Ensure the cache directory exists. Safe to call repeatedly.
sub ImageCacheEnsureDir()
    dir = ImageCacheDir()
    fs = CreateObject("roFileSystem")
    if fs = invalid then return
    if not fs.Exists(dir) then fs.CreateDirectory(dir)
end sub

function ImageCacheIsHttpUrl(uri as dynamic) as boolean
    s = StringOf(uri)
    lower = LCase(s)
    return Left(lower, 7) = "http://" or Left(lower, 8) = "https://"
end function

' True for URIs that are eligible for byte caching/prefetch (remote http/https).
function ImageCacheIsCacheable(uri as dynamic) as boolean
    return ImageCacheIsHttpUrl(uri)
end function

' A stable hash key for a request URL. roEVPDigest is available on device and
' in most runtimes; fall back to a simple hash if it is not.
function ImageCacheHash(text as string) as string
    digest = CreateObject("roEVPDigest")
    if digest <> invalid
        digest.Setup("md5")
        ba = CreateObject("roByteArray")
        ba.FromAsciiString(text)
        digest.Update(ba)
        out = digest.Final()
        if out <> invalid
            ' Final() returns a roByteArray on some platforms and a hex roString
            ' on others (Roku device) — handle both.
            if type(out) = "roByteArray" or type(out) = "ByteArray"
                return LCase(out.ToHexString())
            else
                s = LCase(out.ToStr())
                if s <> "" then return s
            end if
        end if
    end if
    ' Fallback: djb2-style hex, good enough for a cache key.
    h = 5381&
    for i = 1 to Len(text)
        c = Asc(Mid(text, i, 1))
        h = ((h * 33&) + c) and &h7fffffff&
    end for
    return h.ToStr()
end function

' Deterministic cache file path for an effective request URL.
function ImageCachePathForRequestUrl(requestUrl as string) as string
    if requestUrl = "" then return ""
    return ImageCacheDir() + "/" + ImageCacheHash(requestUrl)
end function

' The effective network request URL for an image (honors dev proxy rewrites).
function ImageCacheRequestUrl(uri as dynamic) as string
    s = StringOf(uri)
    if s = "" then return ""
    if not ImageCacheIsCacheable(s) then return s
    return ProxyImageUri(s)
end function

' Resolve a display image URI to a local cached file when available, otherwise
' to the (possibly proxied) remote request URL. Non-http URIs (pkg:/, tmp:/,
' already-local, empty) pass through unchanged. This is the single choke point
' for image display: callers feed the original URI and get back what the
' Poster/loader should load.
'
' Cache membership comes from the ImageCacheTask's published index (set from the
' task thread) so this stays render-thread safe — no roFileSystem access here.
function ResolveImageUri(uri as dynamic) as string
    s = StringOf(uri)
    if s = "" then return ""

    if not ImageCacheIsCacheable(s) then return s

    requestUrl = ProxyImageUri(s)

    g = GetGlobalAA()
    cached = invalid
    if g <> invalid and g.global <> invalid and g.global.imageCacheTask <> invalid
        cached = g.global.imageCacheTask.cached
    end if
    if cached <> invalid and requestUrl <> "" and cached.DoesExist(requestUrl)
        print "[imgcache] hit " + requestUrl
        return ImageCachePathForRequestUrl(requestUrl)
    end if
    return requestUrl
end function

' True when two resolved display URIs refer to the same underlying image. A
' cache miss resolves to the remote/proxied URL and a hit to the tmp:/ path; a
' later re-resolve can flip between them for the same original image. Treating
' that flip as equivalent avoids reloading an already-displayed poster.
function ImageCacheSameResolvedUri(originalUri as dynamic, uriA as dynamic, uriB as dynamic) as boolean
    a = StringOf(uriA)
    b = StringOf(uriB)
    if a = b then return true
    s = StringOf(originalUri)
    if s = "" or not ImageCacheIsCacheable(s) then return false
    requestUrl = ProxyImageUri(s)
    localPath = ImageCachePathForRequestUrl(requestUrl)
    if a = requestUrl and b = localPath then return true
    if a = localPath and b = requestUrl then return true
    return false
end function


' Enqueue image URIs for background byte prefetch (download-only). Best-effort
' and non-blocking: if the cache task is not available this is a no-op. Accepts
' a single URI string or an array of URIs. highPriority queues focus/hero assets
' ahead of bulk poster prefetch. replaceHi makes this batch "latest wins" for
' hi-pri hero window prefetch by replacing stale pending/queued hi-pri work.
sub ImageCachePrefetch(urls as dynamic, highPriority = false as boolean, replaceHi = false as boolean)
    if urls = invalid then return
    g = GetGlobalAA()
    if g = invalid or g.global = invalid then return
    task = g.global.imageCacheTask
    if task = invalid then return

    list = urls
    if type(urls) <> "roArray" then list = [urls]
    if list.Count() = 0 then return
    label = "low"
    if highPriority then label = "high"
    suffix = ""
    if replaceHi and highPriority then suffix = ", replace"
    print "[imgcache] prefetch requested " + list.Count().ToStr() + " (" + label + suffix + ")"

    ' Append to pending batches instead of replacing so rapid producers (e.g.
    ' per-item enrichment completions) don't overwrite each other before the
    ' task ingests them. The task consumes and clears these fields.
    ' For window prefetch (replaceHi), latest batch wins to avoid fast-scroll waste.
    if highPriority
        if replaceHi
            task.enqueueHiReplace = true
            task.enqueueHi = list
        else
            ' If a replace batch is already pending, keep replace semantics and
            ' merge into it rather than downgrading to append.
            if task.enqueueHiReplace = true
                pending = task.enqueueHi
                merged = []
                if pending <> invalid and type(pending) = "roArray"
                    for each x in pending
                        merged.Push(x)
                    end for
                end if
                for each x in list
                    merged.Push(x)
                end for
                task.enqueueHi = merged
            else
                pending = task.enqueueHi
                merged = []
                if pending <> invalid and type(pending) = "roArray"
                    for each x in pending
                        merged.Push(x)
                    end for
                end if
                for each x in list
                    merged.Push(x)
                end for
                task.enqueueHi = merged
            end if
        end if
    else
        pending = task.enqueue
        merged = []
        if pending <> invalid and type(pending) = "roArray"
            for each x in pending
                merged.Push(x)
            end for
        end if
        for each x in list
            merged.Push(x)
        end for
        task.enqueue = merged
    end if
end sub

' Convenience: enqueue hero art (background/logo) URLs from a list of metas.
' Posters are intentionally excluded (Roku handles poster caching). limit caps
' how many metas to scan (0 = all).
sub ImageCachePrefetchMetas(metas as dynamic, limit = 0 as integer, highPriority = false as boolean, replaceHi = false as boolean)
    if metas = invalid or type(metas) <> "roArray" then return
    urls = []
    count = metas.Count()
    if limit > 0 and limit < count then count = limit
    for i = 0 to count - 1
        meta = metas[i]
        if meta = invalid then continue for
        if meta.background <> invalid and meta.background <> "" then urls.Push(StringOf(meta.background))
        if meta.logo <> invalid and meta.logo <> "" then urls.Push(StringOf(meta.logo))
    end for
    if urls.Count() > 0 then ImageCachePrefetch(urls, highPriority, replaceHi)
end sub


