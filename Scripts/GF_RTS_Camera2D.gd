# Pack From: Game Forge Kit
# File: GF_RTS_Camera2D.gd
# Version: v1.2.0
# Author: Kode Game Studio
# Godot: 4.x
# Desc: RTS-style Camera2D with edge scrolling, keyboard panning, middle-mouse drag,
#       wheel zoom with min/max, world limits, and animated focus (pan + zoom).

@icon("res://addons/Camera_RTS_2D/icon.png")
extends Camera2D
class_name GF_RTS_Camera2D

## A modular RTS-style Camera2D for top-down strategy games.[br]
##
## Features:[br]
## - Keyboard and edge scrolling movement[br]
## - Middle mouse drag to pan[br]
## - Mouse wheel zoom (min/max/step)[br]
## - Optional world limits (Rect2)[br]
## - Animated focus to position or Node2D (pan + zoom)[br]
## [br]
## Designed for clarity inside the editor.


## Emitted when an animated focus starts.
## @param target_pos The world position the camera will focus to.
## @param target_zoom The zoom value that will be targeted.
signal focus_started(target_pos: Vector2, target_zoom: float)

## Emitted when an animated focus ends.
signal focus_finished()

@export_group("Controls — Keyboard")
## Enables keyboard panning using InputMap actions (ui_up/down/left/right).
@export var use_keyboard: bool = true

## Base panning speed in pixels per second at zoom 1.0.
@export_range(50.0, 5000.0, 10.0, "or_greater")
var base_speed: float = 900.0

## Acceleration in pixels per second squared.
@export_range(0.0, 20000.0, 10.0, "or_greater")
var acceleration: float = 6000.0

@export_group("Controls — Edge Scroll")
## Enables edge scrolling when the mouse reaches screen borders.
@export var use_edge_scroll: bool = true

## Margin, in pixels, near viewport borders that triggers edge scrolling.
@export_range(1, 128, 1, "suffix:px")
var edge_margin_px: int = 16

@export_group("Controls — Mouse Drag")
## Multiplier applied to middle-mouse drag panning.
@export_range(0.1, 5.0, 0.1)
var drag_sensitivity: float = 1.0

@export_group("Zoom")
## Minimal zoom factor.
@export_range(0.05, 10.0, 0.01)
var zoom_min: float = 0.5

## Maximal zoom factor.
@export_range(0.05, 10.0, 0.01)
var zoom_max: float = 3.0

## Step applied on mouse wheel input.
@export_range(0.01, 1.0, 0.01)
var zoom_step: float = 0.1

@export_group("World Limits")
## If true, camera position is clamped inside [world_rect].
@export var obey_world_limits: bool = false

## The world rectangle to confine the camera within (top-left + size).
@export var world_rect := Rect2(Vector2(-4096, -4096), Vector2(8192, 8192))

@export_group("Mouse")
## If true, confines the mouse to the viewport/window.
@export var mouse_confined_in_viewport: bool = false

@export_group("Animated Focus (Pan + Zoom)")
## Default zoom used by focus if [param target_zoom] is <= 0.
@export_range(0.05, 10.0, 0.01)
var focus_default_zoom: float = 0.85

## Default duration used by focus if [param duration] is <= 0 (seconds).
@export_range(0.05, 3.0, 0.01)
var focus_duration: float = 0.35

## If true, disables user inputs while focusing.
@export var focus_disable_inputs: bool = true

## Transition type used by the tween during focus.
@export var focus_trans: Tween.TransitionType = Tween.TRANS_QUAD

## Ease type used by the tween during focus.
@export var focus_ease: Tween.EaseType = Tween.EASE_OUT

# --- Internals ---
var _velocity: Vector2 = Vector2.ZERO

var _is_focusing := false
var _focus_tween: Tween

var _drag_active := false
var _drag_button := -1 #  MMB= MOUSE_BUTTON_MIDDLE, RMB= MOUSE_BUTTON_RIGHT, LMB= MOUSE_BUTTON_LEFT


func _ready() -> void:
	## Called when the node is added to the scene for the first time.
	## Sets process mode to PAUSABLE so the camera may animate during pause if desired.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	if mouse_confined_in_viewport:
		Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)

