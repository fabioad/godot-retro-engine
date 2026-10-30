/**************************************************************************/
/*  retro_importer.cpp                                                    */
/**************************************************************************/

#include "core/object/class_db.h"

#include "retro_importer.h"

#include "retro_graphics.h"
#include "retro_sdk.h"
#include "retro_util.h"

#include "core/io/file_access.h"
#include "core/io/image.h"
#include "core/os/time.h"
#include "core/templates/hash_map.h"

void RetroImporter::_bind_methods() {
	ClassDB::bind_method(D_METHOD("scan", "path", "platform_hint"), &RetroImporter::scan, DEFVAL(String()));
	ClassDB::bind_method(D_METHOD("import_project", "path", "platform_hint", "workspace", "copy", "name"),
			&RetroImporter::import_project, DEFVAL(String()), DEFVAL(true), DEFVAL(String()));
	ClassDB::bind_method(D_METHOD("inspect_resource", "path", "platform"), &RetroImporter::inspect_resource, DEFVAL(String()));
	ClassDB::bind_method(D_METHOD("detect_build_files", "path"), &RetroImporter::detect_build_files);
}

Array RetroImporter::detect_build_files(const String &p_path) {
	Array out;
	const String names[] = { "Makefile", "makefile", "GNUmakefile", "Makefile.pvsnes", "makefile.gen", "CMakeLists.txt" };
	for (const String &n : names) {
		const String f = RetroUtil::join(p_path, n);
		if (FileAccess::exists(f)) {
			Dictionary d;
			d["name"] = n;
			d["path"] = f;
			d["content"] = RetroUtil::read_text(f).substr(0, 20000);
			out.push_back(d);
		}
	}
	return out;
}

static Dictionary _retro_infer_map_layout(const String &p_map_path, const Dictionary &p_map_widths, bool p_has_stagedata) {
	Dictionary d;
	const int64_t bytes = FileAccess::get_size(p_map_path);
	const int entries = int(bytes / 2);
	if (entries <= 0) {
		return d;
	}
	const String stem = p_map_path.get_file().get_basename().to_upper();
	int w = 0;
	const String key = stem + "_MAPW";
	if (p_map_widths.has(key)) {
		w = int(p_map_widths[key]);
	}
	bool column = p_has_stagedata && w > 0;
	if (w <= 0) {
		// Common SNES layouts: 32x32, 64x32, 64x64. Sidearms-style maps
		// (240x32 column-major) are covered by stagedata.h above.
		if (entries == 4096) {
			w = 64;
		} else if (entries == 2048) {
			w = 64;
		} else if (entries == 1024) {
			w = 32;
		} else if (entries % 32 == 0 && entries > 2048) {
			w = 32;
		} else {
			w = 32;
		}
	}
	const int h = MAX(1, entries / MAX(1, w));
	d["map_w"] = w;
	d["map_h"] = h;
	d["map_entries"] = entries;
	d["column_major"] = column;
	d["map_layout"] = column ? "column-major" : "row-major";
	return d;
}

