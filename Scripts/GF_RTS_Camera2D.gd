# Pack From: Game Forge Kit
# File: GF_RTS_Camera2D.gd
# Version: v1.2.1 (Fixed Zoom + Movement)
# Author: Kode Game Studio
# Godot: 4.x

@icon("res://addons/Camera_RTS_2D/icon.png")
extends Camera2D
class_name GF_RTS_Camera2D

signal focus_started(target_pos: Vector2, target_zoom: float)
signal focus_finished()

@export_group("Controls — Keyboard")
@export var use_keyboard: bool = true
@export_range(50.0, 5000.0, 10.0, "or_greater")
var base_speed: float = 900.0
@export_range(0.0, 20000.0, 10.0, "or_greater")
var acceleration: float = 6000.0

@export_group("Controls — Edge Scroll")
@export var use_edge_scroll: bool = true
@export_range(1, 128, 1, "suffix:px")
var edge_margin_px: int = 16

@export_group("Controls — Mouse Drag")
@export_range(0.1, 5.0, 0.1)
var drag_sensitivity: float = 1.0

@export_group("Zoom")
@export_range(0.05, 10.0, 0.01)
var zoom_min: float = 0.5
@export_range(0.05, 10.0, 0.01)
var zoom_max: float = 3.0
@export_range(0.01, 1.0, 0.01)
var zoom_step: float = 0.1

@export_group("Mouse")
@export var mouse_confined_in_viewport: bool = false

@export_group("Animated Focus")
@export_range(0.05, 10.0, 0.01)
var focus_default_zoom: float = 0.85
@export_range(0.05, 3.0, 0.01)
var focus_duration: float = 0.35
@export var focus_disable_inputs: bool = true
@export var focus_trans: Tween.TransitionType = Tween.TRANS_QUAD
@export var focus_ease: Tween.EaseType = Tween.EASE_OUT

# --- Internals ---
var _velocity: Vector2 = Vector2.ZERO
var _is_focusing := false
var _focus_tween: Tween
var _drag_active := false
var _drag_button := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	if mouse_confined_in_viewport:
		Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)


func _get_configuration_warnings() -> PackedStringArray:
	var warns: PackedStringArray = []
	if zoom_min <= 0.0:
		warns.append("zoom_min must be > 0.0.")
	if zoom_min >= zoom_max:
		warns.append("zoom_min must be < zoom_max.")
	return warns


func _physics_process(delta: float) -> void:
	if _is_focusing and focus_disable_inputs:
		return

	var dir := _compute_input_dir()

	# Smooth RTS-style speed scaling (no freeze when zooming)
	var zoom_factor := 1.0 + ((zoom.x - 1.0) * 0.35)
	var speed := base_speed / zoom_factor

	var target_velocity = dir * speed
	_velocity = _velocity.move_toward(target_velocity, acceleration * delta)

	position += _velocity * delta
	_apply_limits()


func _apply_limits() -> void:
	if limit_left == limit_right and limit_top == limit_bottom:
		return

	var vp_size = get_viewport_rect().size

	var half_size = (vp_size / zoom) * 0.5

	var min_x = limit_left + half_size.x
	var max_x = limit_right - half_size.x
	var min_y = limit_top + half_size.y
	var max_y = limit_bottom - half_size.y

	position.x = clamp(position.x, min_x, max_x)
	position.y = clamp(position.y, min_y, max_y)


func _compute_input_dir() -> Vector2:
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


# ---------------------------------------------------
# INPUT — unified zoom + drag (no double zoom)
# ---------------------------------------------------
func _input(event: InputEvent) -> void:
	if _is_focusing and focus_disable_inputs:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton

		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_set_zoom(zoom.x - zoom_step)
				get_viewport().set_input_as_handled()

			elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_set_zoom(zoom.x + zoom_step)
				get_viewport().set_input_as_handled()

		# Drag start
		if mb.pressed and (
			mb.button_index == MOUSE_BUTTON_MIDDLE
			or mb.button_index == MOUSE_BUTTON_RIGHT
			or (mb.button_index == MOUSE_BUTTON_LEFT and Input.is_key_pressed(KEY_ALT))
		):
			_drag_active = true
			_drag_button = mb.button_index
			_velocity = Vector2.ZERO
			get_viewport().set_input_as_handled()

		# Drag stop
		if not mb.pressed and _drag_active and mb.button_index == _drag_button:
			_drag_active = false
			_drag_button = -1
			get_viewport().set_input_as_handled()

	# Drag motion
	if event is InputEventMouseMotion and _drag_active:
		var mm := event as InputEventMouseMotion
		position -= mm.relative * (drag_sensitivity / max(zoom.x, 0.001))
		get_viewport().set_input_as_handled()


func _set_zoom(z: float) -> void:
	z = clamp(z, zoom_min, zoom_max)
	zoom = Vector2(z, z)


# ---------------------------------------------------
#   FOCUS SYSTEM
# ---------------------------------------------------
func focus_to(target_world_pos: Vector2, target_zoom: float = -1.0, duration: float = -1.0) -> void:
	var tz := clamp(target_zoom if target_zoom > 0.0 else focus_default_zoom, zoom_min, zoom_max)
	var dur := duration if duration > 0.0 else focus_duration

	_kill_focus_tween_if_running()
	_is_focusing = true
	emit_signal("focus_started", target_world_pos, tz)
	_velocity = Vector2.ZERO

	_focus_tween = create_tween()
	_focus_tween.set_trans(focus_trans).set_ease(focus_ease)
	_focus_tween.parallel().tween_property(self, "position", target_world_pos, dur)
	_focus_tween.parallel().tween_property(self, "zoom", Vector2(tz, tz), dur)

	_focus_tween.finished.connect(func ():
		_is_focusing = false
		emit_signal("focus_finished")
	)


func focus_to_node(node: Node, target_zoom: float = -1.0, duration: float = -1.0) -> void:
	if node is Node2D:
		focus_to((node as Node2D).global_position, target_zoom, duration)


func cancel_focus() -> void:
	_kill_focus_tween_if_running()
	_is_focusing = false


func _kill_focus_tween_if_running() -> void:
	if _focus_tween and _focus_tween.is_running():
		_focus_tween.kill()
