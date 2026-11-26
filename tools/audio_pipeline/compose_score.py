#!/usr/bin/env python3
"""Compose sweeping multi-instrument orchestral arrangements from Knight Lore's ZX tunes
and render them offline via FluidSynth + FFmpeg into loudness-normalized .ogg music assets."""

from __future__ import annotations

import json
import pathlib
import random
import subprocess
import sys
import wave
from dataclasses import dataclass

import mido
import numpy as np

from ensure_soundfont import ensure_soundfont

ROOT = pathlib.Path(__file__).resolve().parents[2]
AUDIO_JSON = ROOT / "data" / "knight_lore" / "audio.json"
MIDI_DIR = ROOT / "tools" / "audio_pipeline" / ".midi"
MUSIC_DIR = ROOT / "assets" / "audio" / "music"

SAMPLE_RATE = 44100
PPQ = 480  # Ticks per quarter note

# General MIDI orchestral patches
GM = {
    "strings_ensemble": 48,   # String Ensemble 1 (legato melody/sweep)
    "slow_strings": 49,       # String Ensemble 2 (warm pads)
    "pizzicato": 45,          # Pizzicato Strings
    "harp": 46,               # Orchestral Harp
    "timpani": 47,            # Timpani
    "choir_aahs": 52,         # Choir Aahs
    "french_horn": 60,        # French Horn
    "oboe": 68,               # Oboe
    "clarinet": 71,           # Clarinet
    "flute": 73,              # Flute
    "contrabass": 43,         # Contrabass
    "cello": 42,              # Cello
    "violin": 40,             # Violin
    "celesta": 8,             # Celesta
}


@dataclass
class NoteEvent:
    channel: int
    pitch: int
    start_beat: float
    duration_beats: float
    velocity: int


class OrchestralBuilder:
    """Helper to construct multi-channel expressive MIDI files with stereo seating and CC11 swells."""

    def __init__(self, bpm: float = 96.0) -> None:
        self.bpm = bpm
        self.events: list[NoteEvent] = []
        self.channel_config: dict[int, dict[str, int]] = {}
        self.cc_events: list[tuple[int, float, int, int]] = []  # (ch, beat, cc, val)

    def setup_channel(
        self,
        ch: int,
        program: int,
        pan: int = 64,
        volume: int = 105,
        reverb: int = 80,
        chorus: int = 20,
    ) -> None:
        self.channel_config[ch] = {
            "program": program,
            "pan": pan,
            "volume": volume,
            "reverb": reverb,
            "chorus": chorus,
        }

    def add_note(
        self,
        ch: int,
        pitch: int,
        start_beat: float,
        dur_beats: float,
        vel: int,
        humanize_ms: float = 8.0,
        rng: random.Random | None = None,
    ) -> None:
        p = max(21, min(108, int(pitch)))
        v = max(12, min(127, int(vel)))
        jitter_beats = 0.0
        if rng is not None and humanize_ms > 0.0:
            jitter_s = rng.uniform(-humanize_ms, humanize_ms) / 1000.0
            jitter_beats = max(-start_beat, jitter_s * (self.bpm / 60.0))
        self.events.append(
            NoteEvent(ch, p, max(0.0, start_beat + jitter_beats), max(0.05, dur_beats), v)
        )

    def add_swell(self, ch: int, start_beat: float, end_beat: float, v_start: int, v_end: int, steps: int = 8) -> None:
        for i in range(steps + 1):
            t = i / max(steps, 1)
            b = start_beat + (end_beat - start_beat) * t
            val = int(round(v_start + (v_end - v_start) * (0.5 - 0.5 * np.cos(np.pi * t))))
            self.cc_events.append((ch, b, 11, max(20, min(127, val))))

    def add_chord(
        self,
        ch: int,
        pitches: list[int],
        start_beat: float,
        dur_beats: float,
        vel: int,
        roll_beats: float = 0.0,
        rng: random.Random | None = None,
    ) -> None:
        for idx, p in enumerate(pitches):
            self.add_note(ch, p, start_beat + idx * roll_beats, dur_beats, vel, 6.0, rng)

    def save_midi(self, out_path: pathlib.Path, total_beats: float) -> None:
        mid = mido.MidiFile(ticks_per_beat=PPQ)
        meta_track = mido.MidiTrack()
        mid.tracks.append(meta_track)
        meta_track.append(mido.MetaMessage("set_tempo", tempo=mido.bpm2tempo(self.bpm), time=0))
        meta_track.append(mido.MetaMessage("time_signature", numerator=4, denominator=4, time=0))

        # Organize events per channel into separate tracks
        by_ch: dict[int, list[tuple[int, mido.Message]]] = {ch: [] for ch in self.channel_config}

        for ch, cfg in self.channel_config.items():
            by_ch[ch].append((0, mido.Message("program_change", channel=ch, program=cfg["program"], time=0)))
            by_ch[ch].append((0, mido.Message("control_change", channel=ch, control=10, value=cfg["pan"], time=0)))
            by_ch[ch].append((0, mido.Message("control_change", channel=ch, control=7, value=cfg["volume"], time=0)))
            by_ch[ch].append((0, mido.Message("control_change", channel=ch, control=91, value=cfg["reverb"], time=0)))
            by_ch[ch].append((0, mido.Message("control_change", channel=ch, control=93, value=cfg["chorus"], time=0)))
            by_ch[ch].append((0, mido.Message("control_change", channel=ch, control=11, value=100, time=0)))

        for ch, b, cc, val in self.cc_events:
            if ch in by_ch:
                tick = int(round(b * PPQ))
                by_ch[ch].append((tick, mido.Message("control_change", channel=ch, control=cc, value=val, time=0)))

        for ev in self.events:
            if ev.channel not in by_ch:
                continue
            t0 = int(round(ev.start_beat * PPQ))
            t1 = int(round((ev.start_beat + ev.duration_beats) * PPQ))
            if t1 <= t0:
                t1 = t0 + 10
            by_ch[ev.channel].append((t0, mido.Message("note_on", channel=ev.channel, note=ev.pitch, velocity=ev.velocity, time=0)))
            by_ch[ev.channel].append((t1, mido.Message("note_off", channel=ev.channel, note=ev.pitch, velocity=0, time=0)))

        for ch in sorted(by_ch):
            trk = mido.MidiTrack()
            mid.tracks.append(trk)
            # Sort note_off before note_on at identical tick to avoid stuck notes
            msgs = sorted(by_ch[ch], key=lambda x: (x[0], 0 if x[1].type == "note_off" else 1 if x[1].type == "control_change" else 2))
            prev_tick = 0
            for tick, msg in msgs:
                delta = max(0, tick - prev_tick)
                trk.append(msg.copy(time=delta))
                prev_tick = tick
            end_tick = max(prev_tick, int(round(total_beats * PPQ)))
            trk.append(mido.MetaMessage("end_of_track", time=max(0, end_tick - prev_tick)))

        out_path.parent.mkdir(parents=True, exist_ok=True)
        mid.save(out_path)


