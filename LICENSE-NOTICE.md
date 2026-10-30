# License notices

Original Retro module, addon, scripts and documentation: see `LICENSE-RETRO.txt`.
Upstream Godot Engine: see `LICENSE.txt` and `COPYRIGHT.txt`.

## Godot Engine
Godot Engine 4.7.2-stable is licensed under the MIT License.
Upstream: https://github.com/godotengine/godot
The fork keeps `COPYRIGHT.txt` and `LICENSE.txt`.

## Godot logo splash
`ide/addons/retro_engine/assets/godot_splash.png` is the Godot Engine logo from
the Godot distribution (`main/splash.png`). The Godot logo is
licensed under Creative Commons Attribution 4.0 (CC BY 4.0); attribution:
Godot Engine contributors, https://godotengine.org/. Generated ROMs may include
the logo only when the user enables the optional splash.

## PVSnesLib 4.6
PVSnesLib is distributed under the zlib license (see
`pvsneslib-sdk-4.6/pvsneslib/pvsneslib_license.txt`). It is used as an external
SDK; it is not vendored into this repository.

## SGDK 2.11
SGDK is distributed under the MIT license (see `sgdk211/license.txt`). GCC and
libgcc are GPLv3 with the GCC runtime library exception (see
`sgdk211/COPYING.RUNTIME`). SGDK is used as an external SDK; it is not vendored.

## GDTerm
The embedded Terminal main screen uses GDTerm 1.0.2 by markeel:
https://github.com/markeel/gdterm
GDTerm is licensed under the MIT License. The addon is vendored at
`ide/addons/gdterm/`; its license is kept at `ide/addons/gdterm/LICENSE`.
The addon also bundles Adobe Source Code Pro fonts under the SIL Open Font
License 1.1, and a bell sound from Berklee under CC BY 3.0 (see
`ide/addons/gdterm/audio/CREDITS`).

GDTerm embeds **libtmt**, the Tiny Mock Terminal Library, by Rob King. The
Linux extension in this repository is rebuilt from a pinned revision with the
control-string fix in `scripts/gdterm/control_strings.patch`. libtmt is
distributed under a BSD-style license:

```text
Copyright (c) 2017 Rob King
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

- Redistributions of source code must retain the above copyright
  notice, this list of conditions and the following disclaimer.
- Redistributions in binary form must reproduce the above copyright
  notice, this list of conditions and the following disclaimer in the
  documentation and/or other materials provided with the distribution.
- Neither the name of the copyright holder nor the names of contributors
  may be used to endorse or promote products derived from this software
  without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHORS, COPYRIGHT HOLDERS, OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## Emulators
Mesen, bsnes, Snes9x, BlastEm, Gens, Gens KMod and RetroArch are external
programs with their own licenses. The IDE detects and launches them but does
not redistribute them.

## Reference projects
The three reference projects remain the property of their authors and are used
only as local integration fixtures. `scripts/validate.sh` copies them into
`validation/projects/` and never edits the originals. Generated copies,
`validation/` artifacts are excluded from version control.
