shader_type canvas_item;
// Рисованный «взрыв» комплекта (sprites/vfx/comic_burst_01..06) под комиксовым словом (scripts/comic_fx.gd),
// перекрашенный в цвет события. Цвет — modulate спрайта (у слова — свой), материал один на все слова.
// Чёрная обводка и тёмный растр остаются чёрными, светлая заливка уходит в цвет, блики — к белому.

uniform float tint_strength = 0.85;   // 0 — авторский цвет картинки, 1 — полностью цвет события
uniform float light_boost = 0.35;     // насколько светлые места картинки светлее цвета события

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	float l = dot(t.rgb, vec3(0.299, 0.587, 0.114));
	float ink = 1.0 - smoothstep(0.12, 0.32, l);
	vec3 painted = tint.rgb * (0.55 + 0.65 * l) + vec3(light_boost) * smoothstep(0.82, 1.0, l);
	vec3 rgb = mix(t.rgb, painted, tint_strength * (1.0 - ink));
	COLOR = vec4(rgb, t.a * tint.a);
}
