' ImageCache runtime — task-side download/eviction helpers (source scope).
'
' Lives in source/ so it is not subject to the components/*.brs render-thread
' static checks; these functions are only invoked from ImageCacheTask (a Task
' node) and from ImageCacheEnsureDir at startup.

sub ImageCacheTaskInit(state as object)
    state.queueHi = []
    state.queue = []
    state.queued = {}
    state.inflight = {}
    state.failed = {}
    state.entries = {}
    state.totalBytes = 0
    state.tick = 0
    state.maxBytes = 40 * 1024 * 1024
    state.maxFiles = 250
    state.maxFileBytes = 5 * 1024 * 1024
    if state.top <> invalid then state.top.cached = {}
end sub

sub ImageCacheTaskPublish(state as object)
    if state.top = invalid then return
    snap = {}
    for each k in state.entries
        snap[k] = true
    end for
    state.top.cached = snap
end sub

sub ImageCacheTaskOnEnqueue(state as object, urls as dynamic, highPriority = false as boolean)
    if urls = invalid or type(urls) <> "roArray" then return
    added = 0
    target = state.queue
    if highPriority then target = state.queueHi
    for each uri in urls
        if uri = invalid then continue for
        s = StringOf(uri)
        if s = "" then continue for
        if not ImageCacheIsCacheable(s) then continue for
        requestUrl = ProxyImageUri(s)
        if requestUrl = "" then continue for
        if state.entries.DoesExist(requestUrl) then
            state.tick = state.tick + 1
            state.entries[requestUrl].tick = state.tick
            continue for
        end if
        if state.failed.DoesExist(requestUrl) then continue for
        if state.queued.DoesExist(requestUrl) then continue for
        if state.inflight.DoesExist(requestUrl) then continue for
        state.queued[requestUrl] = true
        target.Push(requestUrl)
        added = added + 1
    end for
    ' Cap queues: prefer keeping high-priority (focus/hero) work; shed stale
    ' low-priority bulk prefetch first.
    maxHi = 60
    maxLow = 120
    while state.queueHi.Count() > maxHi
        dropped = state.queueHi.Shift()
        if dropped <> invalid then state.queued.Delete(dropped)
    end while
    while state.queue.Count() > maxLow
        dropped = state.queue.Shift()
        if dropped <> invalid then state.queued.Delete(dropped)
    end while
    if added > 0
        label = "low"
        if highPriority then label = "high"
        print "[imgcache] enqueued " + added.ToStr() + " (" + label + ", hi=" + state.queueHi.Count().ToStr() + " low=" + state.queue.Count().ToStr() + " cached=" + state.entries.Count().ToStr() + ")"
    end if
end sub

sub ImageCacheTaskDrain(state as object, stopNode as object)
    drained = 0
    while drained < 4 and (state.queueHi.Count() > 0 or state.queue.Count() > 0)
        if stopNode <> invalid and stopNode.stop = true then return
        requestUrl = invalid
        if state.queueHi.Count() > 0
            requestUrl = state.queueHi.Shift()
        else
            requestUrl = state.queue.Shift()
        end if
        if requestUrl <> invalid then state.queued.Delete(requestUrl)
        ImageCacheTaskFetchOne(state, requestUrl)
        drained = drained + 1
    end while
end sub

