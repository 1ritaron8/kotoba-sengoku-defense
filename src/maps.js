export const TIER_INFO = {
  basic: { name: 'Basic · 기초', difficulty: 1, words: 15, waves: 10 },
  beginner: { name: '초급', difficulty: 1.2, words: 20, waves: 10 },
  intermediate: { name: '중급', difficulty: 1.45, words: 25, waves: 11 },
  advanced: { name: '고급', difficulty: 1.7, words: 30, waves: 12 },
};

export const MAP_THEMES = [
  { id: 'forest', title: '산림 매복전', shortName: '숲', japanese: '森の待ち伏せ', reading: 'もりのまちぶせ', description: '숲의 두 갈림길에 병력을 나누어 배치합니다.', mode: 'ambush', color: '#27413a', accent: '#86a783', words: '방향 · 위치 · 이동', icon: '森' },
  { id: 'farm', title: '논밭의 수확', shortName: '농촌', japanese: '村の収穫', reading: 'むらのしゅうかく', description: '흩어진 곡물 창고를 모두 지켜야 합니다.', mode: 'multi-objective', color: '#5a5c32', accent: '#c1bc70', words: '음식 · 수량 · 사람', icon: '米' },
  { id: 'town', title: '성 아래 장터', shortName: '장터', japanese: '城下の市場', reading: 'じょうかのいちば', description: '골목마다 다른 길로 적이 보급소를 노립니다.', mode: 'alleys', color: '#62482e', accent: '#cfab70', words: '물건 · 가격 · 요청', icon: '市' },
  { id: 'river', title: '두 다리의 전투', shortName: '강', japanese: '二つの橋', reading: 'ふたつのはし', description: '다리를 전환하면 새로 오는 적의 진입로가 바뀝니다.', mode: 'bridges', color: '#2b4c5b', accent: '#8db9c4', words: '건너다 · 열다 · 닫다', icon: '橋' },
  { id: 'harbor', title: '해안의 상륙', shortName: '항구', japanese: '港の防衛', reading: 'みなとのぼうえい', description: '선박이 서로 다른 부두로 상륙합니다.', mode: 'landing', color: '#2a5058', accent: '#7fc2bd', words: '배 · 도착 · 시간', icon: '港' },
  { id: 'convoy', title: '보급 행렬 호위', shortName: '호위', japanese: '荷車の護衛', reading: 'にぐるまのごえい', description: '움직이는 보급 수레의 이동 경로를 따라 방어합니다.', mode: 'escort', color: '#625437', accent: '#d1b77a', words: '앞뒤 · 속도 · 멈추다', icon: '車' },
  { id: 'temple', title: '산사의 계단', shortName: '산사', japanese: '山寺の階段', reading: 'やまでらのかいだん', description: '높은 지대의 병력은 더 멀리 공격합니다.', mode: 'elevation', color: '#464c3a', accent: '#a7b490', words: '위아래 · 거리 · 장소', icon: '寺' },
  { id: 'snow', title: '눈 덮인 고개', shortName: '설산', japanese: '雪の峠', reading: 'ゆきのとうげ', description: '눈보라가 길을 막고 양쪽 병력의 움직임을 늦춥니다.', mode: 'weather', color: '#4d6674', accent: '#cee0e9', words: '날씨 · 계절 · 상태', icon: '雪' },
  { id: 'night', title: '한밤의 봉화', shortName: '야간', japanese: '夜の村', reading: 'よるのむら', description: '병력과 봉화 주변의 시야에서만 적을 조준할 수 있습니다.', mode: 'visibility', color: '#182632', accent: '#d9a34b', words: '듣기 · 방향 · 경고', icon: '夜' },
  { id: 'siege', title: '성문 최후 방어', shortName: '공성', japanese: '城門の戦い', reading: 'じょうもんのたたかい', description: '갑옷을 입은 적과 대장을 막고 성문을 지킵니다.', mode: 'siege', color: '#564b48', accent: '#c8a18b', words: '무기 · 방어 · 명령', icon: '城' },
];

