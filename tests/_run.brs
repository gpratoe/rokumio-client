' Runner for the harness suites. Loaded last; executes every suite, prints the
' verdict and forces a nonzero exit when anything failed (the brs interpreter
' turns that runtime error into exit code 1).

sub Harness_RunAll()
    Test_Stack_Introspection()
    Test_Push_ShowsAndEnters()
    Test_Modal_Push_KeepsPreviousVisible()
    Test_Push_UnknownScreen()
    Test_Pop_RefusesOnSingle()
    Test_Pop_RestoresPrevious()
    Test_Back_Delegates()
    Test_Back_EmptyStack()
    Test_PopTo()
    Harness_Finish()
end sub

Harness_RunAll()

if m.failed > 0
    bad = invalid
    x = bad.poison
end if