sub ImageCacheTaskFetchOne(state as object, requestUrl as dynamic)
    if requestUrl = invalid then return
    url = StringOf(requestUrl)
    if url = "" then return
    if state.entries.DoesExist(url) then return
    if state.failed.DoesExist(url) then return

    state.inflight[url] = true
    path = ImageCachePathForRequestUrl(url)
    fs = CreateObject("roFileSystem")

    if fs <> invalid and path <> "" and fs.Exists(path)
        stat = fs.Stat(path)
        bytes = 0
        if stat <> invalid and stat.size <> invalid then bytes = stat.size
        ImageCacheTaskRegister(state, url, path, bytes)
        state.inflight.Delete(url)
        return
    end if

    tmpPath = path + ".part"
    ok = ImageCacheDownloadToFile(url, tmpPath)
    if not ok
        if fs <> invalid and tmpPath <> "" and fs.Exists(tmpPath) then fs.Delete(tmpPath)
        state.failed[url] = true
        print "[imgcache] failed " + url
        state.inflight.Delete(url)
        return
    end if

    bytes = 0
    if fs <> invalid
        stat = fs.Stat(tmpPath)
        if stat <> invalid and stat.size <> invalid then bytes = stat.size
        if bytes <= 0 or bytes > state.maxFileBytes
            fs.Delete(tmpPath)
            state.failed[url] = true
            print "[imgcache] skipped (size) " + url + " bytes=" + bytes.ToStr()
            state.inflight.Delete(url)
            return
        end if
        if path <> "" and fs.Exists(path) then fs.Delete(path)
        ' roFileSystem exposes Rename/CopyFile/Delete (not MoveFile).
        renamed = fs.Rename(tmpPath, path)
        if renamed <> true
            copied = fs.CopyFile(tmpPath, path)
            if fs.Exists(tmpPath) then fs.Delete(tmpPath)
            if copied <> true
                state.failed[url] = true
                print "[imgcache] failed (store) " + url
                state.inflight.Delete(url)
                return
            end if
        end if
    end if

    ImageCacheTaskRegister(state, url, path, bytes)
    print "[imgcache] cached " + url + " bytes=" + Int(bytes).ToStr() + " (entries=" + state.entries.Count().ToStr() + " total=" + state.totalBytes.ToStr() + ")"
    ImageCacheTaskPublish(state)
    ImageCacheTaskEvictIfNeeded(state)
    state.inflight.Delete(url)
end sub

function ImageCacheDownloadToFile(url as string, filePath as string) as boolean
    if url = "" or filePath = "" then return false
    transfer = CreateObject("roUrlTransfer")
    if transfer = invalid then return false
    port = CreateObject("roMessagePort")
    transfer.SetMessagePort(port)
    transfer.SetPort(port)
    transfer.SetUrl(url)
    transfer.EnableEncodings(true)
    transfer.RetainBodyOnError(true)
    transfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    transfer.InitClientCertificates()
    started = transfer.AsyncGetToFile(filePath)
    if started <> true then return false
    msg = Wait(12000, port)
    if msg = invalid then return false
    if type(msg) <> "roUrlEvent" then return false
    code = msg.GetResponseCode()
    return code >= 200 and code < 300
end function

sub ImageCacheTaskRegister(state as object, requestUrl as string, path as string, bytes as dynamic)
    b = 0
    if bytes <> invalid then b = Int(bytes)
    state.tick = state.tick + 1
    state.entries[requestUrl] = { path: path, bytes: b, tick: state.tick }
    state.totalBytes = state.totalBytes + b
end sub

sub ImageCacheTaskEvictIfNeeded(state as object)
    evicted = 0
    while (state.totalBytes > state.maxBytes or state.entries.Count() > state.maxFiles) and state.entries.Count() > 0
        victimKey = invalid
        victimTick = invalid
        for each k in state.entries
            t = state.entries[k].tick
            if victimTick = invalid or t < victimTick
                victimTick = t
                victimKey = k
            end if
        end for
        if victimKey = invalid then exit while
        victim = state.entries[victimKey]
        state.entries.Delete(victimKey)
        evicted = evicted + 1
        if victim <> invalid
            if victim.bytes <> invalid then state.totalBytes = state.totalBytes - victim.bytes
            fs = CreateObject("roFileSystem")
            if fs <> invalid and victim.path <> invalid and fs.Exists(victim.path)
                fs.Delete(victim.path)
            end if
        end if
    end while
    if state.totalBytes < 0 then state.totalBytes = 0
    if evicted > 0
        print "[imgcache] evicted " + evicted.ToStr() + " (entries=" + state.entries.Count().ToStr() + " total=" + state.totalBytes.ToStr() + ")"
        ImageCacheTaskPublish(state)
    end if
end sub
