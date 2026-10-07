"""Draft the reviewed roads without touching production or inventing weather.

Each battlefield has an explicit local corridor. Parallel fronts follow the
same terrain contour rather than padding one route with a decorative loop.
The draft must pass actual Godot navigation/placement review before adoption.
"""
from __future__ import annotations

import copy
import itertools
import json
import math
from pathlib import Path

from normalize_battlefield_layouts import Terrain, xy, rec, add, sub, mul, norm, lerp, distance, lengths, along, closest, astar, rounded, nearest_safe
from author_enemy_camp_approaches import BOATS, safe_route
from audit_campaign_routes import audit, draw_sheets

ROOT=Path(__file__).resolve().parent.parent
PROFILE=ROOT/'tests/profiles/balanced-route-design-20261007/wide-v6'

# No implicit map-name routing: these are reviewed normalized tactical floors.
# Historical terrain, season, records and objective identities remain intact.
DESIGNS={
 1: ([(.96,.27),(.78,.40),(.62,.54),(.48,.67)], .055, 'common', '토루 앞 두 진입로는 비슷한 폭과 일정한 중간 간격으로 낮은 구릉을 따라옵니다.'),
 2: ([(.90,.035),(.83,.23),(.75,.41),(.66,.57)], .050, 'common', '구릉 사이 공통 접근부에서 세 야영지로 고른 폭의 부채꼴 전선을 엽니다.'),
 3: ([(.92,.09),(.76,.28),(.58,.46),(.43,.62)], .060, 'common', '산기슭 등고선을 함께 따라 오르는 두 완만한 진입로입니다.'),
 4: ([(.97,.12),(.79,.28),(.62,.44),(.46,.61)], .060, 'common', '낮은 석축 단구를 나란히 잇고 성문 앞에서 합류합니다.'),
 5: ([(.91,.05),(.81,.22),(.68,.40),(.60,.59)], .060, 'common', '내륙 저지대의 토루 바깥으로 두 비슷한 굴곡의 접근로를 냅니다. 바위를 빙 도는 고리는 제거합니다.'),
 6: ([(.80,.06),(.66,.25),(.57,.43),(.45,.61)], .055, 'common', '낮은 구릉의 두 넓은 진입로와 후방의 수레 순환로를 구분합니다.'),
 7: ([(.96,.32),(.79,.40),(.62,.50),(.45,.64)], .055, 'common', '만의 육지 가장자리를 따라 구릉 진입로가 완만하게 나뉩니다.'),
 8: ([(.96,.20),(.93,.40),(.78,.56),(.56,.71)], .055, 'common', '가네가사키 철수로의 두 육로는 서로 떨어진 전선을 유지하고 후방 야영지에서 합류합니다.'),
 9: ([(.9275,.1125),(.78,.30),(.62,.45),(.43,.65)], .055, 'independent', '강변의 두 넓은 육로가 여울과 하안 지형을 따르며, 도하 공간은 별도의 자연스러운 합류부로 둡니다.'),
 10: ([(.83,.04),(.76,.24),(.67,.42),(.60,.62)], .055, 'common', '호수 뒤편 산기슭의 두 능선 접근부를 짧고 비슷하게 잇습니다.'),
 11: ([(.86,.025),(.76,.24),(.62,.44),(.43,.64)], .055, 'independent', '넓은 겨울 대지의 두 전열이 같은 낮은 굴곡을 따라 진군합니다. 한쪽만 크게 돌아가지 않습니다.'),
 12: ([(.12,.025),(.24,.23),(.35,.40),(.40,.56)], .050, 'common', '하천과 저습지 사이 육지에서 갈라져 세 작은 보급 진영으로 고른 폭의 육로가 이어집니다.'),
 13: ([(.92,.05),(.77,.25),(.61,.46),(.43,.67)], .055, 'common', '숲의 안부를 따르는 두 가까운 산길입니다. 산을 가로지르는 지름길은 두지 않습니다.'),
 14: ([(.975,.58),(.78,.57),(.61,.61),(.46,.69)], .055, 'independent', '골짜기 성읍 바깥 두 가도를 일정 간격으로 잇고 하천과 목조 시가지의 자리를 보존합니다.'),
 15: ([(.97,.12),(.78,.29),(.60,.46),(.44,.63)], .055, 'common', '능선 사면을 같이 따라가는 두 공격로로 급격한 직각 우회를 없앱니다.'),
 16: ([(.96,.32),(.85,.43),(.74,.54),(.63,.65)], .050, 'common', '합류부 아래 육지에서 보급 진영까지 두 나란한 접근로를 냅니다. 후방 수레 순환로는 유지합니다.'),
 17: ([(.975,.22),(.81,.34),(.65,.46),(.48,.63)], .060, 'independent', '개울과 목책 외곽의 떨어진 전열이 비슷한 거리로 사격 전선에 접근합니다.'),
 18: ([(.97,.25),(.79,.36),(.61,.51),(.43,.68)], .055, 'common', '겨울 능선의 두 사면길을 비슷한 굴곡으로 구성합니다.'),
 19: ([(.9275,.0725),(.78,.26),(.62,.42),(.45,.61)], .055, 'independent', '불어난 강의 안전한 하안 길 두 개를 사용하고 강을 건너는 좁은 육상 연결부에서만 합류합니다.'),
 20: ([(.96,.08),(.78,.28),(.62,.45),(.46,.64)], .055, 'common', '숲 능선에서 두 갈래가 같은 사면을 따라 성문 앞으로 이어집니다.'),
 21: ([(.94,.08),(.90,.23),(.77,.38),(.66,.57)], .065, 'common', '강 남쪽 봉쇄 진영의 접근부에서 세 개의 짧은 구릉 전선이 갈라집니다.'),
 22: ([(.94,.04),(.85,.24),(.76,.42),(.67,.58)], .045, 'common', '성읍 토루 바깥 공통 가도에서 세 야영지 골목으로 자연스럽게 퍼집니다.'),
 23: ([(.94,.08),(.90,.23),(.77,.38),(.66,.57)], .065, 'common', '포위 초기와 같은 미키 지형·접근로를 유지하고 장기 봉쇄의 훼손과 고갈만 더합니다.'),
 24: ([(.18,.03),(.27,.23),(.36,.43),(.46,.63)], .055, 'independent', '사찰 성읍의 두 육상 접근부가 같은 대지 가장자리를 따라 이어집니다.'),
 25: ([(.93,.035),(.84,.23),(.73,.41),(.62,.61)], .065, 'common', '산성 아래 봉쇄 진영을 잇는 세 전선으로 큰 원형 우회를 제거합니다.'),
 26: ([(.18,.04),(.24,.25),(.30,.44),(.40,.61)], .060, 'common', '홍수 수역 서쪽 육지 제방을 따라 세 갈래가 보급 진영으로 이어집니다. 수레 순환로는 별개입니다.'),
 27: ([(.18,.04),(.24,.25),(.30,.44),(.40,.61)], .060, 'common', '다카마쓰의 기존 제방 전선을 유지하며 급보를 받은 상황의 전장 흔적으로 차이를 냅니다.'),
 28: ([(.18,.04),(.21,.24),(.25,.44),(.28,.63)], .055, 'common', '홍수 서쪽의 후퇴 가도와 양옆 소로로 같은 방향의 세 전선을 구성합니다.'),
 29: ([(.20,.03),(.30,.24),(.40,.44),(.43,.64)], .065, 'common', '덴노잔 산기슭과 동쪽 저지대 사이 세 가까운 침투로입니다. 한 길만 큰 고리를 만들지 않습니다.'),
 30: ([(.14,.035),(.20,.23),(.25,.41),(.29,.60)], .060, 'independent', '호수 서쪽 능선의 세 작은 진지에서 나란히 내려오는 산길입니다.'),
 31: ([(.975,.36),(.80,.34),(.65,.46),(.54,.64)], .065, 'common', '낮은 구릉 사면과 야전 진지 사이 세 가도를 비슷한 길이로 엽니다.'),
 32: ([(.94,.08),(.84,.26),(.74,.43),(.64,.59)], .045, 'common', '낮은 구릉의 접근부에서 세 야영지로 펼쳐지는 전선이며, 중앙 진영은 두 인접 가도로 압박합니다.'),
 33: ([(.975,.50),(.80,.56),(.64,.62),(.48,.70)], .075, 'independent', '산성 사면의 네 전열이 같은 능선 방향으로 진입합니다. 먼 반대편에서 돌아오는 불필요한 네 번째 길을 제거합니다.'),
 34: ([(.90,.025),(.81,.23),(.69,.44),(.60,.63)], .055, 'independent', '평성 해자 바깥 두 육상 가도가 같은 완만한 흐름으로 본진에 접근합니다.'),
 35: ([(.87,.045),(.78,.23),(.65,.40),(.46,.60)], .065, 'independent', '내륙 강의 넓은 여울로 세 전열이 가까이 도하한 뒤 하안단구를 따라 진군합니다.'),
 36: ([(.94,.08),(.79,.27),(.65,.46),(.49,.64)], .065, 'common', '야전 진영으로 향하는 세 가까운 야습 전선입니다. 보급 수레의 후방 순환로와 구분합니다.'),
 37: ([(.975,.52),(.80,.61),(.64,.69),(.48,.74)], .065, 'independent', '마른 해자 사이 토교를 향한 세 접근로를 고른 폭과 완만한 굴곡으로 잇습니다.'),
 38: ([(.94,.07),(.86,.25),(.73,.44),(.62,.62)], .065, 'common', '구릉 요새 외곽 포위 진영으로 세 짧은 육상 전선이 펼쳐집니다.'),
 39: ([(.975,.24),(.84,.38),(.73,.51),(.63,.65)], .065, 'independent', '습지 동쪽 자연 제방의 세 접근로로 큰 원형 우회를 없앱니다. 별동대 수상 상륙로는 따로 둡니다.'),
 40: ([(.975,.16),(.972,.34),(.89,.48),(.75,.60),(.64,.69)], .065, 'common', '해자와 총구 토루 바깥 공통 진입부에서 네 완만한 포위 전선으로 갈라집니다. 반대편을 크게 도는 장식 고리는 제거합니다.'),
}
START_OVERRIDES={24:[(.24,.025),(.12,.035)],33:[(.975,.50),(.975,.46),(.975,.54),(.975,.42)],35:[(.88,.025),(.975,.12),(.76,.025)],37:[(.975,.52),(.975,.46),(.975,.58)],39:[(.975,.24),(.975,.18),(.975,.30)]}

