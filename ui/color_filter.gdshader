shader_type canvas_item;
// Коррекция цвета для цветовой слепоты (GDD 22) — дальтонизация всего экрана.
// mode: 1 — протанопия, 2 — дейтеранопия, 3 — тританопия. Один материал на всю игру
// (GameSettings.apply_colorblind), создаётся только при включении режима.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform int mode = 0;
uniform float strength = 1.0;

vec3 simulate(vec3 c) {
	if (mode == 1) {
		return vec3(dot(c, vec3(0.56667, 0.43333, 0.0)), dot(c, vec3(0.55833, 0.44167, 0.0)), dot(c, vec3(0.0, 0.24167, 0.75833)));
	} else if (mode == 2) {
		return vec3(dot(c, vec3(0.625, 0.375, 0.0)), dot(c, vec3(0.7, 0.3, 0.0)), dot(c, vec3(0.0, 0.3, 0.7)));
	}
	return vec3(dot(c, vec3(0.95, 0.05, 0.0)), dot(c, vec3(0.0, 0.43333, 0.56667)), dot(c, vec3(0.0, 0.475, 0.525)));
}

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	vec3 err = c - simulate(c);
	// Потерянную разницу переносим в каналы, которые человек различает
	vec3 shift = mode == 3
		? vec3(err.r + err.b * 0.7, err.g + err.b * 0.7, 0.0)
		: vec3(0.0, err.g + err.r * 0.7, err.b + err.r * 0.7);
	COLOR = vec4(clamp(c + shift * strength, 0.0, 1.0), 1.0);
}
