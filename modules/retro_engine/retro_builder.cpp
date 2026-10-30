/**************************************************************************/
/*  retro_builder.cpp                                                     */
/**************************************************************************/

#include "core/object/class_db.h"

#include "retro_builder.h"

#include "retro_sdk.h"
#include "retro_util.h"

#include "core/io/file_access.h"
#include "core/os/os.h"
#include "core/os/time.h"

void RetroBuilder::_bind_methods() {
	ClassDB::bind_method(D_METHOD("build", "project", "target", "clean_first", "debug"),
			&RetroBuilder::build, DEFVAL(String()), DEFVAL(false), DEFVAL(false));
	ClassDB::bind_method(D_METHOD("clean", "project"), &RetroBuilder::clean);
	ClassDB::bind_method(D_METHOD("cancel"), &RetroBuilder::cancel);
	ClassDB::bind_method(D_METHOD("is_building"), &RetroBuilder::is_building);
	ClassDB::bind_method(D_METHOD("get_last_log"), &RetroBuilder::get_last_log);
	ClassDB::bind_method(D_METHOD("get_last_result"), &RetroBuilder::get_last_result);

	ADD_SIGNAL(MethodInfo("build_started", PropertyInfo(Variant::STRING, "command")));
	ADD_SIGNAL(MethodInfo("log_line", PropertyInfo(Variant::STRING, "line"), PropertyInfo(Variant::INT, "level")));
	ADD_SIGNAL(MethodInfo("build_finished", PropertyInfo(Variant::BOOL, "success"), PropertyInfo(Variant::DICTIONARY, "result")));
}

RetroBuilder::RetroBuilder() = default;

void RetroBuilder::_notification(int p_what) {
	if (p_what == NOTIFICATION_PREDELETE) {
		cancel_requested = true;
		if (thread.is_started()) {
			thread.wait_to_finish();
		}
	}
}

