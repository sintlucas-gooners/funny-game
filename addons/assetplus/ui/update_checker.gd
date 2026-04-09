@tool
extends RefCounted

## Checks for AssetPlus updates from GitHub releases

const SettingsDialog = preload("res://addons/assetplus/ui/settings_dialog.gd")

const GITHUB_REPO = "moongdevstudio/AssetPlus"
const GITHUB_API_URL = "https://api.github.com/repos/%s/releases/latest"

signal update_available(current_version: String, new_version: String, browse_url: String, download_url: String, release_notes: String)
signal check_complete(has_update: bool)

var _http_request: HTTPRequest
var _parent_node: Node


func check_for_updates(parent: Node) -> void:
	## Check if a newer version is available on GitHub
	_parent_node = parent

	var current_version = _get_current_version()
	if current_version.is_empty():
		SettingsDialog.debug_print("Update check skipped - could not read current version")
		check_complete.emit(false)
		return

	SettingsDialog.debug_print("Checking for updates... (current: %s)" % current_version)

	_http_request = HTTPRequest.new()
	parent.add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)

	var url = GITHUB_API_URL % GITHUB_REPO
	var headers: PackedStringArray = [
		"User-Agent: AssetPlus-Godot-Plugin",
		"Accept: application/vnd.github.v3+json"
	]

	var error = _http_request.request(url, headers)
	if error != OK:
		SettingsDialog.debug_print("Update check failed - HTTP request error")
		_cleanup()
		check_complete.emit(false)


func _on_request_completed(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		SettingsDialog.debug_print("Update check failed - HTTP %d" % code)
		_cleanup()
		check_complete.emit(false)
		return

	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		SettingsDialog.debug_print("Update check failed - JSON parse error")
		_cleanup()
		check_complete.emit(false)
		return

	var data = json.data
	if not data is Dictionary:
		_cleanup()
		check_complete.emit(false)
		return

	# Parse GitHub release response
	var tag_name = data.get("tag_name", "")
	# Remove 'v' prefix if present (v1.0.1 -> 1.0.1)
	var remote_version = tag_name.trim_prefix("v")
	var browse_url = data.get("html_url", "https://github.com/%s/releases" % GITHUB_REPO)
	var download_url = data.get("zipball_url", "")
	var release_notes = data.get("body", "")

	var current_version = _get_current_version()

	SettingsDialog.debug_print("Update check: current=%s, remote=%s" % [current_version, remote_version])

	if _is_newer_version(remote_version, current_version):
		SettingsDialog.debug_print("New version available: %s" % remote_version)
		update_available.emit(current_version, remote_version, browse_url, download_url, release_notes)
		check_complete.emit(true)
	else:
		SettingsDialog.debug_print("AssetPlus is up to date")
		check_complete.emit(false)

	_cleanup()


func _get_current_version() -> String:
	## Read the current version from plugin.cfg
	var config = ConfigFile.new()
	var err = config.load("res://addons/assetplus/plugin.cfg")
	if err != OK:
		return ""
	return config.get_value("plugin", "version", "")


func _is_newer_version(remote: String, current: String) -> bool:
	## Compare version strings (e.g., "1.2.3" vs "1.2.0")
	if remote.is_empty() or current.is_empty():
		return false

	var remote_parts = remote.split(".")
	var current_parts = current.split(".")

	# Pad arrays to same length
	while remote_parts.size() < 3:
		remote_parts.append("0")
	while current_parts.size() < 3:
		current_parts.append("0")

	for i in range(3):
		var r = remote_parts[i].to_int()
		var c = current_parts[i].to_int()
		if r > c:
			return true
		elif r < c:
			return false

	return false


func _cleanup() -> void:
	if _http_request and is_instance_valid(_http_request):
		_http_request.queue_free()
		_http_request = null
