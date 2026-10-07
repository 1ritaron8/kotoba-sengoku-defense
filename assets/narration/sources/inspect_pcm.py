"""Inspect unchanged official WAVs and add auditable asset metadata.

Pitch is a simple voiced-window autocorrelation estimate, not an audition or
proof that a performance meets the requested artistic direction. No WAV edits.
"""
from pathlib import Path
import json, wave, hashlib, math, array, statistics, sys

ROOT = Path(__file__).resolve().parents[1]
manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8-sig"))
index = {Path(row["url"]).name: row for row in json.loads((ROOT / "sources/download-index.json").read_text(encoding="utf-8-sig"))}
stats = []
for clip in manifest["clips"]:
    file = ROOT / "clips" / clip["originalFile"]
    with wave.open(str(file), "rb") as wav:
        rate, channels, width, frames = wav.getframerate(), wav.getnchannels(), wav.getsampwidth(), wav.getnframes()
        assert width == 2, file
        values = array.array("h", wav.readframes(frames))
        if sys.byteorder != "little": values.byteswap()
    mono = [sum(values[i:i+channels]) / (channels * 32768.0) for i in range(0, len(values), channels)]
    rms = math.sqrt(sum(v*v for v in mono) / max(1, len(mono)))
    pitch = []
    # 40 ms frames, coarse low-rate analysis to keep standard-library work small.
    stride = max(1, rate // 4000)
    reduced = mono[::stride]
    analysis_rate = rate / stride
    size = int(analysis_rate * .040)
    for start in range(0, len(reduced)-size, max(1, size//2)):
        window = reduced[start:start+size]
        energy = sum(v*v for v in window)
        if energy / size < max(.0002, rms*rms*.4): continue
        mean = sum(window)/size
        window = [v-mean for v in window]
        candidates = []
        for lag in range(int(analysis_rate/240), int(analysis_rate/65)+1):
            a, b = window[:-lag], window[lag:]
            den = math.sqrt(sum(v*v for v in a)*sum(v*v for v in b))
            corr = sum(x*y for x,y in zip(a,b))/den if den else 0.0
            candidates.append((corr, lag))
        best = max(candidates)
        if best[0] >= .55: pitch.append(analysis_rate/best[1])
    clip.update({"path":"res://assets/narration/clips/"+file.name,"downloadUrl":index[file.name]["url"],"sha256":hashlib.sha256(file.read_bytes()).hexdigest(),"bytes":file.stat().st_size,"seconds":frames/rate,"sampleRate":rate,"channels":channels,"bits":width*8,"rms":rms,"peak":max(abs(v) for v in mono),"pitchEstimateHz":statistics.median(pitch) if pitch else None,"pitchEstimateMethod":"65-240Hz normalized autocorrelation, voiced40ms windows; octave errors possible, no artistic-tone claim"})
    assert clip["jp"] == index[file.name]["jp"], (clip["jp"],index[file.name]["jp"])
    assert len(mono)>1000 and rms>.004
    stats.append({k:clip[k] for k in ("id","seconds","sampleRate","channels","bits","rms","peak","pitchEstimateHz")})
(ROOT / "manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
(ROOT / "sources/pcm-analysis.json").write_text(json.dumps(stats,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
print(json.dumps(stats,ensure_ascii=False))