const pt = (x, y) => ({ x, y });
const route = (id, points, objectiveId = 'main') => ({ id, points: points.map(([x, y]) => pt(x, y)), objectiveId });
const objective = (id, x, y, label, hp = 20) => ({ id, x, y, label, hp });
const zone = (x, y, r = 0.095, elevation = 0) => ({ x, y, r, elevation });

function makeLayout(theme, tierIndex) {
  const s = tierIndex * 0.018;
  switch (theme) {
    case 'forest': return {
      paths: [route('north', [[0.03,0.18+s],[0.22,0.25],[0.29,0.43+s],[0.50,0.49],[0.64,0.65],[0.89,0.76]]), route('south', [[0.03,0.81-s],[0.22,0.71],[0.34,0.61-s],[0.50,0.49],[0.64,0.65],[0.89,0.76]])],
      objectives: [objective('main',0.89,0.76,'山の砦',24)],
      buildZones: [zone(0.18,0.40),zone(0.23,0.57),zone(0.42,0.34),zone(0.45,0.67),zone(0.67,0.46),zone(0.75,0.73),zone(0.76,0.57)],
      obstacles: [{x:0.13,y:0.59,r:0.025},{x:0.68,y:0.28,r:0.10}],
      ...(tierIndex>1 ? {extraPath:route('ridge',[[0.67,0.03],[0.62,0.28],[0.50,0.49],[0.64,0.65],[0.89,0.76]])} : {}),
    };
    case 'farm': return {
      paths: [route('west',[[0.03,0.24],[0.30,0.25+s],[0.40,0.45],[0.78,0.43]],'grain'),route('south',[[0.32,0.98],[0.33,0.74-s],[0.51,0.67],[0.80,0.74]],'rice'),route('east',[[0.98,0.14+s],[0.71,0.21],[0.61,0.35],[0.44,0.30]],'village')],
      objectives: [objective('grain',0.78,0.43,'蔵',12),objective('rice',0.80,0.74,'米蔵',12),objective('village',0.44,0.30,'村',12)],
      buildZones: [zone(0.22,0.38),zone(0.47,0.47),zone(0.60,0.53),zone(0.70,0.66),zone(0.31,0.60),zone(0.66,0.13),zone(0.86,0.58)],
      obstacles: [{x:0.18,y:0.72,r:0.10},{x:0.56,y:0.84,r:0.08}],
    };
    case 'town': return {
      paths: [route('market',[[0.03,0.27+s],[0.31,0.27+s],[0.31,0.56],[0.65,0.56],[0.65,0.77],[0.86,0.77]]),route('alley',[[0.60,0.03],[0.60,0.25],[0.77,0.25],[0.77,0.48],[0.65,0.56],[0.65,0.77],[0.86,0.77]]), ...(tierIndex ? [route('backstreet',[[0.03,0.84],[0.43,0.84],[0.43,0.68],[0.65,0.77],[0.86,0.77]])] : [])],
      objectives: [objective('main',0.86,0.77,'兵糧所',25)],
      buildZones: [zone(0.19,0.43,0.07),zone(0.43,0.42,0.07),zone(0.57,0.38,0.07),zone(0.87,0.35,0.07),zone(0.51,0.70,0.07),zone(0.77,0.64,0.07),zone(0.52,0.90,0.07)],
      obstacles: [{x:0.45,y:0.19,r:0.06},{x:0.15,y:0.62,r:0.07},{x:0.90,y:0.51,r:0.05}],
    };
    case 'river': return {
      paths: [route('upper-bridge',[[0.03,0.22],[0.28,0.26+s],[0.40,0.35],[0.62,0.35],[0.74,0.49],[0.90,0.56]]),route('lower-bridge',[[0.03,0.77],[0.27,0.74-s],[0.40,0.68],[0.62,0.68],[0.74,0.49],[0.90,0.56]])],
      objectives: [objective('main',0.90,0.56,'川辺の砦',25)],
      buildZones: [zone(0.23,0.42,0.085),zone(0.27,0.60,0.085),zone(0.68,0.28,0.085),zone(0.69,0.78,0.085),zone(0.79,0.36,0.08),zone(0.83,0.71,0.08)],
      water: {x:0.40,y:0,w:0.22,h:1}, bridges: [{x:0.39,y:0.31,w:0.24,h:0.08},{x:0.39,y:0.64,w:0.24,h:0.08}], obstacles:[],
    };
    case 'harbor': return {
      paths: [route('north-pier',[[0.02,0.15],[0.18,0.23],[0.37,0.32+s],[0.48,0.32+s],[0.58,0.47],[0.80,0.62]]),route('south-pier',[[0.02,0.87],[0.16,0.73],[0.36,0.69-s],[0.48,0.69-s],[0.58,0.47],[0.80,0.62]]), ...(tierIndex>1 ? [route('central-pier',[[0.01,0.48],[0.37,0.48],[0.58,0.47],[0.80,0.62]])] : [])],
      objectives: [objective('main',0.80,0.62,'港の倉庫',27)],
      buildZones: [zone(0.50,0.16,0.08),zone(0.60,0.31,0.08),zone(0.52,0.56,0.06),zone(0.51,0.83,0.08),zone(0.67,0.76,0.08),zone(0.74,0.43,0.08),zone(0.87,0.49,0.08)],
      water:{x:0,y:0,w:0.39,h:1}, obstacles:[], landingIndex:2,
    };
    case 'convoy': return {
      paths: [route('pursuit',[[0.03,0.18],[0.24,0.31],[0.38,0.46],[0.62,0.53],[0.82,0.66]],'cart'),route('flank',[[0.97,0.13+s],[0.77,0.32],[0.62,0.53],[0.82,0.66]],'cart'), ...(tierIndex ? [route('rear',[[0.43,0.98],[0.42,0.77],[0.62,0.53],[0.82,0.66]],'cart')] : [])],
      objectives: [{...objective('cart',0.82,0.66,'荷車',30),mobile:true}],
      escortRoute: [pt(0.48,0.40),pt(0.76,0.42+s),pt(0.82,0.66),pt(0.53,0.73-s),pt(0.48,0.40)],
      buildZones: [zone(0.23,0.47),zone(0.45,0.27),zone(0.65,0.27),zone(0.64,0.63),zone(0.85,0.47),zone(0.39,0.67),zone(0.76,0.82)],
      obstacles:[{x:0.13,y:0.68,r:0.10}],
    };
    case 'temple': return {
      paths:[route('stairs',[[0.03,0.85],[0.25,0.80],[0.25,0.62],[0.52,0.62],[0.52,0.40],[0.75,0.40],[0.75,0.20],[0.86,0.20]]),route('pilgrim',[[0.98,0.88],[0.79,0.72-s],[0.64,0.62],[0.52,0.62],[0.52,0.40],[0.75,0.40],[0.75,0.20],[0.86,0.20]])],
      objectives:[objective('main',0.86,0.20,'本堂',25)],
      buildZones:[zone(0.20,0.52,0.08,1),zone(0.38,0.73,0.08,0),zone(0.40,0.46,0.08,1),zone(0.61,0.28,0.08,2),zone(0.66,0.48,0.07,2),zone(0.87,0.43,0.08,2),zone(0.71,0.86,0.08,0)],
      obstacles:[{x:0.30,y:0.27,r:0.11}], terraces:[{x:0.15,y:0.44,w:0.77,h:0.22},{x:0.48,y:0.17,w:0.45,h:0.23}],
    };
    case 'snow': return {
      paths:[route('mountain-pass',[[0.02,0.72],[0.21,0.77-s],[0.32,0.58],[0.51,0.62],[0.62,0.34+s],[0.80,0.34],[0.88,0.17]]),route('ice-path',[[0.03,0.15],[0.22,0.27],[0.32,0.58],[0.51,0.62],[0.62,0.34+s],[0.80,0.34],[0.88,0.17]])],
      objectives:[objective('main',0.88,0.17,'峠の関所',27)],
      buildZones:[zone(0.13,0.46),zone(0.27,0.71),zone(0.42,0.43),zone(0.58,0.77),zone(0.69,0.53),zone(0.72,0.20),zone(0.88,0.45)],
      obstacles:[{x:0.51,y:0.26,r:0.07},{x:0.85,y:0.76,r:0.11}], stormZone:{x:0.51,y:0.62,r:0.11},
    };
    case 'night': return {
      paths:[route('west-road',[[0.02,0.26],[0.25,0.34+s],[0.41,0.51],[0.69,0.57],[0.85,0.74]]),route('south-road',[[0.22,0.98],[0.33,0.76],[0.41,0.51],[0.69,0.57],[0.85,0.74]]), ...(tierIndex ? [route('east-road',[[0.98,0.13],[0.80,0.27],[0.69,0.57],[0.85,0.74]])] : [])],
      objectives:[objective('main',0.85,0.74,'村の門',26)],
      buildZones:[zone(0.19,0.48),zone(0.37,0.31),zone(0.47,0.69),zone(0.66,0.38),zone(0.74,0.78),zone(0.87,0.47)],
      torches:[pt(0.31,0.42),pt(0.59,0.59),pt(0.80,0.72)], obstacles:[{x:0.15,y:0.77,r:0.06},{x:0.60,y:0.21,r:0.07}],
    };
    case 'siege': return {
      paths:[route('main-gate',[[0.03,0.50],[0.25,0.50],[0.45,0.62-s],[0.66,0.56],[0.85,0.50]]),route('north-ramp',[[0.05,0.14],[0.28,0.22+s],[0.45,0.39],[0.66,0.56],[0.85,0.50]]),route('south-ramp',[[0.03,0.91],[0.25,0.81-s],[0.45,0.62-s],[0.66,0.56],[0.85,0.50]])],
      objectives:[objective('main',0.85,0.50,'城門',32)],
      buildZones:[zone(0.22,0.36),zone(0.22,0.66),zone(0.42,0.24),zone(0.46,0.80),zone(0.59,0.43),zone(0.68,0.73),zone(0.78,0.33,0.07,1),zone(0.80,0.66,0.07,1)],
      obstacles:[{x:0.60,y:0.16,r:0.06}], walls:[{x:0.87,y:0.12,w:0.03,h:0.29},{x:0.87,y:0.60,w:0.03,h:0.31}],
    };
  }
}