Dictionary RetroImporter::_classify_resource(const String &p_root, const String &p_file, const String &p_platform) {
	Dictionary d;
	const String rel = p_file.trim_prefix(p_root + "/");
	const String ext = RetroUtil::file_extension_lower(p_file);
	const String lower = rel.to_lower();
	const uint64_t size = FileAccess::get_size(p_file);

	String editor = "none";
	String kind = "unknown";
	bool editable = false;
	String note;

	if (ext == "png" || ext == "bmp" || ext == "webp" || ext == "jpg") {
		kind = "image";
		editable = true;
		if (lower.contains("tile") || lower.contains("bg") || lower.contains("stage") || lower.contains("background") || lower.contains("font")) {
			editor = "stage";
		} else if (lower.contains("sprite") || lower.contains("obj") || lower.contains("char") || lower.contains("player") || lower.contains("enemy")) {
			editor = "sprite";
		} else {
			editor = "image";
		}
	} else if (ext == "chr") {
		kind = "tiles_4bpp";
		editor = lower.contains("sprite") || lower.contains("obj") ? "sprite" : "stage";
		editable = true;
	} else if (ext == "pic") {
		kind = "pvsneslib_tiles";
		editor = "stage";
		editable = true;
		note = "Raw PVSnesLib gfx4snes tile blob (planar, usually 4bpp).";
	} else if (ext == "pal") {
		kind = p_platform == "megadrive" ? "cram_palette" : "cgram_palette";
		editor = "palette";
		editable = true;
	} else if (ext == "map") {
		kind = p_platform == "megadrive" ? "vdp_nametable" : "snes_tilemap";
		editor = "stage";
		editable = true;
	} else if (ext == "res") {
		kind = "sgdk_resource_script";
		editor = "resources";
		editable = true;
		note = "Compiled with rescomp.jar; source images are beside it.";
	} else if (ext == "sff") {
		kind = "mugen_sprite_bank";
		editor = "animation";
		editable = false;
		note = "Read-only in the IDE. Sprite frames are produced by the project's own SFF converter.";
	} else if (ext == "air") {
		kind = "mugen_animation";
		editor = "animation";
		editable = false;
		note = "MUGEN AIR animation data; editable as text only, not as visual timeline.";
	} else if (ext == "c" || ext == "h" || ext == "cpp" || ext == "hpp") {
		kind = "c_source";
		editor = "code";
		editable = true;
	} else if (ext == "asm" || ext == "s" || ext == "inc") {
		kind = "assembly_source";
		editor = "code";
		editable = true;
	} else if (ext == "mid" || ext == "it" || ext == "wav" || ext == "mp3") {
		kind = "audio";
		editor = "audio";
		editable = true;
		note = "Audio editor: import, convert and preview BGM/SFX for SNES and Mega Drive.";
	} else if (ext == "mod" || ext == "xm" || ext == "s3m" || ext == "vgm" || ext == "xgm" || ext == "xgm2" || ext == "brr" || ext == "msu" || ext == "spc") {
		kind = "audio";
		editor = "audio";
		editable = false;
		note = "Recognized audio asset. Use MIDI/IT/WAV/MP3 or the SFX synth to generate a new console asset.";
	} else if (ext == "json") {
		kind = "data";
		editor = "none";
		editable = false;
	} else if (ext == "bin" || ext == "o" || ext == "obj") {
		kind = "binary";
	} else if (ext == "zip" || ext == "7z" || ext == "rar" || ext == "tar" || ext == "gz") {
		kind = "archive";
	} else if (ext == "sfc" || ext == "smc" || ext == "md" || ext == "gen") {
		kind = "rom";
	} else if (ext == "py" || ext == "sh" || ext == "mk" || ext == "md") {
		kind = "tooling";
		editor = "code";
		editable = true;
	}

	d["id"] = rel.replace("/", "_");
	d["rel_path"] = rel;
	d["path"] = p_file;
	d["name"] = p_file.get_file();
	d["ext"] = ext;
	d["kind"] = kind;
	d["editor"] = editor;
	d["editable"] = editable;
	d["size"] = int64_t(size);
	d["note"] = note;
	d["group"] = editor;
	return d;
}

static String _find_companion(const String &p_root, const String &p_file, const String &p_ext) {
	const String base = p_file.get_basename();
	const String direct = base + "." + p_ext;
	if (FileAccess::exists(direct)) {
		return direct;
	}
	if (p_ext == "pal") {
		const String variants[] = { base + "_pal.bin", base + "_pal.pal", base + "_palette.bin", base + "_palette.pal" };
		for (const String &v : variants) {
			if (FileAccess::exists(v)) {
				return v;
			}
		}
	}
	// chr/pic and pal/map may share a stem with suffixes such as _pal.
	Array siblings = RetroUtil::list_files(p_file.get_base_dir(), false);
	for (int i = 0; i < siblings.size(); i++) {
		const String s = siblings[i];
		if (RetroUtil::file_extension_lower(s) == p_ext && s.get_file().to_lower().contains(p_file.get_file().get_basename().to_lower())) {
			return s;
		}
	}
	(void)p_root;
	return String();
}

