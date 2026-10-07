"""Read the official ZIP directory and download only the Windows release template."""
import io
import struct
import urllib.request
import zipfile
import zlib
from pathlib import Path

url = 'https://godot-releases.nbg1.your-objectstorage.com/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz'

def request_range(start, end):
    req = urllib.request.Request(url, headers={'Range': f'bytes={start}-{end}', 'User-Agent': 'KotobaSengoku-build/1.0'})
    with urllib.request.urlopen(req, timeout=120) as response:
        if response.status != 206:
            raise RuntimeError(f'Range not supported: {response.status}')
        return response.read()

with urllib.request.urlopen(urllib.request.Request(url, method='HEAD'), timeout=30) as response:
    size = int(response.headers['Content-Length'])
tail = request_range(size - 65557, size - 1)
eocd = tail.rfind(b'PK\x05\x06')
if eocd < 0:
    raise RuntimeError('ZIP directory missing')
record = struct.unpack_from('<4s4H2IH', tail, eocd)
directory_size, directory_offset = record[5:7]
directory = request_range(directory_offset, directory_offset + directory_size - 1)
cursor = 0
entries = []
while cursor < len(directory):
    fields = struct.unpack_from('<4s6H3I5H2I', directory, cursor)
    if fields[0] != b'PK\x01\x02':
        raise RuntimeError('Invalid ZIP directory')
    name_len, extra_len, comment_len = fields[10:13]
    name = directory[cursor + 46:cursor + 46 + name_len].decode('utf-8')
    if name.endswith('windows_release_x86_64.exe'):
        entries.append((name, fields[4], fields[7], fields[8], fields[9], fields[16]))
    cursor += 46 + name_len + extra_len + comment_len
if len(entries) != 1:
    raise RuntimeError(f'Unexpected Windows release entries: {entries}')
name, method, crc, packed_size, unpacked_size, offset = entries[0]
header = request_range(offset, offset + 29)
local = struct.unpack('<4s5H3I2H', header)
start = offset + 30 + local[9] + local[10]
packed = request_range(start, start + packed_size - 1)
data = zlib.decompress(packed, -15) if method == 8 else packed
if len(data) != unpacked_size or zlib.crc32(data) != crc:
    raise RuntimeError('Template size or checksum mismatch')
target = Path(__file__).resolve().parent / 'godot' / 'windows_release_x86_64.exe'
target.write_bytes(data)
print(f'Official template verified: {name}, {len(data):,} bytes; downloaded {packed_size:,} of {size:,}')
