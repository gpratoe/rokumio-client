import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

// Regression guard for the "store API symmetry" bug class: a component calling
// `m.<store>.<method>(...)` where the store never defines `<method>` (or an
// accessor that was dropped during extraction). These only fail at runtime
// with "Function Call Operator ( ) attempted on non-function" (&he0).
//
// This scans every .brs file under components/, records every store call that
// maps to a known store file, and asserts each method name is defined there as
// `store.<method> = function`. Cross-store calls through injected references
// (`m._addonStore`, `m._libraryStore`) resolve to their owning store file too.

const root = process.cwd();
const componentsDir = path.join(root, 'components');
const storeFiles = fs
    .readdirSync(componentsDir)
    .filter((name) => /Store\.brs$/.test(name));

if (storeFiles.length === 0) {
    console.error('No store files found to validate.');
    process.exit(1);
}

function storeFileFor(target) {
    const base = target.replace(/^_+/, '');
    const file = base.charAt(0).toUpperCase() + base.slice(1) + '.brs';
    return storeFiles.includes(file) ? file : null;
}

function definedMethods(file) {
    const text = fs.readFileSync(path.join(componentsDir, file), 'utf8');
    const methods = new Set();
    const pattern = /\bstore\.([A-Za-z_][A-Za-z0-9_]*)\s*=\s*function\b/g;
    let match;
    while ((match = pattern.exec(text)) !== null) methods.add(match[1]);
    return methods;
}

const methodsByFile = Object.fromEntries(
    storeFiles.map((file) => [file, definedMethods(file)])
);

const failures = [];
const callPattern = /m\.([A-Za-z_][A-Za-z0-9_]*Store)\.([A-Za-z_][A-Za-z0-9_]*)\s*\(/g;

for (const source of fs.readdirSync(componentsDir).filter((name) => /\.brs$/.test(name))) {
    const sourceText = fs.readFileSync(path.join(componentsDir, source), 'utf8');
    let match;
    while ((match = callPattern.exec(sourceText)) !== null) {
        const calleeFile = storeFileFor(match[1]);
        if (calleeFile === null) continue;
        if (source === calleeFile) continue; // self-call via the store's own m. field is not a public API check
        const method = match[2];
        if (!methodsByFile[calleeFile].has(method)) {
            failures.push(`${source} calls m.${match[1]}.${method}(...) but ${calleeFile} does not define store.${method} = function`);
        }
    }
}

if (failures.length > 0) {
    console.error('Store API checks failed:');
    for (const failure of failures) console.error(`- ${failure}`);
    process.exit(1);
}

console.log('Store API checks passed.');