extends SceneTree
## Data-only history regression guards. Official source contents are reviewed separately.
var checks: int = 0
var failures: Array[String] = []
var summaries: Array = []
const REQUIRED_TEXT: Array = ["stageId","battleEventId","battleKo","battleJP","chapterKo","phaseKo","introKo","outroKo","historyOutcomeKo","playerGoalKo","bridgeKo"]
const MODE_HINTS: Dictionary = {
	"ambush":["숲","갈림길","목교"],
	"multi-objective":["창고","군량"],
	"alleys":["골목","보급"],
	"bridges":["진입로","다리"],
	"landing":["부두","육지"],
	"escort":["수레"],
	"elevation":["높은","진지"],
	"weather":["느린","이동","고개","산길"],
	"visibility":["시야"],
	"siege":["방어선","교두보","성문"]
}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("STORY: " + message)

func has_one(text: String, candidates: Array) -> bool:
	for candidate in candidates:
		if text.contains(str(candidate)):
			return true
	return false

func official_host(url: String) -> bool:
	if not url.begins_with("https://"):
		return false
	var host: String = url.substr(8).get_slice("/",0).to_lower()
	return host.ends_with(".lg.jp") or host in ["www.nagoyajo.city.nagoya.jp","www.archives.go.jp","www.kumagaya-bunkazai.jp","www.city.nagoya.jp","www.info.city.tsu.mie.jp","www.city.uji.kyoto.jp","www.town.heguri.nara.jp","www.city.okayama.jp","www.town.oyamazaki.kyoto.jp","www.city.mishima.shizuoka.jp","www.city.izunokuni.shizuoka.jp","www.city.odawara.kanagawa.jp","www.pref.okayama.jp"]

