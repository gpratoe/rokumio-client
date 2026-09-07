' DummyDetail — the M1 pushed screen.
'
' Proves push physics: it receives params from the pushing screen, its own Back
' is declined (so the Scene pops it), and everything it does is local. The real
' Details screen replaces this in M3.

function OnEnter(params as object) as void
    if params = invalid then return
    m.top.FindNode("detailTitle").text = "Details — " + params.title
    meta = "row " + params.row.ToStr() + " • tile " + params.index.ToStr()
    m.top.FindNode("detailMeta").text = meta
end function

function OnExit() as void
end function

function OnBackPressed() as boolean
    return false
end function

sub BlurFocus()
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    return false
end function