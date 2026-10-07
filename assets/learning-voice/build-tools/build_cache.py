"""Offline curriculum speech cache builder; standard library + official C API.

`--inventory` only reads authored content. Synthesis requires downloaded tools
and an explicit approved-terms marker; it never fetches or accepts any license.
"""
from __future__ import annotations
import argparse
import array
import ctypes as C
import hashlib
import io
import json
import math
import os
from pathlib import Path
import time
import wave

ROOT = Path(__file__).resolve().parents[3]
VOICE = ROOT / "assets/learning-voice"
BUILD = VOICE / "build-tools"
RUNTIME = BUILD / "runtime"
STYLE = 10005  # Official Nemo normal female1; no voice imitation or pitch shift.
BRIEFING_STYLE = 10001  # Official Nemo male1; original neutral pitch, not a cloned actor.

def key(text):
    return hashlib.sha256(text.strip().encode("utf-8")).hexdigest()

def inventory():
    items = {}
    conflicts = []
    word_ids = []
    def visit(value, source):
        if isinstance(value, dict):
            text = value.get("jp")
            if isinstance(text, str) and text.strip():
                text = text.strip()
                reading = str(value.get("reading", text)).strip() or text
                item = {"text": text, "reading": reading, "sources": [source], "voiceType": "learning", "styleId": STYLE}
                if text not in items:
                    items[text] = item
                else:
                    if source not in items[text]["sources"]:
                        items[text]["sources"].append(source)
                    if items[text]["reading"] != reading:
                        conflicts.append({"text": text, "kept": items[text]["reading"], "alternative": reading, "source": source})
            for name, child in value.items():
                visit(child, source+"/"+name)
        elif isinstance(value, list):
            for n, child in enumerate(value):
                visit(child, source+"/"+str(n))
    curriculum = json.loads((ROOT / "native/curriculum.json").read_text(encoding="utf-8-sig"))
    for tier, lessons in curriculum.items():
        if not isinstance(lessons, list): continue
        for lesson in lessons:
            word_ids.extend(str(word["id"]) for word in lesson.get("newWords", []))
    for path in ["native/curriculum.json", "native/learning_plans.json", "native/units.json"]:
        visit(json.loads((ROOT/path).read_text(encoding="utf-8-sig")), path)
    learning_count = len(items)
    story_path = ROOT/"native/campaign_story.json"
    briefing_stages = []
    if story_path.is_file():
        story = json.loads(story_path.read_text(encoding="utf-8-sig"))
        for stage in story.get("stages", []):
            text = str(stage.get("briefingJP", "")).strip()
            reading = str(stage.get("briefingReading", "")).strip()
            ko = str(stage.get("briefingKo", "")).strip()
            if not text or not reading or not ko: continue
            if text in items and items[text]["voiceType"] != "mission-briefing":
                raise ValueError("Briefing must have its own complete phrase, not reuse a learning-text key")
            stage_id = str(stage.get("stageId", ""))
            if text not in items:
                items[text] = {"text": text, "reading": reading, "ko": ko,
                               "sources": ["native/campaign_story.json/"+stage_id],
                               "voiceType": "mission-briefing", "styleId": BRIEFING_STYLE,
                               "stageIds": [stage_id]}
            elif stage_id not in items[text]["stageIds"]:
                items[text]["stageIds"].append(stage_id)
            briefing_stages.append(stage_id)
    result = {"version": 1, "wordCount": len(word_ids), "wordIds": word_ids,
              "uniqueLearningTextCount": learning_count,
              "briefingStageCount": len(briefing_stages), "briefingStageIds": briefing_stages,
              "uniqueTextCount": len(items), "readingConflicts": conflicts,
              "items": [{"key": key(text), **item} for text, item in items.items()]}
    BUILD.mkdir(parents=True, exist_ok=True)
    (BUILD/"corpus.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"wordCount": len(word_ids), "uniqueTextCount": len(items), "conflicts": len(conflicts)}, ensure_ascii=False), flush=True)
    return result

class LoadOrt(C.Structure):
    _fields_ = [("filename", C.c_char_p)]
class Initialize(C.Structure):
    _fields_ = [("acceleration_mode", C.c_int), ("cpu_num_threads", C.c_uint16)]
class LoadModel(C.Structure):
    _fields_ = [("on_existing", C.c_int)]
class Synthesis(C.Structure):
    _fields_ = [("enable_interrogative_upspeak", C.c_bool)]

class Synth:
    def __init__(self):
        dll = next((RUNTIME/"c_api").rglob("voicevox_core.dll"))
        ort = next((RUNTIME/"onnxruntime").rglob("*.dll"))
        self.handles = [os.add_dll_directory(str(dll.parent)), os.add_dll_directory(str(ort.parent))]
        self.api = C.CDLL(str(dll))
        signatures = {
            "voicevox_error_result_to_message": ([C.c_int], C.c_char_p),
            "voicevox_onnxruntime_load_once": ([LoadOrt, C.POINTER(C.c_void_p)], C.c_int),
            "voicevox_open_jtalk_rc_new": ([C.c_char_p, C.POINTER(C.c_void_p)], C.c_int),
            "voicevox_synthesizer_new": ([C.c_void_p, C.c_void_p, Initialize, C.POINTER(C.c_void_p)], C.c_int),
            "voicevox_voice_model_file_open": ([C.c_char_p, C.POINTER(C.c_void_p)], C.c_int),
            "voicevox_synthesizer_load_voice_model": ([C.c_void_p, C.c_void_p, LoadModel], C.c_int),
            "voicevox_synthesizer_create_audio_query": ([C.c_void_p, C.c_char_p, C.c_uint32, C.POINTER(C.c_void_p)], C.c_int),
            "voicevox_synthesizer_synthesis": ([C.c_void_p, C.c_char_p, C.c_uint32, Synthesis, C.POINTER(C.c_size_t), C.POINTER(C.c_void_p)], C.c_int),
            "voicevox_json_free": ([C.c_void_p], None),
            "voicevox_wav_free": ([C.c_void_p], None),
            "voicevox_synthesizer_delete": ([C.c_void_p], None),
            "voicevox_voice_model_file_delete": ([C.c_void_p], None),
            "voicevox_open_jtalk_rc_delete": ([C.c_void_p], None),
        }
        for name, (args, ret) in signatures.items():
            fn = getattr(self.api, name)
            fn.argtypes, fn.restype = args, ret
        self.ort, self.ojt, self.synth, self.model = (C.c_void_p() for _ in range(4))
        self.check(self.api.voicevox_onnxruntime_load_once(LoadOrt(str(ort).encode()), C.byref(self.ort)))
        dic = next((RUNTIME/"dict").glob("open_jtalk_dic*"))
        self.check(self.api.voicevox_open_jtalk_rc_new(str(dic).encode(), C.byref(self.ojt)))
        self.check(self.api.voicevox_synthesizer_new(self.ort, self.ojt, Initialize(1, 2), C.byref(self.synth)))
        model = next((RUNTIME/"models").rglob("n0.vvm"))
        self.check(self.api.voicevox_voice_model_file_open(str(model).encode(), C.byref(self.model)))
        self.check(self.api.voicevox_synthesizer_load_voice_model(self.synth, self.model, LoadModel(0)))

    def check(self, code):
        if code != 0:
            raise RuntimeError(self.api.voicevox_error_result_to_message(code).decode())

    def speak(self, text, style=STYLE):
        ptr = C.c_void_p()
        self.check(self.api.voicevox_synthesizer_create_audio_query(self.synth, text.encode(), style, C.byref(ptr)))
        try:
            query = json.loads(C.string_at(ptr))
        finally:
            self.api.voicevox_json_free(ptr)
        query.update(speedScale=0.92 if style==BRIEFING_STYLE else 0.94, pitchScale=0.0, intonationScale=1.0, volumeScale=1.0,
                     prePhonemeLength=0.08, postPhonemeLength=0.12, outputSamplingRate=24000, outputStereo=False)
        wav_len, wav_ptr = C.c_size_t(), C.c_void_p()
        self.check(self.api.voicevox_synthesizer_synthesis(self.synth, json.dumps(query).encode(), style,
                                                        Synthesis(False), C.byref(wav_len), C.byref(wav_ptr)))
        try:
            return C.string_at(wav_ptr, wav_len.value)
        finally:
            self.api.voicevox_wav_free(wav_ptr)

    def close(self):
        self.api.voicevox_synthesizer_delete(self.synth)
        self.api.voicevox_voice_model_file_delete(self.model)
        self.api.voicevox_open_jtalk_rc_delete(self.ojt)

def inspect_wav(payload):
    with wave.open(io.BytesIO(payload), "rb") as f:
        if f.getnchannels()!=1 or f.getsampwidth()!=2 or f.getframerate()!=24000:
            raise ValueError("Expected mono 24kHz 16-bit authored learning speech")
        data = array.array("h", f.readframes(f.getnframes()))
        if not data: raise ValueError("Empty PCM")
        peak = max(abs(n) for n in data)/32768
        rms = math.sqrt(sum((n/32768)**2 for n in data)/len(data))
        duration = f.getnframes()/f.getframerate()
        if not .15 < duration < 90 or peak<.005 or rms<.001:
            raise ValueError("Silent or implausible learning audio")
        return {"duration": duration, "peak": peak, "rms": rms, "sampleRate": 24000,
                "channels": 1, "bytes": len(payload), "sha256": hashlib.sha256(payload).hexdigest()}

def write_json(path, value):
    temporary = path.with_suffix(path.suffix+".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")
    os.replace(temporary, path)

def build(corpus, limit=0):
    if not (BUILD/"terms-approved.json").is_file():
        raise RuntimeError("Explicit user terms approval marker is required. This script does not accept terms.")
    target = VOICE/"clips"
    target.mkdir(exist_ok=True)
    synth = Synth()
    clips = {}
    start = time.monotonic()
    generated = 0
    generated_duration = 0.0
    try:
        n = 0
        while n < len(corpus["items"]):
            if limit and n>=limit: break
            item = corpus["items"][n]
            path = target/(item["key"]+".wav")
            if path.exists():
                payload = path.read_bytes()
            else:
                payload = synth.speak(item["reading"], int(item.get("styleId",STYLE)))
                info = inspect_wav(payload)
                temporary = path.with_suffix(".wav.tmp")
                temporary.write_bytes(payload)
                os.replace(temporary, path)
                generated += 1
                generated_duration += info["duration"]
            clips[item["key"]] = {"text": item["text"], "reading": item["reading"],
                                 "voiceType": item.get("voiceType", "learning"), "styleId": item.get("styleId",STYLE),
                                 "stageIds": item.get("stageIds",[]), "ko": item.get("ko",""),
                                 "sources": item["sources"],
                                 "path": "res://assets/learning-voice/clips/"+path.name,
                                 **inspect_wav(payload)}
            if (n+1)%25==0:
                progress = {"done": n+1, "total": len(corpus["items"]),
                            "seconds": round(time.monotonic()-start,1), "generatedNew": generated,
                            "generatedAudioSeconds": round(generated_duration,2),
                            "bytes": sum(c["bytes"] for c in clips.values()), "running": True}
                write_json(BUILD/"progress.json", progress)
                print(json.dumps(progress, ensure_ascii=False), flush=True)
            n += 1
            if not limit and n == len(corpus["items"]):
                # Briefings may be authored while the long learning batch is running.
                # Read them again at the end, append new exact phrases, and synthesize
                # their actual male style before publishing the final manifest.
                refreshed = inventory()
                existing = {entry["key"] for entry in corpus["items"]}
                additions = [entry for entry in refreshed["items"] if entry["key"] not in existing]
                corpus["items"].extend(additions)
                corpus["briefingStageCount"] = refreshed["briefingStageCount"]
                corpus["briefingStageIds"] = refreshed["briefingStageIds"]
                corpus["uniqueTextCount"] = len(corpus["items"])
    finally:
        synth.close()
    manifest = {"version": 1, "title": "일본어 오프라인 학습 읽기", "engine": "VOICEVOX CORE 0.17.0",
                "voice": "VOICEVOX Nemo 女声1", "styleId": STYLE, "synthetic": True,
                "credit": "VOICEVOX Nemo", "license": "VOICEVOX Nemo terms; commercial permitted with credit",
                "source": "https://voicevox.hiroshiba.jp/nemo/term/", "gainDb": -4.0,
                "pitchScale": 1.0, "sampleRate": 24000, "channels": 1,
                "wordCount": corpus["wordCount"], "uniqueTextCount": len(corpus["items"]),
                "generatedClipCount": len(clips), "complete": len(clips)==len(corpus["items"]),
                "uniqueLearningTextCount": corpus["uniqueLearningTextCount"],
                "briefingStageCount": corpus.get("briefingStageCount",0),
                "briefingComplete": corpus.get("briefingStageCount",0)==40,
                "briefingVoice": "VOICEVOX Nemo 男声1", "briefingStyleId": BRIEFING_STYLE,
                "generationSeconds": round(time.monotonic()-start,3),
                "clips": clips}
    write_json(VOICE/"manifest.json",manifest)
    write_json(BUILD/"progress.json", {"done":len(clips),"total":len(corpus["items"]),
               "seconds":manifest["generationSeconds"],"bytes":sum(c["bytes"] for c in clips.values()),
               "running":False,"complete":manifest["complete"],"briefingComplete":manifest["briefingComplete"]})
    print(json.dumps({"done":len(clips), "seconds":manifest["generationSeconds"],"bytes":sum(c["bytes"] for c in clips.values())},ensure_ascii=False),flush=True)

if __name__=="__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("--inventory",action="store_true")
    parser.add_argument("--limit",type=int,default=0)
    args=parser.parse_args()
    corpus=inventory()
    if not args.inventory: build(corpus,args.limit)
