import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

// Static checks over the BrightScript sources for the UI scaling rules. These are
// the mistakes that do not show up until the app is on a TV, so they are worth
// catching without a device or a simulator.

const root = process.cwd();
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');

const mainScene = read('components/MainScene.brs');
const settingsSource = read('components/Settings.brs');
const componentSources = fs
    .readdirSync(path.join(root, 'components'))
    .filter((file) => file.endsWith('.brs'))
    .map((file) => ({ file: `components/${file}`, source: read(`components/${file}`) }));

const failures = [];

checkSliderTakesFocus();
checkSliderKeyHandling();
checkUiScaleOpensOnOk();
checkSettingsListDispatchesOwnRows();
checkEverySelectableSettingsRowHasAHandler();
checkRuntimeCoordinatesAreScaled();

if (failures.length > 0) {
    console.error('UI scale checks failed:');
    for (const failure of failures) {
        console.error(`- ${failure}`);
    }
    process.exit(1);
}

console.log('UI scale checks passed.');

// A LabelList keeps focus unless it is explicitly blurred, and then it swallows
// OK and the arrows before the scene's onKeyEvent runs, leaving the slider open
// but inert.
function checkSliderTakesFocus() {
    const open = functionBody(mainScene, 'OpenUiScaleSlider');
    if (!open) {
        failures.push('MainScene.brs: missing OpenUiScaleSlider');
        return;
    }

    // Board/library content now lives in the browse screen; the settings list is
    // blurred separately. Both have to lose focus before the scene takes it.
    const blur = open.indexOf('m.browseScreen.CallFunc("BlurFocus")');
    const settingsBlur = open.indexOf('m.settingsScreen.SetFocus(false)');
    const focus = open.indexOf('m.top.SetFocus(true)');
    if (blur < 0 || settingsBlur < 0) {
        failures.push('OpenUiScaleSlider must blur m.browseScreen and the settings screen before the scene takes focus');
    } else if (focus < 0) {
        failures.push('OpenUiScaleSlider must give focus to the scene so onKeyEvent receives keys');
    } else if (blur > focus || settingsBlur > focus) {
        failures.push('OpenUiScaleSlider blurs m.browseScreen/the settings screen after m.top.SetFocus(true); a list keeps focus');
    }

    const close = functionBody(mainScene, 'CloseUiScaleSlider');
    if (!close) {
        failures.push('MainScene.brs: missing CloseUiScaleSlider');
    } else if (!close.includes('FocusActiveContent()')) {
        failures.push('CloseUiScaleSlider must hand focus back to the settings list');
    }
}

function checkSliderKeyHandling() {
    const onKeyEvent = functionBody(mainScene, 'onKeyEvent');
    if (!onKeyEvent) {
        failures.push('MainScene.brs: missing onKeyEvent');
        return;
    }

    const branch = onKeyEvent.indexOf('m.screenMode = "uiScale"');
    if (branch < 0) {
        failures.push('onKeyEvent has no branch for the uiScale screen mode');
        return;
    }

    // The branch must run before the "options" handler, otherwise * opens the
    // settings dialog on top of the slider instead of resetting the scale.
    const optionsHandler = onKeyEvent.indexOf('if key = "options"');
    if (optionsHandler >= 0 && optionsHandler < branch) {
        failures.push('the uiScale branch in onKeyEvent must come before the "options" handler');
    }

    const branchBody = onKeyEvent.slice(branch, branch + 1200);
    for (const key of ['"left"', '"right"', '"OK"', '"back"', '"options"']) {
        if (!branchBody.includes(key)) {
            failures.push(`the uiScale branch in onKeyEvent does not handle ${key}`);
        }
    }

    // Anti-regression: the settings list activates a row through its itemSelected
    // observer (see checkSettingsListDispatchesOwnRows), NOT through onKeyEvent. An
    // old onKeyEvent branch re-dispatched ActivateSettingsRow for the same OK press,
    // so itemSelected ran the row's action and the identical press then reached
    // onKeyEvent and ran it again -- language cycles skipped languages and toggles
    // flipped twice. Keep activation single-path: onKeyEvent must never activate a
    // settings row.
    if (onKeyEvent.includes('ActivateSettingsRow(m.settingsRows[m.settingsFocusIndex])')) {
        failures.push('onKeyEvent must not also activate the focused settings row on OK; the itemSelected observer is the single activation path');
    }
}

// The UI scale slider opens on an explicit OK, like every other settings row,
// through the uiScale branch of ActivateAction. It must NOT open on focus: an old
// MaybeOpenFocusedSettingsRow workaround opened it the moment the cursor landed on
// the row, because OK was double-dispatched (itemSelected plus onKeyEvent) and
// would have opened-then-immediately-closed it. That root cause is fixed, so the
// slider opens the normal way and focus navigation stays purely navigational.
function checkUiScaleOpensOnOk() {
    const dispatch = functionBody(mainScene, 'ActivateAction');
    if (!dispatch) {
        failures.push('MainScene.brs: missing ActivateAction');
        return;
    }
    if (!dispatch.includes('actionType = "uiScale"')) {
        failures.push('ActivateAction must detect the uiScale settings row');
    }
    if (!dispatch.includes('OpenUiScaleSlider()')) {
        failures.push('ActivateAction must open the UI scale slider on OK');
    }

    if (mainScene.includes('MaybeOpenFocusedSettingsRow')) {
        failures.push('MainScene.brs: MaybeOpenFocusedSettingsRow must be removed; the UI scale slider opens on OK, not on focus');
    }
}

