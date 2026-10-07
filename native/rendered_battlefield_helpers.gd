extends RefCounted
## Manifest-backed artwork changes presentation, never the authored movement
## or terrain data. Missing or stale art remains a development fallback.

const MANIFEST_PATH: String = "res://assets/battlefields-rendered/manifest.json"
const MAPS_PATH: String = "res://native/maps.json"
const EXPECTED_STAGE_COUNT: int = 40
static var manifest_cache: Dictionary = {}
static var hash_cache: Dictionary = {}

static func release_shared_resources() -> void:
	manifest_cache.clear()
	hash_cache.clear()

static func _source_hash(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var source: FileAccess = FileAccess.open(path,FileAccess.READ)
	if source == null:
		return ""
	var length: int = source.get_length()
	source.close()
	var signature: String = str(FileAccess.get_modified_time(path))+":"+str(length)
	var previous: Dictionary = hash_cache.get(path,{})
	if str(previous.get("signature","")) == signature:
		return str(previous.get("hash",""))
	var value: String = FileAccess.get_sha256(path)
	hash_cache[path] = {"signature":signature,"hash":value}
	return value

static func _read_manifest(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"valid":false,"reason":"manifest_missing","stages":[],"camera":{}}
	var text_value: String = FileAccess.get_file_as_string(path)
	var signature: String = text_value.sha256_text()
	var previous: Dictionary = manifest_cache.get(path,{})
	if str(previous.get("signature","")) == signature:
		return previous
	var parsed: Variant = JSON.parse_string(text_value)
	if not parsed is Dictionary or not parsed.get("stages",null) is Array:
		return {"valid":false,"reason":"manifest_invalid","stages":[],"camera":{}}
	var result: Dictionary = parsed.duplicate(true)
	result["signature"] = signature
	result["valid"] = int(result.get("version",0)) == 1
	result["reason"] = "" if bool(result.valid) else "manifest_version_unsupported"
	manifest_cache[path] = result
	return result

static func _data_hash(record: Dictionary) -> String:
	return str(record.get("sourceDataSha256",record.get("sourceMapsSha256","")))

static func _entry_status(entry: Dictionary,manifest: Dictionary,current_hash: String) -> Dictionary:
	var path: String = str(entry.get("path",""))
	var expected_hash: String = str(entry.get("sha256",""))
	if not path.begins_with("res://") or path.is_empty():
		return {"valid":false,"reason":"art_path_invalid"}
	if not FileAccess.file_exists(path) and not ResourceLoader.exists(path):
		return {"valid":false,"reason":"art_missing"}
	var claimed_data_hash: String = _data_hash(entry)
	if claimed_data_hash.is_empty():
		claimed_data_hash = _data_hash(manifest)
	if not claimed_data_hash.is_empty() and claimed_data_hash != current_hash:
		return {"valid":false,"reason":"source_data_changed"}
	if expected_hash.length() != 64:
		return {"valid":false,"reason":"art_hash_missing"}
	# Source files exist during development. In an exported PCK, the importer
	# may replace the PNG with a remapped resource; its approved hash is recorded.
	var actual_hash: String = _source_hash(path)
	if not actual_hash.is_empty() and actual_hash != expected_hash:
		return {"valid":false,"reason":"art_hash_mismatch"}
	return {"valid":true,"reason":"","sourceDataVerified":not claimed_data_hash.is_empty(),"rawArtHashVerified":not actual_hash.is_empty()}

static func resolve(stage: Dictionary,physical_fingerprint: String,manifest_path: String = MANIFEST_PATH,legacy_preview: bool = false) -> Dictionary:
	var manifest: Dictionary = _read_manifest(manifest_path)
	var current_data_hash: String = _source_hash(MAPS_PATH)
	var result: Dictionary = {"mode":"native","artPath":"","lighting":{},"normalizedBounds":Vector4(0,0,1,1),"distributionReady":false,"coverage":0,"expectedStageCount":EXPECTED_STAGE_COUNT,"manifestPath":manifest_path,"sourceDataSha256":current_data_hash,"reason":str(manifest.get("reason","")),"sourceDataVerified":false,"rawArtHashVerified":false,"sourceProjection":manifest.get("camera",{})}
	var selected: Dictionary = {}
	var seen: Dictionary = {}
	var seen_art_hashes: Dictionary = {}
	var all_verified: bool = true
	if bool(manifest.get("valid",false)):
		for value in manifest.get("stages",[]):
			if not value is Dictionary:
				all_verified = false
				continue
			var id: String = str(value.get("stageId",""))
			var status: Dictionary = _entry_status(value,manifest,current_data_hash)
			if id.is_empty() or seen.has(id):
				all_verified = false
				continue
			seen[id] = bool(status.valid)
			if bool(status.valid):
				result.coverage += 1
				all_verified = all_verified and bool(status.get("sourceDataVerified",false))
				var art_hash: String = str(value.get("sha256",""))
				if seen_art_hashes.has(art_hash):
					all_verified = false
				seen_art_hashes[art_hash] = true
			else:
				all_verified = false
			if id == str(stage.get("id","")):
				if bool(status.valid):
					selected = value.duplicate(true)
					result.sourceDataVerified = bool(status.get("sourceDataVerified",false))
					result.rawArtHashVerified = bool(status.get("rawArtHashVerified",false))
				else:
					result.reason = str(status.reason)
		# An exact 40-ID match prevents a manifest containing 40 unrelated or
		# repeated entries from being mistaken for a distributable campaign.
		var authored: Variant = JSON.parse_string(FileAccess.get_file_as_string(MAPS_PATH))
		var complete_ids: bool = authored is Array and authored.size() == EXPECTED_STAGE_COUNT and seen.size() == EXPECTED_STAGE_COUNT
		if authored is Array:
			for config in authored:
				if not config is Dictionary or not bool(seen.get(str(config.get("id","")),false)):
					complete_ids = false
		result.distributionReady = result.coverage == EXPECTED_STAGE_COUNT and complete_ids and all_verified
	if not selected.is_empty():
		var expected_geometry: String = str(selected.get("sourceGeometryFingerprint",""))
		if not expected_geometry.is_empty() and expected_geometry != physical_fingerprint:
			result.reason = "source_geometry_changed"
			result.distributionReady = false
		else:
			result.mode = "rendered"
			result.artPath = str(selected.path)
			result.artSha256 = str(selected.sha256)
			result.lighting = selected.get("lighting",{}).duplicate(true)
			result.reason = ""
			var bounds: Variant = selected.get("normalizedBounds",[0,0,1,1])
			if bounds is Array and bounds.size() == 4:
				result.normalizedBounds = Vector4(float(bounds[0]),float(bounds[1]),maxf(.001,float(bounds[2])),maxf(.001,float(bounds[3])))
			elif bounds is Dictionary:
				result.normalizedBounds = Vector4(float(bounds.get("x",0)),float(bounds.get("y",0)),maxf(.001,float(bounds.get("w",1))),maxf(.001,float(bounds.get("h",1))))
	if str(result.mode) == "native" and legacy_preview:
		var legacy_path: String = str(stage.get("background",""))
		if FileAccess.file_exists(legacy_path) or ResourceLoader.exists(legacy_path):
			result.mode = "legacy_preview"
			result.artPath = legacy_path
			result.artSha256 = _source_hash(legacy_path)
			result.distributionReady = false
			result.reason = "legacy_preview_not_historical_release_art"
	return result
