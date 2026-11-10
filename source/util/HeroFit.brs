' HeroFit — one package for the hero box shared by the Home and Details
' heroes: narrow logos (under 1.7:1) take the tall portrait envelope,
' everything wider the short wide band. Returns { width, height, tall } —
' each screen keeps its own label choreography, because only it knows what
' sits under (or beside) its logo.

function HeroFit(bitmapWidth as integer, bitmapHeight as integer) as object
    if bitmapWidth <= 0 or bitmapHeight <= 0 then return invalid
    ratio = bitmapWidth / bitmapHeight
    if ratio < 1.7
        maxWidth = 420
        maxHeight = 460
    else
        maxWidth = 820
        maxHeight = 190
    end if
    logoWidth = ratio * maxHeight
    if logoWidth > maxWidth then logoWidth = maxWidth
    logoHeight = logoWidth / ratio
    return { width: Int(logoWidth), height: Int(logoHeight), tall: ratio < 1.7 }
end function
