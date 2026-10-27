// Общая часть шейдеров эффектов: цвет и яркость задаются на экземпляре (set_instance_shader_parameter),
// поэтому на все вспышки/кольца/искры — по одному материалу каждого вида. Затухание — GeometryInstance3D.transparency.
instance uniform vec4 color : source_color = vec4(1.0);
instance uniform float energy = 1.0;
// Затухание для GL Compatibility: там GeometryInstance3D.transparency не работает, FX.sync_fades каждый кадр
// копирует 1 - transparency сюда. В Forward+ остаётся 1.0 — transparency движок сам кладёт в ALPHA по умолчанию,
// поэтому шейдеры альфу УМНОЖАЮТ (ALPHA *= …): присваивание ALPHA = … отключало затухание узла.
instance uniform float fade = 1.0;
