shader_type canvas_item;
// Комиксовый растр (halftone) для слов-ударов и «взрывов» за ними (scripts/comic_fx.gd).
// Один шейдер, два общих материала: буквы (градиент сверху вниз) и «взрыв» (радиальный по UV).
// Цвет приходит через modulate/цвет полигона — материалы на слово не создаются.
// Тёмные пиксели (чёрная обводка букв) не трогаем.

uniform bool radial = false;          // true — «взрыв»: UV = позиция точки / радиус
uniform float text_height = 110.0;    // высота строки букв в локальных пикселях (для градиента)
uniform float dot_spacing = 9.0;      // шаг сетки точек, локальные пиксели
uniform float dot_strength = 0.3;     // насколько точки темнее заливки
uniform float highlight = 0.5;        // осветление к центру/верху
uniform float dot_min = 0.06;         // радиус точки у центра/сверху (доля ячейки)
uniform float dot_max = 0.42;         // радиус точки у края/снизу

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec4 c = COLOR;
	float bright = smoothstep(0.12, 0.45, max(c.r, max(c.g, c.b)));
	float t = radial ? clamp(length(UV), 0.0, 1.0) : clamp(local_pos.y / text_height, 0.0, 1.0);
	vec3 base = mix(mix(c.rgb, vec3(1.0), highlight), c.rgb, smoothstep(0.05, 0.9, t));
	// Сетка точек под 45°
	vec2 p = mat2(vec2(0.7071, -0.7071), vec2(0.7071, 0.7071)) * local_pos / dot_spacing;
	vec2 cell = fract(p) - 0.5;
	float r = mix(dot_min, dot_max, t);
	float d = length(cell);
	// Сглаживание края точки в долях ячейки (без fwidth: производные в canvas-шейдере роняли
	// программный Vulkan при компиляции)
	float aa = 0.06;
	float dotm = 1.0 - smoothstep(r - aa, r + aa, d);
	base = mix(base, base * (1.0 - dot_strength), dotm);
	c.rgb = mix(c.rgb, base, bright);
	COLOR = c;
}
