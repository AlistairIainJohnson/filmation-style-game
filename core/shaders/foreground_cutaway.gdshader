shader_type spatial;
render_mode cull_back, depth_draw_opaque;

global uniform vec3 player_world_pos;

uniform vec4 albedo_color : source_color = vec4(0.47, 0.46, 0.44, 1.0);
uniform float metallic_val : hint_range(0.0, 1.0) = 0.04;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.78;
uniform float cutaway_radius : hint_range(0.2, 4.0) = 1.25;
uniform float cutaway_softness : hint_range(0.05, 1.5) = 0.45;
uniform float depth_bias : hint_range(0.0, 1.0) = 0.10;
instance uniform float cutaway_active : hint_range(0.0, 1.0) = 0.0;

float bayer8(ivec2 p) {
	int x = p.x & 7;
	int y = p.y & 7;
	int idx = x + y * 8;
	const int M[64] = int[64](
		 0, 32,  8, 40,  2, 34, 10, 42,
		48, 16, 56, 24, 50, 18, 58, 26,
		12, 44,  4, 36, 14, 46,  6, 38,
		60, 28, 52, 20, 62, 30, 54, 22,
		 3, 35, 11, 43,  1, 33,  9, 41,
		51, 19, 59, 27, 49, 17, 57, 25,
		15, 47,  7, 39, 13, 45,  5, 37,
		63, 31, 55, 23, 61, 29, 53, 21
	);
	return (float(M[idx]) + 0.5) / 64.0;
}

void fragment() {
	if (cutaway_active > 0.001) {
		vec3 player_view = (VIEW_MATRIX * vec4(player_world_pos, 1.0)).xyz;
		if (VERTEX.z > player_view.z + depth_bias) {
			float dist_xy = length(VERTEX.xy - player_view.xy);
			float factor = (1.0 - smoothstep(cutaway_radius - cutaway_softness, cutaway_radius, dist_xy)) * cutaway_active;
			if (factor > bayer8(ivec2(FRAGCOORD.xy))) {
				discard;
			}
		}
	}

	ALBEDO = albedo_color.rgb;
	METALLIC = metallic_val;
	ROUGHNESS = roughness_val;
}