# This lower-road support point must not sit inside the larger neighbouring
# lane's support circle: real placement otherwise resolves to that lane first.
POST_FRACTION_OVERRIDES={25:{'intermediate-harbor-ground-extra-12':.80}}

# Keep whole tactical strips between roads. The predecessor sine fan squeezed
# three/four roads into less than one physical road width, so it was rejected.
WORLD_WIDTH=18.5
WORLD_DEPTH=12.0
MAIN_ROAD_WIDTH=1.10
OUTER_ONLY={3,4,7,8,10,13,15,18,20,25,37}
DRY_POCKETS={6,9,12,16,19,21,23,26,27,28,30,33,36,39,40}
ADDITIONAL_DRY_POCKETS={12:{3,6,9,12},30:{3,6,9,12},33:{3,6,9,12,15},40:{3,6,9,12,15}}
WIDE_ANCHORS={
 2:[(.90,.035),(.69,.23),(.56,.42),(.46,.60)],
 12:[(.12,.025),(.32,.23),(.43,.42),(.43,.60)],
 22:[(.94,.04),(.73,.24),(.59,.43),(.48,.61)],
 26:[(.18,.04),(.22,.25),(.24,.44),(.33,.64)],
 27:[(.18,.04),(.22,.25),(.24,.44),(.33,.64)],
 28:[(.18,.04),(.22,.25),(.24,.44),(.28,.63)],
 31:[(.975,.36),(.74,.30),(.58,.45),(.45,.64)],
 32:[(.94,.08),(.73,.26),(.60,.43),(.47,.61)],
 # A few local bends belong to the actual kind of terrain. They are not a
 # template applied to every map, and neither lane takes a decorative U-loop.
 4:[(.97,.12),(.79,.28),(.62,.36),(.57,.52),(.47,.65)],
 6:[(.80,.06),(.66,.25),(.49,.35),(.44,.60)],
 13:[(.92,.05),(.85,.23),(.65,.30),(.58,.48),(.43,.66)],
 14:[(.975,.58),(.72,.53),(.53,.60),(.46,.69)],
 18:[(.97,.25),(.80,.32),(.70,.48),(.49,.56),(.42,.70)],
 35:[(.87,.045),(.78,.22),(.61,.34),(.60,.47),(.43,.51),(.37,.69)],
 37:[(.975,.52),(.83,.57),(.76,.70),(.53,.73),(.43,.74)],
}

