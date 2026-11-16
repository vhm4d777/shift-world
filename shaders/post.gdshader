shader_type canvas_item;
// Full-screen post effect: dimension-shift shockwave, chromatic aberration,
// colour flash and a soft vignette.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform vec2 center = vec2(0.5, 0.5);
uniform float radius = -1.0;
uniform float strength = 0.0;
uniform float aberration = 0.0;
uniform float vignette = 0.45;
uniform float aspect = 1.7647;
uniform float flash = 0.0;
uniform vec3 flash_color = vec3(1.0);

void fragment() {
	vec2 uv = SCREEN_UV;
	if (radius > 0.0) {
		vec2 d = uv - center;
		d.x *= aspect;
		float dist = length(d);
		float x = (dist - radius) / 0.07;
		if (abs(x) < 1.0) {
			vec2 dir = normalize(d + vec2(1e-5));
			dir.x /= aspect;
			uv -= dir * (1.0 - x * x) * strength;
		}
	}
	vec3 col;
	if (aberration > 0.0001) {
		col.r = texture(screen_tex, uv + vec2(aberration, 0.0)).r;
		col.g = texture(screen_tex, uv).g;
		col.b = texture(screen_tex, uv - vec2(aberration, 0.0)).b;
	} else {
		col = texture(screen_tex, uv).rgb;
	}
	vec2 v = SCREEN_UV - 0.5;
	col *= 1.0 - dot(v, v) * vignette;
	col = mix(col, flash_color, flash);
	COLOR = vec4(col, 1.0);
}
