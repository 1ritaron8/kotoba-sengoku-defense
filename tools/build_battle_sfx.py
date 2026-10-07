"""Rebuild short, non-looping battle Foley from preserved licensed recordings.

Only stdlib and already available NumPy are used. Original archives remain in
tools/sfx/source and never ship. No network, paid assets or audio programs.
"""
from __future__ import annotations

import hashlib
import io
import json
import struct
import wave
import zipfile
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tools/sfx/source"
OUT = ROOT / "assets/sfx"
RATE = 44100
CC0 = "https://creativecommons.org/publicdomain/zero/1.0/"
BY3 = "https://creativecommons.org/licenses/by/3.0/"
SOURCES = {
    "bow": {
        "id": "artisticdude-battle", "title": "Battle Sound Effects",
        "author": "artisticdude (submitted by Ogrebane)",
        "source": "https://opengameart.org/content/battle-sound-effects",
        "download": "https://opengameart.org/sites/default/files/battle_sound_effects_0.zip",
        "archive": "battle-sound-effects.zip", "published": "2010-05-20",
        "license": "CC0 1.0", "licenseUrl": CC0,
        "licenseEvidence": "tools/sfx/pages/battle-sound-effects.html",
    },
    "foley": {
        "id": "vehicle-tinysized", "title": "Tinysized SFX Library",
        "author": "Jan Schupke / Vehicle",
        "source": "https://opengameart.org/content/fantasy-sound-effects-tinysized-sfx",
        "download": "https://opengameart.org/sites/default/files/tinysized.zip",
        "archive": "tinysized.zip", "published": "2015-08-12",
        "license": "CC0 1.0", "licenseUrl": CC0,
        "licenseEvidence": "tinysized.zip::readme.txt and tools/sfx/pages/fantasy-sound-effects-tinysized-sfx.html",
    },
    "gun": {
        "id": "vincent-sevedge-gunshots", "title": "Gunshot Sounds",
        "author": "Vincent Sevedge (archive copyright); submitted by Tabasco",
        "source": "https://opengameart.org/content/gunshot-sounds",
        "download": "https://opengameart.org/sites/default/files/sounds.zip",
        "archive": "gunshot-sounds.zip", "published": "2010-07-02",
        "copyright": "Copyright (c) 2009 Vincent Sevedge",
        "license": "CC BY 3.0", "licenseUrl": BY3,
        "licenseEvidence": "gunshot-sounds.zip::sounds/creativecommons.txt",
        "licenseNote": "Source webpage lists CC0; included original copyright/license says CC BY 3.0. Attribution 3.0 terms are retained conservatively.",
    },
    "voice": {
        "id": "brandon-song-adventurer", "title": "Voice Clip Pack - Male Adventurer RPG",
        "author": "Brandon Song (wolfwoot)",
        "source": "https://opengameart.org/content/voice-clip-pack-male-adventurer-rpg",
        "download": "https://opengameart.org/sites/default/files/RPG%20Male%20Adventurer.zip",
        "archive": "male-adventurer.zip", "published": "2020-02-09",
        "license": "CC0 1.0", "licenseUrl": CC0,
        "creditText": "Voice performance: Brandon Song (wolfwoot), Voice Clip Pack - Male Adventurer RPG, CC0 1.0.",
        "licenseEvidence": "tools/sfx/pages/male-adventurer.html (author's CC0 release and requested credit name)",
        "use": "Short nonverbal hurt/death performances only; no dialogue, synthetic/TTS voices or nationality/language claims.",
    },
}
ARCHIVE_HASHES = {
    "battle-sound-effects.zip": "44e3d26b2378d2eb3a4f28b4c5cbc71908ad13c7389038348dbe9b8cde4f4c05",
    "tinysized.zip": "7f00e2b1dae15e68db0e1d6096767f03755e9e7c247128afc3e935e63774d7db",
    "gunshot-sounds.zip": "5b3960083a94e18ee47bc84376615a476debc884b18f25b93ea4b6ab3f278e4f",
    "male-adventurer.zip": "eb874f027758ccf9eca0449d09dc3220dc44eb4095e8b0da93351d276e176f7f",
}


