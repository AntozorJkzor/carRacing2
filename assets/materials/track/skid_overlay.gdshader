shader_type spatial;

// Skid-only overlay. Asphalt stays on the ground StandardMaterial3D.
// Lit but matte: a little sun/ambient reaches the rubber, no shiny reflections.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled, shadows_disabled;

uniform sampler2D skid_tex : hint_default_black, filter_nearest, repeat_disable;
uniform vec3 rubber_color : source_color = vec3(0.025, 0.022, 0.02);
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform float alpha_cutoff : hint_range(0.0, 0.5) = 0.04;
uniform float light_response : hint_range(0.0, 1.0) = 0.35;

void fragment() {
	float mark = texture(skid_tex, UV).r * opacity;
	ALBEDO = rubber_color;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	ALPHA = mark;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
}

void light() {
	// Soften how much directional/ambient light sticks to the rubber.
	DIFFUSE_LIGHT *= light_response;
	SPECULAR_LIGHT *= 0.0;
}
