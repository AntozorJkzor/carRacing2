shader_type spatial;

uniform vec4 base_color : source_color = vec4(0.12, 0.14, 0.17, 1.0);
uniform vec4 line_color : source_color = vec4(0.25, 0.29, 0.34, 1.0);
uniform float spacing = 5.0;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 coord = world_position.xz / max(spacing, 0.01);
	vec2 width = max(fwidth(coord), vec2(0.0001));
	vec2 grid = abs(fract(coord - 0.5) - 0.5) / width;
	float line = 1.0 - min(min(grid.x, grid.y), 1.0);
	ALBEDO = mix(base_color.rgb, line_color.rgb, line);
	ROUGHNESS = 0.92;
}