def riff_samples(raw: bytes) -> tuple[np.ndarray, int]:
    """Read PCM16/24/32 or IEEE float WAV without an external decoder."""
    assert raw[:4] == b"RIFF" and raw[8:12] == b"WAVE"
    offset = 12
    fmt = data = None
    while offset + 8 <= len(raw):
        name, size = struct.unpack_from("<4sI", raw, offset)
        payload = raw[offset + 8: offset + 8 + size]
        if name == b"fmt ": fmt = payload
        elif name == b"data": data = payload
        offset += 8 + size + size % 2
    assert fmt is not None and data is not None
    kind, channels, rate, _, _, bits = struct.unpack_from("<HHIIHH", fmt)
    if kind == 3 and bits == 32:
        samples = np.frombuffer(data, "<f4").astype(np.float64)
    elif kind == 1 and bits in (16, 32):
        samples = np.frombuffer(data, "<i2" if bits == 16 else "<i4").astype(np.float64) / (2 ** (bits - 1))
    elif kind == 1 and bits == 24:
        b = np.frombuffer(data, np.uint8).reshape(-1, 3).astype(np.int32)
        values = b[:, 0] | b[:, 1] << 8 | b[:, 2] << 16
        values = (values ^ 0x800000) - 0x800000
        samples = values / 8388608.0
    else:
        raise ValueError(f"Unsupported WAV kind={kind} bits={bits}")
    samples = samples.reshape(-1, channels).mean(axis=1)
    assert np.isfinite(samples).all()
    return samples, rate


CACHE = {}
AUDIT = []


def recorded(key: str, filename: str) -> np.ndarray:
    cache_key = key + ":" + filename
    if cache_key not in CACHE:
        source = SOURCES[key]
        with zipfile.ZipFile(SOURCE / source["archive"]) as archive:
            raw = archive.read(filename)
        samples, rate = riff_samples(raw)
        if rate != RATE:
            samples = np.interp(np.arange(round(len(samples) * RATE / rate)) * rate / RATE, np.arange(len(samples)), samples)
        CACHE[cache_key] = samples
        AUDIT.append({"sourceId": source["id"], "originalFile": filename, "sha256": hashlib.sha256(raw).hexdigest(), "duration": round(len(samples) / RATE, 4)})
    return CACHE[cache_key].copy()


def filter_band(samples: np.ndarray, low: float = 55, high: float = 9000) -> np.ndarray:
    """Soft spectral roll-off; no abrupt cutoff or invented electronic beep."""
    spectrum = np.fft.rfft(samples)
    freq = np.fft.rfftfreq(len(samples), 1 / RATE)
    weight = (1 - np.exp(-(freq / low) ** 2)) * np.exp(-(freq / high) ** 4)
    return np.fft.irfft(spectrum * weight, n=len(samples))


def pitched(samples: np.ndarray, factor: float) -> np.ndarray:
    return np.interp(np.arange(0, len(samples) - 1, factor), np.arange(len(samples)), samples)


def strongest(samples: np.ndarray, seconds: float, lead: float = .016) -> np.ndarray:
    """Select a single real transient and its short tail, excluding room lead-in."""
    block = max(1, round(.006 * RATE))
    envelope = np.convolve(samples ** 2, np.ones(block) / block, "same")
    peak = int(envelope.argmax())
    threshold = float(envelope[peak]) * .08
    onset = peak
    while onset > 0 and envelope[onset] > threshold:
        onset -= 1
    begin = max(0, onset - round(lead * RATE))
    return samples[begin:begin + round(seconds * RATE)].copy()


def mix(layers: list[tuple[np.ndarray, float, float]], seconds: float | None = None) -> np.ndarray:
    total = max(round(delay * RATE) + len(s) for s, delay, _ in layers)
    if seconds is not None: total = max(total, round(seconds * RATE))
    out = np.zeros(total)
    for samples, delay, gain in layers:
        start = round(delay * RATE)
        out[start:start + len(samples)] += samples * gain
    return out


