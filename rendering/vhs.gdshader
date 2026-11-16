shader_type canvas_item;

// Light tape grade: a little chroma, scanlines, vignette and lantern warmth.
// Strength stays low so HUD text and the road stay readable.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float amount : hint_range(0.0, 1.0) = 0.55;

void fragment() {
	vec2 uv = SCREEN_UV;
	float px = SCREEN_PIXEL_SIZE.x;
	float py = SCREEN_PIXEL_SIZE.y;
	float t = TIME;

	float wobble = sin(t * 1.6) * py * 0.55 * amount;
	vec2 suv = uv + vec2(0.0, wobble);

	float ca = px * 1.05 * amount;
	float r = texture(screen_tex, suv + vec2(ca, 0.0)).r;
	float g = texture(screen_tex, suv).g;
	float b = texture(screen_tex, suv - vec2(ca, 0.0)).b;
	vec3 col = vec3(r, g, b);

	float row = uv.y / max(py, 0.0001);
	float scan = step(0.55, fract(row * 0.5));
	col *= 1.0 - scan * 0.055 * amount;

	vec2 q = uv * 2.0 - 1.0;
	float vig = smoothstep(1.35, 0.42, dot(q, q));
	col *= mix(1.0, vig, 0.22 * amount);

	col = mix(col, col * vec3(1.05, 0.98, 0.91) + vec3(0.012, 0.005, 0.0), amount);

	float n = fract(sin(dot(uv + fract(t * 0.31), vec2(12.9898, 78.233))) * 43758.5453);
	col += (n - 0.5) * 0.022 * amount;

	float bar_y = fract(t * 0.025);
	float bar = smoothstep(0.018, 0.0, abs(uv.y - bar_y));
	col += vec3(0.035, 0.025, 0.015) * bar * amount;

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
