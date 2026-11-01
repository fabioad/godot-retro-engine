/**************************************************************************/
/*  retro_emulator.cpp                                                    */
/**************************************************************************/

#include "core/object/class_db.h"

#include "retro_emulator.h"

#include "retro_sdk.h"
#include "retro_util.h"

#include "core/io/file_access.h"
#include "core/os/os.h"

void RetroEmulator::_bind_methods() {
	ClassDB::bind_static_method("RetroEmulator", D_METHOD("detect", "platform"), &RetroEmulator::detect, DEFVAL(String()));
	ClassDB::bind_static_method("RetroEmulator", D_METHOD("launch", "rom", "emulator_id", "extra_args"), &RetroEmulator::launch, DEFVAL(String()), DEFVAL(Array()));
	ClassDB::bind_static_method("RetroEmulator", D_METHOD("launch_debug", "rom", "emulator_id"), &RetroEmulator::launch_debug, DEFVAL(String()));
	ClassDB::bind_static_method("RetroEmulator", D_METHOD("probe_rom", "rom"), &RetroEmulator::probe_rom);
	ClassDB::bind_static_method("RetroEmulator", D_METHOD("supports_debug", "emulator_id"), &RetroEmulator::supports_debug);
	ClassDB::bind_static_method("RetroEmulator", D_METHOD("is_running", "pid"), &RetroEmulator::is_running);
	ClassDB::bind_static_method("RetroEmulator", D_METHOD("terminate", "pid"), &RetroEmulator::terminate);
}

Array RetroEmulator::detect(const String &p_platform) {
	RetroSDK *sdk = RetroSDK::get_singleton();
	if (!sdk) {
		return Array();
	}
	if (!p_platform.is_empty()) {
		return sdk->get_emulators(p_platform);
	}
	Array all;
	Array snes = sdk->get_emulators("snes");
	Array md = sdk->get_emulators("megadrive");
	for (int i = 0; i < snes.size(); i++) {
		all.push_back(snes[i]);
	}
	for (int i = 0; i < md.size(); i++) {
		all.push_back(md[i]);
	}
	return all;
}

static Dictionary _launch_with(const Dictionary &p_emulator, const String &p_rom, const Array &p_extra_args, const String &p_debug_flag) {
	Dictionary result;
	const String exec = p_emulator.get("executable", String());
	String argline = p_emulator.get("args", String("{rom}"));
	argline = argline.replace("{rom}", p_rom);
	List<String> args;
	// Split on spaces, honouring double quotes.
	String current;
	bool quoted = false;
	for (int i = 0; i < argline.length(); i++) {
		const char32_t c = argline[i];
		if (c == '"') {
			quoted = !quoted;
		} else if (c == ' ' && !quoted) {
			if (!current.is_empty()) {
				args.push_back(current);
				current = String();
			}
		} else {
			current += String::chr(c);
		}
	}
	if (!current.is_empty()) {
		args.push_back(current);
	}
	if (!p_debug_flag.is_empty()) {
		args.push_back(p_debug_flag);
	}
	for (int i = 0; i < p_extra_args.size(); i++) {
		args.push_back(String(p_extra_args[i]));
	}
	ProcessID pid = 0;
	const Error err = OS::get_singleton()->create_process(exec, args, &pid);
	result["ok"] = err == OK;
	result["pid"] = int64_t(pid);
	result["executable"] = exec;
	Array a;
	for (const List<String>::Element *E = args.front(); E; E = E->next()) {
		a.push_back(E->get());
	}
	result["args"] = a;
	result["rom"] = p_rom;
	result["emulator"] = p_emulator.get("name", String());
	if (err != OK) {
		result["error"] = "Could not start " + exec + " (error " + itos(err) + ").";
	}
	return result;
}

Dictionary RetroEmulator::launch(const String &p_rom, const String &p_emulator_id, const Array &p_extra_args) {
	Dictionary result;
	if (!FileAccess::exists(p_rom)) {
		result["ok"] = false;
		result["error"] = "ROM not found: " + p_rom;
		return result;
	}
	const Dictionary probe = probe_rom(p_rom);
	const String platform = probe.get("platform", "snes");
	Array emulators = detect(platform);
	Dictionary chosen;
	for (int i = 0; i < emulators.size(); i++) {
		const Dictionary e = emulators[i];
		if (p_emulator_id.is_empty() || String(e.get("id", "")) == p_emulator_id) {
			chosen = e;
			break;
		}
	}
	if (chosen.is_empty()) {
		result["ok"] = false;
		result["error"] = p_emulator_id.is_empty()
				? "No emulator installed for " + platform + ". Install Mesen/bsnes/Snes9x or BlastEm."
				: "Emulator '" + p_emulator_id + "' is not installed.";
		result["available"] = emulators;
		return result;
	}
	return _launch_with(chosen, p_rom, p_extra_args, String());
}

Dictionary RetroEmulator::launch_debug(const String &p_rom, const String &p_emulator_id) {
	Dictionary result;
	if (!FileAccess::exists(p_rom)) {
		result["ok"] = false;
		result["error"] = "ROM not found: " + p_rom;
		return result;
	}
	const String platform = probe_rom(p_rom).get("platform", "snes");
	Array emulators = detect(platform);
	Dictionary chosen;
	for (int i = 0; i < emulators.size(); i++) {
		const Dictionary e = emulators[i];
		if ((p_emulator_id.is_empty() && supports_debug(String(e.get("id", "")))) ||
				String(e.get("id", "")) == p_emulator_id) {
			chosen = e;
			break;
		}
	}
	if (chosen.is_empty()) {
		result["ok"] = false;
		result["error"] = "No debug-capable emulator selected/detected. BlastEm (-d) and Gens KMod are supported when installed.";
		return result;
	}
	const String id = chosen.get("id", "");
	String flag;
	if (id == "blastem" || id == "gens-kmod" || id == "gens") {
		// BlastEm documents "-d Enter debugger on startup". Gens KMod has
		// historically used the same switch; it is only offered when the
		// binary was actually detected.
		flag = "-d";
	}
	if (flag.is_empty()) {
		result["ok"] = false;
		result["error"] = "The selected emulator (" + String(chosen.get("name", id)) + ") does not expose a documented debugger CLI flag. Launch it normally and attach its monitor manually.";
		return result;
	}
	return _launch_with(chosen, p_rom, Array(), flag);
}

