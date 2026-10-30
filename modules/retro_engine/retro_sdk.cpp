/**************************************************************************/
/*  retro_sdk.cpp                                                         */
/**************************************************************************/

#include "core/object/class_db.h"

#include "retro_sdk.h"

#include "retro_util.h"

#include "core/io/file_access.h"
#include "core/os/os.h"

RetroSDK *RetroSDK::singleton = nullptr;

void RetroSDK::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure", "platform", "path"), &RetroSDK::configure);
	ClassDB::bind_method(D_METHOD("get_configured_path", "platform"), &RetroSDK::get_configured_path);
	ClassDB::bind_method(D_METHOD("probe_snes", "path"), &RetroSDK::probe_snes);
	ClassDB::bind_method(D_METHOD("probe_megadrive", "path"), &RetroSDK::probe_megadrive);
	ClassDB::bind_method(D_METHOD("detect_all"), &RetroSDK::detect_all);
	ClassDB::bind_method(D_METHOD("get_sdk", "platform"), &RetroSDK::get_sdk);
	ClassDB::bind_method(D_METHOD("get_limits", "platform", "mode"), &RetroSDK::get_limits, DEFVAL(String()));
	ClassDB::bind_method(D_METHOD("get_modes", "platform"), &RetroSDK::get_modes);
	ClassDB::bind_method(D_METHOD("get_emulators", "platform"), &RetroSDK::get_emulators);
}

RetroSDK::RetroSDK() {
	singleton = this;
	snes_home = OS::get_singleton()->get_environment("PVSNESLIB_HOME");
	md_home = OS::get_singleton()->get_environment("GDK");
}

RetroSDK::~RetroSDK() {
	if (singleton == this) {
		singleton = nullptr;
	}
}

RetroSDK *RetroSDK::get_singleton() {
	return singleton;
}

void RetroSDK::configure(const String &p_platform, const String &p_path) {
	if (p_platform == "snes") {
		snes_home = RetroUtil::normalize(p_path);
	} else if (p_platform == "megadrive") {
		md_home = RetroUtil::normalize(p_path);
	}
}

String RetroSDK::get_configured_path(const String &p_platform) const {
	return p_platform == "snes" ? snes_home : (p_platform == "megadrive" ? md_home : String());
}

static String _find_vendor_tool(const String &p_tool) {
	const String exe_dir = OS::get_singleton()->get_executable_path().get_base_dir();
	const char *relatives[] = {
		"../vendor/sgdk-linux/bin",
		"../../vendor/sgdk-linux/bin",
		"../../../vendor/sgdk-linux/bin",
		"../../../../vendor/sgdk-linux/bin"
	};
	for (const char *rel : relatives) {
		const String candidate = exe_dir.path_join(rel).path_join(p_tool);
		if (FileAccess::exists(candidate)) {
			return candidate;
		}
	}
	return String();
}

static Dictionary _tool_report(const String &p_base, const Vector<String> &p_tools, const Vector<String> &p_required) {
	Dictionary tools;
	Array missing;
	for (int i = 0; i < p_tools.size(); i++) {
		const String name = p_tools[i];
		const String found = RetroUtil::which(p_base.path_join(name));
		tools[name] = found;
		if (found.is_empty()) {
			for (int r = 0; r < p_required.size(); r++) {
				if (p_required[r] == name) {
					missing.push_back(name);
					break;
				}
			}
		}
	}
	Dictionary out;
	out["tools"] = tools;
	out["missing_required"] = missing;
	out["ready"] = missing.is_empty();
	return out;
}