String RetroBuilder::_build_command(const String &p_target) const {
	if (!project.is_valid()) {
		return String();
	}
	if (!project->get_build_command().strip_edges().is_empty()) {
		return project->get_build_command();
	}
	const String path = project->get_path();
	const String sdk = project->get_sdk_path();
	String env;
	if (project->get_platform() == "snes" && !sdk.is_empty()) {
		env += "PVSNESLIB_HOME=" + RetroUtil::shell_quote(sdk) + " ";
		// Raw WLA-DX projects can use the assembler/linker shipped with
		// PVSnesLib. Environment variables act as make variable defaults.
		const String wla = RetroUtil::which(sdk.path_join("devkitsnes/bin/wla-65816"));
		const String wlalink = RetroUtil::which(sdk.path_join("devkitsnes/bin/wlalink"));
		const String wla_spc = RetroUtil::which(sdk.path_join("devkitsnes/bin/wla-spc700"));
		if (!wla.is_empty()) {
			env += "WLA=" + RetroUtil::shell_quote(wla) + " ";
		}
		if (!wlalink.is_empty()) {
			env += "WLALINK=" + RetroUtil::shell_quote(wlalink) + " ";
		}
		if (!wla_spc.is_empty()) {
			env += "WLA_SPC=" + RetroUtil::shell_quote(wla_spc) + " ";
		}
		env += "PATH=" + RetroUtil::shell_quote(sdk.path_join("devkitsnes/bin")) + ":$PATH ";
	}
	if (project->get_platform() == "megadrive" && !sdk.is_empty()) {
		env += "GDK=" + RetroUtil::shell_quote(sdk) + " ";
		env += "RETRO_SGDK_ROOT=" + RetroUtil::shell_quote(sdk) + " ";
		env += "PATH=" + RetroUtil::shell_quote(sdk.path_join("bin")) + ":$PATH ";
		// If the IDE was launched without vendor/sgdk-linux/env.sh, add the
		// local Wine-wrapped m68k-elf toolchain explicitly.
		const Dictionary md_info = RetroSDK::get_singleton()->probe_megadrive(sdk);
		const Dictionary linux_info = md_info.get("linux", Dictionary());
		const String gcc = String(linux_info.get("m68k_elf_gcc", ""));
		if (!gcc.is_empty()) {
			env += "PATH=" + RetroUtil::shell_quote(gcc.get_base_dir()) + ":$PATH ";
		}
	}
	if (project->get_platform() == "snes" && debug_build) {
		env += "PVSNESLIB_DEBUG=1 ";
	}

	String target = p_target;
	if (target.is_empty()) {
		target = project->get_build_target();
	}
	if (debug_build && project->get_build_system() == "sgdk" && target.is_empty()) {
		target = "debug";
	}

	String make = RetroUtil::which("make");
	if (make.is_empty()) {
		make = "make";
	}
	String command = "cd " + RetroUtil::shell_quote(path) + " && ";
	if (!env.is_empty()) {
		command += "env " + env;
	}
	String build_file = project->get_build_file();
	if (project->get_build_system() == "sgdk" && !FileAccess::exists(RetroUtil::join(path, build_file))) {
		// Fall back to SGDK's generic makefile.
		build_file = RetroUtil::join(sdk, "makefile.gen");
	}
	command += RetroUtil::shell_quote(make);
	if (!build_file.is_empty()) {
		String bf = build_file;
		if (!bf.is_absolute_path()) {
			bf = RetroUtil::join(path, bf);
		}
		if (FileAccess::exists(bf)) {
			command += " -f " + RetroUtil::shell_quote(bf);
		}
	}
	if (!target.is_empty()) {
		command += " " + target;
	}
	// SGDK resource scripts (.res) are not properly ordered against the C
	// objects in its stock makefile, so a parallel first build can compile C
	// before the generated header exists. Use one job for SGDK.
	int jobs = MAX(1, OS::get_singleton()->get_processor_count() - 1);
	if (project->get_build_system() == "sgdk") {
		jobs = 1;
	}
	command += " -j" + itos(MIN(jobs, 12));
	if (project->get_build_system() == "sgdk" && !sdk.is_empty()) {
		const String libgcc = sdk.path_join("lib/libgcc.a");
		if (FileAccess::exists(libgcc)) {
			command += " LIBGCC=" + RetroUtil::shell_quote(libgcc);
		}
	}
	return command;
}

String RetroBuilder::_clean_command() const {
	if (!project.is_valid()) {
		return String();
	}
	const String path = project->get_path();
	const String sdk = project->get_sdk_path();
	String env;
	if (project->get_platform() == "snes" && !sdk.is_empty()) {
		env += "PVSNESLIB_HOME=" + RetroUtil::shell_quote(sdk) + " ";
		const String wla = RetroUtil::which(sdk.path_join("devkitsnes/bin/wla-65816"));
		const String wlalink = RetroUtil::which(sdk.path_join("devkitsnes/bin/wlalink"));
		const String wla_spc = RetroUtil::which(sdk.path_join("devkitsnes/bin/wla-spc700"));
		if (!wla.is_empty()) { env += "WLA=" + RetroUtil::shell_quote(wla) + " "; }
		if (!wlalink.is_empty()) { env += "WLALINK=" + RetroUtil::shell_quote(wlalink) + " "; }
		if (!wla_spc.is_empty()) { env += "WLA_SPC=" + RetroUtil::shell_quote(wla_spc) + " "; }
		env += "PATH=" + RetroUtil::shell_quote(sdk.path_join("devkitsnes/bin")) + ":$PATH ";
	}
	if (project->get_platform() == "megadrive" && !sdk.is_empty()) {
		env += "GDK=" + RetroUtil::shell_quote(sdk) + " ";
		env += "RETRO_SGDK_ROOT=" + RetroUtil::shell_quote(sdk) + " ";
		env += "PATH=" + RetroUtil::shell_quote(sdk.path_join("bin")) + ":$PATH ";
		// If the IDE was launched without vendor/sgdk-linux/env.sh, add the
		// local Wine-wrapped m68k-elf toolchain explicitly.
		const Dictionary md_info = RetroSDK::get_singleton()->probe_megadrive(sdk);
		const Dictionary linux_info = md_info.get("linux", Dictionary());
		const String gcc = String(linux_info.get("m68k_elf_gcc", ""));
		if (!gcc.is_empty()) {
			env += "PATH=" + RetroUtil::shell_quote(gcc.get_base_dir()) + ":$PATH ";
		}
	}
	String make = RetroUtil::which("make");
	if (make.is_empty()) {
		make = "make";
	}
	String command = "cd " + RetroUtil::shell_quote(path) + " && ";
	if (!env.is_empty()) {
		command += "env " + env;
	}
	command += RetroUtil::shell_quote(make);
	const String build_file = project->get_build_file();
	if (!build_file.is_empty() && FileAccess::exists(RetroUtil::join(path, build_file))) {
		command += " -f " + RetroUtil::shell_quote(RetroUtil::join(path, build_file));
	}
	const String clean_target = project->get_clean_target().is_empty() ? "clean" : project->get_clean_target();
	command += " " + clean_target;
	return command;
}