// Working copies live under res://workspaces, inside the IDE's own Godot
// project. Without this marker Godot's editor importer scans them and treats
// native build artifacts such as WLA-DX / 816-tcc .obj files as Wavefront OBJ
// text, which prints thousands of UTF-8 errors and stalls the first scan at
// 99%. The IDE always accesses project files through absolute paths, so hiding
// the copy from Godot's resource importer is safe.
static void _ensure_godot_ignore(const String &p_dir) {
	const String marker = p_dir.path_join(".gdignore");
	if (!FileAccess::exists(marker)) {
		RetroUtil::write_text(marker, String());
	}
}

String RetroImporter::_detect_platform(const String &p_root, const Array &p_makefiles, Dictionary &r_info) {
	String text;
	for (int i = 0; i < p_makefiles.size(); i++) {
		const Dictionary m = p_makefiles[i];
		if (String(m.get("name", "")) == "makefile.gen") {
			continue;
		}
		text += String(m.get("content", "")) + "\n";
	}
	const String lower = text.to_lower();
	bool snes = false;
	bool md = false;
	if (lower.contains("pvsneslib_home") || lower.contains("snes_rules")) {
		snes = true;
		r_info["build_system"] = "pvsneslib";
	}
	if (lower.contains("wla-65816") || lower.contains("wlalink") || lower.contains("wla-spc700")) {
		snes = true;
		if (!r_info.has("build_system")) {
			r_info["build_system"] = "wla-dx";
		}
	}
	if (lower.contains("makefile.gen") || lower.contains("genesis.h") || lower.contains("sgdk") || lower.contains("$(gdk)")) {
		md = true;
		r_info["build_system"] = "sgdk";
	}
	if (FileAccess::exists(p_root.path_join("hdr.asm")) || FileAccess::exists(p_root.path_join("linkfile"))) {
		snes = true;
	}
	if (FileAccess::exists(p_root.path_join("res")) && FileAccess::exists(p_root.path_join("src"))) {
		md = true;
	}
	// Explicit PVSnesLib convenience target.
	for (int i = 0; i < p_makefiles.size(); i++) {
		const Dictionary m = p_makefiles[i];
		if (String(m.get("name", "")) == "Makefile.pvsnes") {
			snes = true;
			r_info["build_system"] = "pvsneslib";
			r_info["build_target"] = "pvsnes";
		}
	}
	if (md && !snes) {
		return "megadrive";
	}
	if (snes) {
		return "snes";
	}
	return String();
}

