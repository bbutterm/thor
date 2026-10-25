shader_type canvas_item;
// Радиальные линии скорости по краям экрана. intensity 0..1 задаёт HUD по скорости игрока.

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float line_count = 90.0;

float hash(float n) { return fract(sin(n) * 43758.5453); }

void fragment() {
	vec2 uv = UV - vec2(0.5);
	uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float r = length(uv);
	float a = atan(uv.y, uv.x) / 6.2831853 + 0.5;
	float id = floor(a * line_count);
	float t = floor(TIME * 18.0);
	float rnd = hash(id * 13.17 + t * 0.71);
	float lane = fract(a * line_count);
	float thin = smoothstep(0.5, 0.0, abs(lane - 0.5)) ;
	float on = step(0.55, rnd);
	float start = mix(0.32, 0.48, hash(id + t));
	float radial = smoothstep(start, start + 0.25, r);
	float alpha = thin * on * radial * intensity * 0.55;
	COLOR = vec4(line_color.rgb, alpha);
}
