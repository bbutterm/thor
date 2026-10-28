shader_type spatial;
// Текстурные эффекты VFX-комплекта (sprites/vfx/*): вспышка, искры, ихор, дым, огонь, молния, волна, трещины, лёд.
// Один шейдер — один пайплайн; материал на текстуру создаётся один раз (FX.sprite_material) и живёт всегда.
// Всё, что меняется у отдельного эффекта, — на экземпляре: цвет и яркость, кадр полосы,
// режим billboard, поворот в плоскости, скорость петли. Затухание — GeometryInstance3D.transparency
// (альфу умножаем: присваивание ALPHA = … отключало его), в GL Compatibility — instance uniform fade (FX.sync_fades).
// В GL Compatibility выделенный блок instance-переменных занимает 16 ячеек; номинально до 256 блоков на 4096 ячеек.
// Снятие материала не гарантирует освобождения блока: сохранённые параметры могут удерживать его до удаления RID.
render_mode unshaded, shadows_disabled, depth_draw_never, cull_disabled;
// rgb — оттенок (текстуры комплекта белые/серые там, где tintable), a — яркость (> 1 — светится в Glow)
instance uniform vec4 color : source_color = vec4(1.0);

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
// Кадров в полосе-атласе по X и Y (vfx_hit_flash — 6×1, vfx_smoke и vfx_fire — 8×1)
uniform vec2 grid = vec2(1.0, 1.0);

// Параметры экземпляра одним vec4:
// x — номер кадра (дробная часть отбрасывается);
// y — billboard: 0 — как повернут узел (декали на полу, ленты молний), 1 — к камере, 2 — к камере вокруг оси Y (огонь, лёд);
// z — поворот в плоскости квада, рад (у billboard-спрайта поворот узла не виден);
// w — > 0: кадры идут сами по TIME с этой частотой, x — сдвиг фазы (петля огня)
instance uniform vec4 sprite = vec4(0.0);
// 1 - transparency узла для GL Compatibility (FX.sync_fades); в Forward+ всегда 1.0
instance uniform float fade = 1.0;

void vertex() {
	float frame = sprite.x;
	float billboard = sprite.y;
	float anim_fps = sprite.w;
	float c = cos(sprite.z);
	float s = sin(sprite.z);
	VERTEX.xy = mat2(vec2(c, s), vec2(-s, c)) * VERTEX.xy;
	if (billboard > 0.5) {
		vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
		mat4 bb;
		if (billboard < 1.5) {
			bb = mat4(INV_VIEW_MATRIX[0] * sc.x, INV_VIEW_MATRIX[1] * sc.y, INV_VIEW_MATRIX[2] * sc.z, MODEL_MATRIX[3]);
		} else {
			vec3 up = vec3(0.0, 1.0, 0.0);
			vec3 to_cam = INV_VIEW_MATRIX[3].xyz - MODEL_MATRIX[3].xyz;
			to_cam.y = 0.0;
			to_cam = length(to_cam) > 0.001 ? normalize(to_cam) : vec3(0.0, 0.0, 1.0);
			vec3 right = cross(up, to_cam);
			bb = mat4(vec4(right * sc.x, 0.0), vec4(up * sc.y, 0.0), vec4(to_cam * sc.z, 0.0), MODEL_MATRIX[3]);
		}
		MODELVIEW_MATRIX = VIEW_MATRIX * bb;
	}
	float n = max(grid.x * grid.y, 1.0);
	float f = frame;
	if (anim_fps > 0.0) {
		f += TIME * anim_fps;
	}
	f = mod(floor(f), n);
	vec2 cell = vec2(mod(f, grid.x), floor(f / grid.x));
	UV = (UV + cell) / grid;
}

void fragment() {
	vec4 t = texture(tex, UV);
	ALBEDO = t.rgb * color.rgb * color.a;
	ALPHA *= t.a * fade;
}