# These describe the historic setting, not a claim that the game's exact road
# or prop positions were excavated. The art uses the same finite road/floor
# geometry as gameplay; a descriptor cannot invent an extra decorative road.
TERRAIN_COMPOSITIONS={
 1:('low_hill_fort','낮은 구릉의 토루와 작은 목책, 문 앞 흙해자'),
 2:('valley_front','낮은 둔덕 사이 열린 저지와 작은 천막 군영'),
 3:('mountain_town_edge','산기슭 성하와 가까운 능선의 높낮이 대비'),
 4:('stone_terraces','불규칙한 석축 단구와 경사면을 잇는 완만한 꺾임'),
 5:('basin_earthwork','분지의 넓은 육로, 토루와 낮은 해자'),
 6:('valley_supply','골짜기 옆 고개와 후방 수레 보급 순환로'),
 7:('coastal_hill','만을 내려다보는 낮은 구릉과 작은 흙 성채'),
 8:('coastal_rearguard','같은 해안 구릉의 철수로, 닳은 목책과 바퀴자국'),
 9:('gravel_fords','강의 자갈 여울과 양안 전열, 별동대의 수상 상륙'),
 10:('lake_foothill','호수 서안 산록과 가까운 산성 연락 통로'),
 11:('open_plateau','마른 겨울 대지와 넓은 전열, 드문 낮은 둔덕'),
 12:('lowland_waterways','하천과 옛 호수 사이 마른 미고지와 작은 보급 진영'),
 13:('wooded_saddle','숲 고개의 사면을 따르는 제한된 굴곡과 퇴각 흔적'),
 14:('valley_town','계곡 성하의 흙담과 목조 집터 사이 넓은 방향 전환'),
 15:('ridge_kuruwa','능선 위 흙 곡륜과 야간 연락부, 절제된 횃불'),
 16:('confluence_relief','두 강의 합류부 절벽 강안과 마른 후방 수레 보급로'),
 17:('palisade_front','개울 앞 넓은 사격 전열과 서로 구분된 방마책 구간'),
 18:('cold_ridge_ascent','마른 풀의 차가운 산성 사면, 제한된 등고선 굴곡'),
 19:('rising_river_retreat','불어난 탁한 강과 젖은 하안 퇴로, 도하 연결부'),
 20:('earthen_ridge','숲 능선의 흙 곡륜과 골짜기 방향 연락부'),
 21:('spring_siege_posts','봄 구릉에 분리된 포위 군영과 흙 보루'),
 22:('terrace_castle_town','이타미 단구의 토루, 해자와 성하 골목'),
 23:('winter_blockade','같은 미키 포위망의 맨가지, 닳은 군행로와 고갈된 보급부'),
 24:('fortified_monastery','사찰 목조 지붕과 흙담, 대지 아래 물길과 빈 퇴거 건물'),
 25:('mountain_blockade','산성 아래 서로 분리된 차단 군영과 계곡 보급 접근부'),
 26:('flood_siege','탁한 침수 저지, 연속된 흙 제방과 마른 후방 수레 순환로'),
 27:('flood_rear_message','같은 침수지 후방의 전령 연락부와 수레 집결 흔적'),
 28:('wet_withdrawal','같은 침수지 바깥 철수 가도와 거두는 군영, 진흙 바퀴자국'),
 29:('footslope_river_front','덴노잔 기슭과 하천 사이 젖은 전면, 넓은 전열 공간'),
 30:('lake_ridge_posts','요고호 옆 서로 다른 능선의 소규모 야전 진지'),
 31:('plain_hill_standoff','넓은 평야 속 낮은 독립 구릉과 야전 군영'),
 32:('rolling_field_front','낮은 푸른 구릉과 열린 들판, 서로 다른 교전 지점'),
 33:('river_hillside_fort','강변 평지와 배후 능선 사면의 대비'),
 34:('flat_moated_fort','평지의 옛 물길과 낮은 성곽 해자, 넓은 육로 포위부'),
 35:('winter_river_terrace','내륙 강의 넓은 자갈 도하부와 하안단구 가장자리를 따라 방향을 바꾸는 전열'),
 36:('night_field_relief','구릉 기슭 야전 진지의 야습 전면과 마른 구원 보급로'),
 37:('red_loam_dry_moats','적갈색 흙의 쇼지보리와 우네보리, 해자 바깥 토교 접근부'),
 38:('plain_edge_encirclement','평야 가장자리의 낮은 산성과 분리된 구릉 포위 진지'),
 39:('wetland_levees','여름 습지 사이 자연제방, 마른 연락로와 수상 상륙부'),
 40:('outer_rampart_siege','총방어 토루의 끝과 해자 바깥 통로, 배후의 시대에 맞는 성하'),
}
EMPHASIZED_BENDS={4,13,18,35,37,40}