def finish(samples: np.ndarray, peak: float = .78) -> np.ndarray:
    samples = filter_band(samples - samples.mean())
    samples /= max(.00001, float(np.max(np.abs(samples))))
    samples *= peak
    fade_in = min(round(.002 * RATE), len(samples) // 10)
    fade_out = min(round(.035 * RATE), len(samples) // 5)
    samples[:fade_in] *= np.linspace(0, 1, fade_in)
    samples[-fade_out:] *= np.linspace(1, 0, fade_out)
    return samples


CLIPS = []


def save(name: str, samples: np.ndarray, keys: list[str], purpose: str, files: list[str], changes: str) -> None:
    samples = finish(samples)
    pcm = np.round(samples * 32767).astype("<i2")
    path = OUT / f"{name}.wav"
    with wave.open(str(path), "wb") as stream:
        stream.setparams((1, 2, RATE, len(pcm), "NONE", "not compressed"))
        stream.writeframes(pcm.tobytes())
    clip = {"id": name, "path": "res://assets/sfx/" + path.name, "sourceIds": [SOURCES[k]["id"] for k in keys],
            "purposeKo": purpose, "originalFiles": files, "changes": changes,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "seconds": round(len(pcm) / RATE, 4),
            "sampleRate": RATE, "channels": 1, "bits": 16,
            "peak": round(float(np.abs(samples).max()), 6), "rms": round(float(np.sqrt(np.mean(samples ** 2))), 6),
            "nonzeroSamples": int(np.count_nonzero(pcm))}
    assert .04 < clip["seconds"] < 2.1 and .005 < clip["rms"] < .5 and clip["peak"] < .8
    CLIPS.append(clip)


def build() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, expected in ARCHIVE_HASHES.items():
        actual = hashlib.sha256((SOURCE / name).read_bytes()).hexdigest()
        assert actual == expected, f"Preserved source archive hash mismatch: {name}"
    b = lambda n: recorded("bow", "battle_sound_effects/" + n + ".wav")
    f = lambda n: recorded("foley", "sfx-cc0/" + n + ".wav")
    v = lambda n: recorded("voice", "RPG Male Adventurer/" + n + ".wav")
    # Bow is a real string release, not a laser/whistle substitute.
    bow = strongest(b("Bow"), .34)
    save("bow_release_a", bow, ["bow"], "활시위 발사", ["Bow.wav"], "Single string transient; trimmed, mono 44.1 kHz, soft EQ and edge fades.")
    save("bow_release_b", pitched(bow, .94), ["bow"], "활시위 발사 변주", ["Bow.wav"], "Release variant with 6% lower pitch; same short-tail mastering.")
    for suffix, filename in [("a", "swish_2"), ("b", "swish_3")]:
        save("sword_swing_" + suffix, strongest(b(filename), .32), ["bow"], "검·창의 실제 공격 휘두름", [filename + ".wav"], "Trimmed air/weapon swish, subdued high-frequency roll-off, mono and fades.")
    # The rifle recording is explicitly an adapted game matchlock effect, not
    # an authentic historical matchlock recording. Retain archive CC BY 3.0.
    gun = recorded("gun", "sounds/mosin.wav")
    shot = strongest(gun, .60, .008)
    shot = filter_band(shot, 80, 5500)
    shot *= np.exp(-np.arange(len(shot)) / RATE / .24)
    for suffix, factor in [("a", .91), ("b", .97)]:
        save("matchlock_" + suffix, pitched(shot, factor), ["gun"], "화승총 발사 게임 효과", ["sounds/mosin.wav"], "Adapted modern rifle recording: isolated one shot, room noise/tail shortened, lowered pitch, soft 5.5 kHz EQ, mono/fades; not an authentic historical musket recording.")
    for suffix, n in [("a", "sword-clash-01"), ("b", "sword-clash-02")]:
        save("metal_hit_" + suffix, strongest(f(n), .42), ["foley"], "검·갑옷 금속 피격", [n + ".wav"], "Single recorded metal clash, trimmed ringing tail, mono and fades.")
    wood = strongest(f("wood-bowl-spoon-01"), .24)
    wood2 = strongest(f("wood-bowl-spoon-02"), .25)
    cloth = strongest(f("cloth-pouch-shake-01"), .28)
    fall = strongest(f("boots-leather-jump-01"), .38)
    step = strongest(f("boots-leather-step-01"), .25)
    soil = strongest(f("soil-steps-01"), .28)
    for suffix, stick in [("a", wood), ("b", wood2)]:
        save("wood_hit_" + suffix, mix([(stick, 0, .7), (pitched(fall[:round(.18 * RATE)], .86), .003, .3)]), ["foley"], "창·봉의 둔한 나무 충격", ["wood-bowl-spoon-0" + ("1" if suffix == "a" else "2") + ".wav", "boots-leather-jump-01.wav"], "Recorded wood contact and real leather landing only; mono/fades, no synthesized thud.")
    save("body_hit_a", mix([(fall[:round(.18 * RATE)], 0, .7), (cloth, .005, .3)]), ["foley"], "갑옷 없는 몸·천 피격", ["boots-leather-jump-01.wav", "cloth-pouch-shake-01.wav"], "Real leather/body-weight and cloth Foley only; no synthesized sound or gore.")
    save("body_hit_b", mix([(soil, 0, .62), (cloth, .008, .3)]), ["foley"], "몸·천 피격 변주", ["soil-steps-01.wav", "cloth-pouch-shake-01.wav"], "Short soil and cloth Foley layered, mono/fades.")
    for suffix, s in [("a", step), ("b", soil)]:
        save("footstep_" + suffix, s, ["foley"], "이동하는 보병의 발 접지", ["boots-leather-step-01.wav" if suffix == "a" else "soil-steps-01.wav"], "One leather/earth foot contact, trimmed, mono and edge fades.")
    hoof = pitched(wood, .82)
    save("hoof_step", mix([(hoof, 0, .85), (wood2, .045, .45)]), ["foley"], "기마 한 보폭의 발굽 접지", ["wood-bowl-spoon-01.wav", "wood-bowl-spoon-02.wav"], "Wooden Foley performed as a paired hoof clop; constructed horse Foley, not a horse field recording.")
    save("horse_charge", mix([(hoof, 0, .55), (wood2, .065, .5), (hoof, .155, .6), (wood2, .218, .5), (pitched(fall, .85), .26, .8)]), ["foley"], "기마 돌격의 발굽·몸무게 충돌", ["wood-bowl-spoon-01.wav", "wood-bowl-spoon-02.wav", "boots-leather-jump-01.wav"], "Paired wooden hoof Foley and real leather landing only; no synthesized impact.")
    coin = strongest(f("coins-shake-01"), .28)
    leather = strongest(f("quiver-leather-squeeze-01"), .22)
    save("recruit", mix([(coin, 0, .5), (leather, .035, .6)]), ["foley"], "성공한 소집의 금화·장비 준비", ["coins-shake-01.wav", "quiver-leather-squeeze-01.wav"], "Coin and leather equipment Foley; no electronic UI beep.")
    latch = strongest(f("handcuffs-metal-lock-01"), .18)
    save("deploy", mix([(step, 0, .85), (latch, .045, .25)]), ["foley"], "성공한 병력 배치의 접지·장비 체결", ["boots-leather-step-01.wav", "handcuffs-metal-lock-01.wav"], "Leather foot plant with quiet mechanical latch; mono and fades.")
    save("ui_click", strongest(wood2, .085), ["foley"], "작은 나무 조작음", ["wood-bowl-spoon-02.wav"], "Very short muted wooden contact; no tone oscillator.")
    save("kill", mix([(fall, 0, .8), (cloth, .04, .5), (pitched(latch, .78), .085, .2)]), ["foley"], "적의 사망·갑옷 바닥 착지", ["boots-leather-jump-01.wav", "cloth-pouch-shake-01.wav", "handcuffs-metal-lock-01.wav"], "A single body landing with equipment/cloth fall; no screaming or duplicated kill rewards.")
    save("ally_down", mix([(pitched(fall, .82), 0, .8), (cloth, .075, .4)]), ["foley"], "아군 전투 불능 착지", ["boots-leather-jump-01.wav", "cloth-pouch-shake-01.wav"], "Lower leather landing and cloth Foley, mono/fades.")
    hammer = strongest(f("metal-hammer-hit-01"), .42)
    save("objective_hit", mix([(pitched(hammer, .75), 0, .65), (pitched(wood2, .68), .012, .6)]), ["foley"], "본진·목표의 피해 경고", ["metal-hammer-hit-01.wav", "wood-bowl-spoon-02.wav"], "Real recorded metal/wood impact with lowered playback pitch; no oscillator/alarm beep.")
    patterns = {
        "wave_start": [(wood, 0, .65), (wood2, .18, .7)],
        "wave_clear": [(wood2, 0, .5), (hammer, .20, .45)],
        "victory": [(wood, 0, .65), (wood2, .18, .65), (hammer, .40, .5)],
        "defeat": [(pitched(hammer, .74), 0, .55), (pitched(fall, .82), .32, .65)],
    }
    purposes = {"wave_start": "적 공세 시작의 나무 신호", "wave_clear": "파상 공격 종료의 나무·금속 신호", "victory": "승리의 짧은 나무·금속 신호", "defeat": "패배의 낮은 장비 착지 신호"}
    pattern_files = {"wave_start": ["wood-bowl-spoon-01.wav", "wood-bowl-spoon-02.wav"], "wave_clear": ["wood-bowl-spoon-02.wav", "metal-hammer-hit-01.wav"], "victory": ["wood-bowl-spoon-01.wav", "wood-bowl-spoon-02.wav", "metal-hammer-hit-01.wav"], "defeat": ["metal-hammer-hit-01.wav", "boots-leather-jump-01.wav"]}
    for name, pattern in patterns.items():
        save(name, mix(pattern), ["foley"], purposes[name], pattern_files[name], "Short sequence of real recorded wooden/metal/equipment contacts; DSP edit only, no synthesis or TTS.")
    for name, original in [("pain_reaction_a", "hurt1"), ("pain_reaction_b", "hurt4"), ("death_reaction_a", "death0"), ("death_reaction_b", "death1")]:
        save(name, strongest(v(original), .7 if original.startswith("hurt") else 1.05), ["voice"], "실제 배우의 짧은 비언어 전투 반응", ["RPG Male Adventurer/" + original + ".wav"], "Human vocal performance by Brandon Song; nonverbal hurt/death clip only, silence/tail trimmed, mono/EQ/fades. No TTS, generated voice, dialogue or nationality claim.")
    # Persist byte-identical archive notices and legal text, but only shipped
    # source families are listed. Kenney research packs are not used/credited.
    for key in ("bow", "foley", "gun", "voice"):
        item = SOURCES[key]
        item["archiveSha256"] = hashlib.sha256((SOURCE / item["archive"]).read_bytes()).hexdigest()
    with zipfile.ZipFile(SOURCE / "gunshot-sounds.zip") as z:
        (OUT / "gunshot-original-notice.txt").write_bytes(z.read("sounds/creativecommons.txt"))
    with zipfile.ZipFile(SOURCE / "tinysized.zip") as z:
        (OUT / "tinysized-original-notice.txt").write_bytes(z.read("readme.txt"))
    legal = ROOT / "tools/sfx/pages/CC0-1.0.txt"
    if legal.exists(): (OUT / "CC0-1.0.txt").write_bytes(legal.read_bytes())
    legal = ROOT / "tools/sfx/pages/CC-BY-3.0.txt"
    if legal.exists(): (OUT / "CC-BY-3.0.txt").write_bytes(legal.read_bytes())
    (OUT / "voice-original-notice.txt").write_text("Voice Clip Pack - Male Adventurer RPG\nVoice performance: Brandon Song (wolfwoot)\nSource: https://opengameart.org/content/voice-clip-pack-male-adventurer-rpg\nLicense: CC0 1.0 https://creativecommons.org/publicdomain/zero/1.0/\nRelease date: 2020-02-09\nAuthor permits any type of project and appreciates credit as Brandon Song.\nChanges: nonverbal hurt/death files only, trimmed, mono converted, EQ/fades; no generated voice or dialogue.\n", encoding="utf-8")
    manifest = {"version": 1, "checkedDate": "2026-10-04", "format": "44.1kHz mono PCM16 WAV, non-looping", "recordedOnly": True, "sources": [SOURCES[k] for k in ("bow", "foley", "gun", "voice")], "clips": CLIPS,
                "licenseFiles": ["res://assets/sfx/gunshot-original-notice.txt", "res://assets/sfx/tinysized-original-notice.txt", "res://assets/sfx/voice-original-notice.txt", "res://assets/sfx/CC0-1.0.txt", "res://assets/sfx/CC-BY-3.0.txt"],
                "mastering": "Every effect is adapted from free licensed real recordings: organic Foley, wooden/metal signals and restrained human nonverbal reactions. Editing/EQ/fades only, no synthesis, generated percussion, beeps or TTS. The recorded modern rifle is not represented as an authentic historical matchlock recording."}
    assert len({c["sha256"] for c in CLIPS}) == len(CLIPS)
    (ROOT / "native/sfx_sources.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (ROOT / "tools/sfx/source-audit.json").write_text(json.dumps(AUDIT, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"clips": len(CLIPS), "totalBytes": sum((OUT / (c["id"] + ".wav")).stat().st_size for c in CLIPS), "seconds": round(sum(c["seconds"] for c in CLIPS), 2), "uniqueHashes": len({c["sha256"] for c in CLIPS})}))


if __name__ == "__main__":
    build()
