shader_type spatial;
// Diagnostics only. This deliberately discards the original colour texture,
// anti-tiling, noise, and overlay; it is not a replacement for world_surface.
// Keep the lighting mode, vertex AO, normal-map calculation and material tint so
// timing isolates mostly colour/roughness work on the same geometry.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform float uv_scale = 0.35;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.9;
uniform float overlay_roughness : hint_range(0.0, 1.0) = 0.95;
uniform float blend_sharpness = 6.0;
uniform float vertex_ao : hint_range(0.0, 1.0) = 1.0;

varying vec3 w_pos;
varying vec3 w_nrm;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 tangent_normal(vec2 uv) {
	vec2 xy = texture(normal_tex, uv * uv_scale).rg * 2.0 - 1.0;
	xy *= normal_strength;
	return vec3(xy, sqrt(max(0.0, 1.0 - dot(xy, xy))));
}

void fragment() {
	vec3 n = normalize(w_nrm);
	vec3 ao = mix(vec3(1.0), COLOR.rgb, vertex_ao);
	ALBEDO = vec3(0.5) * tint.rgb * ao;
	AO = mix(1.0, COLOR.r, vertex_ao);
	AO_LIGHT_AFFECT = 0.25;
	ROUGHNESS = (roughness_base + overlay_roughness) * 0.5;
	SPECULAR = 0.35;
	if (normal_strength > 0.0) {
		vec3 bw = pow(abs(n), vec3(blend_sharpness));
		bw /= max(bw.x + bw.y + bw.z, 0.0001);
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