# Open fronts, towns, levees and siege posts are authored separately. A single
# symmetric fork algorithm cannot express all of these historical settings.
# Index order preserves the original objective IDs and all wave assignments.
AUTHORED_CORRIDORS={
 2:[[(.90,.035),(.80,.28),(.70,.53),(.60,.69)],[(.70,.025),(.60,.28),(.52,.53),(.43,.69)],[(.50,.035),(.46,.27),(.37,.53),(.30,.68)]],
 12:[[(.24,.025),(.27,.27),(.27,.55),(.29,.72)],[(.42,.025),(.40,.24),(.42,.48),(.43,.66)],[(.66,.025),(.60,.28),(.60,.53),(.58,.73)]],
 14:[[(.975,.53),(.77,.54),(.56,.59),(.39,.72)],[(.975,.76),(.76,.77),(.55,.78),(.39,.72)]],
 21:[[(.84,.025),(.84,.23),(.77,.42),(.66,.59),(.59,.70)],[(.025,.24),(.21,.36),(.35,.51),(.45,.60),(.59,.70)],[(.975,.23),(.94,.37),(.84,.50),(.73,.63),(.59,.70)]],
 22:[[(.90,.035),(.77,.24),(.70,.44),(.64,.66)],[(.63,.025),(.58,.24),(.50,.43),(.44,.65)],[(.18,.025),(.17,.28),(.21,.49),(.26,.68)]],
 23:[[(.84,.025),(.84,.23),(.77,.42),(.66,.59),(.59,.70)],[(.025,.24),(.21,.36),(.35,.51),(.45,.60),(.59,.70)],[(.975,.23),(.93,.37),(.84,.50),(.73,.63),(.59,.70)]],
 25:[[(.69,.025),(.66,.23),(.64,.45),(.59,.65)],[(.21,.17),(.30,.32),(.39,.52),(.59,.70)],[(.975,.28),(.85,.35),(.77,.51),(.65,.67),(.59,.70)]],
 26:[[(.14,.025),(.13,.24),(.12,.43),(.14,.60),(.39,.64),(.51,.75)],[(.30,.025),(.29,.25),(.29,.48),(.34,.63),(.51,.75)],[(.975,.10),(.95,.31),(.93,.52),(.72,.66),(.51,.75)]],
 27:[[(.14,.025),(.13,.24),(.12,.43),(.14,.60),(.39,.64),(.51,.75)],[(.30,.025),(.29,.25),(.29,.48),(.34,.63),(.51,.75)],[(.975,.10),(.95,.31),(.93,.52),(.72,.66),(.51,.75)]],
 28:[[(.14,.025),(.13,.24),(.11,.44),(.12,.65),(.25,.72)],[(.30,.025),(.29,.25),(.30,.48),(.34,.60),(.25,.72)],[(.975,.44),(.95,.50),(.82,.57),(.63,.63),(.42,.64),(.25,.72)]],
 29:[[(.16,.025),(.20,.23),(.18,.46),(.22,.69),(.37,.77)],[(.38,.025),(.39,.25),(.40,.48),(.40,.69),(.37,.77)],[(.75,.025),(.70,.25),(.65,.48),(.56,.69),(.37,.77)]],
 30:[[(.13,.025),(.16,.25),(.17,.46),(.23,.64),(.34,.70)],[(.33,.025),(.32,.32),(.35,.50),(.37,.63),(.34,.70)],[(.975,.52),(.89,.62),(.71,.60),(.52,.65),(.34,.70)]],
 31:[[(.83,.025),(.76,.24),(.67,.43),(.55,.63),(.46,.71)],[(.975,.29),(.91,.34),(.73,.55),(.61,.65),(.46,.71)],[(.21,.025),(.30,.23),(.42,.40),(.44,.60),(.46,.71)]],
 32:[[(.64,.025),(.64,.24),(.58,.47),(.44,.68),(.41,.71)],[(.94,.05),(.91,.27),(.78,.53),(.63,.73)],[(.22,.025),(.23,.25),(.25,.51),(.27,.71)],[(.42,.025),(.42,.25),(.42,.50),(.41,.71)]],
 33:[[(.975,.32),(.91,.48),(.70,.60),(.47,.70),(.36,.73)],[(.975,.56),(.80,.62),(.57,.72),(.36,.73)],[(.975,.80),(.76,.82),(.55,.83),(.36,.73)],[(.20,.025),(.24,.24),(.27,.45),(.33,.61),(.36,.73)]],
 34:[[(.63,.025),(.61,.24),(.58,.46),(.54,.63),(.55,.67)],[(.94,.025),(.85,.22),(.75,.43),(.65,.60),(.55,.67)]],
 35:[[(.60,.025),(.63,.25),(.47,.46),(.42,.61),(.25,.73)],[(.88,.20),(.80,.34),(.65,.44),(.56,.62),(.40,.68),(.25,.73)],[(.37,.025),(.39,.24),(.25,.42),(.22,.63),(.25,.73)]],
 36:[[(.88,.14),(.75,.32),(.63,.48),(.51,.64),(.33,.67)],[(.50,.025),(.47,.25),(.43,.46),(.37,.61),(.33,.67)],[(.16,.025),(.17,.24),(.21,.44),(.27,.61),(.33,.67)]],
 37:[[(.975,.30),(.85,.36),(.84,.51),(.76,.69),(.54,.72)],[(.65,.025),(.62,.21),(.45,.37),(.46,.58),(.36,.65)],[(.13,.025),(.07,.14),(.07,.38),(.16,.56),(.23,.66)]],
 38:[[(.26,.025),(.31,.28),(.40,.49),(.53,.70)],[(.77,.025),(.75,.26),(.68,.47),(.60,.65),(.53,.70)],[(.975,.21),(.92,.38),(.84,.53),(.72,.64),(.53,.70)]],
 39:[[(.975,.08),(.87,.28),(.84,.48),(.72,.60),(.59,.70)],[(.12,.025),(.12,.31),(.25,.43),(.40,.60),(.59,.70)],[(.72,.025),(.72,.28),(.71,.46),(.65,.61),(.59,.70)]],
 40:[[(.975,.12),(.95,.32),(.86,.46),(.73,.60),(.59,.70)],[(.79,.035),(.79,.22),(.78,.41),(.69,.58),(.59,.70)],[(.025,.14),(.16,.37),(.19,.57),(.37,.62),(.59,.70)],[(.025,.32),(.035,.47),(.10,.63),(.29,.68),(.59,.70)]],
}
SHARED_GATE_APPROACHES={14:(.39,.72),21:(.55,.69),23:(.55,.69),25:(.55,.69),26:(.55,.68),27:(.55,.68),28:(.30,.68),29:(.40,.74),30:(.31,.67),31:(.42,.67),33:(.32,.68),34:(.55,.67),35:(.25,.73),36:(.33,.67),38:(.55,.67),39:(.55,.67),40:(.55,.67)}