def setup_standard_orchestra(ob: OrchestralBuilder) -> None:
    """Configure an authentic stereo-seated symphony orchestra."""
    ob.setup_channel(0, GM["strings_ensemble"], pan=38, volume=106, reverb=88, chorus=25)  # Violins I/II
    ob.setup_channel(1, GM["slow_strings"], pan=92, volume=96, reverb=92, chorus=28)       # Violas / Inner Strings
    ob.setup_channel(2, GM["cello"], pan=98, volume=104, reverb=78, chorus=12)             # Cellos
    ob.setup_channel(3, GM["contrabass"], pan=108, volume=98, reverb=65, chorus=0)         # Contrabasses
    ob.setup_channel(4, GM["french_horn"], pan=48, volume=100, reverb=92, chorus=10)       # French Horns
    ob.setup_channel(5, GM["flute"], pan=58, volume=106, reverb=86, chorus=8)              # Solo Flute
    ob.setup_channel(6, GM["oboe"], pan=72, volume=96, reverb=86, chorus=6)                # Solo Oboe
    ob.setup_channel(7, GM["harp"], pan=28, volume=98, reverb=84, chorus=12)               # Concert Harp
    ob.setup_channel(8, GM["timpani"], pan=68, volume=104, reverb=72, chorus=0)            # Timpani
    ob.setup_channel(10, GM["choir_aahs"], pan=64, volume=90, reverb=98, chorus=32)        # Cathedral Choir
    ob.setup_channel(11, GM["pizzicato"], pan=50, volume=90, reverb=70, chorus=0)          # Pizzicato Strings