Dictionary RetroSDK::probe_snes(const String &p_path) const {
	Dictionary out;
	String root = RetroUtil::normalize(p_path);
	if (root.is_empty()) {
		return out;
	}
	// Accept either the SDK root (containing devkitsnes/ and pvsneslib/) or
	// the inner pvsneslib directory.
	if (!RetroUtil::exists(root.path_join("devkitsnes/bin/wla-65816")) &&
			!RetroUtil::exists(root.path_join("devkitsnes/bin/wla-65816.exe"))) {
		if (RetroUtil::exists(root.path_join("../devkitsnes/bin/wla-65816"))) {
			root = root.get_base_dir().simplify_path();
		} else if (RetroUtil::exists(root.path_join("pvsneslib/devkitsnes"))) {
			// unusual layout, keep as-is
		}
	}
	const bool has_rules = RetroUtil::exists(root.path_join("devkitsnes/snes_rules"));
	const bool has_lib = RetroUtil::exists(root.path_join("pvsneslib/lib/LoROM_SlowROM/crt0_snes.obj"));
	const bool has_include = RetroUtil::exists(root.path_join("pvsneslib/include/snes.h"));
	const String version = RetroUtil::read_text(root.path_join("pvsneslib/pvsneslib_version.txt")).strip_edges();
	if (!has_rules && !has_lib && !has_include) {
		out["found"] = false;
		return out;
	}

	Vector<String> tools;
	tools.push_back("devkitsnes/bin/816-tcc");
	tools.push_back("devkitsnes/bin/wla-65816");
	tools.push_back("devkitsnes/bin/wla-spc700");
	tools.push_back("devkitsnes/bin/wlalink");
	Vector<String> required;
	required.push_back("devkitsnes/bin/wla-65816");
	required.push_back("devkitsnes/bin/wlalink");
	Dictionary report = _tool_report(root, tools, required);

	const String gfx = RetroUtil::which(root.path_join("devkitsnes/tools/gfx4snes"));
	out["found"] = true;
	out["platform"] = "snes";
	out["path"] = root; // PVSNESLIB_HOME
	out["version"] = version.is_empty() ? "PVSnesLib (unknown)" : version;
	out["has_rules"] = has_rules;
	out["has_libraries"] = has_lib;
	out["has_headers"] = has_include;
	out["gfx4snes"] = gfx;
	out["tools"] = report["tools"];
	out["missing_required"] = report["missing_required"];
	out["ready"] = report["ready"];
	out["toolchain"] = has_rules && has_lib ? "pvsneslib-linux" : "incomplete";
	return out;
}

Dictionary RetroSDK::probe_megadrive(const String &p_path) const {
	Dictionary out;
	String root = RetroUtil::normalize(p_path);
	if (root.is_empty()) {
		return out;
	}
	if (!RetroUtil::exists(root.path_join("inc/genesis.h"))) {
		// Allow pointing at a project that includes makefile.gen.
		if (RetroUtil::exists(root.path_join("../inc/genesis.h"))) {
			root = root.get_base_dir().simplify_path();
		}
	}
	const bool has_header = RetroUtil::exists(root.path_join("inc/genesis.h"));
	const bool has_lib = RetroUtil::exists(root.path_join("lib/libmd.a"));
	const bool has_rescomp = RetroUtil::exists(root.path_join("bin/rescomp.jar"));
	if (!has_header && !has_lib && !has_rescomp) {
		out["found"] = false;
		return out;
	}

	const String header = RetroUtil::read_text(root.path_join("inc/genesis.h"));
	String version = "SGDK";
	const int vpos = header.find("SGDK_VERSION");
	if (vpos >= 0) {
		version = header.substr(vpos + 13, 32).strip_edges().get_slice("\n", 0).strip_edges();
	}

	Vector<String> tools;
	tools.push_back("bin/rescomp.jar");
	tools.push_back("bin/m68k-elf-gcc");
	tools.push_back("bin/sjasm");
	tools.push_back("bin/mac68k");
	tools.push_back("bin/bintos");
	tools.push_back("bin/convsym");
	Vector<String> required;
	required.push_back("bin/rescomp.jar");
	Dictionary report = _tool_report(root, tools, required);

	// On Linux the toolchain is usually installed system-wide.
	String sys_gcc = RetroUtil::which("m68k-elf-gcc");
	if (sys_gcc.is_empty()) {
		sys_gcc = _find_vendor_tool("m68k-elf-gcc");
	}
	const String java = RetroUtil::which("java");
	const bool linux_tools = RetroUtil::exists(root.path_join("bin/m68k-elf-gcc")) || !sys_gcc.is_empty();
	const bool resource_only = has_rescomp && !java.is_empty();

	Dictionary linux_info;
	linux_info["m68k_elf_gcc"] = sys_gcc.is_empty() ? String() : sys_gcc;
	linux_info["java"] = java.is_empty() ? String() : java;
	linux_info["system_tools"] = !sys_gcc.is_empty();
	linux_info["available"] = linux_tools;
	linux_info["resource_compiler_available"] = resource_only;

	out["found"] = true;
	out["platform"] = "megadrive";
	out["path"] = root; // GDK
	out["version"] = "SGDK " + version;
	out["has_libraries"] = has_lib;
	out["has_headers"] = has_header;
	out["has_rescomp"] = has_rescomp;
	out["tools"] = report["tools"];
	out["linux"] = linux_info;
	out["missing_required"] = report["missing_required"];
	// The C toolchain is required for full ROM builds. Resource compilation
	// alone only needs Java + rescomp.jar.
	out["ready"] = linux_tools && has_lib && has_header;
	out["resource_ready"] = resource_only;
	out["toolchain"] = linux_tools ? "sgdk-linux" : "sgdk-resources-only";
	return out;
}

