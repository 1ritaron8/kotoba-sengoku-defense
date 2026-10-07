import fs from 'node:fs';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';

const curriculum = JSON.parse(fs.readFileSync(new URL('../native/curriculum.json',import.meta.url),'utf8'));
const maps = JSON.parse(fs.readFileSync(new URL('../native/maps.json',import.meta.url),'utf8'));
const tiers = {basic:15,beginner:20,intermediate:25,advanced:30};
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
    themeSet.add(map.theme);
    assert.ok(map.paths.length>=1 && map.buildZones.length>=3 && map.objectives.length>=1,map.id);
    assert.ok(map.totalWaves>=8 && map.initialGold>=90,map.id);
    const objectives = new Set(map.objectives.map(object=>object.id));
    for (const path of map.paths) {
      assert.ok(path.points.length>=2,map.id);
      assert.ok(objectives.has(path.objectiveId),`${map.id}: route target`);
      for (const point of path.points) {
        assert.ok(point.x>=0 && point.x<=1 && point.y>=0 && point.y<=1,`${map.id}: normalized point`);
      }
    }
  }
}
assert.equal(words,900);
assert.equal(themeSet.size,10);
assert.equal(new Set(maps.map(map=>map.id)).size,40);
assert.equal(new Set(maps.map(map=>map.stageNumber)).size,40,'Forty global stage numbers');
assert.equal(new Set(maps.map(map=>map.title)).size,40,'Forty distinct stage names');
assert.equal(new Set(maps.map(map=>map.background)).size,40,'No background is assigned to multiple stages');
const pictureHashes = new Set();
const layoutHashes = new Set();
const operationNames = new Set();
const effectShapes = new Set();
for (const map of maps) {
  const image = fs.readFileSync(new URL(`../${map.background.replace('res://','')}`,import.meta.url));
  assert.ok(image.length>10000,`${map.id}: real stage background`);
  const pictureHash = createHash('sha256').update(image).digest('hex');
  assert.ok(!pictureHashes.has(pictureHash),`${map.id}: no copied background under another filename`);
  pictureHashes.add(pictureHash);
  const layout = {paths:map.paths,objectives:map.objectives.map(({id,x,y})=>({id,x,y})),zones:map.buildZones,obstacles:map.obstacles};
  const layoutHash = createHash('sha256').update(JSON.stringify(layout)).digest('hex');
  assert.ok(!layoutHashes.has(layoutHash),`${map.id}: distinct battlefield layout`);
  layoutHashes.add(layoutHash);
  const rule = map.trait;
  assert.equal(rule.stageId,map.id,`${map.id}: operation belongs to this stage`);
  assert.ok(rule.nameJP && rule.reading && rule.nameKO && rule.descriptionKO,`${map.id}: bilingual operation description`);
  assert.match(rule.reading,/^[\u3040-\u309fー・\s]+$/,`${map.id}: hiragana operation reading`);
  assert.ok(!operationNames.has(rule.nameJP),`${map.id}: distinct Japanese operation name`);
  operationNames.add(rule.nameJP);
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
  assert.equal(map.music,track.path,`${map.id}: stage music metadata agrees`);
  assert.ok(track.author && track.source && track.license && track.licenseUrl,`${map.id}: complete credits`);
  const audio = fs.readFileSync(new URL(`../${track.path.replace('res://','')}`,import.meta.url));
  assert.ok(audio.length>50000,`${map.id}: actual downloaded music`);
  const audioHash = createHash('sha256').update(audio).digest('hex');
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
console.log(`CONTENT QA: PASS — ${maps.length} unique backgrounds/layouts/operation types and ${music.tracks.length} unique songs, ${themeSet.size} theme families, ${words} unique words, ${expressions} expressions.`);
