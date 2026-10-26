shader_type spatial;
render_mode unshaded, shadows_disabled, fog_disabled;
#include "res://shaders/fx_common.gdshaderinc"

void fragment() {
	ALBEDO = color.rgb * energy;
}
