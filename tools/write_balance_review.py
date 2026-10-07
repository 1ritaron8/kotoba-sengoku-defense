"""Produce a standalone Korean Markdown review from a read-only Godot export."""
from __future__ import annotations

import hashlib
import json
import math
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROFILE = ROOT / "tests/profiles/combat-growth-removal-20261007"
SNAPSHOT = PROFILE / "source-snapshot"
OUTPUT = ROOT / "GAME_BALANCE_REVIEW.md"
TIER_NAMES = {"basic": "기초", "beginner": "초급", "intermediate": "중급", "advanced": "고급"}
NAMES = {"archer": "궁병", "spear": "창병", "samurai": "사무라이", "gunner": "조총병", "naginata": "장도병", "monk": "승병", "commander": "기마 무장", "ninja": "닌자"}
ENEMIES = {"raider": "일반병", "runner": "질주병", "shield": "방패병", "heavy": "중갑병", "commander": "적 장수", "enemy_archer": "적 궁병", "enemy_gunner": "적 조총병", "enemy_cavalry": "적 기마병", "enemy_samurai": "적 사무라이"}
ORIGIN_CODES = {"raider": "일반", "runner": "질주", "shield": "방패", "heavy": "중갑", "commander": "장수"}
ENEMY_ORDER = list(ENEMIES)
checks: list[str] = []


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def verify(condition: bool, description: str):
    if not condition:
        raise AssertionError(description)
    checks.append(description)


def number(value: float, digits: int = 3) -> str:
    result = f"{float(value):.{digits}f}".rstrip("0").rstrip(".")
    return result if result else "0"


def cell(value) -> str:
    return str(value).replace("|", "\\|").replace("\n", " / ").strip()


def table(headers, rows) -> str:
    return "\n".join(["| " + " | ".join(map(cell, headers)) + " |", "| " + " | ".join("---" for _ in headers) + " |", *("| " + " | ".join(map(cell, row)) + " |" for row in rows)])


def span(values, digits=3) -> str:
    values = list(values)
    if not values:
        return "—"
    low, high = min(values), max(values)
    return number(low, digits) if math.isclose(low, high, abs_tol=1e-9) else f"{number(low,digits)}~{number(high,digits)}"


def support_value(row: dict, key: str) -> float:
    return float(row.get("supportStats", {}).get(key, 0.0))


