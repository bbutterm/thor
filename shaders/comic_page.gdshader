shader_type canvas_item;
// «Страница комикса» (ui/comic_page.gd): стоп-кадр игры как напечатанный — меньше цветов,
// растр точками под 45° (крупнее в тенях), тёплая бумага. Один общий материал на все кадры.
// Без производных (fwidth): программный Vulkan падал на них при компиляции (см. comic_halftone).

uniform float dot_spacing = 5.0;      // шаг сетки точек, локальные пиксели
uniform float dot_strength = 0.42;    // насколько точки темнее заливки
uniform float levels = 7.0;           // ступеней цвета на канал (постеризация)
uniform float poster_mix = 0.55;      // доля постеризации
uniform float saturation = 1.18;
uniform vec4 paper : source_color = vec4(1.0, 0.95, 0.84, 1.0);
uniform float paper_mix = 0.18;

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec4 c = COLOR;
	vec3 rgb = c.rgb;
	float lum = dot(rgb, vec3(0.299, 0.587, 0.114));
	rgb = mix(vec3(lum), rgb, saturation);
	rgb = mix(rgb, floor(rgb * levels + 0.5) / levels, poster_mix);
	lum = dot(rgb, vec3(0.299, 0.587, 0.114));
	vec2 p = mat2(vec2(0.7071, -0.7071), vec2(0.7071, 0.7071)) * local_pos / dot_spacing;
	float d = length(fract(p) - 0.5);
	float r = 0.55 * sqrt(clamp(1.0 - lum, 0.0, 1.0));
	float dotm = 1.0 - smoothstep(r - 0.07, r + 0.07, d);
	rgb = mix(rgb, rgb * (1.0 - dot_strength), dotm);
	rgb = mix(rgb, rgb * paper.rgb + paper.rgb * 0.06, paper_mix);
	c.rgb = clamp(rgb, 0.0, 1.0);
	COLOR = c;
}
