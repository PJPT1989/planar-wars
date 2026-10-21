#!/usr/bin/env python3
"""Generates the background music in music/: a title theme and one theme per race.

Everything is synthesised here with numpy (additive instruments, plucks, drums and a
convolution reverb) and encoded to Ogg Vorbis with ffmpeg. Each track is one seamless loop:
whatever rings past the end (note tails, reverb) is folded back onto the start.

    python3 tools/gen_music.py              # all tracks
    python3 tools/gen_music.py ravnica      # some tracks
    python3 tools/gen_music.py --wav        # also write /tmp/pw-music/<name>.wav
"""
import functools
import os
import subprocess
import sys

import numpy as np

SR = 32000
NYQ = SR * 0.45
TAIL = 10.0          # seconds of buffer past the loop for ringing notes
TARGET_RMS = 0.13    # every track is levelled to this before the limiter
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "music")

rng = np.random.default_rng(7)

# --- pitches -------------------------------------------------------------------------------

NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def midi(name):
	"""'C#4', 'Bb2' -> midi number."""
	n = NOTE[name[0]]
	i = 1
	while i < len(name) and name[i] in "#b":
		n += 1 if name[i] == "#" else -1
		i += 1
	return n + 12 * (int(name[i:]) + 1)


def hz(m):
	return 440.0 * 2.0 ** ((m - 69) / 12.0)


CHORDS = {"": [0, 4, 7], "m": [0, 3, 7], "dim": [0, 3, 6], "sus": [0, 5, 7], "5": [0, 7], "7": [0, 4, 7, 10]}


def chord(name, low):
	"""'Dm', 'Bb', 'Bdim' -> midi notes of the chord, the root at or above the midi note `low`."""
	r = NOTE[name[0]]
	q = name[1:]
	if q[:1] in ("#", "b"):
		r += 1 if q[0] == "#" else -1
		q = q[1:]
	m = low + (r - low) % 12
	return [m + s for s in CHORDS[q]]


# --- signal helpers ------------------------------------------------------------------------

def times(n):
	return np.arange(n) / SR


def band(x, lo, hi, soft=0.25):
	"""Band-pass by FFT with soft edges (lo/hi in Hz, 0 or None for no edge)."""
	X = np.fft.rfft(x)
	f = np.fft.rfftfreq(len(x), 1.0 / SR)
	g = np.ones_like(f)
	if lo:
		g *= 1.0 / (1.0 + (lo / np.maximum(f, 1.0)) ** (2.0 / soft))
	if hi:
		g *= 1.0 / (1.0 + (f / hi) ** (2.0 / soft))
	return np.fft.irfft(X * g, len(x))


def noise(n):
	return rng.standard_normal(n)


def envelope(n, att, dur, rel, curve=1.0):
	"""Attack, hold until dur, then an exponential release over rel."""
	t = times(n)
	e = np.minimum(1.0, t / max(att, 1e-4)) ** curve
	after = t > dur
	e[after] *= np.exp(-(t[after] - dur) / max(rel / 5.0, 1e-3))
	e[-min(n, 64):] *= np.linspace(1, 0, min(n, 64))
	return e


def additive(freq, dur, amps, decays=None, att=0.01, rel=0.3, vib=0.0, vib_rate=5.0, vib_delay=0.3,
		glide_from=None, glide_t=0.09, cents=0.0, inharm=0.0, hold=True, length=None, seed=0):
	"""Sum of harmonics k*freq with amplitudes amps[k-1] (and per-harmonic decay rates)."""
	n = int((length if length else dur + rel) * SR)
	t = times(n)
	f = np.full(n, freq * 2.0 ** (cents / 1200.0))
	if glide_from:
		s = np.clip(t / glide_t, 0.0, 1.0)
		s = s * s * (3 - 2 * s)
		f *= (glide_from / freq) ** (1.0 - s)
	if vib:
		f *= 1.0 + vib * np.sin(2 * np.pi * vib_rate * t) * np.clip((t - vib_delay) / 0.4, 0.0, 1.0)
	phase = 2 * np.pi * np.cumsum(f) / SR
	r = np.random.default_rng(seed)
	out = np.zeros(n)
	for k, a in enumerate(amps, 1):
		ratio = k * np.sqrt(1.0 + inharm * k * k)
		if ratio * freq > NYQ or a == 0:
			continue
		p = np.sin(phase * ratio + r.uniform(0, 2 * np.pi)) * a
		if decays is not None:
			p *= np.exp(-t * decays[k - 1])
		out += p
	if hold:
		out *= envelope(n, att, dur, rel)
	else:
		e = np.minimum(1.0, t / max(att, 1e-4))
		e[-min(n, 256):] *= np.linspace(1, 0, min(n, 256))
		out *= e
	return out


def saw(count, power=1.0):
	return [1.0 / k ** power for k in range(1, count + 1)]


def formant(freq, count, peaks):
	"""Harmonic amplitudes shaped by vowel formants [(centre Hz, width Hz, gain)]."""
	a = []
	for k in range(1, count + 1):
		fk = k * freq
		g = 0.05 / k
		for c, w, gain in peaks:
			g += gain * np.exp(-((fk - c) / w) ** 2)
		a.append(g)
	return a


AH = [(700, 160, 1.0), (1150, 200, 0.5), (2600, 300, 0.18)]
OO = [(330, 120, 1.0), (800, 180, 0.35), (2300, 300, 0.05)]

# --- instruments (each returns a mono signal; cached by its arguments) ---------------------


@functools.lru_cache(maxsize=None)
def strings(m, dur, bright=1.0):
	f = hz(m)
	amps = [a * (0.82 ** ((k) * (1.4 - bright))) for k, a in enumerate(saw(28), 1)]
	s = 0
	for i, c in enumerate((-7.0, 6.0)):
		s = s + additive(f, dur, amps, att=0.28, rel=0.7, vib=0.004, vib_rate=5.1 + i * 0.4, vib_delay=0.25, cents=c, seed=m * 3 + i)
	return s * 0.25


