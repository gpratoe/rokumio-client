// Mock Stremio-shaped addon server for the Rokumio client.
//
// Minimal HTTP server (no dependencies) that stands in for a real addon server
// while M2 builds out the stores. Implements the client-facing surface the
// stores speak to: a host manifest, catalog + meta payloads, and health.
//
// Run directly:   node tools/mock-addon-server/server.js [-p 4141] [--host 0.0.0.0]
// Exercised by:   node tools/mock-addon-server/server.test.js (wired into npm test)
"use strict";

const http = require("http");

const manifest = {
    id: "stremio.rokumio.mock",
    version: "0.1.0",
    name: "Rokumio Mock Addon",
    catalogs: [
        { type: "movie", id: "top", name: "Top Movies" },
        { type: "movie", id: "trending", name: "Trending" },
        { type: "series", id: "top", name: "Top Series" },
    ],
    types: ["movie", "series"],
    resources: ["catalog", "meta"],
};

function sendJson(res, status, body) {
    const text = JSON.stringify(body);
    res.writeHead(status, { "Content-Type": "application/json" });
    res.end(text);
}

function catalogResponse(type, id) {
    return {
        metas: [
            { id: `mock:${type}:${id}:1`, type, name: `Mock ${id} One` },
            { id: `mock:${type}:${id}:2`, type, name: `Mock ${id} Two` },
        ],
    };
}

function metaResponse(type, id) {
    if (type === "series") {
        return {
            meta: {
                id: `mock:series:${id}`,
                type: "series",
                name: `Mock ${id} Series`,
                poster: "https://images.metahub.space/poster/medium/img.png",
                videos: [
                    { id: `mock:series:${id}:s1:e1`, name: `${id} s1e1`, season: 1, episode: 1 },
                    { id: `mock:series:${id}:s1:e2`, name: `${id} s1e2`, season: 1, episode: 2 },
                    { id: `mock:series:${id}:s2:e1`, name: `${id} s2e1`, season: 2, episode: 1 },
                ],
            },
        };
    }
    return {
        meta: {
            id: `mock:movie:${id}`,
            type: "movie",
            name: `Mock ${id} Movie`,
            poster: "https://images.metahub.space/poster/medium/img.png",
        },
    };
}

function streamResponse(type, id) {
    return {
        streams: [
            {
                name: "Mock Torrent",
                type: "torrent",
                infoHash: "0123456789abcdef0123456789abcdef01234567",
                fileIdx: 1,
            },
            { name: "Mock Direct", url: "http://127.0.0.1:11470/mock/file.mp4" },
        ],
    };
}

function createAddonServer() {
    const server = http.createServer((req, res) => {
        const path = new URL(req.url, "http://localhost").pathname;

        if (req.method === "GET" && path === "/health") {
            return sendJson(res, 200, { ok: true });
        }
        if (req.method === "GET" && (path === "/" || path === "/manifest.json")) {
            return sendJson(res, 200, manifest);
        }

        const catalogMatch = path.match(/^\/catalog\/([^/]+)\/([^/]+)\/[\w=+%-]+\.json$/);
        if (req.method === "GET" && catalogMatch) {
            return sendJson(res, 200, catalogResponse(catalogMatch[1], catalogMatch[2]));
        }

        const metaMatch = path.match(/^\/meta\/([^/]+)\/([^/]+)\.json$/);
        if (req.method === "GET" && metaMatch) {
            return sendJson(res, 200, metaResponse(metaMatch[1], metaMatch[2]));
        }

        const streamMatch = path.match(/^\/stream\/([^/]+)\/([^/]+)\.json$/);
        if (req.method === "GET" && streamMatch) {
            return sendJson(res, 200, streamResponse(streamMatch[1], streamMatch[2]));
        }

        sendJson(res, 404, { error: "not found" });
    });
    return server;
}

if (require.main === module) {
    const portIdx = process.argv.indexOf("-p");
    const hostIdx = process.argv.indexOf("--host");
    const port = Number(portIdx >= 0 ? process.argv[portIdx + 1] : 4141);
    const host = hostIdx >= 0 ? process.argv[hostIdx + 1] : "0.0.0.0";
    createAddonServer().listen(port, host, () => {
        console.log(`mock addon server on http://${host}:${port}`);
    });
}

module.exports = { createAddonServer, manifest };