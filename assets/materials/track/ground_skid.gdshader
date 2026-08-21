shader_type spatial;

// Legacy combined asphalt+skid shader — unused.
// Skids now use skid_overlay.gdshader on a separate mesh;
// asphalt stays on Ground/Plane StandardMaterial3D.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_tint : source_color = vec4(0.28, 0.29, 0.3, 1.0);
uniform float asphalt_uv_scale : hint_range(1.0, 500.0) = 250.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.85;

void fragment() {
	ALBEDO = texture(albedo_tex, UV * asphalt_uv_scale).rgb * albedo_tint.rgb;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
}
