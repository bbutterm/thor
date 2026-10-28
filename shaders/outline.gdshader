shader_type spatial;
// Комиксовая обводка (GDD 20): «вывернутая оболочка» (inverted hull) — общий оверлей-материал
// (GeometryInstance3D.material_overlay) у врагов, боссов, оружия на полу, сундуков и бочек/ящиков
// (scripts/outline.gd). Рисуются только задние грани, сдвинутые от силуэта на постоянную толщину в пикселях.
// Без instance-переменных: сам не требует нового блока; прежний блок узла может сохраняться до удаления RID.
// Толщина/цвет — обычные uniform одного общего материала: смена настройки — без компиляции.
// depth_draw_never → проход прозрачных: не пишет глубину, не попадает в тени и в depth prepass.
// Скин-меши: VERTEX/NORMAL здесь уже после скелета (Forward+ — compute, Compatibility — до кода шейдера).
render_mode unshaded, cull_front, depth_draw_never, shadows_disabled;

uniform vec4 outline_color : source_color = vec4(0.03, 0.02, 0.02, 1.0);
// Толщина у близких объектов, px при высоте кадра 1080 (меньше кадр — тоньше пропорционально)
uniform float width_px = 5.0;
// Множитель из настроек («Толщина обводки»)
uniform float width_scale = 1.0;
// До этого расстояния (м) — полная толщина, дальше — тоньше (∝ 1/расстояние) ...
uniform float near_dist = 6.0;
// ... но не меньше этой доли
uniform float min_scale = 0.4;
// Оболочка отодвинута от камеры (м): не мерцает на двусторонних плащах/волосах и прячется под одеждой
uniform float depth_push = 0.04;

void vertex() {
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 n = normalize(mat3(MODELVIEW_MATRIX) * NORMAL);
	float dist = max(length(view.xyz), 0.0001);
	// Вдоль луча из камеры: точка на экране не сдвигается, только глубина
	vec3 pushed = view.xyz + view.xyz / dist * depth_push;
	vec4 clip = PROJECTION_MATRIX * vec4(pushed, 1.0);
	// Направление нормали на экране (в пикселях, с учётом перспективы)
	vec4 tip = PROJECTION_MATRIX * vec4(view.xyz + n * 0.05, 1.0);
	vec4 base = PROJECTION_MATRIX * view;
	vec2 dir = (tip.xy / tip.w - base.xy / base.w) * VIEWPORT_SIZE;
	float len = length(dir);
	if (len > 0.00001) {
		float px = width_px * width_scale * VIEWPORT_SIZE.y / 1080.0 * clamp(near_dist / max(-view.z, 0.01), min_scale, 1.0);
		clip.xy += dir / len * px * 2.0 / VIEWPORT_SIZE * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