// Settings rows are rendered from the Settings component's own MarkupList. The
// component observes itemSelected inside itself and reports the activated row
// through its action field. MainScene observes that field, so activation still
// routes through the shared ActivateAction dispatcher (the single activation
// path) without the scene reaching into the row list.
function checkSettingsListDispatchesOwnRows() {
    if (!mainScene.includes('m.settingsScreen.ObserveField("action", "onSettingsScreenAction")')) {
        failures.push('settingsScreen action must dispatch through onSettingsScreenAction');
    }

    const dispatched = functionBody(mainScene, 'onSettingsScreenAction');
    if (!dispatched) {
        failures.push('MainScene.brs: missing onSettingsScreenAction');
        return;
    }

    if (!dispatched.includes('ActivateAction(action.type, action.payload)')) {
        failures.push('onSettingsScreenAction must dispatch the row action to ActivateAction');
    }
}

// A settings row wired to an action type with no handler renders as a normal,
// selectable row that silently does nothing when the user presses OK.
function checkEverySelectableSettingsRowHasAHandler() {
    const dispatch = functionBody(mainScene, 'ActivateAction');
    if (!dispatch) {
        failures.push('MainScene.brs: missing ActivateAction');
        return;
    }

    const handled = new Set();
    for (const match of dispatch.matchAll(/actionType\s*=\s*"(?<type>[^"]+)"/g)) {
        handled.add(match.groups.type);
    }

    // Info rows carry the action type second; settings rows carry a display
    // value first, so theirs is third. Both dispatch in MainScene via the same
    // ActivateAction dispatcher. InfoAction rows live in the browse screen
    // (library signed-out list); SettingRow rows live in the Settings component.
    const declared = new Set();
    for (const { source } of componentSources) {
        for (const args of callArguments(source, 'InfoAction')) {
            const actionType = args[1]?.trim();
            const literal = actionType?.match(/^"([^"]*)"$/);
            if (literal) declared.add(literal[1]);
        }
    }
    for (const args of callArguments(settingsSource, 'SettingRow')) {
        const actionType = args[2]?.trim();
        const literal = actionType?.match(/^"([^"]*)"$/);
        if (literal) declared.add(literal[1]);
    }

    // "none" is the deliberate marker for an informational row.
    declared.delete('none');

    for (const type of [...declared].sort()) {
        if (!handled.has(type)) {
            failures.push(`settings row action "${type}" has no branch in ActivateAction`);
        }
    }
}

// Layout is authored in 1920x1080 design space; anything assigned at runtime has
// to go through ScaleUi/ScaleUiXY or it lands at the wrong place on an HD player.
function checkRuntimeCoordinatesAreScaled() {
    for (const { file, source } of componentSources) {
        for (const match of source.matchAll(/\.translation\s*=\s*\[(?<pair>[^\]]*)\]/g)) {
            const parts = match.groups.pair.split(',').map((part) => part.trim());
            const literals = parts.map(Number);
            if (literals.some(Number.isNaN)) continue; // computed, not a raw coordinate
            if (literals.every((value) => value === 0)) continue; // the origin scales to itself
            failures.push(`${file}: raw design-space translation ${match[0]}; wrap it in ScaleUiXY`);
        }

        for (const match of source.matchAll(/\.(?<field>width|height)\s*=\s*(?<value>-?\d+(?:\.\d+)?)\s*$/gm)) {
            if (Number(match.groups.value) === 0) continue;
            failures.push(`${file}: raw design-space ${match.groups.field} ${match[0].trim()}; wrap it in ScaleUi`);
        }
    }
}

function functionBody(source, name) {
    const start = source.search(new RegExp(`^(sub|function)\\s+${name}\\s*\\(`, 'm'));
    if (start < 0) return undefined;
    const tail = source.slice(start);
    const stop = tail.search(/^end (sub|function)\s*$/m);
    return stop < 0 ? tail : tail.slice(0, stop);
}

// Splits the top-level arguments of every call to `name`, so nested calls and
// the commas inside them do not confuse the caller.
function callArguments(source, name) {
    const calls = [];
    const opener = `${name}(`;

    for (let index = source.indexOf(opener); index >= 0; index = source.indexOf(opener, index + 1)) {
        let depth = 0;
        let inString = false;
        let current = '';
        const args = [];

        for (let cursor = index + opener.length - 1; cursor < source.length; cursor += 1) {
            const character = source[cursor];
            if (character === '"') inString = !inString;

            if (!inString && character === '(') {
                depth += 1;
                if (depth === 1) continue;
            } else if (!inString && character === ')') {
                depth -= 1;
                if (depth === 0) {
                    args.push(current);
                    break;
                }
            } else if (!inString && character === ',' && depth === 1) {
                args.push(current);
                current = '';
                continue;
            }

            current += character;
        }

        calls.push(args);
    }

    return calls;
}
