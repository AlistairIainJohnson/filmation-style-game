shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform vec4 room_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float path_width : hint_range(0.5, 4.0) = 1.6;
uniform float detail_scale : hint_range(0.5, 4.0) = 1.35;

varying vec3 v_world_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * vnoise(p);
		p = p * 2.07 + vec2(13.1, 7.7);
		amp *= 0.5;
	}
	return v;
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = v_world_pos.xz * detail_scale;
	float macro = fbm(uv * 0.55);
	float micro = fbm(uv * 2.8 + vec2(4.2, -3.1));
	float leaf_fleck = vnoise(uv * 6.5);

	vec3 soil = vec3(0.20, 0.15, 0.10);
	vec3 moss_deep = vec3(0.16, 0.29, 0.13);
	vec3 fern_hi = vec3(0.25, 0.39, 0.17);
	vec3 leaf_litter = vec3(0.35, 0.23, 0.12);

	// Blend soil, moss patches & sunlit fern highlights organically
	vec3 col = mix(soil, moss_deep, smoothstep(0.30, 0.65, macro));
	col = mix(col, fern_hi, smoothstep(0.55, 0.85, micro) * smoothstep(0.35, 0.72, macro) * 0.75);

	// Subtle scattered fallen autumn leaves & twigs on the loam
	float fleck_mask = smoothstep(0.76, 0.90, leaf_fleck) * smoothstep(0.25, 0.65, 1.0 - macro * 0.5);
	col = mix(col, leaf_litter, fleck_mask * 0.65);

	// Gentle worn dirt footpath along central cross-axes so drop shadow & hazards read crisply
	float dist_edge = min(min(v_world_pos.x, 8.0 - v_world_pos.x), min(v_world_pos.z, 8.0 - v_world_pos.z));
	float rim_moss = 1.0 - smoothstep(0.2, 1.4, dist_edge);
	col = mix(col, moss_deep * 0.90, rim_moss * 0.45);
	float center_track = exp(-pow(min(abs(v_world_pos.x - 4.0), abs(v_world_pos.z - 4.0)) / path_width, 2.0));
	col = mix(col, soil * 1.12, center_track * 0.32 * smoothstep(0.25, 0.75, micro));

	col *= mix(vec3(1.0), room_tint.rgb, 0.40);

	ALBEDO = col;
	METALLIC = 0.0;
	ROUGHNESS = mix(0.84, 0.94, 1.0 - macro);
}
