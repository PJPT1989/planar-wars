#!/usr/bin/env python3
"""Generates the unit voices in voices/: every troop answers when it is selected, ordered to move,
ordered to attack and when it is trained.

Speech comes from Piper (neural text to speech) with the LibriTTS-R voice (904 speakers, data
under CC BY 4.0); each race then gets its own treatment (Phyrexians are metallic and doubled,
the Angel echoes, golems are slowed down). Beasts and machines that do not talk get synthesised
growls, shrieks, grinding and beeps instead. Clips are mono Ogg Vorbis.

    pip install piper-tts
    python3 tools/gen_voices.py                 # all units
    python3 tools/gen_voices.py ravnica         # one race
The voice model (about 75 MB) is downloaded to /tmp/piper the first time. With faster-whisper
installed, each line is spoken up to four times and the take the recogniser understands best is
kept (speech synthesis varies from take to take).
"""
import io
import os
import subprocess
import sys
import urllib.request
import wave

import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "voices")
MODEL_DIR = "/tmp/piper"
MODEL = "en_US-libritts_r-medium.onnx"
MODEL_URL = "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/libritts_r/medium/"
EVENTS = ("select", "move", "attack", "ready")

rng = np.random.default_rng(11)

# --- the lines -----------------------------------------------------------------------------
# Per unit: treatment, pitch (playback factor; below 1 is deeper and slower), [select x3],
# [move x3], [attack x3], ready. A one-word entry is a synthesised creature or machine (SOUNDS).