Dictionary RetroImporter::scan(const String &p_path, const String &p_platform_hint) {
	Dictionary out;
	const String root = RetroUtil::absolute(p_path);
	if (!RetroUtil::is_dir(root)) {
		out["ok"] = false;
		out["error"] = "Directory not found: " + root;
		return out;
	}

	const Array makefiles = detect_build_files(root);
	Dictionary info;
	String platform = p_platform_hint;
	if (platform.is_empty()) {
		platform = _detect_platform(root, makefiles, info);
	} else {
		(void)_detect_platform(root, makefiles, info);
	}
	if (platform.is_empty()) {
		platform = "snes";
		info["build_system"] = "generic";
	}
	if (!info.has("build_system")) {
		info["build_system"] = "generic";
	}

	// Build file: prefer the project Makefile. PVSnesLib projects that expose a
	// pvsnes target use it, because their default target may be a boot ROM.
	String build_file = "Makefile";
	for (int i = 0; i < makefiles.size(); i++) {
		const String n = String(Dictionary(makefiles[i]).get("name", ""));
		if (n == "Makefile" || n == "makefile" || n == "GNUmakefile") {
			build_file = n;
			break;
		}
	}
	if (String(info.get("build_system", "")) == "sgdk") {
		build_file = "Makefile";
	}

	const Vector<String> resource_exts = {
		"png", "bmp", "webp", "jpg", "chr", "pic", "pal", "map", "res", "sff", "air",
		"c", "h", "cpp", "hpp", "asm", "s", "inc", "it", "mod", "xm", "s3m", "vgm", "xgm", "xgm2",
		"wav", "mp3", "brr", "mid", "msu", "spc", "json", "bin"
	};

	Array resources;
	Array sources;
	Array warnings;
	Array files = RetroUtil::find_files(root, resource_exts, 7);

	// Map layout metadata: some projects store maps column-major and declare
	// the width in stagedata.h (sidearms). Preserve that layout instead of
	// guessing and silently transposing the stage.
	Dictionary map_widths;
	bool has_stagedata = false;
	for (int i = 0; i < files.size(); i++) {
		const String f = files[i];
		if (f.get_file() != "stagedata.h") {
			continue;
		}
		has_stagedata = true;
		const Array lines = RetroUtil::split_lines(RetroUtil::read_text(f));
		for (int l = 0; l < lines.size(); l++) {
			const String line = String(lines[l]).strip_edges();
			if (!line.begins_with("#define") || !line.contains("_MAPW")) {
				continue;
			}
			const PackedStringArray parts = line.split_spaces();
			if (parts.size() >= 3) {
				map_widths[parts[1]] = parts[2].to_int();
			}
		}
	}
	int image_loaded = 0;
	for (int i = 0; i < files.size(); i++) {
		const String f = files[i];
		Dictionary r = _classify_resource(root, f, platform);
		if (r.get("kind", "unknown") == "unknown") {
			continue;
		}
		if (!(bool)r.get("editable", false)) {
			warnings.push_back(String(r["name"]) + ": " + String(r.get("note", "read-only")));
		}
		// Lightweight image metadata (do not decode huge files).
		const String ext = String(r.get("ext", ""));
		if ((ext == "png" || ext == "bmp") && int64_t(r.get("size", 0)) < 8 * 1024 * 1024 && image_loaded < 600) {
			const PackedColorArray png_pal = (ext == "png") ? RetroGraphics::read_png_palette(f) : PackedColorArray();
			Ref<Image> img = Image::load_from_file(f);
			if (img.is_valid()) {
				r["width"] = img->get_width();
				r["height"] = img->get_height();
				PackedColorArray pal = png_pal;
				if (pal.is_empty()) {
					pal = RetroGraphics::extract_palette(img, 64, false);
				}
				r["palette_size"] = pal.size();
				r["has_alpha"] = img->detect_alpha() != Image::ALPHA_NONE;
				image_loaded++;
			}
			const String map = _find_companion(root, f, "map");
			if (!map.is_empty()) {
				r["map_path"] = map;
				const Dictionary layout = _retro_infer_map_layout(map, map_widths, has_stagedata);
				for (const Variant *K = layout.next(nullptr); K; K = layout.next(K)) {
					r[K->operator String()] = layout[*K];
				}
				r["tile_size"] = 8;
			}
		}
		if (ext == "map") {
			const Dictionary layout = _retro_infer_map_layout(f, map_widths, has_stagedata);
			for (const Variant *K = layout.next(nullptr); K; K = layout.next(K)) {
				r[K->operator String()] = layout[*K];
			}
		}
		if (ext == "chr" || ext == "pic") {
			r["bpp"] = 4;
			r["tile_size"] = 8;
			const String pal = _find_companion(root, f, "pal");
			const String map = _find_companion(root, f, "map");
			if (!pal.is_empty()) {
				r["palette_path"] = pal;
			}
			if (!map.is_empty()) {
				r["map_path"] = map;
				const Dictionary layout = _retro_infer_map_layout(map, map_widths, has_stagedata);
				for (const Variant *K = layout.next(nullptr); K; K = layout.next(K)) {
					r[K->operator String()] = layout[*K];
				}
			}
		}
		if (ext == "c" || ext == "h" || ext == "cpp" || ext == "hpp" || ext == "asm" || ext == "s" || ext == "inc") {
			sources.push_back(r);
		}
		resources.push_back(r);
	}

	// Deduplicate read-only warnings.
	Array unique_warnings;
	HashMap<String, bool> seen_warn;
	for (int i = 0; i < warnings.size(); i++) {
		const String w = warnings[i];
		if (!seen_warn.has(w)) {
			seen_warn[w] = true;
			unique_warnings.push_back(w);
		}
	}

	Dictionary sdk;
	RetroSDK *sdk_singleton = RetroSDK::get_singleton();
	if (sdk_singleton) {
		sdk = sdk_singleton->get_sdk(platform);
	}

	String rom = RetroUtil::find_rom(root);
	if (rom.is_empty()) {
		Array roms = RetroUtil::find_files(root, platform == "snes" ? Vector<String>{ "sfc", "smc" } : Vector<String>{ "md", "gen", "bin" }, 3);
		if (!roms.is_empty()) {
			rom = roms[0];
		}
	}

	out["ok"] = true;
	out["path"] = root;
	out["platform"] = platform;
	out["name"] = root.get_file();
	out["build_system"] = info.get("build_system", "generic");
	out["build_file"] = build_file;
	out["build_target"] = info.get("build_target", String());
	out["makefiles"] = makefiles;
	out["resources"] = resources;
	out["sources"] = sources;
	out["warnings"] = unique_warnings;
	out["sdk"] = sdk;
	out["sdk_path"] = sdk.get("path", String());
	out["sdk_version"] = sdk.get("version", String());
	out["rom_path"] = rom;
	out["resource_count"] = resources.size();
	out["source_count"] = sources.size();
	return out;
}