func run() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://native/campaign_story.json"))
	var map_parsed = JSON.parse_string(FileAccess.get_file_as_string("res://native/maps.json"))
	check(parsed is Dictionary,"story is valid JSON")
	check(map_parsed is Array,"authored maps remain readable")
	if not parsed is Dictionary or not map_parsed is Array:
		write_result(0,0)
		return
	var data: Dictionary = parsed
	var maps: Array = map_parsed
	var stages: Array = data.get("stages",[])
	check(int(data.get("version",0)) >= 1,"schema version is present")
	check(stages.size()==40 and maps.size()==40,"all 40 authored stages have a story")
	if stages.size()!=40 or maps.size()!=40:
		write_result(stages.size(),0)
		return
	var hero: Dictionary = data.get("protagonist",{})
	check(not str(hero.get("nameKo","")).is_empty(),"one named player protagonist")
	check(str(hero.get("motifKo","")).contains("히데요시") and str(hero.get("motifKo","")).contains("가상"),"historical inspiration is explicitly fictional")
	check(str(data.get("adaptationKo","")).contains("지형") and str(data.get("adaptationKo","")).contains("기상") and str(data.get("adaptationKo","")).contains("각색"),"fictional missions and map weather are distinguished from history")
	check(str(data.get("yearBasisKo","")).contains("연호"),"year convention is explicit")
	var reading: RegEx = RegEx.new()
	check(reading.compile("^[ぁ-ゖー・ ]+$")==OK,"name-reading validator compiles")
	var ids: Dictionary = {}
	var event_phases: Dictionary = {}
	var event_stages: Dictionary = {}
	var chapters: Dictionary = {}
	var unique_text: Dictionary = {"introKo":{},"outroKo":{},"playerGoalKo":{}}
	var previous_year: int = 0
	var source_urls: Dictionary = {}
	for index in range(stages.size()):
		var stage: Dictionary = stages[index]
		var label: String = "stage " + str(index+1)
		check(int(stage.get("stageNumber",0))==index+1,label+" number follows authored order")
		check(str(stage.get("stageId",""))==str(maps[index].id),label+" binds its original unique geometry ID")
		check(not ids.has(str(stage.stageId)),label+" ID is unique")
		ids[str(stage.stageId)] = true
		var year: int = int(stage.get("year",0))
		check(year>=1560 and year<=1590 and year>=previous_year,label+" years never run backward")
		previous_year=year
		for key in REQUIRED_TEXT:
			var text: String = str(stage.get(key,""))
			check(not text.strip_edges().is_empty(),label+" provides "+key)
			check(not text.contains("TODO") and not text.contains("??"),label+" has no unfinished "+key)
		check(str(stage.introKo).length()<=240 and str(stage.outroKo).length()<=240,label+" briefing/result stay concise")
		check((str(stage.introKo)+str(stage.outroKo)).contains(str(hero.nameKo)),label+" keeps the same named protagonist")
		for key in unique_text:
			check(not unique_text[key].has(str(stage[key])),label+" "+key+" is authored individually")
			unique_text[key][str(stage[key])]=true
		var next_id: String = str(stages[index+1].stageId) if index<39 else ""
		check(str(stage.get("nextStageId",""))==next_id,label+" leads to the next real stage")
		var event_id: String = str(stage.battleEventId)
		var phase_key: String = event_id+"|"+str(stage.phaseKo)
		check(not event_phases.has(phase_key),label+" repeated events have distinct phases")
		event_phases[phase_key]=true
		if not event_stages.has(event_id):
			event_stages[event_id]=[]
		event_stages[event_id].append(index+1)
		var chapter: String = str(stage.chapterKo)
		chapters[chapter] = int(chapters.get(chapter,0))+1
		if index%10>0:
			check(chapter==str(stages[index-1].chapterKo),label+" stays inside its ten-stage growth chapter")
		elif index>0:
			check(chapter!=str(stages[index-1].chapterKo),label+" starts the next growth chapter")
		var opponent: Dictionary = stage.get("opponent",{})
		for key in ["nameKo","nameJP","reading"]:
			check(not str(opponent.get(key,"")).is_empty(),label+" opponent supplies "+key)
		check(reading.search(str(opponent.get("reading","")))!=null,label+" opponent reading is hiragana")
		var sources: Array = stage.get("sources",[])
		check(not sources.is_empty(),label+" names a primary source")
		for url in sources:
			check(official_host(str(url)),label+" references a verified public historical institution")
			source_urls[str(url)]=true
		check(has_one(str(stage.playerGoalKo),MODE_HINTS.get(str(maps[index].mode),[])),label+" mission reflects the original map mechanic")
		check(not stage.has("paths") and not stage.has("buildZones") and not stage.has("objectives"),label+" story contains no replacement map geometry")
		summaries.append({"number":index+1,"stageId":stage.stageId,"year":year,"battle":stage.battleKo,"eventId":event_id,"phase":stage.phaseKo,"sources":sources.size()})
	check(chapters.size()==4,"four growth chapters")
	for chapter in chapters:
		check(int(chapters[chapter])==10,"each chapter contains ten distinct stages")
	check(event_stages.size()==35,"35 real events are expanded into 40 explicit battle phases")
	for pair in [[7,8],[16,17],[21,23],[26,28],[31,32]]:
		check(str(stages[pair[0]-1].battleEventId)==str(stages[pair[1]-1].battleEventId),"documented paired phases "+str(pair)+" share event identity")
		check(str(stages[pair[0]-1].phaseKo)!=str(stages[pair[1]-1].phaseKo),"paired phases "+str(pair)+" have separate mission labels")
	check(int(stages[0].year)==1560 and int(stages[39].year)==1590,"campaign starts in 1560 and ends in 1590")
	for number in [1,8,11,19,32,35]:
		check(has_one(str(stages[number-1].playerGoalKo),["철수","패주","귀환"]), "historical setback "+str(number)+" succeeds by preserving the army")
	check(str(stages[3].historyOutcomeKo).contains("버리고"),"Kannonji is abandoned rather than a fabricated frontal capture")
	check(str(stages[5].historyOutcomeKo).contains("화의"),"Okawachi ends through agreement")
	check(str(stages[21].historyOutcomeKo).contains("떠났고"),"Murashige leaves before Arioka falls")
	var news: Dictionary = stages[26]
	check(news.get("opponentOnField",true)==false,"Mitsuhide is not teleported to Takamatsu")
	check(str(news.introKo).contains("같은 전선") and str(news.playerGoalKo).contains("다카마쓰"),"Honnoji news is received at the same Takamatsu front")
	check(str(stages[27].introKo).contains("다카마쓰") or str(stages[27].introKo).contains("현지"),"following peace mission remains at Takamatsu")
	check(str(stages[28].introKo).contains("회군"),"Yamazaki is reached after a stated return march")
	check(str(stages[30].bridgeKo).contains("정치"),"Ieyasu's change from ally to opponent is explained")
	check(str(stages[31].historyOutcomeKo).contains("이에야스 측의 승리") and str(stages[31].outroKo).contains("노부카쓰"),"Nagakute defeat and later Nobukatsu agreement are distinguished")
	check(str(stages[34].introKo).contains("시코쿠 화의 뒤 아군"),"Chosokabe's move from opponent to expedition ally is explained")
	check(str(stages[35].bridgeKo).contains("1588") and str(stages[35].bridgeKo).contains("1590"),"three-year gap has an explicit rebuilding bridge")
	check(str(stages[37].introKo).contains("화의한 노부카쓰"),"former opponent Nobukatsu's new campaign alignment is explained")
	var oshi: Dictionary = stages[38]
	check(str(oshi.outroKo).contains("함락되지"),"Oshi remains unresolved before Odawara")
	check(str(oshi.historyOutcomeKo).contains("오다와라가 항복한 뒤"),"Oshi opening follows rather than precedes Odawara")
	check(str(stages[39].outroKo).contains("이후 오시성"),"final result completes Oshi in historical order")
	check(str(stages[39].opponent.nameJP)=="北条氏政・氏直","final opponent is the Odawara Hojo leadership")
	var ending: Dictionary = data.get("ending",{})
	check(not str(ending.get("titleKo","")).is_empty() and str(ending.get("textKo","")).contains("전국 통일"),"campaign has its requested unification ending")
	check(str(ending.get("textKo","")).contains("1590") and str(ending.get("textKo","")).contains("도호쿠"),"ending carries the final historical consolidation bridge")
	check(JSON.parse_string(JSON.stringify(data))==data,"full Unicode story survives JSON serialization")
	write_result(stages.size(),event_stages.size(),source_urls.size())

func write_result(stage_count: int, event_count: int, source_count: int = 0) -> void:
	var result: Dictionary = {"checks":checks,"failures":failures,"stageCount":stage_count,"eventCount":event_count,"uniqueSourceCount":source_count,"stages":summaries,"scope":"Data-only CPU verification of 40 authored map IDs, chronological story links, source references, distinct phases, history setback guards, Honnoji locality, Oshi/Odawara order. Does not automate source credibility or GPU/UI rendering."}
	var file: FileAccess = FileAccess.open("res://tests/qa_campaign_story.json",FileAccess.WRITE)
	if file!=null:
		file.store_string(JSON.stringify(result,"  "))
	print("STORY_QA "+JSON.stringify({"checks":checks,"failures":failures.size(),"stages":stage_count,"events":event_count,"sources":source_count}))
	quit(0 if failures.is_empty() else 1)