Error RetroBuilder::build(Ref<RetroProject> p_project, const String &p_target, bool p_clean_first, bool p_debug) {
	if (building) {
		return ERR_BUSY;
	}
	if (!p_project.is_valid()) {
		return ERR_INVALID_PARAMETER;
	}
	if (!RetroUtil::is_dir(p_project->get_path())) {
		return ERR_FILE_NOT_FOUND;
	}
	const String system = p_project->get_build_system();
	const bool generated = bool(p_project->get_metadata().get("generated_game", false));
	if (system == "pvsneslib" || system == "sgdk" || (generated && system == "make")) {
		const String platform = p_project->get_platform();
		String sdk = p_project->get_sdk_path();
		if (sdk.is_empty()) {
			sdk = String(RetroSDK::get_singleton()->get_sdk(platform).get("path", ""));
		}
		if (sdk.is_empty()) {
			return ERR_UNCONFIGURED;
		}
		const Dictionary probe = platform == "snes"
				? RetroSDK::get_singleton()->probe_snes(sdk)
				: RetroSDK::get_singleton()->probe_megadrive(sdk);
		if (!bool(probe.get("ready", false))) {
			return ERR_UNCONFIGURED;
		}
	}
	project = p_project;
	requested_target = p_target;
	clean_first = p_clean_first;
	if (p_target == "__clean_only__") {
		clean_first = false;
	}
	debug_build = p_debug;
	cancel_requested = false;
	building = true;
	full_log = String();
	last_result = Dictionary();
	thread.start(&RetroBuilder::_thread_entry, this);
	return OK;
}

Error RetroBuilder::clean(Ref<RetroProject> p_project) {
	if (building) {
		return ERR_BUSY;
	}
	if (!p_project.is_valid()) {
		return ERR_INVALID_PARAMETER;
	}
	project = p_project;
	requested_target = "__clean_only__";
	running_command = _clean_command();
	if (running_command.is_empty()) {
		return ERR_INVALID_PARAMETER;
	}
	building = true;
	cancel_requested = false;
	full_log = String();
	thread.start(&RetroBuilder::_thread_entry, this);
	return OK;
}

void RetroBuilder::cancel() {
	cancel_requested = true;
}

void RetroBuilder::_thread_entry(void *p_user) {
	static_cast<RetroBuilder *>(p_user)->_run_build();
}

void RetroBuilder::_append_line(const String &p_line, int p_level) {
	// Strip ANSI colour sequences emitted by GCC without depending on the
	// optional RegEx module.
	String line;
	for (int i = 0; i < p_line.length(); i++) {
		if (p_line[i] == 0x1B && i + 1 < p_line.length() && p_line[i + 1] == '[') {
			i += 2;
			while (i < p_line.length() && !((p_line[i] >= 'A' && p_line[i] <= 'Z') || (p_line[i] >= 'a' && p_line[i] <= 'z'))) {
				i++;
			}
			continue;
		}
		line += String::chr(p_line[i]);
	}
	{
		MutexLock lock(mutex);
		full_log += line + "\n";
	}
	call_deferred("emit_signal", "log_line", line, p_level);
}