Dictionary RetroImporter::inspect_resource(const String &p_path, const String &p_platform) {
	return _classify_resource(p_path.get_base_dir(), p_path, p_platform);
}

Ref<RetroProject> RetroImporter::import_project(const String &p_path, const String &p_platform_hint,
		const String &p_workspace, bool p_copy, const String &p_name) {
	const Dictionary scan_result = scan(p_path, p_platform_hint);
	Ref<RetroProject> project;
	project.instantiate();
	if (!bool(scan_result.get("ok", false))) {
		{ Array w; w.push_back(String(scan_result.get("error", "import failed"))); project->set_warnings(w); }
		return project;
	}
	const String source = scan_result["path"];
	String name = p_name.is_empty() ? String(scan_result["name"]) : p_name;
	name = RetroUtil::sanitize_name(name);
	String work = source;
	if (p_copy) {
		work = RetroUtil::join(p_workspace, name);
		if (RetroUtil::exists(work)) {
			work = work + "_" + Time::get_singleton()->get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_").substr(0, 15);
		}
		DirAccess::make_dir_recursive_absolute(work);
		// Write the marker before copying anything so Godot never starts
		// importing files as they land in the workspace.
		_ensure_godot_ignore(work);
		Vector<String> excluded;
		excluded.push_back("build");
		excluded.push_back("out");
		excluded.push_back(".retro");
		excluded.push_back("node_modules");
		// Copy the source tree, but keep generated/possibly huge build dirs out.
		const Error err = RetroUtil::copy_tree(source, work, excluded);
		if (err != OK) {
			{ Array w; w.push_back("Failed to create working copy; linking original instead."); project->set_warnings(w); }
			work = source;
			p_copy = false;
		}
	}

	project->set_name(name);
	project->set_path(work);
	project->set_source_path(source);
	project->set_platform(scan_result.get("platform", "snes"));
	project->set_sdk_path(scan_result.get("sdk_path", String()));
	project->set_sdk_version(scan_result.get("sdk_version", String()));
	project->set_build_system(scan_result.get("build_system", "generic"));
	project->set_build_file(scan_result.get("build_file", "Makefile"));
	project->set_build_target(scan_result.get("build_target", String()));
	project->set_clean_target("clean");
	project->set_rom_path(String(scan_result.get("rom_path", "")).replace(source, work));
	project->set_linked_in_place(!p_copy);
	project->set_imported(true);
	project->set_mode(project->get_platform() == "snes" ? "mode1" : "h40");

	// Rebase resource paths to the working copy.
	Array resources = scan_result.get("resources", Array());
	for (int i = 0; i < resources.size(); i++) {
		Dictionary r = resources[i];
		r["path"] = String(r.get("path", "")).replace(source, work);
		r["id"] = String(r.get("rel_path", "")).replace("/", "_");
		resources[i] = r;
	}
	Array sources = scan_result.get("sources", Array());
	for (int i = 0; i < sources.size(); i++) {
		Dictionary s = sources[i];
		s["path"] = String(s.get("path", "")).replace(source, work);
		sources[i] = s;
	}
	project->set_resources(resources);
	project->set_sources(sources);
	project->set_warnings(scan_result.get("warnings", Array()));

	Dictionary meta;
	meta["imported_from"] = source;
	meta["imported_at"] = Time::get_singleton()->get_datetime_string_from_system();
	meta["copy"] = p_copy;
	meta["scan"] = scan_result;
	project->set_metadata(meta);
	project->save();
	return project;
}
