#include <metal_stdlib>
using namespace metal;

struct Particle {
    float2 position;
    float2 velocity;
    float2 affineX;
    float2 affineY;
};
struct Uniforms {
    uint4 dimensions;
    float4 step;
    float4 source;
};

constant uint binCapacity = 32;

float random01(uint value) {
    value ^= value >> 16;
    value *= 0x7feb352du;
    value ^= value >> 15;
    value *= 0x846ca68bu;
    value ^= value >> 16;
    return float(value & 0x00ffffffu) / float(0x01000000u);
}

float weight(float x) {
    x = abs(x);
    if (x < 0.5f) return 0.75f - x * x;
    if (x < 1.5f) return 0.5f * (1.5f - x) * (1.5f - x);
    return 0;
}

bool inside(int2 c, constant Uniforms &s) {
    return all(c >= 0) && c.x < int(s.dimensions.x) && c.y < int(s.dimensions.y);
}

uint countAt(int2 c, device atomic_uint *counts, constant Uniforms &s) {
    if (!inside(c, s)) return 0;
    return atomic_load_explicit(&counts[c.y * s.dimensions.x + c.x], memory_order_relaxed);
}

kernel void clearGrid(device atomic_uint *counts [[buffer(1)]],
                      constant Uniforms &s [[buffer(8)]], uint id [[thread_position_in_grid]]) {
    if (id < s.dimensions.x * s.dimensions.y)
        atomic_store_explicit(&counts[id], 0, memory_order_relaxed);
}

kernel void spawnParticles(device Particle *particles [[buffer(0)]],
                           constant Uniforms &s [[buffer(8)]], uint id [[thread_position_in_grid]]) {
    uint index = id + s.dimensions.w;
    if (index >= s.dimensions.z) return;
    float x = s.step.w + (random01(index * 2 + 1) - 0.5f) * s.source.y;
    Particle p;
    p.position = float2(clamp(x, 0.3f, float(s.dimensions.x) - 0.3f),
                        float(s.dimensions.y) - 0.3f - random01(index * 2 + 2) * 0.7f);
    p.velocity = float2(sin(s.step.z), -cos(s.step.z)) * s.source.x;
    p.affineX = p.affineY = 0;
    particles[index] = p;
}

kernel void binParticles(device const Particle *particles [[buffer(0)]],
                         device atomic_uint *counts [[buffer(1)]], device uint *bins [[buffer(2)]],
                         constant Uniforms &s [[buffer(8)]],
                         device atomic_uint *diagnostics [[buffer(9)]],
                         uint id [[thread_position_in_grid]]) {
    if (id >= s.dimensions.z) return;
    int2 cell = clamp(int2(floor(particles[id].position)), int2(0), int2(s.dimensions.xy) - 1);
    uint cellID = cell.y * s.dimensions.x + cell.x;
    uint slot = atomic_fetch_add_explicit(&counts[cellID], 1, memory_order_relaxed);
    if (slot < binCapacity) bins[cellID * binCapacity + slot] = id;
    else atomic_fetch_add_explicit(diagnostics, 1, memory_order_relaxed);
}

// Gather instead of floating-point atomic scatter, so this also works on simulator GPUs.
float gatherFace(float2 face, bool horizontal, device const Particle *particles,
                 device atomic_uint *counts, device const uint *bins, constant Uniforms &s) {
    float momentum = 0, mass = 0;
    int2 base = int2(floor(face - 1.5f));
    for (int j = 0; j < 4; ++j) for (int i = 0; i < 4; ++i) {
        int2 cell = base + int2(i, j);
        uint count = min(countAt(cell, counts, s), binCapacity);
        if (count == 0) continue;
        uint offset = (cell.y * s.dimensions.x + cell.x) * binCapacity;
        for (uint k = 0; k < count; ++k) {
            Particle p = particles[bins[offset + k]];
            float2 d = face - p.position;
            float w = weight(d.x) * weight(d.y);
            float velocity = horizontal ? p.velocity.x + dot(p.affineX, d)
                                        : p.velocity.y + dot(p.affineY, d);
            momentum += w * velocity;
            mass += w;
        }
    }
    return mass > 1e-6f ? momentum / mass : 0;
}

kernel void particlesToGrid(device const Particle *particles [[buffer(0)]],
                            device atomic_uint *counts [[buffer(1)]], device const uint *bins [[buffer(2)]],
                            device float *u [[buffer(3)]], device float *v [[buffer(4)]],
                            constant Uniforms &s [[buffer(8)]], uint id [[thread_position_in_grid]]) {
    uint nx = s.dimensions.x, ny = s.dimensions.y;
    if (id < (nx + 1) * ny) {
        uint x = id % (nx + 1), y = id / (nx + 1);
        u[id] = x == 0 || x == nx ? 0 :
            gatherFace(float2(x, y + 0.5f), true, particles, counts, bins, s);
    }
    if (id < nx * (ny + 1)) {
        uint x = id % nx, y = id / nx;
        v[id] = y == 0 || y == ny ? 0 :
            gatherFace(float2(x + 0.5f, y), false, particles, counts, bins, s) - s.step.y * s.step.x;
    }
}