@functools.lru_cache(maxsize=None)
def choir(m, dur, vowel="ah"):
	f = hz(m)
	amps = formant(f, 30, AH if vowel == "ah" else OO)
	s = 0
	for i, c in enumerate((-9.0, 0.0, 8.0)):
		s = s + additive(f, dur, amps, att=0.45, rel=0.9, vib=0.005, vib_rate=4.6 + i * 0.5, vib_delay=0.1, cents=c, seed=m * 5 + i)
	return s * 0.22


@functools.lru_cache(maxsize=None)
def horn(m, dur):
	f = hz(m)
	n = int((dur + 0.35) * SR)
	t = times(n)
	out = np.zeros(n)
	# brightness opens with the attack: higher harmonics come in later
	for k in range(1, 18):
		if k * f > NYQ:
			break
		a = 1.0 / k ** 1.25
		swell = np.clip(t / (0.04 + 0.012 * k), 0, 1)
		out += a * swell * np.sin(2 * np.pi * k * f * t + k)
	vib = 1 + 0.004 * np.sin(2 * np.pi * 5.0 * t) * np.clip((t - 0.35) / 0.4, 0, 1)
	out *= vib * envelope(n, 0.05, dur, 0.35)
	return out * 0.35


@functools.lru_cache(maxsize=None)
def flute(m, dur):
	f = hz(m)
	s = additive(f, dur, [1.0, 0.3, 0.12, 0.05, 0.02], att=0.07, rel=0.25, vib=0.006, vib_rate=5.3, vib_delay=0.2, seed=m)
	n = len(s)
	breath = band(noise(n), f * 0.8, f * 2.5) * 0.07
	return (s + breath * envelope(n, 0.05, dur, 0.2)) * 0.45


@functools.lru_cache(maxsize=None)
def bass(m, dur):
	f = hz(m)
	amps = [1.0, 0.45, 0.25, 0.12, 0.06, 0.03]
	return additive(f, dur, amps, decays=[0.3, 0.8, 1.6, 2.5, 3.5, 4.5], att=0.012, rel=0.25, seed=m) * 0.55


@functools.lru_cache(maxsize=None)
def pluck(m, dur, bright=1.0, ring=1.0):
	"""Harp / lute: harmonics that die faster the higher they are."""
	f = hz(m)
	amps = [1.0 / k ** (1.6 - 0.5 * bright) for k in range(1, 26)]
	dec = [(1.2 + 0.35 * k * k * (0.002 * f / 4.0 + 0.05)) / ring for k in range(1, 26)]
	n_len = min(dur + 1.6 * ring, 6.0)
	s = additive(f, dur, amps, decays=dec, att=0.003, hold=False, length=n_len, inharm=0.00004, seed=m)
	return s * 0.5


@functools.lru_cache(maxsize=None)
def harpsichord(m, dur):
	f = hz(m)
	amps = [(1.0 / k ** 0.75) * (0.35 if k % 7 == 0 else 1.0) for k in range(1, 30)]
	dec = [2.0 + 0.4 * k for k in range(1, 30)]
	return additive(f, dur, amps, decays=dec, att=0.002, hold=False, length=min(dur + 1.0, 3.0), seed=m) * 0.22


@functools.lru_cache(maxsize=None)
def sitar(m, dur, glide=None):
	"""Bright buzzing pluck that can slide in from the previous note."""
	f = hz(m)
	k = np.arange(1, 40)
	amps = list(1.0 / k ** 0.9 * (1 + 0.6 * np.sin(k * 1.7)))
	dec = list(1.0 + 0.09 * k)
	s = additive(f, dur, amps, decays=dec, att=0.004, hold=False, length=min(dur + 1.2, 4.0),
			glide_from=hz(glide) if glide is not None else None, glide_t=0.12, vib=0.003, vib_rate=6.0, vib_delay=0.4, seed=m)
	return s * 0.17


@functools.lru_cache(maxsize=None)
def santoor(m):
	f = hz(m)
	s = 0
	for c in (-4.0, 4.0):
		s = s + additive(f, 0.1, [1.0, 0.5, 0.3, 0.2, 0.1, 0.06], decays=[2.2, 3.0, 4.0, 5.5, 7.0, 9.0],
				att=0.002, hold=False, length=2.0, cents=c, seed=m)
	return s * 0.2


@functools.lru_cache(maxsize=None)
def tanpura(m, dur):
	"""Drone string: the buzz (upper harmonics) blooms after the pluck."""
	f = hz(m)
	n = int((dur + 1.5) * SR)
	t = times(n)
	out = np.zeros(n)
	for k in range(1, 30):
		if k * f > NYQ:
			break
		bloom = 1.0 if k < 4 else 0.25 + 0.75 * np.sin(np.pi * np.clip(t / (dur + 1.0), 0, 1)) ** 0.5
		out += (1.0 / k ** 0.8) * bloom * np.sin(2 * np.pi * k * f * t + k * 0.7)
	out *= np.exp(-t * 0.5) * np.minimum(1, t / 0.01)
	out[-256:] *= np.linspace(1, 0, 256)
	return out * 0.12


BELL = [(0.5, 1.0, 0.6), (1.0, 1.0, 1.0), (1.19, 0.6, 1.4), (1.56, 0.5, 1.8), (2.0, 0.45, 2.2), (2.51, 0.3, 3.0), (2.66, 0.25, 3.2), (3.01, 0.2, 3.8), (4.1, 0.12, 5.0)]


