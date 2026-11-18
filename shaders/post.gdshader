shader_type canvas_item;
// Full-screen post effect: dimension-shift shockwave, chromatic aberration,
// bloom on bright pixels, light film grain, colour flash and a soft vignette.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform vec2 center = vec2(0.5, 0.5);
uniform float radius = -1.0;
uniform float strength = 0.0;
uniform float aberration = 0.0;
uniform float vignette = 0.45;
uniform float aspect = 1.7647;
uniform float flash = 0.0;
uniform vec3 flash_color = vec3(1.0);
uniform float bloom = 0.6;
uniform float grain = 0.025;

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
	// bloom: gather bright neighbours in two rings
	vec2 px = vec2(1.0 / 480.0, 1.0 / 272.0);
	vec3 glow = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.785398;
		vec2 o = vec2(cos(a), sin(a)) * px;
		glow += max(texture(screen_tex, uv + o * 2.0).rgb - 0.6, 0.0);
		glow += max(texture(screen_tex, uv + o * 5.0).rgb - 0.6, 0.0) * 0.6;
	}
	col += glow * bloom * 0.16;
	float n = fract(sin(dot(floor(SCREEN_UV * vec2(480.0, 272.0)) + TIME, vec2(12.9898, 78.233))) * 43758.5453);
	col += (n - 0.5) * grain;
	vec2 v = SCREEN_UV - 0.5;
	col *= 1.0 - dot(v, v) * vignette;
	col = mix(col, flash_color, flash);
	COLOR = vec4(col, 1.0);
}
