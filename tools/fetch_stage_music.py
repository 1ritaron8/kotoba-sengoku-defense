"""Fetch licensed stage BGM from official PeriTune and Amacha sources.

Discovery saves original source/terms pages and a compact inventory. The fetch
command reads native/music.json, resumes completed files, and records hashes and
audio metadata. No packages, credentials, or external music services are used.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import html
import json
import re
import struct
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / "tools" / "music" / "pages"
TERMS = "https://peritune.com/about/"
ARCHIVES = ["https://peritune.com/blog/tag/japanese_style/", "https://peritune.com/blog/tag/japanese_style/page/2/"]
HEADERS = {"User-Agent": "SengokuJapaneseDefense/1.0 (official free BGM attribution and download)"}
OFFICIAL_HOSTS = {"peritune.com", "amachamusic.chagasi.com"}
AMACHA_TERMS = "https://amachamusic.chagasi.com/terms.html"
AMACHA_SONGS = [
    "yuruyakanakaze", "bunanomorinimauyuki", "ojizousamanoirukomichi",
    "ryunomai", "japaneseautumn", "hanamatsuri", "bakumatsubukyoku_ikusa",
    "kamigaminoyadorubasho",
]


def request(url: str) -> bytes:
    url = url.replace("http://peritune.com/", "https://peritune.com/")
    if urllib.parse.urlparse(url).hostname not in OFFICIAL_HOSTS:
        raise ValueError(f"Only the official host is allowed: {url}")
    with urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=90) as response:
        if urllib.parse.urlparse(response.url).hostname not in OFFICIAL_HOSTS:
            raise ValueError("Download redirected outside the official host")
        return response.read()


def text_content(raw: str) -> str:
    raw = re.sub(r"<(script|style)\b[^>]*>.*?</\1>", "", raw, flags=re.S | re.I)
    raw = re.sub(r"</(?:p|h[1-6]|li|div|tr|section)>", "\n", raw, flags=re.I)
    return "\n".join(line.strip() for line in html.unescape(re.sub(r"<[^>]+>", " ", raw)).splitlines() if line.strip())


def cache_page(url: str) -> str:
    parsed = urllib.parse.urlparse(url)
    path = parsed.hostname + "__" + (parsed.path.strip("/").replace("/", "__") or "home")
    target = CACHE / (path + ".html")
    CACHE.mkdir(parents=True, exist_ok=True)
    old_target = CACHE / ((parsed.path.strip("/").replace("/", "__") or "home") + ".html")
    if not target.exists() and parsed.hostname == "peritune.com" and old_target.exists():
        raw = old_target.read_text(encoding="utf-8")
    elif target.exists():
        raw = target.read_text(encoding="utf-8")
    else:
        payload = request(url)
        try:
            raw = payload.decode("utf-8")
        except UnicodeDecodeError:
            raw = payload.decode("shift_jis")
    if not target.exists():
        target.write_text(raw, encoding="utf-8")
    (CACHE / (path + ".txt")).write_text(text_content(raw), encoding="utf-8")
    return raw


def inspect_page(url: str) -> dict:
    raw = cache_page(url)
    if urllib.parse.urlparse(url).hostname == "amachamusic.chagasi.com":
        body = text_content(raw)
        title_match = re.search(r"<title\b[^>]*>(.*?)</title>", raw, re.S | re.I)
        title = text_content(title_match.group(1)).split("｜")[0]
        date = re.search(r"(\d{4})\.(\d{2})\s*\|", body)
        if not date:
            raise ValueError("Amacha publication month missing: " + url)
        urls = sorted(set(urllib.parse.urljoin(url, html.unescape(match)) for match in re.findall(r'href=[\"\']([^\"\']+\.mp3)[\"\']', raw, re.I)))
        compact = body[body.find("音楽素材のダウンロード"):].split("サイト内検索")[0]
        return {"title": title, "published": "-".join(date.groups()), "source": url, "downloads": urls, "description": compact, "termsUrl": AMACHA_TERMS}
    title_match = re.search(r"<h1\b[^>]*>(.*?)</h1>", raw, re.S | re.I)
    title = text_content(title_match.group(1)) if title_match else ""
    date = re.search(r"/blog/(\d{4})/(\d{2})/(\d{2})/", url)
    published = "-".join(date.groups()) if date else ""
    if not published or published > "2026-02-28":
        raise ValueError("CC BY cutoff not satisfied: " + url)
    urls = sorted(set(html.unescape(match).replace("http://peritune.com/", "https://peritune.com/") for match in re.findall(r'https?://peritune\.com/(?:music|loop)/[^\s\"\'<>]+', raw)))
    compact = text_content(raw[title_match.start():]) if title_match else text_content(raw)
    compact = compact.split("関連記事")[0].split("試聴")[0]
    return {"title": title, "published": published, "source": url, "downloads": urls, "description": compact, "termsUrl": TERMS}


def discover() -> None:
    cache_page(TERMS)
    links = set()
    for url in ARCHIVES:
        raw = cache_page(url)
        for match in re.findall(r'href=[\"\']([^\"\']+)[\"\']', raw):
            absolute = urllib.parse.urljoin(url, html.unescape(match))
            if re.match(r"https://peritune\.com/blog/\d{4}/\d{2}/\d{2}/[^/?#]+/?$", absolute):
                links.add(absolute)
    # Archive sidebars can contain unrelated links; keep posts whose article
    # itself describes Japanese style, rather than trusting a link container.
    rows = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for row in pool.map(inspect_page, sorted(links)):
            rows.append(row)
            if len(rows) % 10 == 0:
                print(f"Cached {len(rows)} official song pages", flush=True)
    cache_page("https://peritune.com/freematerial_list/")
    cache_page(AMACHA_TERMS)
    for slug in AMACHA_SONGS:
        rows.append(inspect_page(f"https://amachamusic.chagasi.com/music_{slug}.html"))
    path = ROOT / "tools" / "music" / "inventory.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Inventory: {len(rows)} songs -> {path.relative_to(ROOT)}", flush=True)


def mp3_metadata(data: bytes) -> dict:
    cursor = 0
    if data[:3] == b"ID3":
        length = sum((data[6 + i] & 127) << (7 * (3 - i)) for i in range(4))
        cursor = 10 + length + (10 if data[5] & 16 else 0)
    duration = 0.0
    frames = 0
    sample_rates = set()
    bitrates_v1 = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0]
    bitrates_v2 = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0]
    while cursor + 4 <= len(data):
        header = int.from_bytes(data[cursor:cursor + 4], "big")
        if header & 0xFFE00000 != 0xFFE00000:
            if frames and data[cursor:cursor + 3] == b"TAG":
                break
            cursor += 1
            continue
        version = (header >> 19) & 3
        layer = (header >> 17) & 3
        bitrate_index = (header >> 12) & 15
        rate_index = (header >> 10) & 3
        if version == 1 or layer != 1 or rate_index == 3 or bitrate_index in (0, 15):
            cursor += 1
            continue
        rate = [44100, 48000, 32000][rate_index]
        if version == 2:
            rate //= 2
        elif version == 0:
            rate //= 4
        bitrate = (bitrates_v1 if version == 3 else bitrates_v2)[bitrate_index] * 1000
        samples = 1152 if version == 3 else 576
        frame_size = (144 if version == 3 else 72) * bitrate // rate + ((header >> 9) & 1)
        if cursor + frame_size > len(data):
            break
        duration += samples / rate
        frames += 1
        sample_rates.add(rate)
        cursor += frame_size
    if frames < 100 or duration < 10:
        raise ValueError("MP3 does not contain a complete usable music track")
    return {"format": "mp3", "durationSeconds": round(duration, 3), "sampleRates": sorted(sample_rates), "frames": frames}


def ogg_metadata(data: bytes) -> dict:
    marker = data.find(b"\x01vorbis")
    if data[:4] != b"OggS" or marker < 0:
        raise ValueError("Not an Ogg Vorbis stream")
    rate = struct.unpack_from("<I", data, marker + 12)[0]
    cursor = 0
    maximum = 0
    pages = 0
    while cursor + 27 <= len(data):
        if data[cursor:cursor + 4] != b"OggS":
            raise ValueError("Broken Ogg page sequence")
        granule = struct.unpack_from("<Q", data, cursor + 6)[0]
        if granule != 0xFFFFFFFFFFFFFFFF:
            maximum = max(maximum, granule)
        segments = data[cursor + 26]
        sizes = data[cursor + 27:cursor + 27 + segments]
        cursor += 27 + segments + sum(sizes)
        pages += 1
    if cursor != len(data) or maximum / rate < 10:
        raise ValueError("Ogg file is incomplete or too short")
    return {"format": "ogg", "durationSeconds": round(maximum / rate, 3), "sampleRates": [rate], "pages": pages}


def local_audio_metadata(path: Path) -> dict:
    data = path.read_bytes()
    info = ogg_metadata(data) if path.suffix == ".ogg" else mp3_metadata(data)
    return {**info, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}


def fetch_one(track: dict) -> dict:
    info = inspect_page(track["source"])
    if info["published"] != track["published"]:
        raise ValueError("Manifest publication/license mismatch")
    if urllib.parse.urlparse(track["source"]).hostname == "peritune.com" and track["license"] != "CC BY 4.0":
        raise ValueError("PeriTune must retain its verified CC BY license")
    official_downloads = info["downloads"]
    url = track["download"]
    if url not in official_downloads:
        raise ValueError("Download link not present on its official song page: " + url)
    target = (ROOT / track["path"].removeprefix("res://")).resolve()
    allowed = (ROOT / "assets" / "music").resolve()
    if not target.is_relative_to(allowed):
        raise ValueError("Audio target is outside assets/music")
    target.parent.mkdir(parents=True, exist_ok=True)
    if not target.exists():
        payload = request(url)
        if url.lower().endswith(".zip"):
            import io
            import zipfile
            with zipfile.ZipFile(io.BytesIO(payload)) as archive:
                choices = [name for name in archive.namelist() if name.lower().endswith(target.suffix)]
                exact = [name for name in choices if "_loop." in name.lower()]
                member = (exact or choices)[0]
                payload = archive.read(member)
        target.write_bytes(payload)
    return {"stageId": track["stageId"], "title": track["title"], "path": track["path"], **local_audio_metadata(target)}


def fetch() -> None:
    manifest = json.loads((ROOT / "native" / "music.json").read_text(encoding="utf-8"))
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for result in pool.map(fetch_one, manifest["tracks"]):
            results.append(result)
            if len(results) % 10 == 0:
                (ROOT / "tools" / "music" / "audio-validation.json").write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
                print(f"Downloaded and validated {len(results)}/{len(manifest['tracks'])} unique stage tracks", flush=True)
    if len({item["sha256"] for item in results}) != len(results):
        raise ValueError("Duplicate audio content found")
    (ROOT / "tools" / "music" / "audio-validation.json").write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Validated {len(results)} distinct files, {sum(item['bytes'] for item in results) / 1048576:.1f} MiB", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["discover", "fetch", "inspect"])
    parser.add_argument("url", nargs="?")
    args = parser.parse_args()
    if args.command == "discover":
        discover()
    elif args.command == "fetch":
        fetch()
    else:
        print(json.dumps(inspect_page(args.url), ensure_ascii=False, indent=2))
