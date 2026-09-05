function CreateBitReader(bytes as object) as object
    return {
        bytes: bytes
        byteIdx: 0
        bitIdx: 0
        ReadBit: function() as integer
            if m.byteIdx >= m.bytes.Count() then return 0
            bit = Int(m.bytes[m.byteIdx] / (2 ^ m.bitIdx)) mod 2
            m.bitIdx = m.bitIdx + 1
            if m.bitIdx = 8
                m.bitIdx = 0
                m.byteIdx = m.byteIdx + 1
            end if
            return bit
        end function
        ReadBits: function(n as integer) as integer
            val = 0
            for i = 0 to n - 1
                val = val + m.ReadBit() * (2 ^ i)
            end for
            return val
        end function
    }
end function

function BuildHuffmanTable(lengths as object) as object
    maxLen = 0
    for each l in lengths
        if l > maxLen then maxLen = l
    end for

    blCount = []
    for i = 0 to maxLen
        blCount.Push(0)
    end for
    for each l in lengths
        if l > 0 then blCount[l] = blCount[l] + 1
    end for

    code = 0
    nextCode = []
    for i = 0 to maxLen
        nextCode.Push(0)
    end for
    for bits = 1 to maxLen
        code = (code + blCount[bits - 1]) * 2
        nextCode[bits] = code
    end for

    table = {}
    for symbol = 0 to lengths.Count() - 1
        l = lengths[symbol]
        if l > 0
            c = nextCode[l]
            nextCode[l] = nextCode[l] + 1
            table[l.ToStr() + "-" + c.ToStr()] = symbol
        end if
    end for
    return { table: table, maxLen: maxLen }
end function

function DecodeSymbol(reader as object, huff as object) as integer
    code = 0
    for len = 1 to huff.maxLen
        bit = reader.ReadBit()
        code = (code * 2) + bit
        key = len.ToStr() + "-" + code.ToStr()
        if huff.table.DoesExist(key)
            return huff.table[key]
        end if
    end for
    return -1
end function

function GetLength(reader as object, code as integer) as integer
    if code < 257 or code > 285 then return 0
    if code <= 264 then return code - 254
    if code = 285 then return 258

    extraBits = Int((code - 261) / 4)
    base = 0
    if extraBits = 1
        base = 11 + (code - 265) * 2
    else if extraBits = 2
        base = 19 + (code - 269) * 4
    else if extraBits = 3
        base = 35 + (code - 273) * 8
    else if extraBits = 4
        base = 67 + (code - 277) * 16
    else if extraBits = 5
        base = 131 + (code - 281) * 32
    end if

    return base + reader.ReadBits(extraBits)
end function

function GetDistance(reader as object, code as integer) as integer
    if code < 0 or code > 29 then return 0
    if code <= 3 then return code + 1

    extraBits = Int(code / 2) - 1
    base = 0
    if extraBits = 1
        base = 5 + (code - 4) * 2
    else if extraBits = 2
        base = 9 + (code - 6) * 4
    else if extraBits = 3
        base = 17 + (code - 8) * 8
    else if extraBits = 4
        base = 33 + (code - 10) * 16
    else if extraBits = 5
        base = 65 + (code - 12) * 32
    else if extraBits = 6
        base = 129 + (code - 14) * 64
    else if extraBits = 7
        base = 257 + (code - 16) * 128
    else if extraBits = 8
        base = 513 + (code - 18) * 256
    else if extraBits = 9
        base = 1025 + (code - 20) * 512
    else if extraBits = 10
        base = 2049 + (code - 22) * 1024
    else if extraBits = 11
        base = 4097 + (code - 24) * 2048
    else if extraBits = 12
        base = 8193 + (code - 26) * 4096
    else if extraBits = 13
        base = 16385 + (code - 28) * 8192
    end if

    return base + reader.ReadBits(extraBits)
end function

