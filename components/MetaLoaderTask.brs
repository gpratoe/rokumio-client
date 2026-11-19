' MetaLoaderTask — fetch one add-on meta ({ ok, meta, error }) off the UI thread.
' Both Home (continue-watching tiles stack a full item meta before opening
' Details) and Episodes (its season list build) need the same fetch; running it
' in a Task means a hung add-on costs the worker thread, not a frozen channel.
' The store is built fresh in the task scope — no object created on the render
' thread is shared across the thread boundary.
'
' When candidateAddresses is provided, each address is tried in order until one
' returns usable meta (series meta must include videos, enforced by the store).
' This enables capability/prefix-aware fallback (e.g. source -> Cinemeta/other
' matching meta providers) without breaking callers.

sub init()
    m.top.functionName = "load"
end sub

sub load()
    try
        http = Transport()
        store = EpisodesStore(http)
        addresses = m.top.candidateAddresses
        if addresses = invalid or Type(addresses) <> "roArray" or addresses.Count() = 0
            addresses = [m.top.addonAddress]
        end if
        m.top.result = MetaLoaderTryCandidates(addresses, m.top.metaType, m.top.metaId, store)
    catch e
        m.top.result = { ok: false, meta: invalid, error: e.message }
    end try
end sub

' Try ordered meta-provider addresses until one returns usable meta. Dedupe and
' skip empty entries; a series meta without videos is not usable (rejected by
' EpisodesStore.GetMeta), so it falls through to the next candidate.
function MetaLoaderTryCandidates(addresses as object, metaType as dynamic, metaId as dynamic, store as object) as object
    last = { ok: false, meta: invalid, error: "meta type or id missing" }
    if store = invalid then return { ok: false, meta: invalid, error: "meta store unavailable" }
    if addresses = invalid or Type(addresses) <> "roArray" or addresses.Count() = 0
        return last
    end if

    tried = {}
    for each address in addresses
        addr = ""
        if address <> invalid and (Type(address) = "String" or Type(address) = "roString")
            addr = address.Trim()
        end if
        if addr = "" or tried.DoesExist(addr) then continue for
        tried[addr] = true
        answer = store.GetMeta(addr, metaType, metaId)
        last = { ok: answer.ok, meta: answer.meta, error: answer.error }
        if last.ok then return last
    end for
    return last
end function