export const MAPS = Object.keys(TIER_INFO).flatMap((tier, tierIndex) => MAP_THEMES.map((theme, index) => {
  const layout = makeLayout(theme.id, tierIndex);
  if (layout.extraPath) { layout.paths.push(layout.extraPath); delete layout.extraPath; }
  const variation = ['初陣', '援軍', '激戦', '決戦'][tierIndex];
  return {
    ...theme, ...layout,
    id: `${tier}-${theme.id}`, theme: theme.id, tier, tierIndex, level: index + 1,
    title: `${theme.title} · ${['첫 출진','지원 작전','격전','결전'][tierIndex]}`,
    japanese: `${theme.japanese}・${variation}`,
    difficulty: TIER_INFO[tier].difficulty * (1 + index * 0.022),
    totalWaves: TIER_INFO[tier].waves,
    initialGold: 280 + tierIndex * 35,
    recruitCost: 60,
    unitLimit: 14 + tierIndex * 2,
    recommendedWords: TIER_INFO[tier].words,
    reviewWords: TIER_INFO[tier].words,
    unlocked: true,
  };
}));

export function getMap(tier = 'basic', index = 0) {
  const resolvedTier = typeof tier === 'number' ? Object.keys(TIER_INFO)[tier] : tier;
  return MAPS.find(map => map.tier === resolvedTier && map.level === Number(index) + 1) || MAPS[0];
}
