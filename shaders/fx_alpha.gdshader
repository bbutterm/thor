shader_type spatial;
render_mode unshaded, shadows_disabled, depth_draw_never;
#include "res://shaders/fx_common.gdshaderinc"

void fragment() {
	ALBEDO = color.rgb * energy;
	ALPHA = color.a;
}
