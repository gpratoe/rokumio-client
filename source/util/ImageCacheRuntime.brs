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
    state.retryCount = {}
    state.hiWanted = {}
    state.entries = {}
    state.totalBytes = 0
    state.tick = 0
    state.maxFileBytes = 5 * 1024 * 1024

    ' Static ceiling for now (capability-based ceiling is a later step).
    state.ceilingBytes = 40 * 1024 * 1024
    state.ceilingFiles = 250
    state.maxBytes = state.ceilingBytes
    state.maxFiles = state.ceilingFiles
    state.maxQueueHi = 60
    state.maxQueueLow = 120

    ' Memory pressure / budget tier state
    state.pressureTier = "normal"
    state.memoryLevel = "normal"
    state.normalStableSinceMs = -1
    state.lastMemoryCheckMs = -1
    state.memoryCheckIntervalMs = 10000
    state.pressureRecoveryMs = 30000
    state.deviceInfo = invalid
    state.memoryEventsEnabled = false

    if state.top <> invalid then state.top.cached = {}
    if state.top <> invalid then state.top.enqueueHiReplace = false
    ImageCacheApplyBudgetTier(state, "normal", "init")
end sub

function ImageCacheBudgetForTier(tier as string) as object
    t = LCase(StringOf(tier))
    if t = "critical"
        return { tier: "critical", maxBytes: 8 * 1024 * 1024, maxFiles: 60, maxQueueHi: 20, maxQueueLow: 0 }
    else if t = "low"
        return { tier: "low", maxBytes: 20 * 1024 * 1024, maxFiles: 125, maxQueueHi: 40, maxQueueLow: 40 }
    end if
    return { tier: "normal", maxBytes: 40 * 1024 * 1024, maxFiles: 250, maxQueueHi: 60, maxQueueLow: 120 }
end function

sub ImageCachePruneQueuesToCaps(state as object)
    if state.queueHi = invalid then state.queueHi = []
    if state.queue = invalid then state.queue = []
    if state.queued = invalid then state.queued = {}
    maxHi = state.maxQueueHi
    maxLow = state.maxQueueLow
    if maxHi = invalid or maxHi < 0 then maxHi = 0
    if maxLow = invalid or maxLow < 0 then maxLow = 0
    while state.queueHi.Count() > maxHi
        dropped = state.queueHi.Shift()
        if dropped <> invalid then state.queued.Delete(dropped)
    end while
    while state.queue.Count() > maxLow
        dropped = state.queue.Shift()
        if dropped <> invalid then state.queued.Delete(dropped)
    end while
end sub

sub ImageCacheApplyBudgetTier(state as object, tier as string, reason = "" as string)
    budget = ImageCacheBudgetForTier(tier)
    prevTier = StringOf(state.pressureTier)
    prevBytes = state.maxBytes
    prevFiles = state.maxFiles
    prevQHi = state.maxQueueHi
    prevQLow = state.maxQueueLow

    state.pressureTier = budget.tier
    state.maxBytes = budget.maxBytes
    state.maxFiles = budget.maxFiles
    state.maxQueueHi = budget.maxQueueHi
    state.maxQueueLow = budget.maxQueueLow

    changed = (prevTier <> budget.tier) or (prevBytes <> budget.maxBytes) or (prevFiles <> budget.maxFiles) or (prevQHi <> budget.maxQueueHi) or (prevQLow <> budget.maxQueueLow)
    if changed
        ImageCachePruneQueuesToCaps(state)
        ImageCacheTaskEvictIfNeeded(state)
        why = StringOf(reason)
        if why = "" then why = "update"
        print "[imgcache] budget tier=" + budget.tier + " reason=" + why + " maxBytes=" + Int(state.maxBytes).ToStr() + " maxFiles=" + Int(state.maxFiles).ToStr() + " qHi=" + Int(state.maxQueueHi).ToStr() + " qLow=" + Int(state.maxQueueLow).ToStr() + " cached=" + state.entries.Count().ToStr() + " total=" + Int(state.totalBytes).ToStr()
    end if
end sub

