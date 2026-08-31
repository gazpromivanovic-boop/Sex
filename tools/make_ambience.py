"""Синтезирует звуковую подложку лобби в assets/audio/.

    blender --background --factory-startup --python tools/make_ambience.py

Запускается через Blender ради numpy — в системном питоне его нет, а больше
ничего от Blender здесь не нужно.

Почему синтез, а не запись: скачивать звук из интернета я не могу, а лицензия у
звука важна не меньше, чем у кода. Синтезированный прибой при этом звучит
достойно — это шум, огибающая которого дышит набегом волн, и ухо принимает его
за море. С чайками сложнее: синтетический крик слышно, что синтетический,
поэтому это заведомо временная затычка под настоящую запись.

Все петли бесшовные: длина кратна периодам всех модуляций, а стык дополнительно
сшивается кроссфейдом — иначе на повторе слышен щелчок.
"""

import math
import os
import struct
import wave

import numpy as np

RATE = 44100
OUT_DIR = "assets/audio"


def write_wav(path, left, right):
    """Пишем 16 бит стерео. Нормируем с запасом: клиппинг на прибое слышно
    сразу, он превращается в треск."""
    peak = max(float(np.max(np.abs(left))), float(np.max(np.abs(right))), 1e-6)
    scale = 0.89 / peak
    data = np.empty(left.size * 2, dtype=np.int16)
    data[0::2] = np.clip(left * scale * 32767.0, -32768, 32767).astype(np.int16)
    data[1::2] = np.clip(right * scale * 32767.0, -32768, 32767).astype(np.int16)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as f:
        f.setnchannels(2)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(data.tobytes())
    print("### %-28s %5.1f с, %5.2f МБ" % (os.path.basename(path),
          left.size / RATE, os.path.getsize(path) / 1048576.0))


def seam(x, fade=0.35):
    """Сшивает конец с началом кроссфейдом: без этого петля щёлкает на стыке."""
    n = int(fade * RATE)
    if n * 2 >= x.size:
        return x
    ramp = np.linspace(0.0, 1.0, n)
    out = x.copy()
    out[:n] = x[:n] * ramp + x[-n:] * (1.0 - ramp)
    return out[:-n]


def brown_noise(n, rng):
    """Коричневый шум: интеграл белого. У него завал верхов, поэтому он гудит
    морем, а не шипит телевизором."""
    w = rng.standard_normal(n)
    b = np.cumsum(w)
    b -= np.linspace(b[0], b[-1], n)      # убираем уползание постоянной составляющей
    return b / (np.max(np.abs(b)) + 1e-9)


def lowpass(x, cutoff):
    """Однополюсный фильтр. Точности тут не нужно, нужен характер."""
    a = math.exp(-2.0 * math.pi * cutoff / RATE)
    out = np.empty_like(x)
    acc = 0.0
    for i in range(x.size):
        acc = a * acc + (1.0 - a) * x[i]
        out[i] = acc
    return out


def lowpass_fast(x, cutoff):
    """То же самое, но через частотную область: цикл на миллионах отсчётов
    в питоне идёт минуты."""
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(x.size, 1.0 / RATE)
    spec *= 1.0 / (1.0 + (freqs / cutoff) ** 2)
    return np.fft.irfft(spec, n=x.size)


def highpass_fast(x, cutoff):
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(x.size, 1.0 / RATE)
    k = (freqs / cutoff) ** 2
    spec *= k / (1.0 + k)
    return np.fft.irfft(spec, n=x.size)


def make_surf(seconds=24.0, seed=7):
    """Прибой: широкий шум плюс набеги волн. Периоды набегов делят длину петли
    нацело, иначе на стыке волна обрывается на середине."""
    rng = np.random.default_rng(seed)
    n = int(seconds * RATE)
    t = np.arange(n) / RATE

    body = lowpass_fast(brown_noise(n, rng), 900.0)
    spray = highpass_fast(lowpass_fast(brown_noise(n, rng), 6000.0), 1200.0)

    # три набега разной длины: одиночный период звучит метрономом
    swell = np.zeros(n)
    for period, weight in ((seconds / 3.0, 1.0), (seconds / 5.0, 0.6),
                           (seconds / 8.0, 0.35)):
        phase = 2.0 * math.pi * t / period
        swell += weight * (0.5 + 0.5 * np.sin(phase))
    swell /= 1.95
    # степень делает подъём волны крутым, а откат долгим — как на берегу
    swell = swell ** 1.8

    left = body * (0.35 + 0.65 * swell) + spray * (0.10 + 0.55 * swell ** 2)
    # правый канал — свой шум, иначе стерео схлопывается в точку посередине
    rng2 = np.random.default_rng(seed + 1)
    body_r = lowpass_fast(brown_noise(n, rng2), 900.0)
    spray_r = highpass_fast(lowpass_fast(brown_noise(n, rng2), 6000.0), 1200.0)
    right = body_r * (0.35 + 0.65 * swell) + spray_r * (0.10 + 0.55 * swell ** 2)

    return seam(left), seam(right)


def make_wind(seconds=18.0, seed=21):
    """Ветер: узкая полоса шума, медленно дышащая по громкости."""
    rng = np.random.default_rng(seed)
    n = int(seconds * RATE)
    t = np.arange(n) / RATE
    core = highpass_fast(lowpass_fast(brown_noise(n, rng), 2200.0), 260.0)
    gust = 0.55 + 0.45 * (0.5 + 0.5 * np.sin(2.0 * math.pi * t / (seconds / 2.0)))
    gust *= 0.7 + 0.3 * (0.5 + 0.5 * np.sin(2.0 * math.pi * t / (seconds / 3.0)))
    left = core * gust
    right = highpass_fast(lowpass_fast(brown_noise(n, np.random.default_rng(seed + 1)),
                                       2200.0), 260.0) * gust
    return seam(left), seam(right)


def make_gull(index, seed=101):
    """Крик чайки. Слышно, что синтетика — это временная затычка под запись.

    Устройство: пила с быстрым подъёмом и спадом высоты, поверх — хрип из
    шума. Чистый тон звучал бы флейтой, а не птицей.
    """
    rng = np.random.default_rng(seed + index * 13)
    dur = 0.42 + 0.18 * rng.random()
    n = int(dur * RATE)
    t = np.arange(n) / RATE

    base = 900.0 + 260.0 * rng.random()
    bend = np.interp(t, [0.0, dur * 0.18, dur * 0.55, dur],
                     [0.75, 1.35, 1.0, 0.62])
    phase = 2.0 * math.pi * np.cumsum(base * bend) / RATE
    tone = np.zeros(n)
    for harm, amp in ((1, 1.0), (2, 0.55), (3, 0.32), (4, 0.16)):
        tone += amp * np.sin(phase * harm)
    rasp = 1.0 + 0.35 * lowpass_fast(rng.standard_normal(n), 90.0)
    env = np.interp(t, [0.0, dur * 0.06, dur * 0.5, dur], [0.0, 1.0, 0.75, 0.0])
    voice = tone * rasp * env
    voice = lowpass_fast(voice, 5200.0)

    pan = 0.35 + 0.3 * rng.random()
    return voice * (1.0 - pan), voice * pan


def main():
    l, r = make_surf()
    write_wav(os.path.join(OUT_DIR, "surf_loop.wav"), l, r)
    l, r = make_wind()
    write_wav(os.path.join(OUT_DIR, "wind_loop.wav"), l, r)
    for i in range(3):
        l, r = make_gull(i)
        write_wav(os.path.join(OUT_DIR, "gull_%d.wav" % (i + 1)), l, r)


if __name__ == "__main__":
    main()
