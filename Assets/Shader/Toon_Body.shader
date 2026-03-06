Shader "Toon Shader/Toon_Body"
{
    Properties
    {
        [Header(Texture)]
        _BaseMap ("Base Map", 2D) = "white" {}
        _NormalMap ("Normal Map", 2D) = "bump" {}
        _NormalStrength ("Normal Strength", Range(0, 2)) = 1
        _RampTex ("RampTex", 2D) = "white" {}

        [Header(RimLight)]
        _RimColor ("Rim Color", Color) = (1,1,1,1)
        _RimPower ("Rim Power", Range(0.5,8)) = 3
        _RimIntensity ("Rim Intensity", Range(0,5)) = 1

        [Toggle(_USE_RAMP_SHADOW)] _USE_RAMP_SHADOW ("Use Ramp Shadow", Range(0,1)) = 1

        [Header(ShadowRamp)]
        _ShadowRampWidth ("Shadow Ramp Width", Float) = 1
        _ShadowPosition ("Shadow Position", Float) = 0.55
        _ShadowSoftness ("Shadow Softness", Float) = 0.5

        [Header(Specular)]
        _SpecularStrength ("Specular Strength", Range(0, 5)) = 1.0

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

            #pragma shader_feature_local _USE_RAMP_SHADOW // 渐变阴影功能开关

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl" // 核心库
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl" // 光照库

            CBUFFER_START (UnityPerMaterial)
                sampler2D _BaseMap;
                sampler2D _NormalMap;
                float _NormalStrength;
                float _SpecularStrength;
                sampler2D _RampTex;
                float _ShadowRampWidth;
                float _ShadowPosition;
                float _ShadowSoftness;
                float _Exposure;
                float _Contrast;
                float4 _Tint;
                float4 _RimColor;
                float _RimPower;
                float _RimIntensity;
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

            Cull Off

            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            struct attributes
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : NORMAL;
                float4 tangent : TANGENT;
                float4 color : COLOR;
            };

            struct varryings
            {
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float4 tangentWS : TEXCOORD2;
                float3 positionWS : TEXCOORD3;
                half4 color : COLOR;
            };

            varryings vert(attributes v)
            {
                varryings o;
                VertexPositionInputs VertexInput = GetVertexPositionInputs (v.vertex.xyz);
                VertexNormalInputs NormalInput = GetVertexNormalInputs(v.normal, v.tangent);
                o.positionWS = VertexInput.positionWS;
                o.normalWS = NormalInput.normalWS;
                o.tangentWS = float4(NormalInput.tangentWS, v.tangent.w);
                
                o.pos = VertexInput.positionCS;
                o.uv = v.uv;
                o.color = v.color;
                return o;
            }

            half4 frag(varryings i) : SV_Target
            {
                Light light = GetMainLight();
                half3 nWS = normalize(i.normalWS);
                half4 vertexColor = i.color;

                // 采样切线空间法线（UnpackNormal把 0~1 转成 -1~1，并处理法线格式）
                half3 normalTS = UnpackNormal(tex2D(_NormalMap, i.uv));
                normalTS.xy *= _NormalStrength;
                normalTS.z = sqrt(saturate(1.0h - dot(normalTS.xy, normalTS.xy)));

                // 构造 TBN
                half3 tWS = normalize(i.tangentWS.xyz);
                half3 bWS = normalize(cross(nWS, tWS) * i.tangentWS.w);

                half3 N = normalize(
                    normalTS.x * tWS +
                    normalTS.y * bWS +
                    normalTS.z * nWS
                );

                half3 V = normalize(_WorldSpaceCameraPos - i.positionWS);

                half3 L = normalize(light.direction);

                half NoL = saturate(dot(N,L));
                half NoV = saturate(dot(N,V));

                float3 H = normalize(L + V);

                float3 specular = light.color * pow(saturate(dot(N, H)), 64) * _SpecularStrength; // 简单的高光计算

                half4 baseColor = tex2D(_BaseMap, i.uv);

                half lambert = NoL;
                half halflambert = lambert * 0.5 + 0.5;
                halflambert *= pow(halflambert,2);
                half lambertstep = smoothstep(0.01, 0.4, halflambert);
                half shadowFactor = lerp(0, halflambert, lambertstep);

                half isShadowArea = step(halflambert, _ShadowPosition);
                half shadowDepth = saturate((_ShadowPosition - halflambert) / _ShadowRampWidth);
                shadowDepth = pow(shadowDepth, _ShadowSoftness);
                shadowDepth = min(shadowDepth, 1.0);
                half rampWidthFactor = vertexColor.g * 2 * _ShadowRampWidth;
                half shadowPosition = (_ShadowPosition - shadowFactor) / _ShadowPosition;

                // 应用渐变阴影
                half rampU = 1 - saturate (shadowDepth / rampWidthFactor);
                half rampV = 0.5;
                half rampUV = half2(rampU, rampV);
                half3 rampColor = tex2D(_RampTex, rampUV).rgb;

                float rim = 1 - saturate(dot(N,V));

                rim = pow(rim, _RimPower);
                rim *= NoL;

                float3 rimLight = rim * _RimColor.rgb * _RimIntensity;

                #ifdef _USE_RAMP_SHADOW
                    half3 finalcolor = baseColor.rgb * rampColor * (isShadowArea ? 1 : 1.2) + specular + rimLight; // 设置最终颜色为基础贴图颜色乘以渐变贴图颜色，在非阴影区域稍微提亮
                #else
                    half3 finalcolor = baseColor.rgb * halflambert + specular + rimLight;
                #endif

                half3 c = finalcolor;
                c *= _Tint.rgb;
                c *= _Exposure;
                c = (c - 0.5h) * _Contrast + 0.5h;
                // 防止溢出
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

            #pragma vertex ShadowVS
            #pragma fragment ShadowFS

            float3 _LightDirection;
            float3 _LightPosition;

            struct attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
            };

            struct varryings
            {
                float4 positionCS : SV_POSITION;
            };

            // 将阴影的世界空间顶点位置转换为适合阴影投射的裁剪空间位置
            float4 GetShadowPositionHClip(attributes v)
            {
                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(v.normalOS);

                #if _CASTING_PUNCTUAL_LIGHT_SHADOW // 点光源
                    float3 lightDirectionWS = normalize(_LightPosition - positionWS);
                #else // 平行光
                    float3 lightDirectionWS = _LightDirection;
                #endif

                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS)); // 应用阴影偏移

                #if UNITY_REVERSED_Z // 反转Z缓冲区
                    positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE); // 限制Z值在近裁剪平面以下
                #else // 正向Z缓冲区
                    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE); // 限制Z值在远裁剪平面以上
                #endif

                return positionCS;
            }

            varryings ShadowVS (attributes v)
            {
                varryings o;
                o.positionCS = GetShadowPositionHClip(v);
                return o;
            }

            float4 ShadowFS(varryings i) : SV_Target
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

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
            };

            Varyings vert (Attributes v)
            {
                Varyings o;

                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(v.normalOS);

                positionWS += normalWS * _OutlineWidth;

                o.positionCS = TransformWorldToHClip(positionWS);

                return o;
            }

            half4 frag (Varyings i) : SV_Target
            {
                return _OutlineColor;
            }

            ENDHLSL
        }
    }
}
