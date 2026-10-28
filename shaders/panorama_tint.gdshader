shader_type sky;

// Тонируем панораму только для профиля, который этого требует. Небо по-прежнему
// берётся из существующей текстуры; рисунок и направление солнца сохраняются.
uniform sampler2D panorama : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 sky_tint : source_color = vec4(1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform float energy = 1.0;

void sky() {
	vec3 source = texture(panorama, SKY_COORDS).rgb;
	float lightness = dot(source, vec3(0.2126, 0.7152, 0.0722));
	COLOR = mix(source, lightness * sky_tint.rgb, strength) * energy;
}