UNITS = {
	"phyrexia": {
		"worker": ("phyrexian", 0.92, ["Drone awaits.", "Function?", "Assign me."],
			["Complying.", "It is done.", "Moving."], ["Must I?", "Rending.", "Obey."], "Drone decanted."),
		"infantry": ("phyrexian", 0.85, ["Flesh is weak.", "We are one.", "Command the Legion."],
			["Advancing.", "The march is endless.", "As one."], ["Compleate them!", "Kill the flesh.", "All will be one!"], "The Legion grows."),
		"spear": ("phyrexian", 0.88, ["Husk ready.", "Impale?", "Sharpened."],
			["Shambling on.", "Onward.", "Where the spines are needed."], ["Skewer them!", "Pierce!", "Pin them down."], "Husk awakened."),
		"archer": ("phyrexian", 0.95, ["Glistening.", "Oil ready.", "Spit?"],
			["Seeping forward.", "Flowing.", "Yes."], ["Drown them in oil!", "Burn, flesh.", "Spray!"], "Glands are full."),
		"cavalry": ("hound",),
		"siege": ("gorger",),
		"flyer": ("drake",),
		"champion": ("chosen", 0.86, ["The Praetor sees through me.", "Speak, lesser one.", "I am chosen."],
			["I go where the Mother wills.", "Make way.", "Kneel as I pass."], ["Your flesh is mine.", "Bow to perfection!", "Unmake them."], "The Chosen has risen."),
	},
	"dominaria": {
		"worker": ("field", 1.0, ["Aye?", "What needs doing?", "At your service."],
			["Right away.", "Off I go.", "Aye, aye."], ["With a pitchfork?", "If I must!", "Have at you!"], "Ready to work."),
		"infantry": ("field", 0.97, ["For Benalia!", "Sword ready.", "Orders, captain?"],
			["Marching.", "Forward!", "On the double."], ["Charge!", "Hold the line!", "Steel and courage!"], "Footman reporting."),
		"spear": ("field", 1.0, ["Pikes up.", "Yes, sir?", "Standing firm."],
			["Moving out.", "Pikes forward.", "As you say."], ["Brace the pikes!", "Stop those riders!", "Lower spears!"], "Pikeman ready."),
		"archer": ("field", 1.0, ["Bow strung.", "I've a keen eye.", "Yes?"],
			["Going.", "To the ridge.", "Swift and quiet."], ["Loose!", "Arrows away!", "Fire at will!"], "Longbow at the ready."),
		"cavalry": ("field", 0.96, ["My lance is yours.", "Honor and glory.", "Mounted and ready."],
			["Ride on!", "Onward!", "We ride."], ["For the Coalition!", "Lances down!", "Ride them down!"], "A knight of Benalia rides."),
		"flyer": ("field", 1.0, ["Skies are clear.", "Wings ready.", "Where to?"],
			["Taking wing.", "Up we go!", "Flying."], ["Dive!", "From above!", "Strike from the clouds!"], "Pegasus saddled."),
		"caster": ("hall", 1.0, ["Knowledge is power.", "The academy listens.", "Hmm?"],
			["As you wish.", "Time is on our side.", "Moving."], ["Feel the arcane!", "A lesson for you!", "Let me show you."], "The mage has arrived."),
		"champion": ("angel", 1.0, ["I stand with you.", "The Host is watching.", "Be not afraid."],
			["I go.", "Where light is needed.", "On wings of dawn."], ["Fall before the Host!", "By light and sword!", "Begone, darkness!"], "The Host descends."),
	},
	"ravnica": {
		"worker": ("street", 1.0, ["Union rules apply.", "What's the job?", "Yeah?"],
			["On the clock.", "Fine, fine.", "Heading over."], ["That's not in my contract!", "Alright, alright!", "Get them!"], "Laborer on shift."),
		"infantry": ("street", 0.98, ["Legion, ready.", "By the Legion's law.", "Trooper standing by."],
			["Patrolling.", "Securing the street.", "Moving in."], ["Enforce the law!", "Break them!", "Legion, attack!"], "Trooper on duty."),
		"spear": ("street", 1.0, ["Precinct watch.", "Halberd ready.", "State your business."],
			["Clear the way.", "Making rounds.", "Understood."], ["You're under arrest!", "Halt!", "Cut them down!"], "Halberdier reporting."),
		"archer": ("street", 1.0, ["Got the high ground.", "Bolt loaded.", "Watching."],
			["Over the rooftops.", "Relocating.", "Quiet now."], ["Bolts away!", "Got a clear shot.", "Firing!"], "Crossbow loaded."),
		"siege": ("street", 1.0, ["Coils charged.", "Careful, it bites.", "Cannon crew here."],
			["Rolling!", "Push!", "Mind the wheels."], ["Fire the spark!", "Light it up!", "Discharge!"], "Spark cannon ready."),
		"flyer": ("street", 1.0, ["Skyknight aloft.", "The sky is ours.", "Ready to fly."],
			["Wings out.", "Over the spires.", "On my way."], ["Strike!", "Swooping in!", "For the guild!"], "Skyknight takes flight."),
		"caster": ("hall", 1.0, ["The guild provides.", "Contracts are binding.", "Yes?"],
			["By guild charter.", "Moving.", "Very well."], ["By decree!", "Feel the storm!", "Annulled!"], "Guild mage present."),
		"champion": ("golem", 0.88, ["Guardian.", "I protect.", "Stone listens."],
			["I walk.", "Slowly.", "The city moves."], ["Crush.", "Protect the city.", "Stone breaks bone."], "Guardian awakens."),
	},
	"avishkar": {
		"worker": ("servo",),
		"spear": ("bright", 1.0, ["Lance polished.", "Brass and bravery.", "Ready!"],
			["Off we go!", "Swift as a spark.", "On it!"], ["Lance them!", "Charge forward!", "Through the gears!"], "Lancer suited up."),
		"archer": ("bright", 1.0, ["Rifle primed.", "Sights calibrated.", "Steady hands."],
			["Repositioning.", "Moving up.", "Got it."], ["Fire!", "Aether rounds out!", "Taking the shot!"], "Rifleman ready."),
		"cavalry": ("bright", 1.04, ["Engine's hot!", "Need speed?", "Let's race!"],
			["Full throttle!", "Out of my way!", "Racing!"], ["Ram them!", "Fastest wins!", "Eat my dust!"], "Cycle tuned and ready."),
		"siege": ("bright", 1.0, ["Pressure's up.", "Cannon primed.", "Aim me."],
			["Rolling out.", "Heave!", "Easy does it."], ["Fire the cannon!", "Boom!", "Aether blast!"], "Cannon assembled."),
		"flyer": ("thopter",),
		"caster": ("bright", 1.0, ["Eureka?", "I have an idea.", "Inventor here."],
			["To the workshop!", "Let's test it.", "Brilliant, moving."], ["Experimental!", "Try this!", "Prototype away!"], "Fresh from the Fair."),
		"champion": ("colossus", 0.85, ["Colossus online.", "Gears turning.", "Awaiting input."],
			["Striding.", "Course set.", "Moving."], ["Smash.", "Engage.", "Crushing gears."], "Colossus assembled."),
	},
}

