import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const root = process.cwd();
const mainScene = fs.readFileSync(path.join(root, 'components/MainScene.brs'), 'utf8');
const videoPlayer = fs.readFileSync(path.join(root, 'components/StrokuVideoPlayer.brs'), 'utf8');
const videoXml = fs.readFileSync(path.join(root, 'components/StrokuVideoPlayer.xml'), 'utf8');
const episodeCard = fs.readFileSync(path.join(root, 'components/EpisodeCard.brs'), 'utf8');
const episodeXml = fs.readFileSync(path.join(root, 'components/EpisodeCard.xml'), 'utf8');
const locale = fs.readFileSync(path.join(root, 'components/Locale.brs'), 'utf8');
const settings = fs.readFileSync(path.join(root, 'components/Settings.brs'), 'utf8');
const settingsXml = fs.readFileSync(path.join(root, 'components/Settings.xml'), 'utf8');
const addons = fs.readFileSync(path.join(root, 'components/Addons.brs'), 'utf8');
const settingsStore = fs.readFileSync(path.join(root, 'components/SettingsStore.brs'), 'utf8');
const addonStore = fs.readFileSync(path.join(root, 'components/AddonStore.brs'), 'utf8');
const libraryStore = fs.readFileSync(path.join(root, 'components/LibraryStore.brs'), 'utf8');
const authStore = fs.readFileSync(path.join(root, 'components/AuthStore.brs'), 'utf8');
const catalogStore = fs.readFileSync(path.join(root, 'components/CatalogStore.brs'), 'utf8');
const calendarStore = fs.readFileSync(path.join(root, 'components/CalendarStore.brs'), 'utf8');

// The search dialog copy now lives in the localization layer, so the
// "does not overpromise TVDB" guarantee is asserted against the English table
// rather than against a literal in MainScene.brs.
const englishTable = (locale.match(/function LocaleStringsEnglish\(\) as object([\s\S]*?)\nend function/) || [])[1] || '';

const failures = [];

const requiredMainPatterns = [
    ['Remote add-on details handler', /sub ShowAddonDetails\(addon as object\)/],
    ['Installed add-on details handler', /sub ShowInstalledAddonDetails\(index as integer\)/],
    ['Settings links handler', /sub OpenSettingsLink\(kind as string\)/],
    ['Blur unwatched episodes writes card field', /blurThumbnail: true/],
    // The calendar is a card list now, not an info list. This used to match
    // RenderInfoList, which the calendar no longer goes through, so it passed
    // without proving anything about the calendar.
    ['Calendar refresh preserves focused control', /else if not focusContent\s+targetIndex = m\.calendarFocusIndex/],
    ['Calendar chips and cards do not both own the Addons screen', /sub DispatchAddonAction\(actionType as string, payload as dynamic\)/],
    ['Addons toolbar is reachable from the card list', /m\.addonsScreen\.callFunc\("FocusChips"\)/],
    ['IMDb ID resolver', /function IsImdbId\(value as string\) as boolean/],
    ['Search dialog copy routes through the localization layer', /dialog\.message = TrText\("dialog\.search\.message"\)/],
];

