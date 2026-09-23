' Screen — the base every screen extends.
'
' The screen contract (documented in this header, previously source/core/Screen.bs)
' is now a real component, declared once and implemented here with defaults:
'
'   function SetStores(stores as object)  - hands the store facade to the
'                                           screen. Class instances cannot cross
'                                           components through an interface
'                                           field, so the Scene delivers them via
'                                           callFunc, and this is the byte-for-byte
'                                           body every screen used to re-type.
'   function OnEnter(params as object)    - called when the screen is pushed or
'                                           restored; params is invalid when it is
'                                           only being uncovered by a pop.
'   function OnExit()                     - called when the screen is popped.
'   function OnBackPressed() as boolean   - true means the screen swallowed Back
'                                           (e.g. a backdrop or dialog inside it);
'                                           false lets the stack pop the screen —
'                                           the default, so a screen that handles
'                                           no back-press edge just pops.
'   function BlurFocus()                  - drop any inline focus the screen holds
'                                           (chips, secondary lists) so a blurred
'                                           node never eats OK/arrow keys again.
'                                           No-op by default; screens that hold
'                                           secondary focus override it.
'
' Screens that implement a lifecycle function keep their override in their own
' script (and declare it in their own interface, mirroring how every screen
' worked before this base existed); these defaults answer the calls a screen
' never overrides. This file touches nothing but m.stores and platform globals,
' so it resolves from any screen's scope with no cross-file dependencies.

function SetStores(stores as object) as void
    m.stores = stores
end function

function OnEnter(params as object) as void
end function

function OnExit() as void
end function

function OnBackPressed() as boolean
    return false
end function

function BlurFocus() as void
end function