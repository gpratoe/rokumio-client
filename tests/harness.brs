' Minimal self-contained test harness for the brs interpreter.
'
' Pure BrightScript only — no classes, no BrighterScript-only syntax — so the
' brs CLI can run it unmodified. npm test transpiles the BSL sources first, then
' hands them to brs along with this harness, the suites and tests/_run.brs.
'
'   brs <transpiled sources...> tests/harness.brs tests/<suite>.brs tests/_run.brs

' File-scope tally. tests/run.js concatenates this file, the suites and the
' runner into ONE script, so every function here shares this `m`.
m.passed = 0
m.failed = 0

function Harness_Suite(name as string) as void
    print ""
    print "SUITE: " + name
end function

function Harness_Ok(condition as boolean, what as string) as void
    if condition
        m.passed++
        print "    ok   " + what
    else
        m.failed++
        print "    FAIL " + what
    end if
end function

function Harness_Equal(actual as dynamic, expected as dynamic, what as string) as void
    if actual = expected
        m.passed++
        print "    ok   " + what
    else
        m.failed++
        print "    FAIL " + what + "  expected [" + toJson(expected) + "] got [" + toJson(actual) + "]"
    end if
end function

function Harness_Finish() as void
    print ""
    print "Assertions passed: " + m.passed.ToStr() + "  failed: " + m.failed.ToStr()
    if m.failed = 0
        print "RESULT: PASS"
    else
        print "RESULT: FAIL"
    end if
end function