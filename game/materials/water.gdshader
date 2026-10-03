shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://game/materials/surface_detail.gdshaderinc"
uniform vec4 water_color : source_color = vec4(0.095,0.19,0.165,1.0);
varying vec3 world_position;
void vertex() { world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
	vec2 p=world_position.xz;
	float a=sin(p.x*4.6+p.y*2.3+TIME*0.9);
	float b=cos(p.y*6.7-p.x*1.9-TIME*0.65);
	float c=sin(p.x*13.0+p.y*8.0-TIME*1.2);
	ALBEDO=water_color.rgb*(0.9+0.1*a*b);
	METALLIC=0.30;
	ROUGHNESS=0.16;
	SPECULAR=0.85;
	NORMAL=surface_detail_normal(VERTEX,NORMAL,a*0.012+b*0.008+c*0.003);
}