def author_routes(stage):
    """Use real dry corridors without a shared-lens template."""
    n=stage['stageNumber']
    if n==30:
        post=next(l for l in stage['historicalBattlefield']['sceneLandmarks'] if l['id']=='shizugatake-east-post')
        post.update(y=.81,isGameAdaptation=True)
    if n==40:
        # The abstract full-width wall had no opening at all. Two bank
        # segments make a real dry approach through the outer earthwork.
        # Their exact opening is a game layout, not a documented gate site.
        landmarks=stage['historicalBattlefield']['sceneLandmarks']
        bank=next(l for l in landmarks if l['id']=='odawara-hill-earthwork')
        bank.update(x=.69,y=.32,scale={'w':.08,'h':.055},isGameAdaptation=True)
        east=copy.deepcopy(bank)
        east.update(id='odawara-hill-earthwork-east',x=.87,scale={'w':.10,'h':.055})
        landmarks.append(east)
    terrain=Terrain(stage)
    goals={o['id']:xy(o) for o in stage['objectives']}
    routes=[]
    for path,knots in zip(stage['paths'],AUTHORED_CORRIDORS[n]):
        anchors=list(knots)
        if n in SHARED_GATE_APPROACHES: anchors[-1]=SHARED_GATE_APPROACHES[n]
        anchors.append(goals[path['objectiveId']])
        corridor=smooth_corridor(anchors,terrain)
        points=[along(corridor,k/64)[0] for k in range(65)]
        # Include the actual authored joint, shared with other roads, rather
        # than four unrelated last samples that only appear to meet.
        tail=lerp(anchors[-2],anchors[-1],.60)
        error,_,segment,t=closest(tail,corridor)
        if error<.000001 and terrain.segment(tail,anchors[-1],.018):
            arc=lengths(corridor)
            tail_fraction=(arc[segment]+t*(arc[segment+1]-arc[segment]))/arc[-1]
            points=[along(corridor,k/64)[0] for k in range(65) if k/64<tail_fraction]+[tail,anchors[-1]]
        if not all(terrain.segment(a,b,.018) for a,b in zip(points,points[1:])):
            raise ValueError((n,path['id'],'authored corridor crosses blocked terrain'))
        routes.append(points)
    return routes

def spread_fraction(t):
    # Two separated roads stay parallel across the full middle section.
    # Only the real common camp and final approach are shared.
    if t<.34:
        u=max(0,min(1,(t-.12)/.22))
        return u*u*(3-2*u)
    if t>.64:
        u=max(0,min(1,(.95-t)/.31))
        return u*u*(3-2*u)
    return 1.0

def between_roads(point,routes):
    signs=[]
    for path in routes:
        _,foot,segment,_=closest(point,path)
        axis=sub(path[segment+1],path[segment])
        axis=(axis[0]*WORLD_WIDTH,axis[1]*WORLD_DEPTH)
        delta=sub(point,foot)
        delta=(delta[0]*WORLD_WIDTH,delta[1]*WORLD_DEPTH)
        signs.append((axis[0]*delta[1]-axis[1]*delta[0])/max(math.hypot(*axis),1e-9))
    return min(signs)<-.05 and max(signs)>.05


def write(path,value):
    path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')


def smooth_corridor(anchors,terrain):
    raw=[anchors[0]]
    for a,b in zip(anchors,anchors[1:]):
        if terrain.segment(a,b,.022): raw.append(b)
        else: raw.extend(astar(a,b,terrain)[1:])
    for radius in (.10,.07,.04,.02):
        result=rounded(raw,terrain,radius)
        if all(terrain.segment(a,b,.018) for a,b in zip(result,result[1:])): return result
    raise ValueError('Cannot round corridor safely')