kernel void computeDivergence(device const Particle *particles [[buffer(0)]],
                              device atomic_uint *counts [[buffer(1)]], device const uint *bins [[buffer(2)]],
                              device const float *u [[buffer(3)]], device const float *v [[buffer(4)]],
                              device float *pressure [[buffer(5)]], device float *other [[buffer(6)]],
                              device float *divergence [[buffer(7)]], constant Uniforms &s [[buffer(8)]],
                              uint id [[thread_position_in_grid]]) {
    uint nx = s.dimensions.x;
    if (id >= nx * s.dimensions.y) return;
    uint x = id % nx, y = id / nx;
    if (countAt(int2(x, y), counts, s) == 0) {
        pressure[id] = other[id] = 0;
        divergence[id] = 0;
    } else {
        pressure[id] = other[id] = 0;
        divergence[id] = u[y * (nx + 1) + x + 1] - u[y * (nx + 1) + x]
            + v[(y + 1) * nx + x] - v[y * nx + x];
        // Compensate accumulated particle compression. A divergence-free velocity alone
        // cannot undo density errors introduced by advection and emitter sampling.
        float density = 0;
        float2 center = float2(x + 0.5f, y + 0.5f);
        for (int j = -1; j <= 1; ++j) for (int i = -1; i <= 1; ++i) {
            int2 cell = int2(x, y) + int2(i, j);
            uint count = min(countAt(cell, counts, s), binCapacity);
            if (count == 0) continue;
            uint offset = (cell.y * nx + cell.x) * binCapacity;
            for (uint k = 0; k < count; ++k) {
                float2 d = center - particles[bins[offset + k]].position;
                density += weight(d.x) * weight(d.y);
            }
        }
        divergence[id] -= 0.05f / max(s.step.x, 1e-6f) * max(0.0f, density / 4.0f - 1.0f);
    }
}

// Pressure is scaled by dt/rho. Air is Dirichlet p=0; solid walls are Neumann.
kernel void solvePressure(device atomic_uint *counts [[buffer(1)]],
                          device const float *pressure [[buffer(5)]], device float *next [[buffer(6)]],
                          device const float *divergence [[buffer(7)]], constant Uniforms &s [[buffer(8)]],
                          uint id [[thread_position_in_grid]]) {
    int nx = s.dimensions.x;
    if (id >= s.dimensions.x * s.dimensions.y) return;
    int2 cell = int2(id % nx, id / nx);
    if (countAt(cell, counts, s) == 0) { next[id] = 0; return; }
    int2 neighbors[4] = {cell + int2(-1, 0), cell + int2(1, 0),
                         cell + int2(0, -1), cell + int2(0, 1)};
    float sum = 0, diagonal = 0;
    for (int k = 0; k < 4; ++k) {
        int2 c = neighbors[k];
        if (!inside(c, s)) continue;
        diagonal += 1;
        if (countAt(c, counts, s) > 0) sum += pressure[c.y * nx + c.x];
    }
    // Weighted Jacobi damps the checkerboard mode of the five-point Laplacian.
    next[id] = diagonal > 0 ? mix(pressure[id], (sum - divergence[id]) / diagonal, 0.8f) : 0;
}

kernel void projectVelocity(device atomic_uint *counts [[buffer(1)]],
                            device float *u [[buffer(3)]], device float *v [[buffer(4)]],
                            device const float *pressure [[buffer(5)]], constant Uniforms &s [[buffer(8)]],
                            uint id [[thread_position_in_grid]]) {
    uint nx = s.dimensions.x, ny = s.dimensions.y;
    if (id < (nx + 1) * ny) {
        int x = id % (nx + 1), y = id / (nx + 1);
        if (x == 0 || x == int(nx)) u[id] = 0;
        else if (countAt(int2(x - 1, y), counts, s) || countAt(int2(x, y), counts, s))
            u[id] -= pressure[y * nx + x] - pressure[y * nx + x - 1];
    }
    if (id < nx * (ny + 1)) {
        int x = id % nx, y = id / nx;
        if (y == 0 || y == int(ny)) v[id] = 0;
        else if (countAt(int2(x, y - 1), counts, s) || countAt(int2(x, y), counts, s))
            v[id] -= pressure[y * nx + x] - pressure[(y - 1) * nx + x];
    }
}

float sampleComponent(float2 position, bool horizontal, device const float *field,
                      constant Uniforms &s, thread float2 &affine) {
    float2 offset = horizontal ? float2(0, 0.5f) : float2(0.5f, 0);
    int2 size = int2(s.dimensions.xy) + (horizontal ? int2(1, 0) : int2(0, 1));
    int2 base = int2(floor(position - offset - 0.5f));
    float result = 0, sum = 0;
    affine = 0;
    float2 displacement = 0;
    for (int j = 0; j < 3; ++j) for (int i = 0; i < 3; ++i) {
        int2 cell = base + int2(i, j);
        if (any(cell < 0) || any(cell >= size)) continue;
        float2 delta = float2(cell) + offset - position;
        float w = weight(delta.x) * weight(delta.y);
        float value = field[cell.y * size.x + cell.x];
        result += w * value;
        affine += 4 * w * value * delta;
        displacement += w * delta;
        sum += w;
    }
    if (sum <= 1e-6f) return 0;
    result /= sum;
    // Remove the spurious constant-velocity moment from truncated wall stencils.
    affine = (affine - 4 * result * displacement) / sum;
    affine *= min(1.0f, 30.0f / max(length(affine), 1e-6f)) * 0.98f;
    return result;
}

