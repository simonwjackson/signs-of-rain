// Screen derivatives recover a surface gradient in view space. Unlike NORMAL_MAP,
// this works on procedural meshes without tangent arrays or UV seam artefacts.
vec3 surface_detail_normal(vec3 position, vec3 normal, float height) {
	vec3 dx = dFdx(position);
	vec3 dy = dFdy(position);
	vec3 rx = cross(dy, normal);
	vec3 ry = cross(normal, dx);
	float determinant = dot(dx, rx);
	vec3 gradient = sign(determinant) * (dFdx(height) * rx + dFdy(height) * ry);
	return normalize(abs(determinant) * normal - gradient);
}