def create_parallel_routes(stage):
    n=stage['stageNumber'];anchors,amplitude,mode,reason=DESIGNS[n]
    anchors=WIDE_ANCHORS.get(n,anchors)
    terrain=Terrain(stage);count=len(stage['paths'])
    starts=[xy(p['points'][0]) for p in stage['paths']]
    if mode=='common': starts=[anchors[0]]*count
    if n in START_OVERRIDES: starts=START_OVERRIDES[n]
    goals={o['id']:xy(o) for o in stage['objectives']}
    center_goal=tuple(sum(p[k] for p in goals.values())/len(goals) for k in (0,1))
    center_base=smooth_corridor(list(anchors)+[center_goal],terrain)
    bases=[center_base]*count
    main_axis=sub(center_goal,anchors[0])
    main_direction=norm((main_axis[0]*WORLD_WIDTH,main_axis[1]*WORLD_DEPTH))
    lane_side=(-main_direction[1]/WORLD_WIDTH,main_direction[0]/WORLD_DEPTH)
    tangent=norm(sub(anchors[1],anchors[0]));normal=(-tangent[1],tangent[0])
    if mode=='independent':
        order=sorted(range(count),key=lambda i:sum(a*b for a,b in zip(sub(starts[i],anchors[0]),normal)))
    elif len(goals)>1:
        lastaxis=norm(sub(tuple(sum(p[k] for p in goals.values())/len(goals) for k in (0,1)),anchors[-1]))
        lastnormal=(-lastaxis[1],lastaxis[0])
        order=sorted(range(count),key=lambda i:sum(a*b for a,b in zip(goals[stage['paths'][i]['objectiveId']],lastnormal)))
    else: order=list(range(count))
    spacing=2.6 if count==4 else 2.8
    lanes={index:(ordinal-(count-1)/2)*spacing for ordinal,index in enumerate(order)}
    candidates=[];rejections=[]
    for scale in (1,.9,.8):
        routes=[]
        for i,base in enumerate(bases):
            points=[]
            for step in range(81):
                t=step/80
                p,_,_=along(base,t)
                side=lane_side
                envelope=spread_fraction(t)
                if n==40:
                    rise=max(0,min(1,(t-.40)/.22))
                    fall=max(0,min(1,(.96-t)/.24))
                    envelope=min(rise*rise*(3-2*rise),fall*fall*(3-2*fall))
                p=add(p,mul(side,lanes[i]*scale*envelope))
                goal_blend=max(0,min(1,(t-.58)/.42))
                goal_blend=goal_blend*goal_blend*(3-2*goal_blend)
                p=add(p,mul(sub(goals[stage['paths'][i]['objectiveId']],center_goal),goal_blend))
                if mode=='independent': p=add(p,mul(sub(starts[i],anchors[0]),max(0,1-t/.28)**2))
                points.append(p)
            points[0]=starts[i];points[-1]=goals[stage['paths'][i]['objectiveId']]
            if not all(.018<=p[0]<=.982 and .020<=p[1]<=.96 for p in points):
                rejections.append((scale,i,'bounds',next(p for p in points if not (.018<=p[0]<=.982 and .020<=p[1]<=.96))))
                break
            if not all(terrain.segment(a,b,.032) for a,b in zip(points,points[1:])):
                try:
                    # A real rock or wall bends its own road; it must not
                    # compress all neighbouring lanes by a global scale.
                    anchors_on_lane=[points[0]]+[points[k] for k in (12,24,40,56,68) if terrain.point(points[k],.026)]+[points[-1]]
                    routed=smooth_corridor(anchors_on_lane,terrain)
                    points=[along(routed,k/80)[0] for k in range(81)]
                    if not all(terrain.segment(a,b,.018) for a,b in zip(points,points[1:])): raise ValueError('unsafe widened route')
                except ValueError as error:
                    rejections.append((scale,i,'terrain',str(error)))
                    break
            # Keep the last real gate approach a shared continuous segment.
            # Dense sampling previously made contact QA overlook this short
            # shared floor even though both armies stand on the same lane.
            if len(goals)==1 and terrain.segment(points[76],points[-1],.018):
                points=points[:77]+[points[-1]]
            routes.append(points)
        if len(routes)==count:
            candidates.append((scale,routes))
            break
    if not candidates: raise ValueError((n,'No safe separated parallel fronts',rejections))
    scale,routes=candidates[0]
    return register_routes(stage,routes,reason,spacing,scale)


def register_routes(stage,routes,reason,spacing,scale):
    n=stage['stageNumber']
    starts=[points[0] for points in routes]
    for path,points in zip(stage['paths'],routes): path['points']=[rec(p) for p in points]
    stage['enemyApproaches']=[dict(rec(p),pathIndex=i,role='path_attacker',terrainBasisKo=reason) for i,p in enumerate(starts)]
    if len(set(starts))==1: stage['commonEnemyEntry']=dict(rec(starts[0]),branchPoint=rec(routes[0][1]),landingIndex=0)
    else: stage.pop('commonEnemyEntry',None)
    stage['historicalBattlefield'].update(routeTopologyKo=reason,
        roadArtPolicyKo='主攻路 전체 폭은 1.10이며 갈래 사이에 전술 공간을 남깁니다. 두 갈래는 분리 구간에서 일정한 간격, 세 갈래는 말단부의 고른 간격을 우선합니다. 실제 문·여울의 합류부 외에는 좁게 붙이지 않습니다. 청록 가이드 밖의 막다른 길·큰 장식 고리는 그리지 않습니다. 별동대 접근로와 후방 수레 순환로는 주력 도로와 구분합니다.',
        interRoadPlacement={'policy':'outer_only' if n in OUTER_ONLY else 'dry_pockets' if n in DRY_POCKETS else 'open_positions','isGameAdaptation':True},
        ambushClearings=[])
    terrain_type,appearance=TERRAIN_COMPOSITIONS[n]
    stage['historicalBattlefield']['terrainComposition']={
        'type':terrain_type,'appearanceKo':appearance,
        'emphasizedBend':n in EMPHASIZED_BENDS,
        'landmarkIds':[l['id'] for l in stage['historicalBattlefield']['sceneLandmarks'] if not l['id'].startswith('enemy-departure-') and not l.get('isGameMission')],
        'layoutIsGameAdaptation':True,
        'historyBasisKo':stage['historicalBattlefield'].get('terrainDesignKo',''),
        'constraintKo':'길의 폭·개수·정확한 꺾임과 소품 위치는 게임 각색입니다. 바위나 사면의 규모에 맞는 짧은 굴곡만 사용하고, 길 밖 장식 때문에 넓은 우회나 새 도로를 만들지 않습니다. 계단이 필요한 단차는 배치 공간 바깥에 두며 주력 도로는 이어지는 경사로로 읽히게 합니다.',
    }
    return routes,{'stageNumber':n,'reasonKo':reason,'terrainType':terrain_type,'emphasizedBend':n in EMPHASIZED_BENDS,'parallelWidthWorld':MAIN_ROAD_WIDTH,'targetLaneSpacingWorld':spacing,'offsetScale':scale,'independentEntrances':len(set(starts)),'routesRequireNewArtwork':True}