# LibriTTS-R speaker ids: for each unit, of a few speakers of the right pitch, the one whose
# treated lines a speech recogniser understood best
SPEAKERS = {
	("phyrexia", "worker"): 261,   # male, 102 Hz
	("phyrexia", "infantry"): 808,   # low male, 98 Hz
	("phyrexia", "spear"): 216,   # male, 108 Hz
	("phyrexia", "archer"): 757,   # female, 188 Hz
	("phyrexia", "champion"): 93,   # female, 191 Hz
	("dominaria", "worker"): 317,   # male, 119 Hz
	("dominaria", "infantry"): 670,   # male, 115 Hz
	("dominaria", "spear"): 22,   # low male, 87 Hz
	("dominaria", "archer"): 201,   # male, 113 Hz
	("dominaria", "cavalry"): 797,   # low male, 85 Hz
	("dominaria", "flyer"): 832,   # female, 197 Hz
	("dominaria", "caster"): 748,   # female, 169 Hz
	("dominaria", "champion"): 179,   # female, 170 Hz
	("ravnica", "worker"): 495,   # male, 107 Hz
	("ravnica", "infantry"): 755,   # female, 180 Hz
	("ravnica", "spear"): 760,   # low male, 95 Hz
	("ravnica", "archer"): 527,   # male, 107 Hz
	("ravnica", "siege"): 812,   # male, 121 Hz
	("ravnica", "flyer"): 484,   # low male, 97 Hz
	("ravnica", "caster"): 503,   # female, 190 Hz
	("ravnica", "champion"): 204,   # low male, 100 Hz
	("avishkar", "spear"): 880,   # female, 174 Hz
	("avishkar", "archer"): 221,   # male, 120 Hz
	("avishkar", "cavalry"): 151,   # male, 114 Hz
	("avishkar", "siege"): 418,   # low male, 99 Hz
	("avishkar", "caster"): 450,   # female, 200 Hz
	("avishkar", "champion"): 605,   # low male, 89 Hz
}

# --- signal helpers ------------------------------------------------------------------------


def band(x, lo, hi, soft=0.3):
	X = np.fft.rfft(x)
	f = np.fft.rfftfreq(len(x), 1.0 / SR)
	g = np.ones_like(f)
	if lo:
		g *= 1.0 / (1.0 + (lo / np.maximum(f, 1.0)) ** (2.0 / soft))
	if hi:
		g *= 1.0 / (1.0 + (f / hi) ** (2.0 / soft))
	return np.fft.irfft(X * g, len(x))


def resample(x, factor):
	"""Plays x at `factor` times the speed (below 1: deeper and longer)."""
	n = int(len(x) / factor)
	return np.interp(np.arange(n) * factor, np.arange(len(x)), x)


def stretch(x, rate, n_fft=1024, hop=256):
	"""Phase-vocoder time stretch: rate > 1 is shorter, pitch unchanged."""
	win = np.hanning(n_fft)
	frames = [np.fft.rfft(win * x[i:i + n_fft]) for i in range(0, len(x) - n_fft, hop)]
	if len(frames) < 2:
		return x
	S = np.array(frames)
	steps = np.arange(0, len(S) - 1, rate)
	omega = 2 * np.pi * hop * np.arange(S.shape[1]) / n_fft
	phase = np.angle(S[0])
	out = np.zeros(int(len(steps) * hop + n_fft))
	for k, t in enumerate(steps):
		i = int(t)
		frac = t - i
		mag = (1 - frac) * np.abs(S[i]) + frac * np.abs(S[i + 1])
		out[k * hop:k * hop + n_fft] += win * np.fft.irfft(mag * np.exp(1j * phase), n_fft)
		dphi = np.angle(S[i + 1]) - np.angle(S[i]) - omega
		dphi -= 2 * np.pi * np.round(dphi / (2 * np.pi))
		phase += omega + dphi
	return out / (np.sum(win ** 2) / hop)


def shift(x, factor):
	"""Pitch times `factor`, same length."""
	return resample(stretch(x, factor), factor)


def delay(x, seconds, gain, feedback=0.0, taps=1):
	d = int(seconds * SR)
	out = np.concatenate([x, np.zeros(d * (taps + 1))])
	echo = np.zeros_like(out)
	src = out.copy()
	g = gain
	for t in range(1, taps + 1):
		echo[d * t:] += src[: len(out) - d * t] * g
		g *= feedback if feedback else 0.0
		if g == 0:
			break
	return out + echo


