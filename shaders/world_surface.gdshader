shader_type spatial;
// Поверхности залов (блок Б0 «Одеть залы»): пол, видимые грани блоков, валуны, башни. Трипланар по миру
// без видимых повторов: текстура берётся дважды (второй раз — крупнее и повёрнута) и смешивается по шуму,
// поверх — крупные пятна яркости/оттенка и второй слой (мох, грязь, сажа) по шуму; у основания вертикальных
// граней — грязь; цвет вершин — запечённое затемнение (углы, стыки стены с полом; GL Compatibility без SSAO).
// ОДИН шейдер на все поверхности: материалы (rooms/materials/surface_*.tres) различаются только параметрами —
// новых пайплайнов нет (правило фризов в CLAUDE.md). Без переменных экземпляра: буфер GL Compatibility не занимает (FX._has_iu считает узлы по тексту шейдера — этих слов здесь не писать).
// Прогрев — RoomDress.warmup (ShaderWarmup).
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.0;
uniform vec4 tint : source_color = vec4(1.0);
// Повторов текстуры на метр (как uv1_scale трипланара StandardMaterial3D)
uniform float uv_scale = 0.35;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.9;
// Резкость перехода между проекциями трипланара
uniform float blend_sharpness = 6.0;

// Шум (T_Noise_Terrain MegaKit, бесшовный): анти-повтор, пятна, второй слой
uniform sampler2D noise_tex : filter_linear, repeat_enable;
// Второй отсчёт текстуры: во сколько раз крупнее и на сколько повёрнут (рад); 0 — выключен
uniform float detail_mix : hint_range(0.0, 1.0) = 1.0;
uniform float detail_scale = 0.61;
uniform float detail_angle = 0.7;
// Масштаб шума смешения двух отсчётов (1/м)
uniform float antitile_scale = 0.07;
// Крупные пятна яркости и оттенка (1/м) и их сила
uniform float macro_scale = 0.035;
uniform float macro_strength : hint_range(0.0, 1.0) = 0.3;
uniform vec4 macro_tint : source_color = vec4(0.82, 0.76, 0.7, 1.0);
// Второй слой: цвет, доля поверхности, масштаб (1/м), мягкость края, тяга к верхним граням (мох)
uniform vec4 overlay_color : source_color = vec4(0.30, 0.34, 0.18, 1.0);
// Текстура второго слоя (пятна земли на кирпиче, булыжник в земле); нет — сплошной цвет overlay_color
uniform sampler2D overlay_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float overlay_uv = 0.3;
uniform float overlay_amount : hint_range(0.0, 1.0) = 0.3;
uniform float overlay_scale = 0.12;
uniform float overlay_softness : hint_range(0.01, 0.5) = 0.12;
uniform float overlay_top : hint_range(0.0, 1.0) = 0.5;
uniform float overlay_roughness : hint_range(0.0, 1.0) = 0.95;
// Грязь у основания вертикальных граней: до какой высоты над полом зала (м) и сила
uniform vec4 grime_color : source_color = vec4(0.18, 0.14, 0.11, 1.0);
uniform float grime_height = 0.9;
uniform float grime_strength : hint_range(0.0, 1.0) = 0.55;
// Цвет вершин как затемнение (запечённый AO генератора); у мешей без цвета вершин — белый
uniform float vertex_ao : hint_range(0.0, 1.0) = 1.0;

varying vec3 w_pos;
varying vec3 w_nrm;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec2 rot2(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Отсчёт по одной проекции: два масштаба, смешение по шуму (k)
vec3 sample_plane(vec2 uv, float k) {
	vec3 a = texture(albedo_tex, uv * uv_scale).rgb;
	vec3 b = texture(albedo_tex, rot2(uv, detail_angle) * uv_scale * detail_scale + vec2(0.37, 0.71)).rgb;
	return mix(a, b, k * detail_mix);
}

vec3 tangent_normal(vec2 uv) {
	vec2 xy = texture(normal_tex, uv * uv_scale).rg * 2.0 - 1.0;
	xy *= normal_strength;
	return vec3(xy, sqrt(max(0.0, 1.0 - dot(xy, xy))));
}

void fragment() {
	vec3 n = normalize(w_nrm);
	vec3 bw = pow(abs(n), vec3(blend_sharpness));
	bw /= max(bw.x + bw.y + bw.z, 0.0001);
	// Шум смешения двух отсчётов и пятен: по полу — XZ, по стенам — вдоль грани
	vec2 nuv = w_pos.xz * bw.y + w_pos.zy * bw.x + w_pos.xy * bw.z;
	float k = smoothstep(0.35, 0.65, texture(noise_tex, nuv * antitile_scale).r);
	// Проекции с почти нулевым весом не считаем: у пола и стен работает одна (ветвление согласованное — дёшево)
	vec3 col = vec3(0.0);
	if (bw.x > 0.02) { col += sample_plane(w_pos.zy, k) * bw.x; }
	if (bw.y > 0.02) { col += sample_plane(w_pos.xz, k) * bw.y; }
	if (bw.z > 0.02) { col += sample_plane(w_pos.xy, k) * bw.z; }
	col /= max(dot(step(vec3(0.02), bw), bw), 0.0001);
	col *= tint.rgb;
	// Крупные пятна: яркость и оттенок
	float m = texture(noise_tex, nuv * macro_scale + vec2(0.13, 0.29)).r;
	col *= mix(vec3(1.0), macro_tint.rgb, smoothstep(0.3, 0.75, m) * macro_strength * 2.0);
	col *= 1.0 + (m - 0.5) * macro_strength;
	// Второй слой (мох / грязь / сажа): по шуму, гуще на верхних гранях
	float o = texture(noise_tex, nuv * overlay_scale + vec2(0.51, 0.07)).r;
	float up = clamp(n.y, 0.0, 1.0);
	float thr = 1.0 - overlay_amount * mix(1.0 - overlay_top, 1.0 + overlay_top, up);
	float ov = smoothstep(thr - overlay_softness, thr + overlay_softness, o);
	vec3 ovc = overlay_color.rgb * texture(overlay_tex, rot2(nuv, 0.4) * overlay_uv).rgb;
	col = mix(col, ovc * (0.75 + 0.5 * o), ov);
	// Грязь у основания вертикальных граней
	float side = 1.0 - abs(n.y);
	float g = (1.0 - smoothstep(0.0, max(grime_height, 0.01), w_pos.y)) * side * grime_strength;
	col = mix(col, grime_color.rgb, clamp(g, 0.0, 1.0));
	// Запечённое затемнение (цвет вершин)
	vec3 ao = mix(vec3(1.0), COLOR.rgb, vertex_ao);
	ALBEDO = col * ao;
	AO = mix(1.0, COLOR.r, vertex_ao);
	AO_LIGHT_AFFECT = 0.25;
	ROUGHNESS = mix(roughness_base, overlay_roughness, ov);
	SPECULAR = 0.35;
	if (normal_strength > 0.0) {
		// Нормали трипланара (whiteout), в мировых осях → в осях камеры
		vec3 tx = bw.x > 0.02 ? tangent_normal(w_pos.zy) : vec3(0.0, 0.0, 1.0);
		vec3 ty = bw.y > 0.02 ? tangent_normal(w_pos.xz) : vec3(0.0, 0.0, 1.0);
		vec3 tz = bw.z > 0.02 ? tangent_normal(w_pos.xy) : vec3(0.0, 0.0, 1.0);
		tx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
		ty = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
		tz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
		vec3 wn = normalize(tx.zyx * bw.x + ty.xzy * bw.y + tz.xyz * bw.z);
		NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	}
}
