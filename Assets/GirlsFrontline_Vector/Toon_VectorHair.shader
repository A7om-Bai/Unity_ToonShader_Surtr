Shader "Toon Shader/Toon_VectorHair"
{
    Properties
    {
        [Header(Texture)]
        _BaseMap ("Hair Base Map", 2D) = "white" {}
        _NormalMap ("Normal Map", 2D) = "bump" {}
        _NormalStrength ("Normal Strength", Range(0, 2)) = 0.4
        _HairMatCapMap ("Hair SPA / MatCap", 2D) = "black" {}
        _SpecMap ("Specular / Shine Map", 2D) = "black" {}

        [Header(Toon Shadow)]
        _RampTex ("Ramp Texture", 2D) = "white" {}
        _ShadowColor ("Shadow Color", Color) = (0.42, 0.36, 0.32, 1)
        _ShadowPosition ("Shadow Position", Range(0, 1)) = 0.42
        _ShadowSoftness ("Shadow Softness", Range(0.001, 1)) = 0.1
        _LightBoost ("Light Boost", Range(0.5, 2)) = 1.18

        [Header(Hair Highlight)]
        _MatCapIntensity ("MatCap Intensity", Range(0, 3)) = 0.8
        _SpecularColor ("Specular Color", Color) = (1,1,1,1)
        _SpecularStrength ("Specular Strength", Range(0, 5)) = 0.8
        _AnisoPower ("Anisotropic Power", Range(8, 256)) = 96

        [Header(Outline)]
        _OutlineWidth ("Outline Width", Range(0,0.01)) = 0.001
        _OutlineColor ("Outline Color", Color) = (0.07,0.05,0.04,1)
        [Enum(Off,0,On,1)] _ZWrite ("Z Write", Float) = 1

        [Header(Color Adjust)]
        _Exposure ("Exposure", Range(0.5, 2.0)) = 1.0
        _Contrast ("Contrast", Range(0.0, 2.0)) = 1.0
        _Tint ("Tint", Color) = (1,1,1,1)
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }

        HLSLINCLUDE
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_SGADOWS
            #pragma multi_compile_fragment _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _SHADOWS_SOFT

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap);       SAMPLER(sampler_BaseMap);
            TEXTURE2D(_NormalMap);     SAMPLER(sampler_NormalMap);
            TEXTURE2D(_HairMatCapMap); SAMPLER(sampler_HairMatCapMap);
            TEXTURE2D(_SpecMap);       SAMPLER(sampler_SpecMap);
            TEXTURE2D(_RampTex);       SAMPLER(sampler_RampTex);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                float4 _NormalMap_ST;
                float4 _HairMatCapMap_ST;
                float4 _SpecMap_ST;
                float4 _RampTex_ST;
                float _NormalStrength;
                float4 _ShadowColor;
                float _ShadowPosition;
                float _ShadowSoftness;
                float _LightBoost;
                float _MatCapIntensity;
                float4 _SpecularColor;
                float _SpecularStrength;
                float _AnisoPower;
                float _OutlineWidth;
                float _ZWrite;
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

            float2 MatCapUV(float3 normalWS)
            {
                float3 normalVS = normalize(mul((float3x3)UNITY_MATRIX_V, normalWS));
                return normalVS.xy * 0.5 + 0.5;
            }
        ENDHLSL

        Pass
        {
            Name "UniversalForward"
            Tags { "LightMode"="UniversalForward" }
            Cull Off
            ZWrite [_ZWrite]
            ZTest LEqual
            Stencil
            {
                Ref 64
                WriteMask 64
                Comp Always
                Pass Replace
            }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float2 uv : TEXCOORD1;
                float2 uvNormal : TEXCOORD2;
                float3 normalWS : TEXCOORD3;
                float4 tangentWS : TEXCOORD4;
                float4 shadowCoord : TEXCOORD5;
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                VertexPositionInputs pos = GetVertexPositionInputs(v.positionOS.xyz);
                VertexNormalInputs normal = GetVertexNormalInputs(v.normalOS, v.tangentOS);
                o.positionCS = pos.positionCS;
                o.positionWS = pos.positionWS;
                o.shadowCoord = GetShadowCoord(pos);
                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);
                o.uvNormal = TRANSFORM_TEX(v.uv, _NormalMap);
                o.normalWS = normal.normalWS;
                o.tangentWS = float4(normal.tangentWS, v.tangentOS.w);
                return o;
            }

            float4 frag(Varyings i) : SV_Target
            {
                float4 baseColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv);
                float3 normalTS = UnpackNormal(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, i.uvNormal));
                normalTS.xy *= _NormalStrength;
                normalTS.z = sqrt(saturate(1.0 - dot(normalTS.xy, normalTS.xy)));

                float3 nWS = normalize(i.normalWS);
                float3 tWS = normalize(i.tangentWS.xyz);
                float3 bWS = normalize(cross(nWS, tWS) * i.tangentWS.w);
                float3 N = normalize(mul(normalTS, float3x3(tWS, bWS, nWS)));

                Light light = GetMainLight(i.shadowCoord);
                float3 L = normalize(light.direction);
                float3 V = normalize(_WorldSpaceCameraPos - i.positionWS);
                float3 H = normalize(L + V);

                float halfLambert = saturate(dot(N, L) * 0.5 + 0.5);
                float toonStep = smoothstep(_ShadowPosition - _ShadowSoftness, _ShadowPosition + _ShadowSoftness, halfLambert);
                float3 rampColor = SAMPLE_TEXTURE2D(_RampTex, sampler_RampTex, float2(toonStep, 0.5)).rgb;
                float3 toonLight = lerp(_ShadowColor.rgb, rampColor * _LightBoost, toonStep);
                toonLight *= light.color * light.shadowAttenuation;

                float3 additionalLighting = 0;

                #if defined(_ADDITIONAL_LIGHTS)
                uint additionalLightCount = GetAdditionalLightsCount();

                for (uint lightIndex = 0u; lightIndex < additionalLightCount; lightIndex++)
                {
                    Light additionalLight = GetAdditionalLight(lightIndex, i.positionWS);
                    float additionalNdL = saturate(dot(N, additionalLight.direction));

                    additionalLighting += additionalLight.color * additionalNdL * additionalLight.distanceAttenuation * additionalLight.shadowAttenuation * 0.25;
                }
                #endif

                toonLight += additionalLighting;

                float aniso = pow(saturate(1.0 - abs(dot(normalize(tWS), H))), _AnisoPower);
                float specMask = SAMPLE_TEXTURE2D(_SpecMap, sampler_SpecMap, i.uv).r;
                float3 specular = aniso * specMask * _SpecularColor.rgb * _SpecularStrength;
                float3 matCap = SAMPLE_TEXTURE2D(_HairMatCapMap, sampler_HairMatCapMap, MatCapUV(N)).rgb * _MatCapIntensity;
                float3 finalColor = baseColor.rgb * toonLight + specular + matCap;
                return float4(Adjust(finalColor), baseColor.a);
            }
            ENDHLSL
        }

        Pass
        {
            Name "Outline"
            Tags { "LightMode"="SRPDefaultUnlit" }
            Cull Front
            ZWrite [_ZWrite]
            ZTest LEqual
            Stencil
            {
                Ref 64
                WriteMask 64
                Comp Always
                Pass Replace
            }

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