@functools.lru_cache(maxsize=None)
def bell(m, length=4.0):
	f = hz(m)
	n = int(length * SR)
	t = times(n)
	out = np.zeros(n)
	for ratio, a, d in BELL:
		if ratio * f < NYQ:
			out += a * np.exp(-t * d * 0.8) * np.sin(2 * np.pi * ratio * f * t)
	out *= np.minimum(1, t / 0.002)
	out[-256:] *= np.linspace(1, 0, 256)
	return out * 0.18


@functools.lru_cache(maxsize=None)
def metal(m, length=1.6, seed=1):
	"""Inharmonic clang (Phyrexian machinery)."""
	f = hz(m)
	r = np.random.default_rng(seed)
	n = int(length * SR)
	t = times(n)
	out = np.zeros(n)
	for i in range(14):
		ratio = 1.0 + i * 0.73 + r.uniform(-0.2, 0.2)
		if ratio * f > NYQ:
			continue
		out += r.uniform(0.3, 1.0) / (1 + i * 0.4) * np.exp(-t * (3.0 + i * 1.2)) * np.sin(2 * np.pi * ratio * f * t)
	click = band(noise(n), 2000, 9000) * np.exp(-t * 60)
	out = out + click * 0.4
	out[-256:] *= np.linspace(1, 0, 256)
	return out * 0.16


# --- drums ---------------------------------------------------------------------------------

@functools.lru_cache(maxsize=None)
def taiko(pitch=1.0, length=1.4):
	n = int(length * SR)
	t = times(n)
	f = 48 * pitch + 70 * pitch * np.exp(-t * 18)
	body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 3.2)
	skin = band(noise(n), 60, 900) * np.exp(-t * 28) * 0.5
	out = (body + skin) * np.minimum(1, t / 0.002)
	out[-256:] *= np.linspace(1, 0, 256)
	return out * 0.55


@functools.lru_cache(maxsize=None)
def kick(length=0.5):
	n = int(length * SR)
	t = times(n)
	f = 45 + 90 * np.exp(-t * 30)
	out = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 7) + band(noise(n), 1000, 5000) * np.exp(-t * 90) * 0.15
	out[-128:] *= np.linspace(1, 0, 128)
	return out * 0.5


@functools.lru_cache(maxsize=None)
def frame_drum(pitch=1.0):
	n = int(0.7 * SR)
	t = times(n)
	f = 78 * pitch + 30 * pitch * np.exp(-t * 25)
	out = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 6) + band(noise(n), 200, 2500) * np.exp(-t * 35) * 0.35
	out[-128:] *= np.linspace(1, 0, 128)
	return out * 0.4


@functools.lru_cache(maxsize=None)
def snare(length=0.4):
	n = int(length * SR)
	t = times(n)
	out = band(noise(n), 900, 7000) * np.exp(-t * 16) * 0.6 + np.sin(2 * np.pi * 190 * t) * np.exp(-t * 25) * 0.4
	out[-128:] *= np.linspace(1, 0, 128)
	return out * 0.28


@functools.lru_cache(maxsize=None)
def shaker(length=0.12):
	n = int(length * SR)
	t = times(n)
	out = band(noise(n), 5000, 12000) * np.minimum(1, t / 0.01) * np.exp(-t * 40)
	out[-64:] *= np.linspace(1, 0, 64)
	return out * 0.18


@functools.lru_cache(maxsize=None)
def swell(length=2.0):
	"""Cymbal or steam rising into a downbeat."""
	n = int(length * SR)
	t = times(n)
	out = band(noise(n), 3000, 12000) * (t / length) ** 2.5
	out[-128:] *= np.linspace(1, 0, 128)
	return out * 0.12


@functools.lru_cache(maxsize=None)
def tabla(bol):
	"""Tabla strokes: 'na'/'tin' ring on the treble drum, 'ge' bends on the bass drum."""
	n = int(0.9 * SR)
	t = times(n)
	out = np.zeros(n)
	if bol in ("na", "tin", "dha", "dhin", "ta"):
		f = 560.0
		damp = 9.0 if bol in ("na", "ta", "dha") else 5.0
		for k, a in ((1, 1.0), (2, 0.55), (3, 0.35), (4, 0.15)):
			out += a * np.sin(2 * np.pi * f * k * t) * np.exp(-t * damp * (0.8 + 0.3 * k))
		out += band(noise(n), 2000, 8000) * np.exp(-t * 80) * 0.3
	if bol in ("ge", "dha", "dhin"):
		f = 95 + 25 * np.clip(t / 0.15, 0, 1)
		out += 1.2 * np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 4.0)
	out *= np.minimum(1, t / 0.002)
	out[-128:] *= np.linspace(1, 0, 128)
	return out * 0.3


# --- the song buffer -----------------------------------------------------------------------

class Song:
	def __init__(self, bpm, beats_per_bar, bars, room=2.4, dark=0.5):
		self.beat = 60.0 / bpm
		self.bpb = beats_per_bar
		self.bars = bars
		self.length = bars * beats_per_bar * self.beat
		self.n = int(round(self.length * SR))
		size = self.n + int(TAIL * SR)
		self.dry = np.zeros((2, size))
		self.send = np.zeros((2, size))
		self.room = room
		self.dark = dark

	def t(self, bar, beat=0.0):
		return (bar * self.bpb + beat) * self.beat

	def add(self, sig, time, pan=0.0, gain=1.0, rev=0.3, jitter=0.0):
		if jitter:
			time += rng.uniform(-jitter, jitter)
		i = int(round(time * SR)) % self.n
		sig = sig[: self.dry.shape[1] - i]
		a = (pan + 1.0) * np.pi / 4.0
		for ch, g in ((0, np.cos(a)), (1, np.sin(a))):
			self.dry[ch, i: i + len(sig)] += sig * gain * g * 1.41421
			self.send[ch, i: i + len(sig)] += sig * gain * g * 1.41421 * rev

	def render(self):
		ir = impulse(self.room, self.dark)
		size = self.dry.shape[1] + ir.shape[1]
		nfft = 1 << (size - 1).bit_length()
		mix = np.zeros((2, size))
		mix[:, : self.dry.shape[1]] += self.dry
		for ch in range(2):
			wet = np.fft.irfft(np.fft.rfft(self.send[ch], nfft) * np.fft.rfft(ir[ch], nfft), nfft)[:size]
			mix[ch] += wet
		# fold everything past the loop point back onto the start
		out = np.zeros((2, self.n))
		for s in range(0, size, self.n):
			seg = mix[:, s: s + self.n]
			out[:, : seg.shape[1]] += seg
		out *= TARGET_RMS / np.sqrt(np.mean(out ** 2))
		return np.tanh(out * 1.1) / np.tanh(1.1)


