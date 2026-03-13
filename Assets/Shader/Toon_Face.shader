Shader "Toon Shader/Toon_Face"
{
    Properties
    {
        [Header(Texture)]
        _BaseMap ("Base Map", 2D) = "white" {}

        [Header(Shadow Options)]
        [Toggle (_USE_SDF_SHADOW)] _USE_SDF_SHADOW ("Use SDF Shadow", Range(0,1)) = 1
        _SDF ("SDF", 2D) = "white" {}
        _ShadowMask ("Shadow Mask", 2D) = "white" {}
        _ShadowColor ("Shadow Color", Color) = (1,0.87,0.87,1)

        [Header(Head Direction)]
        [HideInInspector]_HeadForward ("Head Forward", Vector) = (0,0,1,0)
        [HideInInspector]_HeadRight ("Head Right", Vector) = (1,0,0,0)
        [HideInInspector]_HeadUp ("Head Up", Vector) = (0,1,0,0)

        [Header(Outline)]
        _OutlineWidth ("Outline Width", Range(0,0.002)) = 0.001
        _OutlineColor ("Outline Color", Color) = (0,0,0,1)

        [Header(PostProcessing)]
        _Exposure ("Exposure", Range(0.5, 2.0)) = 1.0
        _Contrast ("Contrast", Range(0.0, 2.0)) = 1.0
        _Tint ("Tint", Color) = (1,1,1,1)
    }

    SubShader
    {
        Tags
        {
            "RenderType"="Opaque"
            "RenderPipeline" = "UniversalRenderPipeline"
        }

        HLSLINCLUDE
            #pragma multi_compile _MAIN_LIGHT_SHADOWS // 主光源阴影
            #pragma multi_compile _MAIN_LIGHT_SHADOWS_CASCADE // 主光源阴影级联
            #pragma multi_compile _MAIN_LIGHT_SHADOWS_SCREEN // 主光源阴影屏幕空间

            #pragma multi_compile_fragment _LIGHT_LAYERS // 光照层
            #pragma multi_compile_fragment _LIGHT_COOKIES // 光照饼干
            #pragma multi_compile_fragment _SCREEN_SPACE_OCCLUSION // 屏幕空间遮挡
            #pragma multi_compile_fragment _ADDITIONAL_LIGHT_SHADOWS // 额外光源阴影
            #pragma multi_compile_fragment _SHADOWS_SOFT // 阴影软化

            #pragma shader_feature_local _USE_SDF_SHADOW // 使用SDF阴影特性

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            CBUFFER_START (UnityPerMaterial)
                sampler2D _BaseMap;
                sampler2D _SDF;
                sampler2D _ShadowMask;
                float3 _HeadForward;
                float3 _HeadRight;
                float3 _HeadUp;
                float4 _ShadowColor;
                float _Exposure;
                float _Contrast;
                float4 _Tint;
                float _OutlineWidth;
                float4 _OutlineColor;
            CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "UniversalForward"

            Tags
            {
                "LightMode" = "UniversalForward"
            }

            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            struct attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float3 normalOS : NORMAL;
            };

            struct varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
            };

            varyings vert(attributes v)
            {
                varyings o;
                VertexPositionInputs VertexInput = GetVertexPositionInputs (v.positionOS.xyz);
                VertexNormalInputs NormalInput = GetVertexNormalInputs (v.normalOS);
                o.positionCS = VertexInput.positionCS;
                o.normalWS = NormalInput.normalWS;
                o.uv = v.uv;
                return o;
            }

            half4 frag(varyings i) : SV_Target
            {
                Light light = GetMainLight();
                half3 N = normalize(i.normalWS);
                half3 L = normalize(light.direction);
                half NoL = dot(N,L);

                half3 headRightDir   = normalize(TransformObjectToWorldDir(half3(1,0,0)));
                half3 headUpDir      = normalize(TransformObjectToWorldDir(half3(0,1,0)));
                half3 headForwardDir = normalize(TransformObjectToWorldDir(half3(0,0,1)));

                half4 baseColor = tex2D(_BaseMap, i.uv);
                half4 shadowMask = tex2D(_ShadowMask, i.uv);

                half lambert = NoL;
                half halflambert = lambert * 0.5 + 0.5;
                halflambert *= pow(halflambert,1);

                //计算光照在头部坐标系中的投影，判断光源相对于头部的方向，生成阴影边界
                //去除垂直分量，得到光 L 在 Up 方向的分量
                half3 LpU = dot(L, headUpDir) / pow(length(headUpDir), 2) * headUpDir;
                //得到光在水平方向的分量，作为头部水平面上的光照方向
                half3 LpHeadHorizon = normalize(L- LpU);

                //计算光与头右方向夹角
                half value = acos(dot(LpHeadHorizon, headRightDir)) / 3.141592654;

                //判断左右
                half exposeRight = step(value, 0.5);

                //计算阴影位置，生成阴影边界
                half valueR = pow(1 - value * 2, 3);
                half valueL = pow(value * 2 - 1, 3);
                half mixValue = lerp(valueL, valueR, exposeRight);

                //左右脸分开采样
                half sdfLeft = tex2D(_SDF, half2(1 - i.uv.x, i.uv.y)).r;
                half sdfRight = tex2D(_SDF, i.uv).r;

                //混合
                half mixSdf = lerp(sdfRight, sdfLeft, exposeRight);

                //柔和阴影边界
                float sdfSoft = 0.05;
                half sdf = smoothstep(mixValue - sdfSoft, mixValue + sdfSoft, mixSdf);

                // 只有当头部朝向光源时才考虑SDF阴影，否则直接全亮，避免背面出现不自然的阴影
                sdf = lerp(0, sdf, step(0, dot(LpHeadHorizon, headForwardDir)));
                sdf *= shadowMask.g;

                //利用shadowMask的alpha通道控制SDF阴影的强度，避免过于突兀的边界（眼睛、鼻子、嘴巴）
                sdf = lerp(sdf, 1, shadowMask.a);

                // 如果启用SDF阴影，则使用SDF阴影颜色，否则使用传统的半兰伯特阴影
                #ifdef _USE_SDF_SHADOW
                    half3 finalcolor = lerp(_ShadowColor.rgb * baseColor.rgb, baseColor.rgb, sdf);
                #else
                    half3 finalcolor = baseColor.rgb * halflambert;
                #endif

                //正面补光，根据头部朝向光源的程度提升亮度，避免正面过暗（尤其是当光源位于侧面时），且限制在1.1倍
                half frontBoost = saturate(dot(L, headForwardDir));
                finalcolor *= lerp(1.0, 1.1, frontBoost);

                half3 c = finalcolor;
                c *= _Tint.rgb;
                c *= _Exposure;
                c = (c - 0.5h) * _Contrast + 0.5h; //contrast（以 0.5 为中心拉对比，避免提亮后发灰）
                c = saturate(c);
                finalcolor = c;

                return float4(finalcolor, 1);
            }

            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags
            {
                "LightMode" = "ShadowCaster"
            }

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Off

            HLSLPROGRAM
            #pragma multi_compile_instancing // 启用GPU实例化编译
            #pragma multi_compile _ DOTS_INSTANCING_ON // 启用DOTS实例化编译
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW // 启用点光源阴影

            #pragma vertex ShadowVS // 使用内置的阴影投射顶点着色器
            #pragma fragment ShadowFS // 使用内置的阴影投射片段着色器

            float3 _LightDirection; //光照方向
            float3 _LightPosition; //光照位置

            struct attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
            };

            struct varyings
            {
                float4 positionCS : SV_POSITION;
            };

            float4 GetShadowPositionHClip(attributes v)
            {
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

                return positionCS;
            }

            varyings ShadowVS (attributes v)
            {
                varyings o;
                o.positionCS = GetShadowPositionHClip(v);
                return o;
            }

            float4 ShadowFS(varyings i) : SV_Target
            {
                return 0;
            }
            ENDHLSL
        }

        Pass
        {
            Name "Outline"
            Tags
            {
                "LightMode"="SRPDefaultUnlit"
            }

            Cull Front
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 normalWS : TEXCOORD0;
            };

            Varyings vert (Attributes v)
            {
                Varyings o;

                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(v.normalOS);

                positionWS += normalWS * _OutlineWidth;

                o.positionCS = TransformWorldToHClip(positionWS);
                o.normalWS = normalWS;

                return o;
            }

            half4 frag (Varyings i) : SV_Target
            {
                Light light = GetMainLight();
                float3 N = normalize(i.normalWS);
                float3 L = normalize(light.direction);
                float NoL = saturate(dot(N, L));
                float Power = pow(NoL, 0.05);
                float3 color = _OutlineColor.rgb * (0.5 + Power * 0.5);
                return float4 (color,1);
            }

            ENDHLSL
        }
    }
}
