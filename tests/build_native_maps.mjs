import { MAPS } from '../src/maps.js';
import fs from 'node:fs';

const point = ([x, y]) => ({ x, y });
const path = (id, points, objectiveId = 'main') => ({ id, points: points.map(point), objectiveId });
const obj = (id, x, y, label, hp) => ({ id, x, y, label, hp });
const zones = (points) => points.map(([x,y,r=.08,elevation=0]) => ({x,y,r,elevation}));
const layout = {
  forest: { objectives:[obj('main',.90,.40,'山の砦',26)], paths:[path('north',[[.02,.03],[.18,.24],[.25,.43],[.32,.60],[.53,.70],[.75,.72],[.85,.57],[.90,.40]]),path('ridge',[[.58,.03],[.59,.20],[.72,.28],[.85,.35],[.90,.40]])], buildZones:zones([[.36,.40],[.38,.56],[.53,.57],[.68,.59],[.75,.45],[.76,.24],[.59,.35],[.83,.52]]), obstacles:[{x:.10,y:.70,r:.15},{x:.61,y:.84,r:.07}] },
  farm: { objectives:[obj('grain',.85,.30,'蔵',16),obj('rice',.95,.70,'米蔵',16),obj('village',.31,.55,'村',16)], paths:[path('west',[[.03,.08],[.23,.17],[.40,.27],[.52,.42],[.68,.43],[.85,.30]],'grain'),path('south',[[.54,.98],[.47,.77],[.48,.62],[.58,.53],[.75,.62],[.95,.70]],'rice'),path('lane',[[.98,.69],[.77,.64],[.59,.53],[.48,.48],[.31,.55]],'village')], buildZones:zones([[.35,.36,.065],[.48,.32,.065],[.51,.51,.065],[.64,.45,.065],[.73,.48,.065],[.39,.63,.065],[.63,.63,.065],[.81,.63,.065]]), obstacles:[] },
  town: { objectives:[obj('main',.91,.20,'兵糧所',27)], paths:[path('market',[[.02,.46],[.27,.39],[.48,.47],[.64,.46],[.77,.36],[.87,.26],[.91,.20]]),path('alley',[[.14,.02],[.24,.21],[.35,.35],[.48,.47],[.64,.46],[.77,.36],[.87,.26],[.91,.20]]),path('backstreet',[[.03,.89],[.25,.67],[.41,.59],[.48,.47],[.64,.46],[.77,.36],[.87,.26],[.91,.20]])], buildZones:zones([[.42,.34],[.54,.37],[.63,.56],[.72,.47],[.77,.27],[.45,.67],[.59,.65],[.29,.55]]), obstacles:[] },
  river: { objectives:[obj('main',.93,.40,'川辺の砦',27)], paths:[path('upper-bridge',[[.02,.03],[.14,.11],[.29,.16],[.57,.16],[.72,.21],[.83,.31],[.93,.40]]),path('lower-bridge',[[.02,.59],[.18,.67],[.29,.72],[.61,.72],[.75,.61],[.83,.46],[.93,.40]])], buildZones:zones([[.18,.27],[.19,.52],[.66,.30],[.68,.64],[.80,.40],[.82,.62],[.26,.84]]), water:{x:.30,y:0,w:.28,h:1},bridges:[{x:.29,y:.12,w:.29,h:.08},{x:.29,y:.68,w:.33,h:.08}], obstacles:[] },
  harbor: { objectives:[obj('main',.86,.10,'港の倉庫',29)], paths:[path('west-pier',[[.15,.99],[.18,.70],[.21,.49],[.43,.43],[.66,.41],[.72,.30],[.78,.19],[.86,.10]]),path('middle-pier',[[.50,.99],[.53,.70],[.54,.45],[.66,.41],[.72,.30],[.78,.19],[.86,.10]]),path('east-pier',[[.89,.99],[.88,.71],[.86,.48],[.74,.43],[.72,.30],[.78,.19],[.86,.10]])], buildZones:zones([[.32,.34],[.49,.32],[.63,.31],[.68,.13],[.80,.36],[.89,.32],[.58,.16]]), water:{x:0,y:.55,w:1,h:.45},landingIndex:2,obstacles:[] },
  convoy: { objectives:[{...obj('cart',.72,.54,'荷車',32),mobile:true}], paths:[path('pursuit',[[.02,.18],[.14,.35],[.30,.43],[.48,.52],[.72,.54]],'cart'),path('flank',[[.98,.40],[.84,.48],[.72,.54]],'cart'),path('rear',[[.03,.57],[.26,.42],[.48,.52],[.72,.54]],'cart')], escortRoute:[[.35,.44],[.60,.55],[.87,.49],[.60,.55],[.35,.44]].map(point),buildZones:zones([[.24,.52,.065],[.37,.36,.065],[.51,.42,.065],[.65,.43,.065],[.78,.61,.065],[.88,.38,.065],[.48,.64,.065],[.17,.27,.065]]),obstacles:[] },
  temple: { objectives:[obj('main',.80,.18,'本堂',27)], paths:[path('stairs',[[.03,.70],[.25,.66],[.44,.65],[.58,.56],[.63,.43],[.72,.35],[.76,.25],[.80,.18]]),path('pilgrim',[[.75,.98],[.70,.79],[.56,.66],[.58,.56],[.63,.43],[.72,.35],[.76,.25],[.80,.18]])],buildZones:zones([[.30,.56,.08,0],[.44,.77,.08,0],[.51,.49,.065,1],[.65,.60,.07,1],[.66,.30,.055,2],[.81,.36,.055,2],[.42,.43,.055,1]]),obstacles:[] },
  snow: { objectives:[obj('main',.92,.43,'峠の関所',29)],paths:[path('mountain-pass',[[.10,.02],[.27,.19],[.39,.35],[.43,.48],[.51,.57],[.68,.58],[.82,.52],[.92,.43]]),path('ice-path',[[.41,.98],[.52,.83],[.57,.69],[.51,.57],[.68,.58],[.82,.52],[.92,.43]])],buildZones:zones([[.32,.31],[.35,.47],[.49,.36],[.61,.46],[.76,.64],[.86,.37],[.55,.79],[.72,.32]]),stormZone:{x:.51,y:.57,r:.09},obstacles:[] },
  night: { objectives:[obj('main',.87,.25,'村の門',28)],paths:[path('west-road',[[.02,.12],[.23,.26],[.38,.42],[.53,.46],[.69,.39],[.87,.25]]),path('south-road',[[.02,.70],[.26,.56],[.43,.50],[.53,.46],[.69,.39],[.87,.25]]),path('east-road',[[.76,.99],[.69,.76],[.63,.61],[.53,.46],[.69,.39],[.87,.25]])],buildZones:zones([[.31,.35],[.43,.37],[.53,.59],[.61,.35],[.71,.48],[.79,.35],[.35,.63],[.62,.70]]),torches:[[.34,.43],[.59,.45],[.80,.30]].map(point),obstacles:[] },
  siege: { objectives:[obj('main',.79,.28,'城門',34)],paths:[path('main-gate',[[.02,.08],[.15,.22],[.30,.23],[.50,.27],[.68,.28],[.79,.28]]),path('south-ramp',[[.17,.98],[.28,.76],[.43,.60],[.58,.44],[.68,.28],[.79,.28]]),path('west-ramp',[[.03,.60],[.16,.54],[.30,.65],[.43,.60],[.58,.44],[.68,.28],[.79,.28]])],buildZones:zones([[.31,.32],[.45,.37],[.52,.52],[.61,.36],[.69,.47],[.48,.69],[.73,.38,.06,1],[.80,.46,.06,1]]),obstacles:[{x:.20,y:.42,r:.10}] },
};
const filenames={forest:'forest',farm:'village',town:'market',river:'river',harbor:'harbor',convoy:'convoy',temple:'temple',snow:'snow',night:'night',siege:'castle'};
const maps=MAPS.map(original=>{
  const m=structuredClone(original);
  Object.assign(m,structuredClone(layout[m.theme]));
  m.background='res://assets/map-'+filenames[m.theme]+'.png';
  // Tiers share an environment, but approach positions and route choices differ.
  for (const p of m.paths) {
    p.points[0].y=Math.min(.98,Math.max(.02,p.points[0].y+m.tierIndex*.016));
    if(p.points.length>3 && m.theme!=='river') p.points[1].x+=m.tierIndex*.011;
  }
  if(m.tierIndex===0 && ['town','harbor','convoy','night','siege'].includes(m.theme)) m.paths=m.paths.slice(0,2);
  if(m.tierIndex>=2 && ['forest','temple','snow'].includes(m.theme)) {
    const base=m.paths[0];
    m.paths.push(path('reinforcements',[[.98,.59-m.tierIndex*.04],...base.points.slice(-3).map(p=>[p.x,p.y])],base.objectiveId));
  }
  return m;
});
fs.writeFileSync(new URL('../native/maps.json',import.meta.url),JSON.stringify(maps,null,2));
console.log('40 native map configurations written.');
