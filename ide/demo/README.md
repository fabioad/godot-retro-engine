# Native bridge demos

Open either scene in the Godot editor, then use the **Native** tab:

- `native_showcase.tscn` — `Sprite2D`, `AnimatedSprite2D`, `CollisionShape2D`
  and `Camera2D`. Use **Import current scene** or **Capture background**.
- `native3d.tscn` — a `MeshInstance3D` and `Camera3D`. Use **Bake 3D sprite**;
  the tab selects the Super FX (Star Fox) profile on SNES and the SVP
  (Virtua Racing) profile on Mega Drive.

For automated demos:

```bash
RETRO_TAB=12 RETRO_NATIVE_AUTO=capture \
  ./dist/linux/GodotRetroEngine --editor --path dist/linux/ide \
  res://demo/native_showcase.tscn

RETRO_TAB=12 RETRO_NATIVE_AUTO=bake \
  ./dist/linux/GodotRetroEngine --editor --path dist/linux/ide \
  res://demo/native3d.tscn
```
