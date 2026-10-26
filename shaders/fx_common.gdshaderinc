// Общая часть шейдеров эффектов: цвет и яркость задаются на экземпляре (set_instance_shader_parameter),
// поэтому на все вспышки/кольца/искры — по одному материалу каждого вида. Затухание — GeometryInstance3D.transparency.
instance uniform vec4 color : source_color = vec4(1.0);
instance uniform float energy = 1.0;
