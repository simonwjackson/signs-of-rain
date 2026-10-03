shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://game/materials/surface_detail.gdshaderinc"
uniform vec4 base_color : source_color = vec4(0.6,0.55,0.45,1.0);
uniform float texture_scale = 8.0;
uniform float variation : hint_range(0.0,1.0) = 0.2;
uniform float surface_roughness : hint_range(0.0,1.0) = 0.85;
uniform float grain_direction = 0.0;
varying vec3 local_position;
varying vec3 instance_tint;
float hash(vec3 p) { return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453); }
float noise(vec3 p) {
	vec3 i=floor(p); vec3 f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}
void vertex() { local_position=VERTEX; instance_tint=COLOR.rgb; }
void fragment() {
	vec3 p=local_position*texture_scale;
	float n=noise(p)*0.6+noise(p*3.7)*0.25+noise(p*15.0)*0.15;
	float grain=sin(p.x*8.0+noise(p*vec3(0.3,0.03,0.3))*15.0)*0.5+0.5;
	n=mix(n,grain*0.65+n*0.35,grain_direction);
	ALBEDO=base_color.rgb*instance_tint*(1.0+(n-0.5)*variation);
	ROUGHNESS=surface_roughness;
	SPECULAR=0.25;
	NORMAL=surface_detail_normal(VERTEX,NORMAL,n*0.002);
}