kernel void advectParticles(device Particle *particles [[buffer(0)]],
                           device const float *u [[buffer(3)]], device const float *v [[buffer(4)]],
                           constant Uniforms &s [[buffer(8)]], uint id [[thread_position_in_grid]]) {
    if (id >= s.dimensions.z) return;
    Particle p = particles[id];
    p.velocity.x = sampleComponent(p.position, true, u, s, p.affineX);
    p.velocity.y = sampleComponent(p.position, false, v, s, p.affineY);
    // CFL safety cap: at most 0.9 cells per substep. This is a numerical safeguard.
    float speed = length(p.velocity);
    float maxSpeed = 0.9f / max(s.step.x, 1e-6f);
    if (speed > maxSpeed) p.velocity *= maxSpeed / speed;
    p.velocity *= exp(-0.08f * s.step.x);
    p.position += p.velocity * s.step.x;
    float2 lower = float2(0.2f), upper = float2(s.dimensions.xy) - 0.2f;
    for (uint axis = 0; axis < 2; ++axis) {
        if (p.position[axis] < lower[axis]) {
            p.position[axis] = lower[axis];
            p.velocity[axis] = max(0.0f, p.velocity[axis]);
            p.affineX = p.affineY = 0;
        } else if (p.position[axis] > upper[axis]) {
            p.position[axis] = upper[axis];
            p.velocity[axis] = min(0.0f, p.velocity[axis]);
            p.affineX = p.affineY = 0;
        }
    }
    particles[id] = p;
}

// Smooth compact-support density: particle discs merge into one continuous liquid surface.
kernel void buildSurface(device const Particle *particles [[buffer(0)]],
                         device atomic_uint *counts [[buffer(1)]], device const uint *bins [[buffer(2)]],
                         constant Uniforms &s [[buffer(8)]], texture2d<half, access::write> surface [[texture(0)]],
                         uint id [[thread_position_in_grid]]) {
    uint width = surface.get_width(), height = surface.get_height();
    if (id >= width * height) return;
    uint2 pixel = uint2(id % width, id / width);
    float2 position = (float2(pixel) + 0.5f) / float2(width, height) * float2(s.dimensions.xy);
    int2 base = int2(floor(position));
    float density = 0;
    for (int j = -1; j <= 1; ++j) for (int i = -1; i <= 1; ++i) {
        int2 cell = base + int2(i, j);
        uint count = min(countAt(cell, counts, s), binCapacity);
        if (count == 0) continue;
        uint offset = (cell.y * s.dimensions.x + cell.x) * binCapacity;
        for (uint k = 0; k < count; ++k) {
            float2 d = position - particles[bins[offset + k]].position;
            float q = max(0.0f, 1.0f - dot(d, d));
            density += q * q * q;
        }
    }
    surface.write(half4(half(density), 0, 0, 1), pixel);
}

struct RasterData { float4 position [[position]]; float2 uv; };

vertex RasterData fluidVertex(uint id [[vertex_id]]) {
    float2 vertices[3] = {float2(-1, -1), float2(3, -1), float2(-1, 3)};
    RasterData result;
    result.position = float4(vertices[id], 0, 1);
    result.uv = vertices[id] * 0.5f + 0.5f;
    return result;
}

fragment half4 fluidFragment(RasterData in [[stage_in]],
                             texture2d<half> surface [[texture(0)]],
                             constant Uniforms &s [[buffer(0)]]) {
    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float density = float(surface.sample(linearSampler, in.uv).r);
    float coverage = smoothstep(0.65f, 0.95f, density);
    if (coverage < 0.001f || s.source.z <= 0) return half4(0);
    float2 texel = 1.0f / float2(surface.get_width(), surface.get_height());
    float2 gradient = float2(
        float(surface.sample(linearSampler, in.uv + float2(texel.x, 0)).r)
        - float(surface.sample(linearSampler, in.uv - float2(texel.x, 0)).r),
        float(surface.sample(linearSampler, in.uv + float2(0, texel.y)).r)
        - float(surface.sample(linearSampler, in.uv - float2(0, texel.y)).r));
    float edge = 1 - smoothstep(0.9f, 2.1f, density);
    float3 normal = normalize(float3(-gradient * 2, 1));
    float light = pow(max(0.0f, dot(normal, normalize(float3(-0.6f, 0.8f, 1)))), 16.0f);
    float3 color = mix(float3(0.015f, 0.38f, 0.70f), float3(0.08f, 0.73f, 0.91f), in.uv.y);
    color += edge * (0.22f + light * 0.65f);
    float alpha = coverage * s.source.z;
    return half4(half3(color * alpha), half(alpha)); // Premultiplied source-over.
}
