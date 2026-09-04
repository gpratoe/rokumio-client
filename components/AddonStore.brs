' AddonStore.brs
'
' A single point of truth for everything add-on related in this app: the filter,
' the installed manifests, the discovery catalog, the configured manifest URLs,
' and the pure decisions/rules built on top of them (which manifest provides a
' stream or subtitles, URL privacy, add-on object construction).
'
' It is a plain associative-array "class" in Roku's documented style: each
' instance captures its own fields through m, and MainScene owns one instance
' (m.addonStore) that it asks for data and hands operations to. It deliberately
' owns no dialogs, no HTTP tasks, and no scene chrome -- those stay in MainScene,
' which calls into this store and reads data back out. It DOES own its registry
' persistence (load()/saveUrls()) because roRegistrySection access is synchronous
' and global -- no nodes, no callbacks, no scene coupling -- so it stays
' self-contained without pulling in any MainScene glue.

function CreateAddonStore() as object
    store = {
        _filter: "installed"
        _searchQuery: ""
        _installed: []
        _catalog: []
        _catalogLoaded: false
        _catalogRequestActive: false
        _manifestUrls: []
        _pendingAddonUrl: ""
    }

    ' --- state accessors -----------------------------------------------------

    ' The dict pushed into the Addons component on every render. The keys match
    ' the component's m.state reads exactly.
    store.getState = function() as object
        return {
            addonFilter: m._filter
            addonSearchQuery: m._searchQuery
            addons: m._installed
            catalog: m._catalog
            catalogLoaded: m._catalogLoaded
            catalogRequestActive: m._catalogRequestActive
        }
    end function

    store.getFilter = function() as string
        return m._filter
    end function

    store.getSearchQuery = function() as string
        return m._searchQuery
    end function

    store.getInstalled = function() as object
        return m._installed
    end function

    store.getCatalog = function() as object
        return m._catalog
    end function

    store.catalogLoaded = function() as boolean
        return m._catalogLoaded
    end function

    store.catalogRequestActive = function() as boolean
        return m._catalogRequestActive
    end function

    store.getManifestUrls = function() as object
        return m._manifestUrls
    end function

    store.manifestUrlCount = function() as integer
        return m._manifestUrls.Count()
    end function

    ' --- state mutators ------------------------------------------------------

    store.setFilter = function(f as string)
        m._filter = f
    end function

    store.setSearchQuery = function(q as string)
        m._searchQuery = q
    end function

    store.clearSearchQuery = function()
        m._searchQuery = ""
    end function

    store.setInstalled = function(arr as object)
        m._installed = arr
    end function

    store.setCatalog = function(arr as object)
        m._catalog = arr
    end function

    store.setCatalogLoaded = function(loaded as boolean)
        m._catalogLoaded = loaded
    end function

    store.setCatalogRequestActive = function(active as boolean)
        m._catalogRequestActive = active
    end function

    store.setManifestUrls = function(urls as object)
        m._manifestUrls = urls
    end function

    ' --- persistence (synchronous registry, safe to own here) ------------------

    store.load = function()
        section = CreateObject("roRegistrySection", "Rokumio")
        urls = []
        if section.Exists("addonManifestUrls")
            storedUrls = ParseJson(section.Read("addonManifestUrls"))
            if storedUrls <> invalid then urls = storedUrls
        end if
        m._manifestUrls = urls
    end function

    store.saveUrls = function()
        section = CreateObject("roRegistrySection", "Rokumio")
        section.Write("addonManifestUrls", FormatJson(m._manifestUrls))
        section.Flush()
    end function

    ' --- discovery catalog (the public Stremio collection) ----------------------

    ' Return the request to fire for the add-on collection. The store sets its
    ' in-flight flag here; MainScene owns the HTTP task itself, so the caller
    ' starts the returned request and later hands the response back via
    ' handleCatalogResponse.
    store.requestCatalog = function() as object
        m._catalogRequestActive = true
        return {
            url: "https://api.strem.io/addonscollection.json"
            id: "addonCatalog|all"
        }
    end function

    ' Process a loaded collection: clear the in-flight flag, mark the catalog
    ' loaded, and rebuild the discovery list (capped at 80 entries).
    store.handleCatalogResponse = function(data as dynamic)
        m._catalogRequestActive = false
        m._catalogLoaded = true
        catalog = []
        if data <> invalid
            for each item in data
                if item <> invalid and item.DoesExist("manifest") and item.manifest <> invalid
                    url = SafeString(item, "transportUrl")
                    catalog.Push({
                        url: url
                        manifest: item.manifest
                        summaryTypes: AddonTypesLabel(item.manifest)
                    })
                end if
                if catalog.Count() >= 80 then exit for
            end for
        end if
        m._catalog = catalog
    end function

    ' --- manual configuration (verify a candidate manifest URL) -----------------

    ' Return the request to fire to verify a manifest URL, stashing the URL as
    ' the pending candidate for handleVerifyResponse.
    store.verify = function(url as string) as object
        m._pendingAddonUrl = url
        return {
            url: url
            id: "config|addon"
        }
    end function

    store.getPendingAddonUrl = function() as string
        return m._pendingAddonUrl
    end function

    store.clearPendingAddonUrl = function()
        m._pendingAddonUrl = ""
    end function

    ' Process a verified manifest. Returns an assoc-array the caller (MainScene)
    ' uses for scene glue: { valid:true, name } on success, { valid:false } when
    ' the add-on is rejected (no saved state, pending URL cleared).
    store.handleVerifyResponse = function(manifest as dynamic) as object
        if not m.IsValidAddonManifest(manifest)
            m._pendingAddonUrl = ""
            return {
                valid: false
            }
        end if
        addon = m.BuildAddon(m._pendingAddonUrl, manifest)
        m.addOrReplace(addon)
        m.saveUrls()
        m._pendingAddonUrl = ""
        return {
            valid: true
            name: SafeString(manifest, "name")
        }
    end function

    ' Whether a loaded manifest is worth keeping: it must carry an id/name and
    ' expose a usable stream or subtitles resource.
    store.IsValidAddonManifest = function(manifest as dynamic) as boolean
        if manifest = invalid or Type(manifest) <> "roAssociativeArray" then return false
        if SafeString(manifest, "id") = "" or SafeString(manifest, "name") = "" then return false
        if not manifest.DoesExist("resources") or manifest.resources = invalid then return false

        for each resource in manifest.resources
            if Type(resource) = "roString" or Type(resource) = "String"
                if resource = "stream" or resource = "subtitles" then return true
            else if Type(resource) = "roAssociativeArray"
                resourceName = SafeString(resource, "name")
                if resourceName = "stream" or resourceName = "subtitles" then return true
            end if
        end for
        return false
    end function

    ' --- startup / reload manifest loading -------------------------------------

    ' Clear the installed list and return the configured manifest URLs to
    ' re-fetch. The caller fires the load requests and tracks the pending count;
    ' each response is handed back via handleManifestLoadResponse.
    store.reload = function() as object
        m.clearInstalled()
        return m._manifestUrls
    end function

    ' Process one loaded manifest from a startup/reload fetch. Loads are fan-out
    ' fan-in: the pending count lives in MainScene (it also gates a deferred
    ' stream lookup), so this only touches add-on state.
    store.handleManifestLoadResponse = function(data as dynamic, urlIndex as integer)
        manifestUrls = m._manifestUrls
        if urlIndex >= 0 and urlIndex < manifestUrls.Count() and m.IsValidAddonManifest(data)
            m.addOrReplace(m.BuildAddon(manifestUrls[urlIndex], data))
        end if
    end function

    ' --- installed-manifest maintenance ---------------------------------------

    ' Add an add-on keyed by manifest id, replacing an existing one with the
    ' same id and rewriting its stored URL. Returns true when it was a brand-new
    ' add-on (caller may want to persist), false when it replaced an existing one.
    store.addOrReplace = function(addon as object) as boolean
        addonId = SafeString(addon.manifest, "id")
        for index = 0 to m._installed.Count() - 1
            if SafeString(m._installed[index].manifest, "id") = addonId
                oldUrl = m._installed[index].url
                m._installed[index] = addon
                m.replaceStoredUrl(oldUrl, addon.url)
                return false
            end if
        end for
        m._installed.Push(addon)
        if not ArrayContains(m._manifestUrls, addon.url)
            m._manifestUrls.Push(addon.url)
        end if
        return true
    end function

    store.removeByIndex = function(index as integer) as string
        if index < 0 or index >= m._installed.Count() then return ""
        addon = m._installed[index]
        addonUrl = addon.url
        m._installed.Delete(index)
        for urlIndex = m._manifestUrls.Count() - 1 to 0 step -1
            if m._manifestUrls[urlIndex] = addonUrl
                m._manifestUrls.Delete(urlIndex)
            end if
        end for
        return addonUrl
    end function

    store.clearInstalled = function()
        m._installed = []
    end function

    store.replaceStoredUrl = function(oldUrl as string, newUrl as string)
        replaced = false
        for index = 0 to m._manifestUrls.Count() - 1
            if m._manifestUrls[index] = oldUrl
                m._manifestUrls[index] = newUrl
                replaced = true
                exit for
            end if
        end for
        if not replaced and not ArrayContains(m._manifestUrls, newUrl) then m._manifestUrls.Push(newUrl)
    end function

    ' --- pure add-on rules ----------------------------------------------------

    store.AddonSupports = function(manifest as object, resourceName as string, contentType as string, id as string) as boolean
        if not manifest.DoesExist("resources") or manifest.resources = invalid then return false
        for each resource in manifest.resources
            if Type(resource) = "roString" or Type(resource) = "String"
                if resource = resourceName
                    return m.MatchesAddonFilters(manifest, contentType, id)
                end if
            else if Type(resource) = "roAssociativeArray"
                if SafeString(resource, "name") = resourceName
                    return m.MatchesAddonFilters(manifest, contentType, id) and m.MatchesAddonFilters(resource, contentType, id)
                end if
            end if
        end for
        return false
    end function

    store.AddonSupportsResource = function(manifest as object, resourceName as string) as boolean
        if manifest = invalid or not manifest.DoesExist("resources") or manifest.resources = invalid then return false
        for each resource in manifest.resources
            if Type(resource) = "roString" or Type(resource) = "String"
                if resource = resourceName then return true
            else if Type(resource) = "roAssociativeArray"
                if SafeString(resource, "name") = resourceName then return true
            end if
        end for
        return false
    end function

    store.MatchesAddonFilters = function(filters as object, contentType as string, id as string) as boolean
        if filters.DoesExist("types") and filters.types <> invalid
            if not m.FilterContains(filters.types, contentType) then return false
        end if

        if filters.DoesExist("idPrefixes") and filters.idPrefixes <> invalid and m.FilterCount(filters.idPrefixes) > 0
            prefixMatched = false
            for each prefix in filters.idPrefixes
                prefixText = prefix.ToStr()
                if LCase(Left(id, Len(prefixText))) = LCase(prefixText)
                    prefixMatched = true
                    exit for
                end if
            end for
            if not prefixMatched then return false
        end if
        return true
    end function

    store.FilterContains = function(values as dynamic, expected as string) as boolean
        if Type(values) = "roString" or Type(values) = "String"
            return LCase(values) = LCase(expected)
        end if
        for each value in values
            if LCase(value.ToStr()) = LCase(expected) then return true
        end for
        return false
    end function

    store.FilterCount = function(values as dynamic) as integer
        if Type(values) = "roString" or Type(values) = "String" then return 1
        return values.Count()
    end function

    store.BuildAddon = function(url as string, manifest as object) as object
        return {
            url: url
            baseUrl: m.AddonBaseUrl(url)
            manifest: manifest
        }
    end function

    store.AddonBaseUrl = function(url as string) as string
        suffix = "/manifest.json"
        return Left(url, Len(url) - Len(suffix))
    end function

    ' A configured add-on URL can embed a debrid key, usually as a long opaque
    ' path segment or a credential-looking query parameter. Heuristic on purpose:
    ' the cost of a false positive is a hidden URL, the cost of a false negative
    ' is a leaked account, so this errs toward hiding.
    store.AddonUrlLooksPrivate = function(url as string) as boolean
        if url = "" then return false
        lowered = LCase(url)
        for each marker in ["token", "apikey", "api_key", "password", "secret", "rdkey", "premiumize", "realdebrid", "alldebrid"]
            if Instr(1, lowered, marker) > 0 then return true
        end for

        ' Long opaque path segment: strip the scheme, then look for a run of 20+
        ' characters that is all letters and digits.
        rest = url
        position = Instr(1, rest, "://")
        if position > 0 then rest = Mid(rest, position + 3)
        runLength = 0
        for charIndex = 1 to Len(rest)
            character = Mid(rest, charIndex, 1)
            isAlphaNumeric = (character >= "a" and character <= "z") or (character >= "A" and character <= "Z") or (character >= "0" and character <= "9")
            if isAlphaNumeric
                runLength = runLength + 1
                if runLength >= 20 then return true
            else
                runLength = 0
            end if
        end for
        return false
    end function

    return store
end function

function ArrayContains(values as object, expected as dynamic) as boolean
    if values = invalid then return false
    for each value in values
        if value = expected then return true
    end for
    return false
end function