int RetroBuilder::_execute(const String &p_command, bool p_allow_failure) {
	if (p_command.strip_edges().is_empty()) {
		return -1;
	}
	_append_line(">> " + p_command, 0);
	Dictionary pipes = OS::get_singleton()->execute_with_pipe("/bin/sh", List<String>{ "-c", p_command }, false);
	if (pipes.is_empty()) {
		_append_line("Failed to start process: " + p_command, 2);
		return -1;
	}
	Ref<FileAccess> out = pipes.get("stdio", Ref<FileAccess>());
	Ref<FileAccess> err = pipes.get("stderr", Ref<FileAccess>());
	ProcessID pid = int64_t(pipes.get("pid", 0));
	String pending_out;
	String pending_err;
	Vector<uint8_t> buf;
	buf.resize(16384);

	auto pump = [&](const Ref<FileAccess> &p_file, String &r_pending) {
		if (p_file.is_null()) {
			return;
		}
		for (int guard = 0; guard < 16; guard++) {
			const int n = p_file->get_buffer(buf.ptrw(), buf.size());
			if (n <= 0) {
				break;
			}
			r_pending += RetroUtil::decode_text(buf.ptr(), n);
			int nl = r_pending.find("\n");
			while (nl >= 0) {
				const String line = r_pending.substr(0, nl);
				r_pending = r_pending.substr(nl + 1);
				_append_line(line, line.to_lower().contains("error") ? 2 : (line.to_lower().contains("warning") ? 1 : 0));
				nl = r_pending.find("\n");
			}
		}
	};

	int exit_code = -1;
	while (true) {
		pump(out, pending_out);
		pump(err, pending_err);
		if (cancel_requested) {
			OS::get_singleton()->kill(pid);
			exit_code = -2;
			break;
		}
		if (pid != 0 && !OS::get_singleton()->is_process_running(pid)) {
			// Drain remaining output.
			for (int i = 0; i < 8; i++) {
				pump(out, pending_out);
				pump(err, pending_err);
				OS::get_singleton()->delay_usec(20000);
			}
			exit_code = OS::get_singleton()->get_process_exit_code(pid);
			break;
		}
		OS::get_singleton()->delay_usec(40000);
	}
	if (!pending_out.is_empty()) {
		_append_line(pending_out, 0);
	}
	if (!pending_err.is_empty()) {
		_append_line(pending_err, 2);
	}
	if (out.is_valid()) {
		out->close();
	}
	if (err.is_valid()) {
		err->close();
	}
	if (exit_code != 0 && !p_allow_failure) {
		return exit_code;
	}
	return exit_code;
}

void RetroBuilder::_parse_diagnostics() {
	// This is diagnostic extraction for the UI; the raw log is always kept.
}

