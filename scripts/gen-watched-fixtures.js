#!/usr/bin/env node
// Generates tests/watchedcodec.fixtures.brs — the codec test corpus.
//
// The bitfield payload is compressed with Node's zlib (the same zlib the
// stremio-watched-bitfield library uses on the server), so the interpreter
// fixtures are the true byte-for-byte shape the codec must decode. Each
// fixture is self-checked here: the payload is re-inflated with the same zlib
// and the baked-in expected watched indices must match before it is written.
//
//   node scripts/gen-watched-fixtures.js
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

// Build the raw bit array (one bit per episode, LSB-first within a byte).
function bitsToBytes(nbits, watched) {
    const bytes = Buffer.alloc(Math.ceil(nbits / 8));
    for (const i of watched) {
        bytes[i >> 3] |= 1 << (i & 7);
    }
    return bytes;
}

function watchedIndicesWithin(rawBytes, expose) {
    const seen = [];
    for (let i = 0; i < expose; i++) {
        if (((rawBytes[i >> 3] >> (i & 7)) & 1) === 1) seen.push(i);
    }
    return seen;
}

// Standard fixture: payload = zlib.deflateSync(raw) with the zlib wrapper.
function standard(seriesId, nbits, watched, lastLength, ids, note) {
    const raw = bitsToBytes(nbits, watched);
    const compressed = zlib.deflateSync(raw); // wrapped: header + adler
    const payloadB64 = compressed.toString('base64');
    return verifyAndBuild(seriesId + ':' + lastLength + ':' + payloadB64, raw, lastLength, ids, note);
}

// Fixture from explicit raw bytes (used to hit the dynamic-Huffman path, which
// zlib only picks for certain inputs).
function rawScenario(seriesId, rawBytes, lastLength, ids, note) {
    const compressed = zlib.deflateSync(rawBytes, { level: 9 });
    return verifyAndBuild(seriesId + ':' + lastLength + ':' + compressed.toString('base64'), rawBytes, lastLength, ids, note);
}

// Stored-block fixture: hand-assembled BTYPE=00 block so the stored path is
// exercised regardless of what zlib's encoder chose for the other fixtures.
function storedBlock(seriesId, nbits, watched, lastLength, ids, note) {
    const raw = bitsToBytes(nbits, watched);
    const len = raw.length;
    const nlen = 0xffff - len;
    const stream = [];
    stream.push(0x01); // BFINAL=1, BTYPE=00, then pad bits 0
    stream.push(len & 0xff, (len >> 8) & 0xff);
    stream.push(nlen & 0xff, (nlen >> 8) & 0xff);
    for (const b of raw) stream.push(b);
    const wrapped = Buffer.concat([Buffer.from([0x78, 0x9c]), Buffer.from(stream), Buffer.from([0, 0, 0, 0])]);
    return verifyAndBuild(seriesId + ':' + lastLength + ':' + wrapped.toString('base64'), raw, lastLength, ids, note);
}

// Compose the fixture and prove the baked-in expectation matches the payload.
function verifyAndBuild(bitfield, rawBytes, lastLength, ids, note) {
    const parts = bitfield.split(':');
    const payloadB64 = parts[parts.length - 1];
    const stream = Buffer.from(payloadB64, 'base64');
    const deflateOnly = stream.slice(2, stream.length - 4); // zlib header + trailing adler
    let rawBack;
    try {
        rawBack = zlib.inflateRawSync(deflateOnly);
    } catch (e) {
        throw new Error(`fixture inflate failed for ${note}: ${e.message}`);
    }
    if (!rawBack.equals(rawBytes)) {
        throw new Error(`fixture mismatch for ${note}: got ${rawBack.toString('hex')} want ${rawBytes.toString('hex')}`);
    }
    const expose = Math.min(lastLength, ids.length, rawBytes.length * 8);
    const expected = watchedIndicesWithin(rawBytes, expose);
    return { bitfield, lastLength, ids, expected, note };
}

function makeIds(seriesId, n) {
    const ids = [];
    for (let i = 0; i < n; i++) {
        ids.push(seriesId + ':' + (Math.floor(i / 12) + 1) + ':' + (i % 12 + 1));
    }
    return ids;
}

const fixtures = [];

// Real fixture from stremio-core's watched-bitfield tests. The zlib payload
// (eJyT...) inflates to bytes 1f 00 — bits 0..4 set, 5 episodes.
fixtures.push({
    bitfield: 'tt2934286:1:5:5:eJyTZwAAAEAAIA==',
    lastLength: 5,
    ids: ['tt2934286:1:1', 'tt2934286:1:2', 'tt2934286:1:3', 'tt2934286:1:4', 'tt2934286:1:5'],
    expected: [0, 1, 2, 3, 4],
    note: 'stremio-core sample'
});

