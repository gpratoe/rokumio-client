' Screen — the base every screen extends.
'
' The screen contract (documented in this header, previously source/core/Screen.bs)
' is now a real component, declared once and implemented here with defaults:
'
'   function SetStores()                - binds the store facade to the
'                                           screen. The facade is READ here off
'                                           the global AA, never handed in: a bsc
'                                           class instance is an roAssociativeArray
'                                           whose members are function references,
'                                           and Roku copies (dropping every
'                                           function member) any associative array
'                                           that crosses a component boundary.
'                                           MainScene used to pass m.stores in as
'                                           a callFunc argument and every screen
'                                           received a data-only copy, so
'                                           m.stores.addons.GetAll() died on
'                                           device with &hf4 "Member function not
'                                           found in BrightScript Component or
'                                           interface". The global AA is not a
'                                           component, so the read is by
'                                           reference and every screen gets the
'                                           live instances the Scene owns.
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

function SetStores() as void
    ' GetGlobalAA() is a runtime function, not a component: CreateObject
    ' ("roGlobal") is a BrightSign-ism that returns invalid on Roku.
    storesAA = GetGlobalAA()
    m.stores = storesAA.rokumioStores
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