func _get_configuration_warnings() -> PackedStringArray:
	## Provides editor-time warnings for invalid configuration.
	var warns: PackedStringArray = []
	if zoom_min <= 0.0:
		warns.append("zoom_min must be > 0.0.")
	if zoom_min >= zoom_max:
		warns.append("zoom_min must be strictly less than zoom_max.")
	if obey_world_limits and world_rect.size == Vector2.ZERO:
		warns.append("world_rect has zero size while obey_world_limits is enabled.")
	return warns

func _physics_process(delta: float) -> void:
	## Applies smoothed panning based on input and clamps to world limits if enabled.
	if _is_focusing and focus_disable_inputs:
		if obey_world_limits:
			_apply_world_limits()
		return

	var dir := _compute_input_dir()

	# Scale perceived speed by zoom (higher zoom => slower movement).
	var speed = base_speed / max(zoom.x, 0.001)
	var target_velocity = dir * speed

	_velocity = _velocity.move_toward(target_velocity, acceleration * delta)
	position += _velocity * delta

	if obey_world_limits:
		_apply_world_limits()

func _compute_input_dir() -> Vector2:
	## Computes the desired movement direction from keyboard and edge scrolling.
	## @return The normalized movement vector (or zero).
	var dir := Vector2.ZERO

	if use_keyboard:
		dir.x += Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
		dir.y += Input.get_action_strength("ui_down") - Input.get_action_strength("ui_up")

	if use_edge_scroll:
		var vp := get_viewport()
		var mouse_pos := vp.get_mouse_position()
		var vp_size := vp.get_visible_rect().size

		if mouse_pos.x <= edge_margin_px:
			dir.x -= 1.0
		elif mouse_pos.x >= (vp_size.x - edge_margin_px):
			dir.x += 1.0

		if mouse_pos.y <= edge_margin_px:
			dir.y -= 1.0
		elif mouse_pos.y >= (vp_size.y - edge_margin_px):
			dir.y += 1.0

	if dir.length() > 1.0:
		dir = dir.normalized()
	return dir

func _unhandled_input(event: InputEvent) -> void:
	## Handles mouse wheel zoom and middle-button dragging.
	if _is_focusing and focus_disable_inputs:
		return

	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton

		# Wheel UP increases, DOWN decreases (kept from original logic).
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var z := clamp(zoom.x - zoom_step, zoom_min, zoom_max)
			zoom = Vector2(z, z)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			var z := clamp(zoom.x + zoom_step, zoom_min, zoom_max)
			zoom = Vector2(z, z)

		# Middle-mouse drag toggle.
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_drag_active = mb.pressed
			if _drag_active:
				_velocity = Vector2.ZERO

	if event is InputEventMouseMotion and _drag_active:
		var mm := event as InputEventMouseMotion
		position -= mm.relative * (drag_sensitivity / max(zoom.x, 0.001))
		if obey_world_limits:
			_apply_world_limits()

func _apply_world_limits() -> void:
	## Clamps camera position so the viewport stays inside [world_rect].
	var vp_size := get_viewport().get_visible_rect().size
	var half := (vp_size * 0.5) * zoom

	var min_x := world_rect.position.x + half.x
	var max_x := world_rect.position.x + world_rect.size.x - half.x
	var min_y := world_rect.position.y + half.y
	var max_y := world_rect.position.y + world_rect.size.y - half.y

	# If the visible area is larger than world_rect along an axis, center on that axis.
	if min_x > max_x:
		position.x = (min_x + max_x) * 0.5
	else:
		position.x = clamp(position.x, min_x, max_x)

	if min_y > max_y:
		position.y = (min_y + max_y) * 0.5
	else:
		position.y = clamp(position.y, min_y, max_y)

