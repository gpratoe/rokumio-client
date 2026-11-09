' Toast unit tests — the behaviour of the pure helpers in ToastMetrics.brs,
' not their exact measurements: how tall/long one runs, not how many pixels.

sub Test_Toast_Duration()
    Harness_Suite("Toast duration")
    Harness_Ok(ToastDuration("error") > ToastDuration("info"), "errors hold longer than information")
    Harness_Equal(ToastDuration("anything"), ToastDuration("info"), "an unknown kind runs like information, not longer")
end sub

sub Test_Toast_PlateWidth()
    Harness_Suite("Toast plate width")
    long = ""
    for i = 1 to 200
        long = long + "x"
    end for
    Harness_Ok(ToastPlateWidth("a longer notification message") > ToastPlateWidth("hi"), "wider text, wider plate")
    Harness_Ok(ToastPlateWidth(long) <= 1400, "a long message is capped")
    Harness_Ok(ToastPlateWidth("hi") >= ToastPlateWidth(""), "a short message gets at least the minimum plate")
end sub

sub Test_Toast_PlateHeight()
    Harness_Suite("Toast plate height")
    long = ""
    for i = 1 to 200
        long = long + "x"
    end for
    medium = ""
    for i = 1 to 100
        medium = medium + "x"
    end for
    Harness_Ok(ToastPlateHeight(long, 260) > ToastPlateHeight("hi", 260), "wrapped text grows taller")
    Harness_Ok(ToastPlateHeight(medium, 1400) < ToastPlateHeight(medium, 260), "a wider plate wraps less")
end sub
