// node tests/run.js — transpile BSL sources and run the brs test suite.
//
// The brs interpreter cannot parse BrighterScript `class` syntax, so the BSL
// class under test is transpiled to BrightScript first (brighterscript API,
// createPackage:false) into a throwaway staging dir, then handed to brs along
// with the plain-BrightScript harness and suites. The process exit code is the
// brs exit code, so `npm test` fails when any assertion fails.
const path = require('path');
const { spawnSync } = require('child_process');
const { ProgramBuilder } = require('brighterscript');

const projectRoot = path.resolve(__dirname, '..');
const stagingDir = path.join(projectRoot, 'out-test');

// The brs interpreter gives every file its own module scope, so top-level
// harness state would not be shared across files. The harness + suites + runner
// are concatenated into one script (functions are hoisted within a program) so
// the tally lives in a single scope.
const combinedPath = path.join(stagingDir, 'tests', '_combined.brs');
async function writeCombinedScript() {
    const fs = require('fs');
    const parts = [
        'tests/harness.brs',
        'tests/mocks.brs',
        'components/NetDiagTask.brs',
        'tests/screenstack.test.brs',
        'tests/transport.test.brs',
        'tests/helpers.test.brs',
        'tests/addonjson.test.brs',
        'tests/settingsstore.test.brs',
        'tests/authstore.test.brs',
        'tests/addonsstore.test.brs',
        'tests/addonsync.test.brs',
        'tests/stremioauthstore.test.brs',
        'tests/catalogstore.test.brs',
        'tests/deeplinkstore.test.brs',
        'tests/episodesstore.test.brs',
        'tests/librarystore.test.brs',
        'tests/librarysync.test.brs',
        'tests/watchstatepush.test.brs',
        'tests/librarywritepush.test.brs',
        'tests/logouttask.test.brs',
        'tests/stremioapistore.test.brs',
        'tests/linkcode.test.brs',
        'tests/playbackstore.test.brs',
        'tests/subtitlesstore.test.brs',
        'tests/netdiagverdict.test.brs',
        'tests/setuppage.test.brs',
        'tests/watchedcodec.fixtures.brs',
        'tests/watchedcodec.test.brs',
        'tests/videoidcodec.test.brs',
        'tests/timeutil.test.brs',
        'tests/emojilabel.test.brs',
        'tests/watchstatebuffer.test.brs',
        'tests/stremiolibrarycodec.test.brs',
        'source/core/TileSize.bs',
        'tests/tilesize.test.brs',
        'tests/devicecap.test.brs',
        'tests/codechints.test.brs',
        'tests/torrentprofile.test.brs',
        'tests/cachesize.test.brs',
        'tests/textsstore.test.brs',
        'tests/serversettingsstore.test.brs',
        'tests/_run.brs'
    ].map(rel => fs.readFileSync(path.join(projectRoot, rel), 'utf8'));
    fs.mkdirSync(path.dirname(combinedPath), { recursive: true });
    fs.writeFileSync(combinedPath, parts.join('\n'));
}

const transpiled = [
    path.join(stagingDir, 'source', 'bslib.brs'),
    path.join(stagingDir, 'source', 'core', 'ScreenStack.brs'),
    path.join(stagingDir, 'source', 'stores', 'Transport.brs'),
    path.join(stagingDir, 'source', 'stores', 'SettingsStore.brs'),
    path.join(stagingDir, 'source', 'stores', 'AuthStore.brs'),
    path.join(stagingDir, 'source', 'stores', 'AddonsStore.brs'),
    path.join(stagingDir, 'source', 'stores', 'CatalogStore.brs'),
    path.join(stagingDir, 'source', 'stores', 'DeepLinkStore.brs'),
    path.join(stagingDir, 'source', 'stores', 'VideoIdCodec.brs'),
    path.join(stagingDir, 'source', 'stores', 'EpisodesStore.brs'),
    path.join(stagingDir, 'source', 'stores', 'TimeUtil.brs'),
    path.join(stagingDir, 'source', 'stores', 'TextsStore.brs'),
    path.join(stagingDir, 'source', 'stores', 'WatchStateBuffer.brs'),
    path.join(stagingDir, 'source', 'stores', 'StremioLibraryCodec.brs'),
    path.join(stagingDir, 'source', 'stores', 'LibraryStore.brs'),
    path.join(stagingDir, 'source', 'stores', 'StremioApiStore.brs'),
    path.join(stagingDir, 'source', 'stores', 'PlaybackStore.brs'),
    path.join(stagingDir, 'source', 'stores', 'SubtitlesStore.brs'),
    path.join(stagingDir, 'source', 'stores', 'ServerSettingsStore.brs'),
    path.join(stagingDir, 'source', 'stores', 'WatchedCodec.brs'),
    path.join(stagingDir, 'source', 'util', 'Regex.brs'),
    path.join(stagingDir, 'source', 'util', 'SetupPage.brs'),
    path.join(stagingDir, 'source', 'util', 'CodecProbe.brs'),
    path.join(stagingDir, 'source', 'util', 'TorrentProfile.brs'),
    path.join(stagingDir, 'source', 'util', 'CacheSize.brs'),
    path.join(stagingDir, 'source', 'util', 'Utilities.brs'),
    path.join(stagingDir, 'source', 'util', 'Helpers.brs'),
    path.join(stagingDir, 'source', 'util', 'AddonJson.brs')
];

function checkDeferredVideoPlayContract() {
    const fs = require('fs');
    const xml = fs.readFileSync(path.join(projectRoot, 'components', 'PlayerScreen.xml'), 'utf8');
    const src = fs.readFileSync(path.join(projectRoot, 'components', 'PlayerScreen.brs'), 'utf8');
    const code = src.split('\n').map((line) => line.split("'")[0]).join('\n');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    if (!/<Timer\s+id="playKick"/.test(xml)) {
        err('PlayerScreen.xml declares no <Timer id="playKick" /> — StartPlayback defers `control = "play"` across it, so without it the player is never asked to play at all');
    }
    if (!/FindNode\(\s*"playKick"\s*\)/.test(code)) {
        err('PlayerScreen.brs never looks up the playKick Timer — the node exists in the XML but nothing holds it, so nothing can start it');
    }
    if (!/ObserveField\(\s*"fire"\s*,\s*"onPlayKickFire"\s*\)/.test(code)) {
        err('PlayerScreen.brs does not ObserveField("fire", "onPlayKickFire") on the playKick Timer — an unobserved Timer fires into nothing and the deferred play never happens');
    }
    const kick = new RegExp('^[ \\t]*sub\\s+onPlayKickFire\\s*\\(', 'm').exec(code);
    if (!kick) {
        err('PlayerScreen.brs has no onPlayKickFire() — the field observer names a handler that does not exist, which is a no-op, so the deferred play never happens');
    } else {
        const rest = code.slice(kick.index);
        const end = rest.slice(1).search(/^[ \t]*end\s+sub\b/m);
        const body = end === -1 ? rest : rest.slice(0, end + 1);
        if (!/m\.video\.control\s*=\s*"play"/.test(body)) {
            err('PlayerScreen.brs onPlayKickFire() never sets m.video.control = "play" — the timer fires and does nothing');
        }
    }

    // And the assignment must not still be sitting in the same tick, which is
    // the thing being fixed. A play inside StartPlayback is only allowed as the
    // fallback for a missing Timer, and only after the timer has been offered.
    const start = new RegExp('^[ \\t]*sub\\s+StartPlayback\\s*\\(', 'm').exec(code);
    if (!start) {
        err('PlayerScreen.brs has no StartPlayback()');
    } else {
        const rest = code.slice(start.index);
        const end = rest.slice(1).search(/^[ \t]*end\s+sub\b/m);
        const body = end === -1 ? rest : rest.slice(0, end + 1);
        const contentAt = body.indexOf('m.video.content =');
        const kickAt = body.indexOf('m.playTimer.control = "start"');
        for (const hit of body.matchAll(/m\.video\.control\s*=\s*"play"/g)) {
            if (kickAt === -1) {
                err('PlayerScreen.brs StartPlayback plays without ever starting the playKick timer — remove the deferral entirely or restore it, but do not leave a play that only runs in some paths');
            } else if (hit.index < kickAt) {
                err('PlayerScreen.brs StartPlayback sets m.video.control = "play" before the playKick timer is started — the play is back on the same tick as the content assignment, which is the race this was split to remove');
            }
        }
        if (contentAt === -1) {
            err('PlayerScreen.brs StartPlayback never assigns m.video.content — the deferral guard has nothing to protect');
        }
        // The other way this can rot silently: with the kick gone AND the
        // fallback play gone, there is no `control = "play"` left in StartPlayback
        // at all and the loop above has nothing to complain about — but nothing
        // ever asks the node to play. Either the timer carries the play or
        // StartPlayback does; never neither.
        if (kickAt === -1 && !/m\.video\.control\s*=\s*"play"/.test(body)) {
            err('PlayerScreen.brs StartPlayback neither starts the playKick timer nor sets control = "play" itself — the video is never asked to play by any path');
        }
    }
    return ok;
}

function checkScreenRuntimeHazards() {
    const fs = require('fs');
    const dir = path.join(projectRoot, 'components');
    let ok = true;
    for (const file of fs.readdirSync(dir).filter((f) => f.endsWith('.brs'))) {
        const src = fs.readFileSync(path.join(dir, file), 'utf8');
        const code = src.split('\n').map((line) => line.split("'")[0]).join('\n');

        // Members this same file assigns [] are arrays; anything else named m.x
        // is left alone rather than guessed at.
        const arrays = new Set([...code.matchAll(/\b(m\.[A-Za-z_][\w.]*)\s*=\s*\[\]/g)].map((hit) => hit[1]));
        for (const hit of code.matchAll(/\bLen\(\s*(m\.[A-Za-z_][\w.]*)/g)) {
            if (arrays.has(hit[1])) {
                console.error(`${file}: Len(${hit[1]}) — ${hit[1]} is assigned [] in this file, so it is an array. Len() on an array is a runtime type mismatch (&h18) that aborts the enclosing function; use ${hit[1]}.Count()`);
                ok = false;
            }
        }

        for (const hit of code.matchAll(/CreateObject\(\s*"(roFileSystem)"\s*\)/g)) {
            console.error(`${file}: creates ${hit[1]}, which is MAIN|TASK-only. Screen callbacks include the Video node's state and bufferingStatus handlers, which arrive on the RENDER thread, so this fails there and takes the handler down with it. Read the value you need from m, or hand the work to a Task.`);
            ok = false;
        }

        // An roSGNode Timer is driven through its `control` field ("start" /
        // "stop"); it has no Start()/Stop() methods, and calling one is a
        // runtime &hf4 "Member function not found". Both timers in PlayerScreen
        // are armed the same way, and the first version of the playKick deferral
        // called Start() on it, which threw inside StartPlayback and stopped the
        // player dead — the one function that must never throw. Resolve the
        // member back to the node it holds so a Timer is only flagged when it
        // really is one.
        const xmlPath = path.join(dir, file.replace(/\.brs$/, '.xml'));
        if (!fs.existsSync(xmlPath)) continue;
        const xml = fs.readFileSync(xmlPath, 'utf8');
        for (const bind of code.matchAll(/\b(m\.[A-Za-z_][\w]*)\s*=\s*m\.top\.FindNode\(\s*"([^"]+)"\s*\)/g)) {
            if (!new RegExp(`<Timer\\s+id="${bind[2]}"`).test(xml)) continue;
            for (const call of code.matchAll(new RegExp(`\\b${bind[1].replace('.', '\\.')}\\.(Start|Stop)\\s*\\(`, 'g'))) {
                console.error(`${file}: calls ${bind[1]}.${call[1]}() on the "${bind[2]}" Timer. An roSGNode Timer has no such methods — it is armed with \`control = "start"\` / \`control = "stop"\`, as this file's other Timer already is. Calling one is a runtime &hf4 that aborts whatever function it sits in.`);
                ok = false;
            }
        }
    }
    return ok;
}

function checkScreenContract() {
    const fs = require('fs');
    const contract = ['SetStores', 'OnEnter', 'OnExit', 'OnBackPressed', 'BlurFocus'];
    const screens = ['HomeScreen', 'DetailsScreen', 'EpisodesScreen', 'StreamsScreen', 'PlayerScreen', 'SettingsScreen', 'AddonsScreen', 'SearchScreen', 'DiscoverScreen', 'LibraryScreen', 'AuthScreen', 'LinkStremioScreen'];
    const declaredSet = (name) => {
        const xml = fs.readFileSync(path.join(projectRoot, 'components', `${name}.xml`), 'utf8');
        return new Set([...xml.matchAll(/<function\s+name="([^"]+)"\s*\/?>/gi)].map(match => match[1]));
    };
    let ok = true;
    const base = declaredSet('Screen');
    for (const fn of contract) {
        if (!base.has(fn)) {
            console.error(`Screen.xml (the base) is missing <function name="${fn}" /> from its interface`);
            ok = false;
        }
    }
    for (const name of screens) {
        const xml = fs.readFileSync(path.join(projectRoot, 'components', `${name}.xml`), 'utf8');
        if (!/<component[^>]*extends="Screen"/.test(xml)) {
            console.error(`${name}.xml must extends="Screen" so it inherits the base contract`);
            ok = false;
        }
        const src = fs.readFileSync(path.join(projectRoot, 'components', `${name}.brs`), 'utf8');
        for (const fn of contract) {
            if (!declaredSet(name).has(fn)) continue;
            if (!new RegExp(`function\\s+${fn}\\s*\\(`).test(src)) {
                console.error(`${name}.xml declares <function name="${fn}" /> but ${name}.brs has no implementation`);
                ok = false;
            }
        }
    }
    return ok;
}

// Roku copies any associative array that crosses a component boundary — a
// callFunc argument, a callFunc return value, an interface field — and drops its
// function members. A bsc class instance IS such an array, so handing the store
// facade to a screen used to deliver a data-only copy: every method call died
// with &hf4 "Member function not found in BrightScript Component or interface"
// (this bit us on device at HomeScreen.brs `m.stores.addons.GetAll()`, and the
// data-only copy still satisfied every `m.stores = invalid` guard, so nothing
// upstream noticed). Only nodes cross by reference, so the Scene keeps the
// facade in an UNDECLARED field and hands each screen the SCENE NODE; the screen
// reads storeFacade off that node. Passing the facade itself is the same
// mistake, and so is declaring the field: a declared field marshals exactly like
// a callFunc argument.
// Two dead ends are pinned here so nobody walks them again. GetGlobalAA() is per
// component on this device, not app-wide, so every screen read back its own
// empty AA ("0 add-ons") while the Scene's own store kept working — the
// deep-link import installs through it. And m.top.getScene() is invalid at
// bind time: init() runs inside screen.CreateScene(), and roSGNode.GetScene()
// returns invalid until screen.Show() has put the tree in a scene, so the
// look-it-up-yourself variant bound invalid on every screen and hid behind the
// guards again. CreateObject("roGlobal") is a BrightSign component that does
// not exist on Roku: CreateObject returns invalid, which the compiler also
// rejects as BS1129.
// The interpreter models one flat scope and cannot catch any of this, so pin it
// statically — and pin the reporting, too: every way the hand-off fails looks
// the same from outside (empty grid, "0 add-ons", no crash, nothing in the log),
// so SetStores has to name the failure on screen. `print` cannot do that job, not
    // because it is invisible to an engineering session but because it is not
    // painting anything: it only reaches whoever is attached to the console at the
    // time, and by the time a bug is investigated that session is long gone.
function checkStoreHandoffContract() {
    const fs = require('fs');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };
    // Scan code, not prose: the files document this exact contract in their
    // headers, and a raw-text scan matches the documentation describing the bug.
    const code = (src) => src.split('\n').map(line => line.split("'")[0]).join('\n');
    const readBr = (n) => code(fs.readFileSync(path.join(projectRoot, 'components', n), 'utf8'));
    const dir = path.join(projectRoot, 'components');
    const mainScene = readBr('MainScene.brs');
    const screenBrs = readBr('Screen.brs');
    const hostBrs = readBr('StoreHost.brs');
    const hostXml = fs.readFileSync(path.join(dir, 'StoreHost.xml'), 'utf8');
    const sceneXml = fs.readFileSync(path.join(dir, 'MainScene.xml'), 'utf8');
    const sceneScreenXml = fs.readFileSync(path.join(dir, 'Screen.xml'), 'utf8');
    const cap = (s) => s.charAt(0).toUpperCase() + s.slice(1);
    const bodyOf = (src, header) => {
        const start = src.indexOf(header) + header.length;
        return src.slice(start, src.indexOf('\nend ', start));
    };
    // Split a BrightScript argument or parameter list on its TOP-LEVEL commas,
    // so `{ a: 1, b: 2 }` or `[[0, 10]]` counts as the one argument it is.
    const splitTop = (text) => {
        const out = [];
        let depth = 0, quote = false, cur = '';
        for (const ch of text) {
            if (quote) { cur += ch; if (ch === '"') quote = false; continue; }
            if (ch === '"') { quote = true; cur += ch; }
            else if ('[{('.includes(ch)) { depth++; cur += ch; }
            else if (']})'.includes(ch)) { depth--; cur += ch; }
            else if (ch === ',' && depth === 0) { out.push(cur.trim()); cur = ''; }
            else cur += ch; }
        if (cur.trim().length > 0) out.push(cur.trim());
        return out;
    };
    // The argument text of the callFunc whose "(" is at `from`, up to the paren
    // that closes it, or null if that paren is not on the same line. Bounded to
    // one line on purpose: the comment stripper above truncates at the first
    // apostrophe, so a three-line scan could be thrown off by a string literal
    // elsewhere in the file, and no call site in this codebase wraps a line.
    const callArgs = (src, from) => {
        let depth = 1, quote = false;
        for (let i = from; i < src.length; i++) {
            const ch = src[i];
            if (ch === '\n') return null;
            if (quote) { if (ch === '"') quote = false; continue; }
            if (ch === '"') quote = true;
            else if (ch === '(') depth++;
            else if (ch === ')' && --depth === 0) return src.slice(from, i);
        }
        return null;
    };

    // --- the host exists, and exists before anything binds to it -------------
    if (!/m\.storeHost\s*=\s*CreateObject\(\s*"roSGNode"\s*,\s*"StoreHost"\s*\)/.test(mainScene)) {
        err('MainScene.brs never creates the StoreHost node — screens would have nothing to read data through');
    }
    if (!/m\.top\.AppendChild\(m\.storeHost\)/.test(mainScene)) {
        err('MainScene.brs must attach the StoreHost to the Scene (m.top.AppendChild(m.storeHost)) — a node component nothing holds a reference to is not guaranteed to stay alive');
    }
    const create = mainScene.search(/m\.storeHost\s*=\s*CreateObject/);
    const firstBind = mainScene.search(/callFunc\(\s*"SetStores"/);
    if (create !== -1 && firstBind !== -1 && firstBind < create) {
        err('MainScene.brs binds a screen before creating the StoreHost — that screen would read invalid');
    }

    // --- every bind hands over two nodes, and every screen gets one ---------
    let binds = 0;
    for (const m of mainScene.matchAll(/callFunc\(\s*"SetStores"\s*,\s*([^)]*)\)/g)) {
        binds++;
        const args = m[1].split(',').map(a => a.trim()).filter(a => a.length > 0);
        if (args.length !== 2 || args[0] !== 'm.storeHost' || args[1] !== 'm.top') {
            err(`MainScene.brs passes "${m[1].trim()}" through callFunc("SetStores", ...) — only a node crosses a component boundary by reference, so the bind must pass m.storeHost (the data layer) and m.top (the Scene, which owns the fault strip)`);
        }
    }
    // Screen.xml is the base every screen extends, not an instance of one.
    const screens = fs.readdirSync(dir).filter(f => /Screen\.xml$/.test(f) && f !== 'Screen.xml');
    if (binds < screens.length) {
        err(`MainScene.brs makes ${binds} SetStores binds for ${screens.length} screen components — an unbound screen comes up with an empty grid and no way to tell why`);
    }

    // --- the host is a delegation layer, not a second MainScene -------------
    const STORES = ['addons', 'auth', 'episodes', 'library', 'settings', 'texts', 'time', 'watch'];
    const defined = new Set([...hostBrs.matchAll(/^(?:function|sub)\s+(\w+)\s*\(/gm)].map(m => m[1]));
    const declared = new Set([...hostXml.matchAll(/<function\s+name="([^"]+)"/g)].map(m => m[1]));
    const own = new Set(['EffectiveSessionType', 'SwitchSession', 'LibrarySessionType']);
    for (const m of hostBrs.matchAll(/^function\s+(\w+)\s*\([^)]*\)(?: as \w+)?\s*$/gm)) {
        const name = m[1];
        if (own.has(name)) continue;
        const body = bodyOf(hostBrs, m[0]).split('\n').map(l => l.trim()).filter(l => l.length > 0);
        if (body.length !== 1) {
            err(`StoreHost.brs ${name} has ${body.length} statements — the host forwards, it does not decide. Logic belongs in the store class, where the store tests can reach it`);
            continue;
        }
        if (!/^(return )?m\.stores\.[a-z]+\.[A-Za-z_]+\(.*\)$/.test(body[0])) {
            err(`StoreHost.brs ${name} must be exactly "return m.stores.<store>.<Method>(...)" (no return for a void store method) — anything else is logic in the hand-off layer (got: ${body[0]})`);
            continue;
        }
        // The name says which store it answers for; the body has to agree, or a
        // copy-paste between two same-shaped forwarders hands a screen the
        // wrong store's data and nothing complains.
        const store = STORES.find(s => name.startsWith(cap(s)));
        if (!store) {
            err(`StoreHost.brs ${name} has no store prefix — entry points are named <Store><Method> so the call site says which store it is asking`);
        } else if (!new RegExp('^(return )?m\\.stores\\.' + store + '\\.[A-Za-z_]+\\(').test(body[0])) {
            err(`StoreHost.brs ${name} forwards to a different store than its name claims — screens reach it as m.stores.${store} and would be handed another store's data`);
        }
    }
    for (const n of declared) {
        if (!defined.has(n)) {
            err(`StoreHost.xml declares <function name="${n}" /> but StoreHost.brs does not define it — callFunc against an undefined function is a silent no-op that returns invalid`);
        }
    }
    for (const n of defined) {
        if (!declared.has(n) && n !== 'init') {
            err(`StoreHost.brs defines ${n} but StoreHost.xml does not declare it — callFunc only runs for interface functions, so every caller would get invalid back with nothing on screen to say so`);
        }
    }
    // Every script in a component shares one function namespace, and BrightScript
    // identifiers are case-insensitive, so an entry point whose name matches a
    // store's parameter makes the store's own signature ambiguous. bsc calls it
    // BS1104 and reports it in the store file, four files from the cause — so
    // the host's 48 new names have to be checked against the sources it pulls in.
    const sourceDir = path.join(projectRoot, 'source');
    const paramNames = new Set();
    const walk = (dir) => {
        for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
            const full = path.join(dir, entry.name);
            if (entry.isDirectory()) {
                walk(full);
            } else if (entry.name.endsWith('.bs')) {
                const src = fs.readFileSync(full, 'utf8');
                // Indented, because every store method sits inside a class block.
                for (const m of src.matchAll(/^[ \t]*(?:function|sub)\s+\w+\s*\(([^)]*)\)/gm)) {
                    for (const arg of m[1].split(',')) {
                        const name = arg.trim().split(/\s+as\s+/)[0].trim().toLowerCase();
                        if (name) paramNames.add(name);
                    }
                }
            }
        }
    };
    walk(sourceDir);
    for (const n of defined) {
        if (paramNames.has(n.toLowerCase())) {
            err(`StoreHost.brs defines ${n} and a store under source/ has a parameter by that name — one shared, case-insensitive function namespace, so the store's own signature becomes ambiguous (bsc: BS1104, reported in the store's file)`);
        }
    }

    // The name in a callFunc is a string, so nothing but a static check stands
    // between a typo and the device's &hf4 "Member function not found", and an
    // argument count the entry point does not take fails the same way one hop
    // later. Both are checked below, against the signatures the host actually
    // declares. This is the check that would have caught the four
    // Library Mark* calls EpisodesScreen made on a store that had no entry
    // points for them at all — those shipped to the TV and killed the debugger
    // on the first mark-as-watched press.
    const hostSigs = new Map();
    for (const m of hostBrs.matchAll(/^(?:function|sub)\s+(\w+)\s*\(([^)]*)\)/gm)) {
        hostSigs.set(m[1], splitTop(m[2]).map(p => ({ text: p, required: p.split(/\s+as\s+/)[0].indexOf('=') === -1 })));
    }
    // --- every store call resolves, and no store instance is ever in flight --
    for (const name of fs.readdirSync(dir).filter(f => f.endsWith('.brs'))) {
        if (name === 'StoreHost.brs') continue;
        const src = readBr(name);
        for (const m of src.matchAll(/\bm\.(stores\.[a-z]+|storeHost)\.callFunc\(\s*"([A-Za-z_]+)"/g)) {
            const [, alias, fn] = m;
            if (!defined.has(fn) || !declared.has(fn)) {
                err(`${name} calls callFunc("${fn}") but the StoreHost has no such entry point — the screen would read invalid and render nothing`);
                continue;
            }
            if (alias.startsWith('stores.')) {
                const store = alias.slice('stores.'.length);
                if (!fn.startsWith(cap(store))) {
                    err(`${name} reaches m.stores.${store} for "${fn}" — the name's store prefix must match the alias, or a screen can quietly be handed another store's data`);
                }
            }
            const sig = hostSigs.get(fn);
            // The match ends on the entry point's NAME, so the callFunc "(" is
            // the last paren inside it, not one past the end: step from there to
            // just inside the argument list, where the scan starts at depth 1.
            const argText = callArgs(src, m.index + m[0].lastIndexOf('(') + 1);
            const given = argText === null ? null : splitTop(argText).slice(1);
            if (given === null) {
                err(`${name} calls callFunc("${fn}") with an argument list that never closes — read it as unverified, not as correct`);
            } else if (given.length > sig.length) {
                err(`${name} calls callFunc("${fn}") with ${given.length} arguments but StoreHost.brs ${fn} takes ${sig.length} (${sig.map(p => p.text).join(', ')}) — the VM raises an arity error at runtime, after the call has already left the screen`);
            } else if (given.length < sig.length) {
                const missing = sig.slice(given.length).filter(p => p.required);
                if (missing.length > 0) {
                    err(`${name} calls callFunc("${fn}") without ${missing.map(p => p.text).join(', ')} — StoreHost.brs ${fn} requires ${sig.length} arguments, and a call that omits a required one raises a runtime error`);
                }
            }
        }
        // A store alias stashed in a local is how the Mark* crash got through:
        // the call on the NEXT line was spelled `<local>.Method(`, which no
        // rewrite pattern and no direct-call check above can see, because the
        // alias is a hop away. The alias has to be spelled at the call site,
        // where it is greppable and where the store prefix is checkable.
        for (const m of src.matchAll(/=\s*m\.stores\.[a-z]+\s*$/gm)) {
            err(`${name} assigns a store alias to a variable — spell it at the call site instead (m.stores.${m[0].match(/stores\.([a-z]+)/)[1]}.callFunc("<Store><Method>", ...)). A local hides the store behind a name nothing resolves, so a direct call on it compiles, ships, and dies with &hf4 on the device`);
        }
        if (/=\s*m\.storeHost\s*$/m.test(src)) {
            err(`${name} assigns m.storeHost to a variable — same reason: keep the host spelled at the call site so every store call stays checkable`);
        }
        for (const m of src.matchAll(/\bm\.stores\.[a-z]+\.(?!callFunc\b)([A-Za-z_]+)\s*\(/g)) {
            err(`${name} calls m.stores.${m[1]} directly — a store class instance cannot be handed to another component (Roku copies the associative array and drops its function members); ask the host instead: m.stores.<store>.callFunc("<Store><Method>", ...)`);
        }
        if (/CreateObject\(\s*"roGlobal"/i.test(src) || /GetGlobalAA\(\)/.test(src)) {
            err(`${name} reaches for a global singleton (roGlobal / GetGlobalAA) — neither is shared across components on this device; use the StoreHost node`);
        }
    }

    // --- print is a tracing tool here, not a reporting channel ----------------
    // There used to be a blanket ban on `print` in every component, on the stated
    // grounds that "Roku routes BrightScript print to the Dev Console, not to the
    // device console". That premise is wrong: telnet 8085 IS the device console
    // log, so a print is read live by whoever has an engineering session
    // attached — which is exactly how the [subs]/[addons]/[resolve] traces were
    // read to diagnose the caption failures. Screen.brs says as much in its own
    // header, and a lint that contradicts the file it guards is worse than no
    // lint, because it teaches you to distrust the comment.
    //
    // What the ban was really proxying — do not use print INSTEAD OF painting a
    // fault — is already pinned, and better, by the checks on SetStores above
    // (probe the host, report the fault) and on the strip below (declared, built
    // in init, attached, written through its own fields, sets m.faultText.text).
    // Those say what a short bind has to produce; a print cannot produce any of
    // it, so banning print never added coverage — it only cost us the traces.
    //
    // print stays legal in components/*.brs. Following a worker across a task
    // boundary, or a three-state status down a retry loop, is what it is for.
    // The abandoned carrier, in any file. The host included: a StoreHost that
    // published a facade would be the same split-brain one layer down.
    for (const name of fs.readdirSync(dir).filter(f => f.endsWith('.brs'))) {
        if (/\bstoreFacade\b/.test(readBr(name))) {
            err(`${name} still refers to storeFacade — the facade-on-the-Scene carrier is gone; the StoreHost node is the hand-off`);
        }
    }

    // --- one instance per store, in one place --------------------------------
    // The stores StoreHost owns. DeepLinkStore is deliberately absent: the Scene
    // builds one per deep link and throws it away (DeepLinkStore().Parse(args)),
    // so there is no state to diverge.
    for (const cls of ['AuthStore', 'SettingsStore', 'AddonsStore', 'CatalogStore', 'EpisodesStore', 'LibraryStore', 'PlaybackStore', 'SubtitlesStore', 'WatchStateBuffer', 'TimeUtil']) {
        if (new RegExp('=\\s*(m\\.stores\\.[a-z]+\\s*=\\s*)?' + cls + '\\s*\\(').test(mainScene)) {
            err(`MainScene.brs constructs ${cls} — the data layer belongs to StoreHost. A second instance is a second copy of that store's in-memory state, which is how two screens end up disagreeing about the same session`);
        }
    }
    for (const name of fs.readdirSync(dir).filter(f => f.endsWith('.brs'))) {
        if (name === 'StoreHost.brs' || name === 'MainScene.brs') continue;
        for (const cls of ['LibraryStore', 'WatchStateBuffer']) {
            if (new RegExp('=\\s*' + cls + '\\s*\\(').test(readBr(name))) {
                err(`${name} constructs ${cls} — that store holds in-memory state, so a private instance is a second copy of it; only the stateless per-request wrappers may be built by a task or screen`);
            }
        }
    }

    // --- SetStores takes two nodes and probes the whole path -----------------
    const setStores = screenBrs.match(/^function\s+SetStores\s*\(([^)]*)\)/m);
    if (!setStores) {
        err('Screen.brs no longer defines SetStores — every screen would come up with no stores');
        return ok;
    }
    const args = setStores[1].split(',').map(a => a.trim()).filter(a => a.length > 0);
    if (args.length !== 2) {
        err(`Screen.brs SetStores must take exactly two nodes — the StoreHost to read through and the Scene to report to (found "${setStores[1].trim()}")`);
    }
    const body = bodyOf(screenBrs, setStores[0]);
    if (!/callFunc\(\s*"AddonsGetAll"/.test(body)) {
        err('Screen.brs SetStores must probe the host (callFunc("AddonsGetAll")) — a bind that cannot say which hop failed is the silence that hid three shipping bugs');
    }
    if (!/callFunc\(\s*"ReportStoreFault"/.test(body)) {
        err('Screen.brs SetStores must report a failed bind to the Scene (callFunc("ReportStoreFault", reason, active)) — otherwise a broken store layer is indistinguishable from an empty catalog');
    }
    if (/getScene\(\)/.test(screenBrs)) {
        err('Screen.brs calls getScene() — roSGNode.GetScene() returns invalid until screen.Show() has put the tree in a scene, which is after init(); bind from the nodes MainScene passes instead');
    }
    // screenActive is the stack's, and the only field a screen may declare: a
    // declared field copies its value, so a store handed over that way arrives
    // without its methods. The hand-off is the node, in a callFunc argument.
    for (const m of sceneScreenXml.matchAll(/<field\s+id="([^"]+)"/g)) {
        if (m[1] !== 'screenActive') {
            err(`Screen.xml declares <field id="${m[1]}"> — a declared field copies the value it is given, so anything live handed over that way arrives stripped; the store hand-off is the StoreHost node passed to SetStores`);
        }
    }

    // --- MainScene forwards the stable screen-facing API; FaultStrip owns it.
    if (!/<function\s+name="ReportStoreFault"\s*\/>/.test(sceneXml)) {
        err('MainScene.xml must declare ReportStoreFault() — screens report their bind failures through this stable interface');
    }
    const report = mainScene.match(/^sub\s+ReportStoreFault\s*\(/m);
    if (!report) {
        err('MainScene.brs no longer defines ReportStoreFault — screens would report into nothing');
    } else if (!/m\.faultStrip\.callFunc\("ReportStoreFault"/.test(bodyOf(mainScene, report[0]))) {
        err('MainScene.ReportStoreFault must forward to FaultStrip; MainScene should not own the strip state');
    }
    const sceneInit = mainScene.match(/^sub\s+init\s*\(\)\s*$/m);
    const sceneInitBody = sceneInit ? bodyOf(mainScene, sceneInit[0]) : '';
    if (!/m\.faultStrip\s*=\s*m\.top\.FindNode\("faultStrip"\)/.test(sceneInitBody) || !/<FaultStrip\s+id="faultStrip"/.test(sceneXml)) {
        err('MainScene must hold the declared FaultStrip node — reporting through an absent node silently loses every fault');
    }

    const faultBrs = fs.readFileSync(path.join(dir, 'FaultStrip.brs'), 'utf8');
    const faultXml = fs.readFileSync(path.join(dir, 'FaultStrip.xml'), 'utf8');
    const faultDefined = new Set([...faultBrs.matchAll(/^(?:function|sub)\s+(\w+)\s*\(/gm)].map(m => m[1]));
    const faultDeclared = new Set([...faultXml.matchAll(/<function\s+name="([^"]+)"/g)].map(m => m[1]));
    for (const name of ['ReportStoreFault', 'ReportTransientFault', 'ClearTransientFault']) {
        if (!faultDefined.has(name) || !faultDeclared.has(name)) {
            err(`FaultStrip must define and declare ${name} — callFunc only reaches functions in the component interface`);
        }
    }
    const faultInit = faultBrs.match(/^sub\s+init\s*\(\)\s*$/m);
    const faultInitBody = faultInit ? bodyOf(faultBrs, faultInit[0]) : '';
    if (!/m\.storeFaults\s*=\s*\{\}/.test(faultInitBody) || !/m\.transientFaults\s*=\s*\{\}/.test(faultInitBody)) {
        err('FaultStrip init must initialize both fault maps — an unassigned AA is invalid, and iterating it is a render-thread crash');
    }
    for (const [field, node] of [['m.bar', 'Rectangle'], ['m.label', 'Label']]) {
        if (!new RegExp(field + '\\s*=\\s*CreateObject\\(\\s*"roSGNode"\\s*,\\s*"' + node + '"').test(faultInitBody) || !new RegExp('m\\.top\\.AppendChild\\(' + field + '\\)').test(faultInitBody)) {
            err(`FaultStrip init must create and attach ${field} (${node}) once — an unattached node renders nothing`);
        }
    }
    const paint = faultBrs.match(/^sub\s+Refresh\s*\(\)\s*$/m);
    if (!paint) {
        err('FaultStrip has no Refresh() — a reported fault would never be painted');
    } else {
        const paintBody = bodyOf(faultBrs, paint[0]);
        if (/CreateObject\(|AppendChild\(|FindNode\(|\.Join\(/.test(paintBody)) {
            err('FaultStrip.Refresh() must update its existing nodes directly, building the line by concatenation');
        }
        if (!/m\.label\.text\s*=/.test(paintBody) || !/m\.bar\.visible\s*=/.test(paintBody) || !/m\.label\.visible\s*=/.test(paintBody)) {
            err('FaultStrip.Refresh() must set the label and both visibility fields — otherwise a fault may paint as a blank bar');
        }
    }
    const transient = faultBrs.match(/^sub\s+ReportTransientFault\s*\([^)]*\)\s*$/m);
    if (!transient) {
        err('FaultStrip no longer defines ReportTransientFault');
    } else {
        const body = bodyOf(faultBrs, transient[0]);
        if (!/m\.timer\.control\s*=\s*"start"/.test(body) || !/Refresh\(\)/.test(body)) {
            err('FaultStrip.ReportTransientFault must restart the shared timer and repaint');
        }
    }
    const expiry = faultBrs.match(/^sub\s+onDismissTimerFire\s*\(\)\s*$/m);
    if (!expiry) {
        err('FaultStrip no longer defines onDismissTimerFire — transient faults would outlive their deadline');
    } else {
        const expiryBody = bodyOf(faultBrs, expiry[0]);
        if (!/m\.transientFaults\s*=\s*\{\}/.test(expiryBody) || !/Refresh\(\)/.test(expiryBody)) {
            err('FaultStrip.onDismissTimerFire must clear transient faults and repaint');
        }
    }
    if (!/m\.storeFaults/.test(faultBrs) || !/m\.transientFaults/.test(faultBrs)) {
        err('FaultStrip must merge sticky and transient faults in its display');
    }
    const addonFault = mainScene.match(/^sub\s+AddAddonSyncFault\s*\([^)]*\)\s*$/m);
    if (!addonFault) {
        err('MainScene.brs no longer defines AddAddonSyncFault');
    } else {
        const addonFaultBody = bodyOf(mainScene, addonFault[0]);
        if (!/ReportTransientFault\(/.test(addonFaultBody) || /ReportStoreFault\(/.test(addonFaultBody)) {
            err('MainScene.brs AddAddonSyncFault must report through the transient channel only — sync faults heal by retry and must not outlive the strip');
        }
    }
    return ok;
}

// Including the same script file twice in one component corrupts the shared
// function namespace at load time — a class that some other script then calls
// resolves to a non-function ("Function Call Operator ( ) attempted on
// non-function") on the device. This bit us with WatchedCodec.bs, so pin it:
// no component may repeat a script uri.
function checkNoDuplicateScripts() {
    const fs = require('fs');
    const components = fs.readdirSync(path.join(projectRoot, 'components')).filter(f => f.endsWith('.xml'));
    let ok = true;
    for (const name of components) {
        const xml = fs.readFileSync(path.join(projectRoot, 'components', name), 'utf8');
        const uris = [...xml.matchAll(/<script[^>]*uri="([^"]+)"/gi)].map(m => m[1]);
        const seen = new Set();
        for (const uri of uris) {
            if (seen.has(uri)) {
                console.error(`${name} includes <script uri="${uri}"> more than once — a duplicated script corrupts the component scope`);
                ok = false;
            }
            seen.add(uri);
        }
    }
    return ok;
}

// Roku scopes user-defined global functions per component, so a store method
// invoked from a screen's scope must never call a bare cross-file global —
// `WatchedCodec()` resolved to invalid at runtime inside EpisodeWatched that
// way. The interpreter cannot model this (run.js concatenates one scope), so
// pin it statically: LibraryStore may construct the codec exactly once, in
// new() (which runs under MainScene's scope), and must decode via the stored
// m.codec instance from then on.
function checkLibraryCodecContract() {
    const fs = require('fs');
    const src = fs.readFileSync(path.join(projectRoot, 'source', 'stores', 'LibraryStore.bs'), 'utf8');
    let ok = true;
    const constructors = [];
    for (const [i, line] of src.split('\n').entries()) {
        const code = line.split("'")[0];
        if (/\bWatchedCodec\s*\(/.test(code)) constructors.push(code.trim());
    }
    if (constructors.length !== 1) {
        console.error(`LibraryStore.bs must call WatchedCodec() exactly once, in new(); found ${constructors.length} call(s)`);
        ok = false;
    } else if (!/^m\.codec = WatchedCodec\(\)/.test(constructors[0])) {
        console.error(`LibraryStore.bs: the single WatchedCodec() call must be the m.codec capture in new() (found "${constructors[0]}")`);
        ok = false;
    }
    if (!/\bm\.codec\s*\.\s*WatchedDecode\s*\(/.test(src)) {
        console.error('LibraryStore.bs must decode account bitfields through m.codec.WatchedDecode (a bare global WatchedCodec() dies cross-component)');
        ok = false;
    }
    return ok;
}

// MarkupGrid only updates item components through interface fields named
// `itemContent` and `itemHasFocus` — never `content` or `focused`. This bit us:
// PosterTile observed the wrong fields and never rendered text or focus. Guard
// the interface so the tile's render contract stays pinned to the grid's API.
// Both tiles must keep their interfaces read-only-exclusive: no `content` /
// `focused` re-declaration may ever creep back in (it would silently shadow the
// list's own fields and break the recycle behavior).
function checkTileContract() {
    const fs = require('fs');
    const tiles = [
        { name: 'PosterTile', fields: ['itemContent', 'itemHasFocus', 'rowHasFocus'] },
        { name: 'EpisodeTile', fields: ['itemContent', 'itemHasFocus', 'rowHasFocus'] }
    ];
    let ok = true;
    for (const tile of tiles) {
        const xml = fs.readFileSync(path.join(projectRoot, 'components', `${tile.name}.xml`), 'utf8');
        const declared = new Set(
            [...xml.matchAll(/<field\s+id="([^"]+)"[\s>]/gi)].map(match => match[1])
        );
        for (const field of tile.fields) {
            if (!declared.has(field)) {
                console.error(`${tile.name}.xml is missing <field id="${field}" ... /> from its interface`);
                ok = false;
            }
        }
        for (const forbidden of ['content', 'focused']) {
            if (declared.has(forbidden)) {
                console.error(`${tile.name}.xml must not re-declare <field id="${forbidden}"> — the list drives items through itemContent/itemHasFocus only`);
                ok = false;
            }
        }
    }
    return ok;
}

// Group.visible defaults to true, and screens are declared children of the
// Scene, so an undisclosed screen paints over the stack's top screen (this bit
// us: DummyDetail covered HomeScreen from the first frame). Screens must start
// hidden; only the stack makes them visible. PlayerScreen is intentionally NOT
// here: it is built fresh per play in MainScene and destroyed on pop so the
// device releases the media player (a static child would survive and keep
// leaking audio). Its interface contract is still pinned by checkScreenContract.
// main.brs calls scene.callFunc('Start') and — for an ECP deep link —
// scene.callFunc('HandleDeepLink', args). callFunc only invokes functions
// declared in a component's interface, so a missing declaration would quietly
// no-op on device (Start exists today, so only HandleDeepLink is new). Pin
// both here so the bootstrap contract stays honest.
function checkMainSceneContract() {
    const fs = require('fs');
    const brs = fs.readFileSync(path.join(projectRoot, 'components', 'MainScene.brs'), 'utf8')
        .split('\n').map(line => line.split("'")[0]).join('\n');
    const xml = fs.readFileSync(path.join(projectRoot, 'components', 'MainScene.xml'), 'utf8');
    const declared = new Set(
        [...xml.matchAll(/<function\s+name="([^"]+)"\s*\/?>/gi)].map(match => match[1])
    );
    let ok = true;
    for (const fn of ['Start', 'HandleDeepLink']) {
        if (!declared.has(fn)) {
            console.error(`MainScene.xml is missing <function name="${fn}" /> from its interface`);
            ok = false;
        }
    }
    // Every dialog in the app — support, confirm-exit, logout, session-revoked,
    // deep-link import — is shown by assigning it to m.top.dialog. That slot is
    // NOT built into Scene: assign to it without declaring it and the write
    // lands in an undeclared dynamic field that nothing observes, so the dialog
    // simply never appears. No error, no log line, no crash — which is why
    // every dialog in the app was broken at once and looked like one component
    // misbehaving. `dialog` was never declared, here or at any earlier commit.
    const assigns = [...brs.matchAll(/\bm\.top\.dialog\s*=\s*(?!invalid\b)/g)];
    if (assigns.length > 0 && !/<field\s+id="dialog"\s+type="node"/.test(xml)) {
        console.error(`MainScene.brs shows ${assigns.length} dialog(s) through m.top.dialog but MainScene.xml does not declare <field id="dialog" type="node" /> — the Scene renders no dialog slot it has not been told about, so every one of these assignments writes an undeclared field and shows nothing`);
        ok = false;
    }
    // Dialogs are BUILT, not declared. Both custom dialogs used to be declared as
    // Scene children with visible="false". On device they dimmed the background
    // and took focus — blind OK on the Exit button still fired buttonSelected,
    // so they were alive, laid out and interactive — and painted nothing at all.
    // Their own code was never at fault; the CreateObject shape that the three
    // StandardMessageDialogs already use renders every one of them.
    // Comments describe the old shape by name, so strip them before matching.
    const dialogTags = [...xml.replace(/<!--[\s\S]*?-->/g, '').matchAll(/<([A-Za-z0-9_]*Dialog)\b/g)].map(m => m[1]);
    if (dialogTags.length > 0) {
        console.error(`MainScene.xml declares ${dialogTags.join(', ')} as a Scene child — a dialog declared in markup dims the background and takes focus but paints nothing on this device (verified on both the exit and support dialogs). Build it with CreateObject("roSGNode", "...") and show it through scene.dialog, the shape the three StandardMessageDialogs use`);
        ok = false;
    }
    // Every node handed to the dialog slot must have been built in code.
    // (Holding a reference is not the concern it looks like: assigning to
    // scene.dialog puts the node in the Scene's dialog group, and from there the
    // scene graph itself keeps it alive. The Scene keeps m.confirmExit and
    // m.supportDialog because it re-shows them and their observers are scoped.)
    const built = new Set([...brs.matchAll(/([\w.]+)\s*=\s*CreateObject\(\s*"roSGNode"\s*,\s*"[A-Za-z0-9_]*Dialog"/g)].map(m => m[1]));
    for (const m of brs.matchAll(/m\.top\.dialog\s*=\s*([^=\n]+)/g)) {
        const target = m[1].trim();
        if (target === 'invalid') continue;
        if (!built.has(target)) {
            console.error(`MainScene.brs shows "${target}" through m.top.dialog but nothing ever builds it with CreateObject — a dialog that is declared in markup, or reached any other way, dims the background and paints nothing`);
            ok = false;
        }
    }
    return ok;
}

// Poster.loadStatus is a string with four legal values. Guesses against it are
// invisible at build time and fail silently on the device, and three shipped:
// "ready" on the pairing screen's SUCCESS path, "<> error" in both tiles (always
// true, so a failed image was treated as having art), and then "loaded" in both
// tiles plus the pairing screen — a string that is not documented at all, which
// made every gate a no-op and left the artless face rendering behind its own
// artwork on every row. The literals are plain strings, so nothing but a static
// check stands between a guess and a device. That check used to carry the same
// wrong list it was meant to police, so it agreed with the bug; the set is now
// derived once, below, and the fallback contract asserts the tiles' gate matches.
const POSTER_LOAD_STATUS = {
    none: 'No loading or decoding taking place (the default)',
    loading: 'Being fetched and decoded',
    ready: 'Fetched and decoded, ready to be drawn',
    failed: 'Could not be loaded',
};
const POSTER_LOAD_STATUS_LEGAL = Object.keys(POSTER_LOAD_STATUS);
const POSTER_LOAD_STATUS_READY = 'ready';

function checkPosterStatusContract() {
    const fs = require('fs');
    const LEGAL = POSTER_LOAD_STATUS_LEGAL;
    let ok = true;
    for (const name of fs.readdirSync(path.join(projectRoot, 'components')).filter(f => f.endsWith('.brs'))) {
        const src = fs.readFileSync(path.join(projectRoot, 'components', name), 'utf8')
            .split('\n').map(line => line.split("'")[0]).join('\n');
        // Which locals hold a loadStatus in this file, then every string each of
        // them is compared against. Dataflow is one assignment wide on purpose:
        // the bug is a mistyped literal, not a mistyped variable.
        const vars = new Set([...src.matchAll(/(\w+)\s*=\s*[\w.]+\.loadStatus\b/g)].map(m => m[1]));
        for (const v of vars) {
            for (const m of src.matchAll(new RegExp('\\b' + v + '\\s*(?:<>|<|>|=)\\s*"([^"]+)"', 'g'))) {
                if (!LEGAL.includes(m[1])) {
                    console.error(`${name} compares ${v} (a Poster loadStatus) against "${m[1]}" — the only values are ${LEGAL.join(' / ')}; a status that can never occur makes the branch dead, silently`);
                    ok = false;
                }
            }
        }
    }

    // Police the police. The list above is the one thing standing between a
    // mistyped literal and a device, so it must be exactly the documented set:
    // admitting an invented value (it once admitted "loaded") silently restores
    // the class of bug this whole check exists to catch.
    const expected = ['none', 'loading', 'ready', 'failed'];
    if (LEGAL.length !== expected.length || expected.some((v, i) => LEGAL[i] !== v)) {
        console.error(`the Poster loadStatus allowlist is [${LEGAL.join(', ')}], but the documented set is [${expected.join(', ')}]. An allowlist that admits a value the OS never reports makes every comparison against it dead code`);
        ok = false;
    }

    // A success path must be reachable. Every surface that hides something
    // behind a poster needs the one value that means "a bitmap exists"; if that
    // literal is wrong the branch never runs and the fallback never goes away.
    // Both spellings count: the tiles compare m.poster.loadStatus directly, the
    // pairing screen copies it into a local first.
    for (const name of ['PosterTile.brs', 'EpisodeTile.brs', 'LinkStremioScreen.brs']) {
        const src = fs.readFileSync(path.join(projectRoot, 'components', name), 'utf8')
            .split('\n').map(line => line.split("'")[0]).join('\n');
        const held = [...new Set([...src.matchAll(/(\w+)\s*=\s*[\w.]+\.loadStatus\b/g)].map(m => m[1]))];
        const subjects = ['loadStatus', ...held].join('|');
        const compared = [...src.matchAll(new RegExp('\\b(?:' + subjects + ')\\s*(?:<>|<|>|=)\\s*"([^"]+)"', 'g'))].map(m => m[1]);
        if (!compared.includes(POSTER_LOAD_STATUS_READY)) {
            console.error(`${name} never tests a Poster loadStatus against "${POSTER_LOAD_STATUS_READY}" (${POSTER_LOAD_STATUS.ready}). Without the success value its load handling cannot tell artwork from no artwork, so the fallback renders over the image forever`);
            ok = false;
        }
    }
    return ok;
}

// A tile is one of two states and only ever one at a time: the artless unit (a
// face plus the title) or the poster. Four separate bugs came out of looser
// versions of this rule, so pin the shape it settled on:
//
//   * The gate must be loadStatus = "ready" — the documented success value, and
//     the only one that proves a bitmap exists. Treating any non-failed URL as
//     art left the tile a blank face for the whole download, and this file once
//     itself compared against a non-existent "loaded", which made the branch
//     dead on every row: the face kept rendering behind its own artwork. The
//     literal comes from POSTER_LOAD_STATUS_READY above, not a second guess.
//   * The two states swap as a unit. Gating the *title* alone let it paint over
//     artwork, and declaration order was the only thing hiding that — a recycled
//     tile reports "loading" for the uri it is being handed while still holding
//     the previous cell's bitmap, so the text went visible on top of it.
//   * The status is re-read where the uri is set, because an image that resolves
//     from cache can settle without the observer ever firing.
//   * The poster must never be hidden. Declaring it visible="false" and
//     unhiding it once the artwork arrived deadlocked the load against the gate
//     waiting on it — loadStatus never arrived, so every tile stayed artless. A
//     Poster with no bitmap paints nothing, so there is nothing to hide.
//   * The poster must never be hidden. Declaring it visible="false" and
//     unhiding it once the artwork arrived deadlocked the load against the gate
//     waiting on it — loadStatus never arrived, so every tile stayed artless. A
//     Poster with no bitmap paints nothing, so there is nothing to hide.
function checkPosterFallbackContract() {
    const fs = require('fs');
    const read = (f) => fs.readFileSync(path.join(projectRoot, 'components', f), 'utf8');
    const body = (src, sig) => {
        const start = src.indexOf(sig);
        if (start === -1) return null;
        const next = src.indexOf('\nsub ', start + 1);
        return next === -1 ? src.slice(start) : src.slice(start, next);
    };
    let ok = true;

    // Both tiles: the face and poster must be one hideable unit, nothing may
    // deadlock the poster's own load, and the success branch must be reachable.
    for (const name of ['PosterTile', 'EpisodeTile']) {
        const xml = read(`${name}.xml`);
        const src = read(`${name}.brs`).split('\n').map(line => line.split("'")[0]).join('\n');

        const open = xml.indexOf('<Group id="artless"');
        if (open === -1) {
            console.error(`${name}.xml has no <Group id="artless"> — the face and the title must be one unit that hides as one`);
            ok = false;
            continue;
        }
        const close = xml.indexOf('</Group>', open);
        const inner = close === -1 ? '' : xml.slice(open, close);
        if (!inner.includes('id="tileBg"') || !inner.includes('id="titleText"')) {
            console.error(`${name}.xml the artless group must contain both tileBg and titleText`);
            ok = false;
        }

        const art = xml.match(/<Poster\s+id="poster"[^>]*>/);
        if (art === null) {
            console.error(`${name}.xml has no <Poster id="poster">`);
            ok = false;
        } else {
            // Liveness, and the reason the deadlock happened: a Poster that is
            // not visible never loads, so gating its visibility on loadStatus
            // made the gate wait on the thing the gate prevented.
            if (/visible="false"/.test(art[0])) {
                console.error(`${name}.xml declares the poster visible="false" — it must be visible in order to load at all. Gating its visibility on loadStatus deadlocks the load against the gate waiting on it, leaving every tile artless`);
                ok = false;
            }
        }

        // The face must actually STOP rendering. Relying on the poster painting
        // over it left the face visible behind artwork on unfocused rows.
        for (const [sig, want] of [['sub ShowArtless()', 'true'], ['sub ShowPoster()', 'false']]) {
            const b = body(src, sig);
            if (b === null) {
                console.error(`${name}.brs has no ${sig} — the artless unit must be hidden once artwork paints, or the face renders behind the poster`);
                ok = false;
                continue;
            }
            if (!new RegExp(`m\\.artless\\.visible\\s*=\\s*${want}\\b`).test(b)) {
                console.error(`${name}.brs ${sig} must set m.artless.visible = ${want}`);
                ok = false;
            }
        }

        const handler = body(src, 'sub onPosterLoadStatus()');
        if (handler === null) {
            console.error(`${name}.brs has no onPosterLoadStatus() — nothing would ever hide the face once artwork lands`);
            ok = false;
        } else {
            // One shared source of truth for the success value, and one whole
            // shape rather than three loose greps: this file once hardcoded the
            // wrong literal in two places and agreed with itself, and a handler
            // that merely *mentions* the right status is not enough — "= ready
            // and false" or an inverted branch keeps the face on screen while
            // passing a substring check. The two states are mutually exclusive
            // by construction: exactly one of them, decided by exactly that
            // comparison.
            const shape = new RegExp(
                `if\\s+m\\.poster\\.loadStatus\\s*=\\s*"${POSTER_LOAD_STATUS_READY}"\\s+then\\s+ShowPoster\\(\\)\\s+else\\s+ShowArtless\\(\\)`,
            );
            if (!shape.test(handler)) {
                console.error(`${name}.brs onPosterLoadStatus() must be exactly 'if m.poster.loadStatus = "${POSTER_LOAD_STATUS_READY}" then ShowPoster() else ShowArtless()'. "${POSTER_LOAD_STATUS_READY}" is the documented success value (${POSTER_LOAD_STATUS.ready}); the full set is ${POSTER_LOAD_STATUS_LEGAL.join(' / ')} and there is no "loaded". Anything that merely mentions the right status can still leave the face rendering over the artwork, so pin the whole conditional`);
                ok = false;
            }
        }

        if (!/m\.poster\.ObserveField\("loadStatus"/.test(src)) {
            console.error(`${name}.brs never observes poster.loadStatus, so the face is never hidden when artwork lands`);
            ok = false;
        }
        // A uri can resolve from cache and settle before the observer fires, so
        // the status has to be re-read where the uri is set.
        if (!new RegExp(`m\\.poster\\.loadStatus\\s*=\\s*"${POSTER_LOAD_STATUS_READY}"[\\s\\S]{0,80}onPosterLoadStatus\\(\\)`).test(src)) {
            console.error(`${name}.brs does not re-read loadStatus after setting the uri — a cached image can settle before the observer fires, leaving the face showing over real artwork`);
            ok = false;
        }

        // Never hide the poster from code either: same deadlock, one layer down.
        if (/m\.poster\.visible\s*=/.test(src)) {
            console.error(`${name}.brs assigns poster.visible — the poster must stay visible to load. Only the artless unit is toggled`);
            ok = false;
        }
        if (/titleText\.visible/.test(src)) {
            console.error(`${name}.brs sets titleText.visible directly — visibility belongs to the artless Group, which hides as one unit with the face`);
            ok = false;
        }

        // Paint order still matters: the poster must be able to cover the face.
        if (xml.indexOf('<Group id="artless"') > xml.indexOf('<Poster id="poster"')) {
            console.error(`${name}.xml declares the poster BEFORE the artless group — the poster would paint under the face and title`);
            ok = false;
        }
    }

    return ok;
}

// Auth changes pivot the session-aware stores through a single ReconcileSession()
// (the type is derived from the auth authority, never a call-site literal). A
// stray store.SwitchSession(...) anywhere else means a flow — or a future 4th
// session-aware store — repointed stores by hand and the guest/stremio
// separation can silently drift. Pin it: SwitchSession may only be called
// inside ReconcileSession.
function checkSessionAuthorityContract() {
    const fs = require('fs');
    const read = (f) => fs.readFileSync(path.join(projectRoot, 'components', f), 'utf8');
    const brs = read('MainScene.brs');
    const host = read('StoreHost.brs');
    let ok = true;
    // The Scene may only ask for a pivot from ReconcileSession(), the one
    // authority — and it asks the HOST, which is where the session-aware
    // instances now live.
    const calls = [...brs.matchAll(/callFunc\(\s*"SwitchSession"/g)].map(match => match.index);
    if (calls.length === 0) {
        console.error('MainScene.brs no longer asks for a session pivot anywhere (callFunc("SwitchSession", type)) — the session-aware stores never move off the old session');
        return false;
    }
    const subStart = brs.indexOf('sub ReconcileSession()');
    const nextSub = brs.indexOf('\nsub ', subStart + 1);
    const body = nextSub === -1 ? brs.slice(subStart) : brs.slice(subStart, nextSub);
    for (const index of calls) {
        if (index < subStart || index > nextSub) {
            console.error(`MainScene.brs pivots the session at byte ${index}, outside sub ReconcileSession() — every pivot must go through the authority`);
            ok = false;
        }
    }
    // The host holds the instances, so the host does the fan-out, and it walks
    // one list — a hardcoded pair would silently skip the next session-aware
    // store that joins, which is the failure this rule exists to prevent.
    if (!/\.SwitchSession\s*\(/.test(host)) {
        console.error('StoreHost.brs no longer calls SwitchSession on its session-aware stores — nothing would pivot them');
        ok = false;
    } else if (!/sub\s+SwitchSession\s*\([^)]*\)\s*\n\s*for each store in m\.sessionAware\s*\n\s*store\.SwitchSession\(/.test(host)) {
        console.error('StoreHost.brs SwitchSession must walk m.sessionAware — a hardcoded pair silently leaves the next session-aware store on the old session');
        ok = false;
    }
    // A stray direct pivot anywhere else means some flow bypassed the authority.
    for (const name of fs.readdirSync(path.join(projectRoot, 'components')).filter(f => f.endsWith('.brs'))) {
        if (name === 'StoreHost.brs') continue;
        if (/\.SwitchSession\s*\(/.test(read(name))) {
            console.error(`${name} pivots a store's session directly — only StoreHost may, and only from its SwitchSession entry point, or guest and stremio drift apart`);
            ok = false;
        }
    }
    return ok;
}

// A stremio session's add-ons exist ONLY as whatever the account sync wrote to
// the stremio_addons registry key — AddonsStore deliberately shows no built-in
// seeds for that session type. So an empty key means no Cinemeta, which means
// every AddonsGet("com.linvo.cinemeta") caller gets invalid, including
// MetaAddress(), which is what the Continue Watching row's Details fetch needs.
//
// Three claims about that were carried by COMMENTS rather than by anything a
// test could contradict, and a single failed login-time sync made all of them
// false at once: the session went permanently catalog-less, the failure printed
// nothing, and the only recovery was logging out and re-pairing the account.
// Each is pinned here.
function checkStremioProvisioningContract() {
    const fs = require('fs');
    const read = (f) => fs.readFileSync(path.join(projectRoot, f), 'utf8');
    const brs = read('components/MainScene.brs');
    const syncCoordinator = read('components/AccountSyncCoordinator.brs');
    const screen = read('components/Screen.brs');
    const api = read('source/stores/StremioApiStore.bs');
    let ok = true;

    const subBody = (source, name) => {
        const match = new RegExp(`^[ \\t]*sub ${name}\\s*\\(`, 'm').exec(source);
        if (!match) return '';
        const next = source.indexOf('\nsub ', match.index + 1);
        return next === -1 ? source.slice(match.index) : source.slice(match.index, next);
    };

    // 1. A relaunched stremio session must re-pull the collection, not trust
    //    that a past login left one behind.
    const start = subBody(brs, 'Start');
    if (!/EffectiveSessionType\(\)\s*=\s*"stremio"/.test(start)) {
        console.error('MainScene.brs sub Start() no longer branches on a stremio session — a relaunched account session would sync nothing at all');
        ok = false;
    } else if (!/StartAddonSync\(\)/.test(start)) {
        console.error('MainScene.brs sub Start() does not call StartAddonSync() for a relaunched stremio session — an empty stremio_addons key can never recover, and recovery used to mean re-pairing the account');
        ok = false;
    }
    if (!/StartLibrarySync\(\)/.test(start)) {
        console.error('MainScene.brs sub Start() no longer re-pulls the library on a relaunched stremio session');
        ok = false;
    }

    // 2. The collection is the one unbounded response in the client (whole
    //    collection, every manifest embedded, update:true on top), so it must
    //    ride the long-timeout path. On the default window it returned the same
    //    { ok: false } as a real refusal and the caller could not tell them apart.
    const collection = /function\s+AddonCollectionGet\(\)[\s\S]*?end\s+function/.exec(api);
    if (!collection) {
        console.error('StremioApiStore.bs has no AddonCollectionGet — the account collection pull is gone');
        ok = false;
    } else if (!/PostLong\(\s*"\/api\/addonCollectionGet"/.test(collection[0])) {
        console.error('StremioApiStore.bs AddonCollectionGet must use PostLong, not Post — the collection is the one unbounded response in the client and aborts on the default window');
        ok = false;
    }
    if (!/private\s+function\s+PostLong\s*\(/.test(api)) {
        console.error('StremioApiStore.bs has no PostLong helper — AddonCollectionGet cannot reach the long-timeout path');
        ok = false;
    }

    // 3. A sync that reports nothing must say so. A transport timeout, an HTTP
    //    error and an empty account all used to fall off the end of the sub
    //    identically, so Home kept rendering pre-login rows looking healthy.
    const result = subBody(syncCoordinator, 'onAddonResult');
    if (!/callFunc\("ClearAddonSyncFaults"\)/.test(result)) {
        console.error('AccountSyncCoordinator.onAddonResult does not retract previous fault lines — a retry that failed differently would leave stale errors up forever');
        ok = false;
    }
    if (!/callFunc\("AdoptAddonSyncResult",\s*result\)/.test(result) || !/if\s+not\s+result\.ok\s*\n[\s\S]{0,400}?AddAddonSyncFault\(/.test(brs)) {
        console.error('AccountSyncCoordinator must hand add-on results to MainScene, where failed syncs are reported');
        ok = false;
    }
    const adopt = subBody(brs, 'AdoptAddonSyncResult');
    if (!/result\.error/.test(adopt)) {
        console.error('MainScene.AdoptAddonSyncResult must retain the transport error in its displayed fault');
        ok = false;
    }
    if (!/AddAddonSyncFault\(\s*"addon sync: the account reported no add-ons"/.test(brs)) {
        console.error('MainScene.AdoptAddonSyncResult must name the synced-but-empty outcome — that is the exact state that used to require re-pairing');
        ok = false;
    }

    // 4. The bind probe must not report a stremio session's pre-sync emptiness as
    //    a hand-off fault. It did, and it pointed the investigation at StoreHost
    //    instead of at the request that never arrived.
    const condition = /else\s+if\s+installed\.Count\(\)\s*=\s*0([^\n]*)\n/.exec(screen);
    if (!condition) {
        console.error('Screen.brs no longer reports an empty add-on list as a store fault — the probe lost its "the store answered with nothing" hop');
        ok = false;
    } else if (!/callFunc\(\s*"AuthGetSession"\s*\)\s*<>\s*"stremio"/.test(condition[1])) {
        console.error('Screen.brs raises the empty-add-ons fault for a stremio session — that state is normal between launch and the collection landing, and reporting it names the wrong subsystem');
        ok = false;
    }
    if (!/callFunc\(\s*"AuthGetSession"/.test(screen)) {
        console.error('Screen.brs reads the session through something other than callFunc("AuthGetSession") — the store alias must be spelled at the call site or the hand-off check cannot see it');
        ok = false;
    }
    return ok;
}

// FinishImport calls m.homeScreen.callFunc('RebuildRows') after a deep-link
// import lands new add-ons. Same callFunc interface-declaration trap as
// MainScene above — pin it or a missing declaration silently no-ops on device.
// The add-on sync worker is the one place in this app where a correct-looking
// handler destroys its own answer, and it did so on every first login.
//
// Every Task in this app declares its result as an alwaysNotify field with no
// value, and Roku delivers one notification for such a field at ObserveField time
// carrying whatever the field holds then. The subtlety that cost two deploys to
// pin down: that notification is NOT delivered at the attach. It is queued and
// dispatched on the event loop, so it arrives after AsyncTask_Launch has returned
// and after `control = "RUN"` has started the worker. The queued notification is
// therefore indistinguishable, by arrival, from the real one.
//
// Both handlers got this wrong, in opposite directions:
//
//   onAddonSyncResult read an empty result as "the task produced nothing" and
//   immediately AsyncTask_Reap — which unobserves the field and removes the node.
//   This file's own headers record that removing a running Task node does NOT kill
//   its worker thread, so the genuine result landed on a node nobody was watching.
//   The account's add-ons were silently dropped, `added` stayed 0, RebuildRows
//   never ran, and Home went on rendering its pre-login rows. On device that read
//   as "the catalog never updates when I log in" — a plausible-looking UI bug with
//   no cause anywhere in the UI. FIX: decline an empty result; let the sentinel
//   decide.
//
//   onAddonSyncFinished then arrived as the reporting path and treated the mere
//   ARRIVAL of a "finished" notification as proof the worker was done. It reaped
//   the node and published
//     addon sync: the worker finished with no result (stage: request-started)
//   on the first run of every sync, while the worker was still blocked inside its
//   HTTP call — stage read from a task in flight. FIX: test the sentinel's VALUE.
//   `true` is the only thing that means the worker ran sync() to completion.
//
// The general rule, which both handlers now follow and which the checks below pin:
// for an alwaysNotify field, the notification's arrival means nothing; only the
// value it carries does.
//
// The brs interpreter cannot execute a Task worker thread, so no test in this repo
// can observe any of this. It is the same blind spot as AA iteration order and the
// &h18 truthiness crash: a green suite is not evidence. So the invariant is pinned
// structurally here, and the worker narrates its own progress into a "stage" field
// so that if it ever fails again the fault text names the hop instead of costing
// another round of hypotheses.
// The engine warm-up is what makes the readiness wait possible at all, it spans
// three files, and no interpreter test can reach any of it: the Task's Wait()
// ABORTS the run, and a HEAD in a store is one line. So the invariants below are
// the only guard, and every one of them fails SILENTLY — still compiling, still
// green, still timing out exactly as before.
function checkEngineWarmupContract() {
    const fs = require('fs');
    const read = (f) => fs.readFileSync(path.join(projectRoot, f), 'utf8');
    const code = (src) => src.split('\n').map(line => line.split("'")[0]).join('\n');
    const task = code(read('components/StreamResolveTask.brs'));
    const store = code(read('source/stores/PlaybackStore.bs'));
    const transport = code(read('source/stores/Transport.bs'));
    const player = code(read('components/PlayerScreen.brs'));
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    // 1. HEAD has to reach roUrlTransfer AS a HEAD. Transport used to special-case
    //    only POST, so every other method fell through to AsyncGetToString() and
    //    a "HEAD" was quietly a GET — against a stream route advertising a
    //    Content-Length in the gigabytes, which is a request to buffer an entire
    //    feature into a string while believing it was asking for headers.
    if (!/request\.method\s*=\s*"HEAD"/.test(transport) || !/AsyncHead\(\)/.test(transport)) {
        err('Transport.bs does not dispatch HEAD to AsyncHead() — every method except POST falls through to AsyncGetToString(), so the warm-up would silently be a full GET of the stream route');
    }

    // 2. The warm-up must precede the playlist probe. Order IS the fix: a playlist
    //    request to a server that has not been told to make an engine is not a
    //    slow request, it is a hung one — which is what six timed-out probes and a
    //    44-second wait turned out to be.
    const warmAt = task.search(/WarmEngine\(/);
    const probeAt = task.search(/WaitForPlaylist\(/);
    if (warmAt === -1) {
        err('StreamResolveTask.brs never calls WarmEngine() — the engine is never asked for, so the probe is asking a server that was never told to make one');
    } else if (probeAt !== -1 && warmAt > probeAt) {
        err('StreamResolveTask.brs warms the engine AFTER probing for the playlist — the probe has to run first or it is still the request that hangs');
    }

    // 3. Both warm-up timeouts have to actually arrive, and they are two numbers
    //    because the two requests are not alike. The HEAD submits work and answers
    //    in 30-65ms (the server logs "Engine created" that far behind the
    //    request); the ranged GET is the one that blocks until the engine has
    //    torrent metadata, which is the entire cost of a DHT-only cold start.
    //
    //    They were one constant, and that is how a 40ms request ended up holding
    //    the same budget as the request meant to wait — which is how a cold engine
    //    outlived the cap that existed to notice it. The ceilings below are not
    //    "what the work needs", they are the two ways this can rot: the HEAD
    //    drifting up toward the readiness budget, and the readiness read drifting
    //    up toward a hang.
    const headTimeout = /const\s+ENGINE_HEAD_TIMEOUT_MS\s*=\s*(\d+)/.exec(store);
    const readyTimeout = /const\s+ENGINE_READY_TIMEOUT_MS\s*=\s*(\d+)/.exec(store);
    if (!headTimeout) {
        err('PlaybackStore.bs has no ENGINE_HEAD_TIMEOUT_MS — the warm-up HEAD pays the 15s default, and a default-sized budget on the request that only submits work is where the readiness budget came from in the first place');
    } else {
        if (Number(headTimeout[1]) > 8000) {
            err(`PlaybackStore.bs ENGINE_HEAD_TIMEOUT_MS is ${headTimeout[1]}ms — this request has answered in 30-65ms every time it has been logged, so a budget past 8s is not headroom, it is slack that will get spent on the readiness read instead`);
        }
        if (!/Head\(url,\s*ENGINE_HEAD_TIMEOUT_MS\)/.test(store)) {
            err('PlaybackStore.bs WarmEngine does not pass ENGINE_HEAD_TIMEOUT_MS to Head — the constant is declared but the warm-up still pays the default timeout');
        }
    }
    if (!readyTimeout) {
        err('PlaybackStore.bs has no ENGINE_READY_TIMEOUT_MS — the ranged metadata read falls back to the 15s default, which is the request whose whole job is to block until a cold engine is ready');
    } else {
        if (Number(readyTimeout[1]) > 20000) {
            err(`PlaybackStore.bs ENGINE_READY_TIMEOUT_MS is ${readyTimeout[1]}ms — past this the readiness read is no longer waiting out a cold engine, it is the thing deciding whether the stream is servable, and the probe loop behind it is what decides that`);
        }
    }

    // 3b. The pair is one budget, and only their sum is meaningful. Measured waits
    //     were 1.78s / 3.03s / 4.71s / and one over 8s, so the read needs real room
    //     — but the room does not come from the HEAD, and a pair that can creep up
    //     independently is how the warm-up ends up quietly longer than the probe
    //     loop it sits in front of.
    if (headTimeout && readyTimeout) {
        const warmBudget = Number(headTimeout[1]) + Number(readyTimeout[1]);
        if (warmBudget > 20000) {
            err(`the warm-up can spend ${warmBudget}ms before the probe loop even starts (${headTimeout[1]}ms HEAD + ${readyTimeout[1]}ms readiness read) — the readiness wait is measured in single-digit seconds, so a pair totalling over 20s means the split has drifted back toward one number`);
        }
    }

    // 4. It must be unable to fail the resolve. The warm-up is an optimisation, and
    //    sharing the probe's catch would report its fault as a probe that gave up
    //    — describing a request the server never received as one it refused.
    if (!/catch\s+e\s+resolved\.warmup\s*=/.test(task)) {
        err('StreamResolveTask.brs does not give the warm-up a catch that records it — a throw there would be reported as a failed resolve, or as the probe giving up');
    }

    // 5. A 2xx warm-up is deliberately NOT logged by the transport trace, so the
    //    record it rides back on is the only evidence the request happened at all.
    if (!/result\.warmup\s*<>\s*invalid/.test(player)) {
        err('PlayerScreen.brs never reads result.warmup — a warm-up that succeeded leaves no trace anywhere, so a stall would have nothing to rule it out with');
    }

    // 6. The record has to say WHAT the engine was handed. A timed-out warm-up is
    //    ambiguous on its own — a slow server and an engine with no trackers to
    //    bootstrap from produce the identical line — and those two call for
    //    opposite fixes, so the count is what makes the next run decidable.
    if (!/resolved\.warmup\.trackers\s*=/.test(task)) {
        err('StreamResolveTask.brs does not record how many trackers the engine was handed — a timed-out warm-up cannot otherwise be told apart from an engine bootstrapping over DHT alone');
    }
    if (!/warmup\.trackers\s*<>\s*invalid/.test(player)) {
        err('PlayerScreen.brs never prints the warm-up tracker count — the diagnostic that distinguishes a slow server from an engine with nothing to bootstrap from');

    }

    // 7. The warm-up is TWO requests, and the second is the one that matters. The
    //    HEAD gets the engine CREATED and returns in milliseconds, so it never said
    //    whether the engine could then ANSWER — the probe behind it kept finding
    //    that out the slow way, one timeout at a time. Stremio's client follows the
    //    HEAD with a ranged GET of the first 64KB and lets it block until the
    //    engine has torrent metadata, and the server's log for a device that
    //    starts cleanly shows exactly that request sitting between the HEAD and
    //    the /hls.m3u8.
    //
    //    Without it the warm-up creates an engine and walks away, which is the
    //    state the last unexplained timeout in this whole path came from: the
    //    server held our probe open for ~8.4s gathering metadata and a 4s
    //    deadline cancelled it. The Range header is also what keeps this from
    //    becoming the mistake check #1 describes — an unbounded GET on the torrent
    //    route is a request to buffer a whole feature into a string.
    if (!/bytes=0-65535/.test(store)) {
        err('PlaybackStore.bs WarmEngine no longer asks for a byte range — the HEAD creates the engine but never waits for its metadata, so the readiness probe is back to timing out against a server that was still legitimately working');
    }
    if (!/GetRaw\(\s*url\s*,\s*ENGINE_READY_TIMEOUT_MS\s*,\s*\{[^}]*"Range"/.test(store)) {
        err('PlaybackStore.bs WarmEngine does not pass a Range header to GetRaw — the forced-metadata read is either gone, or became an unbounded GET of the torrent route');
    }
    if (!/function\s+GetRaw\([^)]*headers/.test(transport)) {
        err('Transport.bs GetRaw does not accept headers — the forced-metadata read has nowhere to put its Range header, so it can only ever be a full-body GET');
    }

    // 8. And the result of it has to be readable, or the one thing this warm-up
    //    is for is invisible. HEAD 200 with a dead range means the engine was
    //    created and never became ready; both 200 means the engine was ready and
    //    anything after this belongs to the player.
    if (!/warmup\.range\s*<>\s*invalid/.test(player)) {
        err('PlayerScreen.brs never reads result.warmup.range — a warm-up whose engine was created but never became ready leaves no trace anywhere, which is the one distinction this second request exists to make');
    }

    return ok;
}

// The device refuses NEW concurrent connections past a low ceiling (~4-6):
// sequential soaks are perfect while 8-wide bursts drop transfers, and the
// app's parallel launch syncs collide the same way. Transport's bounded retry
// is what keeps a lost race from failing the fetch. None of this is reachable
// from the brs interpreter — every store test injects a fake client and the
// real one needs roUrlTransfer — so the invariants are pinned structurally.
function checkTransportRetryContract() {
    const fs = require('fs');
    const read = (f) => fs.readFileSync(path.join(projectRoot, f), 'utf8');
    const transport = read('source/stores/Transport.bs');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    if (!/const\s+MAX_TRANSPORT_ATTEMPTS\s*=\s*\d+/.test(transport)) {
        err('Transport.bs has no MAX_TRANSPORT_ATTEMPTS — a retry loop without a ceiling hammers a dead host, and no retry at all lets a connection collision fail the fetch');
    }
    const policy = /function\s+TransportFailureIsRetryable\s*\(\s*status\s+as\s+integer\s*\)\s*as\s+boolean\s*[\s\S]*?return\s+status\s*<\s*0[\s\S]*?end\s+function/.exec(transport);
    if (!policy) {
        err('Transport.bs TransportFailureIsRetryable must retry only negative (transport-level) statuses — an HTTP 404/500 is a real answer, and retrying a timeout (status 0) multiplies a full wait');
    }
    const exec = /client\._execute\s*=\s*function\s*\(request[\s\S]*?\n    end function/.exec(transport);
    if (!exec) {
        err('Transport.bs has no client._execute — the retry wrapper is gone and a connection collision fails the fetch outright');
    } else {
        const body = exec[0];
        if (!/m\._attempt\(request\)/.test(body)) {
            err('Transport.bs client._execute does not call m._attempt — the single round-trip is the thing being retried');
        }
        if (!/m\._retryable\(result\.status\)/.test(body) || !/m\._retryAfter\(attempt\)/.test(body)) {
            err('Transport.bs client._execute does not consult the retry policy and backoff — the retry is unconditional or absent');
        }
        if (!/MAX_TRANSPORT_ATTEMPTS/.test(body)) {
            err('Transport.bs client._execute does not cap attempts at MAX_TRANSPORT_ATTEMPTS — an unbounded retry can hammer a dead host');
        }
    }

    // The backoff has to DESYNCHRONISE, not merely delay. The failure being
    // ridden out is a refused connect, which the device answers in milliseconds
    // — which is exactly when a fixed backoff is worst. Every loser wakes at the
    // same instant, is refused again at the same instant, and keeps marching in
    // step. A fixed backoff reproduces the stampede it exists to break.
    if (!/const\s+TRANSPORT_RETRY_JITTER_MS\s*=\s*\d+/.test(transport)) {
        err('Transport.bs has no TRANSPORT_RETRY_JITTER_MS — retries share one fixed schedule, so the clients that lost the same race all retry at the same instant');
    }
    if (!/Rnd\(\s*TRANSPORT_RETRY_JITTER_MS\s*\)/.test(transport)) {
        err('Transport.bs never applies Rnd(TRANSPORT_RETRY_JITTER_MS) — the jitter is declared but the retries are still synchronised');
    }
    // Rnd is a Roku global and does not resolve in the brs interpreter, so it
    // must not reach TransportRetryBackoffMs: that file-scope function IS
    // exercised by the suite. It belongs on the client closure, which
    // CreateSyncHttpClient builds and no store test ever reaches (every one
    // injects a fake client).
    const backoff = /function\s+TransportRetryBackoffMs\s*\([^)]*\)([\s\S]*?)end\s+function/.exec(transport);
    if (backoff && /\bRnd\s*\(/.test(backoff[1])) {
        err('Transport.bs TransportRetryBackoffMs calls Rnd — that file-scope function is run by the brs interpreter, which has no Rnd global, and the unit tests for it would throw at runtime');
    }
    return ok;
}

// The two account pulls (add-on collection and library) are both launched in
// Start() and on login completion. Firing them together opens two NEW
// connections at the same instant — exactly the concurrency the device refuses
// past ~4-6. The library sync is therefore deferred behind the add-on sync and
// pumped when it settles. The interpreter cannot run either Task, so the
// ordering is pinned structurally.
function checkStaggeredSyncContract() {
    const fs = require('fs');
    const brs = fs.readFileSync(path.join(projectRoot, 'components', 'AccountSyncCoordinator.brs'), 'utf8');
    const scene = fs.readFileSync(path.join(projectRoot, 'components', 'MainScene.brs'), 'utf8');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    const body = (name) => {
        const start = new RegExp(`^[ \\t]*(?:sub|function)\\s+${name}\\s*\\(`, 'm').exec(brs);
        if (!start) return null;
        const rest = brs.slice(start.index);
        const end = rest.slice(1).search(/^[ \\t]*end\\s+(?:sub|function)\\b/m);
        return end === -1 ? rest : rest.slice(0, end + 1);
    };

    const start = body('StartLibrarySync');
    if (!start || !/m\.addonTask\s*<>\s*invalid/.test(start) || !/m\.pendingLibrarySync\s*=\s*true/.test(start)) {
        err('AccountSyncCoordinator.StartLibrarySync no longer defers behind an in-flight add-on sync — both launch-time pulls would open connections at once');
    }
    if (!/LaunchLibrarySync\(\)/.test(start || '')) {
        err('AccountSyncCoordinator.StartLibrarySync no longer launches the library sync when it is free to do so');
    }
    const pump = body('PumpPendingLibrarySync');
    if (!pump || !/m\.pendingLibrarySync\s*<>\s*true\s+then\s+return/.test(pump) || !/LaunchLibrarySync\(\)/.test(pump)) {
        err('AccountSyncCoordinator.PumpPendingLibrarySync must run only a deferred sync and launch it exactly once');
    }
    for (const name of ['onAddonResult', 'onAddonFinished']) {
        const b = body(name);
        if (!b || !/PumpPendingLibrarySync\(\)/.test(b)) {
            err(`AccountSyncCoordinator.${name} does not pump a deferred library sync — a launch that deferred it would never run it`);
        }
    }
    const addonResult = body('onAddonResult');
    const libraryResult = body('onLibraryResult');
    if (!addonResult || !/m\.pendingLibrarySync\s*=\s*false/.test(addonResult) || !libraryResult || !/m\.pendingLibrarySync\s*=\s*false/.test(libraryResult)) {
        err('AccountSyncCoordinator must clear any deferred library sync when the account session is revoked');
    }
    const revoked = scene.match(/sub HandleRevokedSession\(\)[\s\S]*?\nend sub/);
    if (!revoked || !/callFunc\("CancelPendingLibrarySync"\)/.test(revoked[0])) {
        err('MainScene.HandleRevokedSession must cancel a library pull deferred by another coordinator before dropping the account session');
    }
    return ok;
}

// TEMPORARY, like the component it guards. The risk this pins is not that the
// spike stops running but that it stops being worth reading. The codec names it
// asks about are the SERVER's ffprobe `stream.codec` strings, because those are
// what the converter compares by exact string. Roku PRINTS different names for
// some of them (its own docs list "mpeg4 avc" for H.264), and "correcting" the
// candidate list to Roku's vocabulary would make every hinted request miss the
// server's match while looking perfectly correct. Equally, dropping the raw
// reply would hide the only place a rejected name's supported-list appears.
function checkDeviceCapContract() {
    const fs = require('fs');
    const read = (f) => fs.readFileSync(path.join(projectRoot, f), 'utf8');
    const code = (src) => src.split('\n').map(line => line.split("'")[0]).join('\n');
    const xml = read('components/DeviceCapTask.xml');
    const raw = read('components/DeviceCapTask.brs');
    const task = code(raw);
    const probe = code(read('source/util/CodecProbe.brs'));
    const settings = code(read('components/SettingsScreen.brs'));
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    const body = (src, name) => {
        const start = new RegExp(`^[ \\t]*(?:public\\s+|private\\s+|override\\s+)*(?:sub|function)\\s+${name}\\s*\\(`, 'm').exec(src);
        if (!start) return null;
        const rest = src.slice(start.index);
        const end = rest.slice(1).search(/^[ \t]*end\s+(?:sub|function)\b/m);
        return end === -1 ? rest : rest.slice(0, end + 1);
    };

    if (!/extends="Task"/.test(xml)) {
        err('DeviceCapTask.xml does not extend Task — roDeviceInfo is Task-only, so a probe written as a plain Group would fail for a reason unrelated to the codec question');
    }
    if (!/<script[^>]*uri="pkg:\/source\/util\/CodecProbe.brs"/.test(xml)) {
        err('DeviceCapTask.xml does not include source/util/CodecProbe.brs — components do not share function scope, so CodecVideoCandidates() would be a bare-global lookup that dies at runtime, not at load');
    }

    // The codec families the plan turns on. h264/aac/mp3 are the server's current
    // defaults and must always be asked about; hevc is the whole reason this
    // exists; the Dolby pair is the audio headroom.
    for (const name of ['h264', 'hevc']) {
        if (!new RegExp(`codec:\\s*"${name}"`).test(probe)) {
            err(`CodecProbe.brs no longer asks about video "${name}" — a plan that cannot see it cannot advertise it, and (for h264) a hint list missing it would evict the default and force H.264 to be re-encoded`);
        }
    }
    for (const name of ['aac', 'mp3', 'ac3', 'eac3']) {
        if (!new RegExp(`codec:\\s*"${name}"`).test(probe)) {
            err(`CodecProbe.brs no longer asks about audio "${name}" — this is the audio pass-through headroom the plan is about`);
        }
    }
    if (/codec:\s*"mpeg4 avc"/.test(probe)) {
        err('CodecProbe.brs gained "mpeg4 avc" as a candidate — that is the name Roku PRINTS in its reply, not an ffprobe `stream.codec` value the server matches, so the answer could not be put into a request. Ask "h264" and read the reply\'s supported list instead.');
    }

    // The raw reply is the whole point: a codec name the device does not know is
    // visible only through the supported list Roku returns alongside a rejection.
    if (!/FormatJson\s*\(/.test(task)) {
        err('DeviceCapTask.brs no longer keeps the raw FormatJson reply — the naming question this exists to answer is only visible in the list returned with a rejection');
    }
    // Read-only: it reports, it does not fetch or write.
    if (!/CreateObject\(\s*"roDeviceInfo"\s*\)/.test(task)) {
        err('DeviceCapTask.brs no longer reads roDeviceInfo — it is not a capability probe without it');
    }
    if (/roUrlTransfer|roFileSystem|AsyncTask_Launch|roRegistry/.test(task)) {
        err('DeviceCapTask.brs reaches for the network, the filesystem, a task launch or the registry — it is a read-only roDeviceInfo probe and must stay one');
    }

    if (!/action\s*=\s*"devicecap"/.test(settings) || !/RunDeviceCap\(\)/.test(settings)) {
        err('SettingsScreen.brs never dispatches the devicecap row to RunDeviceCap() — the row would appear and do nothing');
    }
    if (!/AsyncTask_Launch\([^\n]*"DeviceCapTask"/.test(settings)) {
        err('SettingsScreen.brs does not launch DeviceCapTask through AsyncTask_Launch — the component would never run');
    }
    const cancel = body(settings, 'CancelDeviceCap');
    if (!cancel) {
        err('SettingsScreen.brs has no CancelDeviceCap() — a run left going when the screen exits is never stopped');
    } else if (!/AsyncTask_Reap\(task,\s*m\.top,\s*true\)/.test(cancel)) {
        err('SettingsScreen.brs CancelDeviceCap() does not reap with STOP (AsyncTask_Reap(task, m.top, true)) — removing a running Task node does not kill its worker thread (AsyncTask.bs says so explicitly), so a probe sweep keeps running against a screen nobody is watching');
    }
    if (!/TEMPORARY/.test(raw) || !/TEMPORARY/.test(read('components/SettingsScreen.brs'))) {
        err('DeviceCapTask.brs or SettingsScreen.brs has lost its TEMPORARY marker — scaffolding that stops announcing itself tends to stay');
    }
    return ok;
}

// The codec-hint plumbing that no interpreter test can see end to end: the
// profile is built in a Task component and consumed in a store, and the suite
// flattens every script into one program, so a cross-file call resolves there
// whether or not the component's XML includes the script on the device. That
// gap is the whole reason this exists — a hint list that dies as an unresolved
// global on the device passes every unit test.
//
// The pure half (which codecs are advertised, at what channel cap) is covered by
// tests/codechints.test.brs; these checks are about the WIRING and the URL SHAPE
// between the two halves, and about the two rules that would silently invert the
// feature if a later edit dropped them: the intersection with the transport flag,
// and the server's floors surviving the replacement list.

// TEMPORARY, like the component it guards. The risk this pins is not that the
// spike stops running but that it stops being worth reading. The codec names it
// asks about are the SERVER's ffprobe `stream.codec` strings, because those are
// what the converter compares by exact string. Roku PRINTS different names for
// some of them (its own docs list "mpeg4 avc" for H.264), and "correcting" the
// candidate list to Roku's vocabulary would make every hinted request miss the
// server's match while looking perfectly correct. Equally, dropping the raw
// reply would hide the only place a rejected name's supported-list appears.
function checkDeviceCapContract() {
    const fs = require('fs');
    const read = (f) => fs.readFileSync(path.join(projectRoot, f), 'utf8');
    const code = (src) => src.split('\n').map(line => line.split("'")[0]).join('\n');
    const xml = read('components/DeviceCapTask.xml');
    const raw = read('components/DeviceCapTask.brs');
    const task = code(raw);
    const probe = code(read('source/util/CodecProbe.brs'));
    const settings = code(read('components/SettingsScreen.brs'));
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    const body = (src, name) => {
        const start = new RegExp(`^[ \\t]*(?:public\\s+|private\\s+|override\\s+)*(?:sub|function)\\s+${name}\\s*\\(`, 'm').exec(src);
        if (!start) return null;
        const rest = src.slice(start.index);
        const end = rest.slice(1).search(/^[ \t]*end\s+(?:sub|function)\b/m);
        return end === -1 ? rest : rest.slice(0, end + 1);
    };

    if (!/extends="Task"/.test(xml)) {
        err('DeviceCapTask.xml does not extend Task — roDeviceInfo is Task-only, so a probe written as a plain Group would fail for a reason unrelated to the codec question');
    }
    if (!/<script[^>]*uri="pkg:\/source\/util\/CodecProbe.brs"/.test(xml)) {
        err('DeviceCapTask.xml does not include source/util/CodecProbe.brs — components do not share function scope, so CodecVideoCandidates() would be a bare-global lookup that dies at runtime, not at load');
    }

    // The codec families the plan turns on. h264/aac/mp3 are the server's current
    // defaults and must always be asked about; hevc is the whole reason this
    // exists; the Dolby pair is the audio headroom.
    for (const name of ['h264', 'hevc']) {
        if (!new RegExp(`codec:\\s*"${name}"`).test(probe)) {
            err(`CodecProbe.brs no longer asks about video "${name}" — a plan that cannot see it cannot advertise it, and (for h264) a hint list missing it would evict the default and force H.264 to be re-encoded`);
        }
    }
    for (const name of ['aac', 'mp3', 'ac3', 'eac3']) {
        if (!new RegExp(`codec:\\s*"${name}"`).test(probe)) {
            err(`CodecProbe.brs no longer asks about audio "${name}" — this is the audio pass-through headroom the plan is about`);
        }
    }
    if (/codec:\s*"mpeg4 avc"/.test(probe)) {
        err('CodecProbe.brs gained "mpeg4 avc" as a candidate — that is the name Roku PRINTS in its reply, not an ffprobe `stream.codec` value the server matches, so the answer could not be put into a request. Ask "h264" and read the reply\'s supported list instead.');
    }

    // The raw reply is the whole point: a codec name the device does not know is
    // visible only through the supported list Roku returns alongside a rejection.
    if (!/FormatJson\s*\(/.test(task)) {
        err('DeviceCapTask.brs no longer keeps the raw FormatJson reply — the naming question this exists to answer is only visible in the list returned with a rejection');
    }
    // Read-only: it reports, it does not fetch or write.
    if (!/CreateObject\(\s*"roDeviceInfo"\s*\)/.test(task)) {
        err('DeviceCapTask.brs no longer reads roDeviceInfo — it is not a capability probe without it');
    }
    if (/roUrlTransfer|roFileSystem|AsyncTask_Launch|roRegistry/.test(task)) {
        err('DeviceCapTask.brs reaches for the network, the filesystem, a task launch or the registry — it is a read-only roDeviceInfo probe and must stay one');
    }

    if (!/action\s*=\s*"devicecap"/.test(settings) || !/RunDeviceCap\(\)/.test(settings)) {
        err('SettingsScreen.brs never dispatches the devicecap row to RunDeviceCap() — the row would appear and do nothing');
    }
    if (!/AsyncTask_Launch\([^\n]*"DeviceCapTask"/.test(settings)) {
        err('SettingsScreen.brs does not launch DeviceCapTask through AsyncTask_Launch — the component would never run');
    }
    const cancel = body(settings, 'CancelDeviceCap');
    if (!cancel) {
        err('SettingsScreen.brs has no CancelDeviceCap() — a run left going when the screen exits is never stopped');
    } else if (!/AsyncTask_Reap\(task,\s*m\.top,\s*true\)/.test(cancel)) {
        err('SettingsScreen.brs CancelDeviceCap() does not reap with STOP (AsyncTask_Reap(task, m.top, true)) — removing a running Task node does not kill its worker thread (AsyncTask.bs says so explicitly), so a probe sweep keeps running against a screen nobody is watching');
    }
    if (!/TEMPORARY/.test(raw) || !/TEMPORARY/.test(read('components/SettingsScreen.brs'))) {
        err('DeviceCapTask.brs or SettingsScreen.brs has lost its TEMPORARY marker — scaffolding that stops announcing itself tends to stay');
    }
    return ok;
}

// The codec-hint plumbing that no interpreter test can see end to end: the
// profile is built in a Task component and consumed in a store, and the suite
// flattens every script into one program, so a cross-file call resolves there
// whether or not the component's XML includes the script on the device. That
// gap is the whole reason this exists — a hint list that dies as an unresolved
// global on the device passes every unit test.
//
// The pure half (which codecs are advertised, at what channel cap) is covered by
// tests/codechints.test.brs; these checks are about the WIRING and the URL SHAPE
// between the two halves, and about the two rules that would silently invert the
// feature if a later edit dropped them: the intersection with the transport flag,
// and the server's floors surviving the replacement list.
function checkCodecPlaybackContract() {
    const fs = require('fs');
    const read = (f) => fs.readFileSync(path.join(projectRoot, f), 'utf8');
    const code = (src) => src.split('\n').map(line => line.split("'")[0]).join('\n');
    const taskXml = read('components/StreamResolveTask.xml');
    const taskBrs = code(read('components/StreamResolveTask.brs'));
    const playerBrs = code(read('components/PlayerScreen.brs'));
    const store = code(read('source/stores/PlaybackStore.bs'));
    const probe = code(read('source/util/CodecProbe.brs'));
    // The UI text now lives in the table rather than in the screen, so the
    // copy checks below can read either — the table is where the migrated
    // strings are, the screen is where a future literal would be.
    const book = read('source/util/texts.json');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    const body = (src, name) => {
        const start = new RegExp(`^[ \\t]*(?:public\\s+|private\\s+|override\\s+)*(?:sub|function)\\s+${name}\\s*\\(`, 'm').exec(src);
        if (!start) return null;
        const rest = src.slice(start.index);
        const end = rest.slice(1).search(/^[ \t]*end\s+(?:sub|function)\b/m);
        return end === -1 ? rest : rest.slice(0, end + 1);
    };

    // 1. The XML include. StreamResolveTask.brs calls CodecVideoFloor() and
    //    friends, which live in CodecProbe.brs; components do not share function
    //    scope, so on the device those are bare-global lookups that fail at
    //    runtime. The suite cannot catch it — it concatenates the scripts into
    //    one program, so the call resolves there and only dies on the device.
    if (!/<script[^>]*uri="pkg:\/source\/util\/CodecProbe\.brs"/.test(taskXml)) {
        err('StreamResolveTask.xml does not include source/util/CodecProbe.brs — components do not share function scope, so ResolveCodecProfile building its lists from CodecVideoFloor()/CodecHints() would be a bare-global lookup that dies at runtime, not at load');
    }

    // 2. The task profiles the device and hands the profile to the resolve. A
    //    profile built and then not passed is a probe whose answer is discarded,
    //    which reads as "the hints did nothing" on every device.
    if (!/profile\s*=\s*ResolveCodecProfile\s*\(/.test(taskBrs)) {
        err('StreamResolveTask.brs resolve() never builds a codec profile — the advertise list is the whole feature, and without it the URL falls back to the server defaults this work exists to improve on');
    }
    if (!/ResolvePlayback\([^)]*\bprofile\b\s*\)/.test(taskBrs)) {
        err('StreamResolveTask.brs resolve() does not pass the profile to ResolvePlayback — the profile is built and then dropped, so the hint route is never taken');
    }

    // 3. The fallback URL has to reach the wait, and the URL handed over has to
    //    be the one the wait settled on. Skip either and the 404 fallback is
    //    decoration: the player keeps the direct route the server just refused.
    if (!/WaitForPlaylist\(store,\s*resolved\.url,\s*resolved\.fallbackUrl\)/.test(taskBrs)) {
        err('StreamResolveTask.brs resolve() does not pass the fallback URL to WaitForPlaylist — a server without /hlsv2 would 404 on every attempt with nothing to fall back to');
    }
    if (!/resolved\.url\s*=\s*resolved\.probe\.url/.test(taskBrs)) {
        err('StreamResolveTask.brs resolve() keeps its own copy of the URL — when the probe falls back, the Video node is still handed the direct /hlsv2 route the server refused');
    }
    const wait = body(taskBrs, 'WaitForPlaylist');
    if (wait && !/status\s*=\s*404/.test(wait)) {
        err('StreamResolveTask.brs WaitForPlaylist no longer advances on a 404 — the one response that means "no such route" is treated as a cold engine and retried forever');
    }

    // 4. The URL shape. /hlsv2 is the only route that reads the hints (the
    //    /hls.m3u8 bridge overwrites the query and hardcodes maxAudioChannels 2),
    //    master.m3u8 is the converter's master, and the three hint keys have to
    //    be on it.
    const codecUrl = body(store, 'CodecPlaybackUrl');
    if (!codecUrl) {
        err('PlaybackStore.bs has no CodecPlaybackUrl() — the hinted route is gone and every play is back on the server defaults');
    } else {
        if (!/"\/hlsv2\/"/.test(codecUrl) || !/\/master\.m3u8/.test(codecUrl)) {
            err('PlaybackStore.bs CodecPlaybackUrl does not build a /hlsv2/{id}/master.m3u8 URL — the hints only exist on the HLS2 router\'s own routes, and the master is the playlist the Video node wants');
        }
        if (!/"mediaURL=/.test(codecUrl)) {
            err('PlaybackStore.bs CodecPlaybackUrl sends no mediaURL — the converter has no source to fetch, and every request would answer 500 instead of a playlist');
        }
        if (!/"maxAudioChannels="/.test(codecUrl)) {
            err('PlaybackStore.bs CodecPlaybackUrl sends no maxAudioChannels — the server falls back to no cap of ours, and a 5.1 Dolby track is copied or downmixed by a number nobody set');
        }
        // REPEATED keys, one per codec. The server keeps `req.query.videoCodecs`
        // as an array only when the key repeats; a single comma-joined value
        // arrives as one string and is in no codec's exact-match list, so it
        // advertises nothing while looking complete.
        if (!/for\s+each\s+codec\s+in\s+videoCodecs/.test(codecUrl) || !/parts\.Push\("videoCodecs="\s*\+\s*m\.transport\.EncodeQueryValue\(codec\)\)/.test(codecUrl)) {
            err('PlaybackStore.bs CodecPlaybackUrl does not push one videoCodecs= key per codec — a single comma-joined value arrives as one string the server cannot match, so it advertises nothing');
        }
        if (!/for\s+each\s+codec\s+in\s+audioCodecs/.test(codecUrl) || !/parts\.Push\("audioCodecs="\s*\+\s*m\.transport\.EncodeQueryValue\(codec\)\)/.test(codecUrl)) {
            err('PlaybackStore.bs CodecPlaybackUrl does not push one audioCodecs= key per codec — a single comma-joined value arrives as one string the server cannot match, so it advertises nothing');
        }
        // An empty converter id would build "/hlsv2//master.m3u8": a non-empty
        // string that reads like a URL and requests a nameless converter.
        if (!/converterId = ""\s*then\s+return ""/.test(codecUrl)) {
            err('PlaybackStore.bs CodecPlaybackUrl does not refuse an empty converter id — an empty fingerprint builds "/hlsv2//master.m3u8", which reads as a URL and asks for a nameless converter');
        }
    }

    // 5. The profile is optional, and its absence keeps the legacy URL — the
    //    path the tests and any un-probed caller take. That URL is also the
    //    fallback, which only exists while PlaybackUrl is still built.
    const resolve = body(store, 'ResolvePlayback');
    if (!resolve) {
        err('PlaybackStore.bs has no ResolvePlayback()');
    } else {
        if (!/result\.fallbackUrl\s*=\s*m\.PlaybackUrl\(/.test(resolve)) {
            err('PlaybackStore.bs ResolvePlayback no longer keeps the /hls.m3u8 URL as the fallback — a server without /hlsv2 then has no route at all');
        }
        if (!/function\s+ResolvePlayback\([^)]*\bprofile\b/.test(store)) {
            err('PlaybackStore.bs ResolvePlayback takes no profile — the device answer has nowhere to enter the store');
        }
    }

    // 6. The converter cache key has to change with the hints. The server builds
    //    a converter only when the id is new, so a shared id serves the first
    //    profile's converter and silently ignores the second's hints.
    const converterId = body(store, 'ConverterId');
    if (converterId && !/profile\.fingerprint/.test(converterId)) {
        err('PlaybackStore.bs ConverterId ignores the profile fingerprint — the server caches by id, so two hint sets sharing an id silently serve the first set\'s converter');
    }
    const profiler = body(taskBrs, 'ResolveCodecProfile');
    if (profiler && !/profile\.fingerprint\s*=\s*CodecFingerprint\(videoCodecs,\s*audioCodecs,\s*channels\)/.test(profiler)) {
        err('StreamResolveTask.brs ResolveCodecProfile fingerprints the wrong values — the id must hash the FINAL lists and the channel cap, or a changed device shares the old converter');
    }

    // 7. The two rules that invert the feature if dropped. The advertised list
    //    is an intersection (device answer AND transport flag), and the server's
    //    defaults are its floor, because an advertised list REPLACES them.
    const hints = body(probe, 'CodecHints');
    if (hints && !/candidate\.hls\s+and\s+accepted/.test(hints)) {
        err('CodecProbe.brs CodecHints no longer requires candidate.hls — the transport half of the intersection is gone, and a device answering true for AV1/VP9/DTS would offer a player codecs it cannot open');
    }
    const videoFloor = body(probe, 'CodecVideoFloor');
    if (videoFloor && !/"h264"/.test(videoFloor)) {
        err('CodecProbe.brs CodecVideoFloor no longer names h264 — dropping the server\'s default from a list that REPLACES the defaults turns the one sure stream-copy into a re-encode');
    }
    const audioFloor = body(probe, 'CodecAudioFloor');
    if (audioFloor && (!/"aac"/.test(audioFloor) || !/"mp3"/.test(audioFloor))) {
        err('CodecProbe.brs CodecAudioFloor no longer names both aac and mp3 — dropping a server default from a list that REPLACES the defaults forces that codec to re-encode');
    }

    // 8. The audio list is a SWITCH, and the switch is off by default.
    //
    //    Two switches, two different questions. Passthrough (filter 1) is what
    //    the attached sound system takes: the server copies the audio and the
    //    receiver decodes the bitstream. Transmux (filter 0) is what the Roku
    //    itself can decode: the server copies the audio and the Roku decodes
    //    it. Both answers are the platform's accept rule — a stream whose
    //    audio is in either set is played, and one that is not comes back as
    //    "not playable on this device" — so the lists are asked of the
    //    platform and not invented here.
    //
    //    The failure is silence, not an error, so no log and no unit test
    //    would notice the default drifting; only this pin does.
    if (profiler) {
        if (!/audioCodecs\s*=\s*CodecAudioFloor\(\)/.test(profiler)) {
            err('StreamResolveTask.brs ResolveCodecProfile no longer starts from CodecAudioFloor() — the switches are off by default, and the floor is what the /hls.m3u8 bridge sends');
        }
        if (!/channels\s*=\s*2\b/.test(profiler)) {
            err('StreamResolveTask.brs ResolveCodecProfile no longer starts from a channel cap of 2 — with the switches off the request must be the one the /hls.m3u8 bridge sends');
        }
        if (!/if\s+m\.top\.audioPassthrough\s+then/.test(profiler)) {
            err('StreamResolveTask.brs ResolveCodecProfile does not read the audioPassthrough switch — the setting would never reach the request');
        }
        if (!/if\s+m\.top\.audioTransmux\s+then/.test(profiler)) {
            err('StreamResolveTask.brs ResolveCodecProfile does not read the audioTransmux switch — the setting would never reach the request');
        }
        if (!/CodecDolbyCandidates\(\)/.test(profiler)) {
            err('StreamResolveTask.brs ResolveCodecProfile does not ask which Dolby codecs it may offer — the switches would have nothing to offer');
        }
        if (!/ResolveProbeFilter\(di,\s*candidate,\s*1\)/.test(profiler)) {
            err('StreamResolveTask.brs ResolveCodecProfile does not probe the attached sound system — the passthrough switch would offer the floor and nothing else');
        }
        if (!/ResolveProbeFilter\(di,\s*candidate,\s*0\)/.test(profiler)) {
            err('StreamResolveTask.brs ResolveCodecProfile does not probe the Roku itself — the transmux switch would offer the floor and nothing else');
        }
        if (!/accepted\.Push\(candidate\.codec\)/.test(profiler)) {
            err('StreamResolveTask.brs ResolveCodecProfile does not collect the probe answers — the advertised list would be the floor whatever the device claims');
        }
        if (!/CanDecodeAudio\(\{[^}]*passthru:/.test(taskBrs)) {
            err('StreamResolveTask.brs does not send a passthru filter — the plain probe answers for the Roku AND the attached HDMI device at once, which is not a question either switch can act on');
        }
        if (!/CodecAudioHints\(/.test(profiler)) {
            err('StreamResolveTask.brs ResolveCodecProfile does not build the list with CodecAudioHints() — the floor must survive the addition, or the server evicts its own defaults and re-encodes aac and mp3');
        }
    }

    // 9. The switches have to reach the task. The screen owns the store and
    //    the Task cannot ask it, so the values are handed over as fields — and
    //    a field the task does not declare is a field the task never reads.
    if (!/<field\s+id="audioPassthrough"\s+type="boolean"/.test(taskXml)) {
        err('StreamResolveTask.xml does not declare the audioPassthrough field — the screen hands the setting over as a field, and a task that does not declare it never sees it');
    }
    if (!/<field\s+id="audioTransmux"\s+type="boolean"/.test(taskXml)) {
        err('StreamResolveTask.xml does not declare the audioTransmux field — the screen hands the setting over as a field, and a task that does not declare it never sees it');
    }
    if (!/audioPassthrough\s*:/.test(playerBrs) || !/audioTransmux\s*:/.test(playerBrs)) {
        err('PlayerScreen.brs does not pass both audio settings to StreamResolveTask — they are read from the store and would never reach the request');
    }
    if (!/SettingsGetAudioPassthrough/.test(playerBrs) || !/SettingsGetAudioTransmux/.test(playerBrs)) {
        err('PlayerScreen.brs does not read both audio settings — the task would always get the defaults');
    }

    // 10. The Settings rows show which codecs each switch would offer, so the
    //     screen has to ask the device itself. roDeviceInfo is Task-only, so
    //     the screen cannot ask and the probe needs a task of its own; a row
    //     that showed a stale or empty set would be worse than one that shows
    //     nothing. The task answers BOTH questions, because the two rows have
    //     to be told apart and one probe of the union cannot do that.
    const settingsScreen = read('components/SettingsScreen.brs');
    if (!/name="AudioCapTask"/.test(read('components/AudioCapTask.xml'))) {
        err('components/AudioCapTask.xml is missing — the Settings rows cannot learn which codecs the device takes, and the values they show would be a guess');
    }
    if (!/AsyncTask_Launch\([^\n]*"AudioCapTask"/.test(settingsScreen)) {
        err('SettingsScreen.brs does not launch AudioCapTask — the rows would never learn the device\'s codecs');
    }
    const audioCap = read('components/AudioCapTask.brs');
    if (!/CanDecodeAudio\(\{[^}]*passthru:/.test(audioCap)) {
        err('AudioCapTask.brs does not send a passthru filter — the plain probe answers for the Roku AND the attached HDMI device at once, and the two rows have to be told apart');
    }
    if (!/CapProbeFilter\(di,\s*candidate,\s*1\)/.test(audioCap) || !/CapProbeFilter\(di,\s*candidate,\s*0\)/.test(audioCap)) {
        err('AudioCapTask.brs does not ask both questions — 1 is the attached HDMI device and 0 is the Roku itself, and the two rows have to be told apart');
    }

    // 11. The side panel is where the two options say what they do, and the
    //     transmux one has to say it is experimental. A panel that is not
    //     wired to the focused row would show the wrong text for the row the
    //     cursor is on, which is worse than no panel at all.
    if (!/id="infoPanel"/.test(read('components/SettingsScreen.xml'))) {
        err('SettingsScreen.xml has no infoPanel — the side panel that explains the selected setting is gone');
    }
    if (!/ObserveField\("rowItemFocused",\s*"onRowFocused"\)/.test(settingsScreen)) {
        err('SettingsScreen.brs does not watch the focused row — the side panel would keep explaining the row the cursor left');
    }
    if (!/Experimental/.test(settingsScreen) && !/Experimental/.test(book)) {
        err('SettingsScreen.brs does not say the transmux option is experimental — it is untested on this kind of device, and the panel is the only place that can say so');
    }

    return ok;
}

// TEMPORARY, like the component it guards. NetDiagTask exists to locate the
// intermittent outbound-connect failures (status -7): DNS, the radio, or
// concurrency. Once that is known the component, the Settings row and this
// contract all go together. The first check is the one that matters:
// roUrlTransfer is Task-only, so a probe written as a plain Group would fail for
// a reason unrelated to the network and would send the whole investigation the
// wrong way.
function checkNetDiagContract() {
    const fs = require('fs');
    const read = (f) => fs.readFileSync(path.join(projectRoot, f), 'utf8');
    const code = (src) => src.split('\n').map(line => line.split("'")[0]).join('\n');
    const xml = read('components/NetDiagTask.xml');
    const raw = read('components/NetDiagTask.brs');
    const task = code(raw);
    const settings = code(read('components/SettingsScreen.brs'));
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    if (!/extends="Task"/.test(xml)) {
        err('NetDiagTask.xml does not extend Task — roUrlTransfer is Task-only, so every probe would fail for a reason unrelated to the network question');
    }

    // The ladder is a control experiment: each rung changes exactly one thing
    // from the one before it. Losing a rung does not just lose a data point, it
    // removes the control the adjacent rungs are read against.
    const tags = ['A', 'B', 'C', 'D', 'E'].filter(t => new RegExp(`tag:\\s*"${t}"`).test(task));
    if (tags.length !== 5) {
        err(`NetDiagTask.brs defines only probes ${tags.join(', ')} — the experiment is the A/B/C/D/E ladder, and dropping one removes the control it depends on`);
    }

    // B must be an IP literal with no DNS in the path; C the same request by
    // hostname. B vs C is the DNS comparison.
    if (!/tag:\s*"B"[^\n]*http:\/\/1\.1\.1\.1\//.test(task)) {
        err('NetDiagTask.brs probe B is not the bare http://1.1.1.1/ IP literal — without a DNS-free internet probe, B vs C cannot isolate name resolution');
    }
    if (!/tag:\s*"C"[^\n]*httpforever\.com/.test(task)) {
        err('NetDiagTask.brs probe C is not the httpforever.com hostname request — C is the DNS-using half of the B/C pair');
    }

    // D and E differ by exactly one call. If E stops asking for the bundle the
    // run silently becomes two copies of D, and "both failed" would be read as
    // evidence about certificates when certificates were never in the test.
    if (!/tag:\s*"E"[^\n]*certs:\s*true/.test(task)) {
        err('NetDiagTask.brs probe E does not set certs: true — without it E is an identical copy of D and the run cannot say anything about the CA bundle');
    }
    if (!/tag:\s*"D"[^\n]*certs:\s*false/.test(task)) {
        err('NetDiagTask.brs probe D sets certs — D must be the uncertificated control or there is nothing to compare E against');
    }

    // DNS is measured on its own, not only through HTTP: roSocketAddress does the
    // same lookup roUrlTransfer does, so a flaky result here is the resolver
    // failing before any socket opens.
    if (!/roSocketAddress/.test(task) || !/IsAddressValid\(\)/.test(task)) {
        err('NetDiagTask.brs no longer resolves hostnames through roSocketAddress/IsAddressValid — DNS would only be implied by HTTP failures instead of measured');
    }

    // Device facts decide the radio hypothesis and name the resolver in use.
    if (!/GetConnectionInfo\(\)/.test(task) || !/GetConnectionType\(\)/.test(task)) {
        err('NetDiagTask.brs no longer reads GetConnectionType()/GetConnectionInfo() — the Wi-Fi signal and the DNS servers actually in use would be invisible');
    }

    // The concurrency burst is the only section that puts several transfers in
    // flight at once, which is the pattern the production failures cluster in.
    if (!/RunBurst\(/.test(task)) {
        err('NetDiagTask.brs no longer issues a concurrency burst — a contention cause could not be distinguished from a DNS one');
    }

    // The three concurrency experiments escalate: the soak removes concurrency
    // entirely, the sweep finds the size at which it breaks, and the version
    // comparison tests Roku's documented "HTTP/2 sharing wants one thread"
    // constraint. Dropping any one leaves a plausible alternative unmeasured.
    if (!/report\.soak\s*=\s*RunSoak\(/.test(task)) {
        err('NetDiagTask.brs no longer runs the sequential soak — a link that drops under NO load would look identical to a concurrency problem');
    }
    if (!/report\.sweep\s*=\s*RunBurstSweep\(/.test(task)) {
        err('NetDiagTask.brs no longer sweeps burst sizes — the concurrency threshold would be a guess instead of a measurement');
    }
    if (!/report\.versions\s*=\s*RunHttpVersionComparison\(/.test(task) || !/SetHttpVersion\(/.test(task)) {
        err('NetDiagTask.brs no longer compares HTTP versions — the documented HTTP/2 same-thread sharing constraint would go untested');
    } else if (!/versions\s*=\s*\[[^\]]*"AUTO"[^\]]*"http2"[^\]]*"1\.1"/.test(task)) {
        err('NetDiagTask.brs HTTP-version comparison does not cover both "http2" and "1.1" — one of the two mechanisms would be unmeasured');
    } else if (!/h1Record\s*=\s*FindVersion\(/.test(task) || !/h1Record\.ok\s*=\s*h1Record\.count/.test(task)) {
        err('NetDiagTask.brs no longer interprets the 1.1 result — the wired run that identified the root cause printed AUTO 5/6, http2 5/6, 1.1 6/6 and the verdict said nothing about it, because the comparison only ever looked at AUTO vs http2');
    }

    // The verdict is what a reader acts on, and it has now been wrong twice in
    // ways that pointed real debugging effort at the wrong layer.
    //
    // `connected` was `status <> 0`, which counts CURLE_COULDNT_CONNECT (-7) as
    // connected. So a run where BOTH the IP-literal and hostname probes returned
    // -7 printed "Both IP and hostname reach the internet" and the DNS question
    // was closed on evidence that never tested it. A real HTTP response code is
    // always >= 100, so the comparison has to be `> 0`.
    if (/outcome\.connected\s*=\s*outcome\.status\s*<>\s*0/.test(task)) {
        err('NetDiagTask.brs computes connected as `status <> 0` — a negative status is a connect that never opened, so a -7 reads as connected and the DNS verdict closes itself on a probe that failed');
    }
    if (!/NetDiagConnected\(outcome\.status\)/.test(task) || !/function\s+NetDiagConnected[\s\S]*?return\s+status\s*>\s*0/.test(task)) {
        err('NetDiagTask.brs does not compute connected as `status > 0` via NetDiagConnected — reachability has to mean a response arrived, and a redirect answered on the way to a 2xx still counts');
    }
    if (!/neither IP nor hostname connected/i.test(task)) {
        err('NetDiagTask.brs has no both-red branch for the B/C pair — when neither the IP literal nor the hostname connects, that says nothing about DNS and must not be reported as if it did');
    }

    // A CA bundle is validated AFTER the TCP connect and TLS handshake. A -7 is
    // the connect refused before either, so "the bundle fixes HTTPS" cannot be
    // concluded from a rung that never connected — and following it would add
    // SetCertificatesFile to Transport for a connection that was never made.
    if (!/dTls\s*=\s*d\.status\s*>\s*0/.test(task) || !/eTls\s*=\s*e\.status\s*>\s*0/.test(task)) {
        err('NetDiagTask.brs does not gate the D/E certificate comparison on whether either rung got a response — a connect-level -7 cannot be a certificate result, so the comparison must report inconclusive instead of blaming or exonerating the bundle');
    }
    if (/CA bundle fixes HTTPS -> add SetCertificatesFile/.test(task)) {
        err('NetDiagTask.brs still emits an unconditional "CA bundle fixes HTTPS -> add SetCertificatesFile to Transport" — that fired off a rung which never connected, and acting on it adds a stall to every request for a connect that failed before TLS');
    }

    // The dev line printed all-empty on the first device run because it guessed
    // key names and values. The raw dump is what makes that impossible to
    // repeat silently, so it is the thing worth guarding.
    if (!/FormatJson\(info\)/.test(task)) {
        err('NetDiagTask.brs no longer dumps GetConnectionInfo() raw — the dev line silently printed all-empty on device once already');
    }

    // BoxStr stringifies platform values. A bare `"" + value` is a Type Mismatch
    // (&h18) on the booleans GetLinkStatus/GetInternetStatus/HasFeature return —
    // it crashed the whole task on device before a single probe ran, which is a
    // deploy spent to learn what this check now catches for free.
    if (!/Boolean/.test(task) || /return "" \+ value/.test(task)) {
        err('NetDiagTask.brs BoxStr no longer special-cases booleans (or reverted to `"" + value`) — GetLinkStatus/GetInternetStatus/HasFeature return booleans and that concat is a hard &h18');
    }
    if (!/CABundlePath\(\)/.test(task) || !/common:\/certs\/ca-bundle\.crt/.test(task)) {
        err('NetDiagTask.brs does not name common:/certs/ca-bundle.crt — Roku documents that path for public CAs, and probing anything else proves nothing about the documented fix');
    }
    const certAt = task.search(/SetCertificatesFile\(/);
    const issueAt = task.search(/AsyncGetToString\(\)/);
    if (certAt === -1) {
        err('NetDiagTask.brs never calls SetCertificatesFile() — the one call under test is missing');
    } else if (issueAt !== -1 && certAt > issueAt) {
        err('NetDiagTask.brs calls SetCertificatesFile() after issuing the request — the docs require it before, and a late call measures the wrong thing');
    }

    // The threshold is inlined in SettingsScreen.brs because standard
    // BrightScript has no file-scope const; assert it is still a deliberate,
    // repeated gesture rather than a single accidental press.
    if (!/m\.testServerTaps\s*>=\s*(\d+)/.test(settings)) {
        err('SettingsScreen.brs no longer gates the diagnostics row on a tap count — the hidden row cannot be reached deliberately');
    } else if (Number(/m\.testServerTaps\s*>=\s*(\d+)/.exec(settings)[1]) < 3) {
        err('SettingsScreen.brs reveals diagnostics on too few taps — few enough to fire by accident on a row users are meant to press');
    }
    if (!/action\s*=\s*"netdiag"/.test(settings) || !/RunNetDiag\(\)/.test(settings)) {
        err('SettingsScreen.brs never dispatches the netdiag row to RunNetDiag() — the row appears and does nothing');
    }
    if (!/AsyncTask_Launch\([^\n]*"NetDiagTask"/.test(settings)) {
        err('SettingsScreen.brs does not launch NetDiagTask — the diagnostic exists but nothing starts it');
    }

    // Both files say TEMPORARY in their own header. Cheap, but this is scaffolding
    // that is easy to build on by accident once it is committed.
    if (!/TEMPORARY/.test(raw) || !/TEMPORARY/.test(read('components/SettingsScreen.brs'))) {
        err('NetDiagTask.brs or SettingsScreen.brs has lost its TEMPORARY marker — scaffolding that stops announcing itself tends to stay');
    }

    return ok;
}

function checkStreamResolveTaskContract() {
    const fs = require('fs');
    const read = (f) => fs.readFileSync(path.join(projectRoot, f), 'utf8');
    const code = (src) => src.split('\n').map(line => line.split("'")[0]).join('\n');
    const taskXml = read('components/StreamResolveTask.xml');
    const taskBrs = code(read('components/StreamResolveTask.brs'));
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    const body = (src, name) => {
        const start = new RegExp(`^[ \\t]*(?:public\\s+|private\\s+|override\\s+)*(?:sub|function)\\s+${name}\\s*\\(`, 'm').exec(src);
        if (!start) return null;
        const rest = src.slice(start.index);
        const end = rest.slice(1).search(/^[ \t]*end\s+(?:sub|function)\b/m);
        return end === -1 ? rest : rest.slice(0, end + 1);
    };

    // The whole readiness wait lives in a Task component, which the brs
    // interpreter never executes — Wait() there ABORTS the run and Ticks() does
    // not exist — so none of this is reachable by an interpreter test. These
    // checks are the only thing standing between a silent no-op and a fix that
    // reads as present. Every one of them is about the wait degenerating into
    // doing nothing while still looking correct.
    if (!/<field\s+id="result"\s+type="assocarray"[^>]*alwaysNotify="true"/.test(taskXml)) {
        err('StreamResolveTask.xml does not declare <field id="result" type="assocarray" ... alwaysNotify="true" /> — without it the screen never hears back');
    }

    const wait = body(taskBrs, 'WaitForPlaylist');
    if (!wait) {
        err('StreamResolveTask.brs has no WaitForPlaylist() — the readiness wait is gone, and the Video node is back to eating the cold-engine response itself');
        return ok;
    }

    // 1. NO CLOCK. The most expensive thing this file has ever contained was a
    //    clock reading: an earlier version bounded the wait with
    //    CreateObject("roDateTime").AsMilliseconds(), a method this codebase has
    //    never put on a device (the only two it does use are ToISOString() and
    //    GetYear()), and the device answered &hf4, member function not found.
    //    No interpreter test can catch a missing platform method, and the file is
    //    never executed by one, so refusing to use a clock here is the only
    //    defence there is. The bound is a count of attempts.
    const clock = /\broDateTime\b|\bTicks\s*\(|\bNowMs\b/.exec(taskBrs);
    if (clock) {
        err(`StreamResolveTask.brs references ${clock[0]} — the readiness wait is bounded by attempt count, and no platform clock is verified on this device (roDateTime.AsMilliseconds answered &hf4). A throw from one here shares resolve()'s catch and takes an already-resolved URL down with it`);
    }

    const interval = /Wait\(\s*(\d+)\s*,\s*invalid\s*\)/.exec(wait);
    if (!interval) {
        err('StreamResolveTask.brs WaitForPlaylist never pauses between attempts — a cold engine would be polled flat out');
    } else if (Number(interval[1]) < 1000) {
        err(`StreamResolveTask.brs WaitForPlaylist pauses ${interval[1]}ms between attempts — that is hammering a server that is still starting an engine`);
    }

    // 2. With no clock, attempts x (per-request timeout + interval) IS the
    //    ceiling — so the per-request timeout is now load-bearing, and it has to
    //    be a short one AND the one the probe actually passes. At Transport's
    //    default 15s, four attempts hold the player for over a minute, which is
    //    longer than the stall this whole mechanism exists to prevent.
    const store = read('source/stores/PlaybackStore.bs');
    const probeTimeout = /const\s+PROBE_TIMEOUT_MS\s*=\s*(\d+)/.exec(store);
    if (!probeTimeout) {
        err('PlaybackStore.bs has no PROBE_TIMEOUT_MS — without a probe-specific timeout the wait ceiling is attempts x the default 15s, over 90s of holding the player for a stream that may never start');
    } else {
        if (Number(probeTimeout[1]) > 8000) {
            err(`PlaybackStore.bs PROBE_TIMEOUT_MS is ${probeTimeout[1]}ms — a probe asks whether the server is up and the caller re-asks, so a request that can take this long is only delaying the next attempt`);
        }
        if (!/GetRaw\(url,\s*PROBE_TIMEOUT_MS\)/.test(store)) {
            err('PlaybackStore.bs ProbePlaylist does not pass PROBE_TIMEOUT_MS to GetRaw — the constant is declared but the probe still pays the default timeout');
        }
    }

    // 2. The retry must be a counted loop, not `while true`. A `while true`
    //    bounded only by a clock is unbounded to a reader, and to a future edit.
    const loop = /for\s+attempt\s*=\s*1\s+to\s+(\d+)/.exec(wait);
    if (!loop) {
        err('StreamResolveTask.brs WaitForPlaylist does not retry a counted number of times — an unbounded wait here is a render-thread-adjacent hang waiting for a bad edit');
    } else if (Number(loop[1]) < 2) {
        err(`StreamResolveTask.brs WaitForPlaylist tries ${loop[1]} time(s) — with one attempt the readiness wait is not a wait, it is the request that was always there`);
    }

    // 2b. The ceiling is attempts x probe timeout, plus the gaps BETWEEN them —
    //     which is one fewer than the attempt count, because the last attempt
    //     deliberately skips its sleep. That off-by-one is the whole reason this
    //     is computed rather than read off a constant: 4 x 8000 + 3 x 4000 is
    //     44s, and so was 6 x 4000 + 5 x 4000, which is how the probe timeout was
    //     raised to 8000 without lengthening the player's worst-case wait at all.
    //
    //     The three numbers involved live in two files and are independently
    //     editable, so pinning any one of them would pin today's arrangement
    //     rather than the property that matters. A future edit that moves either
    //     knob up without paying the other back down is the regression, whichever
    //     file it came through.
    const gapMs = interval ? Number(interval[1]) : 0;
    if (loop && probeTimeout && interval) {
        const ceiling = Number(loop[1]) * Number(probeTimeout[1]) + (Number(loop[1]) - 1) * gapMs;
        if (ceiling > 44000) {
            err(`the readiness wait can hold the player for ${ceiling}ms (${loop[1]} attempts x ${probeTimeout[1]}ms probe + ${Number(loop[1]) - 1} x ${gapMs}ms gap) — that ceiling is what this mechanism exists to cap, and it only stays capped while the attempt count and the probe timeout are moved together`);
        }
    }

    // 3. The pause has to be skipped on the final attempt. With no budget
    //    consulted mid-loop, an unconditional sleep costs a full interval of dead
    //    time after the loop has already decided to give up. Located by the line
    //    the sleep is on, since there are no constant names to find.
    const sleepLine = /^[ \t]*(.*Wait\(\s*\d+\s*,\s*invalid\s*\).*)$/m.exec(wait);
    if (sleepLine && !/if\s+attempt\s*<\s*\d+\s+then/.test(sleepLine[1])) {
        err('StreamResolveTask.brs WaitForPlaylist sleeps unconditionally — the final attempt then waits a whole interval after the loop has already decided to give up');
    }

    // 4. Handing over must not depend on the server having answered. If the give
    //    up path stopped returning a URL, the wait would have quietly become the
    //    thing that prevents playback instead of the thing that delays it.
    if (!/if\s+not\s+probe\.ok\s+then\s+probe\.gaveUp\s*=\s*true/.test(wait)) {
        err('StreamResolveTask.brs WaitForPlaylist does not mark gaveUp — "we stopped waiting" and "the server answered" would be indistinguishable in the record');
    }
    const resolveBody = body(taskBrs, 'resolve');
    if (!resolveBody) {
        err('StreamResolveTask.brs has no resolve() — the worker body is gone');
    } else {
        // 5. The probe is the diagnosis, so it has to be attached BEFORE the
        //    result is published, or it is never read by anyone.
        const probeAt = resolveBody.indexOf('resolved.probe =');
        const resultAt = resolveBody.indexOf('m.top.result =');
        if (probeAt === -1) {
            err('StreamResolveTask.brs resolve() never attaches a probe — "how long, and what did the server say" is the whole diagnosis when this is still wrong');
        } else if (resultAt === -1) {
            err('StreamResolveTask.brs resolve() never sets m.top.result — the screen would wait for a result that never lands');
        } else if (probeAt > resultAt) {
            err('StreamResolveTask.brs resolve() publishes the result before attaching the probe — the probe would never reach the screen');
        }
        if (!/store\.IsTorrent\(/.test(resolveBody)) {
            err('StreamResolveTask.brs resolve() probes unconditionally — a direct URL has no server to wait for, and waiting on one delays a stream that was ready immediately');
        }

        // 6. The probe has to run in its OWN try. Sharing resolve()'s catch is
        //    what turned a fault in a diagnostic into a broken player: the URL
        //    had already resolved correctly, the throw in the wait loop reached
        //    the outer catch, and the screen was told the stream had failed —
        //    "resolve FAILED: Member function not found" for a server that was
        //    never asked for anything. A diagnostic may only ever ADD what is
        //    known, so its failure has to be recorded and then ignored.
        if (!/resolved\.probe\s*=\s*WaitForPlaylist/.test(resolveBody)) {
            err('StreamResolveTask.brs resolve() no longer calls WaitForPlaylist — torrents get no readiness wait, and the Video node is back to eating the cold-engine response itself');
        } else if (!/resolved\.probe\s*=\s*\{/.test(resolveBody)) {
            err('StreamResolveTask.brs resolve() runs the probe in the same try as the resolve — a throw in a diagnostic then discards a URL that already resolved, which is how every torrent reported "Member function not found"');
        } else {
            // The inner catch has to come BEFORE the result is published, or the
            // fallback probe object is attached to nothing.
            const fallbackAt = /resolved\.probe\s*=\s*\{/.exec(resolveBody).index;
            if (resultAt !== -1 && fallbackAt > resultAt) {
                err('StreamResolveTask.brs resolve() publishes the result before the probe fallback — the record of a failed probe would never reach the screen');
            }
        }
    }

    // 7. The probe's account has to reach the log in the SUCCESS case too, and this
    //    one exists because that gap cost real diagnosis. A play that times out once
    //    and then recovers on attempt 2 IS a success — the failure-branch print was
    //    gated on gaveUp, so it stayed silent, and the only trace left was a stray
    //    [http] timeout line with nothing saying how many attempts ran or what the
    //    first one answered. That is precisely the pair of facts needed to tell a
    //    cold engine (first attempt expires while the engine is still coming up)
    //    from a flaky link (an engine already proven ready still loses a request),
    //    and without it the two were indistinguishable in the log.
    const player = code(read('components/PlayerScreen.brs'));
    if (!/probe gave up after/.test(player)) {
        err('PlayerScreen.brs no longer prints the probe give-up — a stream the server refused has nothing left to tell it apart from one that was never asked');
    }
    if (!/probe recovered after/.test(player)) {
        err('PlayerScreen.brs does not print the RECOVERED probe — a play that timed out once and then succeeded is a success, so with only the give-up path logged its timeout left nothing behind but a stray [http] line');
    } else {
        // ...and the recovered print must not be reachable only through the give-up
        // guard, which is what nesting it in that branch would look like. Walked line
        // by line to the first branch terminator rather than matched with one regex:
        // the regex forms of this are all subtly wrong — a lazy match runs straight
        // through an `else if` sibling and reports it as nested, and a tempered one
        // that stops at the `else` can then never reach the `end if` it is looking
        // for. A `^`-anchored lookahead also needs the `m` flag to mean "start of
        // line" at all, which is the sort of detail a contract should not be
        // resting on. Being two lines further down the sub is not nesting.
        const playerLines = player.split('\n');
        const gaveUpLine = playerLines.findIndex(l => /gaveUp\s*=\s*true/.test(l));
        if (gaveUpLine !== -1) {
            for (let i = gaveUpLine + 1; i < playerLines.length; i++) {
                if (/^\s*(else|end if|end while|end for)\b/.test(playerLines[i])) break;
                if (/probe recovered after/.test(playerLines[i])) {
                    err('PlayerScreen.brs prints the recovered probe from inside the gaveUp branch — that branch can never be reached when the probe succeeded, which is the one case that needed it');
                    break;
                }
            }
        }
    }

    return ok;
}

function checkAddonSyncTaskContract() {
    const fs = require('fs');
    const read = (f) => fs.readFileSync(path.join(projectRoot, f), 'utf8');
    const code = (src) => src.split('\n').map(line => line.split("'")[0]).join('\n');
    const taskXml = read('components/AddonSyncTask.xml');
    const taskBrs = code(read('components/AddonSyncTask.brs'));
    const main = code(read('components/MainScene.brs'));
    const coordinator = code(read('components/AccountSyncCoordinator.brs'));
    const async = code(read('source/core/AsyncTask.bs'));
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    // Body of a sub/function by name, from its header to the matching end at the
    // same indentation. Positions matter for the ordering checks below, so this
    // returns the source slice rather than a boolean.
    const body = (src, name) => {
        const start = new RegExp(`^[ \\t]*(?:public\\s+|private\\s+|override\\s+)*(?:sub|function)\\s+${name}\\s*\\(`, 'm').exec(src);
        if (!start) return null;
        const rest = src.slice(start.index);
        const end = rest.slice(1).search(/^[ \t]*end\s+(?:sub|function)\b/m);
        return end === -1 ? rest : rest.slice(0, end + 1);
    };

    // 1. The sentinel and the narration have to exist as declared interface
    //    fields. callFunc/ObserveField on an undeclared field is a no-op, and a
    //    write to an undeclared dynamic field notifies nobody.
    if (!/<field\s+id="finished"\s+type="boolean"[^>]*alwaysNotify="true"/.test(taskXml)) {
        err('AddonSyncTask.xml does not declare <field id="finished" type="boolean" ... alwaysNotify="true" /> — without the sentinel the handler cannot tell "not written yet" from "never written", which is the whole bug');
    }
    if (!/<field\s+id="stage"\s+type="string"/.test(taskXml)) {
        err('AddonSyncTask.xml does not declare a "stage" field — a failure names the hop only if the worker recorded how far it got');
    }

    // 2. The sentinel must be the last statement, and the result must be written
    //    before it. Reversed, the done-callback can conclude "no result" about a
    //    worker that is merely mid-write, which is the original bug wearing a fix.
    const sync = body(taskBrs, 'sync');
    if (!sync) {
        err('AddonSyncTask.brs has no sync() — the worker body is gone');
    } else {
        const resultAt = sync.indexOf('m.top.result =');
        const finishedAt = sync.indexOf('m.top.finished = true');
        if (finishedAt === -1) {
            err('AddonSyncTask.brs sync() never sets m.top.finished — the sentinel is what lets MainScene tell a finished worker from a pending one');
        } else {
            if (resultAt === -1) {
                err('AddonSyncTask.brs sync() sets finished without ever writing m.top.result — the sentinel would report success on a worker that produced nothing');
            } else if (resultAt > finishedAt) {
                err('AddonSyncTask.brs sync() writes m.top.finished BEFORE m.top.result — the done-callback can then fire on a worker whose result has not landed yet, which re-creates the very race the sentinel exists to settle');
            }
            const tail = sync.slice(finishedAt).split('\n').map(l => l.trim()).filter(l => l !== '');
            const last = tail[tail.length - 1];
            if (last !== 'm.top.finished = true') {
                err(`AddonSyncTask.brs sync() does not end on m.top.finished = true (last statement is "${last}") — the sentinel has to be the last thing the worker does, or it can assert completion while work remains`);
            }
        }
        if (!/catch[\s\S]*?m\.top\.result\s*=/.test(sync)) {
            err('AddonSyncTask.brs sync() no longer writes a result from its catch path — a thrown request would finish with the sentinel set and no result at all, which is unreportable');
        }
        // The stage ladder. A presence check is not enough — four of the five
        // rungs can be deleted and `/m.top.stage =/` still matches. What carries
        // the diagnosis is the rung AT THE REQUEST BOUNDARY: it is the one that
        // separates "the worker never got as far as the network" from "the request
        // went out", which is the first question anyone asks when a sync produces
        // nothing. So that specific rung is what gets pinned: a stage write on the
        // statement line immediately before the line that performs the request.
        // (Compared by line, not by character offset — the offset of the call
        // lands mid-line, so slicing "everything before it" ends on the tail of
        // the request line itself and the previous-line lookup silently compares
        // against `result = `.)
        if (!/m\.top\.stage\s*=/.test(sync)) {
            err('AddonSyncTask.brs sync() never writes m.top.stage — the fault strip can only name the failing hop if the worker records it');
        }
        const syncLines = sync.split('\n');
        const reqLine = syncLines.findIndex(l => l.includes('store.AddonCollectionGet()'));
        if (reqLine === -1) {
            err('AddonSyncTask.brs sync() no longer calls store.AddonCollectionGet() — the worker is not doing the job it exists for');
        } else {
            let prev = reqLine - 1;
            while (prev >= 0 && syncLines[prev].trim() === '') prev -= 1;
            if (prev < 0 || !/m\.top\.stage\s*=/.test(syncLines[prev])) {
                err('AddonSyncTask.brs sync() does not write m.top.stage immediately before the request call — that rung is what separates "the worker never reached the network" from "the request went out and never came back", and without it every sync failure reports one indistinguishable stage');
            }
        }
    }

    // 3. The defect itself: an empty result must be DECLINED, not reaped. The
    //    coordinator now owns this task lifecycle; the ordering remains pinned.
    const onResult = body(coordinator, 'onAddonResult');
    if (!onResult) {
        err('AccountSyncCoordinator.brs has no onAddonResult — the sync result has no entry point');
    } else {
        const bailAt = /if\s+result\s*=\s*invalid\s+then\s+return/.exec(onResult);
        if (!bailAt) {
            err('AccountSyncCoordinator.onAddonResult no longer declines an empty result — reaping an alwaysNotify initial notification destroys the real answer');
        }
        const reapAt = onResult.indexOf('AsyncTask_Reap(');
        if (reapAt === -1 || (bailAt && reapAt < bailAt.index)) {
            err('AccountSyncCoordinator.onAddonResult must decline an empty result before reaping the task');
        }
        if (!/if\s+result\.revokedSession\s*=\s*true/.test(onResult)) {
            err('AccountSyncCoordinator.onAddonResult must route a revoked session to MainScene without truthiness-testing an absent field');
        }
        if (!/callFunc\("AdoptAddonSyncResult",\s*result\)/.test(onResult)) {
            err('AccountSyncCoordinator.onAddonResult must hand a valid result to MainScene for store adoption and screen refreshes');
        }
    }

    // 4. The done-callback is the only authority on "the worker finished with
    //    nothing", and it acts only on the sentinel's VALUE.
    const onFinished = body(coordinator, 'onAddonFinished');
    if (!onFinished) {
        err('AccountSyncCoordinator.brs has no onAddonFinished — a worker finishing without a result would be silent');
    } else {
        const finTest = /if\s+task\.finished\s*<>\s*true\s+then\s+return/.exec(onFinished);
        if (!finTest) {
            err('AccountSyncCoordinator.onAddonFinished must test the sentinel value before acting; notification arrival alone does not mean done');
        }
        const finAt = finTest ? finTest.index : -1;
        for (const [needle, what] of [['AsyncTask_Reap(', 'reaps the task'], ['m.addonTask = invalid', 'clears the task slot'], ['ReportAddonSyncFault(', 'publishes a fault']]) {
            const at = onFinished.indexOf(needle);
            if (at !== -1 && finAt !== -1 && at < finAt) {
                err(`AccountSyncCoordinator.onAddonFinished ${what} before testing task.finished — the spurious alwaysNotify notification could reap a live worker`);
            }
        }
        if (!/task\.stage/.test(onFinished) || !/callFunc\("ReportAddonSyncFault"/.test(onFinished) || !/AsyncTask_Reap\(/.test(onFinished)) {
            err('AccountSyncCoordinator.onAddonFinished must reap the finished worker and report its diagnostic stage');
        }
    }

    // 5. Both observers are attached before RUN by AsyncTask_Launch, and this
    //    coordinator owns the launch rather than MainScene.
    const start = body(coordinator, 'StartAddonSync');
    if (!start || !/AsyncTask_Launch\([\s\S]*?"onAddonResult"[\s\S]*?"onAddonFinished"\s*\)/.test(start)) {
        err('AccountSyncCoordinator.StartAddonSync must pass the result and done callbacks to AsyncTask_Launch');
    }
    if (!/callFunc\("StartAddonSync"\)/.test(main)) {
        err('MainScene.StartAddonSync must delegate the account pull to AccountSyncCoordinator');
    }

    const launch = body(async, 'AsyncTask_Launch');
    if (!launch) {
        err('source/core/AsyncTask.bs has no AsyncTask_Launch');
    } else {
        if (!/ObserveField\(\s*"finished"\s*,\s*doneCallback\s*\)/.test(launch)) {
            err('AsyncTask_Launch does not observe the "finished" sentinel — the optional done-callback parameter exists but is never wired to anything');
        }
        const finAt = launch.indexOf('ObserveField("finished"');
        const runAt = launch.indexOf('control = "RUN"');
        if (finAt === -1 || runAt === -1 || finAt > runAt) {
            err('AsyncTask_Launch attaches the "finished" observer AFTER control = "RUN" — the worker can start before its observer exists, so the only notification that reports a failure can be the one that gets missed');
        }
    }
    const reap = body(async, 'AsyncTask_Reap');
    if (!reap || !/UnobserveField\(\s*"finished"\s*\)/.test(reap)) {
        err('AsyncTask_Reap does not unobserve "finished" — a done-callback left attached can fire against a node that has already been handed back or removed');
    }
    return ok;
}

// Home's catalog rows could be permanently stale, with nothing reporting it.
//
// The add-on sync gated its rebuild on `added > 0` — "at least one add-on was
// newly installed". That predicate is false on every run after the first: the
// account's add-ons are already in the registry, so none of them is "added". So
// Home was told to re-derive only on the very first sync of a fresh install and
// never again. Home kept whatever catalog set it walked at launch, which in a
// stremio session is usually just the built-in seeds because a session swap
// replaces what AddonsGetAll returns wholesale. Meanwhile the Add-ons screen,
// which reads the registry live, listed the account's add-ons correctly.
//
// The result was two views of the same registry permanently disagreeing, with no
// fault strip entry, because nothing had failed — the sync succeeded and simply
// told nobody. Device evidence: the Add-ons screen listed the stremio add-ons
// while Home showed only the built-ins, and leaving for Settings and back
// changed nothing.
//
// The fix is a set comparison rather than a count: Home records which add-on set
// its rows were derived from and re-derives when that set moves. This also
// subsumes the two cases a count can never see — a session swap (the set changes
// with nothing installed) and a walk that latched on an empty registry — which is
// why the fix is one mechanism and not three call-site patches.
//
// The brs interpreter can drive HomeScreen's subs, but it cannot run a
// HomeCatalogsTask worker, and the whole failure is about which predicate gates a
// call site. So the invariant is pinned structurally.
function checkTaskTeardownContract() {
    const fs = require('fs');
    const read = (f) => fs.readFileSync(path.join(projectRoot, f), 'utf8');
    const code = (src) => src.split('\n').map(line => line.split("'")[0]).join('\n');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    const body = (src, name) => {
        const start = new RegExp(`^[ \\t]*(?:public\\s+|private\\s+|override\\s+)*(?:sub|function)\\s+${name}\\s*\\(`, 'm').exec(src);
        if (!start) return null;
        const rest = src.slice(start.index);
        const end = rest.slice(1).search(/^[ \t]*end\s+(?:sub|function)\b/m);
        return end === -1 ? rest : rest.slice(0, end + 1);
    };

    // AsyncTask.bs states the contract both screens below used to break: removing
    // a running Task node frees the node WITHOUT killing the worker thread. So a
    // teardown that is only a RemoveChild leaves a thread running that can still
    // write its result into state the screen has already discarded.
    //
    // HomeScreen.RebuildRows did exactly that, unobserving the field and removing
    // the node while HomeCatalogsTask could still be walking the registry. It is
    // reached from a deep-link import, so the sequence is: a walk is in flight, an
    // import lands, RebuildRows throws the grid away and starts a second walk, and
    // the first one finishes and pushes its descriptors at the grid anyway — two
    // workers interleaving rows into one live grid.
    //
    // It had to be STOP-then-remove, not merely AsyncTask_Reap(.., true): the
    // reaper sends STOP to the task NODE, and the loop that reads that flag lives
    // on the task's own worker thread. A bare RemoveChild never reaches either.
    const home = code(read('components/HomeScreen.brs'));
    const rebuild = body(home, 'RebuildRows');
    if (!rebuild) {
        err('HomeScreen.brs has no RebuildRows() — the add-on-import rebuild path cannot be checked at all');
    } else {
        const reap = body(rebuild, 'AsyncTask_Reap') || rebuild;
        const stops = /(AsyncTask_Reap\s*\([^)]*,\s*[^,)]+,\s*true\s*\))|(task\.control\s*=\s*"STOP")/.test(reap);
        const removes = /RemoveChild\s*\(/.test(reap);
        if (!stops && removes) {
            err('HomeScreen.brs RebuildRows() removes m.catalogTask without sending STOP first. Removing a running Task node does not kill its worker thread (AsyncTask.bs says so explicitly), so a catalog walk already in flight finishes and applies its rows to a grid that was just discarded and rebuilt — two workers interleaving descriptors into one grid. Reap with doStop = true, as AsyncTask.bs prescribes for a possibly-still-running task.');
        }
    }

    // StreamsScreen is a static child that survives every pop, so CancelStreamsLoad
    // runs on the way out of an episode whose batch may still be fetching. STOP
    // does not reach an in-flight roUrlTransfer, so those workers keep their
    // sockets open and keep fetching after the screen has disowned them.
    //
    // onStreamsLoaded therefore has to tell "the task I launched is reporting" from
    // "an abandoned task of the same batch shape is reporting". providerIndex is
    // unique only WITHIN a batch: once a new episode launches its own batch, an
    // old worker whose index falls inside the new list would otherwise be
    // accepted, consume a live task's slot, and push the PREVIOUS episode's
    // streams into this episode's provider. The reporting node has to be the node
    // still being waited on.
    const streams = code(read('components/StreamsScreen.brs'));
    const loaded = body(streams, 'onStreamsLoaded');
    if (!loaded) {
        err('StreamsScreen.brs has no onStreamsLoaded() — a cancelled batch cannot be distinguished from the live one without it');
    } else {
        const identity = /task\.loadToken\s*<>\s*m\.loadToken/.test(loaded);
        const slot = /m\.loadTasks\[index\]\s*=\s*invalid/.test(loaded);
        if (slot && !identity) {
            err('StreamsScreen.brs onStreamsLoaded() clears m.loadTasks[index] on providerIndex alone. providerIndex is unique only within a batch, so a worker from a batch CancelStreamsLoad already STOPped can land here after the next episode has launched its own, take a live task\'s slot, and push the previous episode\'s streams into this one. Check the batch token first (`if m.loadToken = "" or task.loadToken <> m.loadToken then return`).');
        }
        // Neither of these node comparisons exists in BrightScript, and both were
        // written here and rejected by the device before the token replaced them:
        // `<>` between two roSGNodes is &h18 (Type Mismatch), and `.IsSame()` is
        // &hf4 — the roSGNode reference lists ifAssociativeArray, ifSGNodeChildren,
        // ifSGNodeField, ifSGNodeDict, ifSGNodeFocus, ifSGNodeBoundingRect and
        // ifSGNodeHttpAgentAccess, and no identity member among them. No static
        // check can catch either, because the brs interpreter has no node objects.
        if (/m\.loadTasks\[index\]\s*<>\s*task/.test(loaded)) {
            err('StreamsScreen.brs onStreamsLoaded() compares two roSGNodes with `<>`. BrightScript\'s comparison operators cannot be applied to node references — that is a runtime &h18 "Type Mismatch. Operator \\"<\\>" can\'t be applied to \\"roSGNode\\" and \\"roSGNode\\"" and it aborts the whole notification handler, so a provider that lands never renders. Compare the scalar loadToken instead.');
        }
        if (/m\.loadTasks\[index\]\s*\.\s*IsSame\s*\(/.test(loaded) || /\btask\s*\.\s*IsSame\s*\(/.test(loaded)) {
            err('StreamsScreen.brs onStreamsLoaded() calls IsSame() on a node. roSGNode has no such member — the documented interfaces are ifAssociativeArray, ifSGNodeChildren, ifSGNodeField, ifSGNodeDict, ifSGNodeFocus, ifSGNodeBoundingRect and ifSGNodeHttpAgentAccess — so this is a runtime &hf4 "Member function not found" that kills the handler. Compare the scalar loadToken instead.');
        }
        if (identity && /m\.loadTasks\[index\]\s*=\s*invalid\s+then\s+return/.test(loaded) === false) {
            err('StreamsScreen.brs onStreamsLoaded() never returns on an already-claimed `m.loadTasks[index] = invalid` slot. Without it a duplicate notification from the same provider re-applies its streams and decrements pendingCount a second time, so the count reaches zero early and the status line misreports while providers are still loading.');
        }
        // The token only separates batches if it is actually minted per batch and
        // stamped onto every task. Either half missing silently disables it.
        if (identity) {
            const launch = /loadToken\s*:\s*m\.loadToken/.test(streams);
            const mint = /m\.loadToken\s*=\s*m\.loadSeq\.ToStr\(\)/.test(streams);
            if (!launch) {
                err('StreamsScreen.brs LoadStreams() does not pass loadToken to AsyncTask_Launch — every task would carry the default "" from StreamsLoaderTask.xml, so the token in onStreamsLoaded compares equal for a stale batch and for the live one, which is exactly the collision it was added to prevent.');
            }
            if (!mint) {
                err('StreamsScreen.brs never mints a fresh m.loadToken per batch (m.loadToken = m.loadSeq.ToStr()) — a token that does not change between passes lets two passes over the same episode accept each other\'s reports.');
            }
        }
        // pendingCount is what OnEnter\'s same-episode guard reads to decide a
        // batch is genuinely in flight. Every terminal path must decrement it or
        // the count sticks above zero and the guard blocks a legitimate reload
        // forever, leaving an episode\'s stream list permanently empty.
        if (identity && slot) {
            const tail = loaded.slice(loaded.indexOf('m.loadTasks[index] = invalid'));
            const guard = /if\s+m\.providers\s*=\s*invalid\s+or\s+index\s*>=\s*m\.providers\.Count\(\)\s+then\s*\n\s*if\s+m\.pendingCount\s*>\s*0\s+then\s+m\.pendingCount\s*=\s*m\.pendingCount\s*-\s*1/.test(tail);
            if (!guard) {
                err('StreamsScreen.brs onStreamsLoaded() can return between claiming m.loadTasks[index] and writing into m.providers without decrementing m.pendingCount. OnEnter guards the same-episode reload on that count, so a stranded non-zero value makes the guard block every later visit and the list never fills. Count the task as landed on that path too.');
            }
        }
    }

    // The guard is only as good as the key it compares and the invalidation it
    // relies on. CancelStreamsLoad must clear BOTH, or a cancelled batch stays
    // "owned": pendingCount keeps its old value and loadKey keeps naming an
    // episode whose tasks were just reaped, so OnEnter matches, skips the reload,
    // and the list stays empty with the fetch that would fill it already cancelled.
    const cancel = body(streams, 'CancelStreamsLoad');
    if (cancel) {
        if (/m\.loadKey\s*=\s*""/.test(cancel) === false) {
            err('StreamsScreen.brs CancelStreamsLoad() does not clear m.loadKey — a reaped batch stays distinguishable from a live one, so OnEnter can treat a cancelled episode as still in flight and skip the reload that would refill the list');
        }
        if (/m\.pendingCount\s*=\s*0/.test(cancel) === false) {
            err('StreamsScreen.brs CancelStreamsLoad() does not zero m.pendingCount — OnEnter reads that count to decide a batch is in flight, so a stale non-zero value makes it skip the reload and the stream list stays empty');
        }
    }

    // The same-episode guard, and the reason it exists: OnEnter used to cancel
    // and re-launch the whole provider batch on every entry, so re-entering an
    // episode while its batch was still fetching sent a second identical request
    // per add-on. Four copies of one manifest in a single device log is this.
    const enter = body(streams, 'OnEnter');
    if (enter) {
        const guardAt = /EpisodeKey\(params\)\s*=\s*m\.loadKey/.exec(enter);
        const cancelAt = /CancelStreamsLoad\(\)/.exec(enter);
        if (guardAt && cancelAt && guardAt.index > cancelAt.index) {
            err('StreamsScreen.brs OnEnter() compares EpisodeKey only AFTER CancelStreamsLoad() — by then m.loadKey and m.pendingCount have been cleared by the cancel, so the guard can never match and every entry re-fans out the whole batch again');
        }
    }

    return ok;
}

// HomeCatalogsTask used to publish { rows: allRowsSoFar } after every catalog.
// Each field assignment crossed the Task boundary with every previous catalog
// and its meta array again, so the payload-copy volume grew quadratically as the
// Home filled. The task now sends one row per result and a small completion
// packet; the screen applies each row as it arrives.
function checkHomeCatalogResultsAreIncremental() {
    const fs = require('fs');
    const read = (f) => fs.readFileSync(path.join(projectRoot, f), 'utf8');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };
    const task = read('components/HomeCatalogsTask.brs');
    const screen = read('components/HomeScreen.brs');
    const onResult = screen.match(/^sub onCatalogState\([^\n]*\)[\s\S]*?^end sub/m);

    if (!/m\.top\.result\s*=\s*\{\s*row:\s*row,\s*done:\s*false\s*\}/.test(task)) {
        err('HomeCatalogsTask must publish one completed row per result, not a snapshot containing every row so far');
    }
    if (/m\.top\.result\s*=\s*\{\s*rows\s*:/.test(task) || /rows\.Push\(/.test(task)) {
        err('HomeCatalogsTask still accumulates/publishes the full catalog row list — that recopies every earlier meta on each result');
    }
    if (!/m\.top\.result\s*=\s*\{\s*done:\s*true/.test(task)) {
        err('HomeCatalogsTask must publish a final completion packet after the last row');
    }
    if (!onResult || !/state\.row/.test(onResult[0]) || !/ApplyCatalogRow\(state\.row\)/.test(onResult[0]) || !/state\.done\s*=\s*true/.test(onResult[0])) {
        err('HomeScreen.onCatalogState must consume each row result and finish on the completion packet');
    }
    return ok;
}

function checkStopSignalContract() {
    const fs = require('fs');
    const read = (f) => fs.readFileSync(path.join(projectRoot, f), 'utf8');
    const code = (src) => src.split('\n').map(line => line.split("'")[0]).join('\n');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    // A Task's run state has to be inquired through `state`, never `control`.
    // Roku documents control as WRITE_ONLY — it only "requests a change in the
    // run state" — and state as READ_ONLY, answering lowercase "init", "stop",
    // "run", "done". BrightScript's `=` is case-sensitive ("one" = "One" is
    // false), so the idiom this app carried, `if m.top.control = "STOP"`, could
    // never match for two independent reasons at once: the field is not
    // readable, and the value it would answer is lowercase anyway. Every such
    // guard was a no-op that, in review, looked exactly like a guard. So the
    // regression this pins is someone reintroducing it — in either half.
    const tasks = [
        'components/StreamResolveTask.brs',
        'components/SubtitleLoaderTask.brs',
        'components/LinkStremioTask.brs'
    ];

    for (const file of tasks) {
        const src = code(read(file));
        const name = file.split('/').pop();

        // The guard has to exist at all. Removing a running Task node does not
        // kill its worker thread (AsyncTask.bs says so), so without a check the
        // worker keeps going after the screen stopped it and walked away — and
        // in StreamResolveTask that is the worker whose requests keep the
        // stream server's idle clock reset, so the companion keeps downloading
        // for a play nobody is watching.
        if (!/m\.top\.state\s*=\s*"stop"/.test(src)) {
            err(`${name} has no \`if m.top.state = "stop"\` guard — removing a running Task node does not kill its worker thread, so the worker has no way to notice the screen stopped it and keeps working after the user has left`);
        }

        // The field. A read of control is the old no-op: it is WRITE_ONLY, so
        // reading it back never reflects a stop. The stop checks are the only
        // reads of it in these three files, so any occurrence is that check.
        if (/m\.top\.control/.test(src)) {
            err(`${name} reads m.top.control — it is WRITE_ONLY ("requests a change in the run state"), so reading it back never reflects a stop and the guard silently degenerates to a no-op. Read m.top.state (READ_ONLY) instead`);
        }

        // The case. Even against the right field, "STOP" never matches: state
        // answers lowercase and `=` is case-sensitive. This is the half that
        // survives a field swap, and it is the easiest to reintroduce by muscle
        // memory from the WRITE side, which really is uppercase.
        if (/m\.top\.state\s*=\s*"STOP"/.test(src)) {
            err(`${name} compares m.top.state to "STOP" — state answers lowercase and BrightScript's = is case-sensitive, so ("stop" = "STOP") is false and the guard never fires. Compare to "stop"`);
        }
    }

    // The write side is NOT symmetric with the read: control is case-
    // insensitive to SET, so `control = "STOP"` (or "stop") is how a task is
    // stopped — while state is READ_ONLY and cannot be assigned at all. This
    // pins the writer so the read-side fix above is not mistaken for a reason
    // to touch it, and so a STOP is never routed through the inquiry field.
    if (!/\btask\.control\s*=\s*"/.test(code(read('source/core/AsyncTask.bs')))) {
        err('AsyncTask.bs no longer stops the task through task.control — the WRITE belongs on control (the setter; state is READ_ONLY), and teardown depends on STOP reaching the node before it is removed');
    }

    return ok;
}

function checkHomeCatalogStalenessContract() {
    const fs = require('fs');
    const read = (f) => fs.readFileSync(path.join(projectRoot, f), 'utf8');
    const code = (src) => src.split('\n').map(line => line.split("'")[0]).join('\n');
    const home = code(read('components/HomeScreen.brs'));
    const homeXml = read('components/HomeScreen.xml');
    const main = code(read('components/MainScene.brs'));
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    const body = (src, name) => {
        const start = new RegExp(`^[ \\t]*(?:public\\s+|private\\s+|override\\s+)*(?:sub|function)\\s+${name}\\s*\\(`, 'm').exec(src);
        if (!start) return null;
        const rest = src.slice(start.index);
        const end = rest.slice(1).search(/^[ \t]*end\s+(?:sub|function)\b/m);
        return end === -1 ? rest : rest.slice(0, end + 1);
    };

    // 1. The predicate itself: freshness is the add-on SET, compared against
    //    what Home last derived from. A count cannot be substituted here.
    const sig = body(home, 'CatalogSignature');
    if (!sig) {
        err('HomeScreen.brs has no CatalogSignature() — nothing can tell that Home\'s rows were overtaken');
    } else if (!/m\.stores\.addons\.callFunc\(\s*"AddonsGetAll"\s*\)/.test(sig)) {
        err('HomeScreen.brs CatalogSignature() does not read the live add-on set — a signature derived from anything but the current registry cannot detect staleness');
    } else if (!/\.Sort\(/.test(sig) || !/\.Join\(/.test(sig)) {
        err('HomeScreen.brs CatalogSignature() does not sort and join — without that, two identical sets in a different order compare as different and every sync re-walks every catalog');
    }

    const ensure = body(home, 'EnsureCurrentRows');
    if (!ensure) {
        err('HomeScreen.brs has no EnsureCurrentRows() — the call sites have nothing to call, and a stale grid stays stale');
    } else {
        // Fresh must be a no-op, and the test must come BEFORE the rebuild.
        const fresh = /if\s+m\.catalogSignature\s*=\s*CatalogSignature\(\)\s+then\s+return/.exec(ensure);
        if (!fresh) {
            err('HomeScreen.brs EnsureCurrentRows() does not short-circuit when the add-on set is unchanged — every launch would re-walk every catalog over the network');
        }
        if (!/RebuildRows\(\)/.test(ensure)) {
            err('HomeScreen.brs EnsureCurrentRows() never re-derives the grid — it can detect staleness but does nothing about it');
        }
        const freshAt = fresh ? fresh.index : -1;
        const rebuildAt = ensure.indexOf('RebuildRows()');
        if (freshAt !== -1 && rebuildAt !== -1 && rebuildAt < freshAt) {
            err('HomeScreen.brs EnsureCurrentRows() rebuilds BEFORE the freshness test — the grid is re-derived on every call regardless of whether anything changed');
        }
    }

    // 2. The walk must record what it derived from, and must do so BEFORE the
    //    empty-registry early return. A walk that latched on an empty registry
    //    and left the signature at init-time "" is indistinguishable from a
    //    correct empty grid, which is precisely the state that must stay
    //    recognisable as stale once add-ons arrive.
    const start = body(home, 'StartCatalogLoad');
    if (!start) {
        err('HomeScreen.brs has no StartCatalogLoad()');
    } else {
        const setAt = /m\.catalogSignature\s*=\s*CatalogSignature\(\)/.exec(start);
        if (!setAt) {
            err('HomeScreen.brs StartCatalogLoad() never records m.catalogSignature — Home would have no record of what its rows were derived from, so nothing can ever be stale');
        }
        const emptyGate = /if\s+addons\.Count\(\)\s*=\s*0\s+then/.exec(start);
        if (emptyGate && setAt && setAt.index > emptyGate.index) {
            err('HomeScreen.brs StartCatalogLoad() records m.catalogSignature AFTER the empty-registry early return — a walk that latched on an empty registry then keeps the init-time signature, making it indistinguishable from a correct empty grid and permanently unrecoverable');
        }
    }

    // 3. Re-entry must repair it. StartCatalogLoad() is a no-op once the walk has
    //    latched, so OnEnter needs its own check or leaving and returning cannot
    //    fix a stale grid.
    const onEnter = body(home, 'OnEnter');
    if (!onEnter || !/EnsureCurrentRows\(\)/.test(onEnter)) {
        err('HomeScreen.brs OnEnter() no longer calls EnsureCurrentRows() — StartCatalogLoad() is a no-op once latched, so without this a stale grid can only be repaired by a relaunch (which is what it looked like: Settings-and-back changed nothing)');
    }

    // 4. The call sites must be UNCONDITIONAL. This is the defect itself: a
    //    rebuild gated on an install count is false on every re-sync.
    const onSync = body(main, 'AdoptAddonSyncResult');
    if (!onSync) {
        err('MainScene.brs has no AdoptAddonSyncResult()');
    } else {
        if (!/callFunc\(\s*"EnsureCurrentRows"\s*\)/.test(onSync)) {
            err('MainScene.brs AdoptAddonSyncResult() no longer calls EnsureCurrentRows() — the sync is the authority on "the add-on set may have moved" and it now tells nobody');
        }
        if (/if\s+added\s*>/.test(onSync)) {
            err('MainScene.brs AdoptAddonSyncResult() re-gates the rebuild on `added > 0` — an unchanged account installs nothing, so this is false on every run after the first and Home is never told to re-derive. That is the original bug.');
        }
    }
    const importSub = body(main, 'ImportFinished');
    if (importSub) {
        if (!/callFunc\(\s*"EnsureCurrentRows"\s*\)/.test(importSub)) {
            err('MainScene.brs ImportFinished() no longer calls EnsureCurrentRows() — an import that re-registers add-ons Home already has still leaves Home showing its pre-import catalog set');
        }
    }

    // 5. Reachable through callFunc at all.
    if (!/<function\s+name="EnsureCurrentRows"/.test(homeXml)) {
        err('HomeScreen.xml does not declare EnsureCurrentRows in its <interface> — callFunc against an undeclared name is a silent no-op, so the call sites would do nothing at all');
    }
    const init = body(home, 'init');
    if (!init || !/m\.catalogSignature\s*=\s*""/.test(init)) {
        err('HomeScreen.brs init() does not seed m.catalogSignature — an uninitialised field reads invalid, and invalid would never equal a real signature, so the very first EnsureCurrentRows() would rebuild unconditionally');
    }
    return ok;
}

// Subtitle providers are MERGED, not raced.
//
// It used to be first-hit-wins: the drain stopped at the first provider that
// returned tracks, and its list REPLACED whatever was there. So a user with two
// working subtitle add-ons saw only one provider's captions, ranked order decided
// which one got to answer at all, and a user with one flaky add-on and one good
// one got captions on some plays and not others with nothing on screen to say
// which. The fix is sequential merge: every ranked provider is asked, in rank
// order, and their tracks accumulate.
//
// Merge is only safe because of two properties, and both are invisible in the
// resulting track list — which is why they need pinning rather than eyeballing:
//
//   m.subtitleIndex is computed ONCE, on the first provider that yields tracks.
//   Re-picking per provider renumbers an append-only list underneath a selection
//   the user may already have made, silently switching them to another caption.
//
//   The append is genuinely append-only — no dedup, no re-sort, no replace. A
//   dedup would make the surviving track depend on provider order, which is the
//   device-dependent ordering this whole area was rebuilt to eliminate.
//
// The brs interpreter can run these subs, but the drain is driven by task
// callbacks the interpreter never fires, so the sequence is not observable from a
// test. Pinned structurally.
function checkSubtitleMergeContract() {
    const fs = require('fs');
    const read = (f) => fs.readFileSync(path.join(projectRoot, f), 'utf8');
    const code = (src) => src.split('\n').map(line => line.split("'")[0]).join('\n');
    const player = code(read('components/PlayerScreen.brs'));
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    const member = (src, name) => {
        const start = src.search(new RegExp(`^[ \\t]*(?:public\\s+|private\\s+|override\\s+)*(?:sub|function)\\s+${name}\\s*\\(`, 'm'));
        if (start === -1) return null;
        const rest = src.slice(start);
        const end = rest.slice(1).search(/^[ \t]*end\s+(?:sub|function)\b/m);
        return end === -1 ? rest : rest.slice(0, end + 1);
    };

    const onResult = member(player, 'onSubtitleResult');
    if (!onResult) {
        err('PlayerScreen.brs has no onSubtitleResult — the merge has no entry point');
        return ok;
    }

    // 1. It must APPEND, not assign. `m.subtitleTracks = result.subtitles` is the
    //    exact first-hit-wins line this replaced, and it is the single most
    //    important thing to keep gone.
    if (/m\.subtitleTracks\s*=\s*result\.subtitles/.test(onResult)) {
        err('PlayerScreen.onSubtitleResult assigns m.subtitleTracks = result.subtitles — that REPLACES the merged list, which is first-hit-wins: the first provider to answer becomes the only one with a say');
    }
    if (!/m\.subtitleTracks\.Push\(\s*track\s*\)/.test(onResult)) {
        err('PlayerScreen.onSubtitleResult no longer appends with m.subtitleTracks.Push(track) — tracks must accumulate across providers, and the merge is the whole point');
    }

    // 2. The default pick happens once. A PickTrack call outside the firstTracks
    //    branch renumbers the list under the user on every provider that answers.
    const pick = /m\.subtitleIndex\s*=\s*m\.subtitlePicker\.PickTrack\(/.exec(onResult);
    if (!pick) {
        err('PlayerScreen.onSubtitleResult no longer picks a default track — nothing would ever be selected, only listed');
    } else {
        if (!/firstTracks/.test(onResult)) {
            err('PlayerScreen.onSubtitleResult re-picks the default on every provider — the pick must be gated on the first merge that yields tracks, or later providers renumber the list under the user\'s existing selection');
        } else {
            // The pick must be INSIDE the firstTracks guard, not merely near it.
            const guard = /if\s+firstTracks\s+then[^\n]*PickTrack\(/.test(onResult);
            if (!guard) {
                err('PlayerScreen.onSubtitleResult does not gate the PickTrack call on firstTracks — a pick per provider renumbers an append-only list and silently switches the user to a different caption');
            }
        }
    }

    // 3. The drain must continue after a provider SUCCEEDS, not only after one
    //    returns nothing. This is the difference between "one provider answered"
    //    and "every ranked provider answered".
    const lines = onResult.split('\n');
    const pushLine = lines.findIndex(l => /m\.subtitleTracks\.Push\(\s*track\s*\)/.test(l));
    const drainLine = lines.findIndex((l, i) => i > pushLine && /LaunchSubtitleFetch\(\)/.test(l));
    if (drainLine === -1) {
        err('PlayerScreen.onSubtitleResult does not launch the next provider after a SUCCESSFUL merge — first-hit-wins is back: the first provider to answer ends the search and the rest are never asked');
    }

    // 4. A merge is append-only, so it must start from nothing. Reusing the
    //    previous play's tracks mixes two videos' captions into one list and
    //    leaves the index pointing into the older half.
    const start = member(player, 'StartSubtitles');
    if (!start) {
        err('PlayerScreen.brs has no StartSubtitles');
    } else {
        if (!/m\.subtitleTracks\s*=\s*invalid/.test(start)) {
            err('PlayerScreen.StartSubtitles does not reset m.subtitleTracks — an append-only merge that starts from the previous play\'s list mixes two videos\' captions together and points m.subtitleIndex into the older half');
        }
        if (!/m\.subtitleIndex\s*=\s*-1/.test(start)) {
            err('PlayerScreen.StartSubtitles does not reset m.subtitleIndex — a stale index against a freshly reset track list selects whatever happens to sit at that position');
        }
    }

    // 5. The reap-before-check defect, in this handler. The result field is
    //    alwaysNotify with no value, so it also notifies while the request is
    //    still in flight; reaping on that unobserves the field and removes the
    //    node, and the real answer lands on a node nobody is watching.
    const resultAt = /result\s*=\s*task\.result/.exec(onResult);
    const reapAt = /AsyncTask_Reap\(/.exec(onResult);
    if (!resultAt) {
        err('PlayerScreen.onSubtitleResult no longer reads task.result');
    }
    if (!reapAt) {
        err('PlayerScreen.onSubtitleResult never reaps the subtitle task — a finished task node would stay in the tree for the life of the screen');
    } else if (resultAt && !/if\s+result\s*=\s*invalid\s+then\s+return/.test(onResult)) {
        err('PlayerScreen.onSubtitleResult reaps without declining an empty result — the alwaysNotify notification arrives while the request is in flight, so this destroys the real result (the same defect that ate the add-on sync result)');
    } else if (resultAt && reapAt) {
        const bail = /if\s+result\s*=\s*invalid\s+then\s+return/.exec(onResult);
        if (bail && reapAt.index < bail.index) {
            err('PlayerScreen.onSubtitleResult reaps BEFORE declining an empty result — the node is unobserved and removed while the worker is still running, so the real result can never land');
        }
    }
    return ok;
}

function checkHomeScreenContract() {
    const fs = require('fs');
    const xml = fs.readFileSync(path.join(projectRoot, 'components', 'HomeScreen.xml'), 'utf8');
    const declared = new Set(
        [...xml.matchAll(/<function\s+name="([^"]+)"\s*\/?>/gi)].map(match => match[1])
    );
    let ok = true;
    for (const fn of ['RebuildRows']) {
        if (!declared.has(fn)) {
            console.error(`HomeScreen.xml is missing <function name="${fn}" /> from its interface`);
            ok = false;
        }
    }
    return ok;
}

// DiscoverScreen and LibraryScreen embed the shared FilterBar (chips + dropdown)
// and must talk to it only through its interface: callFunc handlers for the tag
// side and the chipActivated/optionPicked observers for the events. Pin the
// interface functions the component declares and that both screens observe the
// pick events.
function checkFilterBarContract() {
    const fs = require('fs');
    const root = projectRoot;
    const xml = fs.readFileSync(path.join(root, 'components', 'FilterBar.xml'), 'utf8');
    const declared = new Set(
        [...xml.matchAll(/<function\s+name="([^"]+)"\s*\/?>/gi)].map(match => match[1])
    );
    const expected = ['SetChips', 'ShowMenu', 'HideMenu', 'FocusChips', 'FocusIsOnChips', 'IsMenuOpen'];
    let ok = true;
    for (const fn of expected) {
        if (!declared.has(fn)) {
            console.error(`FilterBar.xml is missing <function name="${fn}" /> from its interface`);
            ok = false;
        }
    }
    for (const screen of ['DiscoverScreen', 'LibraryScreen']) {
        const brs = fs.readFileSync(path.join(root, 'components', `${screen}.brs`), 'utf8');
        if (!brs.includes(`m.filterBar = m.top.FindNode("filterBar")`)) {
            console.error(`${screen}.brs does not embed the shared FilterBar (FindNode "filterBar")`);
            ok = false;
        }
        for (const observe of ['"chipActivated"', '"optionPicked"']) {
            if (!brs.includes(`ObserveField(${observe}`)) {
                console.error(`${screen}.brs does not observe filterBar.${observe} — membership/deferred picks would silently no-op`);
                ok = false;
            }
        }
    }
    return ok;
}

// The account write-back worker must keep its contract (authKey + item in,
// result out with alwaysNotify) so MainScene's pump cannot silently mismatch a
// field the task never declared. One worker serves every write-back kind
// (position, watched marks, add/remove), so this pins its interface once.
function checkLibraryPutTaskContract() {
    const fs = require('fs');
    const xml = fs.readFileSync(path.join(projectRoot, 'components', 'LibraryPutTask.xml'), 'utf8');
    const declared = {};
    for (const match of xml.matchAll(/<field\s+id="([^"]+)"([^>]*)>/gi)) {
        declared[match[1]] = match[2];
    }
    let ok = true;
    for (const field of ['authKey', 'item']) {
        if (!declared[field]) {
            console.error(`LibraryPutTask.xml is missing <field id="${field}" ... /> from its interface`);
            ok = false;
        }
    }
    if (!declared.result) {
        console.error('LibraryPutTask.xml is missing <field id="result" ... /> from its interface');
        ok = false;
    } else if (!/alwaysNotify\s*=\s*"true"/.test(declared.result)) {
        console.error('LibraryPutTask.xml: result field must be alwaysNotify="true"');
        ok = false;
    }
    return ok;
}

// The server-logout worker must keep its contract (authKey in, result out with
// alwaysNotify) so MainScene's fire-and-forget teardown cannot silently mismatch
// a field the Task never declared.
// The collection-put worker must keep its contract (authKey + payload in,
// result out with alwaysNotify) and its wire must ride the account's OWN
// entries: MainScene must serialize puts through the pump and the store's
// mirror must be the payload source, or one throwaway put erases every
// un-importable account add-on (Local Files and friends).
function checkAddonsWriteTaskContract() {
    const fs = require('fs');
    const xml = fs.readFileSync(path.join(projectRoot, 'components', 'AddonsWriteTask.xml'), 'utf8');
    const declared = {};
    for (const match of xml.matchAll(/<field\s+id="([^"]+)"([^>]*)>/gi)) {
        declared[match[1]] = match[2];
    }
    let ok = true;
    for (const field of ['authKey', 'payload']) {
        if (!declared[field]) {
            console.error(`AddonsWriteTask.xml is missing <field id="${field}" ... /> from its interface`);
            ok = false;
        }
    }
    if (!declared.result) {
        console.error('AddonsWriteTask.xml is missing <field id="result" ... /> from its interface');
        ok = false;
    } else if (!/alwaysNotify\s*=\s*"true"/.test(declared.result)) {
        console.error('AddonsWriteTask.xml: result field must be alwaysNotify="true"');
        ok = false;
    }
    const brs = fs.readFileSync(path.join(projectRoot, 'components', 'AddonsWriteTask.brs'), 'utf8');
    if (!/store\.AddonCollectionSet\(payload\.addons\)/.test(brs)) {
        console.error('AddonsWriteTask.brs must send exactly store.AddonCollectionSet(payload.addons) — that is the whole job of the worker');
        ok = false;
    }
    const mainScene = fs.readFileSync(path.join(projectRoot, 'components', 'MainScene.brs'), 'utf8');
    const mainXml = fs.readFileSync(path.join(projectRoot, 'components', 'MainScene.xml'), 'utf8');
    const writer = fs.readFileSync(path.join(projectRoot, 'components', 'AddonWriteCoordinator.brs'), 'utf8');
    if (!/sub PumpAddonWrites\(\)/.test(mainScene) || !/callFunc\("Pump"\)/.test(mainScene) || !/sub Pump\(\)/.test(writer) || !/if m\.pushing then return/.test(writer)) {
        console.error('MainScene must delegate collection puts to AddonWriteCoordinator, which must pump one AddonsWriteTask at a time — two collection sets in flight write each other stale');
        ok = false;
    }
    // Every import route lands on the same Scene gateway as AddonsScreen, so
    // a registered import reaches the account mirror before the next pull.
    const importer = fs.readFileSync(path.join(projectRoot, 'components', 'ImportCoordinator.brs'), 'utf8');
    const importMain = mainScene.match(/function ImportRegisterAddon\([^)]*\)[\s\S]*?\nend function/);
    if (!/sub AccountAddonInstalled\(/.test(mainScene) || !/m\.scene\.callFunc\("ImportRegisterAddon"/.test(importer) || !importMain || !/AccountAddonInstalled\(/.test(importMain[0])) {
        console.error('ImportCoordinator must report successful registrations through MainScene.ImportRegisterAddon and its one AccountAddonInstalled gateway — otherwise a local import is pruned by the next account sync');
        ok = false;
    }
    if (!/AddonsAccountStamp"\)\s*<>\s*m\.writeStamp/.test(writer)) {
        console.error('AddonWriteCoordinator must re-pump when AddonsAccountStamp() no longer matches the stamp it launched with — a mirror change during a set is written by a follow-up set, not by luck');
        ok = false;
    }
    for (const callback of ['ReportAddonWriteFault', 'HandleRevokedSession']) {
        if (!new RegExp(`<function\\s+name="${callback}"\\s*\\/>`).test(mainXml) || !new RegExp(`(?:sub|function) ${callback}\\(`).test(mainScene) || !new RegExp(`callFunc\\("${callback}"`).test(writer)) {
            console.error(`AddonWriteCoordinator/MainScene callback ${callback} must be defined, declared on MainScene, and called through that interface`);
            ok = false;
        }
    }
    if (!/result\.raw/.test(mainScene)) {
        console.error('MainScene.brs must adopt the pull result.raw as the mirror — filtered descriptors would rewrite the account and delete un-importable add-ons on the next set');
        ok = false;
    }
    const screen = fs.readFileSync(path.join(projectRoot, 'components', 'AddonsScreen.brs'), 'utf8');
    if (!/m\.top\.addonRemoved\s*=\s*\{/.test(screen) || !/m\.top\.addonInstalled\s*=\s*\{/.test(screen)) {
        console.error('AddonsScreen.brs must report addonRemoved/addonInstalled to MainScene — without them local changes never reach the account and the next sync resurrects them');
        ok = false;
    }
    return ok;
}

function checkLogoutTaskContract() {
    const fs = require('fs');
    const xml = fs.readFileSync(path.join(projectRoot, 'components', 'LogoutTask.xml'), 'utf8');
    const declared = {};
    for (const match of xml.matchAll(/<field\s+id="([^"]+)"([^>]*)>/gi)) {
        declared[match[1]] = match[2];
    }
    let ok = true;
    if (!declared.authKey) {
        console.error(`LogoutTask.xml is missing <field id="authKey" ... /> from its interface`);
        ok = false;
    }
    if (!declared.result) {
        console.error('LogoutTask.xml is missing <field id="result" ... /> from its interface');
        ok = false;
    } else if (!/alwaysNotify\s*=\s*"true"/.test(declared.result)) {
        console.error('LogoutTask.xml: result field must be alwaysNotify="true"');
        ok = false;
    }
    return ok;
}

// The session rows report through SettingsScreen.pushRequest (the same
// one-action channel the other screens use). Pin the field or onSettingsAction
// can never fire to start the login flow / logout confirm.
function checkSettingsPushContract() {
    const fs = require('fs');
    const xml = fs.readFileSync(path.join(projectRoot, 'components', 'SettingsScreen.xml'), 'utf8');
    const declared = new Set(
        [...xml.matchAll(/<field\s+id="([^"]+)"[\s>]/gi)].map(match => match[1])
    );
    if (declared.has('pushRequest')) return true;
    console.error('SettingsScreen.xml is missing <field id="pushRequest" ... /> from its interface');
    return false;
}

// The settings are grouped into SECTIONS: a chip per section, the rows of the
// selected one below. The grouping is the whole point — a flat list of every
// setting the app has is unreadable the moment there is more than one topic
// on it — so the parts that make it work are pinned here.
//
// None of this is visible to the test interpreter: the suite flattens the
// scripts into one program, so a screen that lost its chip row would still
// "work" in the tests and only break on the device, where the sections would
// have no way to be selected. The failure is silent either way, which is why
// it needs a pin rather than a unit test.
//
// The `active` flag is pinned with it: without it the selected section is
// told apart by the focus ring alone, and the ring answers "where am I", not
// "which section is showing" — the two come apart as soon as the user walks
// away from the chips.
function checkTorrentProfileContract() {
    const fs = require('fs');
    const read = (f) => fs.readFileSync(path.join(projectRoot, f), 'utf8');
    const screenXml = read('components/SettingsScreen.xml');
    const screen = read('components/SettingsScreen.brs');
    const taskXml = read('components/ServerSettingsTask.xml');
    const task = read('components/ServerSettingsTask.brs');
    const store = read('source/stores/ServerSettingsStore.bs');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    // Components do not share function scope, so the profile table has to be
    // included where it is used. Without the include the calls are bare-global
    // lookups that die at runtime, not at load.
    if (!/pkg:\/source\/util\/TorrentProfile\.brs/.test(screenXml)) {
        err('SettingsScreen.xml does not include source/util/TorrentProfile.brs — components do not share function scope, so TorrentProfileNext() would be a bare-global lookup that dies at runtime, not at load');
    }

    // The row has to be in the server section: the profile is a property of
    // the streaming server.
    if (!/server\s*=\s*\[[^\]]*"torrentProfile"/.test(screen)) {
        err('SettingsScreen.brs does not put the torrent profile row in the server section — the profile is a setting of the streaming server, not of the app');
    }

    // The profile is APPLIED to the server, not remembered by the Roku. A
    // row that only stored a name would look like it did something and
    // change nothing about how torrents are fetched.
    if (!/AsyncTask_Launch\([^)]*"ServerSettingsTask"[^)]*"onServerSettingsWritten"/.test(screen)) {
        err('SettingsScreen.brs never launches ServerSettingsTask to write the profile — the row would remember a name and leave the server running whatever it was running');
    }
    if (!/mode:\s*"set"/.test(screen)) {
        err('SettingsScreen.brs does not ask ServerSettingsTask to write — the profile would be read and never set');
    }
    if (!/values:\s*profile\.values/.test(screen)) {
        err('SettingsScreen.brs does not send the profile\'s own limits to the server — the write would carry something other than the profile');
    }

    // And the server is the truth: the row says what the server reports, so
    // the profile changed on another device shows up here.
    if (!/AsyncTask_Launch\([^)]*"ServerSettingsTask"[^)]*"onServerSettingsRead"/.test(screen)) {
        err('SettingsScreen.brs never asks the server what profile it is running under — the row would report the Roku\'s memory of it rather than the server\'s state');
    }
    if (!/mode:\s*"get"/.test(screen)) {
        err('SettingsScreen.brs does not ask ServerSettingsTask to read — the server\'s state would never be asked for');
    }

    // The task component: the fields are typed on the device (an array into
    // an assocarray field is a hard type mismatch) and nothing in the test
    // suite can see that, so the declaration is checked here.
    for (const field of ['address', 'mode', 'values', 'result']) {
        if (!new RegExp(`id="${field}"`).test(taskXml)) {
            err(`ServerSettingsTask.xml declares no ${field} field — the task cannot be told what to do`);
        }
    }
    if (!/id="values"\s+type="assocarray"/.test(taskXml)) {
        err('ServerSettingsTask.xml does not declare `values` as an assocarray — the profile limits are a dictionary, and the device enforces the declared type where the interpreter does not');
    }
    if (!/pkg:\/source\/stores\/ServerSettingsStore\.bs/.test(taskXml)) {
        err('ServerSettingsTask.xml does not include source/stores/ServerSettingsStore.bs — the task has no store to call, and a store is not shared between components');
    }
    if (!/mode\s*=\s*"set"/.test(task)) {
        err('ServerSettingsTask.brs does not act on the write mode — the write would be answered with a read');
    }

    // The write has to say it is JSON. The server parses the body with
    // body-parser, which only parses a body whose content type says JSON: a
    // body it does not parse is an empty object, so the settings are saved
    // unchanged and the call still answers success. The silence would be the
    // answer.
    if (!/"Content-Type":\s*"application\/json"/.test(store)) {
        err('ServerSettingsStore.bs does not send Content-Type: application/json — the server parses the body with body-parser, and a body it does not parse is an empty object, so the settings would be saved unchanged and the call would still answer success');
    }
    if (!/m\.transport\.Post\(/.test(store)) {
        err('ServerSettingsStore.bs does not POST — the server only writes its settings from a POST');
    }
    return ok;
}

function checkCacheSizeContract() {
    const fs = require('fs');
    const read = (f) => fs.readFileSync(path.join(projectRoot, f), 'utf8');
    const screenXml = read('components/SettingsScreen.xml');
    const screen = read('components/SettingsScreen.brs');
    const store = read('source/stores/ServerSettingsStore.bs');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    if (!/pkg:\/source\/util\/CacheSize\.brs/.test(screenXml)) {
        err('SettingsScreen.xml does not include source/util/CacheSize.brs');
    }

    if (!/server\s*=\s*\[[^\]]*"cacheSize"/.test(screen)) {
        err('SettingsScreen.brs does not put the cache size row in the server section');
    }

    if (!/AsyncTask_Launch\([^)]*"ServerSettingsTask"[^)]*"onServerSettingsWritten"/.test(screen)) {
        err('SettingsScreen.brs never launches ServerSettingsTask to write settings');
    }
    if (!/mode:\s*"set"/.test(screen)) {
        err('SettingsScreen.brs does not ask ServerSettingsTask to write');
    }
    if (!/"cacheSize"/.test(screen)) {
        err('SettingsScreen.brs does not write cacheSize');
    }

    if (!/CacheSizeChoices\(result\.options\)/.test(screen)) {
        err('SettingsScreen.brs does not build the choices from the server\'s options — the choices come from the server, not a fixed table');
    }

    return ok;
}


function checkSettingsSectionsContract() {
    const fs = require('fs');
    const read = (f) => fs.readFileSync(path.join(projectRoot, f), 'utf8');
    const xml = read('components/SettingsScreen.xml');
    const brs = read('components/SettingsScreen.brs');
    const chipContent = read('components/ChipContent.xml');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    if (!/id="settingsChips"/.test(xml)) {
        err('SettingsScreen.xml has no settingsChips row — the sections have no selector and the screen is a flat list again');
    }
    if (!/id="settingsChips"[\s\S]{0,600}itemComponentName="ChipTile"/.test(xml)) {
        err('SettingsScreen.xml does not render settingsChips with the ChipTile — the section row would draw as plain list cells');
    }
    if (!/id="active"/.test(chipContent)) {
        err('ChipContent.xml has no `active` field — the selected section can then only be told apart by the focus ring, which answers "where am I" and not "what is showing"');
    }
    if (!/m\.chips\s*=\s*m\.top\.FindNode\("settingsChips"\)/.test(brs)) {
        err('SettingsScreen.brs does not hold the chips row — the screen cannot switch sections without it');
    }
    if (!/ObserveField\("rowItemSelected",\s*"onChipSelected"\)/.test(brs)) {
        err('SettingsScreen.brs does not observe the chip row — pressing a section would change nothing');
    }
    if (!/item\.active\s*=/.test(brs)) {
        err('SettingsScreen.brs never marks the selected chip active — the chip row and the list below can disagree about which section is on screen');
    }
    if (!/section\s*=\s*m\.sections\[m\.activeSection\]/.test(brs)) {
        err('SettingsScreen.brs does not build the list from the selected section — the rows are flat again, so adding a setting scrambles the list');
    }

    // A visit must start from nothing remembered. The screen's fields outlive
    // OnEnter — the stack pops the screen but does not destroy it — so the
    // section and the focused row of the LAST visit are still sitting there on
    // the next entry.
    //
    // The row is the one that bites: the side panel is painted from this
    // screen's copy of the list's focus, and the copy outlives the visit
    // while the list is rebuilt from scratch and puts its cursor back on the
    // first row. The panel went on describing the row the user left on — a
    // row the cursor was not on — and corrected itself only when the cursor
    // moved. So OnEnter has to forget it, and it has to do so BEFORE the
    // rebuild: BuildRows() reads m.focusedRow to tell the list which row to
    // open on, so a reset after it would leave the list aiming at the stale
    // row and the panel still wrong.
    const subBody = (src, name) => {
        const start = new RegExp(`^[ \\t]*(?:public\\s+|private\\s+|override\\s+)*(?:sub|function)\\s+${name}\\s*\\(`, 'm').exec(src);
        if (!start) return null;
        const rest = src.slice(start.index);
        const end = rest.slice(1).search(/^[ \t]*end\s+(?:sub|function)\b/m);
        return end === -1 ? rest : rest.slice(0, end + 1);
    };
    const enter = subBody(brs, 'OnEnter');
    if (!enter) {
        err('SettingsScreen.brs has no OnEnter() — the screen cannot be entered');
    } else {
        const rowAt = /m\.focusedRow\s*=\s*-1/.exec(enter);
        const sectionAt = /m\.activeSection\s*=\s*0/.exec(enter);
        const rebuildAt = /RefreshSections\(\)/.exec(enter);
        if (!rowAt) {
            err('SettingsScreen.brs OnEnter() does not reset m.focusedRow — the screen\'s fields outlive the visit, so the panel keeps describing the row the user left on while the rebuilt list has its cursor on the first row, and the panel is wrong until the cursor moves');
        }
        if (!sectionAt) {
            err('SettingsScreen.brs OnEnter() does not reset m.activeSection — the section of the last visit outlives it, so the screen comes back on a section the user did not leave');
        }
        if (rowAt && rebuildAt && rowAt.index > rebuildAt.index) {
            err('SettingsScreen.brs OnEnter() resets m.focusedRow AFTER rebuilding the list — BuildRows() reads m.focusedRow to tell the list which row to open on, so the list would still aim at the stale row');
        }
        if (sectionAt && rebuildAt && sectionAt.index > rebuildAt.index) {
            err('SettingsScreen.brs OnEnter() resets m.activeSection AFTER rebuilding the list — the list would be built for the section of the last visit and then the screen would claim another one');
        }
    }

    // A VALUE change must not rebuild the list. Replacing a list's content
    // resets its focus to the first row, so a setting that changes was moving
    // the cursor under the user. The value is written into the row's own
    // content node instead, and the row watches that node.
    const valueChanges = brs.match(/sub (?:ToggleAudio\w+|CycleLanguage|onServerChoice)\(\)[\s\S]*?end sub/g) || [];
    for (const change of valueChanges) {
        if (/RefreshSections\(\)/.test(change)) {
            err('SettingsScreen.brs rebuilds the list when a value changes — replacing the content resets the list\'s focus to the first row, so the cursor jumps under the user. Write the value into the row\'s node instead (RefreshValues)');
        }
    }
    if (!/sub RefreshValues\(\)/.test(brs)) {
        err('SettingsScreen.brs has no RefreshValues() — a value change would have to rebuild the list, and that is what moves the cursor');
    }
    if (!/node\.description\s*=\s*RowValue\(/.test(brs)) {
        err('SettingsScreen.brs does not write the value into the row\'s content node — the row would keep showing the old value');
    }
    // The rows ARE their actions now. Reading a field off one is a type the
    // compiler cannot catch and the interpreter never runs, so it only shows
    // up on the device — as a runtime error in the middle of a repaint.
    if (/\brow\.(action|title|value)\b/.test(brs) || /m\.rows\[[^\]]*\]\.(action|title|value)/.test(brs)) {
        err('SettingsScreen.brs reads a field off a row — the rows are actions now, not records, and a string does not have fields. BrightScript cannot catch that and the interpreter never runs it, so it only shows up on the device');
    }
    if (!/m\.infoTitle\.text\s*=\s*RowLabel\(/.test(brs)) {
        err('SettingsScreen.brs does not take the panel title from RowLabel() — the panel describes the focused row, and the row is an action');
    }
    // And the row has to notice: the RowList does not re-read a content node
    // whose fields changed, so the row watches them itself.
    const prefRow = read('components/PrefRow.brs');
    if (!/ObserveField\("description"/.test(prefRow)) {
        err('PrefRow.brs does not watch the content node\'s description — a value written into the node would never reach the screen');
    }

    // The list is a ChevronList, not a plain RowList: the settings are going
    // to grow, and the chevrons are how a screen says "there is more above or
    // below" instead of letting the rows scroll away silently. The focusRow
    // field is what keeps the cursor on the row the user is working on when
    // the list is rebuilt under it.
    if (!/<ChevronList/.test(xml)) {
        err('SettingsScreen.xml does not use the ChevronList — the list is going to grow, and a plain RowList scrolls the extra rows away with nothing to say so');
    }
    if (!/<field\s+id="focusRow"/.test(read('components/ChevronList.xml'))) {
        err('ChevronList.xml has no focusRow field — a rebuild under the cursor would throw it back to the top');
    }
    if (!/m\.list\.focusRow\s*=/.test(brs)) {
        err('SettingsScreen.brs does not set the list focusRow — a rebuild under the cursor would throw it back to the top');
    }

    // The focus travel between the chips and the list. The list is a GROUP
    // now (a ChevronList), and a Group does not answer for the RowList inside
    // it: asking the group whether it has the focus always says no, so the
    // "up" from the list never reached the chips and the section switch
    // became unreachable. The list has to be asked through its own function.
    if (!/<function\s+name="HasListFocus"/.test(read('components/ChevronList.xml'))) {
        err('ChevronList.xml does not declare HasListFocus() — a screen that owns a second focusable node cannot tell whether the list has the focus');
    }
    if (!/m\.rowList\.HasFocus\(\)/.test(read('components/ChevronList.brs'))) {
        err('ChevronList.brs HasListFocus() does not ask the RowList — the group itself cannot answer for the list inside it');
    }
    if (!/callFunc\("HasListFocus"\)/.test(brs)) {
        err('SettingsScreen.brs does not ask the list whether it has the focus — Up from the list would never reach the chips, and the section switch becomes unreachable');
    }

    // The device is asked ONCE per visit to the screen. Asking again when a
    // setting is flipped put the panel back to "asking the device" for a
    // moment and rebuilt the list a second time, which is what threw the
    // cursor to the first row.
    const toggles = brs.match(/sub ToggleAudio\w+\(\)[\s\S]*?end sub/g) || [];
    if (toggles.length !== 2) {
        err('SettingsScreen.brs does not have both audio toggles — the settings the panel explains are not all there');
    }
    for (const toggle of toggles) {
        if (/StartAudioCap\(\)/.test(toggle)) {
            err('SettingsScreen.brs asks the device again when a setting is flipped — the panel falls back to "asking the device" and the list is rebuilt twice, which is what throws the cursor to the first row');
        }
    }

    // The focus correction after a content change. Replacing the content
    // resets the list's focus to the first row, and the reset lands on the
    // render pass after the one the content was set on — so a jump made at
    // that moment is undone by it. The list remembers the target and corrects
    // the focus when it lands, and does not forward the reset: a consumer
    // that watches the focused row would otherwise repaint from the row the
    // cursor is leaving.
    const chevron = read('components/ChevronList.brs');
    if (!/pendingFocus/.test(chevron)) {
        err('ChevronList.brs does not remember a pending focus — replacing the content throws the cursor to the first row and nothing puts it back');
    }
    if (!/jumpToRowItem\s*=\s*\[0,\s*target\]/.test(chevron)) {
        err('ChevronList.brs does not jump to the pending focus — the cursor stays on the first row after the list is rebuilt');
    }
    // The target has to be remembered BEFORE the content is replaced: the
    // reset can arrive while the content is still being set, and a target
    // remembered afterwards is one step too late to catch it.
    const onContent = chevron.slice(chevron.indexOf('sub onContent()'));
    const body = onContent.slice(0, onContent.indexOf('end sub'));
    if (body.indexOf('pendingFocus') > body.indexOf('m.rowList.content')) {
        err('ChevronList.brs onContent() sets the content BEFORE remembering the pending focus — the focus reset can arrive while the content is being set, and a target remembered afterwards is too late to catch it');
    }

    // The side panel: the title, the eligibility line in red, and the body.
    // The eligibility line is a warning about the DEVICE, so it is separate
    // from the sentence and it is the danger colour — a paragraph that says
    // "this device cannot use this" in the middle of the body is a paragraph
    // nobody reads.
    if (!/id="infoWarn"/.test(xml)) {
        err('SettingsScreen.xml has no infoWarn line — "this device cannot use this option" would be a sentence inside the panel body instead of a warning');
    }
    if (!/m\.infoWarn\.color\s*=\s*\w+\.danger/.test(brs)) {
        err('SettingsScreen.brs does not paint the eligibility line in the danger colour — a warning that looks like body text is not read as one');
    }
    if (!/<MultiStyleLabel/.test(xml)) {
        err('SettingsScreen.xml does not use a MultiStyleLabel for the panel body — the codec names cannot be told from the sentence around them');
    }
    if (!/drawingStyles/.test(brs)) {
        err('SettingsScreen.brs does not set the panel drawingStyles — the bold style would fall back to whatever the node defaults to');
    }
    return ok;
}

// onLibrarySyncResult calls m.libraryScreen.callFunc('RefreshRows') when the
// sync lands while the Library screen is top. Same callFunc interface trap as
// HomeScreen's RebuildRows — pin it.
function checkLibraryScreenContract() {
    const fs = require('fs');
    const xml = fs.readFileSync(path.join(projectRoot, 'components', 'LibraryScreen.xml'), 'utf8');
    const declared = new Set(
        [...xml.matchAll(/<function\s+name="([^"]+)"\s*\/?>/gi)].map(match => match[1])
    );
    let ok = true;
    for (const fn of ['RefreshRows']) {
        if (!declared.has(fn)) {
            console.error(`LibraryScreen.xml is missing <function name="${fn}" /> from its interface`);
            ok = false;
        }
    }
    return ok;
}

// Two Poster/manifest facts that are invisible in review and produce a warning
// on the device console instead of a build error.
//
// 1. loadDisplayMode is an option string with a CLOSED set of values. An
//    unrecognised one is not ignored politely; it is undefined behaviour, and
//    the Poster docs warn that an oversized texture "may fail to load". Four
//    full-screen backgrounds shipped with loadDisplayMode="scaleToCrop" —
//    which reads like a real mode and is not one of the five legal values
//    (limitSize, noScale, scaleToFit, scaleToFill, scaleToZoom). Nothing in the
//    diff looked wrong, and no test failed; the only symptom was a device-console
//    warning nobody reads.
//
// 2. ui_resolutions must name EXACTLY ONE resolution. Declaring several makes
//    Roku treat each as a distinct design target and draw it natively instead of
//    scaling, so every coordinate has to be authored for each one. This app's
//    layout is entirely hardcoded 1920x1080 (43 width/height attributes, and no
//    GetUIResolution/GetDisplaySize anywhere), so the single-canvas
//    auto-scaling in ui_resolutions=fhd is the ONLY thing making it display
//    correctly on the 720p-UI devices that are most of the range. Adding "hd"
//    renders those same 1920x1080 coordinates 1:1 on a 1280x720 canvas and every
//    element comes out 1.5x oversized — a silent, total layout failure.
//
// The Poster load-size policy, which the earlier version of this comment got
// exactly backwards. It claimed capping loadWidth/loadHeight "visibly degrades
// the artwork, which is strictly worse" and that nothing should push toward
// downscaling. Measured on a real device, both halves of that are wrong:
//
//   1. UNCAPED is what degrades artwork. Home builds a tile for every meta in
//      every catalog row — a few hundred — and add-on posters arrive at 500x750,
//      costing 500*750*4 = 1.43MB of texture each to fill a 270x405 node. Total
//      demand ran ~570MB against a budget no device has, so the memory manager
//      evicted continuously and every evicted tile refetched. That is the
//      visible symptom: posters flashing while scrolling the grid, rail icons
//      vanishing under the same pressure, and a device log full of
//      "sg.scene.bitmap.big". Capped to the node, each tile is 0.42MB.
//
//   2. The size must come from the node's own canvas dimensions, never from the
//      UI resolution. ui_resolutions=fhd means the canvas is 1920x1080 on every
//      device and Roku scales the whole canvas to whatever panel it finds. On a
//      720p-UI device that means the canvas renders at 1280x720 and the panel
//      upscales. Capping the artwork to the UI resolution — which is what
//      "Loaded texture (1920 x 1080) larger than the UI resolution (1280 x 720)"
//      appears to ask for — made it worse, not better: Roku downsampled the
//      source at load, then the canvas upscale resampled it again, and the
//      backgrounds visibly degraded. A texture the size of its node is already
//      correct there. So sg.scene.bitmap.big is a false signal on 720p devices
//      and is deliberately NOT an error here; GetUIResolution/GetDisplaySize
//      must never feed a load size, which is why that pairing is rejected above.
//
// limitSize is the only mode that caps the texture at load — the others scale at
// draw time and leave the full bitmap resident — so it is the mode to reach for.
// It preserves aspect ratio, which is why an off-ratio source decodes smaller than
// its node and leaves an uncovered strip rather than being squashed. That is
// acceptable only because every capped tile here sits over something opaque
// rather than over bare artwork (see checkPosterScalingContract). Capped tiles:
// PosterTile (2:3 tile, 2:3 posters), EpisodeTile (16:9 cell, 16:9 stills), and
// the 1:1 glyphs. EpisodeTile used to be exempt on the theory that its crop was
// load-bearing; that was weighing a cosmetic edge case against ~25-30 uncapped
// cells per season row, which is the wrong side of the ledger.
// A Poster that crops (scaleToZoom) is a promise about its source: the node shows
// the centre of the image, scaled by max(nodeW/srcW, nodeH/srcH) so it covers the
// node. When the source's aspect ratio matches the node's, that is a near-identity
// and nothing is lost. When it does not, the crop silently throws most of the
// image away — and for a gradient the surviving slice can be the one part that
// looks completely wrong.
//
// This is not hypothetical. images/mask.png was a 1918x1079 vertical alpha ramp in
// a 1920x1080 node: aspects matched to within 0.1%, so scaleToZoom was effectively
// a fit and the scrim looked right. Shrinking it to an 8x256 ramp — 8KB of texture
// instead of 8.36MB — left scaleToZoom scaling it 240x, rendering 1920x61440, and
// cropping to source rows 125.8-130.2: alpha ~247, i.e. a flat opaque black
// Episodes background. Nothing in the diff looked wrong and nothing failed to
// build; the screen just went black.
//
// The lesson is not "don't shrink the mask", it is that an asset's aspect ratio is
// load-bearing whenever the display mode crops. Two ways out, and this pins both:
//   - Give the asset the node's aspect ratio so no crop can change what is shown
//     (mask.png is now 114x64, 16:9 to within 0.2%, at 29KB instead of 8.36MB).
//   - Or pick a display mode that does not crop, when the source has no aspect
//     worth preserving. A gradient uniform along x has nothing to preserve, so
//     scaleToFill is both correct and immune to this entire class of bug.
function checkPosterLoadSizePolicy() {
    const fs = require('fs');
    const path = require('path');
    let ok = true;
    const projectRoot = path.resolve(__dirname, '..');
    const dir = path.join(projectRoot, 'components');
    const attr = (src, name) => {
        const m = new RegExp('\\b' + name + '="([^"]*)"').exec(src);
        return m ? m[1] : null;
    };
    const num = (v) => (v === null ? null : parseInt(v, 10));

    let cappedHighVolumeTile = false;

    for (const name of fs.readdirSync(dir).filter(f => f.endsWith('.xml'))) {
        const xml = fs.readFileSync(path.join(dir, name), 'utf8');

        for (const m of xml.matchAll(/<Poster\b([^>]*?)\/?>/g)) {
            const id = attr(m[1], 'id') || '(anonymous)';
            const w = num(attr(m[1], 'width'));
            const h = num(attr(m[1], 'height'));
            const lw = num(attr(m[1], 'loadWidth'));
            const lh = num(attr(m[1], 'loadHeight'));

            // A hint with only half the pair leaves the other dimension
            // uncapped, which looks correct and does not work.
            if ((lw === null) !== (lh === null)) {
                console.error(`${name}: Poster "${id}" sets only one of loadWidth/loadHeight — the other dimension stays uncapped, so the bitmap is still oversized in that axis. Set both or neither`);
                ok = false;
                continue;
            }
            if (lw === null) continue;

            // The rule the old comment got backwards, stated as an invariant:
            // a load hint may only ever match or undercut its own node. A hint
            // derived from the UI resolution (or from GetDisplaySize) lands here
            // and is rejected, which is exactly the backgrounds regression.
            if ((w !== null && lw > w) || (h !== null && lh > h)) {
                console.error(`${name}: Poster "${id}" caps its load at ${lw}x${lh}, which is LARGER than its own ${w}x${h} node — a load hint must never exceed the node it fills. Deriving the hint from the UI resolution rather than the node is what downsamples artwork twice (once at load, once in the canvas upscale) and visibly degrades it`);
                ok = false;
            }

            if (name === 'PosterTile.xml' && id === 'poster') cappedHighVolumeTile = true;
        }
    }

    // The tile behind every Home catalog row. Without its hint the grid goes
    // back to ~570MB of texture demand and the eviction/refetch cycle returns,
    // and nothing in the diff would look wrong.
    if (!cappedHighVolumeTile) {
        console.error('PosterTile.xml: the "poster" node must set loadWidth/loadHeight/limitSize. It is the component behind every Home catalog tile, and it is the one whose uncapped texture size causes the eviction and refetch cycle');
        ok = false;
    }

    // PosterTile now resizes itself from the per-row cell RowList writes into
    // its width/height interface fields (channel/tv rows are 1:1 squares). The
    // load caps must ride the node, or a square cell decodes at the XML-only
    // 270x405 hint — still one cap, but for a node that is no longer that
    // shape. Declaring the fields is what lets the tile learn its size at all.
    const tileBrs = fs.readFileSync(path.join(projectRoot, 'components', 'PosterTile.brs'), 'utf8');
    const posterTileXml = fs.readFileSync(path.join(projectRoot, 'components', 'PosterTile.xml'), 'utf8');
    if (!/<field\s+id="width"\s+type="float"[^>]*onChange="ApplyTileSize"/.test(posterTileXml) ||
        !/<field\s+id="height"\s+type="float"[^>]*onChange="ApplyTileSize"/.test(posterTileXml)) {
        console.error('PosterTile.xml must declare the RowList width/height item fields (wired to ApplyTileSize) — without them the tile never learns its per-row cell size and a square row renders the fixed 2:3 slab');
        ok = false;
    }
    if (!/m\.poster\.loadWidth\s*=\s*w/.test(tileBrs) || !/m\.poster\.loadHeight\s*=\s*h/.test(tileBrs)) {
        console.error('PosterTile.brs ApplyTileSize must resize loadWidth/loadHeight WITH width/height — a dynamically resized tile that keeps the XML-only caps decodes a texture that no longer matches its node shape');
        ok = false;
    }

    // The onChange handler is fired by the RowList writing the cell size into
    // the width/height interface fields as it CREATES the item component —
    // which happens before init() has run, so the nodes ApplyTileSize resizes
    // are not there yet. Assigning to an invalid node is a runtime error
    // (&he4), not a no-op, and it lands on the first line that touches one.
    //
    // The user sees nothing: Roku catches it in the callback, init() then runs
    // and calls ApplyTileSize() again with the cell size already in the
    // interface fields, so the tile is laid out correctly. What it costs is a
    // runtime error in the log — and Roku reports those to the developer's
    // crash dashboard, one per tile created, from other people's devices. A
    // guard that reads as "nothing happens" is easy to delete as dead code,
    // so it is pinned here: the failure is invisible in the diff, invisible in
    // the app, and only ever visible as noise someone else reports.
    if (!/if\s+m\.poster\s*=\s*invalid\s+then\s+return/.test(tileBrs)) {
        console.error('PosterTile.brs ApplyTileSize does not bail when the poster node is not there yet — the RowList writes the cell size before init() runs, so the handler resizes nodes that do not exist and dies with &he4 on every tile created');
        ok = false;
    }

    return ok;
}

// The companion-app QR on AddonsScreen. Three things are invisible until someone
// looks at the TV — or, in the third case's absence, invisible until texture
// telemetry is pulled — which is exactly why they are pinned here:
//   1. The Poster's uri must name a file that exists. A typo'd or missing pkg path
//      simply paints nothing — the same silent failure that made the QR vanish on
//      LinkStremioScreen.
//   2. loadSync must NOT be set. It was originally required, on the reasoning
//      that a bundled image has no network to wait on so there is no reason to
//      paint a frame with a hole. Device testing showed the hole is not real —
//      the panel renders correctly without it — while the stall is: loadSync
//      blocks startup on decoding a 700x700 asset for a screen most sessions
//      never open.
//
//      One thing this does NOT do, which an earlier version of this comment got
//      wrong: removing loadSync does not free the texture. A fresh-start
//      r2d2-bitmaps with loadSync already removed still showed both QRs resident
//      at 700x700 / 1,982,464 bytes each while sitting on Home. Roku eagerly
//      decodes bundled Poster textures for nodes that exist in the scene graph,
//      and every static screen exists from app start. loadSync only controls
//      whether the app *blocks* on that decode, not whether it happens. Actually
//      reclaiming those ~3.96MB means clearing the Poster's uri when the screen
//      is hidden, which is a separate change and is not implemented here — do not
//      assume otherwise from this check passing.
//   3. The image must still decode to the URL the panel copy claims it offers.
//      The encoder in scripts/gen-companion-qr.js is a hand-rolled QR
//      implementation, and a QR that looks right but will not scan is worse than
//      none at all — the version/EC table is easy to get subtly wrong in a way
//      that renders plausibly. Rather than re-implement a decoder here, the
//      encoder round-trips through a reference implementation when one is
//      available (see verify-companion-qr.js), so this check covers what is
//      cheaply checkable and points at the rest.
function checkCompanionQrContract() {
    const fs = require('fs');
    let ok = true;
    const dir = path.join(projectRoot, 'components');
    const xml = fs.readFileSync(path.join(dir, 'AddonsScreen.xml'), 'utf8');

    const posters = [...xml.matchAll(/<Poster\b([^>]*)>/g)];
    if (posters.length === 0) {
        console.error('AddonsScreen.xml: no <Poster /> — the companion-app QR is missing entirely');
        return false;
    }
    for (const m of posters) {
        const attrs = m[1];
        const id = (/\bid="([^"]*)"/.exec(attrs) || [, '(anonymous)'])[1];
        const uri = /\buri="([^"]*)"/.exec(attrs);
        if (!uri || !uri[1].trim()) {
            console.error(`AddonsScreen.xml: Poster "${id}" has no uri — it would paint nothing`);
            ok = false;
            continue;
        }
        if (!/\bpkg:\/images\//.test(uri[1])) {
            console.error(`AddonsScreen.xml: Poster "${id}" uri is not a bundled pkg:/images/ path (got "${uri[1]}"). The companion QR must ship with the app, not be fetched at runtime`);
            ok = false;
        }
        const rel = uri[1].replace(/^pkg:\//, '');
        if (!fs.existsSync(path.join(projectRoot, rel))) {
            console.error(`AddonsScreen.xml: Poster "${id}" uri "${uri[1]}" does not resolve to ${rel} on disk`);
            ok = false;
        }
        if (/\bloadSync="true"/.test(attrs)) {
            console.error(`AddonsScreen.xml: Poster "${id}" sets loadSync="true". Device testing showed the companion panel renders correctly without it, so loadSync only buys a startup stall on decoding a 700x700 asset for a screen most sessions never open. Note this does NOT reclaim texture memory either way — see the comment above for what actually would`);
            ok = false;
        }
    }

    // The generator has to keep existing alongside the image, or the asset becomes
    // an untraceable blob — the state the two donation QRs in SupportDialog are in.
    const genPath = path.join(projectRoot, 'scripts', 'gen-companion-qr.js');
    if (!fs.existsSync(genPath)) {
        console.error('scripts/gen-companion-qr.js is missing. It records what the QR encodes and regenerates it; without it images/qr-companion.png is an untraceable blob');
        ok = false;
    } else {
        const gen = fs.readFileSync(genPath, 'utf8');
        if (!/const URL\s*=\s*'https?:\/\//.test(gen)) {
            console.error('scripts/gen-companion-qr.js: expected a `const URL = \'https://...\'` holding the encoded target, so the encoded value stays greppable');
            ok = false;
        }
    }

    // The panel is decorative. If anything in it ever becomes focusable it stops
    // being an OK/Back no-op, which is the property AddonsScreen's key handling
    // depends on — so assert there is nothing there to focus.
    for (const bad of ['Button', 'RowList', 'PosterGrid', 'CheckBox', 'RadioButton', 'EditText']) {
        if (new RegExp(`<${bad}\\b`).test(xml)) {
            console.error(`AddonsScreen.xml: <${bad} /> inside the companion panel. The panel is decorative and must not add a focus stop to a screen that has exactly one (addonsList)`);
            ok = false;
        }
    }

    return ok;
}

function checkSetupServerContract() {
    const fs = require('fs');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    const setup = fs.readFileSync(path.join(projectRoot, 'source', 'util', 'SetupPage.brs'), 'utf8');
    const main = fs.readFileSync(path.join(projectRoot, 'source', 'main.brs'), 'utf8');
    const sceneBrs = fs.readFileSync(path.join(projectRoot, 'components', 'MainScene.brs'), 'utf8')
        .split('\n').map(line => line.split("'")[0]).join('\n');
    const sceneXml = fs.readFileSync(path.join(projectRoot, 'components', 'MainScene.xml'), 'utf8');
    const addonsBrs = fs.readFileSync(path.join(projectRoot, 'components', 'AddonsScreen.brs'), 'utf8');
    const addonsXml = fs.readFileSync(path.join(projectRoot, 'components', 'AddonsScreen.xml'), 'utf8');

    // The pure helper layer and the socket lifecycle live in one file; the
    // socket layer is never exercised by tests, so its API surface has to stay
    // pinned here for main.brs to compile against.
    for (const fn of ['SetupServerStart', 'SetupServerPoll', 'SetupServerClose', 'SetupServerPort', 'SetupLanAddress']) {
        if (!new RegExp(`function ${fn}\\s*\\(|sub ${fn}\\s*\\(`).test(setup)) {
            err(`SetupPage.brs has no ${fn}() — source/main.brs calls it and the device has no fallback`);
        }
    }

    // The listener must register on the SCREEN's message port, or the Wait loop
    // would never receive a roSocketEvent for it.
    if (!/listener\.SetMessagePort\s*\(\s*port\s*\)/.test(setup)) {
        err('SetupPage.brs SetupServerStart must SetMessagePort(port) on the listener — the socket events have to land on the same port Wait() drains');
    }
    // ...and every exit path in Main() must close it. Three returns exist:
    // the exitApp poll fallback, the screen-closed event, and the exitApp node
    // event. A return with no close leaves the listener bound for the session.
    const exits = [...main.matchAll(/^[ \t]*return$/gm)];
    if (exits.length < 3) {
        err(`source/main.brs has only ${exits.length} return(s) in Main — expected the three exit paths`);
    } else {
        for (const m of exits) {
            const before = main.slice(0, m.index).trimEnd().split('\n').pop();
            if (!/SetupServerClose\s*\(/.test(before)) {
                err('source/main.brs returns without SetupServerClose(setup) on every exit path — the port stays bound and the loop is gone');
            }
        }
    }
    if (!/Type\(message\)\s*=\s*"roSocketEvent"/.test(main) || !/SetupServerPoll\s*\(/.test(main)) {
        err('source/main.brs must dispatch roSocketEvent into SetupServerPoll — without it accepted connections sit in the listen backlog forever');
    }

    // The Scene handoff is via callFunc, which only works for DECLARED
    // interface functions — an undeclared one silently no-ops on device while
    // passing the (mocked) interpreter. Pin the declarations to the calls.
    const declaredScene = new Set(
        [...sceneXml.matchAll(/<function\s+name="([^"]+)"\s*\/?>/gi)].map(m => m[1])
    );
    for (const fn of ['ShowSetupAddress', 'ImportFromSetup']) {
        if (!declaredScene.has(fn)) {
            err(`MainScene.xml is missing <function name="${fn}" /> from its interface`);
        }
    }
    if (!new RegExp(`sub ShowSetupAddress\\s*\\(`).test(sceneBrs) || !new RegExp(`function ImportFromSetup\\s*\\(`).test(sceneBrs)) {
        err('MainScene.brs must define ShowSetupAddress() and ImportFromSetup() — main() and the setup page call them');
    }
    const importCoordinatorBrs = fs.readFileSync(path.join(projectRoot, 'components', 'ImportCoordinator.brs'), 'utf8');
    const importCoordinatorXml = fs.readFileSync(path.join(projectRoot, 'components', 'ImportCoordinator.xml'), 'utf8');
    if (!new RegExp(`ImportFromSetup\\s*\\([^)]*\\)\\s*[\\s\\S]*\\nend function`).test(sceneBrs) || !/callFunc\("StartImport"/.test(sceneBrs) || !/callFunc\("StartImport"/.test(sceneBrs.match(/sub HandleDeepLink[\s\S]*?\nend sub/)?.[0] || '')) {
        err('MainScene must route both setup-page and deep-link imports through ImportCoordinator.StartImport — they share one busy slot');
    }
    for (const fn of ['SetScene', 'IsBusy', 'StartImport']) {
        if (!new RegExp(`<function\\s+name="${fn}"\\s*\\/>`).test(importCoordinatorXml) || !new RegExp(`(?:sub|function) ${fn}\\(`).test(importCoordinatorBrs)) {
            err(`ImportCoordinator must define and declare ${fn} for its component boundary`);
        }
    }
    for (const fn of ['ImportRegisterAddon', 'ImportFinished']) {
        if (!declaredScene.has(fn) || !new RegExp(`(?:sub|function) ${fn}\\(`).test(sceneBrs)) {
            err(`MainScene must define and declare ${fn}, the ImportCoordinator callback interface`);
        }
    }
    if (!/AsyncTask_Launch\(m\.top,\s*"AddonsInstallTask",\s*"onInstallResult"/.test(importCoordinatorBrs) || !/m\.scene\.callFunc\("ImportFinished",\s*summary\)/.test(importCoordinatorBrs)) {
        err('ImportCoordinator must own the sequential install task and return its plain summary to MainScene');
    }

    const declaredAddons = new Set(
        [...addonsXml.matchAll(/<function\s+name="([^"]+)"\s*\/?>/gi)].map(m => m[1])
    );
    if (!declaredAddons.has('SetSetupAddress')) {
        err('AddonsScreen.xml is missing <function name="SetSetupAddress" /> from its interface');
    }
    if (!/sub SetSetupAddress\s*\(/.test(addonsBrs)) {
        err('AddonsScreen.brs must define SetSetupAddress() — the Scene forwards the address into it');
    }
    for (const id of ['setupHint', 'setupUrl']) {
        if (!new RegExp(`id="${id}"[^>]*>`, 's').test(addonsXml)) {
            err(`AddonsScreen.xml has no label id="${id}" — the page address has nowhere to show`);
        }
    }

    // The port is one fact with two consumers (the TV that prints it, the
    // listener that binds it); a second literal anywhere would let the two
    // drift. And 8324 is verboten — that is the reference app's port.
    if (!/\b8744\b/.test(setup)) {
        err('SetupPage.brs must serve SetupServerPort()=8744 — see the comment there');
    }
    if (/\b8324\b/.test(setup) || /\b8324\b/.test(main)) {
        err('port 8324 is the reference app\'s port and must not be reused');
    }

    return ok;
}

// The details screen must hand the stream picker the add-on CONTENT type
// verbatim. channel/tv (and any future type) items only resolve when the
// stream request is keyed by the real type: a literal "movie"/"series" sends a
// live-TV add-on a /stream/movie/{id}.json it does not answer, and the user
// gets "No streams found". A literal here is a functional break, not cosmetics.
function checkDetailsMetaTypeContract() {
    const fs = require('fs');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };
    const details = fs.readFileSync(path.join(projectRoot, 'components', 'DetailsScreen.brs'), 'utf8');

    const literal = details.match(/metaType:\s*"(movie|series)"/);
    if (literal) {
        err(`DetailsScreen.brs passes a literal metaType "${literal[1]}" — a considered-kind item of another type would resolve /stream/{wrongType}/{id}.json and an add-on that routes on type would answer nothing`);
    }

    const passThrough = details.match(/metaType:\s*m\.meta\.type/g);
    if (!passThrough || passThrough.length < 2) {
        err('DetailsScreen.brs must pass metaType: m.meta.type on every streamsScreen push (PlayMedia and ResumeEpisode) — the content type has to reach the /stream/ endpoint verbatim');
    }

    return ok;
}

// Stream format is resolved in PlaybackStore now, not sniffed in the player, so
// one path serves a direct URL and a torrent and the store tests can reach it.
// FormatFromUrl strips a URL's query before sniffing the path extension, and
// only then reads a filename hidden in the query itself. The method-form InStr
// is zero-based, so the correct chop is Left(queryIndex) (everything up to the
// '?'). Left(queryIndex - 1) would also eat the last path character: URLs like
// ".../stream.mp4?token=x" would lose their format and the Video node would
// start the classic format-less black screen.
function checkStreamFormatQueryContract() {
    const fs = require('fs');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };
    const store = fs.readFileSync(path.join(projectRoot, 'source', 'stores', 'PlaybackStore.bs'), 'utf8');
    const player = fs.readFileSync(path.join(projectRoot, 'components', 'PlayerScreen.brs'), 'utf8');

    const block = /function FormatFromUrl[\s\S]*?end function/.exec(store);
    if (!block) {
        err('PlaybackStore.bs has no FormatFromUrl() — ResolvePlayback depends on the sniffed streamFormat');
        return ok;
    }
    if (block[0].includes('Left(queryIndex - 1)')) {
        err('PlaybackStore.bs FormatFromUrl chops the query one character early (Left(queryIndex - 1)) — the zero-based InStr index is where the "?" sits, so the correct chop is Left(queryIndex)');
    }
    if (!block[0].includes('Left(queryIndex)')) {
        err('PlaybackStore.bs FormatFromUrl no longer strips the query with Left(queryIndex) — query-bearing stream URLs get no streamFormat');
    }

    // The resolved format has to reach the Video node, and the player must not
    // re-sniff it: two detectors drift, and an unset streamFormat defaults to MP4.
    if (!/result\.streamFormat\s*=\s*m\.StreamFormat\(/.test(store)) {
        err('PlaybackStore.bs ResolvePlayback never sets result.streamFormat from StreamFormat() — the player is handed nothing to declare');
    }
    if (/function\s+DetectStreamFormat\s*\(/.test(player)) {
        err('PlayerScreen.brs still defines DetectStreamFormat() — PlaybackStore owns stream-format detection now, so the player must consume the resolved value');
    }
    if (!/StartPlayback\(\s*result\.url\s*,\s*result\.streamFormat\s*\)/.test(player)) {
        err('PlayerScreen.brs does not forward result.streamFormat into StartPlayback — the Video node would fall back to the default MP4 container');
    }

    return ok;
}

function checkChannelCwPolicyContract() {
    const fs = require('fs');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };
    const store = fs.readFileSync(path.join(projectRoot, 'source', 'stores', 'LibraryStore.bs'), 'utf8');
    const host = fs.readFileSync(path.join(projectRoot, 'components', 'StoreHost.brs'), 'utf8');
    const player = fs.readFileSync(path.join(projectRoot, 'components', 'PlayerScreen.brs'), 'utf8');

    // A live channel has no resume point, so it must never become a
    // continue-watching entry: not from local playback, and not from the
    // account's library on a linked session. One shared predicate keeps every
    // gate honest; a stray literal at any one of the four gates resurrects the
    // entries through the others.
    const predicate = /function IsChannelType\(metaType as string\) as boolean[\s\S]*?(channel|tv)[\s\S]*?return true[\s\S]*?return false[\s\S]*?end function/.exec(store);
    if (!predicate) {
        err('LibraryStore.bs has no IsChannelType() predicate — the policy needs one shared test for "channel"/"tv" so the player gates and the sync filter cannot drift');
    }

    const setGate = store.includes('if m.IsChannelType(metaType) then return');
    if (!setGate) {
        err('LibraryStore.bs SetPosition does not early-return on channel/tv — local playback would push a live channel onto the continue-watching stack');
    }

    const syncFilter = /parsed\.cw and not m\.IsChannelType\(parsed\.metaType\)/.exec(store);
    if (!syncFilter) {
        err('LibraryStore.bs SyncFromStremio no longer excludes channel/tv items from the cw stack — a linked session would surface the account\'s live-channel entries in Continue Watching');
    }

    const bridge = host.includes('function LibraryIsChannelType(metaType as string) as boolean');
    if (!bridge) {
        err('StoreHost.brs has no LibraryIsChannelType bridge — the player cannot call the shared predicate through m.stores.library');
    }

    const gate = /LibraryIsChannelType", metaType\)\s+then return/;
    const save = /sub SavePosition[\s\S]*?end sub/.exec(player);
    const publish = /sub PublishWatchState[\s\S]*?end sub/.exec(player);

    // The gate reads params.metaType, so params must be assigned FIRST. Grepping
    // for the gate alone cannot catch the reverse order: reading .metaType off
    // an uninitialized local throws &hec ("Dot operator attempted with invalid
    // BrightScript Component or interface reference") BEFORE the gate runs, so
    // the guard never executes and the throw unwinds Back out of the handler —
    // the app freezes with no crash and no position ever saved. This is exactly
    // how a live channel "lost Back" after a play had really started.
    const paramsBeforeGate = (block) => {
        const assign = block.indexOf('params = m.playParams');
        const use = block.indexOf('LibraryIsChannelType');
        return assign !== -1 && use !== -1 && assign < use;
    };
    if (!save || !gate.test(save[0])) {
        err('PlayerScreen.brs SavePosition no longer returns early for channel/tv — leaving a live channel would record a meaningless resume point');
    } else if (!paramsBeforeGate(save[0])) {
        err('PlayerScreen.brs SavePosition references params before assigning it — reading params.metaType off an uninitialized local throws &hec and freezes the app before the channel gate can run (assign params = m.playParams first)');
    }
    if (!publish || !gate.test(publish[0])) {
        err('PlayerScreen.brs PublishWatchState no longer returns early for channel/tv — a paused live channel would publish a position the account push turns into a continue-watching entry');
    } else if (!paramsBeforeGate(publish[0])) {
        err('PlayerScreen.brs PublishWatchState references params before assigning it — same &hec trap seen in SavePosition (assign params = m.playParams first)');
    }

    return ok;
}

function checkMetaFieldCoercionContract() {
    const fs = require('fs');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };
    const details = fs.readFileSync(path.join(projectRoot, 'components', 'DetailsScreen.brs'), 'utf8');
    const player = fs.readFileSync(path.join(projectRoot, 'components', 'PlayerScreen.brs'), 'utf8');

    // Roku refuses to cast an explicitly-passed invalid into a typed `as string`
    // parameter — a default only fills in when the argument is OMITTED. poster and
    // posterShape are absent on many add-ons, so feeding m.meta.<field> (or
    // params.<field>) straight across the typed LibraryAddSaved/LibrarySetPosition
    // boundary throws &h18 on device and freezes the tap. @rokucommunity/brs coerces
    // leniently and never reproduces it, so pin the call sites here: the optional
    // args must be pre-normalized locals, never raw field accesses.
    const addLine = (details.match(/.*callFunc\("LibraryAddSaved".*/) || [''])[0];
    if (addLine.includes('m.meta.poster')) {
        err('DetailsScreen.brs passes m.meta.poster/posterShape straight into LibraryAddSaved — an invalid (missing) field casts to a typed string param and throws &h18 on device');
    }
    if (!details.includes('if m.meta.poster <> invalid then')) {
        err('DetailsScreen.brs no longer normalizes m.meta.poster before LibraryAddSaved — an absent poster would crash the save');
    }
    if (!details.includes('if m.meta.posterShape <> invalid then')) {
        err('DetailsScreen.brs no longer normalizes m.meta.posterShape before LibraryAddSaved — the common no-shape case crashes the save');
    }
    // The play-param pushes carry m.meta.poster/posterShape inside an AA on purpose
    // (the player normalizes before its typed SetPosition), so only the write-back
    // packet is a typed boundary: MainScene feeds change.poster into
    // LibraryBuildLibraryChangeItem(poster as string), so it must be the local.
    const packet = (details.match(/m\.top\.libraryChange\s*=\s*\{[\s\S]*?\}/) || [''])[0];
    if (packet.includes('poster: m.meta.poster')) {
        err('DetailsScreen.brs publishes poster: m.meta.poster in the libraryChange packet — MainScene feeds it into the typed LibraryBuildLibraryChangeItem and a missing poster throws &h18 on device; send the normalized local instead');
    }

    const setLine = (player.match(/.*callFunc\("LibrarySetPosition".*/) || [''])[0];
    if (setLine.includes('params.poster')) {
        err('PlayerScreen.brs passes params.poster/posterShape straight into LibrarySetPosition — normalize a missing field to "" first');
    }
    if (!player.includes('if params.posterShape <> invalid then')) {
        err('PlayerScreen.brs no longer normalizes params.posterShape before LibrarySetPosition — a title with no shape crashes the position save');
    }

    return ok;
}

function checkStreamTypeGateContract() {
    const fs = require('fs');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };
    const streams = fs.readFileSync(path.join(projectRoot, 'components', 'StreamsScreen.brs'), 'utf8');
    const store = fs.readFileSync(path.join(projectRoot, 'source', 'stores', 'AddonsStore.bs'), 'utf8');
    const host = fs.readFileSync(path.join(projectRoot, 'components', 'StoreHost.brs'), 'utf8');
    const hostXml = fs.readFileSync(path.join(projectRoot, 'components', 'StoreHost.xml'), 'utf8');

    // Provider selection must mirror Stremio's Manifest::is_resource_supported:
    // a single id-aware predicate checks the "stream" resource together with the
    // media type AND the video id against the add-on's declared types and
    // idPrefixes. The old two-step resource+type gate is gone — an id-agnostic
    // gate would ask "tt"/"kitsu" add-ons for YouTube ids and vice versa.
    const load = /sub LoadStreams[\s\S]*?end sub/.exec(streams);
    if (!load) {
        err('StreamsScreen.brs has no LoadStreams() — the provider build is where the resource match has to be applied');
        return ok;
    }
    const gate = /AddonsSupportsResource"\s*,\s*addon\.resources\s*,\s*addon\.types\s*,\s*addon\.idPrefixes\s*,\s*"stream"\s*,\s*ParamString\(params\.metaType\)\s*,\s*ParamString\(params\.videoId\)/.exec(load[0]);
    if (!gate) {
        err('StreamsScreen.brs LoadStreams does not gate providers on AddonsSupportsResource(addon.resources, addon.types, addon.idPrefixes, "stream", metaType, videoId) — add-ons that cannot serve this media would be queried');
    } else if (load[0].indexOf('providers.Push') !== -1 && load[0].indexOf('AddonsSupportsResource') > load[0].indexOf('providers.Push')) {
        err('StreamsScreen.brs LoadStreams evaluates the resource gate after providers.Push — a provider pushed before the check is still queried, so the filter has no effect');
    }

    // The predicate itself: it must distinguish short from full resources (short
    // inherits the manifest filters), apply the type gate, and defer the id match
    // to MatchesIdPrefixes — the three ways this could silently degrade to "ask
    // everyone".
    const supports = /function SupportsResource\([\s\S]*?end function/.exec(store);
    if (!supports) {
        err('AddonsStore.bs has no SupportsResource() — the resource/id matcher that mirrors stremio-core is missing');
    } else {
        if (!/m\.MatchesIdPrefixes\(/.test(supports[0])) {
            err('AddonsStore.bs SupportsResource() no longer matches ids against the add-on idPrefixes — a "tt"/"kitsu" add-on would be asked for any id');
        }
        if (!/short/.test(supports[0])) {
            err('AddonsStore.bs SupportsResource() no longer distinguishes short from full resources — a short "stream" would not inherit the manifest types/idPrefixes');
        }
        if (!/m\.HasType\(/.test(supports[0])) {
            err('AddonsStore.bs SupportsResource() no longer applies the type gate — a live-TV add-on would be asked for movie/series streams');
        }
    }
    const prefixes = /function MatchesIdPrefixes\([\s\S]*?end function/.exec(store);
    if (!prefixes || !/Left\(/.test(prefixes[0])) {
        err('AddonsStore.bs MatchesIdPrefixes() no longer compares by prefix — the id filter would never match anything');
    }

    // Both install paths must persist idPrefixes, or the matcher always sees
    // "any id" and the per-id filter is inert.
    if (!/idPrefixes: m\.DeclaredList\(json\.idPrefixes\)/.test(store)) {
        err('AddonsStore.bs Install no longer stores the manifest idPrefixes — the id filter would silently pass every id');
    }
    if (!/idPrefixes: m\.DeclaredList\(manifest\.idPrefixes\)/.test(store)) {
        err('AddonsStore.bs InstallFromDescriptor no longer stores the manifest idPrefixes — the id filter would silently pass every id');
    }

    const hasType = /function HasType\(types as dynamic, metaType as string\) as boolean[\s\S]*?channel[\s\S]*?tv[\s\S]*?return false[\s\S]*?end function/.exec(store);
    if (!hasType) {
        err('AddonsStore.bs HasType() no longer treats channel/tv as one family — a "tv"-typed live add-on would be dropped for channel media (and vice versa)');
    }

    if (!host.includes('function AddonsSupportsResource(resources as dynamic, types as dynamic, idPrefixes as dynamic, name as string, metaType as string, id as string) as boolean')) {
        err('StoreHost.brs has no AddonsSupportsResource bridge — StreamsScreen cannot reach the store predicate through m.stores.addons');
    }
    if (!/<function name="AddonsSupportsResource" \/>/.test(hostXml)) {
        err('StoreHost.xml is missing <function name="AddonsSupportsResource" /> — callFunc against an undeclared interface function is a silent no-op that returns invalid, which would read as "matches nothing"');
    }

    return ok;
}

// Discover browses every installed add-on, not just Cinemeta. The failure mode
// this guards is a silent regression to the built-in catalog: a hardcoded
// cinemeta id/address, a chart slotted back in, or a task fed a pre-built extra
// string that skips genre encoding. It also pins that the shared source
// resolution (CatalogSourcesTask + the AddonsCatalogCapabilities/Title bridges)
// is actually wired, since a missing StoreHost declaration is a silent no-op.
function checkDiscoverSourcesContract() {
    const fs = require('fs');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };
    const read = (...p) => fs.readFileSync(path.join(projectRoot, ...p), 'utf8');

    const screen = read('components', 'DiscoverScreen.brs');
    const taskXml = read('components', 'DiscoverLoaderTask.xml');
    const task = read('components', 'DiscoverLoaderTask.brs');
    const sourcesTask = read('components', 'CatalogSourcesTask.brs');
    const sourcesXml = read('components', 'CatalogSourcesTask.xml');
    const host = read('components', 'StoreHost.brs');
    const hostXml = read('components', 'StoreHost.xml');

    if (/com\.linvo\.cinemeta/.test(screen)) {
        err('DiscoverScreen.brs still hardcodes the Cinemeta add-on id — Discover must browse every installed catalog add-on');
    }
    if (/\bCatalogId\s*\(/.test(screen) || /imdbRating/.test(screen)) {
        err('DiscoverScreen.brs still maps a chart to a hardcoded catalog id — Discover takes its catalog from the selected source');
    }
    if (!/AsyncTask_Launch\(m\.top,\s*"CatalogSourcesTask"/.test(screen) || !/onSourcesLoaded/.test(screen)) {
        err('DiscoverScreen.brs does not resolve sources through CatalogSourcesTask/onSourcesLoaded');
    }
    if (!/AddonsCatalogCapabilities"\s*,\s*descriptor/.test(screen) || !/\.feed\b/.test(screen)) {
        err('DiscoverScreen.brs does not gate catalogs on AddonsCatalogCapabilities(...).feed');
    }
    if (!/m\.selectedCatalog\.address/.test(screen) || !/m\.selectedCatalog\.rawType/.test(screen)) {
        err('DiscoverScreen.brs does not fetch against the selected catalog (m.selectedCatalog.address/rawType)');
    }
    if (!/genre:\s*GenreFilter\(\)/.test(screen)) {
        err('DiscoverScreen.brs does not pass a raw genre to DiscoverLoaderTask');
    }

    if (!/<field id="genre" type="string"/.test(taskXml) || /<field id="extra"/.test(taskXml)) {
        err('DiscoverLoaderTask.xml must expose a raw genre field and no pre-built extra field');
    }
    if (!/http\.EncodeQueryValue\(m\.top\.genre\)/.test(task)) {
        err('DiscoverLoaderTask.brs must percent-encode the manifest-sourced genre before it becomes a URL segment');
    }

    if (!/for each addon in m\.top\.addons/.test(sourcesTask)) {
        err('CatalogSourcesTask.brs does not walk m.top.addons');
    }
    if (!/catalog\.Manifest\(addon\.address\)/.test(sourcesTask)) {
        err('CatalogSourcesTask.brs never fetches a manifest for add-ons whose registry entry has no catalogs');
    }
    if (!/<script[^>]*CatalogStore\.bs/.test(sourcesXml) || !/<script[^>]*Transport\.bs/.test(sourcesXml)) {
        err('CatalogSourcesTask.xml is missing the Transport/CatalogStore scripts it instantiates');
    }
    if (!/<field id="result" type="assocarray" alwaysNotify="true"\s*\/>/.test(sourcesXml)) {
        err('CatalogSourcesTask.xml result field must be assocarray alwaysNotify');
    }

    if (!host.includes('function AddonsCatalogCapabilities(catalog as dynamic) as object')) {
        err('StoreHost.brs has no AddonsCatalogCapabilities bridge');
    }
    if (!host.includes('function AddonsCatalogTitle(catalog as dynamic, addonName as dynamic) as string')) {
        err('StoreHost.brs has no AddonsCatalogTitle bridge');
    }
    if (!/<function name="AddonsCatalogCapabilities" \/>/.test(hostXml) || !/<function name="AddonsCatalogTitle" \/>/.test(hostXml)) {
        err('StoreHost.xml is missing the AddonsCatalogCapabilities/AddonsCatalogTitle declarations — an undeclared callFunc is a silent no-op returning invalid');
    }

    return ok;
}

// Search queries every installed add-on, not just Cinemeta. The failure mode
// this guards is a silent regression to the built-in single-address search: a
// hardcoded cinemeta id/address, rows keyed by media type instead of catalog
// descriptor, a Details push fed one shared address, or a task that only asks
// the default "top" catalog. It also pins the shared source resolution, the
// per-catalog task loop, and the dynamic rows: only catalogs that return
// results may occupy a row (nothing is premade for loading or empty catalogs).
function checkMultiAddonSearchContract() {
    const fs = require('fs');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };
    const read = (...p) => fs.readFileSync(path.join(projectRoot, ...p), 'utf8');

    const screen = read('components', 'SearchScreen.brs');
    const screenXml = read('components', 'SearchScreen.xml');
    const task = read('components', 'SearchLoaderTask.brs');
    const taskXml = read('components', 'SearchLoaderTask.xml');
    const store = read('source', 'stores', 'CatalogStore.bs');

    if (/com\.linvo\.cinemeta|cinemetaAddress/.test(screen)) {
        err('SearchScreen.brs still hardcodes the Cinemeta add-on — Search must fan out to every installed search-capable catalog');
    }
    if (/metaType: "movie"|RowForType/.test(screen)) {
        err('SearchScreen.brs still builds rows by media type — Search is one row per search-capable catalog, not grouped by type');
    }

    if (!/AsyncTask_Launch\(m\.top,\s*"CatalogSourcesTask"/.test(screen) || !/onSourcesLoaded/.test(screen)) {
        err('SearchScreen.brs does not resolve sources through CatalogSourcesTask/onSourcesLoaded — sources would never resolve for add-ons the registry has no catalogs for');
    }
    if (!/m\.pendingQuery\s*=/.test(screen) || !/FlushPendingQuery/.test(screen)) {
        err('SearchScreen.brs does not hold a query that arrives before sources land (m.pendingQuery/FlushPendingQuery)');
    }

    if (!/caps = m\.stores\.addons\.callFunc\("AddonsCatalogCapabilities", descriptor\)/.test(screen) || !/not caps\.search then continue for/.test(screen)) {
        err('SearchScreen.brs does not gate rows on AddonsCatalogCapabilities(...).search — every catalog would be queried, including ones that declare no search extra');
    }
    if (!/AddonsCatalogTitle"\s*,\s*descriptor/.test(screen)) {
        err('SearchScreen.brs row titles no longer derive from the catalog descriptor (AddonsCatalogTitle)');
    }
    if (!/"\|"\s*\+\s*descriptor\.type\s*\+\s*"\|"\s*\+\s*descriptor\.id/.test(screen)) {
        err('SearchScreen.brs row keys no longer derive from addonKey|rawType|catalogId — a task result cannot be fanned into its row by key');
    }
    if (!/" - "\s*\+\s*TypeSearchLabel\(descriptor\.type\)/.test(screen)) {
        err('SearchScreen.brs row titles are no longer "{Catalog} - {mediaType}"');
    }
    // The wording itself is a word of the table now; what the check holds is
    // that the channel/tv family is still SPELLED OUT rather than left as
    // the raw add-on type.
    if (!/return (Lang\("search", "tvChannel"\)|"Tv channel")/.test(screen)) {
        err('SearchScreen.brs does not spell the channel/tv media family "Tv channel" in search rows');
    }
    if (!/titleCounts\[c\.title\]\s*>\s*1/.test(screen)) {
        err('SearchScreen.brs no longer prefixes the add-on name when two catalogs would still collide after the title is built');
    }

    if (/loadState|PlaceholderTitle/.test(screen)) {
        err('SearchScreen.brs still builds placeholder/premade rows — empty or loading catalogs must not occupy a row; rows appear only with results');
    }
    if (!/m\.landed\[/.test(screen) || !/RebuildRows/.test(screen) || !/m\.searchOrder/.test(screen)) {
        err('SearchScreen.brs does not park landed metas by key and rebuild rows from the discovery order (m.landed/RebuildRows/m.searchOrder) — rows cannot be built dynamically from results');
    }

    if (!/addonAddress: target\.addonAddress/.test(screen)) {
        err('SearchScreen.brs onResultSelected does not push the row\'s own addonAddress — every result would open against one shared address');
    }

    if (!/AsyncTask_Launch\(m\.top,\s*"SearchLoaderTask"/.test(screen) || !/m\.searchTasks\[addonKey\] = task/.test(screen)) {
        err('SearchScreen.brs does not spawn one SearchLoaderTask per add-on keyed by addonKey');
    }

    if (!/for each cat in m\.top\.catalogs/.test(task)) {
        err('SearchLoaderTask.brs does not iterate the catalogs array it was handed — it would only ever search one catalog per add-on');
    }
    if (!/catalog\.Search\(m\.top\.addonAddress,\s*cat\.type,\s*m\.top\.query,\s*cat\.id\)/.test(task)) {
        err('SearchLoaderTask.brs does not pass each catalog\'s own id to CatalogStore.Search — every search would hit the default "top" catalog');
    }
    const catches = (task.match(/catch e/g) || []).length;
    if (catches < 2) {
        err('SearchLoaderTask.brs has no per-catalog try/catch — one bad catalog answer would kill the rest of that add-on\'s sections');
    }
    if (!/sections\.Push\(section\)/.test(task)) {
        err('SearchLoaderTask.brs no longer publishes a section per requested catalog');
    }

    if (!/<field id="catalogs" type="array"/.test(taskXml) || !/<field id="addonKey" type="string"/.test(taskXml)) {
        err('SearchLoaderTask.xml is missing the catalogs/addonKey fields the screen passes');
    }
    if (/<field id="metaType"/.test(taskXml)) {
        err('SearchLoaderTask.xml still exposes metaType — the task is per add-on, not per media type');
    }
    if (!/<field id="result" type="assocarray" alwaysNotify="true"\s*\/>/.test(taskXml)) {
        err('SearchLoaderTask.xml result field must be assocarray alwaysNotify — without it a second landing with the same shape is not observed');
    }

    if (!/function Search\(addonAddress as string, metaType as string, query as string, catalogId = "top" as string\)/.test(store)) {
        err('CatalogStore.Search no longer takes a catalogId argument defaulting to "top" — search fan-out cannot target a non-default catalog');
    }

    if (!/type="assocarray" alwaysNotify="true"/.test(screenXml)) {
        err('SearchScreen.xml pushRequest must be assocarray alwaysNotify');
    }

    return ok;
}

function checkPosterScalingContract() {
    const fs = require('fs');
    let ok = true;
    const LEGAL = ['limitSize', 'noScale', 'scaleToFit', 'scaleToFill', 'scaleToZoom'];
    const dir = path.join(projectRoot, 'components');

    for (const name of fs.readdirSync(dir).filter(f => f.endsWith('.xml'))) {
        const xml = fs.readFileSync(path.join(dir, name), 'utf8');
        for (const m of xml.matchAll(/<Poster\b([^>]*)>/g)) {
            const mode = /\bloadDisplayMode="([^"]*)"/.exec(m[1]);
            if (mode && !LEGAL.includes(mode[1])) {
                const id = (/\bid="([^"]*)"/.exec(m[1]) || [, '(anonymous)'])[1];
                console.error(`${name}: Poster "${id}" sets loadDisplayMode="${mode[1]}", which is not one of ${LEGAL.join(' / ')}. An unrecognised scaling option is undefined behaviour, and the Poster docs warn the image may then fail to load outright`);
                ok = false;
            }
        }
    }

    return ok;
}

// BrightScript exposes Left/Right/Mid/Trim/InStr as roString METHOD forms (the
// codebase relies on these, e.g. source/util/SetupPage.brs), but UCase/LCase are
// only GLOBAL functions — roString has no .UCase()/.LCase() member at all.
// DiscoverScreen's and SearchScreen's type-label fallbacks capitalized a declared
// catalog type with `key.Left(1).UCase() + key.Mid(1)`. Every known type
// (movie/series/channels) returned before that line, so it looked correct until an
// add-on declared a custom catalog type ("sports") and the line threw &hf4
// "Member function not found", killing DiscoverScreen on load. Pin the whole
// class: never chain a non-existent method onto a string.
function checkStringMethodContract() {
    const fs = require('fs');
    const path = require('path');
    let ok = true;
    const roots = [path.join(projectRoot, 'components'), path.join(projectRoot, 'source')];
    const bad = /\.\s*(UCase|LCase)\s*\(/i;

    const walk = (dir) => {
        for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
            const full = path.join(dir, entry.name);
            if (entry.isDirectory()) { walk(full); continue; }
            if (!/\.(brs|bs)$/.test(entry.name)) continue;
            const src = fs.readFileSync(full, 'utf8');
            const m = bad.exec(src);
            if (m) {
                const line = src.slice(0, m.index).split('\n').length;
                console.error(`${path.relative(projectRoot, full)}:${line} calls .${m[1]}(...) as a string method — roString has no UCase/LCase member; they are global functions, so this throws &hf4 the first time the line runs. Wrap the argument instead: ${m[1]}(value)`);
                ok = false;
            }
        }
    };
    for (const root of roots) walk(root);

    return ok;
}

// The theme migration moved every painted color into theme.reads in init()
// plus script includes, because XML color attributes cannot call code. One
// failure mode would slip past the interpreter: a component calling
// Theme()/AppPalette() without including Theme.bs — a bare-global lookup that
// dies at runtime, not at load. (Hardcoded colors are a style choice, not a
// bug, so they are deliberately not policed here.)
function checkThemeContract() {
    const fs = require('fs');
    const components = fs.readdirSync(path.join(projectRoot, 'components')).filter(f => f.endsWith('.xml'));
    let ok = true;
    for (const name of components) {
        const xml = fs.readFileSync(path.join(projectRoot, 'components', name), 'utf8');
        const brsPath = path.join(projectRoot, 'components', name.replace(/\.xml$/, '.brs'));
        if (fs.existsSync(brsPath)) {
            const brs = fs.readFileSync(brsPath, 'utf8');
            if (/Theme\(|AppPalette\(/.test(brs) && !/Theme\.bs/.test(xml)) {
                console.error(`${name}.xml must include <script uri="pkg:/source/core/Theme.bs"> — its .brs calls Theme()/AppPalette()`);
                ok = false;
            }
        }
    }
    return ok;
}

// The theme contract above pins the same failure for Theme.bs, and it is worth
// stating why it has to be static: Roku scopes user-defined global functions PER
// COMPONENT, so StringOf() in a .brs whose XML does not include Helpers.brs
// resolves to invalid at runtime — "Member function not found", the first time
// the line runs, i.e. the first title an add-on mislabels. The interpreter
// concatenates every file into one scope and cannot model this, so a green
// suite proves nothing about the includes. Pin them.
//
// The missing include is one failure mode. The other is a fork: a screen
// re-declaring its own coercion (as DetailsScreen did with a local ToString),
// which drifts from the fixed version and quietly stops covering the device's
// "ro" spellings for JSON values. One copy lives in Helpers.brs; everything
// else calls it.
function checkStringOfContract() {
    const fs = require('fs');
    const dir = path.join(projectRoot, 'components');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    for (const file of fs.readdirSync(dir).filter((f) => f.endsWith('.brs'))) {
        const src = fs.readFileSync(path.join(dir, file), 'utf8');
        const code = src.split('\n').map((line) => line.split("'")[0]).join('\n');
        if (!/\b(StringOf|Fill|Lang|RefreshTexts)\s*\(/.test(code)) continue;
        const xml = fs.readFileSync(path.join(dir, file.replace(/\.brs$/, '.xml')), 'utf8');
        if (!/pkg:\/source\/util\/Helpers\.brs/.test(xml)) {
            err(`${file} calls a Helpers.brs global (StringOf/Fill/Lang/RefreshTexts) but does not include <script uri="pkg:/source/util/Helpers.brs"> — a per-component global resolves to invalid without the include and the screen dies at runtime, and the interpreter cannot see it`);
        }
    }

    // The fork check, and the crash-site pins: each coercion below was a live
    // throw (Type Mismatch on a non-string add-on value) before StringOf, so a
    // regression that re-reads the raw field must fail here rather than on a
    // device with a badly-typed add-on installed.
    const details = fs.readFileSync(path.join(dir, 'DetailsScreen.brs'), 'utf8');
    const detailsCode = details.split('\n').map((line) => line.split("'")[0]).join('\n');
    if (/^[ \t]*function\s+ToString\s*\(/m.test(detailsCode)) {
        err('DetailsScreen.brs re-declares its own ToString() coercion — one copy lives in source/util/Helpers.brs, and a local fork stops covering the device\'s "ro" type spellings for parsed JSON values');
    }
    if (!/StringOf\(meta\.imdbRating\)/.test(detailsCode)) {
        err('DetailsScreen.brs no longer coerces meta.imdbRating through StringOf — an add-on answering the rating with a number throws Type Mismatch while building the header line');
    }
    const episodes = fs.readFileSync(path.join(dir, 'EpisodesScreen.brs'), 'utf8').split('\n').map((line) => line.split("'")[0]).join('\n');
    if (!/StringOf\(ep\.name\)/.test(episodes)) {
        err('EpisodesScreen.brs no longer coerces ep.name through StringOf — an add-on answering an episode name with a number throws in EpisodeLabel');
    }
    const streams = fs.readFileSync(path.join(dir, 'StreamsScreen.brs'), 'utf8').split('\n').map((line) => line.split("'")[0]).join('\n');
    if (!/StringOf\(stream\.name\)/.test(streams)) {
        err('StreamsScreen.brs no longer coerces stream.name through StringOf — StreamLabel calls .Trim() on it, which throws on a non-string add-on name');
    }
    if (!/StringOf\(params\.episodeName\)/.test(streams)) {
        err('StreamsScreen.brs no longer coerces params.episodeName — the header line concatenates it');
    }
    const addons = fs.readFileSync(path.join(dir, 'AddonsScreen.brs'), 'utf8').split('\n').map((line) => line.split("'")[0]).join('\n');
    if (!/StringOf\(addon\.address\)/.test(addons)) {
        err('AddonsScreen.brs no longer coerces addon.address through StringOf — the built-in prefix is concatenated onto it');
    }

    return ok;
}

// The strings that stay in a migrated file, and why.
//
// The fault strip is plumbing diagnostics about the app's own internals —
// "the store host did not answer AddonsGetAll" — and it stays in ONE
// language by decision: a fault line that changes with the UI language is
// harder to grep in a bug report and harder to match against a log. The
// dialogs around them are prose for the user, and those are translated.
//
// The rest are not words on screen at all: the platform's own contract
// values, and the words a measurement prints. The list is explicit and
// global on purpose: every English-by-decision string in the app is in one
// place, so the decision is visible and cannot grow by accident.
const ENGLISH_BY_DECISION = [
    // Screen.brs — the store hand-off probe
    'store fault: no store host reached this screen',
    'store fault: the store host did not answer AddonsGetAll',
    'store fault: the store is live but reports no add-ons',
    // The save-failed fault, reported by the Settings screen and the import
    'settings could not be saved',
    // MainScene — the add-on mirror and the sync pump
    "the account's add-on list is unknown; the ",
    ' was not synced',
    ' add-on(s) absent from the account',
    ' add-ons were rejected',
    ', already had ',
    ', rejected ',
    'addon already installed',
    'addon change failed: ',
    'addon sync failed: ',
    'addon sync: ',
    'addon sync: the account reported no add-ons',
    'addon sync: the worker finished with no result (stage: ',
    'unknown error',
    '[addons] collection put landed',
    '[addons] sync landed — registered ',
    '[addons] sync pruned ',
    '[addons] sync worker finished with NO result (stage: ',
    // The Player's platform contract, in the platform's words. These are not
    // words on screen: they are the values the Video node's caption-mode field
    // takes, and the fragments of the platform's own error text the player
    // recognises. Both are English by definition.
    'On',
    'Off',
    'no playable tracks',
    'not supported'
];

// The files whose user-visible words come from the table. Each wave adds its
// screen here, and the fault vocabulary above is the only thing left over.
const MIGRATED_FILES = [
    'components/Screen.brs',
    'components/SettingsScreen.brs',
    'components/MainScene.brs',
    'components/HomeScreen.brs',
    'components/AddonsScreen.brs',
    'components/LibraryScreen.brs',
    'components/DetailsScreen.brs',
    'components/EpisodesScreen.brs',
    'components/StreamsScreen.brs',
    'components/PlayerScreen.brs',
    'components/DiscoverScreen.brs',
    'components/SearchScreen.brs',
    'components/AuthScreen.brs',
    'components/LinkStremioScreen.brs'
];

// The string literals of a BrightScript file, comments excluded. The comment
// strip this codebase uses elsewhere (everything after an apostrophe) is not
// good enough here: an apostrophe inside a string is a word, not a comment.
function stringLiterals(src) {
    const out = [];
    let i = 0;
    let inString = false;
    let inComment = false;
    let buf = '';
    while (i < src.length) {
        const c = src[i];
        if (inComment) {
            if (c === '\n') inComment = false;
            i++;
            continue;
        }
        if (inString) {
            if (c === '\\') { buf += src[i + 1]; i += 2; continue; }
            if (c === '"') { inString = false; out.push(buf); buf = ''; i++; continue; }
            buf += c;
            i++;
            continue;
        }
        if (c === "'") { inComment = true; i++; continue; }
        if (c === '"') { inString = true; buf = ''; i++; continue; }
        i++;
    }
    return out;
}

// A migrated file may not carry user-visible words of its own any more:
// every word on screen comes from the table. Two rules catch a copy that was
// pasted back in, and they catch different shapes:
//
//  1. A literal with a space and a word in it is a sentence. The only ones
//     allowed are the English-by-decision strings (ENGLISH_BY_DECISION): the
//     fault lines (diagnostics), the platform's own contract values, and the
//     words a measurement prints.
//  2. A literal that IS a word of the table is a translated string that was
//     hardcoded back — the shape a space-check would miss, because "Cancel",
//     "Language" and "Unknown" are single words.
//
// The identifiers a component needs (node ids, callFunc names, task names,
// table keys) have no space and are not words of the table, so they pass
// untouched.
function checkNoUntranslatedLiterals() {
    const fs = require('fs');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    const table = JSON.parse(fs.readFileSync(path.join(projectRoot, 'source', 'util', 'texts.json'), 'utf8'));
    const values = new Set();
    for (const lang of Object.keys(table)) {
        for (const section of Object.keys(table[lang])) {
            for (const key of Object.keys(table[lang][section])) {
                const value = table[lang][section][key];
                for (const one of (Array.isArray(value) ? value : [value])) values.add(one);
            }
        }
    }

    for (const file of MIGRATED_FILES) {
        const src = fs.readFileSync(path.join(projectRoot, file), 'utf8');
        // A literal on a print line is a console trace, not a word on screen:
        // the traces are how the player and the diagnostics narrate what they
        // are doing, and they are read in a log, next to the device console.
        // They are English by nature — a trace is a debugging tool, not copy.
        const printed = new Set();
        for (const line of src.split('\n')) {
            if (!/\bprint\b/.test(line)) continue;
            for (const m of line.matchAll(/"([^"]*)"/g)) printed.add(m[1]);
        }
        // A KEY PRESS name is the platform's, not ours: `if key = "OK"` names
        // the remote's button, and the remote's buttons are not translated.
        // The convention in this codebase is that the key-press variable is
        // called "key", and a literal compared against it is the platform's
        // spelling of a button.
        const keyNames = new Set();
        for (const line of src.split('\n')) {
            for (const m of line.matchAll(/\bkey\s*=\s*"([^"]*)"/g)) keyNames.add(m[1]);
        }
        for (const lit of stringLiterals(src)) {
            if (ENGLISH_BY_DECISION.includes(lit)) continue;
            if (printed.has(lit) || keyNames.has(lit)) continue;
            if (values.has(lit)) {
                err(`${file} hard-codes ${JSON.stringify(lit)} — that string is a word of the table, and a copy here is a string the language change cannot reach. Use Lang()`);
                continue;
            }
            if (lit.includes(' ') && /[A-Za-z]{3,}/.test(lit)) {
                err(`${file} carries the literal ${JSON.stringify(lit)} — user-visible words come from the table (Lang); the fault lines are the only exception and they are listed in ENGLISH_BY_DECISION`);
            }
        }
    }
    return ok;
}

// The Episodes build must stay series-wide at the component boundary. One
// EpisodesStore.SeriesData call groups the videos and builds their bitfield
// order; one LibraryStore.EpisodeMarksForSeries call decodes the bitfield once
// and answers all seasons. Reintroducing either per-season call restores the
// exact 39x full-meta/list copying cost that measured as six seconds on The
// Simpsons.
function checkEpisodeSeriesBatchContract() {
    const fs = require('fs');
    const read = (file) => fs.readFileSync(path.join(projectRoot, file), 'utf8');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    const screen = read('components/EpisodesScreen.brs');
    const buildStart = screen.indexOf('sub BuildList(meta as object)');
    const buildEnd = buildStart < 0 ? -1 : screen.indexOf('\nend sub', buildStart);
    if (buildStart < 0 || buildEnd < 0) {
        err('EpisodesScreen.brs has no BuildList() — the series episode rows have no build path');
        return false;
    }
    const build = screen.slice(buildStart, buildEnd);
    if (!/callFunc\("EpisodesSeriesData"/.test(build)) {
        err('EpisodesScreen.BuildList() does not gather series data in one EpisodesSeriesData call');
    }
    if (!/callFunc\("LibraryEpisodeMarksForSeries"/.test(build)) {
        err('EpisodesScreen.BuildList() does not request watched marks in one series-wide call');
    }
    for (const oldCall of ['EpisodesEpisodesForSeason', 'LibraryEpisodeMarks"']) {
        if (build.includes(oldCall)) {
            err(`EpisodesScreen.BuildList() still calls ${oldCall} per season — the full meta/list would cross the component boundary once for every season`);
        }
    }

    const episodeStore = read('source/stores/EpisodesStore.bs');
    const seriesStart = episodeStore.indexOf('function SeriesData(');
    const seriesEnd = seriesStart < 0 ? -1 : episodeStore.indexOf('end function', seriesStart);
    if (seriesStart < 0 || seriesEnd < 0) {
        err('EpisodesStore has no SeriesData() query — the series meta would be re-scanned per season');
    } else {
        const seriesData = episodeStore.slice(seriesStart, seriesEnd);
        if ((seriesData.match(/for each video in meta\.videos/g) || []).length !== 1) {
            err('EpisodesStore.SeriesData() must group the videos in one pass over meta.videos');
        }
        if (/EpisodesForSeason\(|OrderedVideoIds\(/.test(seriesData)) {
            err('EpisodesStore.SeriesData() calls an old per-season/repeated-scan helper instead of deriving groups and ids from the grouped data');
        }
    }

    const library = read('source/stores/LibraryStore.bs');
    const marksStart = library.indexOf('function EpisodeMarksForSeries(');
    const marksEnd = marksStart < 0 ? -1 : library.indexOf('end function', marksStart);
    if (marksStart < 0 || marksEnd < 0) {
        err('LibraryStore has no EpisodeMarksForSeries() batch — the bitfield decode would return to per-season calls');
    } else {
        const marks = library.slice(marksStart, marksEnd);
        const decode = marks.indexOf('AccountWatchedSet(');
        const loop = marks.indexOf('for each seasonRun in seasonRuns');
        if (decode < 0 || loop < 0 || decode > loop) {
            err('LibraryStore.EpisodeMarksForSeries() must decode the account watched set before walking the season runs');
        }
        if (loop >= 0 && marks.slice(loop).includes('AccountWatchedSet(')) {
            err('LibraryStore.EpisodeMarksForSeries() decodes the bitfield inside the season loop — it must be one decode for the series');
        }
    }

    return ok;
}

// The UI-language table (source/util/texts.json), read on screen through
// Lang("section", "key"). Three static guarantees hold every translation up:
//
//  1. The table parses at all. On device a broken file degrades to an empty
//     table and every label paints its key — self-diagnosing, never blank —
//     but the diagnosis only works if it fires HERE, before a bad edit ships.
//  2. Language parity: every language carries exactly the same section/key
//     tree as English, and no value is empty. The lookup chain treats an
//     empty value as a miss, so a blank copy is a broken row even though the
//     key exists — parity is what makes a translation "present".
//  3. Every literal Lang("section", "key") call site resolves in EVERY
//     language. A mistyped key self-diagnoses on screen as "section.key";
//     this check cuts the diagnosis from "on the TV" to "in npm test".
function checkI18nContract() {
    const fs = require('fs');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    let table;
    try {
        table = JSON.parse(fs.readFileSync(path.join(projectRoot, 'source', 'util', 'texts.json'), 'utf8'));
    } catch (e) {
        err(`source/util/texts.json does not parse (${e.message}) — the device answers an empty table and every label would paint its key`);
        return false;
    }
    if (!/source\/\*\*\/\*\.\*/.test(fs.readFileSync(path.join(projectRoot, 'bsconfig.json'), 'utf8'))) {
        err('bsconfig.json no longer stages source/**/*.* — texts.json would be missing from the device package and every label would paint its key');
    }

    const flat = (lang) => {
        const out = {};
        const slice = table[lang] || {};
        for (const section of Object.keys(slice)) {
            const body = slice[section] || {};
            for (const key of Object.keys(body)) {
                out[section + '.' + key] = true;
            }
        }
        return out;
    };
    // Every value is a word, not a gap: Lang() treats an empty value as a
    // miss, so a blank copy is a broken row even though the key exists. A
    // value may also be a LIST of words (the month names), which the same
    // rule applies to, element by element.
    for (const lang of Object.keys(table)) {
        const slice = table[lang] || {};
        for (const section of Object.keys(slice)) {
            for (const key of Object.keys(slice[section] || {})) {
                const value = slice[section][key];
                const values = Array.isArray(value) ? value : [value];
                for (const one of values) {
                    if (typeof one !== 'string' || one.length === 0) {
                        err(`texts.json ${lang}.${section}.${key} is not a non-empty string — Lang() treats an empty value as a miss, so the label falls through to English even though the key exists`);
                    }
                }
            }
        }
    }
    // The placeholders inside a string are part of it: a language that drops
    // {soft} or renames it paints the token itself, in the user's language, on
    // the screen. The token set is therefore as much a part of the contract as
    // the words around it.
    const tokensOf = (lang) => {
        const out = {};
        const slice = table[lang] || {};
        for (const section of Object.keys(slice)) {
            for (const key of Object.keys(slice[section] || {})) {
                const value = slice[section][key];
                if (typeof value !== 'string') continue;
                out[section + '.' + key] = [...value.matchAll(/\{([A-Za-z_]+)\}/g)].map((m) => m[1]).sort().join(',');
            }
        }
        return out;
    };
    if (!Array.isArray(Object.keys(table)) || Object.keys(table).length < 2) {
        err('texts.json carries fewer than two languages — en is the fallback chain\'s floor, and a second is where wave-1 translations live');
    }
    for (const lang of Object.keys(table)) {
        if (lang !== 'en') {
            const base = flat('en');
            const mine = flat(lang);
            for (const key of Object.keys(base)) {
                if (!mine[key]) err(`texts.json ${lang} is missing ${key} — Lang() would fall through to English for every screen carrying it`);
            }
            for (const key of Object.keys(mine)) {
                if (!base[key]) err(`texts.json ${lang} has extra key ${key} — English carries none, so the parity between the two languages the fallback relies on has drifted`);
            }
            const baseTokens = tokensOf('en');
            const myTokens = tokensOf(lang);
            for (const key of Object.keys(baseTokens)) {
                if (myTokens[key] !== undefined && myTokens[key] !== baseTokens[key]) {
                    err(`texts.json ${lang}.${key} fills placeholders {${myTokens[key]}} where English fills {${baseTokens[key]}} — the token a language drops or renames is painted literally on the screen`);
                }
            }
        }
    }

    // The literal call sites. Every component in the phase that has migrated
    // speaks Lang(); any literal call must resolve against the whole table.
    const known = {};
    for (const lang of Object.keys(table)) Object.assign(known, flat(lang));
    for (const file of fs.readdirSync(path.join(projectRoot, 'components')).filter((f) => f.endsWith('.brs'))) {
        const code = fs.readFileSync(path.join(projectRoot, 'components', file), 'utf8')
            .split('\n').map((line) => line.split("'")[0]).join('\n');
        for (const m of code.matchAll(/\bLang\(\s*"([A-Za-z]+)"\s*\+\s*"([A-Za-z]+)"\s*\)/g)) {
            err(`${file} builds a Lang() key at runtime ("${m[1]}" + "${m[2]}") — say the whole key at the call site so this check can hold it up`);
        }
        for (const m of code.matchAll(/\bLang\(\s*"([A-Za-z]+)"\s*,\s*"([A-Za-z]+)"/g)) {
            const ref = m[1] + '.' + m[2];
            if (!known[ref]) {
                err(`${file} calls Lang("${m[1]}", "${m[2]}") but no language of texts.json carries ${ref} — the label would paint its key on the screen`);
            }
        }
        // Lang() answers ONE string. A third argument is silently dropped, and
        // with it the values a template needs — the call would paint the
        // template's own "{count}" placeholder on the screen.
        for (const m of code.matchAll(/\bLang\(\s*"[^"]*"\s*,\s*"[^"]*"\s*,/g)) {
            err(`${file} calls Lang() with a third argument — Lang(section, key) answers one string; a template with placeholders needs Fill(Lang(...), { ... })`);
        }
    }

    return ok;
}

// The other half of checkStringOfContract, and the reason the stores do NOT use
// the coercion the components use: Roku scopes user-defined global functions PER
// COMPONENT, and a bare global call inside a method body resolves against the
// component that INVOKED the method, not the file the method came from. Store
// files are shared by many components (StoreHost's bridges, the loader tasks,
// the screens) and their methods are invoked from all of them, so a StringOf()
// in source/stores is "attempted call of a non-function" the first time any
// component other than the one that happened to construct the store runs that
// line. LibraryStore's WatchedCodec note and the AddonsStore file header are
// where that rule is written down, and it is why a shared store helper is not
// just "not idiomatic" — it cannot be called at all from a store method.
//
// What stores do instead: each owns a four-line, intrinsic-only predicate
// (GetInterface-based, so it never depends on how a runtime spells a parsed JSON
// value: "Float" vs "roFloat" is exactly the divergence that makes Type()
// ladders unusable) and every comparison or stored field goes through it. The
// predicates are knowingly duplicated per store, exactly like HasKey already is,
// because the platform leaves no way to share one. Two questions are asked:
// HasText  — is this text with something in it (ids, names, dates, anything that
//            is stored or passed on as a string)
// HasValue — is this a value at all (the hero fields; a NUMBER counts, because
//            the hero renders it through StringOf, and so does an object, which
//            is why MergeMeta keeps Cinemeta's `links`)
function checkStoreAddonValueContract() {
    const fs = require('fs');
    const dir = path.join(projectRoot, 'source', 'stores');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };
    // Comments out, definitions out: what is left is the code that runs.
    const definition = /(?:private\s+|public\s+)?(?:function|sub)\s+[A-Za-z_][A-Za-z0-9_]*\s*\(/gi;
    // Comments out (the pins below match code, not prose).
    const code = (file) => fs.readFileSync(path.join(dir, file), 'utf8')
        .split('\n').map((line) => line.split("'")[0]).join('\n');
    // ...and definitions out, for the global-call scan only: a store DEFINING a
    // method must not read as it CALLING one.
    const calls = (file) => code(file).replace(definition, '(');

    // 1. No store file may call a Helpers.brs global. This is the failure the
    //    device would show as "attempted call of a non-function" in whichever
    //    screen invoked the store method, and no interpreter test can see it.
    //    Deliberately scoped to Helpers.brs: these are the two coercions the
    //    components share, and they are what a store reaching for a formatting
    //    helper would grab. Transport is the one store that does call globals of
    //    its own file (PercentEncode, CreateSyncHttpClient, ...) and that is safe
    //    only because every component that invokes a Transport method also lists
    //    Transport.bs — an arrangement this check does not police.
    const helpers = fs.readFileSync(path.join(projectRoot, 'source', 'util', 'Helpers.brs'), 'utf8');
    const helperFns = [...helpers.matchAll(/^function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/gm)].map((m) => m[1]);
    if (helperFns.length === 0) {
        err('tests/run.js could not find a single function in source/util/Helpers.brs — the store/global check below would pass vacuously');
    }
    for (const file of fs.readdirSync(dir).filter((f) => f.endsWith('.bs'))) {
        const src = calls(file);
        for (const fn of helperFns) {
            if (new RegExp(`(^|[^.A-Za-z0-9_])${fn}\\s*\\(`).test(src)) {
                err(`source/stores/${file} calls ${fn}() — a user-defined global resolves against the scope of the component that invoked the method, so this is a call of a non-function from any other component; ask an m-reachable predicate instead`);
            }
        }
    }

    // 2. The crash-site pins. Every site below was a live throw on a device
    //    before its guard: a raw add-on value compared with `=`/`<>` against a
    //    string, or a string method called on one. A regression that reads the
    //    field raw again must fail here rather than on a device with a
    //    badly-typed add-on installed.
    const mustCall = [
        ['EpisodesStore.bs', /function HasValue\(value as dynamic\) as boolean/, 'EpisodesStore.bs no longer defines HasValue() — the hero-field/MergeMeta guard is gone and a numeric rating would be compared raw again'],
        ['EpisodesStore.bs', /function HasText\(value as dynamic\) as boolean/, 'EpisodesStore.bs no longer defines HasText() — the id/type guard is gone'],
        ['EpisodesStore.bs', /if not m\.HasText\(meta\.id\) then return false/, 'EpisodesStore.NeedsMetaFetch no longer guards meta.id — a non-string id reaches a URL and a typed argument'],
        ['EpisodesStore.bs', /if not m\.HasValue\(meta\[field\]\) then return true/, 'EpisodesStore.NeedsMetaFetch no longer asks HasValue for its hero fields — the imdbRating-8.1 crash site is back'],
        ['EpisodesStore.bs', /if m\.HasValue\(provided\[key\]\) then merged\[key\] = provided\[key\]/, 'EpisodesStore.MergeMeta no longer asks HasValue before letting a provided value win — a container field (Cinemeta `links`) would be compared to "" and throw'],
        ['TimeUtil.bs', /if m\.HasText\(ep\.released\) then dateStr = ep\.released/, 'TimeUtil no longer guards ep.released — an add-on answering a date with a number throws Type Mismatch out of the caller'],
        ['TimeUtil.bs', /m\.HasText\(ep\.firstAired\) then dateStr = ep\.firstAired/, 'TimeUtil no longer guards ep.firstAired — same crash through the fallback field'],
        ['CatalogStore.bs', /if not m\.HasText\(json\.id\) or not m\.HasText\(json\.name\)/, 'CatalogStore.Manifest no longer guards the manifest identity — a non-text id/name is compared raw and then stored as a Float'],
        ['AddonsStore.bs', /kind = "roAssociativeArray" and m\.HasText\(resource\.name\)/, 'AddonsStore.NormalizeResources no longer guards resource.name — a non-text resource name is stored raw and compared later'],
        ['AddonsStore.bs', /if m\.HasText\(resource\.name\) and resource\.name = name then return true/, 'AddonsStore.HasResource no longer guards the resource name'],
        ['AddonsStore.bs', /if not m\.HasText\(declared\) then continue for/, 'AddonsStore.HasType no longer skips a non-text declared type — it would be compared against the wanted type and throw'],
        ['AddonsStore.bs', /if m\.HasText\(extra\.name\) then name = extra\.name/, 'AddonsStore.CatalogCapabilities no longer guards the extra name — a numeric extra name is compared against "search"/"genre"/"skip" and throws'],
        ['AddonsStore.bs', /if not m\.HasText\(json\.id\) or not m\.HasText\(json\.name\)/, 'AddonsStore.Install no longer guards the manifest identity'],
        ['AddonsStore.bs', /not m\.HasText\(manifest\.id\) or not m\.HasText\(manifest\.name\)/, 'AddonsStore.InstallFromDescriptor no longer guards the manifest identity'],
        ['AddonsStore.bs', /if not m\.HasText\(transportUrl\)/, 'AddonsStore.InstallFromDescriptor no longer guards transportUrl — a non-text descriptor URL is put through string methods (BaseFromManifestUrl/Split)'],
        ['AddonsStore.bs', /if record = invalid or not m\.HasText\(record\.id\) then return false/, 'AddonsStore.Register no longer guards record.id'],
        ['PlaybackStore.bs', /url = m\.AsText\(stream\.url\)/, 'PlaybackStore.ResolvePlayback no longer reads stream.url through AsText — Trim on a non-string add-on value throws out of the play handler'],
        ['PlaybackStore.bs', /return m\.AsText\(stream\.infoHash\)/, 'PlaybackStore.StreamInfoHash no longer reads stream.infoHash through AsText — ToStr on a container throws'],
        ['SubtitlesStore.bs', /if not m\.HasText\(track\.lang\) then return ""[\s\S]*?return LCase\(track\.lang\.Trim\(\)\)/, 'SubtitlesStore.TrackLang no longer guards track.lang — Trim/Lcase on a non-string add-on value throws out of the player'],
        ['SubtitlesStore.bs', /function HasText\(value as dynamic\) as boolean/, 'SubtitlesStore.bs no longer defines HasText()'],
    ];
    for (const [file, pattern, message] of mustCall) {
        if (!pattern.test(code(file))) err(message);
    }

    const mustNotMatch = [
        ['EpisodesStore.bs', /if\s+meta\[field\]\s*(<>|=)\s*""/, 'EpisodesStore.bs compares a hero field to "" raw again — that is the "Type Mismatch. Operator \'=\' can\'t be applied to \'roFloat\' and \'String\'" crash; use m.HasValue'],
        ['EpisodesStore.bs', /if\s+meta\.(id|type)\s*(<>|=)\s*""/, 'EpisodesStore.bs compares meta.id/meta.type to "" raw again — use m.HasText'],
        ['TimeUtil.bs', /if\s+ep\.(released|firstAired)\s*(<>|=)\s*""/, 'TimeUtil.bs compares a date field to "" raw again — an add-on answering one with a number throws; use m.HasText'],
        ['CatalogStore.bs', /if\s+json\.(id|name)\s*(<>|=)\s*""/, 'CatalogStore.bs compares the manifest identity to "" raw again — use m.HasText'],
        ['PlaybackStore.bs', /stream\.(url|infoHash)\s*\.\s*(Trim|ToStr|LCase|UCase)\s*\(/, 'PlaybackStore.bs calls a string method on a raw stream field again — Trim/ToStr on a number or a container throws; use m.AsText'],
        ['SubtitlesStore.bs', /if\s+track\.lang\s*<>\s*invalid\s+and\s+track\.lang\.Trim\(\)/, 'SubtitlesStore.bs calls Trim on the raw track.lang again — a non-string lang throws out of the player; use m.HasText first'],
    ];
    for (const [file, pattern, message] of mustNotMatch) {
        if (pattern.test(code(file))) err(message);
    }

    return ok;
}

// The add-on JSON boundary contract.
//
// Add-on payloads are the one input this app does not control, and the crash
// this contract grew out of was not a logic bug: Cinemeta answers imdbRating
// with the JSON NUMBER 8.1, EpisodesStore compared it to "", and `8.1 = ""` is
// "Type Mismatch. Operator '=' can't be applied to 'roFloat' and 'String'" —
// thrown straight out of the Details screen, with an add-on installed that the
// suite had never seen. source/util/AddonJson.brs is the fix: every payload is
// walked once at ingress and the fields the app reads as text are coerced, so
// the reads downstream are string-to-string. This check is what keeps the two
// halves from drifting apart, and it has to be static for one blunt reason: the
// interpreter reproduces NONE of it — @rokucommunity/brs evaluates `8.1 = ""`
// to false where the device throws — so a suite that only runs code cannot see
// this class of bug at all.
//
// Three properties, one per way the arrangement can rot:
//
//   1. The include. A store method that calls NormalizeAddonJson resolves the
//      name against the scope of the component that INVOKED it, so every
//      component that can invoke an add-on-facing store must list AddonJson.brs
//      itself. Missing here, the device shows "attempted call of a non-function"
//      in whichever screen asked.
//
//   2. The ingress call. Each store must still call NormalizeAddonJson where its
//      payload enters — a refactor that drops one leaves a whole endpoint
//      un-normalized and the reads it feeds raw again. Pinned per function, so
//      the call cannot drift to some other method and still pass.
//
//   3. The table. Every field the code reads as text — compared with =/<>/</>,
//      handed to a string method, concatenated to a string, or written into a
//      node's text/uri field — must be named in AddonJson's text table, or be a
//      field this app fills itself (the exception list below, each with the
//      reason it is not add-on JSON). This is the property that would have
//      caught the original bug: imdbRating was compared to "" and the field was
//      not a text field, and nothing in the suite said so.
//
// Why an AST and not regexes: the real-world shape was `meta[field] = ""` over a
// local `fields = [...]` list, which no reasonable regex can follow, and the
// test runner already depends on brighterscript (bsc transpiles the sources, and
// this file already builds the ProgramBuilder). Parser.parse is therefore free —
// no new dependency, and no device time.
//
// The honest limits, so nobody trusts this further than it goes: it knows field
// NAMES, not values, so it cannot tell a payload record from one we built; it
// does not follow values through function returns or across a component
// boundary; and it only reads the receiver roots below. That is deliberate — the
// roots are where add-on payloads actually live in this codebase, and widening
// them to every local would drown the real findings in our own state fields
// (m.sessionType, poster.loadStatus, parse.kind — all typed by us).
const ADDON_PAYLOAD_ROOTS = [
    'meta', 'stream', 'track', 'ep', 'video', 'addon', 'catalog', 'manifest',
    'entry', 'resource', 'extra', 'hints', 'json', 'descriptor', 'provided',
    'fetched', 'c', 'subtitles', 'sources'
];

// Names the scan finds in a text read that are NOT add-on JSON — each one is a
// field this app writes itself, so there is no add-on that can hand us a number
// for it. Keyed by field name (the granularity the normalizer's opt-in table
// uses), with the reason kept here so the next reader does not have to re-derive
// it. A name that is add-on JSON must go in the table instead: that is the whole
// point of the check, and it fails both ways the moment a real payload field is
// listed here by mistake... which is to say: read the reason before adding one.
const ADDON_TEXT_READ_EXCEPTIONS = {
    address: 'our own record field — the transport base derived from a URL the app validated, never an add-on manifest value',
    metaId: 'our own library/progress record field (Stremio API + our own writes), not an add-on meta field',
    addonName: 'our own key on the catalog descriptor the app builds; the value is addon.name, which IS in the table'
};

function checkAddonJsonContract() {
    const fs = require('fs');
    const { Parser, WalkMode } = require('brighterscript');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    // The tables live in the normalizer, so read them from there — the check and
    // the runtime cannot disagree about what a text field is.
    const normalizerPath = path.join(projectRoot, 'source', 'util', 'AddonJson.brs');
    const normalizer = fs.readFileSync(normalizerPath, 'utf8');
    const tableNames = (fnName) => {
        const body = new RegExp(`function\\s+${fnName}\\s*\\([^)]*\\)[\\s\\S]*?end function`).exec(normalizer);
        if (body === null) return null;
        const text = body[0].split('\n').map((line) => line.split("'")[0]).join('\n');
        return [...text.matchAll(/"([^"]*)"/g)].map((m) => m[1]);
    };
    const textFields = tableNames('AddonJsonTextFieldNames');
    const textArrayFields = tableNames('AddonJsonTextArrayFieldNames');
    if (textFields === null || textArrayFields === null) {
        err('source/util/AddonJson.brs no longer defines AddonJsonTextFieldNames()/AddonJsonTextArrayFieldNames() — the boundary contract cannot read the table it enforces, so this whole check is vacuous');
        return false;
    }
    if (textFields.length === 0) {
        err('source/util/AddonJson.brs has an empty text-field table — every payload text read below would fail, which is the table being gutted rather than the reads being wrong');
    }
    const knownNames = new Set([...textFields, ...textArrayFields, ...Object.keys(ADDON_TEXT_READ_EXCEPTIONS)]);

    // 1. The include set. The five stores call the normalizer; every component
    //    that includes one of them can invoke those methods, so every one of them
    //    needs the include. The store list is the source of truth here — add a
    //    sixth store that calls the normalizer and the loop below has to name it.
    const addonStores = ['AddonsStore.bs', 'CatalogStore.bs', 'EpisodesStore.bs', 'PlaybackStore.bs', 'SubtitlesStore.bs'];
    const componentsDir = path.join(projectRoot, 'components');
    for (const xml of fs.readdirSync(componentsDir).filter((f) => f.endsWith('.xml'))) {
        const src = fs.readFileSync(path.join(componentsDir, xml), 'utf8');
        const includesStore = addonStores.some((store) => src.includes(`pkg:/source/stores/${store}`));
        if (includesStore && !src.includes('pkg:/source/util/AddonJson.brs')) {
            err(`components/${xml} includes an add-on-facing store but not <script uri="pkg:/source/util/AddonJson.brs"> — the store's NormalizeAddonJson call resolves against this component's scope, so on the device it is "attempted call of a non-function"`);
        }
    }

    // 2. The ingress call, per store function.
    const ingress = {
        'CatalogStore.bs': ['Manifest', 'Catalog'],
        'EpisodesStore.bs': ['GetMeta'],
        'AddonsStore.bs': ['Install', 'InstallFromDescriptor', 'Load'],
        'PlaybackStore.bs': ['Streams'],
        'SubtitlesStore.bs': ['Subtitles']
    };
    const storesDir = path.join(projectRoot, 'source', 'stores');
    for (const [file, fns] of Object.entries(ingress)) {
        const src = fs.readFileSync(path.join(storesDir, file), 'utf8');
        for (const fn of fns) {
            const body = new RegExp(`(?:function|sub)\\s+${fn}\\s*\\([^)]*\\)[\\s\\S]*?end\\s+(?:function|sub)`).exec(src);
            if (body === null) {
                err(`source/stores/${file} no longer defines ${fn}() — the ingress pin below cannot vouch for a function that is gone`);
            } else if (!body[0].includes('NormalizeAddonJson(')) {
                err(`source/stores/${file} ${fn}() no longer calls NormalizeAddonJson() — add-on JSON enters the app un-normalized here, so every text read downstream is raw again (this is the imdbRating-8.1 crash path)`);
            }
        }
        // A new payload entry point that never normalizes is the same hole, so
        // count them too: N ingress functions named above, at least N calls.
        const calls = (src.match(/NormalizeAddonJson\s*\(/g) || []).length;
        if (calls < fns.length) {
            err(`source/stores/${file} calls NormalizeAddonJson() ${calls} time(s) for ${fns.length} payload ingress point(s) — one of them is not normalized`);
        }
    }

    // 3. The table. Parse every source that can read a payload and collect the
    //    field names read as text through a payload receiver root.
    const scanDirs = [
        ['components', /\.brs$/],
        ['source/stores', /\.bs$/],
        ['source/util', /\.(brs|bs)$/],
        ['source/core', /\.(bs|brs)$/]
    ];
    const memberChain = (node) => {
        // A dotted/indexed read all the way down to a variable: { root, segs }.
        const segs = [];
        let cur = node;
        while (cur && (cur.constructor.name === 'DottedGetExpression' || cur.constructor.name === 'IndexedGetExpression')) {
            if (cur.constructor.name === 'DottedGetExpression') {
                segs.unshift(cur.name.text);
                cur = cur.obj;
            } else {
                const idx = cur.index;
                segs.unshift(idx && idx.constructor.name === 'VariableExpression' ? '[' + idx.name.text + ']' : '[]');
                cur = cur.obj;
            }
        }
        if (!cur || cur.constructor.name !== 'VariableExpression') return null;
        return { root: cur.name.text, segs };
    };
    const isPayloadChain = (chain) => chain !== null && (
        ADDON_PAYLOAD_ROOTS.includes(chain.root) ||
        (chain.root === 'm' && chain.segs.length > 1 && ADDON_PAYLOAD_ROOTS.includes(chain.segs[0]))
    );
    const isStringLiteral = (node) => node !== null && node !== undefined &&
        node.constructor.name === 'LiteralExpression' && String(node.type) === 'string';
    const stringMethods = new Set(['Trim', 'LCase', 'UCase', 'Left', 'Right', 'Mid', 'InStr', 'Split', 'Replace', 'StartsWith', 'EndsWith', 'Len']);
    const stringOps = new Set(['=', '<>', '<', '>', '<=', '>=']);
    const typedTextFields = new Set(['text', 'uri']);

    const reported = new Map(); // field name -> first file:line
    const note = (node, chain, file) => {
        if (!isPayloadChain(chain) || chain.segs.length === 0) return;
        const field = chain.segs[chain.segs.length - 1];
        if (field.startsWith('[')) return; // a dynamic key indexes nothing we can name
        if (!reported.has(field)) {
            const line = node.range && node.range.start && typeof node.range.start.line === 'number' ? node.range.start.line + 1 : 0;
            reported.set(field, `${file}:${line} (${chain.root}.${chain.segs.join('.')})`);
        }
    };

    const scanFile = (file) => {
        let ast;
        try {
            ast = Parser.parse(fs.readFileSync(file, 'utf8'), { file: { src: fs.readFileSync(file, 'utf8'), path: file } }, { isBrighterScript: true }).ast;
        } catch (e) {
            err(`tests/run.js could not parse ${path.relative(projectRoot, file)} for the add-on JSON contract: ${e.message}`);
            return;
        }
        ast.walk((node) => {
            if (!node || !node.constructor) return;
            const kind = node.constructor.name;

            if (kind === 'BinaryExpression' && node.operator) {
                const op = node.operator.text;
                for (const [a, b] of [[node.left, node.right], [node.right, node.left]]) {
                    if (!isStringLiteral(b)) continue;
                    if (stringOps.has(op) || op === '+') note(node, memberChain(a), file);
                }
            }

            if (kind === 'CallExpression' && node.callee) {
                const callee = node.callee;
                if (stringMethods.has(callee.name && callee.name.text) && callee.constructor.name === 'DottedGetExpression') {
                    note(callee, memberChain(callee.obj), file);
                } else if (callee.constructor.name === 'VariableExpression' && stringMethods.has(callee.name.text)) {
                    for (const arg of node.args || []) note(arg, memberChain(arg), file);
                }
            }

            // Writes into a node field the platform types as a string: a Float
            // there is the same &h18 on the other side of the equals sign.
            if (kind === 'AssignmentStatement' && node.name && node.value &&
                node.name.constructor.name === 'DottedGetExpression' && typedTextFields.has(node.name.name.text)) {
                note(node.value, memberChain(node.value), file);
            }
        }, { walkMode: WalkMode.visitAllRecursive });
    };

    for (const [dir, pattern] of scanDirs) {
        const full = path.join(projectRoot, dir);
        for (const file of fs.readdirSync(full).filter((f) => pattern.test(f))) {
            scanFile(path.join(full, file));
        }
    }

    for (const [field, where] of reported) {
        if (!knownNames.has(field)) {
            err(`tests/run.js found a payload field read as text that source/util/AddonJson.brs does not cover: "${field}" at ${where}. Add it to AddonJsonTextFieldNames() so the boundary pass coerces it, or — only if it is really a field this app fills itself — to ADDON_TEXT_READ_EXCEPTIONS with the reason`);
        }
    }
    if (reported.size === 0) {
        err('tests/run.js found no payload text read at all — the add-on JSON contract scan matched nothing, so it is no longer checking anything (the receiver roots or the AST API have drifted)');
    }

    return ok;
}

// The subtitle/play ordering contract, pinned statically for the same reason
// checkDeferredVideoPlayContract is: PlayerScreen never runs under the
// interpreter, so "playback waits for captions" is a property of the code, not
// something a green suite can vouch for.
//
// The invariant: SubtitleTracks reaches the ContentNode only BEFORE the pump
// starts. Writing that array onto a node the video is already playing is a
// mid-play mutation of the bytes the pump is reading, and the symptom is not an
// error — the video hangs, plays a moment and buffers forever, or fills the
// buffer and never renders a frame. It was discovered in the field with a third
// subtitle add-on installed: the drain is sequential, so every extra provider is
// one more of those writes landing mid-play.
//
// Three pins, one per way this could rot:
//   - the playKick hold: onPlayKickFire must reference the budget constant, so
//     the wait cannot be edited out of existence.
//   - no mid-play write: inside onSubtitleResult, ApplySubtitleIndex must come
//     AFTER the `if not m.playStarted` guard that refuses it. If a raw call
//     appears before the guard, the refusal is decoration.
//   - the budget must actually reap the drain when it expires, or a late result
//     can still land and hit the (defensive) drop path at best.
function checkSubtitlePlayGateContract() {
    const fs = require('fs');
    const read = (f) => fs.readFileSync(path.join(projectRoot, 'components', f), 'utf8');
    const code = (src) => src.split('\n').map((line) => line.split("'")[0]).join('\n');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    const player = read('PlayerScreen.brs');
    const src = code(player);
    const body = (name) => {
        const start = new RegExp(`^[ \\t]*(?:public\\s+|private\\s+|override\\s+)*(?:sub|function)\\s+${name}\\s*\\(`, 'm').exec(src);
        if (!start) return null;
        const rest = src.slice(start.index);
        const end = rest.slice(1).search(/^[ \t]*end\s+(?:sub|function)\b/m);
        return end === -1 ? rest : rest.slice(0, end + 1);
    };

    if (!/m\.subtitleHoldMaxTicks\s*=\s*12\b/.test(src)) {
        err('PlayerScreen.brs no longer sets m.subtitleHoldMaxTicks = 12 — the caption wait needs its bound (twelve 0.25s playKick ticks) in one named place');
    }

    const kick = body('onPlayKickFire');
    if (!kick) {
        err('PlayerScreen.brs has no onPlayKickFire() — the playKick Timer fires into nothing and no play ever starts');
    } else {
        if (!/m\.subtitleHoldMaxTicks/.test(kick)) {
            err('PlayerScreen.brs onPlayKickFire() no longer waits for the caption drain (no reference to m.subtitleHoldMaxTicks) — a track array landing mid-play is what hangs playback, and every provider in the drain is one more chance to land there');
        }
        if (!/m\.playStarted\s*=\s*true/.test(kick)) {
            err('PlayerScreen.brs onPlayKickFire() never flags the play started — m.playStarted is what makes onSubtitleResult refuse a late track write');
        }
    }

    // The reset side of m.playStarted, and the reason it has its own pin: the
    // flag is per play, but its writers (onPlayKickFire, MaybeReleaseHeldPlay)
    // run after the NEXT play's StartSubtitles has already asked LaunchSubtitleFetch
    // — which refuses while the flag stands. Only OnEnter clears it before that
    // point, so a cleared-flag requirement is a requirement on OnEnter specifically:
    // this exact leak shipped once, and its symptom (subtitles fetched for the
    // first play after a fresh start and for no play afterwards, plus the hold
    // burning its whole budget against a drain that never started) is invisible
    // to every interpreter test.
    const enter = body('OnEnter');
    if (!enter) {
        err('PlayerScreen.brs has no OnEnter() — a play has no entry point to reset per-play state in');
    } else if (!/m\.playStarted\s*=\s*false/.test(enter)) {
        err('PlayerScreen.brs OnEnter() no longer clears m.playStarted — the flag survives into the next play and LaunchSubtitleFetch refuses every fetch while it stands, so play #2 onward gets no captions and the playKick hold spends its whole budget against a drain that never started');
    }

    const results = body('onSubtitleResult');
    if (!results) {
        err('PlayerScreen.brs has no onSubtitleResult() — a fetched caption list has nowhere to land');
    } else {
        const guardIdx = results.indexOf('if not m.playStarted');
        const applyIdx = results.indexOf('ApplySubtitleIndex(invalid)');
        if (guardIdx === -1 || applyIdx === -1) {
            err('PlayerScreen.brs onSubtitleResult() no longer guards ApplySubtitleIndex with `if not m.playStarted` — the caption result would write SubtitleTracks onto the live content node, which is the mid-play mutation that hangs the video');
        } else if (guardIdx > applyIdx) {
            err('PlayerScreen.brs onSubtitleResult() calls ApplySubtitleIndex BEFORE the `if not m.playStarted` guard — the refusal is unreachable and the array still lands mid-play');
        }
        if (!/(?:DrainSettled|MaybeReleaseHeldPlay)\s*\(/.test(results)) {
            err('PlayerScreen.brs onSubtitleResult() never releases a held play — when the caption drain finishes first, playback would sit out the whole budget for nothing');
        }
    }

    const launch = body('LaunchSubtitleFetch');
    if (!launch) {
        err('PlayerScreen.brs has no LaunchSubtitleFetch() — the sequential drain has no launcher');
    } else if (!/m\.playStarted/.test(launch)) {
        err('PlayerScreen.brs LaunchSubtitleFetch() does not refuse to launch once playback started — a provider asked for a play already running has no safe place to put its tracks, so the request is only a mid-play write waiting to happen');
    }

    if (!/sub\s+MaybeReleaseHeldPlay\b/.test(src)) {
        err('PlayerScreen.brs has no MaybeReleaseHeldPlay() — the drain needs a way to start a held play the moment it settles');
    }

    return ok;
}

// The pre-video indicator's lifetime, pinned for the same reason everything else
// in PlayerScreen is: the interpreter never runs this component, so "the pulse
// runs while playback is being prepared, and only then" is a property of the
// code, not something a green suite can vouch for.
//
// The bug this exists to prevent shipped once. The pulse's stop was hardcoded to
// the resolve task returning — but the caption drain continues after that, so
// the hold re-started the pulse, and a restart rewinds the 3s animation to its
// first keyframe. The logo froze at 0.22, snapped to 0.15 and beat back up: a
// flicker, on every play, with subtitles installed. The fix is a lifetime, not a
// call site: start once on entry, stop only where playback is handed over (the
// play paths), where buffering takes over, or where no video will follow (the
// resolve failure exits).
//
// The pins below encode that shape, so the shape cannot quietly regress:
//   - OnEnter starts it (the one legitimate start).
//   - onPlayKickFire must NOT start it — a start there is the flicker returning,
//     because the hold is inside the same pre-video phase as the resolve.
//   - onResolveResult must still stop it on the no-video exits (otherwise the
//     pulse is stranded behind a failure message, since nothing else ends it).
//   - onVideoStateChanged's buffering branch must stop it AND clear the status
//     line: the platform's own buffering UI is up, so both app-owned pre-video
//     indicators yield at the same moment.
function checkPreVideoIndicatorContract() {
    const fs = require('fs');
    const read = (f) => fs.readFileSync(path.join(projectRoot, 'components', f), 'utf8');
    const code = (src) => src.split('\n').map((line) => line.split("'")[0]).join('\n');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    const player = read('PlayerScreen.brs');
    const src = code(player);
    const body = (name) => {
        const start = new RegExp(`^[ \\t]*(?:public\\s+|private\\s+|override\\s+)*(?:sub|function)\\s+${name}\\s*\\(`, 'm').exec(src);
        if (!start) return null;
        const rest = src.slice(start.index);
        const end = rest.slice(1).search(/^[ \t]*end\s+(?:sub|function)\b/m);
        return end === -1 ? rest : rest.slice(0, end + 1);
    };

    if (!/sub\s+StartPreVideoPulse\b/.test(src) || !/sub\s+StopPreVideoPulse\b/.test(src)) {
        err('PlayerScreen.brs no longer has StartPreVideoPulse()/StopPreVideoPulse() — the pre-video pulse is the only thing the player shows while it prepares a stream, and it cannot be driven from nowhere');
        return false;
    }

    const enter = body('OnEnter');
    if (!enter) {
        err('PlayerScreen.brs has no OnEnter() — nothing starts the pre-video pulse, so a play shows a bare screen');
    } else if (!/StartPreVideoPulse\s*\(/.test(enter)) {
        err('PlayerScreen.brs OnEnter() no longer starts the pre-video pulse — a slow resolve (or a torrent warm-up) would run with nothing on screen saying so');
    }

    const kick = body('onPlayKickFire');
    if (kick && /StartPreVideoPulse\s*\(/.test(kick)) {
        err('PlayerScreen.brs onPlayKickFire() starts the pre-video pulse again — the caption hold runs AFTER the resolve, inside the same pre-video phase, so restarting there rewinds the animation to its first keyframe and the beat flickers');
    }

    const resolve = body('onResolveResult');
    if (resolve && !/StopPreVideoPulse\s*\(/.test(resolve)) {
        err('PlayerScreen.brs onResolveResult() no longer stops the pre-video pulse on its failure exits — nothing downstream ends it, so a resolve that fails leaves the logo beating behind the error message');
    }

    const states = body('onVideoStateChanged');
    if (!states) {
        err('PlayerScreen.brs has no onVideoStateChanged() — the platform buffering handoff has nowhere to hand the pre-video indicators over');
    } else {
        const at = states.indexOf('state = "buffering"');
        if (at === -1) {
            err('PlayerScreen.brs onVideoStateChanged() no longer handles "buffering" — the reveal never takes over from the pulse');
        } else {
            const tail = states.slice(at);
            const cut = tail.slice(1).search(/else\s+if\s+state\s*=|end\s+if/);
            const branch = cut === -1 ? tail : tail.slice(0, cut + 1);
            if (!/StopPreVideoPulse\s*\(/.test(branch)) {
                err('PlayerScreen.brs onVideoStateChanged() buffering branch no longer stops the pre-video pulse — the beat would keep running under the platform\'s own buffering indicator');
            }
            if (!/m\.status\.text\s*=\s*""/.test(branch)) {
                err('PlayerScreen.brs onVideoStateChanged() buffering branch no longer clears the status line — "Loading subtitles x/n" would outlive the drain and sit over the buffering video');
            }
        }
    }

    return ok;
}

// The pre-video status line has two workers behind it and only one of them used to
// write to it. The caption drain owns the line while it runs ("Loading subtitles
// x/n…"), but nothing gave the line back when the drain ended — so on a torrent,
// where the resolve routinely outlives the drain, the last counter stayed on
// screen naming work that had already finished, for the whole of the engine
// warm-up. Pinned here because the interpreter never runs this component: "the
// line names live work, not finished work" is a property of the code.
function checkPreVideoWaitLabelContract() {
    const fs = require('fs');
    const read = (f) => fs.readFileSync(path.join(projectRoot, 'components', f), 'utf8');
    const code = (src) => src.split('\n').map((line) => line.split("'")[0]).join('\n');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    const src = code(read('PlayerScreen.brs'));
    const body = (name) => {
        const start = new RegExp(`^[ \\t]*(?:public\\s+|private\\s+|override\\s+)*(?:sub|function)\\s+${name}\\s*\\(`, 'm').exec(src);
        if (!start) return null;
        const rest = src.slice(start.index);
        const end = rest.slice(1).search(/^[ \t]*end\s+(?:sub|function)\b/m);
        return end === -1 ? rest : rest.slice(0, end + 1);
    };

    const label = body('PreVideoWaitLabel');
    // The message itself is a word of the table now, so the check is that the
    // function ANSWERS one — a literal or a lookup, both fine.
    if (!label || !/return\s+("|Lang\()/.test(label)) {
        err('PlayerScreen.brs has no PreVideoWaitLabel() returning a message — the pre-video wait has no words for work that is still running');
    }

    // One helper at BOTH drain-exhaustion points, and it has to reach the held-play
    // release as well as the label: there are two ways the drain can end (a
    // provider with nothing to give, and the last provider\'s tracks landing), and
    // a fix applied to one of them is a fix forgotten at the other.
    const settled = body('DrainSettled');
    if (!settled) {
        err('PlayerScreen.brs has no DrainSettled() — the drain\'s two exhaustion points have no single place to settle the status line and the held play');
    } else {
        if (!/UpdatePreVideoStatus\s*\(/.test(settled)) {
            err('PlayerScreen.brs DrainSettled() no longer updates the pre-video status — the drain\'s last counter outlives the drain and names finished work over a torrent resolve');
        }
        if (!/MaybeReleaseHeldPlay\s*\(/.test(settled)) {
            err('PlayerScreen.brs DrainSettled() no longer releases a held play — the drain settling would leave playback waiting out the rest of the budget for nothing');
        }
    }

    const result = body('onSubtitleResult');
    if (!result) {
        err('PlayerScreen.brs has no onSubtitleResult() — the drain has no result handler');
    } else if (!/DrainSettled\s*\(/.test(result)) {
        err('PlayerScreen.brs onSubtitleResult() no longer calls DrainSettled() — neither the status handoff nor the release happens when the drain ends');
    }

    const status = body('UpdatePreVideoStatus');
    if (!status) {
        err('PlayerScreen.brs has no UpdatePreVideoStatus() — nothing hands the status line back to a live-phase label');
    } else {
        // It may only speak while the resolve is still out and before the play is
        // handed over. Otherwise it is the stale-label bug one phase later: a label
        // written over a running video, or over a resolve failure\'s own message,
        // is worse than no label at all.
        if (!/m\.resolveTask\s*=\s*invalid\s+then\s+return/.test(status)) {
            err('PlayerScreen.brs UpdatePreVideoStatus() no longer waits for the resolve to still be in flight — it would write over the phase the platform owns');
        }
        if (!/m\.playStarted\s+then\s+return/.test(status)) {
            err('PlayerScreen.brs UpdatePreVideoStatus() no longer refuses once playback has started — the label would be written over a video that is already playing');
        }
    }

    // The label has to exist on BOTH ends of the wait: at the resolve\'s start, for
    // a play with no caption providers at all (where the drain never writes
    // anything and the line would otherwise stay blank for the whole resolve), and
    // after the drain, for a play that has providers.
    const resolve = body('StartResolve');
    if (!resolve || !/PreVideoWaitLabel\s*\(/.test(resolve)) {
        err('PlayerScreen.brs StartResolve() no longer sets the pre-video label — a torrent resolve on a play with no subtitle add-on runs behind a blank status line');
    }

    return ok;
}

// The native buffering UI the platform draws over a playing Video is three
// internal nodes: a BusySpinner (the center wheel), and the retrievingBar /
// bufferingBar ProgressBars. The app's logo reveal is meant to be the only
// buffering feedback on screen, so those internals are hidden while a logo is
// present, and left alone (as the QA-required fallback) when one is not.
//
// Pinned here because it is fiddly in exactly one way: the OS re-shows the wheel
// and bars on every buffer event, so a single hide at play start is undone by the
// first re-buffer. The property that matters is therefore the SHAPE — the
// suppression is armed at play start AND re-applied from the "buffering" branch —
// and it cannot be vouched for by a suite that never runs the component.
function checkNativeBufferingSuppressionContract() {
    const fs = require('fs');
    const read = (f) => fs.readFileSync(path.join(projectRoot, 'components', f), 'utf8');
    const code = (src) => src.split('\n').map((line) => line.split("'")[0]).join('\n');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    const player = read('PlayerScreen.brs');
    const src = code(player);
    const body = (name) => {
        const start = new RegExp(`^[ \\t]*(?:public\\s+|private\\s+|override\\s+)*(?:sub|function)\\s+${name}\\s*\\(`, 'm').exec(src);
        if (!start) return null;
        const rest = src.slice(start.index);
        const end = rest.slice(1).search(/^[ \t]*end\s+(?:sub|function)\b/m);
        return end === -1 ? rest : rest.slice(0, end + 1);
    };

    if (!/sub\s+SuppressNativeBufferingUi\b/.test(src) || !/sub\s+HideNativeBufferingUi\b/.test(src)) {
        err('PlayerScreen.brs no longer has SuppressNativeBufferingUi()/HideNativeBufferingUi() — nothing hides the platform wheel/bars, so the native buffering UI doubles up with the app logo reveal');
        return false;
    }

    const suppress = body('SuppressNativeBufferingUi');
    const hide = body('HideNativeBufferingUi');
    if (!suppress || !/HasLogo\s*\(/.test(suppress)) {
        err('PlayerScreen.brs SuppressNativeBufferingUi() no longer gates on HasLogo() — without a logo there is NO buffering feedback left, which is a certification risk on slow connections');
    }
    if (!hide || !/HasLogo\s*\(/.test(hide)) {
        err('PlayerScreen.brs HideNativeBufferingUi() no longer gates on HasLogo() — the no-logo fallback has to keep the native indicators');
    }

    // The whole reason this check exists. SuppressNativeBufferingUi runs inside
    // CreateVideo → StartPlayback, which is inside onResolveResult's handoff try:
    // anything that escapes it aborts the handoff BEFORE the Video node is given
    // its content, so the play dies behind "The player could not start." with the
    // pulse frozen and the caption drain still overwriting the status line — a
    // dead player indistinguishable from one still preparing the stream.
    //
    // That shipped. The wheel was looked up with FindNodesByType(), which is NOT
    // an roSGNode method (it appears nowhere in the Roku docs), and the call was
    // left outside any try. So: no invented node methods, and the body must carry
    // its own try/catch.
    if (/FindNodesByType/.test(src)) {
        err('PlayerScreen.brs calls FindNodesByType() — there is no such roSGNode method; an unguarded call to it once aborted the playback handoff and stopped every play');
    }
    if (suppress && !/try[\s\S]*catch\s+e[\s\S]*end\s+try/.test(suppress)) {
        err('PlayerScreen.brs SuppressNativeBufferingUi() is no longer wrapped in a try/catch — a throw there aborts the playback handoff before the Video node gets its content, killing the play with no log line');
    }
    if (suppress && !/retrievingBarVisibilityAuto/.test(suppress)) {
        err('PlayerScreen.brs SuppressNativeBufferingUi() no longer opts out of the auto retrieving bar — the initial load bar returns');
    }

    const walk = body('HideBusySpinners');
    if (!walk || !/(GetChild\s*\(|GetChildCount\s*\()/.test(walk) || !/subtype\s*\(/.test(walk)) {
        err('PlayerScreen.brs HideBusySpinners() no longer walks node children by subtype — the center wheel has no field/getter, so that walk is the only documented way to reach it');
    }

    const custom = body('CustomizeVideoNode');
    if (!custom || !/SuppressNativeBufferingUi\s*\(/.test(custom)) {
        err('PlayerScreen.brs CustomizeVideoNode() no longer arms the native buffering suppression at play start — the initial retrieving bar appears before the observer can hide it');
    } else {
        // It must run BEFORE the trickPlayBar guard, since it is independent of
        // that field and an early return would silently skip it on an OS without
        // a trick-play bar.
        const guard = custom.indexOf('HasField("trickPlayBar")');
        const call = custom.indexOf('SuppressNativeBufferingUi');
        if (guard !== -1 && call > guard) {
            err('PlayerScreen.brs CustomizeVideoNode() arms native buffering suppression AFTER the trickPlayBar early return — on an OS without a trick-play bar the wheel/bars would never be suppressed');
        }
    }

    const states = body('onVideoStateChanged');
    if (states) {
        const at = states.indexOf('state = "buffering"');
        if (at !== -1) {
            const tail = states.slice(at);
            const cut = tail.slice(1).search(/else\s+if\s+state\s*=|end\s+if/);
            const branch = cut === -1 ? tail : tail.slice(0, cut + 1);
            if (!/SuppressNativeBufferingUi\s*\(/.test(branch)) {
                err('PlayerScreen.brs onVideoStateChanged() buffering branch no longer re-applies native buffering suppression — the OS brings the wheel/bars back on every re-buffer, so a one-shot hide is not enough');
            }
        }
    }

    return ok;
}

// The one bug class this repository cannot test its way out of.
//
// m.installed is an roAssociativeArray. "for each" over its keys has NO defined
// order: the brs interpreter yields declaration order, a Roku device yields the
// runtime's own hash order. So code that walks it to build a list — or that
// takes "the first entry that has property X" — produces a DIFFERENT list, and
// makes a DIFFERENT choice, on the device than under `npm test`. Every test in
// this repo passes against the broken version, permanently, because the
// interpreter only has one behaviour to exhibit.
//
// That is not hypothetical here. It shipped: Home's catalog rows came out in a
// different order on the device than in the simulator, and the subtitle
// provider picker asked whichever add-on the hash order happened to yield first
// — a provider the app could not drive, while the working one sat in the same
// registry. Guest sessions hid it because their list opens with the built-in
// seeds, so only the tail moved; a stremio session is hash-ordered end to end.
//
// The lesson belongs in the harness as much as in the code: a green suite is
// NOT evidence about anything that depends on iteration order. Pin order by
// construction — an explicit list, persisted as a JSON array — and pin the
// absence of the old shape here, where the interpreter cannot launder it.
function checkAddonOrderingContract() {
    const fs = require('fs');
    const read = (f) => fs.readFileSync(path.join(projectRoot, f), 'utf8');
    const store = read('source/stores/AddonsStore.bs');
    const player = read('components/PlayerScreen.brs');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };

    // Scan CODE, not prose: these files document the exact bug in their headers,
    // and a raw-text scan would match the documentation describing it.
    const code = (src) => src.split('\n').map(line => line.split("'")[0]).join('\n');
    const storeCode = code(store);
    const playerCode = code(player);

    // Body of a `function Name(`/`sub Name(` member, found by depth counting so
    // it works for both indented BSL class methods and flat component subs.
    // Indexed by position, NOT lines.indexOf: every `end for` in a method body
    // is a duplicate line, and indexOf would cut the body at the first one.
    const member = (src, name) => {
        const head = new RegExp(`^[ \\t]*(?:private\\s+)?(?:function|sub)\\s+${name}\\s*\\(`, 'm');
        const m = head.exec(src);
        if (!m) return null;
        const lines = src.slice(m.index).split('\n');
        let depth = 0;
        for (let i = 0; i < lines.length; i++) {
            if (/^\s*(?:private\s+)?(?:function|sub)\s/.test(lines[i])) depth++;
            else if (/^\s*end\s+(?:function|sub)\b/.test(lines[i])) {
                depth--;
                if (depth === 0) return code(lines.slice(0, i + 1).join('\n'));
            }
        }
        return null;
    };

    // The body of the `for each` loop whose header is at `from`, matched on
    // indentation so a nested loop does not end it early.
    const loopBody = (src, from) => {
        const lines = src.split('\n');
        const start = src.slice(0, from).split('\n').length - 1;
        const indent = (lines[start].match(/^\s*/) || [''])[0];
        const out = [];
        for (let i = start + 1; i < lines.length; i++) {
            out.push(lines[i]);
            if (new RegExp(`^${indent}end\\s+for\\b`).test(lines[i])) return out.join('\n');
        }
        return out.join('\n');
    };
    // Every `for each` header matching a pattern, with the body of each loop.
    // More than one is normal (GetAll walks m.order twice: once to build a
    // lookup, once to emit), so a check has to say which of them it means.
    //
    // `[ \t]*` and the trailing `$`, never `\s*`: \s matches a newline, so a
    // pattern that can skip lines starts matching on the BLANK line above the
    // header, the captured indent comes out empty, and loopBody then runs to the
    // end of the member and reports pushes that belong to a later loop. That
    // silently disabled two of these checks once already.
    const walks = (src, pattern) => {
        const re = new RegExp(pattern, 'gm');
        const out = [];
        let m;
        while ((m = re.exec(src)) !== null) out.push({ header: m[0], body: loopBody(src, m.index) });
        return out;
    };
    const pushesTo = (w, list) => w.body.split('\n').some(line => new RegExp(`\\b${list}\\.Push\\s*\\(`).test(line));
    const anyPushes = (ws, list) => ws.some(w => pushesTo(w, list));

    // --- the ordered view is the only view ------------------------------------
    const getAll = member(storeCode, 'GetAll');
    if (!getAll) {
        err('AddonsStore has no GetAll — the one ordered view of the registry is gone');
    } else {
        // Every record that reaches the returned list must arrive through one of
        // these four walks, and no walk of the record map may push into the
        // result at all. Asserted per loop rather than as one regex so a push in
        // a later loop cannot be read as belonging to an earlier one.
        const mapWalks = walks(getAll, '^[ \\t]*for\\s+each\\s+\\w+\\s+in\\s+m\\.installed\\b[^\\n]*$');
        if (mapWalks.length === 0) {
            err('AddonsStore.GetAll no longer walks m.installed at all — records with no entry in the order list need somewhere to be collected and sorted');
        } else if (anyPushes(mapWalks, 'list')) {
            err('AddonsStore.GetAll pushes straight out of its m.installed walk again — that walk is roAssociativeArray key order, which is declaration order in the simulator and hash order on a device, so rows reorder and "first match" picks change per platform. Collect them and sort; append via m.order.');
        }
        const builtinWalks = walks(getAll, '^[ \\t]*for\\s+each\\s+\\w+\\s+in\\s+m\\.BuiltinIds\\(\\)[^\\n]*$');
        if (builtinWalks.length === 0) {
            err('AddonsStore.GetAll no longer walks BuiltinIds() — iterating the BuiltIns() associative array is the same undefined-order trap one level up');
        } else if (!anyPushes(builtinWalks, 'list')) {
            err('AddonsStore.GetAll walks BuiltinIds() but never appends what it yields — the built-in seeds would be missing from every ordered view');
        }
        const orderWalks = walks(getAll, '^[ \\t]*for\\s+each\\s+\\w+\\s+in\\s+m\\.order\\b[^\\n]*$');
        if (orderWalks.length === 0) {
            err('AddonsStore.GetAll does not walk the persisted m.order list — with no explicit order, the display order falls back to registry iteration');
        } else if (!anyPushes(orderWalks, 'list')) {
            err('AddonsStore.GetAll walks m.order but never appends what it yields — the explicit order would be computed and then ignored');
        }
        // The map walk has to be FILTERED by whatever the order walks build, or
        // every record counts as a leftover: the ordered pass emits it, then the
        // sorted leftovers emit it again. Caught here because nothing else in
        // the guard notices — the four walks are all still present and correct.
        if (mapWalks.length > 0 && orderWalks.length > 0) {
            const built = new Set();
            for (const w of orderWalks) {
                for (const m of w.body.matchAll(/^[ \t]*(\w+)(?:\[\w+\])?[ \t]*=/gm)) built.add(m[1]);
            }
            const filtered = built.size > 0 && mapWalks.some(w =>
                [...built].some(name => new RegExp(`\\b${name}\\b`).test(w.body)));
            if (!filtered) {
                err('AddonsStore.GetAll walks the record map without filtering it against the set the m.order walk builds — every record would be collected as a leftover and appended twice (ordered pass, then sorted leftovers)');
            }
        }
        // Anything appended outside a loop has no order behind it at all.
        const outside = getAll
            .replace(/^\s*for\s+each[^\n]*\n(?:^[^\n]*\n)*?^\s*end\s+for\b/gm, '')
            .replace(/^\s*(?:private\s+)?(?:function|sub)\s+[^\n]*$/gm, '');
        if (/\blist\.Push\s*\(/.test(outside)) {
            err('AddonsStore.GetAll appends to the result list outside every loop — an un-ordered append can only come from somewhere with no defined position');
        }
        if (!/m\.SortByNameThenId\(/.test(getAll)) {
            err('AddonsStore.GetAll does not sort its leftovers — records with no entry in the order list (a registry written before the order key existed) would land in map order');
        }
    }

    const sortBy = member(storeCode, 'SortByNameThenId');
    if (!sortBy || !/^\s*private\s+sub\s+SortByNameThenId/m.test(store)) {
        err('AddonsStore has no private SortByNameThenId — the leftover sort has to be one the store fully controls, not Sort() or map iteration');
    }
    const sortsAfter = member(storeCode, 'SortsAfter');
    if (!sortsAfter || !/a\.name/.test(sortsAfter) || !/a\.id/.test(sortsAfter)) {
        err('AddonsStore.SortsAfter must compare name AND id — name alone leaves two same-named add-ons in a platform-defined order');
    }

    // --- the order is persisted where it can survive --------------------------
    const orderKey = member(storeCode, 'OrderKey');
    if (!orderKey || !/m\.RegistryKey\(\)\s*\+\s*"_order"/.test(orderKey)) {
        err('AddonsStore.OrderKey must derive from RegistryKey() + "_order" so each session keeps its own order beside its own records');
    }
    if (!/^\s*order\s+as\s+object/m.test(store)) {
        err('AddonsStore has no `order as object` field — there is nowhere for the display order to live');
    }
    const save = member(storeCode, 'Save');
    if (!save || !/m\.registry\.Write\(\s*m\.OrderKey\(\)/.test(save)) {
        err('AddonsStore.Save does not write the order key — a record written without its order reloads with no order at all');
    }
    if (!/m\.registry\.Write\(\s*m\.RegistryKey\(\)/.test(save || '')) {
        err('AddonsStore.Save no longer writes the record map');
    }
    const load = member(storeCode, 'Load');
    if (!load || !/m\.registry\.Read\(\s*m\.OrderKey\(\)/.test(load)) {
        err('AddonsStore.Load does not read the order key — the order would be rebuilt from scratch on every launch');
    }
    // The reason a second key exists at all: FormatJson(m.installed) is a JSON
    // OBJECT, and ParseJson does not preserve object key order, so an order
    // stored there is silently gone by the next relaunch.
    if (/FormatJson\(\s*m\.order\s*\)/.test(storeCode.replace(/m\.registry\.Write\(\s*m\.OrderKey\(\)\s*,\s*FormatJson\(\s*m\.order\s*\)\s*\)/, ''))) {
        err('AddonsStore formats m.order somewhere other than its own array key — a JSON object does not round-trip key order, so the order cannot live in the record map');
    }

    // --- the order is kept truthful on every write ----------------------------
    const register = member(storeCode, 'Register');
    if (!register || !/m\.order\.Push\(\s*record\.id\s*\)/.test(register)) {
        err('AddonsStore.Register does not append the new id to m.order — a record with no order slot is a record the display order has to guess about');
    }
    const uninstall = member(storeCode, 'Uninstall');
    if (!uninstall || !/m\.DropFromOrder\(/.test(uninstall)) {
        err('AddonsStore.Uninstall does not drop the id from m.order — a re-install would inherit a slot it no longer owns');
    }
    const switchSession = member(storeCode, 'SwitchSession');
    if (!switchSession || !/m\.order\s*=\s*\[\]/.test(switchSession)) {
        err('AddonsStore.SwitchSession does not clear m.order — the other session\'s order would leak across the switch');
    }

    // --- provenance is the id, never the record's flag ------------------------
    // The account sync stamps every record it adopts with builtin: false, so on
    // a stremio session the flag is a constant and carries no information. The
    // one picker that consulted it could not tell the working built-in from the
    // providers that answer with nothing.
    const isBuiltin = member(storeCode, 'IsBuiltin');
    if (!isBuiltin || !/m\.BuiltIns\(\)/.test(isBuiltin)) {
        err('AddonsStore.IsBuiltin must resolve through BuiltIns() (by id) — resolving through a record\'s builtin flag is a constant false on every synced add-on');
    }

    // --- the subtitle provider is ranked, and the queue drains ---------------
    if (/FindSubtitlesAddress/.test(playerCode)) {
        err('PlayerScreen still has FindSubtitlesAddress — it returns the first add-on advertising subtitles, and "first" in an unordered registry is a different add-on on every device');
    }
    const ranked = member(playerCode, 'SubtitlesAddresses');
    if (!ranked) {
        err('PlayerScreen has no SubtitlesAddresses — subtitle provider choice is back to depending on registry order');
    } else {
        if (!/AddonsIsBuiltin/.test(ranked)) {
            err('PlayerScreen.SubtitlesAddresses does not consult AddonsIsBuiltin — ranking has to be by id, since a synced record\'s builtin flag is always false');
        }
        if (!/AddonsHasResource/.test(ranked)) {
            err('PlayerScreen.SubtitlesAddresses does not check AddonsHasResource — it would queue providers that cannot serve captions at all');
        }
        if (!/SortAddressesByName\(/.test(ranked)) {
            err('PlayerScreen.SubtitlesAddresses does not sort the non-built-in candidates — the tail is still registry order, so it is still device-dependent');
        }
    }
    // No check here that StoreHost forwards AddonsIsBuiltin: the callFunc
    // contract (forwarder AND the <function> declaration in StoreHost.xml) is
    // owned by checkStoreHandoffContract, which reports both halves. What is
    // specific to this bug — that ranking goes through the id path at all — is
    // the AddonsIsBuiltin consult asserted above.

    // A wrong pick must cost one round trip, not the whole search: that was the
    // difference between "no subtitles at all" and "this provider had none".
    const startSubs = member(playerCode, 'StartSubtitles');
    if (!startSubs || !/SubtitlesAddresses\(/.test(startSubs) || !/LaunchSubtitleFetch\(\)/.test(startSubs)) {
        err('PlayerScreen.StartSubtitles no longer drains a ranked candidate list — one unreachable provider would end the search the way it used to');
    }
    const onResult = member(playerCode, 'onSubtitleResult');
    const more = member(playerCode, 'MoreSubtitleCandidates');
    if (!more || !/m\.subtitleCursor\s*<\s*m\.subtitleCandidates\.Count\(\)/.test(more)) {
        err('PlayerScreen.MoreSubtitleCandidates no longer asks whether the ranked queue has anyone left — the drain has no terminator, so it either stops at the first provider or never stops');
    }
    if (!onResult || !/MoreSubtitleCandidates\(\)[\s\S]{0,120}?LaunchSubtitleFetch\(\)/.test(onResult)) {
        err('PlayerScreen.onSubtitleResult no longer falls through to the next candidate when a provider returns nothing — picking a provider that cannot answer is back to meaning "no subtitles"');
    }
    // A later provider coming back empty must not discard captions an earlier
    // one already contributed. Under a merge this is the difference between
    // "this add-on had nothing" and "the player lost its subtitles".
    if (onResult) {
        const emptyBranch = onResult.slice(onResult.indexOf('result.subtitles.Count() = 0'));
        const clearAt = emptyBranch.search(/ClearSubtitles\(\)/);
        if (clearAt !== -1) {
            const guard = emptyBranch.slice(0, clearAt);
            if (!/m\.subtitleTracks\s*=\s*invalid\s+or\s+m\.subtitleTracks\.Count\(\)\s*=\s*0/.test(guard)) {
                err('PlayerScreen.onSubtitleResult clears the subtitle list when a LATER provider returns nothing, discarding tracks an earlier provider already merged — under a merge, one flaky add-on would blank captions the user can already see');
            }
        }
    }
    const cancel = member(playerCode, 'CancelSubtitles');
    if (!cancel || !/m\.subtitleCandidates\s*=\s*\[\]/.test(cancel)) {
        err('PlayerScreen.CancelSubtitles does not drop the candidate queue — leaving the player would leave a stale provider queue to walk on the next play');
    }

    // --- an unusable track list never reaches the live content node ---------
    // BuildSubtitleTracks drops entries without a URL, so a non-empty raw list
    // can build to nothing. Writing that empty list onto a playing video blanks
    // its caption state mid-playback, and SetCaptionMode("on") over a list the
    // platform cannot load is how the player ends up in a caption state it
    // cannot leave.
    const apply = member(playerCode, 'ApplySubtitleIndex');
    if (!apply) {
        err('PlayerScreen has no ApplySubtitleIndex');
    } else {
        // Scoped to AFTER the raw-empty guard: writing an empty array there is
        // the documented reset, not the defect. The defect is building the track
        // list after the content node has already been written.
        const rawGuard = apply.indexOf('m.subtitleTracks = invalid');
        if (rawGuard === -1) {
            err('PlayerScreen.ApplySubtitleIndex no longer has the raw-empty-track-list guard');
        } else {
            const guardEnd = apply.indexOf('end if', rawGuard);
            const after = guardEnd === -1 ? apply.slice(rawGuard) : apply.slice(guardEnd);
            const build = after.indexOf('BuildSubtitleTracks()');
            const write = after.indexOf('content.subtitleTracks');
            if (build === -1 || write === -1 || build > write) {
                err('PlayerScreen.ApplySubtitleIndex writes content.subtitleTracks before building the tracks — an empty result still lands on the live content node');
            }
        }
        if (!/tracks\.Count\(\)\s*=\s*0[\s\S]{0,200}?return/.test(apply)) {
            err('PlayerScreen.ApplySubtitleIndex has no empty-tracks bail-out — a provider can return entries that all fail to resolve to a URL');
        }
        const guard = apply.indexOf('if selected = ""');
        const on = apply.indexOf('SetCaptionMode("on")');
        if (guard === -1 || on === -1 || on < guard) {
            err('PlayerScreen.ApplySubtitleIndex turns captions on before a track is confirmed — globalCaptionMode "On" over an unloadable list is the caption state the player cannot exit');
        }
    }

    return ok;
}

// The player used to wedge — app-wide, unrecoverable without killing the
// channel — and the cause was not media, not the stream, and not the server.
//
// The player publishes its position from INSIDE the Video node's "state"
// observer: pausing reports "paused", leaving reports through SavePosition.
// That write woke MainScene's onWatchStateUpdate, which built a
// push worker inline — CreateObject + AppendChild + control = "RUN" —
// on the render thread, underneath a Video node that was mid-transition into the
// OS's own pause screen. The SceneGraph stopped servicing input and never
// recovered. Back froze it, pause froze it, and the three separate theories
// offered for it (a hung stream server, the pendingStop teardown lockout, a
// leaked duplicate player) were all wrong; the same stream from the same server
// played fine, and it never happened in a guest session — because a guest
// session returns at the AuthGetSession gate before the launch, and only a
// stremio session got far enough to wedge.
//
// The invariant is not "be careful here", it is structural: the handler that a
// Video state observer feeds must not build a node. Pin it.
function checkWatchStatePushContract() {
    const fs = require('fs');
    const read = (f) => fs.readFileSync(path.join(projectRoot, f), 'utf8');
    const main = read('components/MainScene.brs');
    const sceneXml = read('components/MainScene.xml');
    const coordinator = read('components/LibraryWriteCoordinator.brs');
    const coordinatorXml = read('components/LibraryWriteCoordinator.xml');
    const player = read('components/PlayerScreen.brs');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };
    const code = (src) => src.split('\n').map(line => line.split("'")[0]).join('\n');
    const sceneCode = code(main);
    const coordinatorCode = code(coordinator);
    const body = (src, name) => {
        const m = new RegExp(`^(?:sub|function) ${name}\\([^\\n]*`, 'm').exec(src);
        if (!m) return '';
        const lines = src.slice(m.index).split('\n');
        for (let i = 0; i < lines.length; i++) {
            if (i > 0 && /^end (?:sub|function)\b/.test(lines[i])) return lines.slice(0, i + 1).join('\n');
        }
        return src.slice(m.index);
    };

    // The Scene is still the field observer, but only forwards the event. The
    // coordinator owns all account-write state and task creation.
    const sceneHandler = body(sceneCode, 'onWatchStateUpdate');
    if (!/m\.libraryWriteCoordinator\.callFunc\("OnWatchStateUpdate"\)/.test(sceneHandler)) {
        err('MainScene.onWatchStateUpdate must forward to LibraryWriteCoordinator');
    }
    for (const forbidden of ['CreateObject', 'AppendChild', 'AsyncTask_Launch']) {
        if (new RegExp(`\\b${forbidden}\\s*\\(`).test(sceneHandler)) {
            err(`MainScene.onWatchStateUpdate calls ${forbidden} — the Video state observer must not create or launch work`);
        }
    }

    // The coordinator reads the buffered packet (not the player node), gates
    // account-only writes, dedupes, and defers the worker off the Video event.
    const handler = body(coordinatorCode, 'OnWatchStateUpdate');
    if (!/callFunc\("AuthGetSession"\)\s*<>\s*"stremio"/.test(handler)) {
        err('LibraryWriteCoordinator.OnWatchStateUpdate lost its stremio-session gate');
    }
    if (!/callFunc\("WatchLatest"\)/.test(handler) || !/m\.pendingWatchState\s*=\s*packet/.test(handler)) {
        err('LibraryWriteCoordinator must read WatchLatest and retain the packet beyond the player node lifetime');
    }
    if (!/ScheduleWatchStatePush\(\)/.test(handler)) {
        err('LibraryWriteCoordinator.OnWatchStateUpdate must defer task creation off the Video state observer');
    }
    const schedule = body(coordinatorCode, 'ScheduleWatchStatePush');
    if (!/m\.watchStatePump\.control\s*=\s*"stop"[\s\S]{0,120}?m\.watchStatePump\.control\s*=\s*"start"/.test(schedule)) {
        err('LibraryWriteCoordinator.ScheduleWatchStatePush must restart the one-shot coalescing timer');
    }
    if (!/m\.watchStatePump\s*=\s*invalid[\s\S]{0,200}?Pump\(\)/.test(schedule)) {
        err('LibraryWriteCoordinator must keep the inline fallback if its deferral timer is missing');
    }
    if (!/m\.watchStatePump\.ObserveField\(\s*"fire"\s*,\s*"onWatchStatePumpFire"\s*\)/.test(coordinatorCode) || !/Pump\(\)/.test(body(coordinatorCode, 'onWatchStatePumpFire'))) {
        err('LibraryWriteCoordinator must observe the timer and pump on its fire');
    }
    if (!/<Timer\s+id="watchStatePump"[^>]*duration="1"/.test(coordinatorXml) || !/<Timer\s+id="watchStatePump"[^>]*repeat="false"/.test(coordinatorXml)) {
        err('LibraryWriteCoordinator.xml must declare a one-shot, one-tick watchStatePump timer');
    }
    const pump = body(coordinatorCode, 'Pump');
    if (!/if m\.pushing then return/.test(pump) || !/NextWrite\(\)/.test(pump) || !/AsyncTask_Launch\(m\.top,\s*"LibraryPutTask"/.test(pump)) {
        err('LibraryWriteCoordinator.Pump must serialize LibraryPutTask launches through the single-flight guard and NextWrite');
    }
    if (!/packet\s*=\s*m\.pendingWatchState\b/.test(body(coordinatorCode, 'NextWrite'))) {
        err('LibraryWriteCoordinator.NextWrite must build the deferred packet from its own pending slot');
    }
    if (!/m\.libraryWriteCoordinator\.callFunc\("SetStoreHost",\s*m\.storeHost\)/.test(sceneCode) || !/<function\s+name="SetStoreHost"\s*\/>/.test(coordinatorXml)) {
        err('MainScene must hand the StoreHost NODE to LibraryWriteCoordinator through its declared setup function');
    }
    for (const [handlerName, screenField, method] of [
        ['onLibraryChange', 'm.detailsScreen.libraryChange', 'OnLibraryChange'],
        ['onWatchedChange', 'm.episodesScreen.watchedChange', 'OnWatchedChange']
    ]) {
        const forwarded = body(sceneCode, handlerName);
        if (!forwarded.includes(screenField) || !forwarded.includes(`callFunc("${method}"`)) {
            err(`MainScene.${handlerName} must forward ${screenField} to LibraryWriteCoordinator.${method}`);
        }
    }

    // The publisher itself stays trivial: it runs inside the Video observer.
    const publish = /sub PublishWatchState\(\)[\s\S]*?\nend sub/.exec(code(player));
    if (!publish) {
        err('PlayerScreen.brs has no PublishWatchState');
    } else {
        for (const forbidden of ['CreateObject', 'AppendChild', 'AsyncTask_Launch', 'Wait(']) {
            if (new RegExp(`\\b${forbidden.replace('(', '\\(')}`).test(publish[0])) {
                err(`PlayerScreen.brs PublishWatchState calls ${forbidden} — it runs inside the Video state observer`);
            }
        }
        if (!/m\.top\.watchStateUpdate\s*=/.test(publish[0])) {
            err('PlayerScreen.brs PublishWatchState no longer publishes through watchStateUpdate');
        }
    }
    return ok;
}

function checkScreensHidden() {
    const fs = require('fs');
    const xml = fs.readFileSync(path.join(projectRoot, 'components', 'MainScene.xml'), 'utf8');
    let ok = true;
    // Every screen the stack can show must exist as a child of the Scene. The
    // two custom dialogs are deliberately NOT here: they are built with
    // CreateObject (a dialog declared in markup dims the background and paints
    // nothing — see checkMainSceneContract), so there is nothing to expect.
    for (const name of ['HomeScreen', 'DetailsScreen', 'EpisodesScreen', 'StreamsScreen', 'SettingsScreen', 'AddonsScreen', 'SearchScreen', 'DiscoverScreen', 'LibraryScreen', 'AuthScreen', 'LinkStremioScreen']) {
        const element = xml.match(new RegExp(`<${name}[^>]*>`));
        if (!element) {
            console.error(`MainScene.xml is missing a <${name} ... /> child`);
            ok = false;
        }
    }
    return ok;
}

async function main() {
    const builder = new ProgramBuilder();
    await builder.run({
        project: null,
        rootDir: projectRoot,
        files: ['source/**/*.bs', 'source/**/*.brs', 'bslib'],
        stagingDir,
        createPackage: false,
        copyToStaging: true,
        deploy: false,
        emitDefinitions: false,
        showDiagnosticsInConsole: true
    });

    const failedDiagnostics = builder.getDiagnostics().filter(d => d.severity === 1);
    if (failedDiagnostics.length > 0) {
        console.error(`Transpile stopped with ${failedDiagnostics.length} error diagnostic(s).`);
        process.exit(1);
    }

    // callFunc only invokes functions declared in a component's interface, and
    // the suite mocks callFunc, so a missing declaration would pass tests but
    // silently no-op on device. Guard the contract here.
    if (!checkDeferredVideoPlayContract() || !checkScreenRuntimeHazards() || !checkScreenContract() || !checkScreensHidden() || !checkTileContract() || !checkPosterStatusContract() || !checkPosterFallbackContract() || !checkNoDuplicateScripts() || !checkStoreHandoffContract() || !checkLibraryCodecContract() || !checkMainSceneContract() || !checkSessionAuthorityContract() || !checkStremioProvisioningContract() || !checkAddonOrderingContract() || !checkAddonSyncTaskContract() || !checkStreamResolveTaskContract() || !checkEngineWarmupContract() || !checkTransportRetryContract() || !checkStaggeredSyncContract() || !checkNetDiagContract() || !checkDeviceCapContract() || !checkCodecPlaybackContract() || !checkHomeCatalogStalenessContract() || !checkTaskTeardownContract() || !checkHomeCatalogResultsAreIncremental() || !checkStopSignalContract() || !checkSubtitleMergeContract() || !checkWatchStatePushContract() || !checkHomeScreenContract() || !checkFilterBarContract() || !checkLibraryScreenContract() || !checkLibraryPutTaskContract() || !checkAddonsWriteTaskContract() || !checkLogoutTaskContract() || !checkSettingsPushContract() || !checkSettingsSectionsContract() || !checkTorrentProfileContract() || !checkCacheSizeContract() || !checkThemeContract() || !checkPosterScalingContract() || !checkPosterLoadSizePolicy() || !checkCompanionQrContract() || !checkSetupServerContract() || !checkDetailsMetaTypeContract() || !checkStreamFormatQueryContract() || !checkChannelCwPolicyContract() || !checkStreamTypeGateContract() || !checkDiscoverSourcesContract() || !checkMultiAddonSearchContract() || !checkStringMethodContract() || !checkMetaFieldCoercionContract() || !checkStringOfContract() || !checkI18nContract() || !checkNoUntranslatedLiterals() || !checkEpisodeSeriesBatchContract() || !checkStoreAddonValueContract() || !checkAddonJsonContract() || !checkSubtitlePlayGateContract() || !checkPreVideoIndicatorContract() || !checkPreVideoWaitLabelContract() || !checkNativeBufferingSuppressionContract()) {
        process.exit(1);
    }

    await writeCombinedScript();

    const result = spawnSync(
        process.execPath,
        [
            path.join(projectRoot, 'node_modules', '@rokucommunity', 'brs', 'bin', 'cli.js'),
            '--root', stagingDir,
            ...transpiled,
            combinedPath
        ],
        { cwd: projectRoot, stdio: 'inherit' }
    );
    process.exit(result.status === null ? 1 : result.status);
}

main().catch(err => {
    console.error(err);
    process.exit(1);
});
