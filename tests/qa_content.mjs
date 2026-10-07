import fs from 'node:fs';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';

const curriculum = JSON.parse(fs.readFileSync(new URL('../native/curriculum.json',import.meta.url),'utf8'));
const mapsSource = fs.readFileSync(new URL('../native/maps.json',import.meta.url));
const maps = JSON.parse(mapsSource.toString('utf8'));
const mapsHash = createHash('sha256').update(mapsSource).digest('hex');
const artManifest = JSON.parse(fs.readFileSync(new URL('../assets/battlefields-rendered/manifest.json',import.meta.url),'utf8'));
const expectedThemes = ['convoy','farm','forest','night','river','siege','temple','town'];
const tiers = {basic:15,beginner:20,intermediate:25,advanced:30};

function readResource(path, label) {
  assert.equal(typeof path,'string',`${label}: resource path`);
  assert.ok(path.startsWith('res://') && !path.includes('\\') && !path.slice(6).split('/').includes('..'),`${label}: project-local resource`);
  const file = new URL(`../${path.slice(6)}`,import.meta.url);
  assert.ok(fs.existsSync(file) && fs.statSync(file).isFile(),`${label}: required file ${path}`);
  return fs.readFileSync(file);
}

function normalizedPoint(point, label) {
  assert.ok(Number.isFinite(point.x) && Number.isFinite(point.y) && point.x>=0 && point.x<=1 && point.y>=0 && point.y<=1,`${label}: finite normalized point`);
}