def impulse(seconds, dark):
	"""Stereo reverb impulse: decaying noise, darker as it fades."""
	n = int(seconds * SR)
	t = times(n)
	ir = np.zeros((2, n))
	for ch in range(2):
		bright = band(noise(n), 150, 7000) * np.exp(-t * 6.9 / (seconds * 0.55))
		warm = band(noise(n), 100, 2500 * (1.2 - dark)) * np.exp(-t * 6.9 / seconds)
		x = bright * (1.0 - dark) + warm
		x[: int(0.018 * SR)] = 0.0
		x *= np.minimum(1, t / 0.03)
		ir[ch] = x / np.sqrt(np.sum(x ** 2))
	return ir


# --- writing music -------------------------------------------------------------------------

def parse(text):
	"""'D4:1.5 r:1 A#4:0.5 | ...' -> [(midi or None, beats)]."""
	out = []
	for tok in text.replace("|", " ").split():
		name, beats = tok.split(":")
		out.append((None if name == "r" else midi(name), float(beats)))
	return out


def line(song, play, text, bar, gain=1.0, pan=0.0, rev=0.3, legato=1.0, shift=0, jitter=0.004, glide=False):
	"""Plays a melody from `bar`; `play(midi, seconds[, prev])` makes each note."""
	beat = 0.0
	prev = None
	for m, beats in parse(text):
		if m is not None:
			m += shift
			dur = round(beats * song.beat * legato, 3)
			if glide:
				sig = play(m, dur, prev if prev is not None and prev != m else None)
			else:
				sig = play(m, dur)
			song.add(sig, song.t(bar, beat), pan, gain, rev, jitter)
			prev = m
		beat += beats
	return beat / song.bpb


def pads(song, play, chords, bar, bars_each=1, low=midi("D3"), gain=1.0, rev=0.45, spread=0.5, extra_octave=True):
	"""Holds each chord for bars_each bars."""
	for i, c in enumerate(chords.split()):
		notes = chord(c, low)
		if extra_octave:
			notes = notes + [notes[0] + 12]
		dur = round(bars_each * song.bpb * song.beat, 3)
		for j, m in enumerate(notes):
			pan = (j / max(1, len(notes) - 1) - 0.5) * 2 * spread
			song.add(play(m, dur), song.t(bar + i * bars_each), pan, gain / len(notes) ** 0.5, rev)


def drums(song, pattern, bar, bars, hit, gain=1.0, pan=0.0, rev=0.2, jitter=0.005, accent="X"):
	"""Step pattern for one bar: 'X' accent, 'x' hit, '.' rest; repeated for `bars` bars."""
	steps = len(pattern)
	for b in range(bars):
		for i, ch in enumerate(pattern):
			if ch in "xX":
				g = gain * (1.0 if ch == accent else 0.6) * rng.uniform(0.85, 1.0)
				song.add(hit, song.t(bar + b, i * song.bpb / steps), pan, g, rev, jitter)


