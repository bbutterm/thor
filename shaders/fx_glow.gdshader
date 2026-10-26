shader_type spatial;
#include "res://shaders/fx_common.gdshaderinc"

void fragment() {
	ALBEDO = color.rgb;
	ROUGHNESS = 0.4;
	EMISSION = color.rgb * energy;
}