def room(x, seconds, wet, dark=3000):
	n = int(seconds * SR)
	t = np.arange(n) / SR
	ir = band(rng.standard_normal(n), 200, dark) * np.exp(-t * 6.9 / seconds)
	ir[: int(0.012 * SR)] = 0
	ir /= np.sqrt(np.sum(ir ** 2))
	size = len(x) + n
	nfft = 1 << (size - 1).bit_length()
	y = np.fft.irfft(np.fft.rfft(x, nfft) * np.fft.rfft(ir, nfft), nfft)[:size]
	out = np.concatenate([x, np.zeros(n)])
	return out + y * wet


def comb(x, seconds, feedback):
	"""Short resonant echo: a metallic ring."""
	d = max(1, int(seconds * SR))
	y = np.concatenate([x, np.zeros(d * 8)])
	# vectorised by blocks of d samples
	for s in range(d, len(y), d):
		e = min(s + d, len(y))
		y[s:e] += y[s - d:e - d] * feedback
	return y


def mix(*parts):
	n = max(len(p) for p in parts)
	return sum(np.pad(p, (0, n - len(p))) for p in parts)


def trim(x, thresh=0.01):
	idx = np.where(np.abs(x) > thresh)[0]
	if len(idx) == 0:
		return x
	a = max(0, idx[0] - int(0.01 * SR))
	b = min(len(x), idx[-1] + int(0.08 * SR))
	return x[a:b]


def finish(x):
	x = trim(x, 0.004)
	x = x / (np.max(np.abs(x)) + 1e-9) * 0.89
	fade = min(len(x), int(0.02 * SR))
	x[-fade:] *= np.linspace(1, 0, fade)
	return x


# --- speech --------------------------------------------------------------------------------

_voice = None


def speak(text, speaker, speed=1.0):
	global _voice
	if _voice is None:
		from piper import PiperVoice
		path = os.path.join(MODEL_DIR, MODEL)
		if not os.path.exists(path):
			os.makedirs(MODEL_DIR, exist_ok=True)
			for f in (MODEL, MODEL + ".json"):
				urllib.request.urlretrieve(MODEL_URL + f, os.path.join(MODEL_DIR, f))
		_voice = PiperVoice.load(path)
	from piper import SynthesisConfig
	buf = io.BytesIO()
	with wave.open(buf, "wb") as w:
		_voice.synthesize_wav(text, w, syn_config=SynthesisConfig(speaker_id=speaker, length_scale=speed, noise_scale=0.6, noise_w_scale=0.7))
	buf.seek(0)
	with wave.open(buf) as w:
		rate = w.getframerate()
		x = np.frombuffer(w.readframes(w.getnframes()), "<i2") / 32768.0
	if rate != SR:
		x = resample(x, rate / SR)
	return trim(x)


def voice(text, speaker, treat, pitch):
	"""Speech with a race's treatment. pitch < 1 lowers it; golems also speak slowly."""
	x = speak(text, speaker, 1.05 if treat == "golem" else 0.92)
	if pitch != 1.0:
		x = shift(x, pitch)
	if treat == "phyrexian":
		# a slightly detuned double, a metallic ring and a rasp
		x = mix(x, 0.6 * delay(resample(x, 0.985), 0.012, 0.0))
		x = comb(x, 0.0042, 0.4)
		x = np.tanh(x * 1.4) * 0.7 + band(x, 1800, 6000) * 0.2
		x = room(x, 0.9, 0.35, 2500)
	elif treat == "chosen":
		x = mix(x, 0.5 * resample(x, 0.97), 0.4 * delay(resample(x, 1.02), 0.02, 0.0))
		x = comb(x, 0.0031, 0.4)
		x = np.tanh(x * 1.4) * 0.7
		x = room(x, 1.6, 0.5, 2200)
	elif treat == "angel":
		x = mix(x, 0.35 * delay(resample(x, 0.995), 0.022, 0.0))
		x = room(x, 2.6, 0.75, 5000)
	elif treat == "golem":
		x = band(x, 60, 4500)
		x = comb(x, 0.006, 0.25)
		x = room(x, 1.2, 0.45, 1800)
	elif treat == "colossus":
		t = np.arange(len(x)) / SR
		x = x * (0.75 + 0.25 * np.sin(2 * np.pi * 55 * t))
		x = comb(x, 0.005, 0.35)
		x = room(x, 1.0, 0.35, 2600)
	elif treat == "field":
		x = room(x, 0.5, 0.12, 4000)
	elif treat == "hall":
		x = room(x, 1.4, 0.3, 4500)
	elif treat == "street":
		x = delay(x, 0.09, 0.12)
		x = room(x, 0.6, 0.15, 4000)
	elif treat == "bright":
		x = x + band(x, 2500, 8000) * 0.25
		x = room(x, 0.5, 0.12, 5000)
	return finish(x)


