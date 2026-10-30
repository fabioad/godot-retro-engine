extends SceneTree
func _initialize() -> void:
	await process_frame
	var W = preload("res://addons/retro_engine/window_controls.gd")
	var host := Window.new()
	get_root().add_child(host)
	var box := HBoxContainer.new()
	host.add_child(box)
	var row = W.add_controls(box, host, true)
	var count := row.get_child_count()
	var icons := 0
	for b in row.get_children():
		if b is Button and b.icon != null:
			icons += 1
	var win := Window.new()
	get_root().add_child(win)
	win.mode = Window.MODE_WINDOWED
	var usable := DisplayServer.screen_get_usable_rect()
	var max_ok := true
	if usable.size.x > 0 and usable.size.y > 0:
		W.toggle_maximize(win)
		max_ok = W.is_maximized()
		W.toggle_maximize(win)
		max_ok = max_ok and not W.is_maximized()
	var dlg = preload("res://addons/retro_engine/game_build_dialog.gd").new()
	get_root().add_child(dlg)
	await process_frame
	var found := false
	for c in dlg.find_children("*", "HBoxContainer", true, false):
		if String(c.name) == "WindowControls":
			found = c.get_child_count() == 3
	print("WINDOW_CONTROLS ", "PASS" if count == 3 and icons == 3 and found and max_ok else "FAIL", " buttons=", count, " icons=", icons, " dialog=", found, " dbl=", max_ok)
	host.queue_free(); win.queue_free(); dlg.queue_free()
	quit(0 if count == 3 and icons == 3 and found and max_ok else 1)
