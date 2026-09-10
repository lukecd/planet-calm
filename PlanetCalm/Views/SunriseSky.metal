#include <metal_stdlib>
using namespace metal;

// Original implementation of single-scattering radiative transfer. Units: km.
// See docs/design/splash-sunrise-model.md for sources and artistic approximations.
constant float earthRadius = 6360.0;
constant float atmosphereRadius = 6460.0;
constant float3 betaRayleigh = float3(0.005802, 0.013558, 0.033100);
constant float3 betaOzone = float3(0.000650, 0.001881, 0.000085);
constant float betaMie = 0.003996;
constant float mieExtinction = 0.004440;
constant float pi = 3.14159265;

// Autumn reuses the physical atmosphere integral, not the splash pigment progression.
struct SunriseUniforms { float4 viewport; float4 story; float4 optics; };
struct SkyVertex { float4 position [[position]]; float2 uv; };

vertex SkyVertex sunriseVertex(uint id [[vertex_id]]) {
    float2 uv = float2((id << 1) & 2, id & 2);
    return {float4(uv.x * 2 - 1, 1 - uv.y * 2, 0, 1), uv};
}

float boundaryDistance(float3 origin, float3 ray, float radius) {
    float b = dot(origin, ray);
    float discriminant = b * b - dot(origin, origin) + radius * radius;
    return discriminant < 0 ? -1 : -b + sqrt(discriminant);
}

float3 mediumDensity(float height) {
    return float3(exp(-height / 8.0), exp(-height / 1.2),
                  max(0.0, 1.0 - abs(height - 25.0) / 15.0));
}

float3 extinction(float3 density) {
    return betaRayleigh * density.x + mieExtinction * density.y + betaOzone * density.z;
}

kernel void sunriseTransmittance(texture2d<half, access::write> lut [[texture(0)]],
                                 uint2 tid [[thread_position_in_grid]]) {
    if (tid.x >= lut.get_width() || tid.y >= lut.get_height()) return;
    float2 uv = (float2(tid) + 0.5) / float2(lut.get_width(), lut.get_height());
    float height = uv.y * uv.y * 100.0;
    // Most samples resolve low solar angles, where the optical path changes fastest.
    float mu = -0.25 + uv.x * 1.25;
    float3 origin = float3(0, earthRadius + height, 0);
    float3 ray = float3(sqrt(max(0.0, 1.0 - mu * mu)), mu, 0);
    float distance = boundaryDistance(origin, ray, atmosphereRadius);
    float groundDiscriminant = pow(dot(origin, ray), 2.0) - dot(origin, origin) + earthRadius * earthRadius;
    if (mu < 0 && groundDiscriminant > 0) { lut.write(half4(0), tid); return; }
    float3 opticalDepth = 0;
    for (int i = 0; i < 64; ++i) {
        float t0 = float(i) / 64, t1 = float(i + 1) / 64;
        float a = distance * t0 * t0, b = distance * t1 * t1;
        float h = max(0.0, length(origin + ray * ((a + b) * 0.5)) - earthRadius);
        opticalDepth += extinction(mediumDensity(h)) * (b - a);
    }
    lut.write(half4(half3(exp(-opticalDepth)), 1), tid);
}

float3 sunTransmission(float3 point, float3 sun, texture2d<half> lut) {
    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float radius = length(point);
    float mu = dot(point / radius, sun);
    float2 uv = float2((mu + 0.25) / 1.25, sqrt(saturate((radius - earthRadius) / 100.0)));
    return float3(lut.sample(linearSampler, uv).rgb);
}

