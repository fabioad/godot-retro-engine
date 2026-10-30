@tool
extends RefCounted
## Cross-checks the active project, the UI platform/mode selector, the build
## system, SDK path and stored export/3D profiles. Build is blocked on errors;
## non-fatal mismatches are returned as warnings.
##
## Entries are structured so the UI can translate them:
##   {"code": "platform_mismatch", "params": {...}}

const I18n = preload("res://addons/retro_engine/i18n.gd")

const VALID_MODES := {
	"snes": ["mode0", "mode1", "mode7"],
	"megadrive": ["h40", "h32"],
}

static func recommended_mode(platform: String) -> String:
	return "mode1" if platform == "snes" else "h40"

static func target_for_build_mode(mode: String) -> String:
	if mode in ["native_snes", "megadrive_snes"]:
		return "snes"
	if mode in ["native_megadrive", "snes_megadrive"]:
		return "megadrive"
	return ""

static func _entry(code: String, params := {}) -> Dictionary:
	return {"code": code, "params": params}

static func inspect(project, selected_platform := "", selected_mode := "") -> Dictionary:
	var errors: Array = []
	var warnings: Array = []
	if project == null:
		errors.append(_entry("no_project"))
		return {"ok": false, "errors": errors, "warnings": warnings, "target": ""}
	var platform := String(project.get_platform())
	if platform not in ["snes", "megadrive"]:
		errors.append(_entry("unknown_platform", {"platform": platform}))
		return {"ok": false, "errors": errors, "warnings": warnings, "target": platform}
	if selected_platform.is_empty():
		selected_platform = platform
	if selected_platform not in ["snes", "megadrive"]:
		errors.append(_entry("unknown_selected_platform", {"platform": selected_platform}))
	elif selected_platform != platform:
		errors.append(_entry("platform_mismatch", {
			"selected": I18n.platform_label(selected_platform),
			"project": String(project.get_name()),
			"project_platform": I18n.platform_label(platform),
		}))

	var mode := String(project.get_mode())
	if mode not in VALID_MODES.get(platform, []):
		errors.append(_entry("invalid_mode", {
			"mode": mode,
			"platform": I18n.platform_label(platform),
			"recommended": recommended_mode(platform),
		}))
	if not selected_mode.is_empty() and selected_mode != mode:
		warnings.append(_entry("mode_mismatch", {"ui": selected_mode, "project_mode": mode}))

	var system := String(project.get_build_system())
	if platform == "snes" and system == "sgdk":
		errors.append(_entry("snes_with_sgdk"))
	elif platform == "megadrive" and system in ["pvsneslib", "wla-dx"]:
		errors.append(_entry("md_with_snes_build", {
			"system": "PVSnesLib" if system == "pvsneslib" else "WLA-DX",
		}))

	var sdk_path := String(project.get_sdk_path())
	if not sdk_path.is_empty():
		var snes_found := bool(RetroSDK.probe_snes(sdk_path).get("found", false))
		var md_found := bool(RetroSDK.probe_megadrive(sdk_path).get("found", false))
		if platform == "snes" and not snes_found and md_found:
			errors.append(_entry("sdk_points_sgdk", {"path": sdk_path}))
		elif platform == "megadrive" and not md_found and snes_found:
			errors.append(_entry("sdk_points_pvs", {"path": sdk_path}))

	var metadata: Dictionary = project.get_metadata()
	var profile = metadata.get("export_profile", {})
	if typeof(profile) == TYPE_DICTIONARY and not profile.is_empty():
		var profile_platform := String(profile.get("platform", ""))
		var profile_id := String(profile.get("profile_id", ""))
		if not profile_platform.is_empty() and profile_platform != platform:
			warnings.append(_entry("export_profile_target", {
				"profile_platform": I18n.platform_label(profile_platform),
				"project_platform": I18n.platform_label(platform),
			}))
		elif not profile_id.is_empty() and not profile_id.begins_with(platform):
			warnings.append(_entry("export_profile_id", {
				"profile_id": profile_id,
				"project_platform": I18n.platform_label(platform),
			}))

	var profile_3d := String(metadata.get("3d_profile", ""))
	if profile_3d == "superfx" and platform == "megadrive":
		warnings.append(_entry("superfx_on_md"))
	elif profile_3d == "svp" and platform == "snes":
		warnings.append(_entry("svp_on_snes"))

	var build_mode := String(metadata.get("build_mode", ""))
	var build_target := target_for_build_mode(build_mode)
	if not build_target.is_empty() and build_target != platform:
		errors.append(_entry("build_mode_mismatch", {
			"build_mode": build_mode,
			"target": I18n.platform_label(build_target),
			"project_platform": I18n.platform_label(platform),
		}))

	return {"ok": errors.is_empty(), "errors": errors, "warnings": warnings, "target": platform}

static func text(entry: Dictionary) -> String:
	var code := String(entry.get("code", ""))
	return I18n.t("checks." + code, entry.get("params", {}))
