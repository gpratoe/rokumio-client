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
// upstream noticed). The facade is published on the global AA — fetched with
// GetGlobalAA(), not a component, so the read is by reference — and read inside
// the receiving screen. Note roGlobal is a BrightSign component that does not
// exist on Roku: CreateObject("roGlobal") returns invalid, which the compiler
// also rejects as BS1129, so it can never be the carrier. The interpreter
// models one flat scope and cannot catch any of this, so pin it statically:
// MainScene must publish before binding, SetStores must take no argument, and
// no screen may be handed a store.
function checkStoreHandoffContract() {
    const fs = require('fs');
    let ok = true;
    // Scan code, not prose: the files document this exact contract in their
    // headers, and a raw-text scan matches the documentation describing the bug.
    const code = (src) => src.split('\n').map(line => line.split("'")[0]).join('\n');
    const mainScene = code(fs.readFileSync(path.join(projectRoot, 'components', 'MainScene.brs'), 'utf8'));
    const publish = mainScene.indexOf('.rokumioStores = m.stores');
    if (publish === -1) {
        console.error('MainScene.brs never publishes the facade — screens read it off the global AA, so nothing would bind');
        ok = false;
    } else {
        const firstBind = mainScene.search(/callFunc\("SetStores"/);
        if (firstBind !== -1 && firstBind < publish) {
            console.error('MainScene.brs binds a screen before publishing the facade on the global AA — that screen would read invalid');
            ok = false;
        }
    }
    for (const match of mainScene.matchAll(/callFunc\("SetStores"\s*,\s*([^)]*)\)/g)) {
        if (match[1].trim() !== 'invalid') {
            console.error(`MainScene.brs passes "${match[1].trim()}" through callFunc("SetStores", ...) — a class instance cannot survive that hop; pass invalid and let SetStores read the global AA`);
            ok = false;
        }
    }
    // A screen binding the facade from an undeclared m field is exactly what the
    // global-AA read replaces; a redeclared interface field would marshal the
    // value and strip the methods again, so m.stores must stay undeclared.
    const screenXml = fs.readFileSync(path.join(projectRoot, 'components', 'Screen.xml'), 'utf8');
    if (/<field\s+id="stores"/i.test(screenXml)) {
        console.error('Screen.xml must not declare <field id="stores"> — assigning the facade to a node field copies it and drops its methods; keep m.stores undeclared');
        ok = false;
    }
    const screenBrs = code(fs.readFileSync(path.join(projectRoot, 'components', 'Screen.brs'), 'utf8'));
    // Match the definition only: the header comment also spells
    // `function SetStores()`, and a first-match regex would read that instead.
    const setStores = screenBrs.match(/^function\s+SetStores\s*\(([^)]*)\)/m);
    if (!setStores) {
        console.error('Screen.brs no longer defines SetStores — every screen would come up with no stores');
        ok = false;
    } else if (setStores[1].trim() !== '') {
        console.error(`Screen.brs SetStores must take no argument (found "${setStores[1].trim()}") — a passed-in facade arrives without its methods`);
        ok = false;
    }
    if (!/GetGlobalAA\(\)/.test(screenBrs)) {
        console.error('Screen.brs SetStores must read the facade off the global AA (GetGlobalAA()) so the class instances arrive by reference');
        ok = false;
    }
    // No other component may take a store through callFunc or an interface
    // field either; the stores are reachable from the global AA and nowhere else.
    for (const name of fs.readdirSync(path.join(projectRoot, 'components')).filter(f => f.endsWith('.brs'))) {
        const src = code(fs.readFileSync(path.join(projectRoot, 'components', name), 'utf8'));
        for (const match of src.matchAll(/callFunc\([^,]+,\s*(m\.stores[^)]*)\)/g)) {
            console.error(`${name} passes the store facade through callFunc (${match[1].trim()}) — that hop drops every method; bind with SetStores and read the global AA instead`);
            ok = false;
        }
        if (/CreateObject\(\s*"roGlobal"/i.test(src)) {
            console.error(`${name} uses CreateObject("roGlobal") — roGlobal is a BrightSign component, not a Roku one; CreateObject returns invalid. Use GetGlobalAA()`);
            ok = false;
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
    const brs = fs.readFileSync(path.join(projectRoot, 'components', 'MainScene.brs'), 'utf8');
    const calls = [...brs.matchAll(/\.SwitchSession\s*\(/g)].map(match => match.index);
    if (calls.length === 0) {
        console.error('MainScene.brs no longer calls SwitchSession anywhere — session-aware stores never pivot');
        return false;
    }
    const subStart = brs.indexOf('sub ReconcileSession()');
    const nextSub = brs.indexOf('\nsub ', subStart + 1);
    const body = nextSub === -1 ? brs.slice(subStart) : brs.slice(subStart, nextSub);
    let ok = true;
    for (const index of calls) {
        if (index < subStart || index > nextSub) {
            console.error(`MainScene.brs calls SwitchSession at byte ${index}, outside sub ReconcileSession() — every pivot must go through the authority`);
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