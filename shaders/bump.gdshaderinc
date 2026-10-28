// For surface shaders only: screen-space derivatives are not allowed in fog or sky shaders.

// Bump a view-space normal by a height field, using screen-space derivatives (Mikkelsen 2010).
vec3 bump_normal(vec3 pos, vec3 n, float h) {
	vec3 dpdx = dFdx(pos);
	vec3 dpdy = dFdy(pos);
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2);
	return normalize(abs(det) * n - grad);
}
