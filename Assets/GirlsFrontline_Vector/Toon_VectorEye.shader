Shader "Toon Shader/Toon_VectorEye"
{
    Properties
    {
        [Header(Texture)]
        _BaseMap ("Eye Base Map", 2D) = "white" {}
        _EyeBlendMap ("Eye Blend Overlay", 2D) = "black" {}
        _ExtraMap ("Extra Atlas", 2D) = "black" {}
        _ExtraIntensity ("Extra Intensity", Range(0, 2)) = 0

        [Header(Highlight)]
        _ShineMap ("Shine Map", 2D) = "black" {}
        _ShineColor ("Shine Color", Color) = (1,1,1,1)
        _ShineIntensity ("Shine Intensity", Range(0, 5)) = 1
        _EyeBlendIntensity ("Eye Blend Intensity", Range(0, 2)) = 0.85

        [Header(Lighting)]
        _ShadowColor ("Shadow Color", Color) = (0.55,0.48,0.45,1)
        _LightBoost ("Light Boost", Range(0.5, 2)) = 1.15

        [Header(Outline)]
        _OutlineWidth ("Outline Width", Range(0,0.01)) = 0.0005
        _OutlineColor ("Outline Color", Color) = (0.04,0.025,0.03,1)

        [Header(Color Adjust)]
        _Exposure ("Exposure", Range(0.5, 2.0)) = 1.0
        _Contrast ("Contrast", Range(0.0, 2.0)) = 1.0
        _Tint ("Tint", Color) = (1,1,1,1)
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }

        HLSLINCLUDE
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap);     SAMPLER(sampler_BaseMap);
            TEXTURE2D(_EyeBlendMap); SAMPLER(sampler_EyeBlendMap);
            TEXTURE2D(_ExtraMap);    SAMPLER(sampler_ExtraMap);
            TEXTURE2D(_ShineMap);    SAMPLER(sampler_ShineMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                float4 _EyeBlendMap_ST;
                float4 _ExtraMap_ST;
                float4 _ShineMap_ST;
                float4 _ShineColor;
                float _ShineIntensity;
                float _ExtraIntensity;
                float _EyeBlendIntensity;
                float4 _ShadowColor;
                float _LightBoost;
                float _OutlineWidth;
                float4 _OutlineColor;
                float _Exposure;
                float _Contrast;
                float4 _Tint;
            CBUFFER_END

            float3 Adjust(float3 color)
            {
                color *= _Tint.rgb;
                color *= _Exposure;
                color = (color - 0.5) * _Contrast + 0.5;
                return saturate(color);
            }

            float3 AlphaBlend(float3 baseColor, float4 overlay, float intensity)
            {
                return lerp(baseColor, overlay.rgb, saturate(overlay.a * intensity));
            }
        ENDHLSL

        Pass
        {
            Name "UniversalForward"
            Tags { "LightMode"="UniversalForward" }
            Cull Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 normalWS : TEXCOORD0;
                float2 uv : TEXCOORD1;
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                VertexPositionInputs pos = GetVertexPositionInputs(v.positionOS.xyz);
                VertexNormalInputs normal = GetVertexNormalInputs(v.normalOS);
                o.positionCS = pos.positionCS;
                o.normalWS = normal.normalWS;
                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);
                return o;
            }

            float4 frag(Varyings i) : SV_Target
            {
                float4 baseColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv);
                float4 blend = SAMPLE_TEXTURE2D(_EyeBlendMap, sampler_EyeBlendMap, TRANSFORM_TEX(i.uv, _EyeBlendMap));
                float4 extra = SAMPLE_TEXTURE2D(_ExtraMap, sampler_ExtraMap, TRANSFORM_TEX(i.uv, _ExtraMap));
                float shine = SAMPLE_TEXTURE2D(_ShineMap, sampler_ShineMap, TRANSFORM_TEX(i.uv, _ShineMap)).r;

                Light light = GetMainLight();
                float ndl = saturate(dot(normalize(i.normalWS), normalize(light.direction)) * 0.5 + 0.5);
                float3 lit = lerp(_ShadowColor.rgb, light.color * _LightBoost, ndl);

                float3 color = baseColor.rgb * lit;
                color = AlphaBlend(color, blend, _EyeBlendIntensity);
                color = AlphaBlend(color, extra, _ExtraIntensity);
                color += shine * _ShineColor.rgb * _ShineIntensity;
                return float4(Adjust(color), baseColor.a);
            }
            ENDHLSL
        }

        Pass
        {
            Name "Outline"
            Tags { "LightMode"="SRPDefaultUnlit" }
            Cull Front
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
            struct Varyings { float4 positionCS : SV_POSITION; };

            Varyings vert(Attributes v)
            {
                Varyings o;
                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(v.normalOS);
                positionWS += normalWS * _OutlineWidth;
                o.positionCS = TransformWorldToHClip(positionWS);
                return o;
            }

            half4 frag(Varyings i) : SV_Target { return _OutlineColor; }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Off

            HLSLPROGRAM
            #pragma vertex ShadowVS
            #pragma fragment ShadowFS
            #pragma multi_compile_instancing
            #pragma multi_compile _ DOTS_INSTANCING_ON
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            float3 _LightDirection;
            float3 _LightPosition;

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
            struct Varyings { float4 positionCS : SV_POSITION; };

            Varyings ShadowVS(Attributes v)
            {
                Varyings o;
                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(v.normalOS);
                #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                    float3 lightDirectionWS = normalize(_LightPosition - positionWS);
                #else
                    float3 lightDirectionWS = _LightDirection;
                #endif
                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));
                #if UNITY_REVERSED_Z
                    positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #else
                    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #endif
                o.positionCS = positionCS;
                return o;
            }

            float4 ShadowFS(Varyings i) : SV_Target { return 0; }
            ENDHLSL
        }
    }
}
