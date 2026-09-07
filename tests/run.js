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
        'tests/catalogstore.test.brs',
        'tests/episodesstore.test.brs',
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
    path.join(stagingDir, 'source', 'stores', 'EpisodesStore.brs')
];

function checkScreenContract() {
    const fs = require('fs');
    const contract = ['OnEnter', 'OnExit', 'OnBackPressed', 'BlurFocus'];
    const screens = ['HomeScreen', 'DummyDetail', 'ConfirmExitDialog'];
    let ok = true;
    for (const name of screens) {
        const xml = fs.readFileSync(path.join(projectRoot, 'components', `${name}.xml`), 'utf8');
        const declared = new Set(
            [...xml.matchAll(/<function\s+name="([^"]+)"\s*\/?>/gi)].map(match => match[1])
        );
        for (const fn of contract) {
            if (!declared.has(fn)) {
                console.error(`${name}.xml is missing <function name="${fn}" /> from its interface`);
                ok = false;
            }
        }
    }
    return ok;
}

// MarkupGrid only updates item components through interface fields named
// `itemContent` and `itemHasFocus` — never `content` or `focused`. This bit us:
// PosterTile observed the wrong fields and never rendered text or focus. Guard
// the interface so the tile's render contract stays pinned to the grid's API.
function checkItemContract() {
    const fs = require('fs');
    const xml = fs.readFileSync(path.join(projectRoot, 'components', 'PosterTile.xml'), 'utf8');
    const declared = new Set(
        [...xml.matchAll(/<field\s+id="([^"]+)"[\s>]/gi)].map(match => match[1])
    );
    let ok = true;
    for (const field of ['itemContent', 'itemHasFocus', 'rowHasFocus']) {
        if (!declared.has(field)) {
            console.error(`PosterTile.xml is missing <field id="${field}" ... /> from its interface`);
            ok = false;
        }
    }
    return ok;
}

// Group.visible defaults to true, and screens are declared children of the
// Scene, so an undisclosed screen paints over the stack's top screen (this bit
// us: DummyDetail covered HomeScreen from the first frame). Screens must start
// hidden; only the stack makes them visible.
function checkScreensHidden() {
    const fs = require('fs');
    const xml = fs.readFileSync(path.join(projectRoot, 'components', 'MainScene.xml'), 'utf8');
    let ok = true;
    for (const name of ['HomeScreen', 'DummyDetail', 'ConfirmExitDialog']) {
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
    if (!checkScreenContract() || !checkScreensHidden() || !checkItemContract()) {
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