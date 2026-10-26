shader_type canvas_item;
// Виньетка под крупным комиксовым словом на весь экран: тёмные края с растровыми точками.
// Сила — альфа цвета ColorRect (общий материал, анимируется color.a).

uniform float inner = 0.32;
uniform float outer = 0.85;
uniform float dot_spacing = 14.0;

void fragment() {
	vec2 q = (UV - 0.5) * vec2(1.6, 1.0);
	float v = smoothstep(inner, outer, length(q));
	vec2 p = mat2(vec2(0.7071, -0.7071), vec2(0.7071, 0.7071)) * FRAGCOORD.xy / dot_spacing;
	float d = length(fract(p) - 0.5);
	float dots = 1.0 - smoothstep(0.5 - v * 0.45 - 0.04, 0.5 - v * 0.45 + 0.04, d);
	float a = clamp(v * 0.75 + dots * v * 0.35, 0.0, 1.0);
	COLOR = vec4(COLOR.rgb, a * COLOR.a);
}
