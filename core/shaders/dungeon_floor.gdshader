shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform vec4 room_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float slab_scale : hint_range(0.5, 2.5) = 1.0;

varying vec3 v_world_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 34.53);
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
		p = p * 2.03 + vec2(17.3, 9.1);
		amp *= 0.5;
	}
	return v;
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_world_pos.xz * slab_scale;

	// Subtle organic edge wobble so stone joints feel hand-hewn
	vec2 wobble = vec2(fbm(p * 3.1) - 0.5, fbm(p * 3.1 + vec2(8.4, 2.9)) - 0.5) * 0.032;
	vec2 wp = p + wobble;

	float row_h = 0.62;
	float row_idx = floor(wp.y / row_h);
	float row_y = fract(wp.y / row_h);

	// Stagger alternate rows and vary slab width per row via row hash
	float row_shift = mod(row_idx, 2.0) * 0.48 + (hash21(vec2(row_idx, 7.1)) - 0.5) * 0.16;
	float col_w = mix(0.86, 1.24, hash21(vec2(row_idx, 19.3)));
	float x_coord = wp.x + row_shift;
	float col_idx = floor(x_coord / col_w);
	float col_x = fract(x_coord / col_w);

	vec2 cell_id = vec2(col_idx, row_idx);
	float cell_rand = hash21(cell_id);
	float cell_warm = hash21(cell_id + vec2(31.7, 11.3));

	// Compute metric distance to nearest horizontal/vertical mortar seam
	float dist_x = min(col_x, 1.0 - col_x) * col_w;
	float dist_y = min(row_y, 1.0 - row_y) * row_h;
	float edge_dist = min(dist_x, dist_y);

	// Crisp mortar groove (~0.035m) + subtle beveled stone shoulder
	float mortar_mask = 1.0 - smoothstep(0.018, 0.042, edge_dist);
	float bevel_dark = 1.0 - smoothstep(0.035, 0.115, edge_dist);

	// Multi-scale stone grain & slight pitting
	float grain = fbm(v_world_pos.xz * 2.9 + cell_id * 3.7);
	float micro = vnoise(v_world_pos.xz * 12.0 + vec2(cell_rand * 10.0));

	// Neutral-warm and cool-slate medieval limestone palette (zero checkerboard)
	vec3 stone_warm = vec3(0.35, 0.33, 0.30);
	vec3 stone_cool = vec3(0.24, 0.25, 0.27);
	vec3 stone_base = mix(stone_cool, stone_warm, mix(cell_warm, cell_rand, 0.45));
	stone_base *= mix(0.84, 1.14, grain);
	stone_base *= mix(0.92, 1.05, micro);

	// Subtle damp moss/grime near joints & weathered dark mortar
	vec3 mortar_col = vec3(0.11, 0.11, 0.10) * mix(0.85, 1.15, micro);
	vec3 grime_col = vec3(0.16, 0.18, 0.15);
	float damp_patch = smoothstep(0.58, 0.85, fbm(v_world_pos.xz * 0.7 + vec2(5.2, 1.9)));

	vec3 col = mix(stone_base, stone_base * 0.72, bevel_dark * 0.42);
	col = mix(col, grime_col, damp_patch * bevel_dark * 0.38);
	col = mix(col, mortar_col, mortar_mask);

	// Gentle room tint (matches forest_floor.gdshader tint strength)
	col *= mix(vec3(1.0), room_tint.rgb, 0.35);

	ALBEDO = col;
	METALLIC = 0.0;
	ROUGHNESS = mix(mix(0.72, 0.88, 1.0 - grain), 0.95, mortar_mask);
}
