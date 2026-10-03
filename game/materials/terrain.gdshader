shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://game/materials/surface_detail.gdshaderinc"

uniform vec2 rain_center = vec2(0.0);
uniform float rain_strength : hint_range(0.0, 1.0) = 0.0;
varying vec3 world_position;
varying vec3 world_normal;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);
}
float path_distance(vec2 p, vec2 a, vec2 b) {
	vec2 ab=b-a; return length(p-a-ab*clamp(dot(p-a,ab)/dot(ab,ab),0.0,1.0));
}
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
	world_normal = MODEL_NORMAL_MATRIX * NORMAL;
}
void fragment() {
	vec2 p = world_position.xz;
	float broad = noise(p * 0.12) * 0.55 + noise(p * 0.43) * 0.3 + noise(p * 1.7) * 0.15;
	float grit = noise(p * 27.0);
	float river = 7.0 + sin(p.y * 0.061) * 7.0 + sin(p.y * 0.14) * 1.8;
	float bank = 1.0-smoothstep(2.0,5.4,abs(p.x-river));
	float clearing = max(1.0-smoothstep(7.5,13.0,length(p-vec2(-26,2))),1.0-smoothstep(7.5,13.0,length(p-vec2(26,2))));
	float track=min(path_distance(p,vec2(-26,2),vec2(26,2)),min(path_distance(p,vec2(-26,2),vec2(0,-4)),path_distance(p,vec2(26,2),vec2(0,-4))));
	track=min(track,min(path_distance(p,vec2(-26,2),vec2(0,8.5)),path_distance(p,vec2(26,2),vec2(0,8.5))));
	float path = 1.0-smoothstep(0.45,1.4,track + (noise(p*2.0)-0.5)*0.35);
	vec3 grass=mix(vec3(0.14,0.17,0.073),vec3(0.29,0.28,0.12),broad);
	vec3 earth=mix(vec3(0.26,0.22,0.15),vec3(0.42,0.37,0.24),broad);
	vec3 rock=mix(vec3(0.30,0.31,0.26),vec3(0.51,0.50,0.40),noise(p*0.65));
	vec3 col=mix(grass,earth,max(clearing*0.60,path*0.9));
	col=mix(col,earth*0.81,bank*0.86);
	float slope=1.0-abs(normalize(world_normal).y);
	col=mix(col,rock,smoothstep(0.10,0.35,slope));
	float fissure=pow(1.0-abs(sin(p.x*7.1+noise(p*0.8)*18.0)*sin(p.y*5.3+noise(p*1.3)*9.0)),26.0);
	col *= 0.94 + grit*0.12 - fissure*bank*0.13;
	float wet=rain_strength*(1.0-smoothstep(4.0,15.0,length(p-rain_center)));
	ALBEDO = col * (1.0-wet*0.32);
	ROUGHNESS = mix(0.94,0.46,wet);
	SPECULAR = 0.25;
	NORMAL = surface_detail_normal(VERTEX,NORMAL,(grit-fissure*bank*0.25)*0.003);
}