# Knight Lore harmonic anchor notes in Bb minor (MIDI pitches):
# Bb2=46, Bb3=58, C4=60, Db4=61, Eb4=63, F4=65, Gb4=66, G4=67, Ab4=68, A4=69, Bb4=70, Db5=73, F5=77
def compose_menu_overture() -> tuple[OrchestralBuilder, float]:
    """Sweeping 16-bar gothic Baroque overture built directly from the de-interleaved ZX 'menu' theme.
    Structure: 4-bar lyrical intro -> 8-bar main theme (i -> v -> i -> v -> bVImaj7 -> bVII6 -> i) ->
    4-bar soaring orchestral reprise with French Horns & Choir swelling seamlessly back into bar 1.
    """
    rng = random.Random(1984)
    bpm = 88.0
    ob = OrchestralBuilder(bpm=bpm)
    setup_standard_orchestra(ob)

    # Bar = 4 beats. Total = 16 bars = 64 beats (~43.6 seconds).
    # Helper: harp arpeggio over 4 beats
    def harp_arp(b0: float, chord: list[int], vel: int = 72) -> None:
        pattern = [chord[0], chord[1], chord[2], chord[3], chord[2], chord[1], chord[2], chord[3]]
        for i, p in enumerate(pattern):
            ob.add_note(7, p, b0 + i * 0.5, 1.35, vel - (6 if i % 2 else 0), 10.0, rng)

    # ---- SECTION A (Bars 0-3: Mysterious Gothic Prelude) ----
    intro_chords = [
        (46, [58, 65, 70, 73]),  # i  (Bbm)
        (41, [53, 60, 65, 68]),  # v  (Fm)
        (42, [54, 61, 66, 70]),  # bVI (Gbmaj7)
        (44, [56, 63, 65, 68]),  # bVII6 (Ab6) -> half cadence to F on beat 2 of bar 3
    ]
    for bar, (bass, chd) in enumerate(intro_chords):
        b = bar * 4.0
        ob.add_note(2, bass + 12, b, 3.9, 68, 8.0, rng)
        ob.add_note(3, bass, b, 3.9, 64, 8.0, rng)
        ob.add_chord(1, chd[:3], b, 3.9, 62, 0.0, rng)
        ob.add_swell(1, b, b + 3.8, 72, 102)
        harp_arp(b, chd, vel=68)
    # Solo Flute lyrical anticipation over bars 2-3
    ob.add_note(5, 77, 8.0, 2.0, 82, 6.0, rng)   # F5
    ob.add_note(5, 75, 10.0, 1.0, 78, 6.0, rng)  # Eb5
    ob.add_note(5, 73, 11.0, 1.0, 76, 6.0, rng)  # Db5
    ob.add_note(5, 72, 12.0, 2.0, 74, 6.0, rng)  # C5
    ob.add_note(5, 69, 14.0, 2.0, 76, 6.0, rng)  # A4 leading tone!
    ob.add_note(8, 41, 14.0, 1.5, 68, 4.0, rng)  # Timpani swell into main theme

    # ---- SECTION B (Bars 4-11: Authentic De-interleaved Knight Lore Main Theme) ----
    # Bars 4 & 6: Bb minor (i) -> melody Bb4, Bb4, Db5, F5 | Bb4, Bb4, Db5, F5
    # Bars 5 & 7: F minor (v)   -> melody Ab4, G4, F4, F4  | Ab4, G4, F4, F4
    mel_i = [(70, 0.5), (70, 0.5), (73, 0.5), (77, 0.5), (70, 0.5), (70, 0.5), (73, 0.5), (77, 0.5)]
    mel_v = [(68, 0.5), (67, 0.5), (65, 1.0), (68, 0.5), (67, 0.5), (65, 1.0)]

    for rep in range(2):
        b_i = (4 + rep * 2) * 4.0
        b_v = (5 + rep * 2) * 4.0
        vel_boost = 10 if rep == 1 else 0

        # Bar i: Bb minor
        ob.add_note(2, 58, b_i, 3.85, 84 + vel_boost, 6.0, rng)
        ob.add_note(3, 46, b_i, 3.85, 80 + vel_boost, 6.0, rng)
        ob.add_chord(1, [58, 61, 65], b_i, 3.85, 70 + vel_boost, 0.0, rng)
        ob.add_note(8, 46, b_i, 1.0, 82 + vel_boost, 4.0, rng)
        harp_arp(b_i, [58, 65, 70, 73], vel=72)
        cur = b_i
        for p, d in mel_i:
            ob.add_note(0, p + 12, cur, d * 0.96, 86 + vel_boost, 6.0, rng)  # Sweeping violins
            ob.add_note(5, p, cur, d * 0.94, 88 + vel_boost, 6.0, rng)       # Flute doubles an octave below
            cur += d

        # Bar v: F minor
        ob.add_note(2, 53, b_v, 3.85, 82 + vel_boost, 6.0, rng)
        ob.add_note(3, 41, b_v, 3.85, 78 + vel_boost, 6.0, rng)
        ob.add_chord(1, [53, 56, 60], b_v, 3.85, 68 + vel_boost, 0.0, rng)
        harp_arp(b_v, [53, 60, 65, 68], vel=70)
        cur = b_v
        for p, d in mel_v:
            ob.add_note(0, p + 12, cur, d * 0.96, 84 + vel_boost, 6.0, rng)
            ob.add_note(6, p, cur, d * 0.94, 84 + vel_boost, 6.0, rng)       # Oboe answers the flute!
            cur += d
        if rep == 1:
            # French horn counter-swell leading into climax
            ob.add_note(4, 60, b_v + 2.0, 2.0, 82, 5.0, rng)
            ob.add_swell(4, b_v + 2.0, b_v + 4.0, 75, 115)

    # Bars 8-11: Climax progression Gb -> Ab -> Bb -> Bb (under high F5 pedal)
    climax_bars = [
        (42, [54, 61, 66, 70], 77, 1.0),   # Bar 8: Gb3 (bVImaj7)
        (44, [56, 63, 68, 72], 77, 1.0),   # Bar 9: Ab3 (bVII6)
        (46, [58, 65, 70, 73], 77, 1.0),   # Bar 10: Bb3 (i)
        (46, [58, 65, 70, 73], 73, 0.9),   # Bar 11: Bb3 resolving gently back to intro
    ]
    for idx, (bass, chd, mel_top, mel_scale) in enumerate(climax_bars):
        b = (8 + idx) * 4.0
        v_climax = 92 if idx < 3 else 78
        ob.add_note(2, bass + 12, b, 3.9, v_climax, 6.0, rng)
        ob.add_note(3, bass, b, 3.9, v_climax - 4, 6.0, rng)
        ob.add_chord(1, chd[:3], b, 3.9, v_climax - 10, 0.0, rng)
        ob.add_chord(10, [p + 12 for p in chd[:3]], b, 3.9, v_climax - 18, 0.0, rng)  # Choir Aahs pad!
        ob.add_swell(10, b, b + 3.8, 80, 118 if idx < 3 else 75)
        ob.add_note(4, bass + 12, b, 3.6, v_climax - 4, 6.0, rng)     # French Horn power bass
        ob.add_note(4, chd[2], b, 3.6, v_climax - 8, 6.0, rng)
        ob.add_note(8, bass, b, 1.2, v_climax, 4.0, rng)
        if idx < 3:
            ob.add_note(8, bass, b + 2.0, 1.2, v_climax - 12, 4.0, rng)
        harp_arp(b, chd, vel=76)
        # Soaring Violin & Flute octaves over the climax
        if idx < 3:
            for q in range(4):
                ob.add_note(0, mel_top + 12, b + q * 1.0, 0.92, int((90 + q * 4) * mel_scale), 5.0, rng)
            ob.add_note(5, mel_top, b, 3.8, 92, 6.0, rng)
        else:
            # Descending sigh F5 -> Eb5 -> Db5 -> C5 to link back to Bar 0
            for q, p in enumerate([77, 75, 73, 72]):
                ob.add_note(0, p + 12, b + q * 1.0, 0.96, 86 - q * 4, 6.0, rng)
                ob.add_note(5, p, b + q * 1.0, 0.95, 82 - q * 4, 6.0, rng)

    # ---- SECTION C (Bars 12-15: Grand Sweep & Cadence into Loop) ----
    # Echo the main theme one last time with full sweeping violins & warm horns, then soft cadence
    for bar, (bass, chd, mel) in enumerate([
        (46, [58, 65, 70, 73], mel_i),
        (41, [53, 60, 65, 68], mel_v),
        (42, [54, 61, 66, 70], [(73, 2.0), (77, 2.0)]),
        (46, [58, 65, 70, 73], [(75, 1.5), (73, 1.5), (70, 1.0)]),
    ]):
        b = (12 + bar) * 4.0
        dec = 12 if bar == 3 else 0
        ob.add_note(2, bass + 12, b, 3.9, 86 - dec, 6.0, rng)
        ob.add_note(3, bass, b, 3.9, 82 - dec, 6.0, rng)
        ob.add_chord(1, chd[:3], b, 3.9, 74 - dec, 0.0, rng)
        ob.add_note(4, chd[1], b, 3.5, 78 - dec, 6.0, rng)
        harp_arp(b, chd, vel=72 - dec)
        cur = b
        for p, d in mel:
            ob.add_note(0, p + 12, cur, d * 0.96, 90 - dec, 6.0, rng)
            ob.add_note(5, p, cur, d * 0.94, 84 - dec, 6.0, rng)
            cur += d

    return ob, 64.0


