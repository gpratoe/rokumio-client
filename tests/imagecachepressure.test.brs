' Image cache pressure/budget helper tests.

sub Test_ImageCachePressure_BudgetTierConfigs()
    Harness_Suite("ImageCache budget tier configs")

    n = ImageCacheBudgetForTier("normal")
    Harness_Equal(n.tier, "normal", "normal tier name")
    Harness_Equal(n.maxBytes, 40 * 1024 * 1024, "normal maxBytes")
    Harness_Equal(n.maxFiles, 250, "normal maxFiles")
    Harness_Equal(n.maxQueueHi, 60, "normal hi queue cap")
    Harness_Equal(n.maxQueueLow, 120, "normal low queue cap")

    l = ImageCacheBudgetForTier("low")
    Harness_Equal(l.tier, "low", "low tier name")
    Harness_Equal(l.maxBytes, 20 * 1024 * 1024, "low maxBytes")
    Harness_Equal(l.maxFiles, 125, "low maxFiles")
    Harness_Equal(l.maxQueueHi, 40, "low hi queue cap")
    Harness_Equal(l.maxQueueLow, 40, "low low queue cap")

    c = ImageCacheBudgetForTier("critical")
    Harness_Equal(c.tier, "critical", "critical tier name")
    Harness_Equal(c.maxBytes, 8 * 1024 * 1024, "critical maxBytes")
    Harness_Equal(c.maxFiles, 60, "critical maxFiles")
    Harness_Equal(c.maxQueueHi, 20, "critical hi queue cap")
    Harness_Equal(c.maxQueueLow, 0, "critical low queue cap")

    u = ImageCacheBudgetForTier("unknown")
    Harness_Equal(u.tier, "normal", "unknown maps to normal")
end sub

sub Test_ImageCachePressure_TierRankAndMapping()
    Harness_Suite("ImageCache memory level/tier mapping")

    Harness_Equal(ImageCacheTierRank("critical"), 0, "critical rank")
    Harness_Equal(ImageCacheTierRank("low"), 1, "low rank")
    Harness_Equal(ImageCacheTierRank("normal"), 2, "normal rank")
    Harness_Equal(ImageCacheTierRank("anything"), 2, "unknown rank defaults to normal")

    Harness_Equal(ImageCacheTierForMemoryLevel("critical"), "critical", "critical level")
    Harness_Equal(ImageCacheTierForMemoryLevel("low"), "low", "low level")
    Harness_Equal(ImageCacheTierForMemoryLevel("normal"), "normal", "normal level")
    Harness_Equal(ImageCacheTierForMemoryLevel(invalid), "normal", "invalid level defaults normal")
    Harness_Equal(ImageCacheTierForMemoryLevel("weird"), "normal", "unknown level defaults normal")
end sub

sub Test_ImageCachePressure_PruneQueuesToCaps()
    Harness_Suite("ImageCache queue pruning to caps")

    state = {
        queueHi: ["h1", "h2", "h3", "h4"]
        queue: ["l1", "l2", "l3"]
        queued: { h1: true, h2: true, h3: true, h4: true, l1: true, l2: true, l3: true }
        maxQueueHi: 2
        maxQueueLow: 1
    }

    ImageCachePruneQueuesToCaps(state)

    Harness_Equal(state.queueHi.Count(), 2, "hi queue trimmed to cap")
    Harness_Equal(state.queueHi[0], "h3", "hi queue keeps newest/tail entries")
    Harness_Equal(state.queueHi[1], "h4", "hi queue tail preserved")
    Harness_Equal(state.queue.Count(), 1, "low queue trimmed to cap")
    Harness_Equal(state.queue[0], "l3", "low queue keeps tail entry")

    Harness_Ok(state.queued.DoesExist("h1") = false, "dropped hi h1 removed from queued")
    Harness_Ok(state.queued.DoesExist("h2") = false, "dropped hi h2 removed from queued")
    Harness_Ok(state.queued.DoesExist("l1") = false, "dropped low l1 removed from queued")
    Harness_Ok(state.queued.DoesExist("l2") = false, "dropped low l2 removed from queued")
    Harness_Ok(state.queued.h3 = true, "kept hi h3 still queued")
    Harness_Ok(state.queued.h4 = true, "kept hi h4 still queued")
    Harness_Ok(state.queued.l3 = true, "kept low l3 still queued")
