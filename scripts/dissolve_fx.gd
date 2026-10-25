class_name DissolveFx
extends RefCounted

const SHADER := preload("res://shaders/dither_dissolve.gdshader")

static func make_material(edge: Color = Color(1.0, 0.62, 0.28, 1.0), scale: float = 10.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("progress", 0.0)
	mat.set_shader_parameter("dither_scale", scale)
	mat.set_shader_parameter("edge_color", edge)
	return mat

static func play(node: CanvasItem, duration: float = 0.8, delay: float = 0.0, edge: Color = Color(1.0, 0.62, 0.28, 1.0)) -> Tween:
	if node == null:
		return null
	var mat := make_material(edge)
	node.material = mat
	var tween := node.create_tween()
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_method(func(v: float): mat.set_shader_parameter("progress", v), 0.0, 1.0, maxf(0.01, duration))
	return tween

static func restore(node: CanvasItem) -> void:
	if node != null:
		node.material = null
