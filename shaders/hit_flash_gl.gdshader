shader_type spatial;
// GL Compatibility: ordinary uniforms belong to one enemy's shared material.
// They carry the same values and color-space hints as hit_flash.gdshader, without
// allocating instance-uniform slots for each piece of the enemy's model.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 glow_color : source_color = vec3(1.0, 0.15, 0.05);
uniform float flash = 0.0;
uniform float glow = 0.0;
uniform vec4 elite = vec4(0.0);

void fragment() {
	ALBEDO = vec3(flash * 0.85) + glow_color * glow + elite.rgb * elite.a;
}
