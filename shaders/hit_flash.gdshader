shader_type spatial;
// Общий оверлей для всех врагов: вспышка при уроне, красное свечение замаха и свечение элиты.
// Значения — per-instance (set_instance_shader_parameter), поэтому материал один на всех:
// ни копий материалов, ни новых вариантов шейдера во время боя (раньше это давало фризы).
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 glow_color : source_color = vec3(1.0, 0.15, 0.05);
instance uniform float flash = 0.0;
instance uniform float glow = 0.0;
// Постоянное свечение элиты (GDD 12.4): цвет модификатора, сила — в альфе
instance uniform vec4 elite = vec4(0.0);

void fragment() {
	ALBEDO = vec3(flash * 0.85) + glow_color * glow + elite.rgb * elite.a;
}