struct ScatteredLight { float3 rayleigh; float3 mie; };
ScatteredLight atmosphere(float3 ray, float3 sun, texture2d<half> lut) {
    float3 origin = float3(0, earthRadius + 0.1, 0);
    float distance = boundaryDistance(origin, ray, atmosphereRadius);
    float mu = dot(ray, sun);
    float rayPhase = 3.0 * (1 + mu * mu) / (16 * pi);
    float g = 0.8;
    float miePhase = (1 - g * g) / (4 * pi * pow(max(0.01, 1 + g * g - 2 * g * mu), 1.5));
    float3 throughput = 1, rayleigh = 0, mie = 0;
    for (int i = 0; i < 32; ++i) {
        float t0 = float(i) / 32, t1 = float(i + 1) / 32;
        float a = distance * t0 * t0, b = distance * t1 * t1;
        float dt = b - a;
        float3 point = origin + ray * ((a + b) * 0.5);
        float3 density = mediumDensity(max(0.0, length(point) - earthRadius));
        float3 sigma = extinction(density);
        float3 segmentT = exp(-sigma * dt);
        float3 integral = (1.0 - segmentT) / max(sigma, float3(1e-7));
        float3 energy = throughput * sunTransmission(point, sun, lut) * integral;
        rayleigh += energy * betaRayleigh * density.x * rayPhase;
        mie += energy * betaMie * density.y * miePhase;
        throughput *= segmentT;
    }
    return {rayleigh, mie};
}

float hash21(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }
float noise21(float2 p) {
    float2 i = floor(p), f = fract(p); f = f * f * (3 - 2 * f);
    return mix(mix(hash21(i), hash21(i + float2(1, 0)), f.x),
               mix(hash21(i + float2(0, 1)), hash21(i + 1), f.x), f.y);
}

// One cloud study, assembled from three opaque paper sheets in shallow depth.
// Coordinates and depths are short-side units; increasing z approaches the viewer.
constant int paperCloudLayerCount = 3;
constant float paperSunDepth = -0.60;
struct PaperCloudLayer { float2 center; float2 size; float depth; float pigment; };

PaperCloudLayer paperCloudLayer(int index, float aspect, float time) {
    float drift = 0.025 * sin(time * 0.035);
    // Balance the sun from the left; preserve the same lateral overlap as the
    // viewport widens instead of centering a cloud directly above the disc.
    float2 anchor = float2(aspect * 0.70 - 0.28 + drift, 0.40);
    // Broad lit crown, with progressively smaller, offset sheets below it.
    // Their lower edges remain exposed rather than hidden by the front sheet.
    switch (index) {
        case 0: return {anchor + float2( 0.014, 0.039), float2(0.205, 0.058), 0.13, 0.32};
        case 1: return {anchor + float2(-0.013, 0.010), float2(0.240, 0.075), 0.16, 0.66};
        default:return {anchor + float2( 0.002,-0.023), float2(0.275, 0.090), 0.19, 1.0};
    }
}

// Elliptical paper lobes meet as one cut edge. No grain enters the occlusion mask.
float cloudEllipse(float2 p, float2 center, float2 radii) {
    return (length((p - center) / radii) - 1) * min(radii.x, radii.y);
}
float paperCloudDistance(float2 point, PaperCloudLayer layer) {
    float2 p = (point - layer.center) / layer.size;
    float d = cloudEllipse(p, float2(-0.72, 0.18), float2(0.29, 0.47));
    d = min(d, cloudEllipse(p, float2(-0.43,-0.10), float2(0.37, 0.70)));
    d = min(d, cloudEllipse(p, float2(-0.04,-0.25), float2(0.40, 0.83)));
    d = min(d, cloudEllipse(p, float2( 0.37,-0.04), float2(0.37, 0.67)));
    d = min(d, cloudEllipse(p, float2( 0.73, 0.22), float2(0.29, 0.42)));
    return d * min(layer.size.x, layer.size.y);
}
float paperCloudAlpha(float2 point, PaperCloudLayer layer, float feather) {
    return 1 - smoothstep(-feather, feather, paperCloudDistance(point, layer));
}