def create_routes(stage):
    n=stage['stageNumber']
    if n not in AUTHORED_CORRIDORS:
        return create_parallel_routes(stage)
    routes=author_routes(stage)
    reason=TERRAIN_COMPOSITIONS[n][1]+'를 바탕으로 열린 육상 접근부를 따로 연결합니다. 물·토루·군영 때문에 나뉘는 전선이며 공통 타원 갈림길을 복제하지 않습니다.'
    return register_routes(stage,routes,reason,2.6 if len(routes)==4 else 2.8,1.0)


def placement_pool(routes,terrain,goals,r):
    pool=[]
    for points in routes:
        for f in [i/100 for i in range(8,95,3)]:
            p,segment,_=along(points,f)
            tangent=norm(sub(points[segment+1],points[segment]));normal=(-tangent[1],tangent[0])
            for side in (-1,1):
                for offset in [max(.055,r+.025),max(.08,r+.045),max(.105,r+.07),.15,.185,.20]:
                    q=add(p,mul(normal,side*offset))
                    if not terrain.circle(q,r): continue
                    if not safe_archer_pocket(q,r,routes): continue
                    if any(distance(q,g)<r+.072 for g in goals): continue
                    pool.append(q)
    # Exact existing clear floors are valuable if the new road still serves
    # them. Do not unnecessarily move identities or teaching destinations.
    return list({(round(p[0],5),round(p[1],5)):p for p in pool}.values())


def safe_archer_pocket(point,r,routes):
    # Preserve the full authored deployment radius. The farthest legal edge
    # must still fit the original model and stay outside a physical main road.
    # Convert both the road and circular input pocket to native world units:
    # normalized circles are ellipses in the 18.5x12 tactical field.
    # Side assault trails remain separate and can approach the emplacement.
    if not r+.07<=point[0]<=.93-r or not r+.18<=point[1]<=.96-r:
        return False
    clearance=min(closest(point,path)[0] for path in routes)
    if clearance<r+.55/WORLD_WIDTH:
        return False
    if clearance>=r+.052:
        return True
    world=(point[0]*WORLD_WIDTH,point[1]*WORLD_DEPTH)
    for path in routes:
        for first,second in zip(path,path[1:]):
            a=(first[0]*WORLD_WIDTH,first[1]*WORLD_DEPTH)
            b=(second[0]*WORLD_WIDTH,second[1]*WORLD_DEPTH)
            axis=sub(b,a)
            denominator=axis[0]*axis[0]+axis[1]*axis[1]
            t=max(0,min(1,sum(x*y for x,y in zip(sub(world,a),axis))/max(denominator,1e-12)))
            delta=sub(world,add(a,mul(axis,t)))
            span=math.hypot(*delta)
            if span<1e-9:
                return False
            normal=mul(delta,1/span)
            pocket_extent=r*math.hypot(normal[0]*WORLD_WIDTH,normal[1]*WORLD_DEPTH)
            if span<.55+pocket_extent+.05:
                return False
    return True