def compose_gameplay_day() -> tuple[OrchestralBuilder, float]:
    """Gentle, atmospheric chamber-orchestra exploration theme in Bb minor.
    Designed to sit softly under footsteps, dungeon echoes, and woodland birdsong without fatiguing the ear.
    """
    rng = random.Random(2001)
    bpm = 76.0
    ob = OrchestralBuilder(bpm=bpm)
    setup_standard_orchestra(ob)

    # Lower master channel expression for gentle unobtrusive exploration feel
    for ch in [0, 1, 2, 3, 5, 6, 7, 11]:
        if ch in ob.channel_config:
            ob.channel_config[ch]["volume"] = min(84, ob.channel_config[ch]["volume"])

    # 16 bars = 64 beats (~50.5 s seamless loop)
    progression = [
        (46, [58, 65, 70, 73]),  # 0: Bbm
        (46, [58, 65, 70, 73]),  # 1: Bbm
        (41, [53, 60, 65, 68]),  # 2: Fm
        (41, [53, 60, 65, 68]),  # 3: Fm
        (42, [54, 61, 66, 70]),  # 4: Gbmaj7
        (44, [56, 63, 68, 72]),  # 5: Ab6
        (46, [58, 65, 70, 73]),  # 6: Bbm
        (41, [53, 60, 65, 68]),  # 7: Fm
        (46, [58, 65, 70, 73]),  # 8: Bbm
        (44, [56, 63, 68, 72]),  # 9: Ab
        (42, [54, 61, 66, 70]),  # 10: Gbmaj7
        (41, [53, 60, 65, 68]),  # 11: Fm
        (39, [51, 58, 63, 66]),  # 12: Ebm
        (42, [54, 61, 66, 70]),  # 13: Gbmaj7
        (41, [53, 60, 65, 69]),  # 14: F7/A (harmonic minor lift)
        (46, [58, 65, 70, 73]),  # 15: Bbm
    ]

    for bar, (bass, chd) in enumerate(progression):
        b = bar * 4.0
        # Warm sustained cello & slow strings pad (long smooth swells)
        ob.add_note(2, bass + 12, b, 3.9, 62, 10.0, rng)
        ob.add_chord(1, chd[:3], b, 3.9, 56, 0.0, rng)
        ob.add_swell(1, b, b + 3.8, 65, 92 if bar % 2 == 0 else 72)

        # Delicate pizzicato quarter pulse on bars 2..13
        if 2 <= bar <= 13:
            for beat in range(4):
                p_idx = beat % 3
                ob.add_note(11, chd[p_idx], b + beat * 1.0, 0.45, 58 - (8 if beat % 2 else 0), 8.0, rng)

        # Gentle harp rolling arpeggio every 2nd bar
        if bar % 2 == 0:
            for i, p in enumerate(chd):
                ob.add_note(7, p, b + i * 0.5, 2.2, 62 - i * 3, 10.0, rng)

    # Sparse, lyrical solo Flute & Oboe phrases derived from Knight Lore's motifs (with breathing rests!)
    phrases = [
        # Bar 1-3: Solo Flute answers
        (5, 4.0,  [(70, 1.0), (73, 1.0), (77, 2.0)]),
        (5, 8.0,  [(75, 1.5), (73, 0.5), (72, 2.0)]),
        # Bar 5-7: Solo Oboe nostalgic motif
        (6, 20.0, [(70, 1.0), (68, 1.0), (66, 2.0)]),
        (6, 24.0, [(65, 1.5), (68, 0.5), (70, 2.0)]),
        # Bar 9-11: High Strings + Flute tender duet
        (5, 36.0, [(77, 1.5), (75, 0.5), (73, 1.0), (70, 1.0)]),
        (0, 36.0, [(82, 2.0), (80, 2.0)]),
        (5, 40.0, [(73, 1.0), (72, 1.0), (68, 2.0)]),
        # Bar 13-15: Gentle closing cadence
        (5, 52.0, [(70, 1.5), (73, 0.5), (72, 2.0)]),
        (5, 56.0, [(69, 2.0), (70, 2.0)]),
    ]
    for ch, start_b, notes in phrases:
        cur = start_b
        for p, d in notes:
            ob.add_note(ch, p, cur, d * 0.94, 70, 10.0, rng)
            cur += d

    return ob, 64.0


