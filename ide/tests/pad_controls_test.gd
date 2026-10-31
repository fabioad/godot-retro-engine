extends SceneTree
## On-screen pad labels/masks follow the active console joypad.

const PadControls = preload("res://addons/retro_engine/pad_controls.gd")

func _initialize() -> void:
	await process_frame
	var pad = PadControls.new()
	get_root().add_child(pad)
	await process_frame
	pad.set_platform("snes")
	var snes: Array = []
	for button in pad._face_buttons:
		snes.append(button.text)
	var snes_select: String = pad._select_button.text
	var snes_ok: bool = snes == ["L", "X", "R", "Y", "B", "A"] and snes_select == "SEL"
	snes_ok = snes_ok and pad._mask_for("A") == 1 << 8 and pad._mask_for("B") == 1 << 0
	snes_ok = snes_ok and pad._mask_for("X") == 1 << 9 and pad._mask_for("Y") == 1 << 1
	snes_ok = snes_ok and pad._mask_for("L") == 1 << 10 and pad._mask_for("R") == 1 << 11
	snes_ok = snes_ok and pad._mask_for("START") == 1 << 3 and pad._mask_for("SEL") == 1 << 2
	snes_ok = snes_ok and pad._mask_for("LEFT") == 1 << 6 and pad._mask_for("RIGHT") == 1 << 7
	snes_ok = snes_ok and pad._mask_for("UP") == 1 << 4 and pad._mask_for("DOWN") == 1 << 5

	pad.set_platform("megadrive")
	var md: Array = []
	for button in pad._face_buttons:
		md.append(button.text)
	var md_select: String = pad._select_button.text
	var md_ok: bool = md == ["X", "Y", "Z", "A", "B", "C"] and md_select == "MODE"
	md_ok = md_ok and pad._mask_for("A") == 1 << 1 and pad._mask_for("B") == 1 << 0
	md_ok = md_ok and pad._mask_for("C") == 1 << 8 and pad._mask_for("X") == 1 << 10
	md_ok = md_ok and pad._mask_for("Y") == 1 << 9 and pad._mask_for("Z") == 1 << 11
	md_ok = md_ok and pad._mask_for("START") == 1 << 3 and pad._mask_for("MODE") == 1 << 2
	md_ok = md_ok and pad._mask_for("LEFT") == 1 << 6 and pad._mask_for("RIGHT") == 1 << 7
	md_ok = md_ok and pad._mask_for("UP") == 1 << 4 and pad._mask_for("DOWN") == 1 << 5

	print("PAD_CONTROLS snes=", snes, " sel=", snes_select,
		" md=", md, " mode=", md_select)
	print("PAD_CONTROLS ", "PASS" if snes_ok and md_ok else "FAIL")
	pad.queue_free()
	await process_frame
	quit(0 if snes_ok and md_ok else 1)