function ImageCacheNowMs() as dynamic
    dt = CreateObject("roDateTime")
    if dt = invalid then return invalid
    dt.ToLocalTime()
    ' Seconds * 1000 + milliseconds if available
    secs = dt.AsSeconds()
    ms = 0
    if secs <> invalid then ms = Int(secs) * 1000
    if dt.GetMilliseconds <> invalid
        msec = dt.GetMilliseconds()
        if msec <> invalid then ms = ms + Int(msec)
    end if
    return ms
end function

function ImageCacheTierRank(tier as string) as integer
    t = LCase(StringOf(tier))
    if t = "critical" then return 0
    if t = "low" then return 1
    return 2
end function

function ImageCacheTierForMemoryLevel(level as dynamic) as string
    l = LCase(StringOf(level))
    if l = "critical" then return "critical"
    if l = "low" then return "low"
    return "normal"
end function

function ImageCacheReadMemoryLevel(state as object) as string
    if state.deviceInfo = invalid then return "normal"
    level = invalid
    if state.deviceInfo.GetGeneralMemoryLevel <> invalid
        level = state.deviceInfo.GetGeneralMemoryLevel()
    end if
    return ImageCacheTierForMemoryLevel(level)
end function

sub ImageCacheEvaluateMemoryPressure(state as object, nowMs = invalid as dynamic, force = false as boolean, reason = "poll" as string)
    if state = invalid then return
    if nowMs = invalid then nowMs = ImageCacheNowMs()
    if (not force) and state.lastMemoryCheckMs <> invalid and state.lastMemoryCheckMs >= 0 and nowMs <> invalid
        if (nowMs - state.lastMemoryCheckMs) < state.memoryCheckIntervalMs then return
    end if
    if nowMs <> invalid then state.lastMemoryCheckMs = nowMs

    levelTier = ImageCacheReadMemoryLevel(state)
    state.memoryLevel = levelTier
    current = StringOf(state.pressureTier)
    if current = "" then current = "normal"

    if ImageCacheTierRank(levelTier) < ImageCacheTierRank(current)
        ' Pressure increased: shrink immediately.
        state.normalStableSinceMs = -1
        if levelTier <> current
            ImageCacheApplyBudgetTier(state, levelTier, "pressure:" + reason + ":" + levelTier)
        end if
        return
    end if

    if levelTier = "normal"
        if current = "normal"
            state.normalStableSinceMs = -1
            return
        end if
        if state.normalStableSinceMs = invalid or state.normalStableSinceMs < 0
            if nowMs <> invalid
                state.normalStableSinceMs = nowMs
            else
                state.normalStableSinceMs = 0
            end if
            return
        end if
        elapsed = 0
        if nowMs <> invalid and state.normalStableSinceMs <> invalid and state.normalStableSinceMs >= 0
            elapsed = nowMs - state.normalStableSinceMs
        end if
        if elapsed >= state.pressureRecoveryMs
            ' Recover gradually: critical->low->normal (one step per stable window).
            nextTier = "normal"
            if current = "critical"
                nextTier = "low"
            else if current = "low"
                nextTier = "normal"
            end if
            state.normalStableSinceMs = -1
            if nextTier <> current
                ImageCacheApplyBudgetTier(state, nextTier, "recover:" + reason)
                ' If we stepped to low, allow another cooldown before normal.
                if nextTier <> "normal" and nowMs <> invalid then state.normalStableSinceMs = nowMs
            end if
        end if
        return
    end if

    ' level is low/critical but not lower than current (e.g. low while already critical,
    ' or low while low). Keep current tighter-or-equal tier and reset recovery timer.
    state.normalStableSinceMs = -1
end sub