def compose_gameplay_night() -> tuple[OrchestralBuilder, float]:
    """Brooding, atmospheric nocturnal score for the Werewolf phase.
    Deep contrabasses, dark slow strings, hushed Cathedral Choir, and distant French Horn.
    """
    rng = random.Random(2002)
    bpm = 66.0
    ob = OrchestralBuilder(bpm=bpm)
    setup_standard_orchestra(ob)

    for ch in [0, 1, 2, 3, 4, 10]:
        if ch in ob.channel_config:
            ob.channel_config[ch]["volume"] = min(82, ob.channel_config[ch]["volume"])

    # 16 bars = 64 beats (~58 s loop) in dark G minor / Bb minor modal shift
    progression = [
        (46, [58, 61, 65]),  # Bbm
        (42, [54, 61, 66]),  # Gb
        (44, [56, 63, 68]),  # Ab
        (41, [53, 60, 65]),  # Fm
        (39, [51, 58, 63]),  # Ebm
        (42, [54, 58, 61]),  # Gb
        (41, [53, 56, 60]),  # Fm
        (41, [53, 60, 65]),  # Fm
        (46, [58, 61, 65]),  # Bbm
        (41, [53, 60, 65]),  # Fm
        (42, [54, 61, 66]),  # Gbmaj7
        (44, [56, 63, 68]),  # Ab
        (39, [51, 58, 63]),  # Ebm
        (41, [53, 57, 60]),  # F (major V)
        (42, [54, 61, 66]),  # Gb (deceptive)
        (41, [53, 60, 65]),  # Fm -> smooth resolve back to Bbm
    ]

    for bar, (bass, chd) in enumerate(progression):
        b = bar * 4.0
        ob.add_note(3, bass, b, 3.9, 64, 10.0, rng)          # Deep Contrabass
        ob.add_note(2, bass + 12, b, 3.9, 66, 10.0, rng)     # Cello
        ob.add_chord(1, chd, b, 3.9, 54, 0.0, rng)           # Dark strings
        ob.add_swell(1, b, b + 3.8, 55, 88 if bar % 2 == 0 else 65)

        if bar % 2 == 0:
            ob.add_chord(10, [p + 12 for p in chd], b, 3.9, 48, 0.0, rng)  # Whispered choir
            ob.add_swell(10, b, b + 3.9, 45, 82)

        if bar % 4 == 0:
            ob.add_note(8, bass, b, 2.0, 56, 6.0, rng)       # Soft distant timpani pulse

        if bar in [2, 6, 10, 14]:
            # Distant French Horn nocturnal motif
            ob.add_note(4, chd[1], b, 2.0, 64, 10.0, rng)
            ob.add_note(4, chd[2], b + 2.0, 1.9, 58, 10.0, rng)

    return ob, 64.0