Dictionary RetroSDK::detect_all() const {
	Dictionary out;
	Array snes_candidates;
	if (!snes_home.is_empty()) {
		snes_candidates.push_back(snes_home);
	}
	const String user_data = OS::get_singleton()->get_user_data_dir();
	snes_candidates.push_back(RetroUtil::join(user_data, "sdks/pvsneslib-4.6.0/pvsneslib"));
	snes_candidates.push_back(RetroUtil::join(user_data, "sdks/pvsneslib-4.6.0"));
	snes_candidates.push_back("/run/media/fabio/Dados/Fabio/pvsneslib-sdk-4.6");
	snes_candidates.push_back("/opt/pvsneslib");
	snes_candidates.push_back(RetroUtil::join(OS::get_singleton()->get_environment("HOME"), "pvsneslib"));
	snes_candidates.push_back(RetroUtil::join(OS::get_singleton()->get_environment("HOME"), "snesdev/pvsneslib"));

	Array md_candidates;
	if (!md_home.is_empty()) {
		md_candidates.push_back(md_home);
	}
	md_candidates.push_back(RetroUtil::join(user_data, "sdks/sgdk-2.11/SGDK-2.11"));
	md_candidates.push_back(RetroUtil::join(user_data, "sdks/sgdk-2.11"));
	md_candidates.push_back("/run/media/fabio/Dados/Fabio/sgdk211");
	md_candidates.push_back("/opt/sgdk");
	md_candidates.push_back(RetroUtil::join(OS::get_singleton()->get_environment("HOME"), "sgdk"));

	Dictionary snes;
	for (int i = 0; i < snes_candidates.size(); i++) {
		const String p = snes_candidates[i];
		if (p.is_empty()) {
			continue;
		}
		const Dictionary probe = probe_snes(p);
		if (probe.get("found", false)) {
			snes = probe;
			break;
		}
	}
	Dictionary md;
	for (int i = 0; i < md_candidates.size(); i++) {
		const String p = md_candidates[i];
		if (p.is_empty()) {
			continue;
		}
		const Dictionary probe = probe_megadrive(p);
		if (probe.get("found", false)) {
			md = probe;
			break;
		}
	}
	out["snes"] = snes;
	out["megadrive"] = md;
	return out;
}

Dictionary RetroSDK::get_sdk(const String &p_platform) const {
	const Dictionary all = detect_all();
	return all.get(p_platform, Dictionary());
}

Dictionary RetroSDK::get_limits(const String &p_platform, const String &p_mode) const {
	Dictionary d;
	if (p_platform == "snes") {
		d["name"] = "Super Nintendo / Super Famicom";
		d["cpu"] = "Ricoh 5A22 (65816) @ 3.58 MHz (FastROM 3.58)";
		d["ram_bytes"] = 131072;
		d["vram_bytes"] = 65536;
		d["palette_colors"] = 256;
		d["sprites_total"] = 128;
		d["sprites_per_line"] = 32;
		{ Array a; a.push_back(8); a.push_back(16); a.push_back(32); a.push_back(64); d["sprite_sizes"] = a; }
		d["oam_bytes"] = 544;
		d["cgram_bytes"] = 512;
		d["max_rom_bytes"] = 8388608;
		d["tile_4bpp_bytes"] = 32;
		d["audio_channels"] = 8;
		d["refresh_hz"] = 60.0988;
		d["native_width"] = 256;
		d["native_height"] = 224;
		if (p_mode.is_empty() || p_mode == "mode1") {
			d["mode"] = "mode1";
			d["bg_layers"] = 3;
			{ Array a; a.push_back(4); a.push_back(4); a.push_back(2); d["bg_bpp"] = a; }
			d["colors_per_palette"] = 16;
			d["bg_palettes"] = 8;
			d["resolution"] = "256x224 (512x224 hires)";
			d["description"] = "Mode 1: 2x 4bpp BG + 1x 2bpp BG, up to 8 BG palettes of 16 colors.";
		} else if (p_mode == "mode0") {
			d["mode"] = "mode0";
			d["bg_layers"] = 4;
			{ Array a; a.push_back(2); a.push_back(2); a.push_back(2); a.push_back(2); d["bg_bpp"] = a; }
			d["colors_per_palette"] = 4;
			d["bg_palettes"] = 8;
			d["resolution"] = "256x224 / 512x224";
			d["description"] = "Mode 0: 4x 2bpp BG layers, 4 colors per palette.";
		} else if (p_mode == "mode7") {
			d["mode"] = "mode7";
			d["bg_layers"] = 1;
			{ Array a; a.push_back(8); d["bg_bpp"] = a; }
			d["colors_per_palette"] = 256;
			d["bg_palettes"] = 1;
			d["resolution"] = "256x224 with affine transform";
			d["description"] = "Mode 7: one 8bpp 128x128 tilemap with affine rotation/scaling.";
		} else {
			d["mode"] = p_mode;
			d["bg_layers"] = 2;
			{ Array a; a.push_back(4); a.push_back(4); d["bg_bpp"] = a; }
			d["colors_per_palette"] = 16;
			d["bg_palettes"] = 8;
		}
		return d;
	}

	d["name"] = "Sega Mega Drive / Genesis";
	d["cpu"] = "Motorola 68000 @ 7.67 MHz + Z80 @ 3.58 MHz";
	d["ram_bytes"] = 65536;
	d["vram_bytes"] = 65536;
	d["palette_colors"] = 64;
	d["sprites_total"] = 80;
	d["sprites_per_line"] = 20;
	{ Array a; a.push_back(8); a.push_back(16); a.push_back(24); a.push_back(32); d["sprite_sizes"] = a; }
	d["max_rom_bytes"] = 4194304;
	d["tile_4bpp_bytes"] = 32;
	d["audio_channels"] = 10;
	d["refresh_hz"] = 59.92;
	d["native_width"] = 320;
	d["native_height"] = 224;
	d["colors_per_palette"] = 16;
	d["bg_palettes"] = 4;
	d["bg_layers"] = 3;
	{ Array a; a.push_back(4); a.push_back(4); a.push_back(4); d["bg_bpp"] = a; }
	d["resolution"] = "320x224 (H40) / 256x224 (H32)";
	d["description"] = "VDP planes A/B/Window, 80 hardware sprites, CRAM 64 colors, VRAM 64 KiB.";
	return d;
}

