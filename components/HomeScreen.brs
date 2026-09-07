' HomeScreen — the stack bottom.
'
' M0: placeholder. It implements the Screen contract (OnEnter / OnExit /
' OnBackPressed / BlurFocus) and owns its own onKeyEvent; M3 replaces the body
' with continue-watching + catalog rows.
sub init()
    m.homeTitle = m.top.FindNode("homeTitle")
end sub

function OnEnter(params as object) as void
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