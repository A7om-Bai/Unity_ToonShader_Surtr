Shader "Toon Shader/Toon_VectorFace"
{
    Properties
    {
        [Header(Texture)]
        _BaseMap ("Face Base Map", 2D) = "white" {}
        _SkinRampTex ("Skin / Toon Ramp", 2D) = "white" {}
        _EyeBlendMap ("Eye Blend Overlay", 2D) = "black" {}
        _EyeBlendIntensity ("Eye Blend Intensity", Range(0, 2)) = 0
        _ExtraMap ("Extra Overlay Atlas", 2D) = "black" {}
        _ExtraIntensity ("Extra Intensity", Range(0, 2)) = 0
        _AlphaClip ("Alpha Clip", Range(0, 1)) = 0
        _Cutoff ("Alpha Cutoff", Range(0, 1)) = 0.5
        [Toggle] _EyeThroughBlocker ("Block Through-Hair Eyes", Range(0, 1)) = 0

        [Header(SDF Shadow Optional)]
        [Toggle(_USE_SDF_SHADOW)] _USE_SDF_SHADOW ("Use SDF Shadow", Range(0,1)) = 0
        _SDF ("SDF", 2D) = "white" {}
        _ShadowMask ("Shadow Mask", 2D) = "white" {}
        _ShadowColor ("Shadow Color", Color) = (0.78,0.56,0.52,1)

        [Header(Head Direction)]
        [HideInInspector]_HeadForward ("Head Forward", Vector) = (0,0,1,0)
        [HideInInspector]_HeadRight ("Head Right", Vector) = (1,0,0,0)
        [HideInInspector]_HeadUp ("Head Up", Vector) = (0,1,0,0)

        [Header(Lighting)]
        _ShadowPosition ("Shadow Position", Range(0, 1)) = 0.48
        _ShadowSoftness ("Shadow Softness", Range(0.001, 1)) = 0.18
        _LightBoost ("Light Boost", Range(0.5, 2)) = 1.08

        [Header(Outline)]
        _OutlineWidth ("Outline Width", Range(0,0.01)) = 0.001
        _OutlineColor ("Outline Color", Color) = (0.09,0.05,0.05,1)

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
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_SGADOWS
            #pragma multi_compile_fragment _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _SHADOWS_SOFT
            #pragma shader_feature_local _USE_SDF_SHADOW

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap);      SAMPLER(sampler_BaseMap);
            TEXTURE2D(_SkinRampTex);  SAMPLER(sampler_SkinRampTex);
            TEXTURE2D(_EyeBlendMap);  SAMPLER(sampler_EyeBlendMap);
            TEXTURE2D(_ExtraMap);     SAMPLER(sampler_ExtraMap);
            TEXTURE2D(_SDF);          SAMPLER(sampler_SDF);
            TEXTURE2D(_ShadowMask);   SAMPLER(sampler_ShadowMask);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                float4 _SkinRampTex_ST;
                float4 _EyeBlendMap_ST;
                float4 _ExtraMap_ST;
                float _EyeBlendIntensity;
                float _ExtraIntensity;
                float _AlphaClip;
                float _Cutoff;
                float _EyeThroughBlocker;
                float3 _HeadForward;
                float3 _HeadRight;
                float3 _HeadUp;
                float4 _ShadowColor;
                float _ShadowPosition;
                float _ShadowSoftness;
                float _LightBoost;
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

            float3 AlphaBlend(float3 baseColor, float4 overlay, float intensity)
            {
                return lerp(baseColor, overlay.rgb, saturate(overlay.a * intensity));
            }
        ENDHLSL

        Pass
        {
            Name "UniversalForward"
            Tags { "LightMode" = "UniversalForward" }

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
                float3 positionWS : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float2 uv : TEXCOORD2;
                float4 shadowCoord : TEXCOORD3;
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                VertexPositionInputs pos = GetVertexPositionInputs(v.positionOS.xyz);
                VertexNormalInputs normal = GetVertexNormalInputs(v.normalOS);
                o.positionCS = pos.positionCS;
                o.positionWS = pos.positionWS;
                o.shadowCoord = GetShadowCoord(pos);
                o.normalWS = normal.normalWS;
                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);
                return o;
            }

            float4 frag(Varyings i) : SV_Target
            {
                float4 baseColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv);
                if (_AlphaClip > 0.5)
                    clip(baseColor.a - _Cutoff);

                float4 eyeBlend = SAMPLE_TEXTURE2D(_EyeBlendMap, sampler_EyeBlendMap, TRANSFORM_TEX(i.uv, _EyeBlendMap));
                float4 extra = SAMPLE_TEXTURE2D(_ExtraMap, sampler_ExtraMap, TRANSFORM_TEX(i.uv, _ExtraMap));

                Light light = GetMainLight(i.shadowCoord);
                float3 N = normalize(i.normalWS);
                float3 L = normalize(light.direction);
                float halfLambert = saturate(dot(N, L) * 0.5 + 0.5);
                float toonStep = smoothstep(_ShadowPosition - _ShadowSoftness, _ShadowPosition + _ShadowSoftness, halfLambert);

                float3 rampColor = SAMPLE_TEXTURE2D(_SkinRampTex, sampler_SkinRampTex, float2(toonStep, 0.5)).rgb;
                float3 litColor = lerp(_ShadowColor.rgb, rampColor * _LightBoost, toonStep);
                litColor *= light.color * light.shadowAttenuation;

                //计算附加光源
                float3 additionalLighting = 0;

                #ifdef _ADDITIONAL_LIGHTS
                uint additionalLightsCount = GetAdditionalLightsCount();

                for(uint lightIndex = 0u; lightIndex < additionalLightsCount; lightIndex++)
                {
                    Light additionalLight = GetAdditionalLight(lightIndex, i.positionWS);
                    float additionalNdL = saturate(dot(N, additionalLight.direction));
                    additionalLighting += additionalLight.color * additionalNdL * additionalLight.shadowAttenuation * additionalLight.distanceAttenuation * 0.25;
                }
                #endif

                litColor += additionalLighting;

                float3 color = baseColor.rgb * litColor;

                //应用SDF贴图
                #ifdef _USE_SDF_SHADOW
                    float3 headRightDir = normalize(TransformObjectToWorldDir(_HeadRight));
                    float3 headUpDir = normalize(TransformObjectToWorldDir(_HeadUp));
                    float3 headForwardDir = normalize(TransformObjectToWorldDir(_HeadForward));
                    float3 lightUp = dot(L, headUpDir) / pow(length(headUpDir), 2) * headUpDir;
                    float3 lightFlat = L - lightUp;
                    float flatLength = max(length(lightFlat), 0.0001);
                    float3 lightHorizon = lightFlat / flatLength;
                    float rightDot = dot(lightHorizon, headRightDir);
                    float frontDot = dot(lightHorizon, headForwardDir);
                    float value = acos(clamp(abs(rightDot), 0.0, 1.0)) / PI;
                    float exposeRight = step(0.0, rightDot);
                    float mixValue = pow(saturate(1.0 - value * 2.0), 3.0);
                    float sdfRight = SAMPLE_TEXTURE2D(_SDF, sampler_SDF, i.uv).r;
                    float sdfLeft = SAMPLE_TEXTURE2D(_SDF, sampler_SDF, float2(1 - i.uv.x, i.uv.y)).r;
                    float sdf = smoothstep(mixValue - 0.1, mixValue + 0.1, lerp(sdfRight, sdfLeft, exposeRight));
                    float4 shadowMask = SAMPLE_TEXTURE2D(_ShadowMask, sampler_ShadowMask, i.uv);
                    float frontFade = smoothstep(-_ShadowSoftness, _ShadowSoftness, frontDot);
                    sdf *= frontFade;
                    sdf *= shadowMask.g;
                    sdf = lerp(sdf, 1, shadowMask.a);
                    color = lerp(_ShadowColor.rgb * baseColor.rgb, baseColor.rgb, sdf);
                #endif

                color = AlphaBlend(color, eyeBlend, _EyeBlendIntensity);
                color = AlphaBlend(color, extra, _ExtraIntensity);
                return float4(ApplyColorAdjust(color), baseColor.a);
            }
            ENDHLSL
        }

        Pass
        {
            Name "EyeThroughBlocker"
            Tags { "LightMode"="SRPDefaultUnlit" }
            Cull Off
            ZWrite Off
            ZTest Always
            ColorMask 0
            Stencil
            {
                Ref 128
                WriteMask 128
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
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                VertexPositionInputs pos = GetVertexPositionInputs(v.positionOS.xyz);
                o.positionCS = pos.positionCS;
                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);
                return o;
            }

            float4 frag(Varyings i) : SV_Target
            {
                clip(_EyeThroughBlocker - 0.5);
                float4 baseColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv);
                if (_AlphaClip > 0.5)
                    clip(baseColor.a - _Cutoff);
                return 0;
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