// Intersect the source-to-receiver segment with each actual paper plane.
// The same source x/y used by the sunrise determines every projected shadow.
float paperSunVisibility(float2 receiver, float receiverDepth, float2 source,
                         float aspect, float time, int ignoredLayer, float feather) {
    float visibility = 1;
    for (int j = 0; j < paperCloudLayerCount; ++j) {
        PaperCloudLayer blocker = paperCloudLayer(j, aspect, time);
        if (j == ignoredLayer || blocker.depth >= receiverDepth) continue;
        float t = (blocker.depth - paperSunDepth) / (receiverDepth - paperSunDepth);
        float2 intersection = mix(source, receiver, t);
        visibility *= 1 - paperCloudAlpha(intersection, blocker, feather);
    }
    return visibility;
}

float3 toLab(float3 c) {
    float3 lms = float3(dot(c, float3(.4122214708,.5363325363,.0514459929)),
                        dot(c, float3(.2119034982,.6806995451,.1073969566)),
                        dot(c, float3(.0883024619,.2817188376,.6299787005)));
    lms = pow(max(lms, 0.0), float3(1.0/3.0));
    return float3(dot(lms, float3(.2104542553,.7936177850,-.0040720468)),
                  dot(lms, float3(1.9779984951,-2.4285922050,.4505937099)),
                  dot(lms, float3(.0259040371,.7827717662,-.8086757660)));
}
float3 fromLab(float3 c) {
    float3 lms = float3(c.x+.3963377774*c.y+.2158037573*c.z,
                        c.x-.1055613458*c.y-.0638541728*c.z,
                        c.x-.0894841775*c.y-1.291485548*c.z);
    lms = lms*lms*lms;
    return float3(dot(lms,float3(4.0767416621,-3.3077115913,.2309699292)),
                  dot(lms,float3(-1.2684380046,2.6097574011,-.3413193965)),
                  dot(lms,float3(-.0041960863,-.7034186147,1.707614701)));
}
float3 warmPaperBlend(float3 a, float3 b, float t) {
    float3 la=toLab(a), lb=toLab(b);
    float ha=atan2(la.z,la.y), hb=atan2(lb.z,lb.y);
    // Keep cool blues negative and gold positive: no branch at the gold hue.
    // Wrapping every negative delta by 2pi creates a full rainbow at near-gold pixels.
    float dh=hb-ha;
    // Cool ink crosses violet and rose on the route to warm paper.
    float h=ha+dh*t;
    float c=mix(length(la.yz),length(lb.yz),t);
    float l=mix(la.x,lb.x,t);
    return max(0.0,fromLab(float3(l,c*cos(h),c*sin(h))));
}
float3 linearToSRGB(float3 c) {
    return select(1.055 * pow(max(c, 0.0), float3(1.0 / 2.4)) - 0.055, 12.92 * c, c <= 0.0031308);
}
float3 sRGBToLinear(float3 c) {
    return select(pow((c + 0.055) / 1.055, float3(2.4)), c / 12.92, c <= 0.04045);
}

