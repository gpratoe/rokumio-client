// Node test for the mock addon server. Boots the server on an ephemeral port
// and asserts every endpoint the stores speak to. Wired into `npm test` after
// the brs suite; same PASS/FAIL convention as the BrightScript harness.
"use strict";

const { createAddonServer } = require("./server");

const server = createAddonServer();
let passed = 0;
let failed = 0;

function request(port, method, path, body) {
    return new Promise((resolve, reject) => {
        const options = {
            host: "127.0.0.1",
            port,
            method,
            path,
            headers: body ? { "Content-Type": "application/json" } : {},
        };
        const req = httpRequest(options, resolve, reject);
        if (body) req.write(JSON.stringify(body));
        req.end();
    });
}

function httpRequest(options, resolve, reject) {
    const http = require("http");
    const req = http.request(options, (res) => {
        let raw = "";
        res.on("data", (chunk) => {
            raw += chunk;
        });
        res.on("end", () => {
            let json = null;
            try {
                json = JSON.parse(raw || "null");
            } catch (err) {
                json = { error: "unparseable body" };
            }
            resolve({ status: res.statusCode, json });
        });
    });
    req.on("error", reject);
    return req;
}

function check(name, condition) {
    if (condition) {
        passed++;
        console.log(`    ok   ${name}`);
    } else {
        failed++;
        console.log(`    FAIL ${name}`);
    }
}

server.listen(0, "127.0.0.1", async () => {
    const port = server.address().port;
    try {
        const health = await request(port, "GET", "/health");
        check("health returns 200 {ok:true}", health.status === 200 && health.json.ok === true);

        const manifest = await request(port, "GET", "/");
        check(
            "manifest returns the addon id",
            manifest.status === 200 && manifest.json.id === "stremio.rokumio.mock"
        );

        const manifestJson = await request(port, "GET", "/manifest.json");
        check(
            "manifest.json alias returns the same manifest",
            manifestJson.status === 200 && manifestJson.json.id === "stremio.rokumio.mock"
        );

        const catalog = await request(port, "GET", "/catalog/movie/top/skip=0.json");
        check(
            "catalog returns two metas",
            catalog.status === 200 && Array.isArray(catalog.json.metas) && catalog.json.metas.length === 2
        );

        const metaMovie = await request(port, "GET", "/meta/movie/tt0133093.json");
        check(
            "movie meta returns a movie",
            metaMovie.status === 200 && metaMovie.json.meta.type === "movie" && metaMovie.json.meta.name.includes("tt0133093")
        );

        const metaSeries = await request(port, "GET", "/meta/series/tt1234567.json");
        check(
            "series meta returns episodes with seasons",
            metaSeries.status === 200 &&
                Array.isArray(metaSeries.json.meta.videos) &&
                metaSeries.json.meta.videos.length === 3 &&
                metaSeries.json.meta.videos[0].season === 1
        );

        const missing = await request(port, "GET", "/nope");
        check("unknown path is 404", missing.status === 404);
    } catch (err) {
        console.error(err);
        failed++;
    } finally {
        server.close();
        console.log("");
        console.log(`Assertions passed: ${passed}  failed: ${failed}`);
        if (failed > 0) {
            console.log("RESULT: FAIL");
            process.exit(1);
        }
        console.log("RESULT: PASS");
    }
});