void RetroBuilder::_run_build() {
	last_result = Dictionary();
	const uint64_t start = Time::get_singleton()->get_ticks_msec();
	int code = 0;
	if (requested_target == "__clean_only__") {
		running_command = _clean_command();
		call_deferred("emit_signal", "build_started", running_command);
		_append_line("Clean: " + running_command, 0);
		code = _execute(running_command);
		last_result["ok"] = code == 0;
		last_result["success"] = code == 0;
		last_result["exit_code"] = code;
		last_result["clean"] = true;
		last_result["command"] = running_command;
		{
			MutexLock lock(mutex);
			last_result["log"] = full_log;
		}
		building = false;
		call_deferred("emit_signal", "build_finished", code == 0, last_result);
		return;
	}
	call_deferred("emit_signal", "build_started", _build_command(requested_target));
	if (clean_first) {
		running_command = _clean_command();
		_append_line("Cleaning project...", 0);
		_execute(running_command, true);
	}
	running_command = _build_command(requested_target);
	_append_line("Build: " + running_command, 0);
	code = _execute(running_command);

	// Parse diagnostics from the accumulated log. We deliberately do not use
	// a regex engine here: the build module must stay independent from the
	// optional RegEx module.
	Array errors;
	Array warnings;
	String log;
	{
		MutexLock lock(mutex);
		log = full_log;
	}
	const PackedStringArray lines = log.split("\n");
	for (int i = 0; i < lines.size(); i++) {
		const String line = lines[i].strip_edges();
		if (line.is_empty()) {
			continue;
		}
		const int c1 = line.find(":");
		if (c1 <= 0) {
			if (line.contains("undefined reference to") || line.contains("multiple definition of")) {
				Dictionary d;
				d["file"] = "";
				d["line"] = 0;
				d["column"] = 0;
				d["severity"] = "error";
				d["message"] = line;
				d["raw"] = line;
				errors.push_back(d);
			}
			continue;
		}
		const String file = line.substr(0, c1);
		String rest = line.substr(c1 + 1);
		const int c2 = rest.find(":");
		if (c2 <= 0) {
			continue;
		}
		const String line_s = rest.substr(0, c2);
		if (!line_s.is_valid_int()) {
			continue;
		}
		int line_no = line_s.to_int();
		rest = rest.substr(c2 + 1);
		int column = 0;
		const int c3 = rest.find(":");
		if (c3 > 0 && rest.substr(0, c3).is_valid_int()) {
			column = rest.substr(0, c3).to_int();
			rest = rest.substr(c3 + 1);
		}
		const String lower = rest.to_lower();
		int sev_pos = lower.find("error");
		String severity = "error";
		if (sev_pos < 0) {
			sev_pos = lower.find("warning");
			severity = "warning";
		}
		if (sev_pos < 0) {
			sev_pos = lower.find("note");
			severity = "note";
		}
		if (sev_pos < 0) {
			continue;
		}
		int msg_start = rest.find(":", sev_pos);
		String message = msg_start >= 0 ? rest.substr(msg_start + 1).strip_edges() : rest.strip_edges();
		Dictionary d;
		d["file"] = file;
		d["line"] = line_no;
		d["column"] = column;
		d["severity"] = severity;
		d["message"] = message;
		d["raw"] = line;
		if (severity == "error") {
			errors.push_back(d);
		} else if (severity == "warning") {
			warnings.push_back(d);
		}
		if (errors.size() > 1000) {
			break;
		}
	}

	String rom = RetroUtil::find_rom(project->get_path());
	if (!rom.is_empty()) {
		project->set_rom_path(rom);
	}
	uint64_t rom_size = rom.is_empty() ? 0 : uint64_t(FileAccess::get_size(rom));
	const bool success = code == 0 && (rom.is_empty() ? errors.is_empty() : true);

	last_result["ok"] = success;
	last_result["success"] = success;
	last_result["exit_code"] = code;
	last_result["command"] = running_command;
	last_result["log"] = log;
	last_result["errors"] = errors;
	last_result["warnings"] = warnings;
	last_result["error_count"] = errors.size();
	last_result["warning_count"] = warnings.size();
	last_result["rom_path"] = rom;
	last_result["rom_size"] = int64_t(rom_size);
	last_result["rom_size_human"] = RetroUtil::human_size(rom_size);
	last_result["duration_ms"] = int64_t(Time::get_singleton()->get_ticks_msec() - start);
	last_result["platform"] = project->get_platform();
	last_result["project"] = project->get_name();
	last_result["cancelled"] = code == -2;

	if (!rom.is_empty()) {
		project->save();
	}
	building = false;
	call_deferred("emit_signal", "build_finished", success, last_result);
}

String RetroBuilder::get_last_log() const {
	MutexLock lock(mutex);
	return full_log;
}

Dictionary RetroBuilder::get_last_result() const {
	return last_result;
}
