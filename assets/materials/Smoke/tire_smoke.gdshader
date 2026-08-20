shader_type spatial;

render_mode blend_mix, cull_disabled, depth_draw_never, diffuse_burley, specular_disabled;

uniform sampler2D smoke_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D noise_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 base_tint : source_color = vec4(0.4, 0.4, 0.42, 1.0);
uniform vec2 noise_scroll = vec2(0.02, -0.01);
uniform float noise_scale : hint_range(0.1, 8.0) = 2.2;
uniform float noise_mix : hint_range(0.0, 1.0) = 0.45;
uniform float alpha_strength : hint_range(0.0, 2.0) = 1.0;
uniform float ground_y = 0.0;
uniform float bottom_fade_height : hint_range(0.01, 2.0) = 0.14;
uniform float bottom_softness : hint_range(0.0, 1.0) = 0.32;
uniform float edge_power : hint_range(0.5, 4.0) = 1.35;
uniform float self_light : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float smoke_alpha = texture(smoke_tex, UV).a;
	vec2 noise_uv = UV * noise_scale + noise_scroll * TIME;
	float noise_value = texture(noise_tex, noise_uv).r;
	float noisy_alpha = smoke_alpha * mix(1.0, clamp(noise_value * 1.2, 0.55, 1.0), noise_mix);

	float radial = 1.0 - clamp(distance(UV, vec2(0.5)) * 2.0, 0.0, 1.0);
	float edge_fade = pow(radial, edge_power);
	float uv_bottom = smoothstep(0.0, max(bottom_softness, 0.001), UV.y);
	float ground_fade = smoothstep(ground_y, ground_y + max(bottom_fade_height, 0.001), WORLD_POSITION.y);
	float alpha = noisy_alpha * edge_fade * mix(1.0, uv_bottom, 0.55) * ground_fade * alpha_strength;

	ALBEDO = base_tint.rgb * COLOR.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = ALBEDO * self_light * alpha;
	ALPHA = clamp(alpha * COLOR.a, 0.0, 1.0);
}
