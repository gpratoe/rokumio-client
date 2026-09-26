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
        'tests/screenstack.test.brs',
        'tests/transport.test.brs',
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
        'tests/watchedcodec.fixtures.brs',
        'tests/watchedcodec.test.brs',
        'tests/videoidcodec.test.brs',
        'tests/timeutil.test.brs',
        'tests/watchstatebuffer.test.brs',
        'tests/stremiolibrarycodec.test.brs',
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
    path.join(stagingDir, 'source', 'stores', 'WatchStateBuffer.brs'),
    path.join(stagingDir, 'source', 'stores', 'StremioLibraryCodec.brs'),
    path.join(stagingDir, 'source', 'stores', 'LibraryStore.brs'),
    path.join(stagingDir, 'source', 'stores', 'StremioApiStore.brs'),
    path.join(stagingDir, 'source', 'stores', 'PlaybackStore.brs'),
    path.join(stagingDir, 'source', 'stores', 'SubtitlesStore.brs'),
    path.join(stagingDir, 'source', 'stores', 'WatchedCodec.brs')
];

// The ScreenStack drives every screen through the five callFunc'd contract
// functions — SetStores plus the four lifecycle hooks. They now live on the
// Screen base component and are inherited, so a screen only declares what it
// adds or overrides. Pin the contract at its source: the base must carry the
// five, every standard screen must extend it (a screen that skipped extends
// would not inherit SetStores and MainScene's callFunc would silently no-op),
// and a screen that re-declares a contract function locally must actually
// implement it (declare-without-impl was how BlurFocus silently no-opped before
// the base existed).
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
// so SetStores has to name the failure on screen. `print` cannot do that job:
// Roku routes BrightScript print to the Dev Console, not to the device console
// the app is debugged from, which is how a broken build looked like a rendering
// bug for two rounds.
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
    const STORES = ['addons', 'auth', 'episodes', 'library', 'settings', 'time', 'watch'];
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
        if (/^\s*print\s/m.test(src)) {
            err(`${name} uses print as a diagnostic — Roku routes BrightScript print to the Dev Console, not to the device console, so it is invisible where these bugs were debugged; make the failure visible in the UI instead`);
        }
    }
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

    // --- a reported fault has to be painted ----------------------------------
    if (!/<function\s+name="ReportStoreFault"\s*\/>/.test(sceneXml)) {
        err('MainScene.xml must declare <function name="ReportStoreFault" /> — callFunc only runs for interface functions, so every screen\'s fault report would go nowhere');
    }
    const report = mainScene.match(/^sub\s+ReportStoreFault\s*\(/m);
    if (!report) {
        err('MainScene.brs no longer defines ReportStoreFault — every screen\'s fault report would hit a non-function');
    } else if (!/^\s*RefreshStoreFaultStrip\(\)\s*$/m.test(mainScene.slice(report.index))) {
        err('MainScene.brs ReportStoreFault must CALL RefreshStoreFaultStrip — a fault recorded but never shown is the bug, not the fix');
    }
    const paint = mainScene.match(/^sub\s+RefreshStoreFaultStrip\s*\(\)/m);
    if (!paint) {
        err('MainScene.brs no longer defines RefreshStoreFaultStrip — a reported fault would never reach the screen');
        return ok;
    }
    const paintBody = bodyOf(mainScene, paint[0]);
    const initHeader = mainScene.match(/^sub\s+init\s*\(\)\s*$/m);
    const initBody = initHeader ? bodyOf(mainScene, initHeader[0]) : '';
    for (const [field, node] of [['m.faultBar', 'Rectangle'], ['m.faultText', 'Label']]) {
        if (!new RegExp(field + '\\s*=\\s*CreateObject\\(\\s*"roSGNode"\\s*,\\s*"' + node + '"').test(initBody)) {
            err(`MainScene.brs init must create ${field} (${node}) — the strip is built once, up front`);
        }
        if (!new RegExp('m\\.top\\.AppendChild\\(' + field + '\\)').test(initBody)) {
            err(`MainScene.brs init must attach ${field} to the Scene — an unattached node renders nothing, which is the exact shape of the bug being fixed`);
        }
    }
    // What the first version actually shipped was one line, and it is worth
    // having on record because it is the shape that painted nothing:
    //     strip.FindNode("storeFaultText").text = reasons.Join("     ")
    // — a strip built lazily, a Label written through a FindNode after the
    // append, and the line joined from an array. On device the bar painted and
    // the label stayed blank. Which of the three was at fault was never
    // isolated, so all three stay pinned out: the strip is created in init,
    // written through the fields themselves, and the line is concatenated.
    if (/CreateObject\(/.test(paintBody) || /AppendChild\(/.test(paintBody)) {
        err('MainScene.brs RefreshStoreFaultStrip must only write to the strip nodes init() already built — creating or attaching a node at paint time is one of the three shapes that shipped as a blank label');
    }
    if (/FindNode\(/.test(paintBody)) {
        err('MainScene.brs RefreshStoreFaultStrip must write to m.faultBar / m.faultText directly, not look them up by id — m.linkLabel.text = link in LinkStremioScreen is the shape known to render here');
    }
    if (!/m\.faultText\.text\s*=/.test(paintBody)) {
        err('MainScene.brs RefreshStoreFaultStrip must set m.faultText.text — a bar with no text says nothing');
    }
    if (/\.Join\(/.test(paintBody)) {
        err('MainScene.brs RefreshStoreFaultStrip must build the line by concatenation, not Join() over an array — the third of the three shapes that shipped as a blank label');
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

// Poster.loadStatus is a string with four legal values: notLoaded, loading,
// loaded, failed. Two guesses were shipped against it and both are invisible at
// build time: "ready" on the pairing screen's SUCCESS path, so a QR that loaded
// perfectly matched nothing and the column was never revealed; and "<> error"
// in both tiles, which is always true, so a poster whose image failed was
// treated as having art and its title fallback was suppressed. The literals are
// strings, so nothing but a static check stands between a guess and the device.
function checkPosterStatusContract() {
    const fs = require('fs');
    const LEGAL = ['notLoaded', 'loading', 'loaded', 'failed'];
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
    const screen = read('components/Screen.brs');
    const api = read('source/stores/StremioApiStore.bs');
    let ok = true;

    const subBody = (source, name) => {
        const start = source.indexOf(`sub ${name}()`);
        if (start === -1) return '';
        const next = source.indexOf('\nsub ', start + 1);
        return next === -1 ? source.slice(start) : source.slice(start, next);
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
    const result = subBody(brs, 'onAddonSyncResult');
    if (!/ClearAddonSyncFaults\(\)/.test(result)) {
        console.error('MainScene.brs onAddonSyncResult does not retract its previous fault lines — a retry that failed differently would leave stale errors up forever');
        ok = false;
    }
    if (!/if\s+not\s+result\.ok\s*\n[\s\S]{0,400}?AddAddonSyncFault\(/.test(result)) {
        console.error('MainScene.brs onAddonSyncResult still falls off the end when the sync fails — an unreported failed sync is indistinguishable from a healthy one');
        ok = false;
    }
    if (!/result\.error/.test(result)) {
        console.error('MainScene.brs onAddonSyncResult never reads result.error — the transport\'s own reason is discarded instead of shown');
        ok = false;
    }
    if (!/AddAddonSyncFault\(\s*"addon sync: the account reported no add-ons"/.test(result)) {
        console.error('MainScene.brs onAddonSyncResult must name the synced-but-empty outcome — that is the exact state that used to require re-pairing');
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
// interface functions the component declares, that both screens call into it
// (not into gone chips/menu nodes), and that no screen XML still hand-rolls the
// now-shared row/menu nodes.
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
        const screenXml = fs.readFileSync(path.join(root, 'components', `${screen}.xml`), 'utf8');
        if (screenXml.includes('Chips"') || screenXml.includes('Menu"')) {
            console.error(`${screen}.xml still hand-rolls chips/menu nodes — use <FilterBar> instead`);
            ok = false;
        }
    }
    return ok;
}

// The watch-state write-back worker must keep its contract (authKey + item in,
// result out with alwaysNotify) so the MainScene pump cannot silently mismatch
// a field the Task never declared.
function checkWatchStatePushTaskContract() {
    const fs = require('fs');
    const xml = fs.readFileSync(path.join(projectRoot, 'components', 'WatchStatePushTask.xml'), 'utf8');
    const declared = {};
    for (const match of xml.matchAll(/<field\s+id="([^"]+)"([^>]*)>/gi)) {
        declared[match[1]] = match[2];
    }
    let ok = true;
    for (const field of ['authKey', 'item']) {
        if (!declared[field]) {
            console.error(`WatchStatePushTask.xml is missing <field id="${field}" ... /> from its interface`);
            ok = false;
        }
    }
    if (!declared.result) {
        console.error('WatchStatePushTask.xml is missing <field id="result" ... /> from its interface');
        ok = false;
    } else if (!/alwaysNotify\s*=\s*"true"/.test(declared.result)) {
        console.error('WatchStatePushTask.xml: result field must be alwaysNotify="true"');
        ok = false;
    }
    return ok;
}

// The library write-back worker must keep its contract (authKey + item in,
// result out with alwaysNotify) so the MainScene pump cannot silently mismatch
// a field the LibraryWritePushTask never declared.
function checkLibraryWritePushTaskContract() {
    const fs = require('fs');
    const xml = fs.readFileSync(path.join(projectRoot, 'components', 'LibraryWritePushTask.xml'), 'utf8');
    const declared = {};
    for (const match of xml.matchAll(/<field\s+id="([^"]+)"([^>]*)>/gi)) {
        declared[match[1]] = match[2];
    }
    let ok = true;
    for (const field of ['authKey', 'item']) {
        if (!declared[field]) {
            console.error(`LibraryWritePushTask.xml is missing <field id="${field}" ... /> from its interface`);
            ok = false;
        }
    }
    if (!declared.result) {
        console.error('LibraryWritePushTask.xml is missing <field id="result" ... /> from its interface');
        ok = false;
    } else if (!/alwaysNotify\s*=\s*"true"/.test(declared.result)) {
        console.error('LibraryWritePushTask.xml: result field must be alwaysNotify="true"');
        ok = false;
    }
    return ok;
}

// The server-logout worker must keep its contract (authKey in, result out with
// alwaysNotify) so MainScene's fire-and-forget teardown cannot silently mismatch
// a field the Task never declared.
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

// The theme migration moved every painted color into theme.reads in init()
// plus script includes, because XML color attributes cannot call code. Two
// failure modes would slip past the interpreter: a component calling
// Theme()/AppPalette() without including Theme.bs (a bare-global lookup that
// dies at runtime, not at load), and a new hardcoded color creeping back into
// an XML. Pin both statically.
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
        const literal = xml.match(/color="0x[0-9A-Fa-f]{6,8}"/);
        if (literal) {
            console.error(`${name}.xml:2 hardcodes color ${literal[0]} — every painted color must come from Theme()`);
            ok = false;
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
    if (!onResult || !/m\.subtitleCursor\s*<\s*m\.subtitleCandidates\.Count\(\)[\s\S]{0,200}?LaunchSubtitleFetch\(\)/.test(onResult)) {
        err('PlayerScreen.onSubtitleResult no longer falls through to the next candidate when a provider returns nothing — picking a provider that cannot answer is back to meaning "no subtitles"');
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
// WatchStatePushTask inline — CreateObject + AppendChild + control = "RUN" —
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
    const xml = read('components/MainScene.xml');
    const player = read('components/PlayerScreen.brs');
    let ok = true;
    const err = (m) => { console.error(m); ok = false; };
    const code = (src) => src.split('\n').map(line => line.split("'")[0]).join('\n');
    const brs = code(main);
    const body = (name) => {
        const m = new RegExp(`^sub ${name}\\(\\)`, 'm').exec(brs);
        if (!m) return '';
        const lines = brs.slice(m.index).split('\n');
        for (let i = 0; i < lines.length; i++) {
            if (i > 0 && /^end sub\b/.test(lines[i])) return lines.slice(0, i + 1).join('\n');
        }
        return brs.slice(m.index);
    };

    // 1. The handler that the player's Video observer feeds must not build a
    //    node. This is the whole defect.
    const handler = body('onWatchStateUpdate');
    if (!handler) {
        err('MainScene.brs has no onWatchStateUpdate — the watch-state write-back has no entry point');
    } else {
        if (/AsyncTask_Launch\s*\(/.test(handler)) {
            err('MainScene.brs onWatchStateUpdate launches the push worker itself — this handler runs inside the player\'s Video "state" observer, and creating a node on that stack is what froze playback. Go through ScheduleWatchStatePush.');
        }
        if (/CreateObject\s*\(/.test(handler)) {
            err('MainScene.brs onWatchStateUpdate calls CreateObject — nothing on the Video state observer\'s stack may build a node');
        }
        if (!/ScheduleWatchStatePush\(\)/.test(handler)) {
            err('MainScene.brs onWatchStateUpdate does not defer through ScheduleWatchStatePush — the push would start on the Video state observer\'s stack');
        }
        // The gate that made this stremio-only, and the reason "works in guest"
        // proved nothing about it. Matched as a callFunc ARGUMENT — "AuthGet"
        // followed by a closing paren is a direct call, and this is a string
        // inside one.
        if (!/callFunc\(\s*"AuthGetSession"\s*\)\s*<>\s*"stremio"/.test(handler)) {
            err('MainScene.brs onWatchStateUpdate lost its stremio-session gate — a guest session would now do the write-back this bug lived in');
        }
    }

    // 2. The deferral has to be real: a one-shot timer, actually observed, and
    //    actually restarted per publish (a burst of pause/seek reports must not
    //    launch a worker per report).
    const schedule = body('ScheduleWatchStatePush');
    if (!schedule) {
        err('MainScene.brs has no ScheduleWatchStatePush — the deferral the player fix depends on is gone');
    } else {
        if (!/m\.watchStatePump\.control\s*=\s*"stop"[\s\S]{0,120}?m\.watchStatePump\.control\s*=\s*"start"/.test(schedule)) {
            err('MainScene.brs ScheduleWatchStatePush does not (re)start the one-shot pump timer — a timer that is never restarted pushes nothing, silently dropping every watch state');
        }
        if (!/m\.watchStatePump\s*=\s*invalid[\s\S]{0,200}?PumpWatchStatePush\(\)/.test(schedule)) {
            err('MainScene.brs ScheduleWatchStatePush has no inline fallback when the timer is missing — a wiring mistake would drop the user\'s watch state instead of pushing it');
        }
    }
    if (!/PumpWatchStatePush\(\)/.test(body('onWatchStatePumpFire') || '')) {
        err('MainScene.brs onWatchStatePumpFire does not pump — the deferral would resolve to nothing');
    }
    if (!/m\.watchStatePump\.ObserveField\(\s*"fire"\s*,\s*"onWatchStatePumpFire"\s*\)/.test(brs)) {
        err('MainScene.brs never observes the watchStatePump timer\'s fire field — the deferred push would never run');
    }
    if (!/<Timer\s+id="watchStatePump"[^>]*duration="1"/.test(xml)) {
        err('MainScene.xml has no <Timer id="watchStatePump" duration="1" ... /> — a FindNode miss means the deferral silently degrades to the inline push that froze the player');
    }
    if (!/<Timer\s+id="watchStatePump"[^>]*repeat="false"/.test(xml)) {
        err('MainScene.xml watchStatePump must be repeat="false" — a repeating one-shot pump would re-run forever and keep launching workers');
    }

    // 3. The deferred pump must carry the packet across the gap on state THIS
    //    scene owns, never on the player node: by the time a deferred pump
    //    runs, a Back-out may already have popped and destroyed the player.
    if (!/callFunc\(\s*"WatchLatest"\s*\)/.test(handler)) {
        err('MainScene.brs onWatchStateUpdate no longer reads the packet out of the shared watch buffer via WatchLatest() — the whole point of the buffer is that it outlives the player node that published it');
    }
    const pump = body('PumpWatchStatePush');
    if (!/packet\s*=\s*m\.pendingWatchState\b/.test(pump)) {
        err('MainScene.brs PumpWatchStatePush no longer takes its packet from m.pendingWatchState — a deferred pump cannot re-read the player node, it can only use the slot the handler left it');
    }

    // 4. The publisher itself must stay trivial. It runs on the Video observer's
    //    stack, so every line of it is a candidate for the same wedge.
    const publish = /sub PublishWatchState\(\)[\s\S]*?\nend sub/.exec(code(player));
    if (!publish) {
        err('PlayerScreen.brs has no PublishWatchState');
    } else {
        for (const forbidden of ['CreateObject', 'AppendChild', 'AsyncTask_Launch', 'Wait(']) {
            if (new RegExp(`\\b${forbidden.replace('(', '\\(')}`).test(publish[0])) {
                err(`PlayerScreen.brs PublishWatchState calls ${forbidden} — it runs inside the Video "state" observer, where anything but a local field write is what froze the player`);
            }
        }
        if (!/m\.top\.watchStateUpdate\s*=/.test(publish[0])) {
            err('PlayerScreen.brs PublishWatchState no longer publishes through the watchStateUpdate field — MainScene\'s deferred pump is fed by that write');
        }
    }

    return ok;
}

function checkScreensHidden() {
    const fs = require('fs');
    const xml = fs.readFileSync(path.join(projectRoot, 'components', 'MainScene.xml'), 'utf8');
    let ok = true;
    // Every static child of the Scene starts hidden so nothing flashes before the
    // stack shows it. The two custom dialogs are deliberately NOT here: they are
    // built with CreateObject (a dialog declared in markup dims the background and
    // paints nothing — see checkMainSceneContract), so there is nothing to hide.
    for (const name of ['HomeScreen', 'DetailsScreen', 'EpisodesScreen', 'StreamsScreen', 'SettingsScreen', 'AddonsScreen', 'SearchScreen', 'DiscoverScreen', 'LibraryScreen', 'AuthScreen', 'LinkStremioScreen']) {
        const element = xml.match(new RegExp(`<${name}[^>]*>`));
        if (!element) {
            console.error(`MainScene.xml is missing a <${name} ... /> child`);
            return false;
        }
        if (!/visible\s*=\s*"false"/.test(element[0])) {
            console.error(`MainScene.xml: <${name} ... /> must be declared visible="false"`);
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
        files: ['source/**/*.bs', 'bslib'],
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
    if (!checkScreenContract() || !checkScreensHidden() || !checkTileContract() || !checkPosterStatusContract() || !checkNoDuplicateScripts() || !checkStoreHandoffContract() || !checkLibraryCodecContract() || !checkMainSceneContract() || !checkSessionAuthorityContract() || !checkStremioProvisioningContract() || !checkAddonOrderingContract() || !checkWatchStatePushContract() || !checkHomeScreenContract() || !checkFilterBarContract() || !checkLibraryScreenContract() || !checkWatchStatePushTaskContract() || !checkLibraryWritePushTaskContract() || !checkLogoutTaskContract() || !checkSettingsPushContract() || !checkThemeContract()) {
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