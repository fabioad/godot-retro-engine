extends SceneTree
func _initialize() -> void:
	_go.call_deferred()
func _go() -> void:
	var p := RetroProject.new()
	p.set_name("smoke")
	p.set_path("/tmp")
	p.set_platform("snes")
	p.set_build_system("generic")
	p.set_build_command("echo HELLO_FROM_BUILDER; sleep 1; echo DONE")
	var b := RetroBuilder.new()
	get_root().add_child(b)
	b.log_line.connect(func(line, level): print("LOG[", level, "] ", line), CONNECT_DEFERRED)
	b.build_finished.connect(func(ok, res): print("FINISHED ", ok, " exit=", res.get("exit_code")), CONNECT_DEFERRED)
	b.build_started.connect(func(cmd): print("START ", cmd), CONNECT_DEFERRED)
	print("calling build")
	var err: int = b.build(p, "", false, false)
	print("build returned ", err)
	var t := 0
	while t < 20:
		await process_frame
		t += 1
		if t % 60 == 0: print("waiting ", t)
	print("done waiting")
	b.queue_free()
	quit(0)
