# 말의 전장

전국시대 전장을 배경으로 일본어를 학습하는 PC용 오프라인 타워 디펜스입니다. 현재 실행 기준은 Godot 4.7.2의 `project.godot`과 `native/main.tscn`입니다.

## 현재 작업 상태

- 역사·지역·계절을 반영한 새 전장 이미지 40개를 등록했습니다. 전장별 실제 화면 검토는 진행 중이며, 등록 완료와 검토 완료를 구분합니다.
- 합성과 전투 중 병사 강화를 제거했습니다. 영구 훈련과 3·5·8레벨 스킬은 병영 성장을 사용합니다.
- 상단바를 두 줄로 정리하고, 전장 글자는 배경판 없이 밝은 색과 외곽선으로 표시합니다.
- 외부 웹 GPT‑6 Pro 검토 후 첫 수치 후보인 **1전장 적 체력 5% 감소**를 적용했습니다. 이동속도·장갑·거점 피해·정원·경제·후속 전장은 유지합니다. 조정 상수는 `native/game.gd`의 `FIRST_STAGE_ENEMY_HP_FACTOR`입니다. 자동 정책의 패배를 사람이 깰 수 없다는 증거로 사용하지 않습니다.
- 실행파일·설치파일 재생성은 사용자 요청으로 보류 중입니다. 기존 PC 실행파일은 최신 소스를 반영하지 않은 이전 빌드입니다.

## 소스 실행

공식 Godot 4.7.2 Windows 엔진을 `tools/godot/Godot_v4.7.2-stable_win64.exe`에 준비한 뒤 `Play.cmd`로 게임을, `Edit.cmd`로 편집기를 실행합니다. 이미 집 PC에 준비한 엔진을 그대로 사용하며 실행기는 엔진을 내려받거나 설치하지 않습니다. 다른 위치의 엔진은 `tools/run.ps1 -GodotPath`로 지정할 수 있습니다.

실행기는 현재 체크아웃 위치를 기준으로 경로를 계산하므로 공백·한글이 있는 폴더에서도 사용할 수 있습니다. 게임 저장은 `.local/player`, 편집기 저장은 `.local/editor` 아래에 유지하며 기존 시스템 AppData는 덮어쓰지 않습니다. 이전 AppData 저장은 자동 이동하지 않습니다. QA는 항상 `tests/profiles/<이름>/run-<고유값>`의 새 격리 폴더를 사용합니다. 이 폴더들과 엔진·캐시·배포 파일은 Git에 포함하지 않습니다.

새 PC에서 `Play.cmd`·`Edit.cmd`를 처음 실행하면 캐시가 없는 경우 원본 자산을 자동으로 가져옵니다. 가져오기가 실패하면 게임을 시작하지 않고 오류를 전달합니다. 수동 자산 가져오기와 검증은 Windows PowerShell에서 프로젝트 루트 기준으로 실행합니다. 콘텐츠 검사의 `node` 명령에는 Node.js가 필요하며 실행기는 이를 설치하지 않습니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 -Mode Import -Headless
node tests/qa_content.mjs
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 -Mode Qa -Script tests/qa_app.gd -Headless
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 -Mode Qa -Script tests/qa_portable_paths.gd -Headless
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run.ps1 -Mode Qa -Script tests/qa_first_stage_hp_patch.gd -ProfileName first-stage-hp-patch -Headless
```

QA는 정상 종료·오류·시간 초과를 종료 코드로 구분하고, 결과와 로그 위치를 출력합니다. 시간 초과는 124이며 실행기가 시작한 프로세스와 그 자식만 종료합니다. Windows가 종료를 거부하더라도 대기를 끝내고 프로세스 ID와 `terminationFailed`를 결과에 기록합니다. 자산 가져오기는 기본 600초, 일반 QA는 180초 제한입니다. 예전 도면의 `export_map_render_blueprints.gd`는 별도로 보관한 당시 소스 스냅샷을 요구하는 제작 도구이며 기본 게임 실행 검사가 아닙니다.

PC 간 갱신은 `git status`를 확인한 뒤 변경이 없는 상태에서 `git pull --ff-only`를 사용합니다. 집 PC 인계 과정에서 만든 README·실행 스크립트가 남아 있으면 `git stash push --include-untracked -m "home-before-update"`로 보관한 뒤 받습니다. 새 실행기를 확인하기 전 옛 실행 스크립트를 다시 덮어쓰지 마십시오. Godot 자동 생성 파일은 실제 변경을 확인해 판단하고, 캐시나 개인 저장 데이터를 커밋하지 않습니다.

`src/`, `index.html`, `server.mjs`는 기존 웹 프로토타입이며, 현재 네이티브 게임의 실행 기준과 구분합니다.

## 검토 자료

- [유닛·경제·40개 전장 밸런스 명세](GAME_BALANCE_REVIEW.md)
- [역사·지역·날씨 및 전장 제작 근거](BATTLEFIELD_HISTORY_WEATHER_PLAN.md)
- 새 전장 등록과 검토 상태: `assets/battlefields-rendered/manifest.json`

음악·음성·폰트·모델의 출처와 이용 조건은 해당 자산 폴더의 라이선스 및 출처 자료를 따릅니다.