def relocate_positions(stage,plans,routes):
    terrain=Terrain(stage);goals=[xy(o) for o in stage['objectives']]
    zones=stage['buildZones'];old=[xy(z) for z in zones]
    pools={r:placement_pool(routes,terrain,goals,r) for r in {float(z['r']) for z in zones}}
    def pool_for(i):
        pool=pools[float(zones[i]['r'])][:]
        q=old[i];r=float(zones[i]['r'])
        d=min(closest(q,p)[0] for p in routes)
        if terrain.circle(q,r) and safe_archer_pocket(q,r,routes) and d<=.205 and all(distance(q,g)>=r+.072 for g in goals): pool.append(q)
        n=stage['stageNumber']
        if n in OUTER_ONLY: pool=[p for p in pool if not between_roads(p,routes)]
        if n in DRY_POCKETS and i not in set(selected)|ADDITIONAL_DRY_POCKETS.get(n,set()): pool=[p for p in pool if not between_roads(p,routes)]
        return pool
    targets=plans['stages'][stage['id']]['missions'][0]['targets']
    selected=[int(t['id'].removeprefix('zone-')) for t in targets]
    labels=[t['label']['jp'] for t in targets]
    axis=0 if labels==['左の支援点','中央の支援点','右の支援点'] else 1 if labels==['上の支援点','中央の支援点','下の支援点'] else None
    target_pools=[sorted(pool_for(i),key=lambda p:distance(p,old[i]))[:90] for i in selected]
    best=None
    for a in target_pools[0]:
        for b in target_pools[1]:
            if distance(a,b)<.22 or axis is not None and a[axis]>=b[axis]-.035: continue
            for c in target_pools[2]:
                if min(distance(a,c),distance(b,c))<.22 or axis is not None and b[axis]>=c[axis]-.035: continue
                cost=sum(distance(p,old[i]) for i,p in zip(selected,(a,b,c)))
                if best is None or cost<best[0]: best=cost,(a,b,c)
    if best is None: raise ValueError((stage['stageNumber'],'No separated learning destinations'))
    positions=dict(zip(selected,best[1]))
    remaining=[i for i in range(len(zones)) if i not in positions]
    # Preserve ID ordering. Target destinations are locked first to keep
    # left/centre/right or upper/centre/lower teaching labels physically true.
    for i in remaining:
        available=[q for q in pool_for(i) if all(distance(q,p)>=max(.074,float(zones[j]['r'])+.006) if stage['stageNumber']==23 else distance(q,p)>=.074 for j,p in positions.items())]
        if not available: raise ValueError((stage['stageNumber'],'No usable emplacement',i))
        positions[i]=min(available,key=lambda p:distance(p,old[i]))
    for i,zone in enumerate(zones): zone.update(rec(positions[i]),betweenRoads=between_roads(positions[i],routes))
    posts=stage.get('tactics',{}).get('groundPosts',[])
    for post in posts:
        i=int(post['pathIndex']);own=[p for p in posts if int(p['pathIndex'])==i]
        ordinal=next(k for k,p in enumerate(own) if p['id']==post['id'])
        fraction=.31+.43*(ordinal+.5)/len(own)
        fraction=POST_FRACTION_OVERRIDES.get(stage['stageNumber'],{}).get(post['id'],fraction)
        _,segment,t=along(routes[i],fraction)
        post.update(segmentIndex=segment,t=round(t,6))
    for aura in stage.get('trait',{}).get('auras',[]):
        nearest=min(range(len(old)),key=lambda i:distance(xy(aura),old[i]))
        aura.update(rec(positions[nearest]))
    for mission in plans['stages'][stage['id']]['missions']:
        for target in mission['targets']:
            target['position']=rec(positions[int(target['id'].removeprefix('zone-'))])
        answer=next(t for t in mission['targets'] if t['id']==mission['answerId'])
        mission['action']['position']=copy.deepcopy(answer['position'])
        existing=stage['historicalBattlefield'].get('learningSupportAnchors',{})
        if mission['id'] in existing: existing[mission['id']].update(answer['position'])
    return [{'id':z['id'],'before':rec(old[i]),'after':rec(positions[i])} for i,z in enumerate(zones)]


def relocate_hunters(stage,routes):
    terrain=Terrain(stage);n=stage['stageNumber'];history=stage['historicalBattlefield']
    history['sceneLandmarks']=[l for l in history['sceneLandmarks'] if not l['id'].startswith('enemy-departure-')]
    for ordinal,entry in enumerate(stage.get('sideAmbushEntrances',[])):
        index=int(entry['pathIndex']);path=routes[index]
        boat=entry.get('transportKind')=='boat'
        start=xy(entry['transportPoints'][-1]) if boat else path[0]
        departure=xy(entry['transportPoints'][0]) if boat else start
        target=next((z for z in stage['buildZones'] if z['id']==entry.get('targetBuildZoneId')),None)
        if target is None: target=min(stage['buildZones'],key=lambda z:distance(xy(z),along(path,.55)[0]))
        _,join,segment,t=closest(xy(target),path)
        staging=add(xy(target),mul(norm(sub(join,xy(target))),.04))
        if not terrain.point(staging,.024): staging=join
        try:
            approach=safe_route(start,staging,terrain,.025 if ordinal%2 else -.025)
        except ValueError:
            if boat: raise
            approach=[]
            for fraction in (.15,.25,.35):
                prefix,_,_=along(path,fraction)
                try:
                    tail=safe_route(prefix,staging,terrain,0)
                    approach=[p for p in path if closest(p,path)[2]<=closest(prefix,path)[2]]+tail
                    break
                except ValueError: continue
            if not approach: raise
        approach+=safe_route(staging,join,terrain,0)[1:]
        entry.update(point=rec(start),enemyDeparturePoint=rec(departure),connectionPoints=[rec(p) for p in approach],
                     segmentIndex=segment,t=round(t,6),targetBuildZoneId=target['id'])
        history['sceneLandmarks'].append({'id':f'enemy-departure-{ordinal+1}','kind':'enemy_dock' if boat else 'enemy_entry_camp',**rec(departure),'scale':{'w':.08,'h':.055},'isGameAdaptation':True})


def main():
    PROFILE.mkdir(parents=True,exist_ok=True)
    source=ROOT/'native/maps.json'
    baseline=PROFILE/'source-maps-baseline.json'
    if not baseline.exists(): baseline.write_bytes(source.read_bytes())
    maps=json.loads(baseline.read_text(encoding='utf-8-sig'))
    plans=json.loads((ROOT/'native/learning_plans.json').read_text(encoding='utf-8-sig'))
    records=[]
    for stage in maps:
        if stage['stageNumber'] not in DESIGNS: continue
        routes,record=create_routes(stage)
        record['zoneMapping']=relocate_positions(stage,plans,routes)
        relocate_hunters(stage,routes)
        records.append(record)
        print('draft',stage['stageNumber'],flush=True)
    write(PROFILE/'maps-balanced-draft.json',maps)
    write(PROFILE/'learning-plans-draft.json',plans)
    write(PROFILE/'design-changes.json',records)
    report=audit(maps,PROFILE/'maps-balanced-draft.json')
    write(PROFILE/'route-audit.json',report)
    draw_sheets(maps,report,PROFILE)
    print(json.dumps({'stages':40,'changedStages':len(records),'sourceUnmodified':source.read_bytes()==baseline.read_bytes(),'candidate':str(PROFILE/'maps-balanced-draft.json'),'flags':[{'n':r['stageNumber'],'ratio':r['lengthRatio'],'flags':r['flags']} for r in report['stages'] if r['flags']]},ensure_ascii=False))


if __name__=='__main__':main()