function InflateDeflate(bytes as object) as object
    reader = CreateBitReader(bytes)
    out = CreateObject("roByteArray")

    bfinal = 0
    while bfinal = 0
        bfinal = reader.ReadBit()
        btype = reader.ReadBits(2)

        if btype = 0
            reader.bitIdx = 0
            if reader.byteIdx + 4 <= reader.bytes.Count()
                len = reader.bytes[reader.byteIdx] + reader.bytes[reader.byteIdx + 1] * 256
                reader.byteIdx = reader.byteIdx + 4
                for i = 0 to len - 1
                    if reader.byteIdx < reader.bytes.Count()
                        out.Push(reader.bytes[reader.byteIdx])
                        reader.byteIdx = reader.byteIdx + 1
                    end if
                end for
            else
                bfinal = 1
            end if
        else if btype = 1 or btype = 2
            litHuff = invalid
            distHuff = invalid

            if btype = 1
                lengths = []
                for i = 0 to 143: lengths.Push(8): end for
                for i = 144 to 255: lengths.Push(9): end for
                for i = 256 to 279: lengths.Push(7): end for
                for i = 280 to 287: lengths.Push(8): end for
                litHuff = BuildHuffmanTable(lengths)

                distLengths = []
                for i = 0 to 31: distLengths.Push(5): end for
                distHuff = BuildHuffmanTable(distLengths)
            else
                numLit = reader.ReadBits(5) + 257
                numDist = reader.ReadBits(5) + 1
                numLen = reader.ReadBits(4) + 4

                codeLenOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
                codeLenLengths = []
                for i = 0 to 18: codeLenLengths.Push(0): end for
                for i = 0 to numLen - 1
                    codeLenLengths[codeLenOrder[i]] = reader.ReadBits(3)
                end for

                codeLenHuff = BuildHuffmanTable(codeLenLengths)

                lengths = []
                while lengths.Count() < numLit + numDist
                    sym = DecodeSymbol(reader, codeLenHuff)
                    if sym < 0
                        exit while
                    else if sym <= 15
                        lengths.Push(sym)
                    else if sym = 16
                        prev = 0
                        if lengths.Count() > 0 then prev = lengths[lengths.Count() - 1]
                        rep = reader.ReadBits(2) + 3
                        for j = 0 to rep - 1: lengths.Push(prev): end for
                    else if sym = 17
                        rep = reader.ReadBits(3) + 3
                        for j = 0 to rep - 1: lengths.Push(0): end for
                    else if sym = 18
                        rep = reader.ReadBits(7) + 11
                        for j = 0 to rep - 1: lengths.Push(0): end for
                    end if
                end while

                litLengths = []
                for i = 0 to numLit - 1: litLengths.Push(lengths[i]): end for
                litHuff = BuildHuffmanTable(litLengths)

                distLengths = []
                for i = 0 to numDist - 1: distLengths.Push(lengths[numLit + i]): end for
                distHuff = BuildHuffmanTable(distLengths)
            end if

            while true
                sym = DecodeSymbol(reader, litHuff)
                if sym < 0 or sym = 256
                    exit while
                else if sym < 256
                    out.Push(sym)
                else
                    len = GetLength(reader, sym)
                    distSym = DecodeSymbol(reader, distHuff)
                    dist = GetDistance(reader, distSym)
                    startIdx = out.Count() - dist
                    for j = 0 to len - 1
                        out.Push(out[startIdx + j])
                    end for
                end if
            end while
        else
            bfinal = 1
        end if
    end while

    return out
end function

function ZlibInflate(bytes as object) as object
    if bytes.Count() < 6 then return CreateObject("roByteArray")
    deflateBytes = CreateObject("roByteArray")
    for i = 2 to bytes.Count() - 5
        deflateBytes.Push(bytes[i])
    end for
    return InflateDeflate(deflateBytes)
end function

function ZlibDeflateNoCompression(bytes as object) as object
    out = CreateObject("roByteArray")
    out.Push(120)
    out.Push(1)
    out.Push(1)

    L = bytes.Count()
    out.Push(L mod 256)
    out.Push(Int(L / 256) mod 256)

    NL = 65535 - L
    out.Push(NL mod 256)
    out.Push(Int(NL / 256) mod 256)

    for i = 0 to L - 1
        out.Push(bytes[i])
    end for

    adlerA = 1
    adlerB = 0
    for i = 0 to L - 1
        adlerA = (adlerA + bytes[i]) mod 65521
        adlerB = (adlerB + adlerA) mod 65521
    end for

    out.Push(Int(adlerB / 256) mod 256)
    out.Push(adlerB mod 256)
    out.Push(Int(adlerA / 256) mod 256)
    out.Push(adlerA mod 256)

    return out
end function

function DecodeWatchedBitfield(watchedStr as string) as object
    parts = watchedStr.Split(":")
    if parts.Count() < 5 then return invalid

    sid = parts[0]
    lastSeason = Val(parts[1])
    lastEpisode = Val(parts[2])
    N = Val(parts[3])
    b64 = parts[4]

    ba = CreateObject("roByteArray")
    ba.FromBase64String(b64)
    decompressed = ZlibInflate(ba)

    watchedIndices = []
    powersOfTwo = [1, 2, 4, 8, 16, 32, 64, 128]
    for i = 0 to N - 1
        byteIdx = Int(i / 8)
        bitIdx = i mod 8
        isWatched = false
        if byteIdx < decompressed.Count()
            isWatched = (decompressed[byteIdx] And powersOfTwo[bitIdx]) <> 0
        end if
        if isWatched
            watchedIndices.Push(i)
        end if
    end for

    return {
        sid: sid
        lastSeason: lastSeason
        lastEpisode: lastEpisode
        N: N
        watchedIndices: watchedIndices
    }
end function

function EncodeWatchedBitfield(sid as string, lastSeason as integer, lastEpisode as integer, N as integer, watchedIndices as object) as string
    numBytes = Int((N + 7) / 8)
    ba = CreateObject("roByteArray")
    for j = 0 to numBytes - 1
        ba.Push(0)
    end for

    powersOfTwo = [1, 2, 4, 8, 16, 32, 64, 128]
    for each i in watchedIndices
        if i >= 0 and i < N
            byteIdx = Int(i / 8)
            bitIdx = i mod 8
            ba[byteIdx] = ba[byteIdx] Or powersOfTwo[bitIdx]
        end if
    end for

    compressed = ZlibDeflateNoCompression(ba)
    b64 = compressed.ToBase64String()

    return sid + ":" + lastSeason.ToStr() + ":" + lastEpisode.ToStr() + ":" + N.ToStr() + ":" + b64
end function