sub ImageCacheInitMemoryMonitoring(state as object, port as object)
    if state = invalid then return
    dev = invalid
    try
        dev = CreateObject("roDeviceInfo")
    catch e
        dev = invalid
    end try
    state.deviceInfo = dev
    state.memoryEventsEnabled = false
    if dev = invalid then return

    if port <> invalid and dev.SetMessagePort <> invalid
        dev.SetMessagePort(port)
    end if
    if dev.EnableLowGeneralMemoryEvent <> invalid
        dev.EnableLowGeneralMemoryEvent(true)
        state.memoryEventsEnabled = true
    end if
    if dev.EnableMemoryWarningEvent <> invalid
        dev.EnableMemoryWarningEvent(true)
        state.memoryEventsEnabled = true
    end if

    level = ImageCacheReadMemoryLevel(state)
    state.memoryLevel = level
    state.lastMemoryCheckMs = ImageCacheNowMs()
    if ImageCacheTierRank(level) < ImageCacheTierRank(StringOf(state.pressureTier))
        state.normalStableSinceMs = -1
        ImageCacheApplyBudgetTier(state, level, "init-level:" + level)
    else
        state.normalStableSinceMs = -1
        print "[imgcache] memory level=" + level + " tier=" + StringOf(state.pressureTier) + " maxBytes=" + Int(state.maxBytes).ToStr()
    end if
end sub

sub ImageCacheHandleDeviceInfoEvent(state as object, msg as dynamic)
    if state = invalid or msg = invalid then return
    ' Any low-memory/general-memory/warning event is treated as pressure signal:
    ' re-evaluate level immediately (fast shrink if needed).
    info = invalid
    if msg.GetInfo <> invalid then info = msg.GetInfo()
    reason = "event"
    if info <> invalid and type(info) = "roAssociativeArray"
        ' Preserve useful context in logs when available.
        if info.DoesExist("type") then reason = "event:" + LCase(StringOf(info.type))
    end if
    state.normalStableSinceMs = -1
    ImageCacheEvaluateMemoryPressure(state, ImageCacheNowMs(), true, reason)
end sub

sub ImageCacheTaskPublish(state as object)
    if state.top = invalid then return
    snap = {}
    for each k in state.entries
        snap[k] = true
    end for
    state.top.cached = snap
end sub

sub ImageCacheTaskOnEnqueue(state as object, urls as dynamic, highPriority = false as boolean, replaceHi = false as boolean)
    if urls = invalid or type(urls) <> "roArray" then urls = []
    added = 0
    if highPriority and replaceHi
        ' "Latest wins" for hero window prefetch: drop stale queued hi-pri work so
        ' fast scrolling doesn't waste bandwidth/cache on items no longer relevant.
        if state.queueHi <> invalid
            for each oldUrl in state.queueHi
                if oldUrl <> invalid then state.queued.Delete(oldUrl)
            end for
        end if
        state.queueHi = []
    end if

    target = state.queue
    if highPriority then target = state.queueHi
    ' Under critical pressure, skip new low-priority prefetch to reduce footprint.
    if (not highPriority) and StringOf(state.pressureTier) = "critical"
        return
    end if
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
        if highPriority then state.hiWanted[requestUrl] = true
        if state.failed.DoesExist(requestUrl)
            ' Allow high-priority hero/logo requests to retry failures.
            if highPriority
                state.failed.Delete(requestUrl)
                if state.retryCount <> invalid then state.retryCount.Delete(requestUrl)
            else
                continue for
            end if
        end if
        if state.queued.DoesExist(requestUrl) then continue for
        if state.inflight.DoesExist(requestUrl) then continue for
        state.queued[requestUrl] = true
        target.Push(requestUrl)
        added = added + 1
    end for
    ' Cap queues: prefer keeping newest high-priority (focus/hero) work; shed
    ' stale bulk/old work first. For hi-pri, drop from front (oldest queued).
    maxHi = state.maxQueueHi
    maxLow = state.maxQueueLow
    if maxHi = invalid or maxHi < 0 then maxHi = 0
    if maxLow = invalid or maxLow < 0 then maxLow = 0
    while state.queueHi.Count() > maxHi
        dropped = state.queueHi.Shift()
        if dropped <> invalid then state.queued.Delete(dropped)
    end while
    while state.queue.Count() > maxLow
        dropped = state.queue.Shift()
        if dropped <> invalid then state.queued.Delete(dropped)
    end while
    if added > 0 or (highPriority and replaceHi)
        label = "low"
        if highPriority then label = "high"
        suffix = ""
        if highPriority and replaceHi then suffix = ", replace"
        print "[imgcache] enqueued " + added.ToStr() + " (" + label + suffix + ", hi=" + state.queueHi.Count().ToStr() + " low=" + state.queue.Count().ToStr() + " cached=" + state.entries.Count().ToStr() + ")"
    end if