const requiredAddonsPatterns = [
    ['Addons Installed filter action', /AddonChip\(TrText\("addons\.filter\.installed"\),\s*"addonFilterInstalled"/],
    ['Addons All filter action', /AddonChip\(TrText\("addons\.filter\.all"\),\s*"addonFilterAll"/],
    ['Reload add-ons survives on the Addons screen', /AddonChip\(TrText\("addons\.reload"\),\s*"reloadAddons"/],
    ['Addons toolbar is focusable from the card list', /sub FocusChips\(\)/],
    ['Addons toolbar hands OK to the chip it is on', /ActivateAddonChip\(m\.addonChipIndex\)/],
];

const requiredSettingsStorePatterns = [
    ['Settings store persists interface preferences', /store\.saveInterfacePreferences = function\(\)/],
    ['Settings store persists player preferences', /store\.savePlayerPreferences = function\(\)/],
    ['Settings store persists subtitle preferences', /store\.saveSubtitlePreferences = function\(\)/],
    ['Settings store persists streaming server config', /store\.saveStreamingServerConfig = function\(\)/],
    ['Settings store loads all stored preferences', /store\.load = function\(\)/],
];

const requiredAddonStorePatterns = [
    ['Addon store loads configured manifest urls', /store\.load = function\(\)[\s\S]*?addonManifestUrls/],
    ['Addon store persists configured manifest urls', /store\.saveUrls = function\(\)[\s\S]*?addonManifestUrls/],
    ['Addon store owns the add-ons collection URL', /store\.requestCatalog = function\(\)[\s\S]*?https:\/\/api\.strem\.io\/addonscollection\.json/],
    ['Addon store builds the discovery catalog from the collection', /store\.handleCatalogResponse = function\(data[\s\S]*?store\.IsValidAddonManifest|store\.handleCatalogResponse = function\(data[\s\S]*?m\._catalog = catalog/],
    ['Addon store verifies a candidate manifest URL', /store\.verify = function\(url as string\)[\s\S]*?config\|addon/],
    ['Addon store saves a verified add-on', /store\.handleVerifyResponse = function\(manifest[\s\S]*?addOrReplace[\s\S]*?saveUrls/],
    ['Addon store validates manifests', /store\.IsValidAddonManifest = function\(/],
    ['Addon store clears its pending verification URL', /store\.clearPendingAddonUrl = function\(\)/],
    ['Addon store reloads configured manifests', /store\.reload = function\(\)[\s\S]*?clearInstalled/],
    ['Addon store processes a loaded manifest', /store\.handleManifestLoadResponse = function\(/],
];

const requiredLibraryStorePatterns = [
    ['Library store fetches the library via datastoreGet', /store\.fetch = function\(authKey as string\)[\s\S]*?datastoreGet/],
    ['Library store processes datastoreGet responses', /store\.handleGetResponse = function\(data[\s\S]*?m\._libraryById = \{\}/],
    ['Library store toggles library membership', /store\.toggle = function[\s\S]*?mode: "put"/],
    ['Library store builds the silent progress put', /store\.buildProgressPut = function[\s\S]*?libraryPutSilent/],
    ['Library store processes datastorePut responses', /store\.handlePutResponse = function\(data as dynamic\) as boolean/],
    ['Library store computes the action label', /store\.libraryActionLabel = function\(item as dynamic, authKey as string\) as string/],
    ['Library store rebuilds the catalog from authoritative state', /store\.rebuildCatalog = function\(\)[\s\S]*?m\._libraryItems = \[\]/],
    ['Library store exposes catalog accessors', /store\.getLibraryItems = function\(\) as object[\s\S]*?store\.hasById = function\(id as string\) as boolean/],
    ['Library store owns the derived watched list', /store\.getWatchedItems = function[\s\S]*?m\.HasWatchedActivity/],
];

const requiredAuthStorePatterns = [
    ['Auth store owns the auth key', /store\.getAuthKey = function/],
    ['Auth store reads auth key from registry', /store\.load = function[\s\S]*?roRegistrySection/],
    ['Auth store persists auth key to registry', /store\.save = function[\s\S]*?section\.Write/],
    ['Auth store clears registry on disconnect', /store\.clear = function[\s\S]*?section\.Delete/],
    ['Auth store builds the link create request', /store\.buildLinkCreate = function[\s\S]*?link\.stremio\.com/],
    ['Auth store handles the create response', /store\.handleLinkCreateResponse = function[\s\S]*?m\._linkCode/],
    ['Auth store builds the link read request', /store\.buildLinkRead = function[\s\S]*?link\.stremio\.com\/api\/v2\/read/],
    ['Auth store handles the read response', /store\.handleLinkReadResponse = function[\s\S]*?m\.save/],
    ['Auth store reports signed-in state', /store\.isSignedIn = function[\s\S]*?m\._authKey <> ""/],
    ['Auth store cancels an in-progress link', /store\.cancelLink = function[\s\S]*?m\._linkCode = ""/],
];

const requiredCatalogStorePatterns = [
    ['Catalog store owns the board rows', /store\.getBoardRows = function[\s\S]*?m\._boardRows/],
    ['Catalog store owns the discover rows', /store\.getDiscoverRows = function[\s\S]*?m\._discoverRows/],
    ['Catalog store fetches the six board catalogs', /store\.fetchBoardCatalogs = function[\s\S]*?boardCatalog\|0[\s\S]*?caching\.stremio\.net\/publicdomainmovies/],
    ['Catalog store builds the discover catalog request', /store\.buildDiscoverCatalog = function[\s\S]*?v3-cinemeta\.strem\.io\/catalog/],
    ['Catalog store resets + restarts discover', /store\.restartDiscoverCatalog = function[\s\S]*?m\._discoverRequestActive = true[\s\S]*?return m\.buildDiscoverCatalog/],
    ['Catalog store owns the channel search request', /catalog\/channel\/top\/search=/],
    ['Catalog store processes catalog responses', /store\.handleCatalogResponse = function[\s\S]*?m\._discoverRows\[rowIndex\]/],
    ['Catalog store processes IMDb-ID meta responses', /store\.handleSearchMetaResponse = function[\s\S]*?return true/],
    ['Catalog store owns the discover filter values', /store\.getDiscoverType = function[\s\S]*?store\.setDiscoverType = function/],
    ['Catalog store reports empty discover rows', /store\.discoverRowsEmpty = function/],
];

const requiredCalendarStorePatterns = [
    ['Calendar store owns the entries', /store\.getEntries = function/],
    ['Calendar store tracks request activity', /store\.getRequestActive = function/],
    ['Calendar store clears on sign-out', /store\.reset = function/],
    ['Calendar metadata requests are capped', /m\.countTrackedSeries\(\) >= 24/],
    ['Calendar metadata concurrency is capped', /pending >= 4/],
    ['Calendar metadata request', /"calendarMeta\|"/],
    ['Calendar store processes metadata responses', /store\.handleMetaResponse = function/],
    ['Calendar entries are trimmed', /store\.trimEntries = function/],
    ['Calendar full sort removed from action build', /m\.addSortedEntry\(upcoming,\s*entry,\s*true,\s*12\)/],
    ['Calendar entries render dated episodes', /store\.entryTitle = function\(entry as object\) as string/],
    ['Calendar loading row is inert', /m\.messageRow\(TrText\("calendar\.loading"\)\)/],
    ['Calendar upcoming header is inert', /m\.headerRow\(TrText\("calendar\.section\.upcoming"\)\)/],
    ['Calendar recent header is inert', /m\.headerRow\(TrText\("calendar\.section\.recent"\)\)/],
    ['Calendar message rows are inert by construction', /store\.messageRow = function\(title as string\) as object[\s\S]*?m\.row\("message", title, "none"/],
    ['Calendar header rows are inert by construction', /store\.headerRow = function\(title as string\) as object[\s\S]*?m\.row\("header", title, "none"/],
    ['Calendar store builds the signed-out rows', /store\.buildSignedOutRows = function/],
    ['Calendar store builds the action rows', /store\.buildActions = function/],
];

const requiredLocalePatterns = [
    ['Search copy does not overpromise TVDB', /"dialog\.search\.message":\s*"Search movies, series, and channels/],
];

const forbiddenMainPatterns = [
    ['Installed filter reverted to no-op', /InfoAction\("Installed",\s*"none"/],
    ['All filter reverted to no-op', /InfoAction\("All",\s*"none"/],
    ['General settings links reverted to no-op', /SettingRow\("(Contact support|Source code|Terms of Service|Privacy Policy)",\s*[^,]+,\s*"none"/],
    ['Interface settings reverted to static rows', /SettingRow\("UI language",\s*[^,]+,\s*"none"/],
    ['Player defaults reverted to static rows', /SettingRow\("Default (language|audio track)",\s*[^,]+,\s*"none"/],
    ['Search dialog still advertises unsupported TVDB', /IMDB\/TVDB IDs/],
    ['App version hardcoded to a Stremio-mimicking literal', /appVersion"\),\s*"/],
    ['Streaming settings tab reintroduced', /"General",\s*"Interface",\s*"Player",\s*"Streaming"/],
    ['Settings up/down still routed through the scene onKeyEvent', /else if \(key = "up" or key = "down"\) and m\.activeTab = "settings" and m\.settings(Screen|List)\.HasFocus\(\)[\s\S]*?return (true|FocusSettings)/],
    ['Settings left/right still routed through the scene onKeyEvent', /key = "left" and m\.activeTab = "settings" and m\.settingsList\.HasFocus\(\)/],
    ['Settings focus echo suppression moved back into the scene', /m\.settingsSuppressIndex/],
    ['Library state still mutated directly in the scene', /m\.libraryById\[.*?\]\s*=/],
    ['Auth key still written to registry directly in the scene', /section\.Write\("stremioAuthKey"/],
    ['Catalog state still mutated directly in the scene', /m\.(boardRows|discoverRows)\[|m\.discover(Type|Catalog|Genre|RequestActive)\s*=/],
    ['Calendar state still mutated directly in the scene', /m\.calendar(Entries|LoadedSeries)[\[\]]+|m\.calendar(Entries|RequestActive|LoadedSeries)\s*=/],
];

const requiredSettingsPatterns = [
    ['Settings rows carry a value, kind, and hint', /function SettingRow\(title as string, value as string, actionType as string, payload as dynamic, kind as string, hint as string\)/],
    ['Settings sections are headers rather than list rows', /function SettingHeader\(title as string\)/],
    ['Settings skip headers when chasing a focus target', /function NextSelectableSettingsIndex\(/],
    ['Settings detail panel follows the focused row', /sub UpdateSettingsDetail\(index as integer\)/],
    ['Settings component skips headers before focus changes', /function NextSelectableIndex\(fromIndex as integer, direction as integer\) as integer[\s\S]*?RowIsHeader\(index\)/],
    ['Settings component owns header skipping on focus', /sub onItemFocused[\s\S]*?if RowIsHeader\(index\)[\s\S]*?NextSelectableIndex\(index, direction\)/],
    ['Settings component reports row activation to the scene', /sub onItemSelected[\s\S]*?m\.top\.action = \{/],
    ['Settings component owns tab navigation internally', /function onKeyEvent[\s\S]*?if key = "left"[\s\S]*?m\.settingsTabIndex = m\.settingsTabIndex - 1[\s\S]*?else if key = "right"[\s\S]*?m\.settingsTabIndex = m\.settingsTabIndex \+ 1/],
    ['App version comes from the device rather than a literal', /SettingRow\(TrText\("settings\.general\.appVersion"\),\s*AppVersionValue\(\)/],
    ['App version reads roAppInfo', /function AppVersionValue\(\) as string/],
    ['Channel build reads roAppInfo', /function AppBuildValue\(\) as string/],
];

const requiredSettingsXmlPatterns = [
    ['Settings component exposes action and screenInfo outputs', /<field id="action" type="assocarray"/],
    ['Settings component exposes a screenInfo output', /<field id="screenInfo" type="assocarray"/],
    ['Settings component takes state from the scene', /<field id="state" type="assocarray"/],
];

const requiredVideoPatterns = [
    ['Default subtitle field exposed', /field id="defaultSubtitleLanguage"/],
    ['Default audio field exposed', /field id="defaultAudioTrack"/],
    ['Default subtitle chooser implemented', /function DefaultSubtitleIndex\(\) as integer/],
    ['Default audio chooser implemented', /sub ApplyDefaultAudioTrack\(\)/],
];

const requiredEpisodePatterns = [
    ['Unwatched thumbnail overlay node exposed', /id="thumbnailScrim"/],
    ['Unwatched thumbnail overlay driven by content field', /content\.DoesExist\("blurThumbnail"\) and content\.blurThumbnail/],
];

for (const [label, pattern] of requiredMainPatterns) {
    if (!pattern.test(mainScene)) failures.push(`${label} is missing from MainScene.brs`);
}

for (const [label, pattern] of requiredAddonsPatterns) {
    if (!pattern.test(addons)) failures.push(`${label} is missing from Addons.brs`);
}

for (const [label, pattern] of requiredSettingsPatterns) {
    if (!pattern.test(settings)) failures.push(`${label} is missing from Settings.brs`);
}

for (const [label, pattern] of requiredSettingsStorePatterns) {
    if (!pattern.test(settingsStore)) failures.push(`${label} is missing from SettingsStore.brs`);
}

for (const [label, pattern] of requiredAddonStorePatterns) {
    if (!pattern.test(addonStore)) failures.push(`${label} is missing from AddonStore.brs`);
}

for (const [label, pattern] of requiredLibraryStorePatterns) {
    if (!pattern.test(libraryStore)) failures.push(`${label} is missing from LibraryStore.brs`);
}

for (const [label, pattern] of requiredAuthStorePatterns) {
    if (!pattern.test(authStore)) failures.push(`${label} is missing from AuthStore.brs`);
}

for (const [label, pattern] of requiredCatalogStorePatterns) {
    if (!pattern.test(catalogStore)) failures.push(`${label} is missing from CatalogStore.brs`);
}

for (const [label, pattern] of requiredCalendarStorePatterns) {
    if (!pattern.test(calendarStore)) failures.push(`${label} is missing from CalendarStore.brs`);
}

for (const [label, pattern] of requiredSettingsXmlPatterns) {
    if (!pattern.test(settingsXml)) failures.push(`${label} is missing from Settings.xml`);
}

for (const [label, pattern] of forbiddenMainPatterns) {
    if (pattern.test(mainScene)) failures.push(`${label} in MainScene.brs`);
}

for (const [label, pattern] of requiredLocalePatterns) {
    if (!pattern.test(englishTable)) failures.push(`${label} is missing from the English table in Locale.brs`);
}

// The copy moved into Locale.brs, so the TVDB overpromise has to stay banned in
// every string table, not just in MainScene.brs.
if (/IMDB\/TVDB IDs/.test(locale)) {
    failures.push('Search dialog still advertises unsupported TVDB in Locale.brs');
}

for (const [label, pattern] of requiredVideoPatterns) {
    const source = label.includes('field') ? videoXml : `${videoXml}\n${videoPlayer}`;
    if (!pattern.test(source)) failures.push(`${label} is missing from video player implementation`);
}

for (const [label, pattern] of requiredEpisodePatterns) {
    if (!pattern.test(`${episodeXml}\n${episodeCard}`)) failures.push(`${label} is missing from episode card implementation`);
}

if (failures.length > 0) {
    console.error('Placeholder implementation checks failed:');
    for (const failure of failures) console.error(`- ${failure}`);
    process.exit(1);
}

console.log('Placeholder implementation checks passed.');