def compose_start_game() -> tuple[OrchestralBuilder, float]:
    """Heroic 4.5-second orchestral brass & strings fanfare from the 9-note ZX 'start_game' motif."""
    rng = random.Random(3001)
    bpm = 112.0
    ob = OrchestralBuilder(bpm=bpm)
    setup_standard_orchestra(ob)

    # Original motif: G#3(x2), B3(x2), A#3(x2), D#3(x2), G#3(x1), F#3(x1), D#3(x1), F#3(x1), G#3(x4)
    # Transposed up an octave into sweeping orchestral French Horns + Violins + Timpani (Ab minor)
    melody = [
        (68, 1.0, [56, 63, 68, 71]),   # Ab4 (Abm)
        (71, 1.0, [56, 63, 68, 71]),   # B4
        (70, 1.0, [54, 61, 66, 70]),   # Bb4 (F#m/Gb)
        (63, 1.0, [51, 58, 63, 66]),   # Eb4 (Ebm)
        (68, 0.5, [56, 63, 68, 71]),   # Ab4
        (66, 0.5, [54, 61, 66, 70]),   # Gb4
        (63, 0.5, [51, 58, 63, 66]),   # Eb4
        (66, 0.5, [54, 61, 66, 70]),   # Gb4
        (68, 2.5, [56, 63, 68, 71]),   # Ab4 final chord swell
    ]
    cur = 0.0
    for idx, (p, d, chd) in enumerate(melody):
        vel = 104 if idx in [0, 8] else 92
        ob.add_note(4, p, cur, d * 0.95, vel, 4.0, rng)            # French Horns
        ob.add_note(0, p + 12, cur, d * 0.96, vel - 4, 4.0, rng)   # Violins octave above
        if idx in [0, 3, 4, 8]:
            ob.add_chord(1, chd[:3], cur, d * 1.1, vel - 12, 0.0, rng)
            ob.add_note(2, chd[0], cur, d * 1.1, vel - 6, 4.0, rng)
            ob.add_note(3, chd[0] - 12, cur, d * 1.1, vel - 8, 4.0, rng)
            ob.add_note(8, chd[0] - 12, cur, min(d, 0.8), vel, 3.0, rng)
        cur += d
    ob.add_chord(7, [56, 63, 68, 71, 75, 80], 6.0, 2.5, 92, 0.06, rng)  # Harp sweep on final chord

    return ob, 10.0  # Extra beats for reverb tail