fragment half4 sunriseFragment(SkyVertex in [[stage_in]],
                                constant SunriseUniforms &u [[buffer(0)]],
                                texture2d<half> lut [[texture(0)]],
                                texture2d<half> grain [[texture(1)]]) {
    float2 size = u.viewport.xy;
    float shortSide = min(size.x, size.y);
    float2 point = in.uv * size / shortSide;
    float2 sunPoint = u.viewport.zw / shortSide;
    float p = saturate(u.story.x);
    float elevation = u.optics.x;
    float3 sun = float3(0, sin(elevation), cos(elevation));
    float2 delta = point - sunPoint;
    // Paper-dome projection: mirror the atmosphere below the paper horizon. It
    // continues the light behind navigation without adding a photographic ground.
    float distanceFromSun = length(delta);
    float discRadius = u.story.z / shortSide;
    float opticalDistance = max(0.0, distanceFromSun - discRadius * 0.85);
    float viewElevation = max(0.002, elevation + opticalDistance * 0.48);
    float azimuth = 0;
    float3 ray = float3(sin(azimuth) * cos(viewElevation), sin(viewElevation), cos(azimuth) * cos(viewElevation));
    ScatteredLight light = atmosphere(ray, sun, lut);

    float cloudTime = u.story.w;
    float aspect = size.x / shortSide;
    // A shallow scattering slab samples shadows cast by the separate paper planes.
    // This is a 2.5D approximation, not a volume of simulated cloud droplets.
    float visibility = 0;
    for (int i = 0; i < 24; ++i) {
        float receiverDepth = mix(0.22, 0.85, (float(i) + 0.5) / 24);
        visibility += paperSunVisibility(point, receiverDepth, sunPoint,
                                        aspect, cloudTime, -1, 0.005) / 24;
    }
    float rayWindow = sin(pi * p) * sin(pi * p);
    float3 radiance = (light.rayleigh + light.mie * mix(1.0, visibility, 0.7 * rayWindow)) * 12.0;
    float exposure = u.optics.y;
    float3 physical = 1 - exp(-radiance * exposure);
    float3 ink = sRGBToLinear(float3(10, 17, 36) / 255.0);
    float3 color = ink + physical * (0.025 + 0.55 * smoothstep(0.0, 0.7, p));
    float3 lab = toLab(color);
    // A continuous pigment gamut from ink-blue through violet/coral to gold.
    // The spectral red/blue ratio determines warmth; hue is never recovered at
    // zero chroma, where atan2 produces discontinuities and green seams.
    float warm = smoothstep(-0.25, 0.55, (color.r-color.b)/(color.r+color.b+0.001));
    float hue = mix(-1.55, 1.35, warm);
    float chroma = mix(0.06, 0.12, warm);
    lab.x += warm * smoothstep(0.03,0.3,p) * 0.20;
    color=max(0.0,fromLab(float3(lab.x,chroma*cos(hue),chroma*sin(hue))));

    // Art-directed paper illumination: a warm pool expands from the same solar
    // origin. This is explicitly a stylization, not a claimed atmospheric law.
    float distance = length(delta);
    float spread = u.optics.z;
    float illumination = exp(-distance * distance / (2 * spread * spread));
    float daylight = u.optics.w * illumination;
    float3 gold = sRGBToLinear(float3(255, 206, 88) / 255.0);
    color = warmPaperBlend(color, gold, saturate(daylight));
    // The reference endpoint is yellow paper. Finish gradually, preserving local
    // variation until the end; this does not determine the preceding sky colors.
    // The widening spatial field reaches the entire canvas continuously at 100%.

    // The paper finish receives the same projected shadow as the scattering slab.
    // Keep uncovered pixels exactly on the approved sunrise's color path.
    color *= 1 - (1 - visibility) * 0.24 * rayWindow;

    float3 output = linearToSRGB(clamp(color, 0.0, 1.0));
    output += (hash21(in.position.xy) - 0.5) / 255.0;
    return half4(half3(output), 1);
}

