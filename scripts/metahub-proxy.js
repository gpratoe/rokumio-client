const http = require("http");
const https = require("https");
const { URL } = require("url");

// Local test proxy for Metahub image requests (used with temporary client-side
// URL rewriting during development). Injects failures and follows redirects so
// Roku receives final image bytes.
//
// Run: node scripts/metahub-proxy.js
// Client rewrite pattern: https://<host>/<path> -> http://<proxy-ip>:8787/__mh__/<host>/<path>

const DEFAULT_HOST = "images.metahub.space";
const PORT = 8787;

function resolveUpstream(rawUrl) {
  // /__mh__/<host>/<path...> -> https://<host>/<path...>
  const m = /^\/__mh__\/([^/]+)(\/.*)?$/i.exec(rawUrl || "");
  if (m) return { hostname: m[1], path: m[2] || "/", protocol: "https:" };
  return { hostname: DEFAULT_HOST, path: rawUrl || "/", protocol: "https:" };
}

function filterHeaders(headers) {
  const out = {};
  for (const [k, v] of Object.entries(headers || {})) {
    const lk = k.toLowerCase();
    if (
      lk === "connection" || lk === "keep-alive" || lk === "proxy-authenticate" ||
      lk === "proxy-authorization" || lk === "te" || lk === "trailer" ||
      lk === "transfer-encoding" || lk === "upgrade" || lk === "content-length" ||
      lk === "location"
    ) continue;
    out[k] = v;
  }
  return out;
}

function requestUpstream(target, req, res, tag, redirectsLeft) {
  const mod = target.protocol === "http:" ? http : https;
  const port = target.port || (target.protocol === "http:" ? 80 : 443);
  const upstream = mod.request({
    protocol: target.protocol || "https:",
    hostname: target.hostname,
    port,
    path: target.path || "/",
    method: "GET",
    headers: {
      "User-Agent": req.headers["user-agent"] || "Rokumio-Network-Test",
      "Accept": req.headers["accept"] || "*/*",
      "Accept-Encoding": "identity"
    }
  }, (upstreamRes) => {
    const status = upstreamRes.statusCode || 502;
    const loc = upstreamRes.headers.location;

    if ([301, 302, 303, 307, 308].includes(status) && loc) {
      upstreamRes.resume();
      if (redirectsLeft <= 0) {
        console.log("UPSTREAM REDIRECT LIMIT", status, tag, "->", loc);
        if (!res.headersSent) res.writeHead(502, { "Content-Type": "text/plain", "Connection": "close" });
        res.end("Redirect limit");
        return;
      }
      let nextUrl;
      try {
        nextUrl = new URL(loc, `${target.protocol || "https:"}//${target.hostname}${target.path || "/"}`);
      } catch (_e) {
        console.log("UPSTREAM BAD REDIRECT", status, tag, "->", loc);
        if (!res.headersSent) res.writeHead(502, { "Content-Type": "text/plain", "Connection": "close" });
        res.end("Bad redirect");
        return;
      }
      const nextTarget = {
        protocol: nextUrl.protocol,
        hostname: nextUrl.hostname,
        port: nextUrl.port,
        path: nextUrl.pathname + (nextUrl.search || "")
      };
      console.log("UPSTREAM", status, tag, "->", nextTarget.hostname, nextTarget.path);
      requestUpstream(nextTarget, req, res, `${nextTarget.hostname} ${nextTarget.path}`, redirectsLeft - 1);
      return;
    }

    console.log("UPSTREAM", status, tag);
    const headers = filterHeaders(upstreamRes.headers);
    headers["Connection"] = "close";
    res.writeHead(status, headers);
    upstreamRes.pipe(res);
    upstreamRes.on("end", () => console.log("DONE", status, tag));
  });

  upstream.setTimeout(20000, () => {
    console.log("UPSTREAM TIMEOUT:", tag);
    upstream.destroy(new Error("timeout"));
  });

  upstream.on("error", (err) => {
    console.log("UPSTREAM ERROR:", tag, err.message);
    if (!res.headersSent) {
      res.writeHead(502, { "Content-Type": "text/plain", "Connection": "close" });
      res.end("Upstream error");
    } else {
      res.destroy();
    }
  });

  req.on("aborted", () => upstream.destroy());
  res.on("close", () => {
    if (!res.writableEnded) console.log("CLIENT CLOSED EARLY:", tag);
  });

  upstream.end();
}

const server = http.createServer((req, res) => {
  const roll = Math.random();
  const target = resolveUpstream(req.url);
  const tag = `${target.hostname} ${target.path}`;

  if (roll < 0.05) {
    console.log("INJECT RESET:", tag);
    req.socket.destroy();
    return;
  }

  if (roll < 0.20) {
    console.log("INJECT 503:", tag);
    res.writeHead(503, {
      "Content-Type": "text/plain",
      "Retry-After": "5",
      "Connection": "close"
    });
    res.end("Simulated MetaHub failure");
    return;
  }

  console.log("PROXY ->", tag);
  requestUpstream(target, req, res, tag, 5);
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`MetaHub test proxy listening on ${PORT}`);
});
