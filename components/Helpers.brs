' Shared string helpers used across components. These are pure functions with no
' scene state, so any component (or MainScene) can include this file and call
' them. Kept here so a self-contained screen component does not have to reach
' into MainScene for string plumbing.

function SafeString(value as object, key as string) as string
    if value <> invalid and value.DoesExist(key) and value[key] <> invalid
        return value[key].ToStr()
    end if
    return ""
end function

function JoinStrings(values as object, separator as string) as string
    result = ""
    for each value in values
        if result <> "" then result = result + separator
        result = result + value.ToStr()
    end for
    return result
end function

function ReplaceNewlines(value as string) as string
    result = value.Replace(Chr(13), " ")
    return result.Replace(Chr(10), " ")
end function

' Shared label builders for add-on manifests. These are shared by MainScene's
' add-on detail dialogs and the Addons screen's card building, so they stay here
' rather than in either component.

function AddonTypesLabel(manifest as object) as string
    if manifest = invalid or not manifest.DoesExist("types") or manifest.types = invalid then return "Addon"
    labels = []
    for each value in manifest.types
        labels.Push(value.ToStr())
    end for
    if labels.Count() = 0 then return "Addon"
    return JoinStrings(labels, " & ")
end function

function AddonResourcesLabel(manifest as object) as string
    if manifest = invalid or not manifest.DoesExist("resources") or manifest.resources = invalid then return "Addon"
    labels = []
    for each resource in manifest.resources
        if Type(resource) = "roAssociativeArray"
            labels.Push(SafeString(resource, "name"))
        else
            labels.Push(resource.ToStr())
        end if
    end for
    if labels.Count() = 0 then return "Addon"
    return JoinStrings(labels, ", ")
end function

' Only the host is ever put on screen: a configured manifest URL can carry a
' private debrid token, and the full value stays in the registry.
function AddonSourceLabel(url as string) as string
    if url = "" then return ""
    rest = url
    position = Instr(1, rest, "://")
    if position > 0 then rest = Mid(rest, position + 3)
    slash = Instr(1, rest, "/")
    if slash > 0 then rest = Left(rest, slash - 1)
    return rest
end function