## Starts an animated focus (pan + zoom) toward a world position.
## If [param target_zoom] <= 0, uses [member focus_default_zoom].
## If [param duration] <= 0, uses [member focus_duration].
## @param target_world_pos The world-space destination.
## @param target_zoom Target zoom value (<= 0 to use default).
## @param duration Duration in seconds (<= 0 to use default).
## @example:
##     $GF_RTS_Camera2D.focus_to(Vector2(1000, 600), 1.0, 0.4)
func focus_to(target_world_pos: Vector2, target_zoom: float = -1.0, duration: float = -1.0) -> void:
	var tz := target_zoom if target_zoom > 0.0 else focus_default_zoom
	tz = clamp(tz, zoom_min, zoom_max)

	var dur := duration if duration > 0.0 else focus_duration

	var final_pos := target_world_pos
	if obey_world_limits:
		final_pos = _clamp_position_for_zoom(target_world_pos, tz)

	_kill_focus_tween_if_running()

	_is_focusing = true
	emit_signal("focus_started", final_pos, tz)
	_velocity = Vector2.ZERO

	_focus_tween = create_tween()
	_focus_tween.set_trans(focus_trans).set_ease(focus_ease)
	_focus_tween.parallel().tween_property(self, "position", final_pos, dur)
	_focus_tween.parallel().tween_property(self, "zoom", Vector2(tz, tz), dur)

	if obey_world_limits:
		_focus_tween.tween_callback(_apply_world_limits)

	_focus_tween.finished.connect(func ():
		_is_focusing = false
		if obey_world_limits:
			_apply_world_limits()
		emit_signal("focus_finished")
	)

## Starts an animated focus toward a Node2D (uses its global_position).
## @param node The node to focus (Node2D).
## @param target_zoom Optional target zoom (<= 0 to use default).
## @param duration Optional duration seconds (<= 0 to use default).
## @example:
##     $GF_RTS_Camera2D.focus_to_node($Target, 0.9, 0.35)
func focus_to_node(node: Node, target_zoom: float = -1.0, duration: float = -1.0) -> void:
	if node is Node2D:
		focus_to((node as Node2D).global_position, target_zoom, duration)

## Cancels a running focus tween (does not restore previous position/zoom).
## @example:
##     $GF_RTS_Camera2D.cancel_focus()
func cancel_focus() -> void:
	_kill_focus_tween_if_running()
	_is_focusing = false

func _kill_focus_tween_if_running() -> void:
	if _focus_tween and _focus_tween.is_running():
		_focus_tween.kill()

func _clamp_position_for_zoom(pos: Vector2, z: float) -> Vector2:
	## Returns a position clamped for a given zoom so the viewport remains inside [world_rect].
	## @param pos Candidate world position.
	## @param z Zoom value to evaluate against.
	## @return The clamped world position.
	if not obey_world_limits:
		return pos

	var vp_size := get_viewport().get_visible_rect().size
	var half := (vp_size * 0.5) * Vector2(z, z)

	var min_x := world_rect.position.x + half.x
	var max_x := world_rect.position.x + world_rect.size.x - half.x
	var min_y := world_rect.position.y + half.y
	var max_y := world_rect.position.y + world_rect.size.y - half.y

	var out := pos
	out.x = (min_x + max_x) * 0.5 if min_x > max_x else clamp(out.x, min_x, max_x)
	out.y = (min_y + max_y) * 0.5 if min_y > max_y else clamp(out.y, min_y, max_y)
	return out

func _input(event: InputEvent) -> void:
	if _is_focusing and focus_disable_inputs:
		return

	# -- Mouse button press/release
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton

		# Zoom (même logique qu'avant)
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var z := clamp(zoom.x - zoom_step, zoom_min, zoom_max)
			zoom = Vector2(z, z)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			var z := clamp(zoom.x + zoom_step, zoom_min, zoom_max)
			zoom = Vector2(z, z)

		# Drag start: MMB or RMB or Alt+LMB
		if mb.pressed and (
			mb.button_index == MOUSE_BUTTON_MIDDLE
			or mb.button_index == MOUSE_BUTTON_RIGHT
			or (mb.button_index == MOUSE_BUTTON_LEFT and Input.is_key_pressed(KEY_ALT))
		):
			_drag_active = true
			_drag_button = mb.button_index
			_velocity = Vector2.ZERO
			get_viewport().set_input_as_handled()

		# Drag end (release same button)
		if not mb.pressed and _drag_active and mb.button_index == _drag_button:
			_drag_active = false
			_drag_button = -1
			get_viewport().set_input_as_handled()

	# -- Mouse motion while dragging
	if event is InputEventMouseMotion and _drag_active:
		var mm := event as InputEventMouseMotion
		position -= mm.relative * (drag_sensitivity / max(zoom.x, 0.001))
		if obey_world_limits:
			_apply_world_limits()
		get_viewport().set_input_as_handled()