fragment half4 paperCloudFragment(SkyVertex in [[stage_in]],
                                    constant SunriseUniforms &u [[buffer(0)]],
                                    texture2d<half> grain [[texture(1)]]) {
    float2 size = u.viewport.xy;
    float shortSide = min(size.x, size.y);
    float2 point = in.uv * size / shortSide;
    float2 sunPoint = u.viewport.zw / shortSide;
    float aspect = size.x / shortSide;
    float cloudTime = u.story.w;
    float p = saturate(u.story.x);
    float3 gold = sRGBToLinear(float3(255, 206, 88) / 255.0);
    float3 color = 0;
    float alpha = 0;
    constexpr sampler paperSampler(coord::normalized, address::repeat, filter::linear);
    float dawn = smoothstep(0.05, 0.45, p);
    float day = smoothstep(0.65, 1.0, p);
    // Blue/slate backs and cream faces; sunrise light adds peach to exposed pieces.
    float3 coolBack = sRGBToLinear(float3(49, 76, 111) / 255.0);
    float3 coolFace = sRGBToLinear(float3(188, 205, 222) / 255.0);
    float3 warmBack = sRGBToLinear(float3(151, 120, 169) / 255.0);
    float3 warmFace = sRGBToLinear(float3(255, 218, 187) / 255.0);
    float3 dayBack = sRGBToLinear(float3(99, 132, 162) / 255.0);
    float3 dayFace = sRGBToLinear(float3(249, 244, 232) / 255.0);
    float3 backPigment = mix(mix(coolBack, warmBack, dawn), dayBack, day);
    float3 facePigment = mix(mix(coolFace, warmFace, dawn), dayFace, day);
    for (int i = 0; i < paperCloudLayerCount; ++i) {
        PaperCloudLayer layer = paperCloudLayer(i, aspect, cloudTime);
        float cover = paperCloudAlpha(point, layer, 0.001);
        // Contact shading makes the stacked paper thickness readable even in shade.
        // It is a restrained studio-fill cue, separate from solar occlusion.
        float contact = paperCloudAlpha(point - float2(0.001, 0.005), layer, 0.0035);
        float shadowAlpha = contact * (1 - cover) * 0.22;
        color *= 1 - shadowAlpha;
        alpha = shadowAlpha + alpha * (1 - shadowAlpha);
        if (cover <= 0) continue;
        float direct = paperSunVisibility(point, layer.depth, sunPoint,
                                          aspect, cloudTime, i, 0.003);
        float3 pigment = mix(backPigment, facePigment, layer.pigment);
        float3 face = pigment * (0.76 + 0.24 * direct);
        float paper = float(grain.sample(paperSampler,
            (point - layer.center) * shortSide / 240.0 + float2(i * 0.27, i * 0.13)).r);
        face *= 0.88 + paper * 0.24;
        float2 towardSun = normalize(sunPoint - point + float2(0.0001));
        float edge = 1 - paperCloudAlpha(point + towardSun * 0.003, layer, 0.001);
        face += gold * edge * 0.12 * sin(pi * p);
        color = mix(color, face, cover);
        alpha = cover + alpha * (1 - cover);
    }

    // UIKit composites the clear cloud surface over the separately drawn paper sun.
    float3 straight = color / max(alpha, 0.00001);
    return half4(half3(linearToSRGB(clamp(straight, 0.0, 1.0)) * alpha), half(alpha));
}

// Fixed-view paper clearing: blue sky fill and a low, warm directional sun.
fragment half4 autumnSkyFragment(SkyVertex in [[stage_in]],
                                constant SunriseUniforms& u [[buffer(0)]],
                                texture2d<half> transmittance [[texture(0)]],
                                texture2d<half> paperGrain [[texture(1)]]) {
    float2 pixel = in.uv * u.viewport.xy;
    float p = saturate(u.story.x);
    float2 solar = u.viewport.zw / u.viewport.xy;
    float elevation = u.optics.x;
    float3 sunDirection = normalize(float3(0, sin(elevation), cos(elevation)));
    float azimuth = (in.uv.x - solar.x) * 1.5;
    float viewElevation = max(0.002, elevation + (solar.y - in.uv.y) * 0.70);
    float3 ray = normalize(float3(sin(azimuth), sin(viewElevation), cos(azimuth) * cos(viewElevation)));
    ScatteredLight scattered = atmosphere(ray, sunDirection, transmittance);
    float3 physical = 1 - exp(-(scattered.rayleigh + scattered.mie) * 10 * u.optics.y);
    float distance = length((pixel - u.viewport.zw) / min(u.viewport.x, u.viewport.y));
    float warm = exp(-distance * distance / 0.16) * (1 - 0.45 * p);
    float3 coolPaper = mix(float3(0.29,0.43,0.59), float3(0.16,0.19,0.32), p);
    float3 radiance = coolPaper * (0.6 + physical * 0.45)
        + float3(1.0,0.53,0.23) * warm * u.optics.y * 0.55;
    constexpr sampler grainSampler(coord::normalized, address::repeat, filter::linear);
    float grain = float(paperGrain.sample(grainSampler, pixel / 420).r) - 0.5;
    return half4(half3(saturate(radiance + grain * 0.045)), 1);
}