# --- creatures and machines -----------------------------------------------------------------

def _t(seconds):
	return np.arange(int(seconds * SR)) / SR


def growl(seconds, base, rough=1.0, snarl=0.0):
	"""A beast's voice: a jittery low pulse through moving formants."""
	t = _t(seconds)
	f = base * (1 + 0.08 * np.sin(2 * np.pi * 3.1 * t) + 0.05 * rng.standard_normal(len(t)).cumsum() / np.sqrt(len(t)))
	ph = 2 * np.pi * np.cumsum(f) / SR
	src = np.sign(np.sin(ph)) * 0.5 + rng.standard_normal(len(t)) * 0.35 * rough
	out = band(src, 150, 900) + band(src, 900, 2200) * (0.35 + snarl * 0.6)
	env = np.minimum(1, t / 0.05) * np.minimum(1, (seconds - t) / 0.12)
	return out * env


def hound(event, i):
	if event == "attack":
		x = np.concatenate([growl(0.12, 140, 1.3, 1.0) * (1 + i * 0.2), np.zeros(int(0.05 * SR)), growl(0.22, 120, 1.4, 1.0)])
	elif event == "move":
		x = growl(0.35 + 0.1 * i, 95 + 10 * i, 0.9, 0.2)
	elif event == "ready":
		x = np.concatenate([growl(0.25, 110, 1.0, 0.6), growl(0.6, 80, 1.1, 0.3)])
	else:
		x = growl(0.5 + 0.15 * i, 75 + 8 * i, 1.0, 0.1)
	return finish(room(comb(x, 0.004, 0.3), 0.6, 0.2))


def drake(event, i):
	t = _t(0.5 if event != "ready" else 0.9)
	sweep = {"select": (900, 700), "move": (700, 1100), "attack": (1400, 600), "ready": (600, 1500)}[event]
	f = np.linspace(sweep[0], sweep[1], len(t)) * (1 + 0.05 * i) * (1 + 0.03 * np.sin(2 * np.pi * 23 * t))
	ph = 2 * np.pi * np.cumsum(f) / SR
	x = np.sin(ph + 1.8 * np.sin(ph * 2.01)) + rng.standard_normal(len(t)) * 0.25
	x = band(x, 400, 5000) * np.minimum(1, t / 0.03) * np.exp(-t * (2.5 if event != "ready" else 1.6))
	return finish(room(comb(x, 0.0035, 0.4), 1.0, 0.35))


def gorger(event, i):
	t = _t(0.7 if event != "ready" else 1.1)
	base = {"select": 55, "move": 48, "attack": 70, "ready": 40}[event] * (1 + 0.06 * i)
	ph = 2 * np.pi * base * t
	x = sum(np.sin(ph * k) / k for k in range(1, 12)) * (0.6 + 0.4 * np.sign(np.sin(2 * np.pi * (9 + 3 * i) * t)))
	x = x + band(rng.standard_normal(len(t)), 300, 2500) * 0.4 * (0.5 + 0.5 * np.sin(2 * np.pi * 13 * t))
	if event == "attack":
		x = x + growl(len(t) / SR, 90, 1.5, 1.0) * 0.8
	x *= np.minimum(1, t / 0.05) * np.minimum(1, (t[-1] - t) / 0.15)
	return finish(room(comb(x, 0.006, 0.5), 0.8, 0.3, 2000))


def chirps(notes, dur=0.07, gap=0.02, wobble=0.0):
	parts = []
	for f0, f1 in notes:
		t = _t(dur)
		f = np.linspace(f0, f1, len(t)) * (1 + wobble * np.sin(2 * np.pi * 30 * t))
		x = np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.3 * np.sin(4 * np.pi * np.cumsum(f) / SR)
		x *= np.minimum(1, t / 0.005) * np.minimum(1, (dur - t) / 0.01)
		parts += [x, np.zeros(int(gap * SR))]
	return np.concatenate(parts)


