## game_theme.gd — Parchment font theme autoload
## Applies Metamorphous-Regular.ttf globally with:
##   fill  : #2B1108  (deep burnt umber)
##   shadow: #E89B3C  at 35% alpha (warm amber/gold, 1-2px offset)
## Explicit add_theme_color_override() calls on individual nodes still win.
## Uses ThemeDB.get_project_theme() to mutate the live project theme in-place.
extends Node

func _ready() -> void:
	var font := load("res://assets/ui/Metamorphous-Regular.ttf") as FontFile

	# get_project_theme() returns the live Theme resource set in project.godot
	# (which already carries the custom_font setting). We mutate it in-place.
	var theme: Theme = ThemeDB.get_project_theme()
	if theme == null:
		theme = Theme.new()

	# --- Font ---
	if font:
		theme.default_font = font
		theme.set_font("font", "Label",         font)
		theme.set_font("font", "Button",        font)
		theme.set_font("font", "LineEdit",      font)
		theme.set_font("font", "RichTextLabel", font)
		theme.set_font("font", "OptionButton",  font)

	# --- Parchment colours ---
	var fill   := Color(0.1686, 0.0667, 0.0314, 1.00)   # #2B1108 deep burnt umber
	var shadow := Color(0.9098, 0.6078, 0.2353, 0.35)   # #E89B3C warm amber @ 35%

	for cls: String in ["Label", "Button", "LineEdit", "RichTextLabel", "OptionButton"]:
		theme.set_color("font_color",        cls, fill)
		theme.set_color("font_shadow_color", cls, shadow)
		theme.set_constant("shadow_offset_x", cls, 1)
		theme.set_constant("shadow_offset_y", cls, 1)