def main():
    runtime = load(PROFILE / "runtime_balance.json")
    verify(not runtime["failures"], "Godot runtime export has zero failures")
    maps = load(SNAPSHOT / "maps.json")
    units = load(SNAPSHOT / "units.json")["units"]
    story_data = load(SNAPSHOT / "campaign_story.json")
    story = {x["stageId"]: x for x in story_data["stages"]}
    curriculum = load(SNAPSHOT / "curriculum.json")
    plans = load(SNAPSHOT / "learning_plans.json")["stages"]
    heroes = load(SNAPSHOT / "hero_catalog.json")["heroes"]
    account = {"available":False}
    stages = runtime["stages"]
    levels = {(x["id"], x["permanentLevel"]): x for x in runtime["friendlyLevels"]}
    definitions = {x["id"]: x for x in units}
    lessons = [x for tier in TIER_NAMES for x in curriculum[tier]]
    verify(len(stages) == len(maps) == len(lessons) == len(story) == 40, "40 stages, lessons and historical narrative entries covered")
    verify(len(levels) == 80 and len(definitions) == 8, "All eight friendly units and ten permanent levels covered")
    verify(len({x["stageId"] for x in stages}) == 40, "Stage identifiers are unique")
    for stage in stages:
        config = stage["config"]
        for enemy in stage["enemyTemplates"]:
            base = (32.0 + enemy["sourceWave"] * 10.0) * config["difficulty"]
            multiplier = {"raider": 1.0, "runner": .7, "shield": 1.65, "heavy": 2.2, "commander": 6.0}[enemy["originKind"]]
            for bonus in config.get("trait", {}).get("enemyBonuses", []):
                if bonus.get("kind", "all") in (enemy["kind"], enemy["originKind"], "all"):
                    multiplier *= bonus.get("hpFactor", 1.0)
            verify(math.isclose(enemy["health"], base * multiplier, rel_tol=1e-10), "Independent enemy HP cross-check")
        for minutes in (10, 20):
            mode = stage["modes"][str(minutes)]
            verify(mode["totalWaves"] == {10: 21, 20: 41}[minutes], "Correct timed wave count")
            verify(math.isclose(mode["waves"][-1]["endSeconds"], minutes * 60), "Correct mode deadline")
            for wave in mode["waves"]:
                verify(sum(wave["composition"].values()) == wave["initialScheduledCount"], "Scheduled composition totals match")
    parts: list[str] = []
    add = parts.append
    add("# 말의 전장 — 현재 유닛·스테이지·시스템 상세 명세와 밸런스 검토안\n")
    add(f"기준: {runtime['snapshot']['capturedAt']} (한국 시간). PC용 오프라인 Godot 네이티브 구현 기준입니다. 아래 ‘현재 구현’은 실제 코드·JSON과 Godot 계산 결과이며, ‘조정 후보’는 아직 적용하지 않은 검토안입니다. 웹 프로토타입의 옛 수치를 섞지 않았습니다.\n")
    add("이 파일만 다른 AI에 전달해도 수식과 조건을 검토할 수 있도록 작성했습니다. 표는 소수점 최대 3자리(사거리·속도는 일부 5~6자리)로 반올림했습니다. 계산 시에는 본문 수식을 사용하십시오. 스테이지별 지형은 역사 기반 재작성 중이므로 아래 지형·작전 설명은 **이 문서가 캡처한 버전**이며, 장수의 병종 배정·가상 주인공의 임무는 게임 각색입니다.\n")
    add("40개 전장의 수치 표는 아래 source SHA의 데이터 기준입니다. 새 배경 제작과 EXE 검증은 별도 진행 중이며 이 수치 문서는 그 완료를 주장하지 않습니다.\n")
    add("## 1. 먼저 읽을 핵심과 변경 상태\n")
    add("- 아군은 **8종**, 적은 **9개 표시 병종**입니다. 적 조총병·궁병 진지는 원래 병종에 따라 체력·장갑이 달라질 수 있습니다.\n- 성장은 병영의 영구 훈련 `L=1~10`과 진화입니다. 스킬은 영구 **3·5·8레벨**, 장비 진화는 **4·8레벨**입니다.\n- 이번 추가 요청을 반영해 승병의 기본 치료·회복 부적·승전 기도, 전의 지원과 아군 피해 감소도 성장하게 수정했습니다. 다른 공격 스킬은 이미 성장한 공격력을 입력받으므로 성장 배율을 다시 곱하지 않습니다.\n- 닌자는 **기습/암살 후 복귀하는 현재 방식**입니다. 닌자의 3·5·8레벨 신규 스킬은 현재 없습니다.\n- 10·20분은 전투 시뮬레이션 시간입니다. 질문·메뉴·일시정지는 시간을 소비하지 않으며 배속은 실제 플레이 시간을 줄입니다. 적이나 보스가 남아도 마지막 시간에 모든 아군 거점이 생존하면 승리합니다.\n- 수치 추출·기능 검증과 ‘40개 전장을 사람이 살짝 어렵게 깰 수 있다’는 밸런스 검증은 다릅니다. 후자는 아직 확정하지 않았습니다.\n")
    if account.get("available"):
        cleared = [x for x in account.get("clearedStageIds", []) if x]
        add(f"읽기 전용으로 확인한 현재 로컬 계정: 제패 {len(cleared)}개, 군자금 {account['army']['currency']}, 선택 시간 {account.get('battleMinutes',5)}분. 확인 시각 {account['capturedAt']}. 영구 레벨: "+", ".join(f"{NAMES[u['id']]} Lv.{account['army'].get('levels',{}).get(u['id'],1)}" for u in units)+". 개인 학습 상세 기록은 이 문서에 포함하지 않았습니다.\n")
    add("## 2. 게임·성장·학습 시스템\n")
    add("병종 선택 카드는 기존 병사의 정적 컷아웃과 종이 질감을 사용합니다. 작은 카드의 일본어는 弓(활)·槍(창)·侍(사무라이)·鉄砲(조총)·薙刀(장도)·僧兵(승병)·騎馬(기마)·忍者(닌자)처럼 짧게 표시하고, 한국어로 병종을 식별합니다. 전체 부대명·읽기·진화명은 상세 정보와 툴팁에서 확인합니다. 이는 화면 표기만 바꾼 것이며 학습 단어·유닛 ID·성장·비용·해금 수치는 바꾸지 않습니다.\n")
    add("### 2.1 전투와 소환\n\n원하는 병종을 골라 금화를 지불합니다. 궁병은 황금색 사격 진지, 조총병·승병·장도병은 청록 전선/지원점, 닌자는 보라색 외곽 엄폐점에 배치합니다. 창병·사무라이·기마 무장은 기지에서 생성되어 적 진입구 쪽으로 전진합니다.\n\n생산은 **최대 24개 주문의 병렬 타이머**입니다. 직렬 스택이 아닙니다. 주문 확정 시 비용이 빠지고 병종별 생산 시간이 지나야 나옵니다. 배치형은 자리 선택이 확정될 때 비용을 내며, 예약 지점은 다른 주문과 겹칠 수 없습니다. 생산 완료 후 정원이 부족하면 `waiting_capacity`로 기다립니다. 창병 2인 소집은 빈칸 2개가 있어야 둘이 함께 나옵니다. 취소는 주문당 한 번 전액 환불합니다.\n\n전진형은 생성 후 같은 출진로에 동료가 모이거나 적이 가까워지면 움직이고, 혼자면 최대 2.5초 집결한 뒤 출발합니다. 같은 길의 3개 좁은 대열을 사용합니다. 창병·사무라이가 약 0.0588, 기마 무장이 약 0.091의 정규화 거리/초로 걷고 기마 돌진 시 1.35배입니다. 장도병은 주어진 수비 반경 안에서 접근/쓸기/돌진 후 복귀합니다. 닌자는 약 0.0728 거리/초로 엄폐에서 육지 경로를 따라 접근합니다. 이동은 지형의 mobilityFactor 등에 영향을 받습니다.\n\n적은 아군 병사뿐 아니라 배치된 궁병·조총병·승병·장도병도 공격합니다. 거점은 길 끝까지 통과한 적에게 1/2/3/5 피해를 받습니다. 어느 거점이든 HP가 0이면 즉시 패배합니다. 아군 HP가 0이면 전사하며 모집 비용이 환불되지 않습니다. 현재 자동 부활·자가 회복·부상 시 기지 후퇴는 없고, 승병이 살아 있는 아군을 치료합니다.\n")
    add("### 2.2 병영 훈련과 경제\n")
    add(table(["종류", "비용/조건", "실제 효과"], [["영구 훈련 L", "군자금; 최대 Lv10", "공격/체력/사거리/공격간격/피해 감소 성장, 승병 치료·지원 성장; Lv3/5/8 스킬"], ["훈련 던전", "별도 메뉴; 현재영구Lv1의 체험 병력; 최대75초", "배치/실제 명중/치료/닌자 명령과 복귀 확인. 완수 기록 저장; 현재 본 전투 사용의 필수 관문은 아님"]])+"\n")
    add(table(["영구 훈련", "군자금 비용", "누적 비용"], [[f"{x['from']}→{x['to']}", x['cost'], sum(y['cost'] for y in runtime['permanentUpgradeCosts'] if y['to']<=x['to'])] for x in runtime["permanentUpgradeCosts"]])+"\n")
    add("군자금은 전투 금화와 별도입니다. 초기 군자금180으로 한 병종을 Lv1→2(140) 훈련할 수 있습니다. 첫 제패 기본 보상 `140+8×스테이지 번호`, 재제패 `40+2×번호`, 여기에 이번 판 정답 수×5(최대100)를 더합니다. 처음 40개를 한 번씩 깨는 기본 보상 합은 12,160, 초기 포함12,340입니다. 한 병종 Lv1→10은5,148, 8종 전부는41,184이므로 전체 최대 강화에는 반복 플레이가 필요합니다. 이 계산은 전투 금화를 군자금으로 바꾸지 않습니다.\n\n전투 금화는 초기 맵별 금화 + 적 처치금(7/11/15/45) + 웨이브 종료 보급(40+3×실제웨이브) + 맵 추가 보급 + 정답 보상으로 공급됩니다. 정답은 궁병 일제 엄호·진군 북소리·적 보급선 교란·낙석 지원·산악 조총대 엄호 중 지형과 상황에 맞는 지원 하나를 추첨합니다. 힌트는 지원 강도0.55배이며, 오답/건너뛰기에는 지급하지 않습니다. 정상 Main은 전투 금화70/25를 지급하는 legacy grant_reward를 호출하지 않습니다.\n")
    add("### 2.3 10·20분과1x·2x 모드, 적 생성\n")
    mode_rows=[]
    for minutes,waves in [(10,21),(20,41)]:
        mode_rows.append([f"{minutes}분", waves, "20초 / 25초", number((60*minutes-45)/(waves-2)), sum(40+3*w for w in range(1,waves+1)), 0, len([w for w in range(1,waves+1) if w%5==0 or w==waves])])
    add(table(["모드", "파상 수", "첫 두 파상", "이후 각 파상 초", "기본 보급 총합", "정답 보급금", "예정 장수 수"],mode_rows)+"\n")
    add("맵의 원래 10~12개 파상 편성을 앞에는 적고 뒤에는 많게 재분배한 뒤, 선택 시간에 맞는 시간 창에 배정합니다. 실제 출현 개체는 **원래 출처 웨이브 s**를 보존하여 HP·기초 속도·공격 피해를 계산합니다. 현재 웨이브 w와 s는 다릅니다. 뒤쪽 시간 창은 약8파상에 원래 마지막 편성으로 올라간 뒤 반복하므로 20분이라고 개체 HP가 끝없이 증가하지 않습니다.\n\n첫 파상 동시 생존 적8, 둘째12, 이후16→20→24→28→32→36으로 올라가 최대36입니다. 첫 생성 지연3/2/1초, 생성 간격 첫 파상1.50초·둘째1.35초·이후1.15→0.62초입니다. 앞 시간 창에서 못 나온 적 주문과 생존 적은 다음 창으로 이어질 수 있습니다. 제한에 걸린 생성은 한꺼번에 밀어내지 않고 기다립니다.\n\n편성 패턴은 1~2파상 산발 교전, 그 후 `대형→기마 선봉→난전` 반복입니다. 대형은 같은 길에 6명 묶음·3개 열·전후 간격을 사용하며 방패/중갑을 우선 정렬합니다. 3파상부터 일부 일반병이 궁병으로, 6단계부터 일부 방패/중갑이 조총병으로, 9단계부터 질주병이 기마병으로 바뀝니다. 5단계부터 일부 중갑은 사무라이입니다. 15단계부터 3파상 이상의 첫 해당 적을 사격 진지로 시도하며 홀수는 궁병·짝수는 조총병입니다. 지형에 합법적인 진지/닌자 접근로가 없거나 이미 점유되어 있으면 고정 진지가 안 생길 수 있습니다.\n\n빈 시간 창에는2초 주기로 작은 적 묶음을 보충합니다. 따라서 표의 예정 병력 수는 고정된 전체 실제 출현 수가 아닙니다. 보충 조건은 생성 주문이 비었고 종료까지0.8초 이상, 생존 적 수가 맵 원래 편성 기반 문턱보다 적을 때입니다. 보충은 별도 웨이브 보급/문제를 만들지 않지만 처치금은 줍니다. **빠른 처치→추가 적→추가 처치금→추가 생산** 루프가 있습니다.\n")
    add("### 2.4 일본어 학습과 지도 해금\n")
    add(table(["단계", "지도 수", "지도당 새 단어", "복습 예산", "구조화 문법 단계", "현재 해금 시험 문항"], [[TIER_NAMES[t],10,len(curriculum[t][0]["newWords"]),"첫맵0, 이후15" if t=="basic" else len(curriculum[t][0].get("reviewIds",[])),"각 지도2" if t in ("basic","beginner") else "현재0",len(curriculum[t][0]["newWords"])+len(curriculum[t][0].get("grammarSteps",[]))] for t in TIER_NAMES])+"\n")
    add("새 단어는 전체900개(150+200+250+300)입니다. 복습은 과거에 실제 노출된 단어의 정답/오답/힌트/복습 예정 기록에서 골라 예산까지 채우므로 예산과 실제 개수는 다릅니다. 처음에는 히라가나를 읽는 사용자가 후리가나·한국어 뜻·짧은 예문·기초 문법을 연결합니다. 단어/예문은 읽기 길이에 따라 실제 화면 시간12~20초씩 머물고, 바쁜 화면/질문/정지에서는 노출을 중단합니다. 2배속은 전투 시간만 가속하므로 같은 판에 실제로 읽을 여유·노출 수가 줄 수 있습니다. 정규화된 한자 읽기 덩어리를 색으로 대응시키며, UI 병종 이름을 임의로 한 글자씩 잘라 읽기를 바꾸지 않습니다.\n\n비최종 웨이브 종료마다 전장을 멈추고 문장 **해당 단어만 빈칸**으로 만든 선택 문제를 냅니다. 전장 위치 요청·뜻·예문·가능한 경우 듣기를 사용합니다. 전장 위치 문제 정답도 위5종 지원 중 하나를 실제 해당 전선에 연결합니다. 같은 응답 ID는 중복 지급하지 않습니다.\n\n다음 지도는 **바로 이전 지도 승리와 그 지도 전 문항 무힌트 정답 시험**이 필요합니다. 시험은 새 단어 전부+구조화 grammarSteps를 포함하고 한 번 오답/힌트/건너뛰기를 쓰면 그 시도는 실패합니다. 시험에는 보급금·군자금·SRS 정답 보상이 없습니다. 교과 범위의 해시가 바뀌면 옛 시험 합격을 재사용하지 않습니다.\n\n‘이번 해금 시험 통과’와 ‘장기 숙련’은 구분합니다. 장기 숙련은 무힌트 연속 성공3회 이상·서로 다른 날짜2일 이상·첫/최근 성공 간20시간 이상·문장 문맥2개(뜻/듣기 문맥1개)가 필요합니다. 무힌트 성공은 복습1일→숙련7일→성공6회14일→10회30일; 힌트는30분, 오답은10분 뒤 재복습을 잡습니다. **현재 중급·고급은 structured grammarSteps가0이므로 문법 이름/예문이 있어도 해금 시험이 문법 전부를 검증한다고 주장할 수 없습니다.**\n")
    add("## 3. 아군 전체 상세 정보\n")
    add("### 3.1 영구 Lv1의 기초 스펙\n\n맵/고도/아군 버프가 없는 기준입니다. `사거리`는 0~1 전장 좌표의 유클리드 거리이며 픽셀·미터가 아닙니다. 근접병의 실제 접촉 피해 거리는 별도 `접촉 reach`입니다. 표의 D/공격간격은 명목 DPS이며 실제 애니메이션·이동·공통 일제사격 주기에 따라 낮아집니다.\n")
    add(table(["병종", "해금: 제패 수", "비용", "생산 초", "HP", "피해 감소", "공격", "간격 초", "명목 DPS", "사거리", "접촉 reach", "기본 저지 수"], [[NAMES[u["id"]],u["unlockClears"],u["cost"],number(u["recruitSeconds"],3),number(levels[u["id"],1]["health"]),number(levels[u["id"],1]["armor"]*100)+"%",number(levels[u["id"],1]["damage"]),number(levels[u["id"],1]["interval"]),number(levels[u["id"],1]["nominalDps"]),number(levels[u["id"],1]["range"],5),number(levels[u["id"],1]["contactReach"],5),levels[u["id"],1]["capacity"]] for u in units])+"\n")
    add("승병의 공격력0/명목 공격DPS0은 정상입니다. 기본 치료는1초마다6HP이며 자해·죽은 대상 부활은 하지 않습니다. 진지 capacityBonus가 있으면 일부 근접병 저지 수가 증가하며, 기본 저지 수와 capacityBonus의 합은1~4로 제한됩니다. 조총병은 항상1, 궁병은0입니다. 승병도 근접 저지 판정에 참여할 수 있어 전선 바로 앞에 놓으면 위험합니다.\n")
    add(table(["병종", "배치/행동", "기본 특징/주의"], [[NAMES[u["id"]],u["role"],u["description"]] for u in units])+"\n")
    add("### 3.2 공통 성장 수식\n\n```text\nL = 병영 영구 훈련(1..10), e = 진지 고도\n진화: L<4 기본 / 4<=L<8 1차 / L>=8 2차 (두 진화 배율을 중복 곱하지 않음)\nE_D = 1 / 1.12 / 1.30\nE_R = 1 / 1.04 / 1.08\nE_I = 1 / 0.96 / 0.92\nE_H = 1 / 1.12 / 1.25\nP = [1+0.08(L-1)] * E_D\n\n공격 D = D0 * P\nHP = H0 * [1+0.05(L-1)] * E_H\n사거리 R = R0 * [1+0.12e] * [1+0.012(L-1)] * E_R\n공격 간격 I = max(0.25, I0 * E_I / [1+0.015(L-1)])\n방어 A = clamp(A0 + 0.006(L-1) + 갑주스킬보너스, 0, 0.65)\n실제 아군 HP 손실 = incoming_damage * (1-A), 무적이면0\n\n승병 치료 배율 H = P\n기본 치료 = 6H / 1초\n회복 부적 = 2H / 1초 * 4초 (Lv3 해금)\n승전 기도 = 대상별18H (Lv8 해금)\n기도 마나 회복 = min(100, 20P), 기마 돌진 쿨타임 감소 = 2P초\n전의 진언 = 1+0.12P (Lv5 해금, 여러 승병 중 가장 강한1개만)\n```\n")
    add("이후 맵별 공격/사거리/간격 보정, 위치·시간 기반 오라, 학습 지원, 고유 스킬을 적용합니다. 궁병 Lv3 이후 D×1.08, 장도병 Lv3 이후 R×1.08·접촉 reach×1.08, 조총병 Lv5 이후 I×0.92를 추가합니다. 사무라이 Lv3 갑주 보너스는 피해 감소+0.12입니다. 창병은 가까운 Lv5 사무라이에 D×1.15, 대형 조건을 만족한 전진 병력은 D×1.12를 받을 수 있고 이 둘은 서로 곱해집니다.\n\n회복 부적은 시전 때의 치료량을 저장하며, 범위를 벗어나거나 시전자가 전사해도 이미 받은 부적은 남은4초 범위에서 회복합니다. 같은 부적은 합산하지 않고 더 강한 회복량과 남은 갱신을 사용합니다. 기본 치료는 같은1초 pulse에 같은 아군을 여러 번 치료하지 않고 강한 치료자부터 배정합니다. 기도 역시 같은 수혜자의12초 수혜 제한이 있습니다. 퍼센트 공격 버프/관통 피해계수/발동확률/지속시간을 다시 전체 성장 배율로 키우는 방식은 사용하지 않습니다.\n")
    add("### 3.3 병종별 모든 영구 레벨 수치\n\n고도0·맵 보정 없음·다른 아군 없음. 자기 스킬의 공격/사거리/장전 보정은 포함합니다. 사무라이의 갑주 스킬도 피해 감소 열에 포함합니다.\n")
    for u in units:
        uid=u["id"]
        add(f"#### {NAMES[uid]} — {u['jp']} ({u['reading']})\n")
        add(table(["L", "진화", "HP", "피해 감소%", "공격", "간격초", "명목 DPS", "사거리", "1주문 생성 수", "치료/1초"],[[L,levels[uid,L]["evolutionStage"],number(levels[uid,L]["health"]),number(100*levels[uid,L]["armor"]),number(levels[uid,L]["damage"]),number(levels[uid,L]["interval"]),number(levels[uid,L]["nominalDps"]),number(levels[uid,L]["range"],5),levels[uid,L]["recruitQuantity"],number(levels[uid,L]["healAmount"]) if uid=="monk" else "—"] for L in range(1,11)])+"\n")
        add("진화: "+" / ".join(f"Lv{e['level']} {e['name']} ({e['jp']})" for e in u["evolutions"])+".\n")
    add("승병 성장 확인: Lv1 기본 치료6 → Lv5 "+number(levels["monk",5]["healAmount"])+" → Lv10 "+number(levels["monk",10]["healAmount"])+"HP/초. Lv10 기도는40.248HP/대상이며 대상의 빈 HP를 넘겨 회복하지 않습니다.\n")
    add("### 3.4 모든 스킬·기본 특성의 실제 조건과 계수\n")
    skills = [
        ["궁병",3,"일제사격","D×1.08. 궁병끼리 전체 공통 사격창0.10초; 현재 가장 느린 궁병 간격을 주기로 사용. 창마다 궁병당1회."],
        ["궁병",5,"불화살","생존한 명중 적에3초 화상. 초당 min(20, 공격계획 기초D×0.07),0.5초 tick. 같은 화상은 강한DPS만 유지/기간갱신."],
        ["궁병",8,"광역 화살비","3발×각0.45D. 각 착탄 반경0.045의 주대상 제외 최대4명에 해당 화살D×0.28(즉0.126D). 모든 화살이 주대상을 맞을 때 주대상 합계1.35D."],
        ["사무라이",3,"갑주 보강","공통 레벨 방어 위에 피해 감소+12%p. 총 피해 감소 상한65%."],
        ["사무라이",5,"창병 지원","반경0.17 내 육지 연결된 창병 D×1.15. 여러 사무라이를 중복 합산하지 않음."],
        ["사무라이",8,"벽력일섬","주 공격의 적사무라이에4% 즉사. 역사 장수/보스는 제외. 일반병·방패병·중갑 표시만으로 즉사하지 않음."],
        ["창병",3,"관통 찌르기","주대상 뒤 같은 경로 길이0.085·폭0.016 안 최대4명에0.55D. 육지 연결 필요."],
        ["창병",5,"2인 소집","90금/2.275초에2명. 정원2칸을 요구하고 각각 독립 HP/공격을 유지."],
        ["창병",8,"독창","4초 중독. 초당 min(20, 공격계획 기초D×0.06),0.5초 tick. 같은 독은 합산되지 않음. 화상과 독은 별개."],
        ["조총병",3,"관통탄","탄착 후 주대상 뒤 같은 경로 길이0.16·폭0.014 안 최대4명에0.65D."],
        ["조총병",5,"장전 숙련","공격 간격×0.92. 공격력/진화 성장과 별개로 적용."],
        ["조총병",8,"갑옷 약화탄","생존한 명중 적 장갑×0.65를2.4초 적용. 첫 탄 자체가 아닌 후속 공격부터 혜택; 만료 시 복원."],
        ["장도병",3,"넓은 쓸기","기본 쓸기 반경0.055→0.070, 주대상 외 같은 길 최대4명에0.55D. 탐지 사거리·접촉 reach×1.08."],
        ["장도병",5,"호위 돌진","마나100, 초당14(진언 보정 가능). 수비선 내 반경0.10에적2명 이상이면 돌진: 이동×1.4·주 공격1.45D; 같은 공격 쓸기 계수도 해당D 사용."],
        ["장도병",8,"돌진 방호","돌진 실제 명중 후1.1초 무적. 일반 공격·취소된 돌진에는 발동하지 않음."],
        ["승병",3,"회복 부적","기본 치료가 실제로 회복했을 때4초 부적. 초당2H, 성장량 시전 시 저장. 대상 범위 이탈 후에도 남은tick 수행."],
        ["승병",5,"전의 진언","지원 반경 안 장도병 마나·기마 돌진 쿨타임 준비에1+0.12P. 예:Lv5 +17.741%,Lv10 +26.832%. 여러 승병 중 최대값 하나."],
        ["승병",8,"승전 기도","지원 반경 내 아군 처치6회, 쿨타임12초. 주변 필요 대상 각각18H 치료, 장도 마나min(100,20P)·기마 돌진 대기−2P초. 같은 수혜자 중복 적용도12초 제한."],
        ["기마 무장",3,"기마 돌진","첫 실제 접근 돌진 포함, 주 피해2.2D. 일반공격간격×6의 돌진 대기시간, 돌진 이동×1.35; 자동 전진 유지."],
        ["기마 무장",5,"전열 대형","같은 출진로·반경0.14·서로 다른 대열열·비슷한 방향(dot≥0.8)의 창/사무라이/기마가 지휘관 포함3명 이상: 구성원 D×1.12."],
        ["기마 무장",8,"대형 붕괴","돌진 주대상이 실제 formation이면 같은 그룹·같은 길·반경0.10 적들의 대열을3초 해제/흩뜨림. 개별 HP나 장갑을 직접 감소시키는 스킬은 아님."],
        ["닌자","기본","기습·진지 암살·복귀","일반 기습은1회 타격 후복귀. 명령한 고정 사격진지는 파괴하거나 접근 불가능해질 때까지 공격 후복귀. HP30% 이하 적에는피해×1.5. 현재 스킬 해금 목록0개."],
    ]
    verify(len(skills)==22, "21 implemented unlock skills plus ninja base behavior documented")
    add(table(["병종", "영구 레벨", "이름", "실제 효과"],skills)+"\n")
    add("관통·화상·독·장도 쓸기·돌진·화살비는 **현재 공격D**에서 출발하므로 영구 훈련, 맵 보정의 영향을 받습니다. 다만 화상/독20DPS 상한, 최대4명 보조 명중, 사거리·지형·원래 대상의 생존 때문에 무조건 명목 배율만큼 DPS가 나오지는 않습니다. 화상/독 피해도 보통 장갑 계산을 거치며 ‘고정 피해’가 아닙니다. 이미 발사된 탄환과 지속 상태는 발사/시전 당시 수치를 사용합니다. 기도6처치는 보급·학습 보상으로 채울 수 없습니다.\n")
    add("### 3.5 장수 배정과 합류\n")
    add(table(["부대", "장수", "합류 단계", "표시/구분"],[[NAMES[h["unitId"]],h["nameKo"]+" · "+h["jp"],h["joinStage"],h.get("historyKo","")] for h in heroes])+"\n")
    add("병종은 제패 수로 먼저 해금될 수 있고 해당 역사 장수의 스토리 합류 시점과 같지 않습니다. 합류 전에는 ‘명장 모티브·합류 전’으로 표시합니다. 닌자 부대는35단계부터 하치스카 마사카쓰→이에마사로 바뀝니다. 장수 이미지는 전승 초상 기반정적2D이며 전장 부대원은 일반 병사3D입니다. 얼굴/장수 병종 배정을 사료상 전문 병종 지휘 사실이라고 주장하지 않습니다.\n")
    add("## 4. 적 전체 스탯·장갑·공격 규칙\n")
    add("### 4.1 적의 기본 원형\n\n```text\ns = 개체가 보존한 원래 출처 웨이브(맵별1..10/11/12), d = 맵 difficulty\n기초HP B = (32+10s)*d\n기초 이동 v = 0.020 + 0.00035s\n실제 적 HP = B * 원형HP배율 * 해당 맵 적HP보너스\n기초 속도 = v * 원형속도배율 * 해당 맵 적속도보너스\n아군에게 공격하는 한 번 피해 = (4+0.6s) * 원형거점피해수치\n거점에 통과할 때 피해 = 원형거점피해수치 (difficulty를 다시 곱하지 않음)\n```\n")
    add(table(["원형", "HP배율", "속도배율", "장갑", "거점피해", "처치금", "근접 반격 간격", "기본 기능"],[["일반병",1,1,"0%",1,7,"0.95초","길 진군/근접진지추격"],["질주병",.7,1.5,"0%",1,7,"0.95초","빠른 길 진군"],["방패병",1.65,.78,"38%",2,11,"0.95초","장갑높음;방향성방패면역은없음"],["중갑병",2.2,.72,"25%",3,15,"1.1초","체력이높지만장갑은방패병보다낮음"],["적장수",6,.62,"30%",5,45,"1.1초","역사상대이름/보스피격조건;별도개인스킬없음"]])+"\n")
    add(table(["파생 표시 병종", "원형", "공격/기능", "주의"],[["적 궁병","보통일반;진지는다른원형도가능","거리0.205,간격0.85초,발사선딜0.25초","원형의HP·장갑·거점피해·처치금을그대로사용"],["적 조총병","방패또는중갑;진지는다른원형도가능","거리0.14,간격1.55초,발사선딜0.25초","방패원형총병은장갑38%,중갑원형은25%"],["적 기마병","질주","질주원형속도/근접반격","외형/선봉편성다양화;적기마전용2.2배돌진스킬없음"],["적 사무라이","중갑","중갑원형근접반격;벽력일섬대상","갑주/전용회피스킬없음"],["고정 사격 진지","궁/총표시+현재선택원형","합법진지에서정지사격;닌자명령대상","별도독립강화체력배율없음;장수즉사대상아님"]])+"\n")
    add("적이 사격할 때 범위·육지 연결을 검사합니다. 가까운 아군에게 저지되면 원형의 근접 반격으로 바뀔 수 있습니다. 적 근접은 궁/총/승병/장도병을 거리0.23에서 감지해 경로를 벗어나 추격하고0.032 안에서 반격합니다. 궁병 기본사거리0.205보다 감지범위가 크고 고도1의0.2296과도 거의 같아, 고지가 피격 면역은 아닙니다.\n\n실제 진군 속도는 위 기초속도×접근배율(초반2.35→후반4.0)이며 아군 교전권에 들어오면1.35로 낮아집니다. 적 대형 앞열과의간격, 슬로우, 오라, 항구 상륙(×1.6), 눈보라(×0.62/중심정지)가 추가됩니다. 야간은 횃불/아군/거점 가까이서만 표적을 볼 수 있습니다. 역사 지형 교정에서 이런 테마가 바뀌면 **숫자 JSON이 같아도 실전 난이도가 달라질 수 있습니다.**\n")
    add("### 4.2 아군 공격의 장갑 적용과 역할 비교\n\n적 장갑 a에 대한 일반피해는 D×(1−a)입니다. 사무라이·기마는 장갑의40%만, 조총병은30%만 적용합니다. 닌자는 적 현재HP≤최대HP30%일때 피해×1.5를 추가합니다. 갑옷약화탄 상태라면 우선 장갑×0.65 후 이 관통 계산을 합니다.\n")
    add(table(["적 장갑", "창/궁/장도/닌자 피해 계수", "사무라이/기마", "조총"],[[f"{a*100:.0f}%",number(1-a),number(1-a*.4),number(1-a*.3)] for a in [0,.25,.30,.38]])+"\n")
    add(table(["Lv1 병종", "무장갑 명목DPS/금", "장갑25% DPS/금", "장갑38% DPS/금"],[[NAMES[u["id"]],number(levels[u["id"],1]["nominalDps"]/u["cost"],4),number(levels[u["id"],1]["nominalDps"]*(1-.25*(.3 if u["id"]=="gunner" else .4 if u["id"] in ("samurai","commander") else 1))/u["cost"],4),number(levels[u["id"],1]["nominalDps"]*(1-.38*(.3 if u["id"]=="gunner" else .4 if u["id"] in ("samurai","commander") else 1))/u["cost"],4)] for u in units if u["id"]!="monk"])+"\n")
    add("이 표만으로 승자를 고르면 안 됩니다. 궁병은 안전거리·다중 길 지원, 조총은 원거리·관통, 전진형은 이동과피격·몸수, 닌자는 왕복시간, 고급스킬은 광역/지원의 영향이 있습니다. 다만 ‘25%중장갑에게 조총이 창보다 확실한 효율우위’라는 의도는현재Lv1단일DPS/금에서차이가작아추가검토가필요합니다.\n")
    add("## 5. 40개 스테이지 전체 수치\n\n아래 전부 캡처한 맵의 실제 난이도/거점/금화/작전과 원래 적 HP 표입니다. 스토리의 역사 전투명으로 식별하고 런타임 stageId를 함께 적었습니다. 10분 파상표의 개체수는 **이 시간창에 추가 예정인 초기주문**이며, 미출현이월/보충때문에 실제출현수와다릅니다. 장수는 해당w의planSourceWave를 쓰고, 각 일반 개체는 서로다른s를 쓸 수 있습니다.\n")
    add(table(["단계", "구간", "역사 전투/국면", "d", "원래 파상", "초기 금", "정원", "거점HP", "새단어/복습예산/시험"],[[m["stageNumber"],TIER_NAMES[m["tier"]],story[m["id"]]["battleKo"]+" · "+story[m["id"]].get("phaseKo",""),number(m["difficulty"],4),m["totalWaves"],m["initialGold"],m["unitLimit"],"/".join(str(o["hp"]) for o in m["objectives"]),f"{len(lessons[i]['newWords'])}/{len(lessons[i].get('reviewIds',[]))}/{len(lessons[i]['newWords'])+len(lessons[i].get('grammarSteps',[]))}"] for i,m in enumerate(maps)])+"\n")
    for i,stage in enumerate(stages):
        m=stage["config"]; hist=story[m["id"]]; lesson=lessons[i]; trait=m.get("trait",{})
        add(f"### {int(m['stageNumber']):02d}. {hist['battleKo']} — {hist.get('phaseKo','')}\n")
        add(f"ID `{m['id']}` · {TIER_NAMES[m['tier']]}-{m['level']} · 연도 {hist.get('year','')} · 적 지휘관 {hist.get('opponent',{}).get('nameKo','사건 보고')} · 캡처 맵명 **{m['title']}** · theme `{m['theme']}` / mode `{m['mode']}`.\n")
        add(f"난이도계수 d={number(m['difficulty'],4)}, 원래파상{m['totalWaves']}, 초기금화{m['initialGold']}, 정원{m['unitLimit']}, 경로{len(m['paths'])}개, 궁병진지{len(m.get('buildZones',[]))}개, 전선/지원점{len(m.get('tactics',{}).get('groundPosts',[]))}개. 거점: "+" / ".join(f"{o['id']}({o.get('label','')}) HP{o['hp']}" for o in m["objectives"])+".\n")
        add(f"학습: 새단어{len(lesson['newWords'])}, 복습예산{len(lesson.get('reviewIds',[]))}, 구조화문법{len(lesson.get('grammarSteps',[]))}, 해금시험{len(lesson['newWords'])+len(lesson.get('grammarSteps',[]))}문항. "+str(plans.get(m['id'],{}).get('goalKo',lesson.get('title','')))+"\n")
        add("플레이 임무: "+hist.get("playerGoalKo",hist.get("introKo",""))+"\n")
        if trait:
            add("작전: "+trait.get("nameKO","")+" — "+trait.get("descriptionKO","")+"\n")
            effects=[]
            for b in trait.get("unitBonuses",[]): effects.append("아군 "+NAMES.get(b.get("type"),b.get("type","all"))+" "+", ".join(f"{key}×{number(value)}" for key,value in b.items() if key!="type"))
            for b in trait.get("enemyBonuses",[]): effects.append("적 "+ENEMIES.get(b.get("kind"),b.get("kind","all"))+" "+", ".join(f"{key}×{number(value)}" for key,value in b.items() if key!="kind"))
            if trait.get("waveGold"): effects.append(f"{trait['waveGold'].get('every',1)}파상마다 추가금{trait['waveGold'].get('amount',0)}")
            if trait.get("reinforcements"): effects.append(f"{trait['reinforcements'].get('every',1)}파상마다 추가적 {trait['reinforcements'].get('kind','')} {trait['reinforcements'].get('count',1)}기(변환규칙적용)")
            if trait.get("cycleRoutes"): effects.append("출진경로파상별교대;river면bridge_index우선")
            add("정확한 작전 보정: "+(" / ".join(effects) if effects else "상시 아군/적 수치배율 없음; 아래 시간/위치 오라만")+".\n")
            if trait.get("auras"):
                add(table(["오라 중심(x,y)","반경","주기/활성초","효과"],[[f"({number(a['x'])},{number(a['y'])})",number(a.get('r',.1)),f"{a.get('period',20)}/{a.get('activeSeconds',a.get('period',20))}",", ".join(f"{k}×{number(v)}" for k,v in a.items() if k not in ('x','y','r','period','activeSeconds','phaseOffset'))] for a in trait["auras"]])+"\n")
        templates={(e['kind'],e['originKind'],e['sourceWave']):e for e in stage['enemyTemplates']}
        add("**원래 출처 웨이브별 적 HP** — 파생병/진지는 원형 열을 사용합니다. 장갑·거점피해·처치금·공격주기는4장의 공통표와 같고 이 맵의 적보너스는이미반영했습니다.\n")
        add(table(["s","일반 원형 HP","질주 원형 HP","방패 원형 HP","중갑 원형 HP","장수 HP","원형별 공격피해(일반/방패/중갑/장수)"],[[s,*[number(templates[k,k,s]['health']) for k in ['raider','runner','shield','heavy','commander']],"/".join(number(templates[k,k,s]['attackDamage']) for k in ['raider','shield','heavy','commander'])] for s in range(1,int(m['totalWaves'])+1)])+"\n")
        add("**원형별 기초 속도 범위**(s=1~원래마지막; 접근/교전배율 적용 전): "+" / ".join(f"{ORIGIN_CODES[k]} {span((templates[k,k,s]['baseMoveSpeed'] for s in range(1,int(m['totalWaves'])+1)),6)}" for k in ORIGIN_CODES)+".\n")
        add("**10분 실제 계획 편성** — 순서: 일반/질주/방패/중갑/장수/적궁/적총/적기마/적사무라이. ‘s범위’에는 원래 혼합된 개체 출처가 들어갑니다. 고정진지는적궁/적총열에포함됩니다.\n")
        add(table(["w","시간창초","s범위","초기 예정 총수","9종 편성","생존적상한","생성간격초","진지시도수","보급+작전금"],[[w['wave'],f"{number(w['startSeconds'],2)}~{number(w['endSeconds'],2)}",span(x['sourceWave'] for x in w['entries']),w['initialScheduledCount'],"/".join(str(w['composition'].get(k,0)) for k in ENEMY_ORDER),w['activeCap'],number(w['spawnInterval']),sum(x['fortificationRequested'] for x in w['entries']),f"{w['stipend']}+{w['traitSupply']}"] for w in stage['modes']['10']['waves']])+"\n")
        add("**이 맵에서 실제 계획에 있는 모든 적 병종/원형 변형** — 두 시간모드의 초기계획을 합친 최소~최대 HP/속도/공격피해입니다. 단일값은범위가아닙니다. 원형이 달라지는 진지는별도행입니다. 보충 병력도 같은수식으로생성됩니다.\n")
        variants=defaultdict(list)
        for mode in stage['modes'].values():
            for w in mode['waves']:
                for e in w['entries']: variants[e['kind'],e['originKind']].append(e)
        add(table(["적 표시 병종", "원형", "계획 s범위", "HP", "기초 속도", "장갑%", "한번 아군피해", "거점피해", "처치금"],[[ENEMIES[k],ORIGIN_CODES[o],span(e['sourceWave'] for e in es),span(e['health'] for e in es),span((e['baseMoveSpeed'] for e in es),6),span(100*e['armor'] for e in es),span(e['attackDamage'] for e in es),span(e['objectiveDamage'] for e in es),span(e['reward'] for e in es)] for (k,o),es in sorted(variants.items(),key=lambda pair:(ENEMY_ORDER.index(pair[0][0]),pair[0][1]))])+"\n")
        add("**10/20분의 후반 반복 구간** — 그 모드 마지막 시간창 기준입니다. 중간에 대형/난전과 진지/추가증원이 w조건으로바뀌므로동일종류만그대로복제되는것은아닙니다.\n")
        add(table(["모드","총파상","마지막plan의기준s","마지막초기예정수","최후생존상한","기본+작전보급총합","정답 보급금"],[[f"{minutes}분",stage['modes'][str(minutes)]['totalWaves'],stage['modes'][str(minutes)]['waves'][-1]['planSourceWave'],stage['modes'][str(minutes)]['waves'][-1]['initialScheduledCount'],stage['modes'][str(minutes)]['waves'][-1]['activeCap'],sum(w['stipend']+w['traitSupply'] for w in stage['modes'][str(minutes)]['waves']),0] for minutes in (10,20)])+"\n")
    add("## 6. 밸런스 검토안 — 목표: 살짝 깨기 어려움\n")
    add("### 6.1 현행 검토 기준\n\n전장 중 병사의 단계나 몸수를 변경하는 기능은 없습니다. 병영의 영구 훈련·배치·병종 조합·학습 지원을 기준으로 난이도를 평가해야 합니다. 이번 변경은 초기 스탯·영구 성장·기본 저지 수를 유지했으며 새 적 수치나 생산 시간을 조정하지 않았습니다.\n")
    add(table(["항목", "현재 규칙", "후속 검증"], [["창병 Lv5", "90금으로 독립2명, 정원2칸", "실전 손실과 다른 전진 병종의 채택률 비교"], ["승병 영구 Lv10", "기본13.416HP/초·기도40.248HP/대상", "유효 치료량·과다 치료·사거리 이탈 관찰"], ["전열", "기본 CAPACITY와 배치 capacityBonus", "자기 경로·유닛별 사상자·거점 피해 기록"], ["장시간 경제", "10/20분·1x/2x, 처치금·병렬 생산·학습 보상", "실제 소모금과 후반 병력 손실 측정"]])+"\n")
    add("### 6.2 이번 검증의 범위\n")
    growth_path=ROOT/"tests/profiles/unit-growth-scaling/removal-20261007/Godot/app_userdata/말의 전장/qa_unit_growth_scaling.json"
    growth=load(growth_path)
    verify(not growth["failures"], "Current permanent-growth runtime contracts pass")
    add(f"실제 Godot 수치 추출 {runtime['checks']:,}개 검사와 영구 성장 QA {growth['checks']:,}개 검사에서 실패0을 확인했습니다. QA는 실제 유료 생산·HP 피해와 회복·부적·처치 후 기도·마나·관통·스킬 해금·병영 프리뷰와 저장을 관찰합니다. 명시적 fixture의 자금/해금/위치를 사용하므로 캠페인 승률·미술·EXE 완료 근거는 아닙니다. 이전 임시 성장 규칙의 QA·자동 전술 승패는 현행 규칙의 승인 근거로 재사용하지 않습니다.\n")
    add("## 7. 다른 AI에게 전달할 검토 요청문\n\n> 현행 병영 영구 레벨 L과 원래 적 출처 웨이브 s, 실제 시간창 w를 구분해 검토해 주세요. 병종별 조합·창병 Lv5 90금2인·승병 치료·기본 저지 수·병렬 생산·학습 지원을 유지하고, 실제 승패와 사상자·유효 치료·거점 피해 근거로 평가해 주세요. 새 성장 기능이나 적 수치 변경을 임의로 적용하지 마십시오.\n")
    add("## 8. 코드 기준과 재현 자료\n")
    add(table(["코드/데이터", "담당 규칙", "SHA-256"],[[x["file"],{"game.gd":"전투/소환/적계산/금화","unit_growth.gd":"공통공격·HP·치료·피해감소성장","unit_skills.gd":"21스킬·치료·지원·상태","ground_combat.gd":"진군/호위/기습/접촉/저지","battle_duration.gd":"10/20분편성/상한/시간창","progress.gd":"영구훈련/군자금/맵해금/저장/SRS","units.json":"8병종기초/생산/스킬/진화","maps.json":"40맵난이도/HP/작전/배치지형","curriculum.json":"900단어/구조화문법/평가","learning_plans.json":"전장문장·위치지원미션"}.get(x["file"],"관련표시/기록/스토리"),x["sha256"]] for x in runtime['snapshot']['files']])+"\n")
    add("스냅샷 `tests/profiles/combat-growth-removal-20261007/source-snapshot/` / 실제런타임추출 `tests/profiles/combat-growth-removal-20261007/runtime_balance.json` / 추출기 `tests/export_balance_snapshot.gd` / 이문서생성기 `tools/write_balance_review.py`. 외부 AI 검토에는 이 Markdown 파일만 보내셔도 됩니다. 재계산/재현이 필요하면 프로젝트의 위 자료를 사용하십시오. 개인 진행 파일은 접근하지 않았습니다.\n")
    document = "\n".join(parts)
    verify(document.count("### ") >= 49, "Expected system and all stage sections emitted")
    verify(sum(f"### {i:02d}. " in document for i in range(1,41))==40, "All forty distinct stage detail sections emitted")
    verify(document.count("**원래 출처 웨이브별 적 HP**")==40, "Every stage has an exact source-wave HP table")
    verify(document.count("**10분 실제 계획 편성**")==40, "Every stage has actual timed-wave roster detail")
    verify("스킬은 영구 **3·5·8레벨**" in document, "Current and unapproved mechanics are distinguished")
    OUTPUT.write_text(document,encoding="utf-8",newline="\n")
    validation={"checks":len(checks),"failures":[],"runtimeChecks":runtime["checks"],"markdownBytes":OUTPUT.stat().st_size,"markdownSha256":hashlib.sha256(OUTPUT.read_bytes()).hexdigest(),"stageCount":40,"friendlyLevelRows":80,"standalone":True,"scope":"Independent raw enemy HP / deadlines / roster totals and standalone Markdown coverage; not an all-campaign victory proof."}
    (PROFILE/"document_checks.json").write_text(json.dumps(validation,ensure_ascii=False,indent=2),encoding="utf-8")
    print(json.dumps(validation,ensure_ascii=False))
    print(OUTPUT)


if __name__ == "__main__":
    main()
