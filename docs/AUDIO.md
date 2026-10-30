# Audio: BGM and SFX for SNES and Mega Drive

The engine imports, synthesizes, previews and compiles real console audio. The
heavy conversion lives in
`ide/addons/retro_engine/tools/retro_audio_tool.py`; the editor UI is
`ide/addons/retro_engine/audio_editor.gd` and the Game Build wrapper is
`ide/addons/retro_engine/audio_pipeline.gd`.

## Supported inputs

| Input | SNES | Mega Drive |
| --- | --- | --- |
| `.mid` | MIDI → full **FluidR3_GM** render → full-duration IT/BRR sample fitted to the SPC budget → `smconv` → SNESMOD | MIDI → **YM2612 FM** VGM (6 FM channels) + PSG noise percussion → `rescomp` XGM2 |
| `.it` | Copied as a tracker module → `smconv` → SNESMOD soundbank | Rendered with libopenmpt at full duration → 13.3 kHz PCM sample → XGM2 PCM |
| `.mp3`, `.wav` | Decoded → full-duration IT sample, adaptive rate to fit ≤58 KiB BRR | Decoded → full-duration 13.3 kHz PCM sample → XGM2 PCM |
| `.wav`, `.mp3` SFX | 32 kHz WAV → `snesbrr` → BRR + `spcSetSoundEntry` table | 16 kHz WAV → `rescomp WAV ... XGM2` → `XGM2_playPCM` |
| Synthesized SFX | Same BRR path | Same XGM2 PCM path |

The MIDI test source is:

```text
https://files.khinsider.com/midifiles/nes/super-mario-bros.-3/world-map-1-grass-land.mid
```

## Synthesized SFX parameters

`AudioPipeline.default_sfx_params()` and the Audio tab expose:

| Parameter | Meaning |
| --- | --- |
| `waveform` | `square`, `triangle`, `sine`, `saw`, `noise` |
| `frequency` | base frequency in Hz |
| `duration_ms` | total length |
| `volume` | output amplitude |
| `duty` | square-wave duty cycle |
| `attack_ms`, `decay_ms`, `sustain`, `release_ms` | ADSR envelope |
| `pitch_slide` | semitone slide over the duration (frequency change) |
| `vibrato_hz`, `vibrato_depth` | periodic frequency modulation |
| `noise` | noise mix |
| `bitcrush` | output bit depth |

The Python synth runs at 32 kHz for SNES and 16 kHz for Mega Drive, then the
SDK tools perform the final BRR/PCM conversion. MIDI BGM is rendered through
TiMidity++ with `FluidR3_GM.sf2` for the full General MIDI arrangement; the
renderer is normalized and then fitted to the console sample budget.

## Preview in the editor

The **Audio** tab provides:

1. `Import BGM (.mid/.it/.mp3/.wav)` and `Add SFX` (opens a file dialog for
   supported `.wav`/`.mp3` files).
2. A searchable asset list with an **All / BGM / SFX** filter and a
   `BGM / SFX` count.
3. `Play` previews the selected BGM/SFX for the project platform.
4. The top toolbar **BGM / SFX** menu opens the browser, shows BGM-only or
   SFX-only, plays the selected asset and stops playback.
5. Double-clicking an audio resource in the left resource tree opens it in the
   Audio tab and starts its preview.
6. SFX parameter controls and `Synth SFX` create a synthesized SFX.
7. `Update SFX` saves the edited name/source/parameters to the selected SFX;
   `Delete SFX` removes the selected SFX and its imported source/previews after
   confirmation.
8. `Preview SNES`, `Preview Mega Drive`, `Convert & Preview Both`, `Stop`.
   Preview conversion runs in a worker thread; `Stop` tears down the player and
   cancels any conversion still in flight, so it responds immediately.
9. `Synthesize BGM`, `Update BGM` and `Delete BGM` sit below the SFX controls.
   `Synthesize BGM` opens the BGM sequencer, `Update BGM` opens the selected
   BGM in it, and `Delete BGM` removes its descriptor, MIDI source, song data
   and previews after confirmation.

## BGM sequencer

The BGM editor is a separate resizable window so it also works when the Audio
tab is narrow. Double-clicking an existing BGM (or a raw `.mid`, `.midi` or
`.it` music file) opens it in the sequencer.

The piano roll supports:

- left click to add a note, left drag to move it, drag its right edge to resize;
- right click or `Delete`/`Backspace` to remove the selected note;
- mouse wheel to scroll vertically, `Shift` + wheel horizontally;
- per-track colors, mute/solo, zoom and step/BPM controls.

The chip panel exposes the per-track controls used by the target hardware:

- **SNES SPC**: waveform (sine/square/saw/triangle/noise), attack, decay,
  sustain, release, echo, noise, pitch modulation and detune.
- **YM2612 FM**: patch family, algorithm, feedback and all four operators
  (multiply, level, attack, decay, sustain, release, detune).
- **SN76489 PSG**: waveform/noise, volume and ADSR.
- **DAC**: PCM sample path.