end sub

sub ImageCacheTaskDrain(state as object, stopNode as object)
    ' Fetch at most one item per call so the task loop can ingest new enqueue
    ' batches between downloads (each download may block for several seconds).
    if state.queueHi.Count() = 0 and state.queue.Count() = 0 then return
    if stopNode <> invalid and stopNode.stop = true then return
    requestUrl = invalid
    fromHi = false
    if state.queueHi.Count() > 0
        requestUrl = state.queueHi.Shift()
        fromHi = true
    else
        requestUrl = state.queue.Shift()
    end if
    if requestUrl <> invalid then state.queued.Delete(requestUrl)
    ImageCacheTaskFetchOne(state, requestUrl, fromHi)
end sub

sub ImageCacheTaskFetchOne(state as object, requestUrl as dynamic, fromHi = false as boolean)
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
        if state.retryCount <> invalid then state.retryCount.Delete(url)
        return
    end if

    tmpPath = path + ".part"
    res = ImageCacheDownloadToFile(url, tmpPath)
    if res = invalid or res.ok <> true
        if fs <> invalid and tmpPath <> "" and fs.Exists(tmpPath) then fs.Delete(tmpPath)
        transient = (res <> invalid and res.transient = true)
        hiEligible = fromHi or (state.hiWanted <> invalid and state.hiWanted.DoesExist(url))
        retries = 0
        if state.retryCount <> invalid and state.retryCount.DoesExist(url) then retries = Int(state.retryCount[url])
        if transient and hiEligible and retries < 2
            retries = retries + 1
            if state.retryCount = invalid then state.retryCount = {}
            state.retryCount[url] = retries
            if not state.queued.DoesExist(url)
                state.queued[url] = true
                state.queueHi.Push(url)
            end if
            code = 0
            if res <> invalid and res.code <> invalid then code = Int(res.code)
            print "[imgcache] retry " + retries.ToStr() + "/2 " + url + " code=" + code.ToStr()
        else
            state.failed[url] = true
            if state.retryCount <> invalid then state.retryCount.Delete(url)
            code = 0
            if res <> invalid and res.code <> invalid then code = Int(res.code)
            reason = "failed"
            if res <> invalid and res.transient = true then reason = "failed (transient)"
            print "[imgcache] " + reason + " " + url + " code=" + code.ToStr()
        end if
        state.inflight.Delete(url)
        return
    end if

    if state.retryCount <> invalid then state.retryCount.Delete(url)

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

function ImageCacheDownloadToFile(url as string, filePath as string) as object
    result = { ok: false, transient: false, code: 0 }
    if url = "" or filePath = "" then return result
    transfer = CreateObject("roUrlTransfer")
    if transfer = invalid
        result.transient = true
        return result
    end if
    port = CreateObject("roMessagePort")
    transfer.SetMessagePort(port)
    transfer.SetPort(port)
    transfer.SetUrl(url)
    transfer.EnableEncodings(true)
    transfer.RetainBodyOnError(true)
    transfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    transfer.InitClientCertificates()
    started = transfer.AsyncGetToFile(filePath)
    if started <> true
        result.transient = true
        return result
    end if
    msg = Wait(12000, port)
    if msg = invalid
        result.transient = true
        return result
    end if
    if type(msg) <> "roUrlEvent"
        result.transient = true
        return result
    end if
    code = msg.GetResponseCode()
    if code = invalid then code = 0
    result.code = Int(code)
    if code >= 200 and code < 300
        result.ok = true
        return result
    end if
    ' Transient: connection/unknown errors (<=0), timeouts/rate-limit/server errors.
    ' Definitive client errors (e.g. 404/403/410) are not retried automatically.
    if code <= 0 or code = 408 or code = 429 or (code >= 500 and code <= 599)
        result.transient = true
    else
        result.transient = false
    end if
    return result
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