def compose_game_over() -> tuple[OrchestralBuilder, float]:
    """Somber orchestral elegy derived from the 32-note ZX 'game_over' cadence (Gb -> Ab -> Bb minor)."""
    rng = random.Random(4001)
    bpm = 72.0
    ob = OrchestralBuilder(bpm=bpm)
    setup_standard_orchestra(ob)

    # Bar 0: Gb -> F5, Bb4 | Bar 1: Ab -> Eb5, Bb4 | Bar 2-3: Bbm -> Db5, Bb4
    bars = [
        (42, [54, 61, 66], [(77, 1.0), (70, 1.0), (77, 1.0), (70, 1.0)]),
        (44, [56, 63, 68], [(75, 1.0), (70, 1.0), (75, 1.0), (70, 1.0)]),
        (46, [58, 61, 65], [(73, 1.0), (70, 1.0), (73, 1.0), (70, 1.0)]),
        (46, [58, 61, 65], [(73, 1.5), (70, 2.5)]),
    ]
    for bar, (bass, chd, mel) in enumerate(bars):
        b = bar * 4.0
        dec = 16 if bar == 3 else 0
        ob.add_note(3, bass, b, 3.9, 80 - dec, 6.0, rng)
        ob.add_note(2, bass + 12, b, 3.9, 82 - dec, 6.0, rng)
        ob.add_chord(1, chd, b, 3.9, 74 - dec, 0.0, rng)
        ob.add_chord(10, [p + 12 for p in chd], b, 3.9, 68 - dec, 0.0, rng)
        ob.add_note(8, bass, b, 1.5, 76 - dec, 4.0, rng)
        cur = b
        for p, d in mel:
            ob.add_note(0, p, cur, d * 0.96, 84 - dec, 6.0, rng)
            ob.add_note(6, p, cur, d * 0.94, 76 - dec, 6.0, rng)
            cur += d

    return ob, 18.0  # Includes trailing decay


def compose_game_complete() -> tuple[OrchestralBuilder, float]:
    """Triumphant full-orchestra victory fanfare from the 25-note ZX 'game_complete' theme,
    resolving on a radiant Bb major Picardie third chord."""
    rng = random.Random(5001)
    bpm = 104.0
    ob = OrchestralBuilder(bpm=bpm)
    setup_standard_orchestra(ob)

    # Original notes: A#3, C4, C#4, A#3, C4, C#4, D#4, C4, C#4, D#4, F4, C#4, C4, C#4, D#4, C4, A#3, C4, C#4, A#3, A3, A#3, C4, A3, A#3(x3)
    raw = [58, 60, 61, 58, 60, 61, 63, 60, 61, 63, 65, 61, 60, 61, 63, 60, 58, 60, 61, 58, 57, 58, 60, 57, 58]
    cur = 0.0
    for idx, p in enumerate(raw):
        d = 2.0 if idx == len(raw) - 1 else 0.5
        mel_p = p + 12  # Lift to Violin/Flute register
        vel = 105 if idx == len(raw) - 1 else 92
        ob.add_note(0, mel_p + 12, cur, d * 0.96, vel, 4.0, rng)
        ob.add_note(5, mel_p, cur, d * 0.96, vel - 4, 4.0, rng)
        ob.add_note(4, p, cur, d * 0.94, vel - 8, 4.0, rng)  # Horns unison an octave below
        if idx % 4 == 0 and idx < len(raw) - 1:
            ob.add_note(2, p - 12, cur, 1.9, 88, 4.0, rng)
            ob.add_note(3, p - 24, cur, 1.9, 84, 4.0, rng)
            ob.add_note(8, p - 24, cur, 0.8, 92, 4.0, rng)
        cur += d

    # Glorious Bb major Picardie third chord at the finale!
    finale_b = cur - 2.0
    ob.add_chord(0, [70, 74, 77, 82], finale_b, 3.8, 108, 0.0, rng)   # Bb major (D natural!)
    ob.add_chord(1, [58, 62, 65], finale_b, 3.8, 98, 0.0, rng)
    ob.add_chord(4, [58, 65, 70], finale_b, 3.6, 102, 0.0, rng)
    ob.add_chord(10, [70, 74, 77], finale_b, 3.8, 92, 0.0, rng)
    ob.add_note(2, 46, finale_b, 3.8, 104, 4.0, rng)
    ob.add_note(3, 34, finale_b, 3.8, 100, 4.0, rng)
    ob.add_note(8, 46, finale_b, 1.5, 110, 4.0, rng)
    ob.add_chord(7, [58, 62, 65, 70, 74, 77, 82, 86], finale_b, 3.5, 104, 0.04, rng)

    return ob, finale_b + 5.5