def arp(song, play, chords, bar, pattern, low, gain=1.0, pan=0.0, rev=0.35, bars_each=1, note_beats=None, spread=0.0):
	"""Broken chords: pattern is a list of chord-tone indexes (index 3+ goes up octaves)."""
	steps = len(pattern)
	step_beats = song.bpb * bars_each / steps
	for i, c in enumerate(chords.split()):
		notes = chord(c, low)
		for s, idx in enumerate(pattern):
			if idx is None:
				continue
			m = notes[idx % len(notes)] + 12 * (idx // len(notes))
			dur = round((note_beats or step_beats) * song.beat, 3)
			p = pan + (spread * (idx / 4.0 - 0.5) if spread else 0.0)
			song.add(play(m, dur), song.t(bar + i * bars_each, s * step_beats), p, gain * rng.uniform(0.85, 1.0), rev, 0.004)


def bassline(song, chords, bar, rhythm, low=midi("D2"), gain=1.0, bars_each=1, play=None):
	"""rhythm: [(beat, beats, chord tone index)] per bar."""
	play = play or bass
	for i, c in enumerate(chords.split()):
		notes = chord(c, low)
		for b in range(bars_each):
			for beat, beats, idx in rhythm:
				m = notes[idx % len(notes)] + 12 * (idx // len(notes))
				song.add(play(m, round(beats * song.beat, 3)), song.t(bar + i * bars_each + b, beat), 0.0, gain, 0.1, 0.003)


# --- the tracks ----------------------------------------------------------------------------

def title():
	"""Main theme: a slow, wide D minor march with horns, strings, choir and taiko."""
	s = Song(76, 4, 32, room=3.0, dark=0.45)
	A = "Dm Bb F C Dm Bb Gm A"
	B = "Bb C Dm Dm Gm Bb C A"
	theme = ("D4:1.5 E4:0.5 F4:1 A4:1 | Bb4:2 A4:1 F4:1 | C5:1.5 A4:0.5 F4:1 G4:1 | E4:3 r:1 |"
			" D4:1.5 E4:0.5 F4:1 A4:1 | D5:2 C5:1 Bb4:1 | Bb4:1 A4:1 G4:1 Bb4:1 | A4:3 r:1")
	high = ("F5:2 D5:1 F5:1 | G5:2 E5:1 C5:1 | A5:3 G5:0.5 F5:0.5 | E5:1 F5:1 D5:2 |"
			" Bb4:1.5 D5:0.5 G5:2 | F5:1.5 D5:0.5 Bb4:2 | C5:1 D5:1 E5:1 G5:1 | A5:2 E5:1 C#5:1")
	# 0-7: intro, pads and choir only
	pads(s, strings, A, 0, low=midi("D3"), gain=0.8)
	pads(s, lambda m, d: choir(m, d, "oo"), A, 0, low=midi("A3"), gain=0.5, extra_octave=False)
	bassline(s, A, 0, [(0, 4, 0)], low=midi("D2"), gain=0.7)
	for b in (3, 7):
		s.add(swell(s.beat * 4), s.t(b), 0, 1.0, 0.4)
	drums(s, "X.......", 0, 8, taiko(0.9), gain=0.8, rev=0.35)
	# 8-15: the theme on horns over a string ostinato
	line(s, horn, theme, 8, gain=0.9, pan=-0.1, rev=0.35)
	line(s, horn, theme, 8, gain=0.45, pan=0.2, rev=0.35, shift=-12)
	arp(s, lambda m, d: strings(m, d, 1.2), A, 8, [0, 2, 1, 2, 0, 2, 1, 2], midi("D3"), gain=0.55, pan=0.25, spread=0.4)
	pads(s, strings, A, 8, low=midi("D3"), gain=0.45)
	bassline(s, A, 8, [(0, 1.5, 0), (1.5, 0.5, 0), (2, 2, 2)], low=midi("D2"), gain=0.8)
	drums(s, "X..x.xx.X..x.x..", 8, 8, taiko(1.0), gain=0.85, rev=0.3)
	drums(s, "....x.......x...", 8, 8, snare(), gain=0.5, rev=0.3)
	s.add(swell(s.beat * 4), s.t(15), 0, 1.0, 0.4)
	# 16-23: the higher second strain on strings and flute, choir under it
	line(s, lambda m, d: strings(m, d, 1.3), high, 16, gain=0.95, pan=-0.15, rev=0.4)
	line(s, flute, high, 16, gain=0.5, pan=0.3, rev=0.45)
	pads(s, choir, B, 16, low=midi("A3"), gain=0.7)
	arp(s, harpsichord_soft, B, 16, [0, 1, 2, 3, 2, 1, 0, 1], midi("D4"), gain=0.6, pan=0.4)
	bassline(s, B, 16, [(0, 1, 0), (1, 1, 0), (2, 1, 2), (3, 1, 0)], low=midi("D2"), gain=0.8)
	drums(s, "X...x...X...x.x.", 16, 8, taiko(1.0), gain=0.85, rev=0.3)
	drums(s, "..x...x...x...x.", 16, 8, shaker(), gain=0.8)
	s.add(swell(s.beat * 4), s.t(23), 0, 1.3, 0.4)
	# 24-31: everything; the last two bars thin out to lead back to the intro
	line(s, horn, theme, 24, gain=1.0, pan=-0.1, rev=0.35)
	line(s, horn, theme, 24, gain=0.5, pan=0.15, rev=0.35, shift=-12)
	line(s, flute, theme, 24, gain=0.35, pan=0.35, rev=0.45, shift=12)
	pads(s, choir, A, 24, low=midi("A3"), gain=0.6)
	pads(s, strings, A, 24, low=midi("D3"), gain=0.5)
	bassline(s, A, 24, [(0, 1.5, 0), (1.5, 0.5, 0), (2, 2, 2)], low=midi("D2"), gain=0.85)
	drums(s, "X..x.xx.X..x.xxx", 24, 6, taiko(1.0), gain=0.9, rev=0.3)
	drums(s, "....x.......x...", 24, 6, snare(), gain=0.55, rev=0.3)
	drums(s, "X.......X.......", 30, 2, taiko(0.85), gain=0.8, rev=0.35)
	s.add(bell(midi("A4"), 5.0), s.t(31), 0.2, 0.6, 0.5)
	return s


@functools.lru_cache(maxsize=None)
def harpsichord_soft(m, dur):
	return pluck(m, dur, 0.6, 0.8) * 0.8


def phyrexia():
	"""Cold machinery: a C phrygian drone, clanking metal ostinato, low brass and a choir."""
	s = Song(66, 4, 32, room=4.2, dark=0.75)
	prog = "Cm Cm Db Cm Ab G Fm G"
	choir_prog = "Cm Db Cm Ab Db Cm G G"
	# drone through the whole loop
	for b in range(0, 32, 4):
		s.add(choir(midi("C2") + 12, round(s.beat * 16, 3), "oo"), s.t(b), -0.2, 0.6, 0.5)
		s.add(bass(midi("C2"), round(s.beat * 16, 3)), s.t(b), 0.0, 0.5, 0.15)
	# the machine: pitched clangs on an uneven 16-step loop
	clank = "x..x.x..x..x.x.."
	pitches = [midi("C4"), midi("G3"), midi("Db4"), midi("C4"), midi("G3"), midi("Gb3")]
	for b in range(32):
		if b >= 30:
			break
		k = 0
		for i, ch in enumerate(clank):
			if ch == "x":
				m = pitches[(k + b) % len(pitches)]
				s.add(metal(m, 1.4, seed=k % 3 + 1), s.t(b, i * 0.25), (k % 3 - 1) * 0.5, 0.55 if b >= 8 else 0.4, 0.4, 0.004)
				k += 1
	drums(s, "X.......x..x....", 0, 30, kick(), gain=0.8, rev=0.25)
	for b in (7, 15, 23):
		s.add(swell(s.beat * 4), s.t(b), 0.3, 1.2, 0.5)
	# 8-15 and 24-31: low brass motif
	motif = "C3:2 Db3:1 C3:1 | G2:4 | Ab2:2 G2:1 F2:1 | G2:4 | C3:2 Db3:1 Eb3:1 | Db3:4 | C3:2 Bb2:1 Ab2:1 | G2:4"
	line(s, horn, motif, 8, gain=1.1, pan=-0.15, rev=0.45)
	line(s, horn, motif, 8, gain=0.55, pan=0.15, rev=0.45, shift=12)
	bassline(s, prog, 8, [(0, 0.75, 0), (1, 0.75, 0), (2.5, 0.5, 0), (3, 1, 2)], low=midi("C2"), gain=0.7)
	# 16-23: the choir sings over it
	ch = "G4:4 | Ab4:4 | G4:2 F4:2 | Eb4:4 | Db4:4 | C4:4 | D4:2 Eb4:2 | B3:4"
	line(s, choir, ch, 16, gain=1.0, pan=0.1, rev=0.6)
	pads(s, lambda m, d: strings(m, d, 0.7), choir_prog, 16, low=midi("G2"), gain=0.6, rev=0.5)
	drums(s, "X.......X...X...", 16, 8, taiko(0.8), gain=0.8, rev=0.35)
	# 24-31: everything together, then the machine winds down
	line(s, horn, motif, 24, gain=1.1, pan=-0.15, rev=0.45)
	line(s, choir, ch, 24, gain=0.8, pan=0.1, rev=0.6, shift=12)
	bassline(s, prog, 24, [(0, 0.75, 0), (1, 0.75, 0), (2.5, 0.5, 0), (3, 1, 2)], low=midi("C2"), gain=0.7)
	drums(s, "X..x....X..x..x.", 24, 6, taiko(0.85), gain=0.9, rev=0.35)
	drums(s, "....x.......x...", 24, 6, snare(), gain=0.35, rev=0.4)
	s.add(metal(midi("C3"), 3.0, seed=9), s.t(30), 0.0, 0.9, 0.7)
	return s


def dominaria():
	"""Old-world folk in D dorian, 6/8: lute arpeggios, a recorder tune, frame drum."""
	s = Song(198, 6, 48, room=2.2, dark=0.4)  # beats are eighth notes
	A = "Dm C G Dm F C Am Dm"
	B = "F C G Dm F C G A"
	tune = "D5:3 E5:1 F5:2 | E5:2 C5:1 G4:3 | B4:2 D5:1 G5:2 F5:1 | F5:2 E5:1 D5:3 | C5:3 A4:1 C5:2 | E5:2 G5:1 E5:3 | A5:2 G5:1 E5:2 C5:1 | D5:6"
	tune_b = "A5:3 G5:1 F5:2 | G5:3 E5:1 C5:2 | D5:2 B4:1 G4:3 | A4:2 D5:1 F5:3 | F5:2 G5:1 A5:2 C6:1 | G5:3 E5:3 | B4:2 D5:1 G5:3 | E5:3 C#5:3"
	lute = lambda m, d: pluck(m, d, 0.9, 1.0)
	harp = lambda m, d: pluck(m, d, 0.6, 1.6)
	pat = [0, 1, 2, 3, 2, 1]
	# 0-7: lute alone with a soft pad
	arp(s, lute, A, 0, pat, midi("D3"), gain=0.7, pan=-0.2, spread=0.4)
	pads(s, lambda m, d: strings(m, d, 0.6), A, 0, low=midi("D3"), gain=0.35)
	# 8-15: the tune on recorder (flute), frame drum comes in
	line(s, flute, tune, 8, gain=0.9, pan=0.15, rev=0.35)
	arp(s, lute, A, 8, pat, midi("D3"), gain=0.7, pan=-0.2, spread=0.4)
	bassline(s, A, 8, [(0, 3, 0), (3, 3, 2)], low=midi("D2"), gain=0.7)
	drums(s, "X..x..", 8, 8, frame_drum(), gain=0.8)
	# 16-23: tune again with a harp answering a third below, shaker
	line(s, flute, tune, 16, gain=0.9, pan=0.15, rev=0.35)
	line(s, harp, tune, 16, gain=0.5, pan=-0.3, rev=0.4, shift=-12)
	arp(s, lute, A, 16, pat, midi("D3"), gain=0.6, pan=-0.2, spread=0.4)
	bassline(s, A, 16, [(0, 3, 0), (3, 2, 2), (5, 1, 1)], low=midi("D2"), gain=0.7)
	drums(s, "X..xx.", 16, 8, frame_drum(), gain=0.8)
	drums(s, ".x.x.x", 16, 8, shaker(), gain=0.7)
	# 24-31: second strain on strings, fuller drums
	line(s, lambda m, d: strings(m, d, 1.1), tune_b, 24, gain=0.95, pan=0.1, rev=0.4)
	pads(s, lambda m, d: choir(m, d, "oo"), B, 24, low=midi("A3"), gain=0.45, extra_octave=False)
	arp(s, harp, B, 24, [0, 2, 3, 4, 3, 2], midi("D3"), gain=0.6, pan=-0.3, spread=0.5)
	bassline(s, B, 24, [(0, 3, 0), (3, 3, 2)], low=midi("D2"), gain=0.75)
	drums(s, "X.xX.x", 24, 8, frame_drum(), gain=0.85)
	drums(s, ".x.x.x", 24, 8, shaker(), gain=0.7)
	s.add(swell(s.beat * 6), s.t(31), 0, 0.9, 0.4)
	# 32-39: the tune with everyone
	line(s, flute, tune, 32, gain=0.9, pan=0.15, rev=0.35)
	line(s, lambda m, d: strings(m, d, 0.9), tune, 32, gain=0.45, pan=-0.15, rev=0.4, shift=-12)
	arp(s, lute, A, 32, pat, midi("D3"), gain=0.65, pan=-0.2, spread=0.4)
	bassline(s, A, 32, [(0, 3, 0), (3, 2, 2), (5, 1, 1)], low=midi("D2"), gain=0.75)
	drums(s, "X.xX.x", 32, 8, frame_drum(), gain=0.85)
	drums(s, ".x.x.x", 32, 8, shaker(), gain=0.7)
	# 40-47: back down to the lute and harp
	arp(s, lute, A, 40, pat, midi("D3"), gain=0.7, pan=-0.2, spread=0.4)
	line(s, harp, tune, 40, gain=0.55, pan=0.3, rev=0.45)
	pads(s, lambda m, d: strings(m, d, 0.6), A, 40, low=midi("D3"), gain=0.35)
	drums(s, "X.....", 40, 7, frame_drum(0.9), gain=0.6)
	return s


def ravnica():
	"""Gothic city: A harmonic minor, harpsichord figures, strings, bells and a choir."""
	s = Song(104, 4, 40, room=3.6, dark=0.5)
	A = "Am Dm G C F Bdim E Am"
	B = "F G Am Am Dm E Am E"
	mel = "E5:1 A5:1 C6:1 B5:0.5 A5:0.5 | F5:2 D5:1 E5:0.5 F5:0.5 | G5:1 B4:1 D5:1 F5:1 | E5:2 G5:1 E5:1 | A5:1 F5:1 C5:1 F5:1 | D5:1 B4:1 F5:1 D5:1 | B5:2 G#5:1 E5:1 | A5:4"
	mel_b = "A4:4 | B4:4 | C5:2 E5:2 | A4:4 | F5:2 D5:2 | E5:2 G#4:2 | A4:3 B4:1 | G#4:4"
	figure = [0, 2, 1, 2, 3, 2, 1, 2] * 2
	# 0-7: harpsichord figures and bells
	arp(s, harpsichord, A, 0, figure, midi("A3"), gain=0.8, pan=-0.25)
	bassline(s, A, 0, [(0, 2, 0), (2, 2, 0)], low=midi("A1"), gain=0.6)
	for b in range(0, 8, 2):
		s.add(bell(chord(A.split()[b], midi("A4"))[0], 4.0), s.t(b), 0.4, 0.6, 0.6)
	# 8-15: the strings take the tune; snare march
	line(s, lambda m, d: strings(m, d, 1.2), mel, 8, gain=0.95, pan=0.1, rev=0.45)
	arp(s, harpsichord, A, 8, figure, midi("A3"), gain=0.65, pan=-0.3)
	pads(s, lambda m, d: strings(m, d, 0.7), A, 8, low=midi("A2"), gain=0.4)
	bassline(s, A, 8, [(0, 1, 0), (1, 1, 2), (2, 1, 0), (3, 1, 2)], low=midi("A1"), gain=0.7)
	drums(s, "X.x.x.xxX.x.x.x.", 8, 8, snare(), gain=0.6, rev=0.35)
	drums(s, "X.......X.......", 8, 8, taiko(1.1), gain=0.6, rev=0.35)
	# 16-23: the choir, slow, with bells on every bar
	line(s, choir, mel_b, 16, gain=1.0, pan=0.0, rev=0.6)
	line(s, choir, mel_b, 16, gain=0.5, pan=0.0, rev=0.6, shift=-12)
	pads(s, lambda m, d: strings(m, d, 0.7), B, 16, low=midi("A2"), gain=0.55)
	arp(s, harpsichord, B, 16, [0, 1, 2, 1] * 2, midi("A3"), gain=0.5, pan=-0.3)
	bassline(s, B, 16, [(0, 4, 0)], low=midi("A1"), gain=0.6)
	for b in range(16, 24):
		s.add(bell(chord(B.split()[b - 16], midi("A4"))[0], 4.0), s.t(b), 0.4, 0.4, 0.6)
	s.add(swell(s.beat * 4), s.t(23), 0, 1.0, 0.5)
	# 24-31: the tune again, octave doubled, full march
	line(s, lambda m, d: strings(m, d, 1.2), mel, 24, gain=0.95, pan=0.1, rev=0.45)
	line(s, horn, mel, 24, gain=0.5, pan=-0.2, rev=0.45, shift=-12)
	arp(s, harpsichord, A, 24, figure, midi("A3"), gain=0.65, pan=-0.3)
	pads(s, choir, A, 24, low=midi("A3"), gain=0.45)
	bassline(s, A, 24, [(0, 1, 0), (1, 1, 2), (2, 1, 0), (3, 1, 2)], low=midi("A1"), gain=0.75)
	drums(s, "X.x.x.xxX.x.x.xx", 24, 8, snare(), gain=0.65, rev=0.35)
	drums(s, "X.....x.X.......", 24, 8, taiko(1.1), gain=0.7, rev=0.35)
	# 32-39: harpsichord and low strings lead back to the start
	arp(s, harpsichord, A, 32, figure, midi("A3"), gain=0.8, pan=-0.25)
	pads(s, lambda m, d: strings(m, d, 0.6), A, 32, low=midi("A2"), gain=0.45)
	bassline(s, A, 32, [(0, 2, 0), (2, 2, 0)], low=midi("A1"), gain=0.6)
	s.add(bell(midi("E5"), 5.0), s.t(39), 0.4, 0.5, 0.6)
	return s


def avishkar():
	"""Bright workshop city: a D drone, sitar and bansuri, tabla, ticking santoor."""
	s = Song(100, 4, 40, room=2.3, dark=0.35)
	alap = "D4:3 E4:1 | F#4:4 | E4:2 D4:2 | A3:4 | B3:2 C4:2 | D4:4 | E4:2 F#4:1 E4:1 | D4:4"
	gat = ("D4:0.5 E4:0.5 F#4:1 G4:0.5 A4:0.5 F#4:1 | A4:1.5 B4:0.5 A4:1 G4:0.5 F#4:0.5 | G4:1 F#4:0.5 E4:0.5 D4:1 E4:1 | F#4:2 E4:1 D4:1 |"
			" A4:0.5 B4:0.5 C5:1 B4:0.5 A4:0.5 G4:1 | A4:1 F#4:1 G4:0.5 E4:0.5 D4:1 | E4:1 F#4:0.5 G4:0.5 A4:1 C5:1 | D5:3 r:1")
	bansuri = "B4:2 D5:2 | C5:1.5 E5:0.5 G5:2 | F#5:3 E5:1 | D5:4 | B5:2 A5:1 G5:1 | A5:1.5 G5:0.5 E5:2 | F#5:1 E5:1 D5:2 | D5:4"
	B = "G C D D G A D D"
	# the tanpura: Pa Sa Sa low-Sa, over and over
	for b in range(40):
		for i, m in enumerate((midi("A3"), midi("D4"), midi("D4"), midi("D3"))):
			s.add(tanpura(m, round(s.beat * 1.1, 3)), s.t(b, i), -0.3 + i * 0.2, 0.75, 0.4)
	# 0-7: free alap on sitar
	line(s, lambda m, d, p=None: sitar(m, d, p), alap, 0, gain=0.9, pan=0.1, rev=0.4, glide=True)
	# teental: dha dhin dhin dha | dha dhin dhin dha | dha tin tin ta | ta dhin dhin dha, one bol per beat
	theka = ["dha", "dhin", "dhin", "dha", "dha", "dhin", "dhin", "dha", "dha", "tin", "tin", "ta", "ta", "dhin", "dhin", "dha"]
	def tablas(bar0, bars, fill=True):
		for b in range(bars):
			for i in range(4):
				bol = theka[(b % 4) * 4 + i]
				s.add(tabla(bol), s.t(bar0 + b, i), 0.15, 0.9 if i == 0 and b % 4 == 0 else 0.7, 0.15, 0.004)
				if fill:
					s.add(tabla("na"), s.t(bar0 + b, i + 0.5), 0.15, 0.35, 0.15, 0.004)
					if i == 3:
						s.add(tabla("ge"), s.t(bar0 + b, i + 0.75), 0.15, 0.4, 0.15, 0.004)
	# 8-15: the gat on sitar with tabla
	line(s, lambda m, d, p=None: sitar(m, d, p), gat, 8, gain=1.0, pan=0.1, rev=0.35, glide=True)
	tablas(8, 8, fill=False)
	# 16-23: again, santoor ticking sixteenths like a clockwork, bansuri doubles
	line(s, lambda m, d, p=None: sitar(m, d, p), gat, 16, gain=0.9, pan=0.1, rev=0.35, glide=True)
	line(s, flute, gat, 16, gain=0.45, pan=-0.3, rev=0.4, shift=12)
	tablas(16, 8)
	tick = [midi(n) for n in ("D5", "A4", "F#5", "A4", "D5", "A4", "G5", "A4")]
	for b in range(16, 24):
		for i in range(16):
			s.add(santoor(tick[i % 8]), s.t(b, i * 0.25), 0.35, 0.5 if i % 4 == 0 else 0.32, 0.35, 0.003)
	# 24-31: bansuri tune over moving chords
	line(s, flute, bansuri, 24, gain=1.0, pan=-0.1, rev=0.45)
	pads(s, lambda m, d: strings(m, d, 0.8), B, 24, low=midi("D3"), gain=0.5)
	bassline(s, B, 24, [(0, 1.5, 0), (1.5, 1, 2), (3, 1, 0)], low=midi("D2"), gain=0.6)
	tablas(24, 8)
	s.add(swell(s.beat * 4), s.t(31), 0, 0.9, 0.4)
	# 32-39: gat with everyone, santoor running
	line(s, lambda m, d, p=None: sitar(m, d, p), gat, 32, gain=1.0, pan=0.1, rev=0.35, glide=True)
	line(s, flute, gat, 32, gain=0.5, pan=-0.3, rev=0.4, shift=12)
	tablas(32, 7)
	for b in range(32, 39):
		for i in range(16):
			s.add(santoor(tick[(i + 4) % 8]), s.t(b, i * 0.25), 0.35, 0.45 if i % 4 == 0 else 0.28, 0.35, 0.003)
	s.add(tabla("dha"), s.t(39), 0.15, 1.0, 0.2)
	return s


TRACKS = {"title": title, "phyrexia": phyrexia, "dominaria": dominaria, "ravnica": ravnica, "avishkar": avishkar}


def write(name, song, keep_wav):
	audio = song.render()
	pcm = (np.clip(audio.T, -1, 1) * 32767).astype("<i2").tobytes()
	os.makedirs(OUT, exist_ok=True)
	ogg = os.path.join(OUT, name + ".ogg")
	cmd = ["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "2", "-i", "-",
			"-c:a", "libvorbis", "-q:a", "3", ogg]
	subprocess.run(cmd, input=pcm, check=True)
	if keep_wav:
		os.makedirs("/tmp/pw-music", exist_ok=True)
		subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "2", "-i", "-",
				"/tmp/pw-music/%s.wav" % name], input=pcm, check=True)
	peak = float(np.max(np.abs(audio)))
	print("%-10s %5.1f s  peak %.2f  %4d kB" % (name, song.length, peak, os.path.getsize(ogg) // 1024))


def main():
	args = [a for a in sys.argv[1:] if not a.startswith("--")]
	keep = "--wav" in sys.argv
	for name in args or TRACKS:
		write(name, TRACKS[name](), keep)


if __name__ == "__main__":
	main()
