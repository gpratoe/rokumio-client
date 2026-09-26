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

function checkScreensHidden() {
    const fs = require('fs');
    const xml = fs.readFileSync(path.join(projectRoot, 'components', 'MainScene.xml'), 'utf8');
    let ok = true;
    for (const name of ['HomeScreen', 'DetailsScreen', 'EpisodesScreen', 'StreamsScreen', 'SettingsScreen', 'AddonsScreen', 'SearchScreen', 'DiscoverScreen', 'LibraryScreen', 'AuthScreen', 'LinkStremioScreen', 'ConfirmExitDialog', 'SupportDialog']) {
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
    if (!checkScreenContract() || !checkScreensHidden() || !checkTileContract() || !checkNoDuplicateScripts() || !checkStoreHandoffContract() || !checkLibraryCodecContract() || !checkMainSceneContract() || !checkSessionAuthorityContract() || !checkHomeScreenContract() || !checkFilterBarContract() || !checkLibraryScreenContract() || !checkWatchStatePushTaskContract() || !checkLibraryWritePushTaskContract() || !checkLogoutTaskContract() || !checkSettingsPushContract() || !checkThemeContract()) {
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