def render_midi_to_ogg(
    sf2_path: pathlib.Path,
    mid_path: pathlib.Path,
    out_ogg: pathlib.Path,
    exact_loop_beats: float | None,
    bpm: float,
    target_lufs: float,
) -> None:
    tmp_wav = mid_path.with_suffix(".raw.wav")
    proc_wav = mid_path.with_suffix(".proc.wav")

    cmd_fs = [
        "fluidsynth",
        "-ni",
        "-g", "0.85",
        "-r", str(SAMPLE_RATE),
        "-o", "synth.reverb.active=yes",
        "-o", "synth.reverb.room-size=0.82",
        "-o", "synth.reverb.damp=0.35",
        "-o", "synth.reverb.width=0.90",
        "-o", "synth.reverb.level=0.72",
        "-o", "synth.chorus.active=yes",
        "-F", str(tmp_wav),
        str(sf2_path),
        str(mid_path),
    ]
    subprocess.run(cmd_fs, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    # Read raw float samples
    with wave.open(str(tmp_wav), "rb") as wf:
        n_ch = wf.getnchannels()
        n_frames = wf.getnframes()
        raw_bytes = wf.readframes(n_frames)
    samples = np.frombuffer(raw_bytes, dtype=np.int16).astype(np.float32) / 32768.0
    samples = samples.reshape(-1, n_ch)

    if exact_loop_beats is not None:
        loop_samples = int(round((exact_loop_beats * 60.0 / bpm) * SAMPLE_RATE))
        if len(samples) > loop_samples:
            # Overlap-add reverb tail onto the beginning of the loop for a seamless loop seam!
            body = samples[:loop_samples].copy()
            tail = samples[loop_samples:]
            add_len = min(len(tail), len(body))
            # Fade out tail slightly at its end to avoid any abrupt cutoff
            fade_tail = np.linspace(1.0, 0.0, add_len, dtype=np.float32)[:, None]
            body[:add_len] += tail[:add_len] * fade_tail
            samples = body
        # Tiny 10 ms edge cross-check fade is unnecessary if overlap-add was clean,
        # just ensure zero DC offset and peak <= 0.92
    else:
        # Trim trailing silence below -65 dB cleanly with 100 ms fade out
        abs_max = np.max(np.abs(samples), axis=1)
        nonzero = np.where(abs_max > 0.0008)[0]
        if len(nonzero) > 0:
            end_idx = min(len(samples), int(nonzero[-1]) + int(0.45 * SAMPLE_RATE))
            samples = samples[:end_idx].copy()
            fade_len = min(len(samples), int(0.18 * SAMPLE_RATE))
            samples[-fade_len:] *= np.linspace(1.0, 0.0, fade_len, dtype=np.float32)[:, None]

    # Soft peak safety limit before ffmpeg loudness normalization
    peak = float(np.max(np.abs(samples)))
    if peak > 0.90:
        samples *= 0.90 / peak

    pcm = np.clip(samples * 32767.0, -32768, 32767).astype(np.int16)
    with wave.open(str(proc_wav), "wb") as wf:
        wf.setnchannels(n_ch)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(pcm.tobytes())

    out_ogg.parent.mkdir(parents=True, exist_ok=True)
    norm_wav = mid_path.with_suffix(".norm.wav")
    # Loudness-normalize via ffmpeg loudnorm then encode high-quality Vorbis via oggenc
    cmd_ff = [
        "ffmpeg", "-y",
        "-i", str(proc_wav),
        "-af", f"loudnorm=I={target_lufs}:TP=-1.5:LRA=9",
        str(norm_wav),
    ]
    subprocess.run(cmd_ff, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    cmd_ogg = ["oggenc", "-Q", "-q", "5", "-o", str(out_ogg), str(norm_wav)]
    subprocess.run(cmd_ogg, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    tmp_wav.unlink(missing_ok=True)
    proc_wav.unlink(missing_ok=True)
    norm_wav.unlink(missing_ok=True)
    print(f"[OK] Rendered {out_ogg.relative_to(ROOT)} ({len(samples)/SAMPLE_RATE:.1f}s)")


def main() -> int:
    if not AUDIO_JSON.exists():
        print(f"ERROR: {AUDIO_JSON} not found", file=sys.stderr)
        return 1
    sf2_path = ensure_soundfont()
    MIDI_DIR.mkdir(parents=True, exist_ok=True)
    MUSIC_DIR.mkdir(parents=True, exist_ok=True)

    cues = [
        ("score_menu.ogg", compose_menu_overture, True, -16.0),
        ("score_gameplay_day.ogg", compose_gameplay_day, True, -19.5),
        ("score_gameplay_night.ogg", compose_gameplay_night, True, -19.0),
        ("score_start_game.ogg", compose_start_game, False, -15.5),
        ("score_game_over.ogg", compose_game_over, False, -16.5),
        ("score_game_complete.ogg", compose_game_complete, False, -15.5),
    ]

    for filename, fn, is_loop, target_lufs in cues:
        ob, beats = fn()
        mid_path = MIDI_DIR / filename.replace(".ogg", ".mid")
        # Render extra 2.5 beats tail so reverb rings cleanly (and wraps for loops)
        ob.save_midi(mid_path, beats + 4.0)
        render_midi_to_ogg(
            sf2_path=sf2_path,
            mid_path=mid_path,
            out_ogg=MUSIC_DIR / filename,
            exact_loop_beats=beats if is_loop else None,
            bpm=ob.bpm,
            target_lufs=target_lufs,
        )

    print("==> All 6 orchestral cues composed and rendered successfully!")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
