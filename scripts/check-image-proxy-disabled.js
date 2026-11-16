#!/usr/bin/env node
// Fails if the dev image proxy is enabled by default in committed source.
// Run manually, via git hook, and via npm test/CI to prevent accidental pushes.

const fs = require("fs");
const path = require("path");

const projectRoot = path.resolve(__dirname, "..");
const mainScenePath = path.join(projectRoot, "components", "MainScene.brs");

function fail(msg) {
  console.error(`image-proxy-check: ${msg}`);
  process.exit(1);
}

if (!fs.existsSync(mainScenePath)) {
  fail(`missing ${path.relative(projectRoot, mainScenePath)}`);
}

const src = fs.readFileSync(mainScenePath, "utf8");
const code = src
  .split("\n")
  .map((line) => line.split("'")[0])
  .join("\n");

if (!/m\.global\.testImageProxyBase\s*=\s*""/.test(code)) {
  fail(
    'MainScene.brs must default m.global.testImageProxyBase to "" (dev image proxy must be disabled by default)'
  );
}

for (const m of code.matchAll(/m\.global\.testImageProxyBase\s*=\s*"([^"]*)"/g)) {
  if (m[1] !== "") {
    fail(
      `MainScene.brs sets m.global.testImageProxyBase to "${m[1]}" — dev image proxy must not be enabled in committed builds`
    );
  }
}

process.exit(0);
