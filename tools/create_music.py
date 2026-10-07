"""Original pentatonic plucked-string and drum loop; no recordings used."""
import math
import random
import struct
import wave
from pathlib import Path

rate = 22050
bpm = 82
beat = 60 / bpm
length = beat * 64
audio = [0.0] * int((length + 1.5) * rate)
rng = random.Random(21)
scale = [50, 53, 55, 57, 60, 62, 65, 67, 69]
melody = [0, 2, 4, 3, 2, 1, 0, 2, 4, 6, 5, 4, 2, 3, 1, 0]

def pluck(start, midi, duration, volume):
    frequency = 440 * 2 ** ((midi - 69) / 12)
    count = int(duration * rate)
    offset = int(start * rate)
    for i in range(count):
        t = i / rate
        envelope = math.exp(-t * 3.3) * min(1, t * 500)
        signal = sum(math.sin(2 * math.pi * frequency * harmonic * t) / harmonic ** 1.6 for harmonic in range(1, 6))
        idx = offset + i
        if idx < len(audio):
            audio[idx] += signal * envelope * volume

def drum(start, volume):
    offset = int(start * rate)
    for i in range(int(rate * 0.45)):
        t = i / rate
        signal = math.sin(2 * math.pi * (70 * t + 23 * (1 - math.exp(-t * 12)) / 12))
        signal += rng.uniform(-1, 1) * math.exp(-t * 65) * 0.65
        audio[offset + i] += signal * math.exp(-t * 10) * volume

for bar in range(16):
    base = bar * 4 * beat
    root = [38, 41, 43, 38][bar % 4]
    pluck(base, root, 3.4, 0.18)
    for pos in range(4):
        index = melody[(bar * 4 + pos) % len(melody)]
        pluck(base + pos * beat, scale[index], 1.9, 0.24 if pos % 2 == 0 else 0.16)
        if pos in (0, 2):
            drum(base + pos * beat, 0.15 if pos == 0 else 0.09)
    if bar % 4 == 3:
        pluck(base + 3.5 * beat, 74, 1.1, 0.10)

audio = audio[:int(length * rate)]
fade = int(rate * 0.8)
for i in range(fade):
    audio[i] *= i / fade
    audio[-i-1] *= i / fade
target = Path(__file__).resolve().parents[1] / 'assets' / 'bgm.wav'
with wave.open(str(target), 'wb') as out:
    out.setnchannels(1)
    out.setsampwidth(2)
    out.setframerate(rate)
    out.writeframes(b''.join(struct.pack('<h', max(-32767, min(32767, int(x * 23000)))) for x in audio))
print(f'Original loop: {length:.1f}s, {target.stat().st_size} bytes')
