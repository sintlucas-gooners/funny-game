@tool
extends AcceptDialog

## Dialog shown when a new version of AssetPlus is available

const SettingsDialog = preload("res://addons/assetplus/ui/settings_dialog.gd")
const UpdateInstaller = preload("res://addons/assetplus/ui/update_installer.gd")

var _current_version: String
var _new_version: String
var _browse_url: String
var _download_url: String
var _release_notes: String

var _install_btn: Button
var _progress_label: Label
var _installer: RefCounted


func _init() -> void:
	title = "AssetPlus Update Available"
	ok_button_text = "Later"


func setup(current_version: String, new_version: String, browse_url: String, download_url: String, release_notes: String = "") -> void:
	_current_version = current_version
	_new_version = new_version
	_browse_url = browse_url
	_download_url = download_url
	_release_notes = release_notes


func _ready() -> void:
	_build_ui()
	# Let the dialog size itself based on content
	call_deferred("_adjust_size")


func _adjust_size() -> void:
	# Reset size to let it auto-fit content
	reset_size()
	# Center on screen
	var screen_size = DisplayServer.screen_get_size()
	position = (screen_size - size) / 2


func _build_ui() -> void:
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)
	add_child(main_vbox)

	# Header with icon
	var header_hbox = HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 12)
	main_vbox.add_child(header_hbox)

	var icon = TextureRect.new()
	icon.custom_minimum_size = Vector2(48, 48)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.texture = load("res://addons/assetplus/icon.png")
	header_hbox.add_child(icon)

	var title_vbox = VBoxContainer.new()
	title_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(title_vbox)

	var title_label = Label.new()
	title_label.text = "New Version Available!"
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.add_theme_color_override("font_color", Color(0.4, 0.8, 0.4))
	title_vbox.add_child(title_label)

	var version_label = Label.new()
	version_label.text = "AssetPlus %s → %s" % [_current_version, _new_version]
	version_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	title_vbox.add_child(version_label)

	main_vbox.add_child(HSeparator.new())

	# Release notes (if available)
	if not _release_notes.is_empty():
		var notes_label = Label.new()
		notes_label.text = "What's new:"
		notes_label.add_theme_font_size_override("font_size", 13)
		main_vbox.add_child(notes_label)

		var notes_text = Label.new()
		notes_text.text = _release_notes
		notes_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		notes_text.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		notes_text.add_theme_font_size_override("font_size", 12)
		main_vbox.add_child(notes_text)

	# Progress label (hidden by default)
	_progress_label = Label.new()
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_label.add_theme_color_override("font_color", Color(0.5, 0.7, 1.0))
	_progress_label.visible = false
	main_vbox.add_child(_progress_label)

	# Buttons
	var btn_hbox = HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 12)
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_child(btn_hbox)

	_install_btn = Button.new()
	_install_btn.text = "Install Now"
	_install_btn.custom_minimum_size.x = 100
	var theme = EditorInterface.get_editor_theme()
	if theme:
		_install_btn.icon = theme.get_icon("Progress1", "EditorIcons")
	_install_btn.pressed.connect(_on_install_pressed)
	btn_hbox.add_child(_install_btn)

	var disable_btn = Button.new()
	disable_btn.text = "Disable Auto-Update"
	disable_btn.custom_minimum_size.x = 120
	disable_btn.pressed.connect(_on_disable_auto_update_pressed)
	btn_hbox.add_child(disable_btn)


func _on_install_pressed() -> void:
	if _download_url.is_empty():
		SettingsDialog.debug_print("No download URL available for auto-install")
		return

	# Disable buttons during install
	_install_btn.disabled = true
	get_ok_button().disabled = true
	_progress_label.visible = true
	_progress_label.text = "Starting update..."

	# Create installer
	_installer = UpdateInstaller.new()
	_installer.progress_updated.connect(_on_progress_updated)
	_installer.install_completed.connect(_on_install_completed)

	# Start installation
	_installer.install_update(self, _download_url)


func _on_progress_updated(message: String) -> void:
	_progress_label.text = message


func _on_install_completed(success: bool, error_message: String) -> void:
	if not success:
		# Re-enable buttons on failure
		_install_btn.disabled = false
		get_ok_button().disabled = false
		_progress_label.text = "Update failed: " + error_message
		_progress_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))

		# Show error dialog
		var error_dialog = AcceptDialog.new()
		error_dialog.title = "Update Failed"
		error_dialog.dialog_text = "Failed to install update:\n%s\n\nYou can try downloading manually from the Asset Library." % error_message
		EditorInterface.get_base_control().add_child(error_dialog)
		error_dialog.confirmed.connect(func(): error_dialog.queue_free())
		error_dialog.popup_centered()
	# If success, the editor will restart automatically


func _on_disable_auto_update_pressed() -> void:
	# Show confirmation dialog
	var confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.title = "Disable Auto-Update"
	confirm_dialog.dialog_text = "Are you sure you want to disable automatic update checks at AssetPlus startup?\n\nYou can still check for updates manually from Settings."
	confirm_dialog.ok_button_text = "Disable"
	confirm_dialog.cancel_button_text = "Cancel"

	confirm_dialog.confirmed.connect(func():
		# Save the setting to disable auto-update
		var settings = SettingsDialog.get_settings()
		settings["auto_update_disabled"] = true
		SettingsDialog.save_settings(settings)
		SettingsDialog.debug_print("Auto-update disabled by user")
		confirm_dialog.queue_free()
		hide()
	)

	confirm_dialog.canceled.connect(func():
		confirm_dialog.queue_free()
	)

	EditorInterface.get_base_control().add_child(confirm_dialog)
	confirm_dialog.popup_centered()