Array RetroSDK::get_modes(const String &p_platform) const {
	Array out;
	if (p_platform == "snes") {
		out.push_back("mode0");
		out.push_back("mode1");
		out.push_back("mode7");
	} else {
		out.push_back("h40");
		out.push_back("h32");
	}
	return out;
}

static void _add_emulator(Array &r_out, const String &p_id, const String &p_name, const String &p_platform,
		const String &p_exec, const String &p_args, const String &p_source) {
	Dictionary e;
	e["id"] = p_id;
	e["name"] = p_name;
	e["platform"] = p_platform;
	e["executable"] = p_exec;
	e["args"] = p_args;
	e["source"] = p_source;
	r_out.push_back(e);
}

Array RetroSDK::get_emulators(const String &p_platform) const {
	Array out;
	const String home = OS::get_singleton()->get_environment("HOME");
	struct Entry {
		const char *id;
		const char *name;
		const char *platform;
		const char *binary;
		const char *args;
	};
	const Entry snes[] = {
		{ "mesen", "Mesen", "snes", "mesen", "\"{rom}\"" },
		{ "bsnes", "bsnes", "snes", "bsnes", "\"{rom}\"" },
		{ "snes9x", "Snes9x", "snes", "snes9x-gtk", "\"{rom}\"" },
		{ "snes9x-cli", "Snes9x (CLI)", "snes", "snes9x", "\"{rom}\"" },
		{ "retroarch", "RetroArch", "snes", "retroarch", "-L mesen_libretro.so \"{rom}\"" },
	};
	const Entry md[] = {
		{ "blastem", "BlastEm", "megadrive", "blastem", "\"{rom}\"" },
		{ "gens", "Gens", "megadrive", "gens", "\"{rom}\"" },
		{ "gens-kmod", "Gens KMod", "megadrive", "gens-kmod", "\"{rom}\"" },
		{ "retroarch", "RetroArch", "megadrive", "retroarch", "-L genesis_plus_gx_libretro.so \"{rom}\"" },
	};
	const Entry *list = p_platform == "snes" ? snes : md;
	const int count = p_platform == "snes" ? int(sizeof(snes) / sizeof(Entry)) : int(sizeof(md) / sizeof(Entry));
	for (int i = 0; i < count; i++) {
		String found = RetroUtil::which(list[i].binary);
		if (found.is_empty()) {
			const String local = RetroUtil::join(home, String(".local/bin/") + list[i].binary);
			if (RetroUtil::is_executable_file(local)) {
				found = local;
			}
		}
		if (found.is_empty()) {
			const String games = String("/usr/games/") + list[i].binary;
			if (RetroUtil::is_executable_file(games)) {
				found = games;
			}
		}
		if (!found.is_empty()) {
			_add_emulator(out, list[i].id, list[i].name, list[i].platform, found, list[i].args, "native");
		}
	}
	// Flatpak fallbacks (installed but not on PATH).
	if (RetroUtil::is_executable_file("/usr/bin/flatpak") || RetroUtil::is_executable_file("/usr/local/bin/flatpak")) {
		if (p_platform == "snes") {
			_add_emulator(out, "bsnes-flatpak", "bsnes (Flatpak)", "snes", "flatpak", "run dev.bsnes.bsnes \"{rom}\"", "flatpak");
			_add_emulator(out, "snes9x-flatpak", "Snes9x (Flatpak)", "snes", "flatpak", "run com.snes9x.Snes9x \"{rom}\"", "flatpak");
		}
	}
	return out;
}