Each song is stored as `<project>/.retro/audio/<name>.retro_bgm.json`; saving
also exports the editable MIDI source to `.retro/audio/sources/<name>.mid` and
updates the `.retro_audio.json` descriptor (kind `bgm`, platform, `source` and
`song`). `.it` files are read through `libopenmpt` (`libopenmpt.so.0`) and
converted to the same editable song/MIDI representation. `Export MIDI` writes
the current song without changing the BGM entry.

The chip values are preserved in the song JSON. The current ROM converter
applies track volume, pan, waveform/patch family and noise routing; detailed
ADSR, echo and operator-level values are kept for a later chip-accurate
renderer.

Source WAV/MP3 SFX preview uses the selected file through the target
conversion path (BRR for SNES, PCM for Mega Drive), not the SFX synthesizer.
The synthesized path is used only when the SFX has no source file.

Raw project audio (`.mid`, `.it`, `.wav`, `.mp3`) is wrapped into a temporary
BGM/SFX descriptor when selected. Earlier builds discarded that descriptor and
fell back to a short synthesized SFX; that fallback is fixed, so selecting a
project MIDI now previews the actual MIDI BGM.

Previews are WAV files rendered from the actual target pipeline:

- SNES BGM: for MIDI/WAV/MP3 sample-based BGM the preview is written directly
  from the resampled BRR sample, so it always covers the full source/MIDI
  duration instead of being truncated by the IT module's fixed 16 s pattern.
- Mega Drive BGM: the generated YM2612 FM VGM is previewed with the tool's
  two-operator FM renderer. The test also records the real ROM through Genesis
  Plus GX so the FM result can be compared.
- SFX: the synthesized/decoded WAV is played directly.

SNES and Mega Drive previews are written under `preview/snes/` and
`preview/megadrive/`, so converting one target never overwrites the other. For
very long BGMs the SNES BRR sample-rate floor (4 kHz) can exceed the SPC sample
budget; the preview is still full-length, but the ROM may need a looped or
shortened track.

The asset descriptor is stored under
`<project>/.retro/audio/<name>.retro_audio.json`; sources are copied to
`<project>/.retro/audio/sources/`.

## Game Build integration

`GameBuild.generate()` reads audio resources (`editor: "audio"`) and prepares
them for the target:

- SNES makefile exports `AUDIOFILES`, `SOUNDBANK` and `SMCONVFLAGS`; the
  project gets `soundbank.asm/.h/.bnk`, calls
  `spcBoot → spcSetBank → spcLoad → spcAllocateSoundRegion → spcPlay`, and
  embeds BRR SFX arrays plus a `brrsamples` table.
- Mega Drive writes `res/audio.res` with `XGM2` or `WAV ... XGM2` resources and
  calls `XGM2_play` or `XGM2_playPCM(Ex)` from the generated `main.c`.

The generated ROMs are real: the audio test records the emulator output and
requires non-silent PCM.

## Test

```bash
scripts/test_audio.sh
```

It downloads the MIDI above (if needed), generates both projects, builds both
ROMs, renders previews and records emulator audio. Expected output:

```text
AUDIO_BUILD PASS
AUDIO_PREVIEW PASS snes_worldmap.wav ...
AUDIO_PREVIEW PASS megadrive_worldmap.wav ...
AUDIO_PREVIEW PASS snes_jump.wav ...
AUDIO_PREVIEW PASS megadrive_jump.wav ...
AUDIO_GM PASS duration=16.71s source=FluidR3_GM
AUDIO_YM2612 PASS writes=648
AUDIO_LONG_PCM PASS duration=16.71s
AUDIO_EMULATOR PASS snes_record.wav ...
AUDIO_EMULATOR PASS md_record.wav ...
==> MIDI to SNES and Mega Drive audio PASS
```

ROMs:

```text
validation/audio/roms/audio_snes_mid.sfc
validation/audio/roms/audio_megadrive_mid.bin
validation/game_build/roms_para_testar/07_snes_music_mid.sfc
validation/game_build/roms_para_testar/08_megadrive_music_mid.bin
```

Previews:

```text
validation/audio/preview/snes_worldmap.wav
validation/audio/preview/megadrive_worldmap.wav
validation/audio/preview/snes_jump.wav
validation/audio/preview/megadrive_jump.wav
```

## Limitations

- MIDI → SNES uses the full FluidR3_GM arrangement, but it is rendered to a
  mono PCM/BRR sample. Long songs are adaptively downsampled to 4-8 kHz to fit
  the 58 KiB SPC sample RAM, so the result is a full GM mix rather than a
  multi-instrument tracker with per-program GM samples.
- MIDI → Mega Drive uses real YM2612 FM on six channels with per-family
  two-carrier FM patches (piano, guitar, bass, strings, brass, lead) and PSG
  noise drums. It is not a full 128-program GM FM patch bank; program changes
  select the matching family patch rather than a unique GM instrument.
- `.it` on Mega Drive is rendered through libopenmpt to PCM; tracker effects
  are applied by that render rather than recreated by an XGM tracker player.
- `.mp3`/`.wav` BGM now keeps the full duration. Mega Drive ROM size grows with
  the PCM sample; SNES chooses the sample rate that fits the BRR budget instead
  of cutting at 8 seconds.