SERVO = {
	"select": [[(1200, 1600), (1600, 1300)], [(900, 1400)], [(1500, 1500), (1100, 1800)]],
	"move": [[(1000, 1500), (1500, 2000)], [(1300, 1300), (1300, 1700)], [(1100, 1600), (1700, 1700), (2000, 2200)]],
	"attack": [[(2000, 900), (2000, 900)], [(1800, 700)], [(2200, 1200), (1200, 2200), (2200, 800)]],
	"ready": [[(800, 1200), (1200, 1600), (1600, 2400)]],
}


def servo(event, i):
	x = chirps(SERVO[event][i], 0.08, 0.025, 0.02)
	return finish(room(x, 0.4, 0.15, 6000))


def thopter(event, i):
	t = _t(0.55 if event != "ready" else 0.8)
	whirr = band(rng.standard_normal(len(t)), 300, 3000) * (0.5 + 0.5 * np.sin(2 * np.pi * (38 + 6 * i) * t)) ** 2
	whirr *= np.minimum(1, t / 0.08) * np.minimum(1, (t[-1] - t) / 0.12) * 0.6
	tones = {"select": [(1600, 2100)], "move": [(1400, 1900), (1900, 2300)], "attack": [(2400, 1300), (2400, 1300)], "ready": [(1200, 1800), (1800, 2600)]}[event]
	c = chirps(tones, 0.07, 0.02)
	c = np.pad(c, (int(0.1 * SR), 0))[: len(t)]
	x = whirr + 0.7 * np.pad(c, (0, len(t) - len(c)))
	return finish(room(x, 0.5, 0.15, 6000))


SOUNDS = {"hound": hound, "drake": drake, "gorger": gorger, "servo": servo, "thopter": thopter}

# --- picking takes --------------------------------------------------------------------------

_asr = False


def understood(x, text):
	"""Share of the line's words a speech recogniser hears in x (1.0 without a recogniser)."""
	global _asr
	if _asr is False:
		try:
			from faster_whisper import WhisperModel
			_asr = WhisperModel("base.en", device="cpu", compute_type="int8")
		except ImportError:
			_asr = None
	if _asr is None:
		return 1.0
	y = np.interp(np.arange(int(len(x) * 16000 / SR)) * SR / 16000, np.arange(len(x)), x).astype(np.float32)
	heard = " ".join(seg.text for seg in _asr.transcribe(y, beam_size=1, language="en")[0])
	words = lambda t: "".join(c for c in t.lower() if c.isalpha() or c == " ").split()
	want = words(text)
	got = words(heard)
	return sum(1 for w in want if w in got) / max(1, len(want))


def best_take(text, speaker, treat, pitch, tries=4):
	best = None
	for _ in range(tries):
		x = voice(text, speaker, treat, pitch)
		score = understood(x, text)
		if best is None or score > best[1]:
			best = (x, score)
		if score >= 1.0:
			break
	return best


# --- writing --------------------------------------------------------------------------------


def write(path, x):
	pcm = (np.clip(x, -1, 1) * 32767).astype("<i2").tobytes()
	subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "1", "-i", "-",
			"-c:a", "libvorbis", "-q:a", "2", path], input=pcm, check=True)


def main():
	races = [a for a in sys.argv[1:] if not a.startswith("--")] or list(UNITS)
	os.makedirs(OUT, exist_ok=True)
	count = 0
	scores = []
	for race in races:
		for role, spec in UNITS[race].items():
			for ev_i, event in enumerate(EVENTS):
				n = 1 if event == "ready" else 3
				for i in range(n):
					if len(spec) == 1:
						x = SOUNDS[spec[0]](event, i)
					else:
						treat, pitch = spec[:2]
						text = spec[2 + ev_i] if event == "ready" else spec[2 + ev_i][i]
						x, score = best_take(text, SPEAKERS[(race, role)], treat, pitch)
						scores.append(score)
					write(os.path.join(OUT, "%s_%s_%s%d.ogg" % (race, role, event, i)), x)
					count += 1
		print(race, "done")
	print(count, "clips", "(recogniser heard %.0f%% of the words)" % (100 * sum(scores) / len(scores)) if scores else "")


if __name__ == "__main__":
	main()
