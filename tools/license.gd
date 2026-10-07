extends SceneTree

func _initialize() -> void:
	var file = FileAccess.open("res://dist/ThirdParty.txt",FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string("Kotoba Sengoku / 말의 전장\n\nOriginal game code and generated artwork, 2026.\n\nSTAGE MUSIC CREDITS\n40 stages each use a distinct musical work.\n\n")
	var library: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://native/music.json"))
	file.store_string("Source terms checked: %s\nTerms: %s\n\n" % [str(library.get("checkedDate","")),str(library.get("termsUrl",""))])
	for track in library.get("tracks",[]):
		file.store_string("Stage: %s\nMusic: %s\nAuthor: %s\nPublished: %s\nLicense: %s\nLicense URL: %s\nSource: %s\nTerms: %s\nChanges: %s\n" % [str(track.stageId),str(track.title),str(track.author),str(track.get("published","")),str(track.license),str(track.licenseUrl),str(track.source),str(track.get("termsUrl",library.get("termsUrl",""))),str(track.get("changes","Author-provided audio; in-game volume adjusted and playback repeated."))])
		if track.has("creditText"):
			file.store_string(str(track.creditText) + "\n")
		if track.has("usageConditions"):
			file.store_string("Usage conditions: " + str(track.usageConditions) + "\n")
		file.store_string("\n")
	var sfx_path = "res://native/sfx_sources.json"
	if FileAccess.file_exists(sfx_path):
		var sfx = JSON.parse_string(FileAccess.get_file_as_string(sfx_path))
		if sfx is Dictionary:
			file.store_string("\nBATTLE SOUND EFFECTS\nSource/license checked: %s\n" % str(sfx.get("checkedDate","")))
			file.store_string(str(sfx.get("mastering","")) + "\n\n")
			for source in sfx.get("sources",[]):
				file.store_string("Title: %s\nAuthor: %s\nSource: %s\nLicense: %s\nLicense URL: %s\n" % [str(source.title),str(source.author),str(source.source),str(source.license),str(source.get("licenseUrl",""))])
				if source.has("copyright"):
					file.store_string(str(source.copyright) + "\n")
				if source.has("licenseNote"):
					file.store_string(str(source.licenseNote) + "\n")
				file.store_string("\n")
			for clip in sfx.get("clips",[]):
				file.store_string("Effect: %s\nOriginal files: %s\nSources: %s\nChanges: %s\n\n" % [str(clip.id),str(clip.get("originalFiles",[])),str(clip.get("sourceIds",[])),str(clip.get("changes",""))])
			for notice_path in sfx.get("licenseFiles",[]):
				if FileAccess.file_exists(str(notice_path)):
					file.store_string("\nSound-effect license/notice: %s\n" % str(notice_path))
					file.store_string(FileAccess.get_file_as_string(str(notice_path)) + "\n")
	var narration_path = "res://assets/narration/manifest.json"
	if FileAccess.file_exists(narration_path):
		var narration = JSON.parse_string(FileAccess.get_file_as_string(narration_path))
		if narration is Dictionary:
			file.store_string("\nJAPANESE BATTLE NARRATION\nVoice actor: %s\nSource/license checked: %s\nCredit: %s\n\n" % [str(narration.get("voiceActor","")),str(narration.get("checkedDate","")),str(narration.get("credit",""))])
			for source in narration.get("sources",[]):
				file.store_string("Title: %s\nAuthor: %s\nSource: %s\nLicense: %s\nLicense URL: %s\nChanges: %s\n\n" % [str(source.get("title","")),str(source.get("author","")),str(source.get("sourceUrl","")),str(source.get("license","")),str(source.get("licenseUrl","")),str(source.get("modifications",""))])
			for clip in narration.get("clips",[]):
				file.store_string("Narration: %s\nFile: %s\nOriginal: %s\n\n" % [str(clip.get("id","")),str(clip.get("path","")),str(clip.get("originalFile",""))])
			for notice_path in narration.get("licenseFiles",[]):
				if FileAccess.file_exists(str(notice_path)):
					file.store_string("Narration license/notice: %s\n%s\n\n" % [str(notice_path),FileAccess.get_file_as_string(str(notice_path))])
	var announcements_path = "res://assets/announcements/manifest.json"
	if FileAccess.file_exists(announcements_path):
		var announcements = JSON.parse_string(FileAccess.get_file_as_string(announcements_path))
		if announcements is Dictionary:
			file.store_string("\nJAPANESE FEMALE NOTIFICATION VOICE\nVoice asset provider: %s\nSource/license checked: %s\nCredit: %s\n\n" % [str(announcements.get("voiceActor","")),str(announcements.get("checkedDate","")),str(announcements.get("credit",""))])
			for source in announcements.get("sources",[]):
				file.store_string("Title: %s\nAuthor: %s\nSource: %s\nLicense: %s\nLicense URL: %s\nChanges: %s\n\n" % [str(source.get("title","")),str(source.get("author","")),str(source.get("sourceUrl","")),str(source.get("license","")),str(source.get("licenseUrl","")),str(source.get("modifications",""))])
			for clip in announcements.get("clips",[]):
				file.store_string("Notification: %s\nFile: %s\nOriginal: %s\n\n" % [str(clip.get("id","")),str(clip.get("path","")),str(clip.get("originalFile",""))])
			for notice_path in announcements.get("licenseFiles",[]):
				if FileAccess.file_exists(str(notice_path)):
					file.store_string("Notification license/notice: %s\n%s\n\n" % [str(notice_path),FileAccess.get_file_as_string(str(notice_path))])
	var portraits_path = "res://assets/commanders/manifest.json"
	if FileAccess.file_exists(portraits_path):
		var portraits = JSON.parse_string(FileAccess.get_file_as_string(portraits_path))
		if portraits is Dictionary:
			file.store_string("\nHISTORICAL COMMANDER PORTRAITS\nStatic 2D derivatives of historical portraits/illustrations. Source files are retained unchanged in the project.\n\n")
			for portrait in portraits.get("portraits",[]):
				file.store_string("Commander: %s\nArtwork: %s\nArtist: %s\nSource: %s\nCredit: %s\nLicense: %s\nLicense URL: %s\nChanges: %s\n\n" % [str(portrait.heroId),str(portrait.sourceTitle),str(portrait.artist),str(portrait.sourcePage),str(portrait.credit),str(portrait.license),str(portrait.licenseUrl),str(portrait.processing)])
	if FileAccess.file_exists("res://assets/ui/barracks-warroom.png"):
		file.store_string("Japanese painted headquarters backdrop and lacquer/washi UI materials: original project artwork created with OpenAI built-in image generation, 2026.\n\n")
	if FileAccess.file_exists("res://assets/battlefields-rendered/manifest.json"):
		file.store_string("Sengoku battlefield terrain renders: original project artwork created using OpenAI built-in image generation, 2026. Individual images follow authored historical terrain relations and distinct gameplay-layout blueprints; they are game interpretations rather than surveyed reconstructions. Runtime terrain heights, path navigation, placement and unit shadows remain physical. Provenance: assets/battlefields-rendered/manifest.json.\n\n")
	var lobby_path = "res://assets/music/lobby/manifest.json"
	if FileAccess.file_exists(lobby_path):
		var lobby = JSON.parse_string(FileAccess.get_file_as_string(lobby_path))
		if lobby is Dictionary:
			file.store_string("\nLOBBY MUSIC\nTitle: %s\nAuthor: %s\nSource: %s\nLicense: %s\nLicense URL: %s\nCredit: %s\nChanges: %s\n\n" % [str(lobby.get("title","")),str(lobby.get("author","")),str(lobby.get("source","")),str(lobby.get("license","")),str(lobby.get("licenseUrl","")),str(lobby.get("creditText","")),str(lobby.get("changes","Original audio; runtime gain and loop playback."))])
	var materials_path = "res://native/material_sources.json"
	var atlas_path = "res://assets/atlas/coastline-manifest.json"
	if FileAccess.file_exists(atlas_path):
		var atlas = JSON.parse_string(FileAccess.get_file_as_string(atlas_path))
		if atlas is Dictionary:
			file.store_string("\nVECTOR JAPAN CAMPAIGN COASTLINE\nDataset: %s\nVersion: %s\nAuthor: Natural Earth\nSource: %s\nLicense: %s\nTerms: %s\nChanges: %s\n\n" % [str(atlas.get("dataset","")),str(atlas.get("datasetVersion","")),str(atlas.get("sourceURL","")),str(atlas.get("license","Public Domain")),str(atlas.get("licenseURL","")),str(atlas.get("modificationKo",""))])
	if FileAccess.file_exists("res://native/campaign_geography.json"):
		var geography = JSON.parse_string(FileAccess.get_file_as_string("res://native/campaign_geography.json"))
		if geography is Dictionary:
			file.store_string("\nHISTORICAL CAMPAIGN LOCATION DATA\n")
			for source in geography.get("dataCredits",[]):
				file.store_string("Title: %s\nSource: %s\nCredit: %s\nLicense: %s\nChanges: %s\n\n" % [str(source.get("title","")),str(source.get("url","")),str(source.get("credit","")),str(source.get("license","")),str(source.get("modifiedKo",""))])
	if FileAccess.file_exists(materials_path):
		var materials = JSON.parse_string(FileAccess.get_file_as_string(materials_path))
		if materials is Dictionary:
			file.store_string("\n3D MATERIAL TEXTURES\n")
			for material in materials.get("materials",[]):
				file.store_string("Material: %s\nSource: %s\nLicense: %s\nLicense URL: %s\nUse: %s\n\n" % [str(material.id),str(material.source),str(material.license),str(material.licenseUrl),str(material.get("use",""))])
	if FileAccess.file_exists("res://assets/materials/sengoku/surface-atlas-v1.png"):
		file.store_string("Project-generated Sengoku material atlas (iron, hemp, leather, skin): created using OpenAI built-in image generation, 2026. Surface colour detail only; Poly Haven normal/roughness maps remain in use.\n\n")
	if FileAccess.file_exists("res://assets/units-standing/support.json"):
		var standing = JSON.parse_string(FileAccess.get_file_as_string("res://assets/units-standing/support.json"))
		if standing is Dictionary:
			file.store_string("Authored raster standing-portrait idle frames: original project-generated core unit sheets and newly generated support poses, 2026. Support generator: %s; provenance: assets/units-standing/support-prompt.json.\n\n" % str(standing.get("generator","built-in image_gen")))
	for scanned_path in ["res://assets/materials/terrain/manifest.json","res://assets/models/battlefield/manifest.json"]:
		if not FileAccess.file_exists(scanned_path): continue
		var scanned=JSON.parse_string(FileAccess.get_file_as_string(scanned_path))
		if not scanned is Dictionary: continue
		file.store_string("\nNATIVE BATTLEFIELD PBR SURFACES AND NATURAL MODELS\n")
		for material in scanned.get("materials",scanned.get("models",[])):
			file.store_string("Asset: %s\nSource: %s\nAuthor: Poly Haven contributors\nLicense: %s\nTerms: %s\nChanges: Runtime terrain materials, mesh LOD and instancing; author-provided textures retained.\n\n" % [str(material.get("id",material.get("path",""))),str(material.get("source","")),str(material.get("license","CC0")),str(material.get("licenseUrl","https://polyhaven.com/license"))])
	if FileAccess.file_exists("res://assets/learning-voice/NOTICE.txt"):
		file.store_string("\nOFFLINE JAPANESE LEARNING AND MISSION BRIEFING\n")
		file.store_string(FileAccess.get_file_as_string("res://assets/learning-voice/NOTICE.txt")+"\n\n")
	if FileAccess.file_exists("res://assets/materials/terrain/pine-canopy-atlas-v1.png"):
		file.store_string("Native battlefield pine canopy atlas: original project artwork created with OpenAI built-in image generation, 2026. Transparent crown images are mapped to physical, shadow-casting 3D foliage. Provenance: assets/materials/terrain/pine-canopy-atlas-v1.metadata.json.\n\n")
	file.store_string("Fonts: Nanum Myeongjo Bold/ExtraBold, Yuji Syuku Regular, Klee One SemiBold, Noto Sans CJK JP Regular and Noto Serif CJK JP Medium. SIL Open Font License 1.1.\n\n")
	for font_notice in ["OFL.txt","OFL-NotoSerifCJK.txt","OFL-NanumMyeongjo.txt","OFL-YujiSyuku.txt","OFL-KleeOne.txt"]:
		var notice_path: String="res://assets/fonts/"+font_notice
		if FileAccess.file_exists(notice_path):
			file.store_string("Font license: "+font_notice+"\n"+FileAccess.get_file_as_string(notice_path)+"\n\n")
	file.store_string("Godot Engine:\n")
	file.store_string(Engine.get_license_text())
	file.store_string("\n\nThird-party notices from Godot Engine:\n")
	file.store_string(JSON.stringify(Engine.get_copyright_info(),"  "))
	file.store_string("\n\nThird-party license texts:\n")
	file.store_string(JSON.stringify(Engine.get_license_info(),"  "))
	file.close()
	quit(0)
