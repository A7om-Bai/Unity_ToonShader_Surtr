Shader "Toon Shader/Toon_VectorBody"
{
    Properties
    {
        [Header(Texture)]
        _BaseMap ("Base Map", 2D) = "white" {}
        _NormalMap ("Normal Map", 2D) = "bump" {}
        _NormalStrength ("Normal Strength", Range(0, 2)) = 1
        _RMOMap ("RMO Map (R Roughness G Metallic B Occlusion)", 2D) = "white" {}
        _OcclusionStrength ("Occlusion Strength", Range(0, 1)) = 0.75

        [Header(Toon Shadow)]
        _RampTex ("Ramp Texture", 2D) = "white" {}
        _ShadowColor ("Shadow Color", Color) = (0.55, 0.50, 0.48, 1)
        _ShadowPosition ("Shadow Position", Range(0, 1)) = 0.45
        _ShadowSoftness ("Shadow Softness", Range(0.001, 1)) = 0.12
        _LightBoost ("Light Boost", Range(0.5, 2)) = 1.15

        [Header(Specular)]
        _SpecularColor ("Specular Color", Color) = (1,1,1,1)
        _SpecularStrength ("Specular Strength", Range(0, 5)) = 0.65
        _MetallicStrength ("Metallic Strength", Range(0, 2)) = 0
        _SmoothnessStrength ("Smoothness Strength", Range(0, 2)) = 1

        [Header(MatCap)]
        _MatCapMap ("MatCap / SPA Map", 2D) = "black" {}
        _MatCapColor ("MatCap Color", Color) = (1,1,1,1)
        _MatCapIntensity ("MatCap Intensity", Range(0, 3)) = 0

        [Header(RimLight)]
        _RimColor ("Rim Color", Color) = (1,1,1,1)
        _RimPower ("Rim Power", Range(0.5,8)) = 3
        _RimIntensity ("Rim Intensity", Range(0,5)) = 0.35

        [Header(Outline)]
        _OutlineWidth ("Outline Width", Range(0,0.01)) = 0.001
        _OutlineColor ("Outline Color", Color) = (0.08,0.06,0.05,1)

        [Header(Color Adjust)]
        _Exposure ("Exposure", Range(0.5, 2.0)) = 1.0
        _Contrast ("Contrast", Range(0.0, 2.0)) = 1.0
        _Tint ("Tint", Color) = (1,1,1,1)
    }

    SubShader
    {
        Tags
        {
            "RenderType"="Opaque"
            "RenderPipeline" = "UniversalPipeline"
        }

        HLSLINCLUDE
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _SHADOWS_SOFT

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap);     SAMPLER(sampler_BaseMap);
            TEXTURE2D(_NormalMap);   SAMPLER(sampler_NormalMap);
            TEXTURE2D(_RMOMap);      SAMPLER(sampler_RMOMap);
            TEXTURE2D(_RampTex);     SAMPLER(sampler_RampTex);
            TEXTURE2D(_MatCapMap);   SAMPLER(sampler_MatCapMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                float4 _NormalMap_ST;
                float4 _RMOMap_ST;
                float4 _RampTex_ST;
                float4 _MatCapMap_ST;
                float _NormalStrength;
                float _OcclusionStrength;
                float4 _ShadowColor;
                float _ShadowPosition;
                float _ShadowSoftness;
                float _LightBoost;
                float4 _SpecularColor;
                float _SpecularStrength;
                float _MetallicStrength;
                float _SmoothnessStrength;
                float4 _MatCapColor;
                float _MatCapIntensity;
                float4 _RimColor;
                float _RimPower;
                float _RimIntensity;
                float _OutlineWidth;
                float4 _OutlineColor;
                float _Exposure;
                float _Contrast;
                float4 _Tint;
            CBUFFER_END

            float3 ApplyColorAdjust(float3 color)
            {
                color *= _Tint.rgb;
                color *= _Exposure;
                color = (color - 0.5) * _Contrast + 0.5;
                return saturate(color);
            }

            float2 GetMatCapUV(float3 normalWS)
            {
                float3 normalVS = normalize(mul((float3x3)UNITY_MATRIX_V, normalWS));
                return normalVS.xy * 0.5 + 0.5;
            }
        ENDHLSL

        Pass
        {
            Name "UniversalForward"
            Tags { "LightMode" = "UniversalForward" }
            Cull Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float4 color : COLOR;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float2 uvBase : TEXCOORD1;
                float2 uvNormal : TEXCOORD2;
                float2 uvRMO : TEXCOORD3;
                float3 normalWS : TEXCOORD4;
                float4 tangentWS : TEXCOORD5;
                float4 shadowCoord : TEXCOORD6;
                float4 color : COLOR;
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                VertexPositionInputs pos = GetVertexPositionInputs(v.positionOS.xyz);
                VertexNormalInputs normal = GetVertexNormalInputs(v.normalOS, v.tangentOS);
                o.positionCS = pos.positionCS;
                o.positionWS = pos.positionWS;
                o.shadowCoord = GetShadowCoord(pos);
                o.normalWS = normal.normalWS;
                o.tangentWS = float4(normal.tangentWS, v.tangentOS.w);
                o.uvBase = TRANSFORM_TEX(v.uv, _BaseMap);
                o.uvNormal = TRANSFORM_TEX(v.uv, _NormalMap);
                o.uvRMO = TRANSFORM_TEX(v.uv, _RMOMap);
                o.color = v.color;
                return o;
            }

            float4 frag(Varyings i) : SV_Target
            {
                float4 baseColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uvBase);
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

                #ifdef _ADDITIONAL_LIGHTS
                    uint additionalLightsCount = GetAdditionalLightsCount();

                    for (uint lightIndex = 0u; lightIndex < additionalLightsCount; lightIndex++)
                    {
                        Light additionalLight = GetAdditionalLight(lightIndex, i.positionWS);
                        float additionalNdL = saturate(dot(N, additionalLight.direction));

                        additionalLighting += additionalLight.color * additionalNdL * additionalLight.shadowAttenuation * additionalLight.distanceAttenuation * 0.25;
                    }
                #endif

                toonLight += additionalLighting;

                float4 rmo = SAMPLE_TEXTURE2D(_RMOMap, sampler_RMOMap, i.uvRMO);
                float roughness = saturate(rmo.r);
                float metallic = saturate(rmo.g * _MetallicStrength);
                float occlusion = lerp(1.0, rmo.b, _OcclusionStrength);
                float smoothness = saturate((1.0 - roughness) * _SmoothnessStrength);

                float specPower = lerp(24.0, 256.0, smoothness);
                float specMask = lerp(0.25, 1.0, metallic);
                float3 specular = _SpecularColor.rgb * _SpecularStrength * specMask * pow(saturate(dot(N, H)), specPower);

                float rim = pow(1.0 - saturate(dot(N, V)), _RimPower) * saturate(dot(N, L));
                float3 rimLight = rim * _RimColor.rgb * _RimIntensity;

                float3 matCap = SAMPLE_TEXTURE2D(_MatCapMap, sampler_MatCapMap, GetMatCapUV(N)).rgb;
                matCap *= _MatCapColor.rgb * _MatCapIntensity;

                float3 finalColor = baseColor.rgb * toonLight * occlusion + specular + rimLight + matCap;
                return float4(ApplyColorAdjust(finalColor), baseColor.a);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
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
    }
}