end sub

sub Test_ImageCachePressure_ApplyBudgetTierShrinksAndEvicts()
    Harness_Suite("ImageCache apply budget tier shrinks queues and evicts cache")

    state = {
        queueHi: ["h1", "h2", "h3"]
        queue: ["l1", "l2", "l3", "l4"]
        queued: { h1: true, h2: true, h3: true, l1: true, l2: true, l3: true, l4: true }
        inflight: {}
        failed: {}
        retryCount: {}
        hiWanted: {}
        entries: {
            "u1": { path: "tmp:/imgcache/nope1", bytes: 5 * 1024 * 1024, tick: 1 }
            "u2": { path: "tmp:/imgcache/nope2", bytes: 4 * 1024 * 1024, tick: 2 }
            "u3": { path: "tmp:/imgcache/nope3", bytes: 3 * 1024 * 1024, tick: 3 }
        }
        totalBytes: 12 * 1024 * 1024
        tick: 3
        maxBytes: 40 * 1024 * 1024
        maxFiles: 250
        maxQueueHi: 60
        maxQueueLow: 120
        maxFileBytes: 5 * 1024 * 1024
        pressureTier: "normal"
        top: invalid
    }

    ' Critical tier: 8MB/60 files, hi cap 20, low cap 0 -> should evict oldest until <=8MB and drop low queue
    ' total 12MB (5+4+3), limit 8MB: evict u1 (5MB, tick 1) => 7MB, enough.
    ImageCacheApplyBudgetTier(state, "critical", "test")

    Harness_Equal(state.pressureTier, "critical", "tier set to critical")
    Harness_Equal(state.maxBytes, 8 * 1024 * 1024, "critical maxBytes applied")
    Harness_Equal(state.maxFiles, 60, "critical maxFiles applied")
    Harness_Equal(state.maxQueueHi, 20, "critical hi queue cap applied")
    Harness_Equal(state.maxQueueLow, 0, "critical low queue cap applied")

    Harness_Equal(state.queue.Count(), 0, "low queue cleared in critical")
    Harness_Ok(state.queued.DoesExist("l1") = false and state.queued.DoesExist("l2") = false and state.queued.DoesExist("l3") = false and state.queued.DoesExist("l4") = false, "dropped low-pri urls removed from queued")
    Harness_Equal(state.queueHi.Count(), 3, "hi queue kept within critical cap")

    Harness_Ok(state.entries.DoesExist("u1") = false, "oldest entry u1 evicted to satisfy byte cap")
    Harness_Ok(state.entries.DoesExist("u2") = true, "u2 retained once under cap")
    Harness_Ok(state.entries.DoesExist("u3") = true, "newest entry u3 retained")
    Harness_Equal(state.totalBytes, 7 * 1024 * 1024, "totalBytes reduced to retained entries")
    Harness_Equal(state.entries.Count(), 2, "entry count reduced")
end sub

sub Test_ImageCachePressure_ApplyBudgetTierNoopWhenUnchanged()
    Harness_Suite("ImageCache apply budget tier unchanged is safe")

    state = {
        queueHi: ["h1"]
        queue: ["l1"]
        queued: { h1: true, l1: true }
        inflight: {}
        failed: {}
        retryCount: {}
        hiWanted: {}
        entries: {}
        totalBytes: 0
        tick: 0
        maxBytes: 40 * 1024 * 1024
        maxFiles: 250
        maxQueueHi: 60
        maxQueueLow: 120
        maxFileBytes: 5 * 1024 * 1024
        pressureTier: "normal"
        top: invalid
    }

    ImageCacheApplyBudgetTier(state, "normal", "noop")

    Harness_Equal(state.pressureTier, "normal", "tier remains normal")
    Harness_Equal(state.queueHi.Count(), 1, "hi queue unchanged")
    Harness_Equal(state.queue.Count(), 1, "low queue unchanged")
    Harness_Ok(state.queued.h1 = true and state.queued.l1 = true, "queued map unchanged")
end sub