Dictionary RetroEmulator::probe_rom(const String &p_rom) {
	Dictionary out;
	const int64_t size = FileAccess::get_size(p_rom);
	out["size"] = int64_t(size);
	const Vector<uint8_t> data = RetroUtil::read_bytes(p_rom);
	String platform;
	String mapper;
	String title;
	const String ext = p_rom.get_extension().to_lower();

	// Mega Drive must be checked before the SNES header heuristic: a 68k ROM
	// can contain arbitrary bytes at 0x7FC0 that happen to resemble a SNES
	// map-mode byte.
	bool is_md = false;
	if (data.size() > 0x104) {
		String sega;
		for (int i = 0; i < 4; i++) {
			sega += String::chr(data[0x100 + i]);
		}
		is_md = sega == "SEGA";
	}
	if (is_md) {
		platform = "megadrive";
		String t;
		for (int i = 0; i < 16 && 0x150 + i < data.size(); i++) {
			const uint8_t c = data[0x150 + i];
			t += (c >= 32 && c < 127) ? String::chr(c) : String::chr(' ');
		}
		title = t.strip_edges();
		mapper = data.size() > 0x400000 ? "SSF2 / Pier Solar / custom mapper (size-dependent)" : "Sega 4 MiB linear mapper";
		if (data.size() > 0x1A0) {
			out["region"] = String::chr(data[0x1F0]);
		}
	} else {
		// SNES: inspect LoROM/HiROM/ExHiROM header positions and require a
		// plausible size byte plus a valid checksum complement.
		int header = 0x7FC0;
		bool found = false;
		int headers[] = { 0x7FC0, 0xFFC0, 0x40FFC0 };
		if (data.size() > 0x400000) {
			headers[0] = 0x40FFC0;
			headers[1] = 0xFFC0;
			headers[2] = 0x7FC0;
		}
		for (int h = 0; h < 3; h++) {
			const int pos = headers[h];
			if (pos + 0x20 > data.size()) {
				continue;
			}
			const int csum = (data[pos + 0x1F] << 8) | data[pos + 0x1E];
			const int comp = (data[pos + 0x1D] << 8) | data[pos + 0x1C];
			const uint8_t size_byte = data[pos + 0x17];
			const uint8_t map_mode = data[pos + 0x15];
			const bool checksum_ok = ((csum + comp) & 0xFFFF) == 0xFFFF;
			if (checksum_ok && size_byte >= 0x05 && size_byte <= 0x0D && map_mode != 0) {
				header = pos;
				found = true;
				if (map_mode == 0x35) {
					mapper = "ExHiROM";
				} else if (map_mode == 0x32) {
					mapper = "HiROM (S-DD1)";
				} else if (map_mode & 0x01) {
					mapper = "HiROM";
				} else {
					mapper = "LoROM";
				}
				break;
			}
		}
		if (found || ext == "sfc" || ext == "smc") {
			platform = "snes";
			String t;
			for (int i = 0; i < 21 && header + i < data.size(); i++) {
				const uint8_t c = data[header + i];
				t += (c >= 32 && c < 127) ? String::chr(c) : String::chr(' ');
			}
			title = t.strip_edges();
			if (header + 0x20 <= data.size()) {
				const int csum = (data[header + 0x1F] << 8) | data[header + 0x1E];
				const int comp = (data[header + 0x1D] << 8) | data[header + 0x1C];
				const uint8_t map_mode = data[header + 0x15];
				out["map_mode"] = map_mode;
				out["rom_size_byte"] = data[header + 0x17];
				out["checksum"] = csum;
				out["complement"] = comp;
				out["checksum_valid"] = ((csum + comp) & 0xFFFF) == 0xFFFF;
			}
		} else if (ext == "md" || ext == "gen" || ext == "bin") {
			platform = "megadrive";
			mapper = "unknown Mega Drive mapper";
		}
	}
	if (platform.is_empty()) {
		platform = (ext == "md" || ext == "gen") ? "megadrive" : "snes";
	}
	out["platform"] = platform;
	out["mapper"] = mapper;
	out["title"] = title;
	out["path"] = p_rom;
	out["size_human"] = RetroUtil::human_size(size);
	uint32_t fingerprint = 0;
	for (int i = 0; i < MIN<int>(32, data.size()); i++) {
		if (data[i] != 0) {
			fingerprint = fingerprint * 31 + data[i];
		}
	}
	out["fingerprint"] = fingerprint;
	return out;
}

bool RetroEmulator::supports_debug(const String &p_emulator_id) {
	return p_emulator_id == "blastem" || p_emulator_id == "gens-kmod" || p_emulator_id == "gens";
}

bool RetroEmulator::is_running(int64_t p_pid) {
	if (p_pid <= 0) {
		return false;
	}
	return OS::get_singleton()->is_process_running(ProcessID(p_pid));
}

void RetroEmulator::terminate(int64_t p_pid) {
	if (p_pid > 0) {
		OS::get_singleton()->kill(ProcessID(p_pid));
	}
}