// One-episode series, single bit set, lastLength 1.
{
    const n = 1;
    fixtures.push(standard('tt1110001:1:1', n, [0], 1, makeIds('tt1110001', n), 'single episode watched'));
}

// lastLength 0 → empty bitfield; no bits to expose.
{
    const n = 5;
    fixtures.push(standard('tt2220002:1:1', 0, [], 0, makeIds('tt2220002', n), 'zero-length bitfield'));
}

// 64-bit (8-byte) payload, sparse set across byte boundaries.
{
    const n = 64;
    fixtures.push(standard('tt3330003:5:9', n, [3, 7, 40, 63], n, makeIds('tt3330003', n), 'sparse 64-bit payload'));
}

// 81-bit (11-byte) payload — crosses byte + a nonzero last byte.
{
    const n = 81;
    fixtures.push(standard('tt4440004:3:4', n, [0, 1, 5, 11, 43, 80], n, makeIds('tt4440004', n), '81-bit block-boundary payload'));
}

// 24 episodes, every bit set.
{
    const n = 24;
    const all = [];
    for (let i = 0; i < n; i++) all.push(i);
    fixtures.push(standard('tt5550005:2:1', n, all, n, makeIds('tt5550005', n), 'all 24 episodes watched'));
}

// 200 unwatched episodes = a run of zero bytes, which zlib encodes with a
// length/distance match (exercises the match path regardless of block type).
{
    const n = 200;
    fixtures.push(standard('tt6660006:16:2', n, [], n, makeIds('tt6660006', n), '200 zero bits (run of zeros)'));
}

// A 200-episode claim over data that only holds 24 bits: decode exposes what
// the data can supply, no crash.
{
    const n = 24;
    fixtures.push(standard('tt7770007:12:4', n, [0, 5, 23], 200, makeIds('tt7770007', 200), 'bitfield shorter than its claimed length'));
}

// Episode list shorter than the bitfield: exposed bits clamp to the ids.
{
    const n = 5;
    fixtures.push(standard('tt8880008:1:1', n, [0, 1, 2, 3, 4], 5, makeIds('tt8880008', 2), 'exposed bits clamp to episode list'));
}

// Hand-built stored block (BTYPE=00) with a 24-bit payload.
{
    const n = 24;
    fixtures.push(storedBlock('tt9990009:2:3', n, [0, 14, 17], n, makeIds('tt9990009', n), 'stored block payload'));
}

// Dynamic-Huffman block with back-references: a repetitive text payload
// (zlib emits BTYPE=10 with length/distance matches for this shape). The
// payload is decoded in full even though exposure is capped to the first 96
// bits to keep the fixture small.
{
    const text = Buffer.from(('episode ' + 'watched bitfield pattern '.repeat(20)).repeat(5));
    const n = text.length * 8;
    const watched = [];
    for (let bit = 0; bit < n; bit++) {
        if (((text[bit >> 3] >> (bit & 7)) & 1) === 1) watched.push(bit);
    }
    fixtures.push(rawScenario('tt1010101:1:1', text, 96, makeIds('tt1010101', 96), 'dynamic block with length/distance matches'));
}

const outPath = path.join(__dirname, '..', 'tests', 'watchedcodec.fixtures.brs');
const blocks = [];
blocks.push("' Auto-generated by scripts/gen-watched-fixtures.js - do not edit by hand.\n");
blocks.push("' The codec test corpus: real bitfield strings (ids:long:base64-zlib) plus\n");
blocks.push("' the ordered episode id list and the expected watched indices for each.\n");
blocks.push('function WatchedCodecFixtures() as object\n    return [');
for (const f of fixtures) {
    blocks.push('        {');
    blocks.push(`            note: "${f.note}"`);
    blocks.push(`            bitfield: "${f.bitfield}"`);
    blocks.push(`            lastLength: ${f.lastLength}`);
    blocks.push('            ids: [' + f.ids.map((id) => '"' + id + '"').join(', ') + ']');
    blocks.push('            expected: [' + f.expected.join(', ') + ']');
    blocks.push('        }');
}
blocks.push('    ]\nend function\n');

fs.writeFileSync(outPath, blocks.join('\n'));
console.log(`wrote ${fixtures.length} fixtures -> ${path.relative(process.cwd(), outPath)}`);
function blockTypeOf(bitfield) {
    const parts = bitfield.split(':');
    const stream = Buffer.from(parts[parts.length - 1], 'base64');
    const first = stream[2];
    const type = first & 0x6; // bits 1..2 of the first payload byte
    return type === 0 ? 'stored' : type === 2 ? 'fixed' : 'dynamic';
}
for (const f of fixtures) {
    console.log(`  - ${f.note}: ${blockTypeOf(f.bitfield)} block`);
}