const ids = new Set();
const surfaces = new Set();
const themeSet = new Set();
let words = 0;
let expressions = 0;
for (const [tier, target] of Object.entries(tiers)) {
  assert.equal(curriculum[tier].length,10,`${tier}: ten lessons`);
  const tierMaps = maps.filter(map=>map.tier===tier);
  assert.equal(tierMaps.length,10,`${tier}: ten maps`);
  for (let index=0; index<10; index++) {
    const lesson = curriculum[tier][index];
    assert.equal(lesson.newWords.length,target,`${lesson.id}: new word count`);
    for (const word of lesson.newWords) {
      assert.ok(word.id && word.jp && word.reading && word.ko,`${lesson.id}: all language fields`);
      assert.ok(!ids.has(word.id),`Duplicate id ${word.id}`);
      const normalized = word.jp.normalize('NFKC');
      assert.ok(!surfaces.has(normalized),`Duplicate word ${normalized}`);
      assert.match(word.reading,/^[\u3040-\u309fー・\s]+$/,`Hiragana reading: ${word.jp}`);
      assert.ok(word.example?.jp && word.example?.reading && word.example?.ko,`Example: ${word.jp}`);
      if (word.parts) assert.equal(word.parts.map(part=>part.text).join(''),word.jp,`Ruby reconstructs word: ${word.jp}`);
      ids.add(word.id);
      surfaces.add(normalized);
      words++;
    }
    for (const id of lesson.reviewIds) assert.ok(ids.has(id),`Review must refer to earlier/current known id: ${id}`);
    for (const expression of lesson.expressions ?? []) {
      assert.ok(expression.jp && expression.reading && expression.ko,`${lesson.id}: expression`);
      expressions++;
    }
    const map = tierMaps[index];
    assert.ok(expectedThemes.includes(map.theme),`${map.id}: supported historical theme ${map.theme}`);
    themeSet.add(map.theme);
    assert.ok(map.paths.length>=1 && map.buildZones.length>=3 && map.objectives.length>=1,map.id);
    assert.ok(map.totalWaves>=8 && map.initialGold>=90,map.id);
    const objectives = new Set(map.objectives.map(object=>object.id));
    assert.equal(objectives.size,map.objectives.length,`${map.id}: unique objective ids`);
    for (const objective of map.objectives) normalizedPoint(objective,`${map.id}: objective ${objective.id}`);
    for (const zone of map.buildZones) normalizedPoint(zone,`${map.id}: defense position`);
    for (const path of map.paths) {
      assert.ok(path.points.length>=2,map.id);
      assert.ok(objectives.has(path.objectiveId),`${map.id}: route target`);
      for (const point of path.points) {
        normalizedPoint(point,`${map.id}: route ${path.id}`);
      }
    }
  }
}
assert.equal(words,900);
assert.deepEqual([...themeSet].sort(),expectedThemes,'The campaign uses all eight approved historical theme families');
assert.equal(maps.length,40,'Forty source stages');
assert.equal(new Set(maps.map(map=>map.id)).size,40);
assert.deepEqual(maps.map(map=>map.stageNumber).sort((a,b)=>a-b),Array.from({length:40},(_,index)=>index+1),'Global stage numbers cover 1 through 40');
assert.equal(new Set(maps.map(map=>map.title)).size,40,'Forty distinct stage names');
assert.equal(artManifest.version,1,'Supported rendered battlefield manifest');
assert.equal(artManifest.expectedStageCount,40,'The manifest declares the full campaign');
assert.equal(artManifest.complete,true,'All campaign artwork is registered');
assert.equal(artManifest.sourceMapsSha256,mapsHash,'Manifest binds the exact source map bytes');
assert.equal(artManifest.stages.length,40,'Forty registered battlefield images');
assert.deepEqual(artManifest.stages.map(stage=>stage.stageId).sort(),maps.map(map=>map.id).sort(),'Artwork covers exactly the authored stage ids');
const artByStage = new Map(artManifest.stages.map(stage=>[stage.stageId,stage]));
const mapById = new Map(maps.map(map=>[map.id,map]));
const pictureHashes = new Set();
const layoutHashes = new Set();
const operationNames = new Map();
const operationIds = new Set();
const effectShapes = new Set();
let sharedTerrainStages = 0;
for (const map of maps) {
  const artwork = artByStage.get(map.id);
  assert.equal(artwork.stageNumber,map.stageNumber,`${map.id}: artwork belongs to the correct campaign stage`);
  assert.match(artwork.path,/^res:\/\/assets\/battlefields-rendered\/[^/]+\.png$/,`${map.id}: registered battlefield PNG`);
  assert.equal(artwork.sourceDataSha256??artManifest.sourceMapsSha256,mapsHash,`${map.id}: artwork source data is current`);
  assert.match(artwork.sourceGeometryFingerprint,/^[a-f0-9]{64}$/,`${map.id}: recorded geometry fingerprint`);
  const image = readResource(artwork.path,`${map.id}: registered artwork`);
  assert.ok(image.length>10000,`${map.id}: actual registered artwork`);
  assert.ok(image.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])),`${map.id}: PNG signature`);
  assert.equal(image.toString('ascii',12,16),'IHDR',`${map.id}: PNG image header`);
  assert.equal(image.readUInt32BE(16),artwork.width,`${map.id}: registered image width`);
  assert.equal(image.readUInt32BE(20),artwork.height,`${map.id}: registered image height`);
  const pictureHash = createHash('sha256').update(image).digest('hex');
  assert.equal(pictureHash,artwork.sha256,`${map.id}: approved image hash`);
  assert.ok(!pictureHashes.has(pictureHash),`${map.id}: no copied background under another filename`);
  pictureHashes.add(pictureHash);
  // Check legacy preview resources separately from the registered release artwork.
  readResource(map.background,`${map.id}: legacy preview background`);
  const layout = {paths:map.paths,objectives:map.objectives.map(({id,x,y})=>({id,x,y})),zones:map.buildZones,obstacles:map.obstacles};
  const layoutHash = createHash('sha256').update(JSON.stringify(layout)).digest('hex');
  layoutHashes.add(layoutHash);
  const history = map.historicalBattlefield;
  assert.ok(history?.missionField?.locationId,`${map.id}: authored battlefield location`);
  if (history.sameLocationPreviousStageId) {
    const previous = mapById.get(history.sameLocationPreviousStageId);
    assert.ok(previous && previous.stageNumber<map.stageNumber,`${map.id}: reused terrain refers to an earlier authored stage`);
    assert.equal(history.missionField.locationId,previous.historicalBattlefield.missionField.locationId,`${map.id}: repeated phase stays at the same actual battlefield`);
    assert.ok(history.terrainLayout && previous.historicalBattlefield.terrainLayout,`${map.id}: repeated terrain has an authored shared layout`);
    for (const key of ['terrainLayout','heightFeatures','waterFeatures','ambushClearings']) {
      assert.deepEqual(history[key],previous.historicalBattlefield[key],`${map.id}: reused ${key} preserves the original geography`);
    }
    sharedTerrainStages++;
  }
  const rule = map.trait;
  assert.equal(rule.stageId,map.id,`${map.id}: operation belongs to this stage`);
  assert.ok(rule.id && !operationIds.has(rule.id),`${map.id}: unique operation id`);
  operationIds.add(rule.id);
  assert.ok(rule.nameJP && rule.reading && rule.nameKO && rule.descriptionKO,`${map.id}: bilingual operation description`);
  assert.match(rule.reading,/^[\u3040-\u309fー・（）\s]+$/,`${map.id}: hiragana operation reading with optional phase parentheses`);
  if (operationNames.has(rule.nameJP)) {
    assert.ok(history.sameLocationPreviousStageId,`${map.id}: repeated operation label has an authored battlefield link`);
    assert.equal(operationNames.get(rule.nameJP),history.missionField.locationId,`${map.id}: repeated operation label belongs to the same battlefield`);
  }
  operationNames.set(rule.nameJP,history.missionField.locationId);
  // Ignore numeric tuning and coordinates: effects must differ in what they do.
  const shape = JSON.stringify({
    units:(rule.unitBonuses??[]).map(({type,...effects})=>[type,Object.keys(effects).sort()]),
    enemies:(rule.enemyBonuses??[]).map(({kind,...effects})=>[kind,Object.keys(effects).sort()]),
    gold:!!rule.waveGold,
    reinforcements:rule.reinforcements?.kind??null,
    routes:!!rule.cycleRoutes,
    auras:(rule.auras??[]).map(aura=>Object.keys(aura).filter(key=>key.endsWith('Factor')).sort())
  });
  assert.ok(!effectShapes.has(shape),`${map.id}: operation differs beyond numeric tuning`);
  effectShapes.add(shape);
  for (const aura of rule.auras??[]) {
    assert.ok(aura.x>=0 && aura.x<=1 && aura.y>=0 && aura.y<=1 && aura.r>0,`${map.id}: valid operation area`);
    assert.ok(aura.period>aura.activeSeconds && aura.activeSeconds>0,`${map.id}: periodic operation area`);
    assert.ok(map.buildZones.some(zone=>Math.hypot(aura.x-zone.x,aura.y-zone.y)<0.001),`${map.id}: operation area matches an authored defense position`);
  }
}
const music = JSON.parse(fs.readFileSync(new URL('../native/music.json',import.meta.url),'utf8'));
assert.equal(music.tracks.length,40,'Forty separate musical works');
assert.equal(new Set(music.tracks.map(track=>track.stageId)).size,40,'One track assignment per stage');
assert.equal(new Set(music.tracks.map(track=>track.title.toLowerCase())).size,40,'Forty distinct music titles');
const audioHashes = new Set();
for (const map of maps) {
  const track = music.tracks.find(track=>track.stageId===map.id);
  assert.ok(track,`${map.id}: assigned music exists`);
  // Main selects native/music.json by stage id; map.music is legacy metadata.
  assert.equal(track.stageNumber,map.stageNumber,`${map.id}: music belongs to the correct campaign stage`);
  assert.ok(track.author && track.source && track.license && track.licenseUrl,`${map.id}: complete credits`);
  const audio = readResource(track.path,`${map.id}: assigned music`);
  assert.ok(audio.length>50000,`${map.id}: actual downloaded music`);
  const audioHash = createHash('sha256').update(audio).digest('hex');
  assert.equal(audioHash,track.sha256,`${map.id}: recorded music hash`);
  assert.equal(audio.length,track.bytes,`${map.id}: recorded music file size`);
  assert.ok(!audioHashes.has(audioHash),`${map.id}: no renamed duplicate audio`);
  audioHashes.add(audioHash);
}
for (const path of ['map-forest','map-village','map-market','map-river','map-harbor','map-convoy','map-temple','map-snow','map-night','map-castle','units-atlas']) {
  assert.ok(fs.statSync(new URL(`../assets/${path}.png`,import.meta.url)).size>10000,`${path}: actual image file`);
}
for (const path of ['main.gd','game.gd','progress.gd']) {
  const text = fs.readFileSync(new URL(`../native/${path}`,import.meta.url),'utf8');
  assert.ok(!/HTTPRequest|WebSocketPeer|ENetMultiplayerPeer/.test(text),`${path}: offline app`);
}
console.log(`CONTENT QA: PASS — ${maps.length} manifest-backed images, ${layoutHashes.size} gameplay layouts with ${sharedTerrainStages} declared terrain reuses, ${effectShapes.size} operation types, ${music.tracks.length} unique songs, ${themeSet.size} approved theme families, ${words} unique words, ${expressions} expressions. Source/assets only; forty in-game screens and runtime geometry are not reviewed by this check.`);
