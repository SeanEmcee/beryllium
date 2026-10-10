#include <metal_stdlib>
using namespace metal;

// Animated text-only shader; preserves the text glyph's original alpha.
[[ stitchable ]] half4 berylliumTypographyFX(float2 position, half4 color,
                                                 float time, float strength, float effect) {
    if (color.a <= half(0.001) || effect < 0.5) return color;
    float wave = 0.5 + 0.5 * sin(position.x * 0.035 - time * 3.0);
    float3 rgb = float3(color.rgb) / max(float(color.a), 0.0001);
    if (effect < 1.5) { // Shimmer: moving highlights.
        float highlight = pow(wave, 8.0) * strength;
        rgb = mix(rgb, float3(1.0), highlight);
    } else if (effect < 2.5) { // Aurora: cyan-violet chromatic movement.
        float phase = time * 0.7 + position.x * 0.025 + position.y * 0.025;
        float3 aurora = float3(0.45 + 0.45 * sin(phase),
                              0.55 + 0.40 * sin(phase + 2.1),
                              0.65 + 0.33 * sin(phase + 4.2));
        rgb = mix(rgb, aurora, 0.70 * strength);
    } else if (effect < 3.5) { // Pulse: soft rhythmic light.
        rgb *= 1.0 + strength * (0.14 + 0.26 * sin(time * 2.2));
    } else { // Holographic: iridescent spatial diffraction.
        float p = position.x * 0.048 - position.y * 0.018 - time * 1.4;
        float3 prism = float3(0.55 + 0.45 * sin(p),
                              0.55 + 0.45 * sin(p + 2.094),
                              0.55 + 0.45 * sin(p + 4.188));
        rgb = mix(rgb, prism, 0.76 * strength);
    }
    return half4(half3(clamp(rgb, 0.0, 1.0)) * color.a, color.a);
}
