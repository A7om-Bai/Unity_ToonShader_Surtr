Shader "Genshin Toon/Genshin Toon_Body" //着色器名称
{
    Properties //属性,相当于一个公共变量区
    {
        [Header(Texture)] //纹理头
        _BaseMap ("Base Map", 2D) = "white" {} //基础贴图
        _NormalMap ("Normal Map", 2D) = "bump" {} //法线贴图
        _NormalStrength ("Normal Strength", Range(0, 2)) = 1 //法线强度
        _RampTex ("RampTex", 2D) = "white" {} //渐变贴图
        [Toggle(_USE_RAMP_SHADOW)] _USE_RAMP_SHADOW ("Use Ramp Shadow", Range (0,1)) = 1 //使用渐变阴影开关
        _ShadowRampWidth ("Shadow Ramp Width", Float) = 1 //阴影边缘宽度
        _ShadowPosition ("Shadow Position", Float) = 0.55 //阴影位置
        _ShadowSoftness ("Shadow Softness", Float) = 0.5 //阴影柔和度
        _Exposure ("Exposure", Range(0.5, 2.0)) = 1.0
        _Contrast ("Contrast", Range(0.0, 2.0)) = 1.0
        _Tint ("Tint", Color) = (1,1,1,1)

    }
    SubShader //子着色器
    {
        Tags //标签
        {
            "RenderType"="Opaque" //渲染类型为不透明
            "RenderPipeline" = "UniversalRenderPipeline" //渲染管线为通用渲染管线
        }

        HLSLINCLUDE //HLSL包含
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

            CBUFFER_START (UnityPerMaterial) // 材质常量缓冲区开始
                sampler2D _BaseMap; // 基础贴图采样器
                sampler2D _NormalMap;
                float _NormalStrength;
                sampler2D _RampTex; // 渐变贴图采样器
                float _ShadowRampWidth; // 阴影边缘宽度
                float _ShadowPosition; // 阴影位置
                float _ShadowSoftness; // 阴影柔和度
                float _Exposure;
                float _Contrast;
                float4 _Tint;

            CBUFFER_END // 常量缓冲区结束
        ENDHLSL //结束HLSL

        Pass //通道
        {
            Name "UniversalForward" //通道名称

            Tags //标签
            {
                "LightMode" = "UniversalForward" //光照模式为通用前向
            }

            HLSLPROGRAM //HLSL程序开始

            #pragma vertex vert //声明顶点着色器函数
            #pragma fragment frag //声明片元着色器函数

            struct appdata //顶点着色器输入参数
            {
                float4 vertex : POSITION; //顶点位置
                float2 uv : TEXCOORD0; //顶点纹理坐标
                float3 normal : NORMAL; //顶点法线
                float4 tangent : TANGENT; //顶点切线
                float4 color : COLOR; //顶点颜色
            };

            struct v2f //片元着色器输入参数
            {
                float4 pos : SV_POSITION; //裁剪空间位置
                float2 uv : TEXCOORD0; //纹理坐标
                float3 normalWS : TEXCOORD1; //世界空间法线
                float4 tangentWS : TEXCOORD2; //世界空间切线
                half4 color : COLOR; //顶点颜色
            };

            v2f vert(appdata v) //顶点着色器主函数
            {
                // 顶点着色器逻辑（如果需要，可以在这里添加）
                v2f o; // 输出变量
                VertexPositionInputs VertexInput = GetVertexPositionInputs (v.vertex.xyz); // 获取顶点位置
                VertexNormalInputs NormalInput = GetVertexNormalInputs(v.normal, v.tangent); // 获取顶点法线和切线
                o.normalWS = NormalInput.normalWS; // 传递世界空间法线
                o.tangentWS = float4(NormalInput.tangentWS, v.tangent.w); // 传递世界空间切线


                // o.normalWS = NormalInput.normalWS; // 传递世界空间法线
                o.pos = VertexInput.positionCS; // 设置裁剪空间位置
                o.uv = v.uv; // 传递纹理坐标
                o.color = v.color; // 传递顶点颜色
                return o; // 返回裁剪空间位置
            }

            half4 frag(v2f i) : SV_Target //片段着色器主函数
            {
                // 片段着色器逻辑（如果需要，可以在这里添加）
                Light light = GetMainLight(); // 获取主光源
                half3 nWS = normalize(i.normalWS); // 归一化世界空间法线
                half4 vertexColor = i.color; // 获取顶点颜色

                // 采样切线空间法线（UnpackNormal 会把 0~1 转成 -1~1，并处理法线格式）
                half3 normalTS = UnpackNormal(tex2D(_NormalMap, i.uv));
                // 强度缩放：压低 x/y，重新归一化
                normalTS.xy *= _NormalStrength;
                normalTS.z = sqrt(saturate(1.0h - dot(normalTS.xy, normalTS.xy)));

                // 构造 TBN
                half3 tWS = normalize(i.tangentWS.xyz);
                half3 bWS = normalize(cross(nWS, tWS) * i.tangentWS.w);

                // 切线空间法线 -> 世界空间法线
                half3 N = normalize(
                    normalTS.x * tWS +
                    normalTS.y * bWS +
                    normalTS.z * nWS
                );


                half3 L = normalize(light.direction); // 计算光照方向
                half NoL = dot(N,L); // 计算法线与光照方向的点积

                half4 baseColor = tex2D(_BaseMap, i.uv); // 采样基础贴图颜色

                half lambert = NoL; //Lambert光照（-1到1）
                half halflambert = lambert * 0.5 + 0.5; //Halflambert光照（0到1）
                halflambert *= pow(halflambert,2); //增强Halflambert效果
                half lambertstep = smoothstep(0.01, 0.4, halflambert); //平滑过渡函数
                half shadowFactor = lerp(0, halflambert, lambertstep); //计算阴影因子)

                half isShadowArea = step(halflambert, _ShadowPosition); //判断是否在阴影区域
                half shadowDepth = saturate((_ShadowPosition - halflambert) / _ShadowRampWidth); //计算阴影深度
                shadowDepth = pow(shadowDepth, _ShadowSoftness); //应用阴影柔和度
                shadowDepth = min(shadowDepth, 1.0); //确保阴影深度不超过1)
                half rampWidthFactor = vertexColor.g * 2 * _ShadowRampWidth; //根据顶点颜色的绿色通道调整阴影边缘宽度
                half shadowPosition = (_ShadowPosition - shadowFactor) / _ShadowPosition; //计算阴影位置

                // 应用渐变阴影
                half rampU = 1 - saturate (shadowDepth / rampWidthFactor); // 计算渐变贴图的U坐标
                half rampV = 0.5; // 固定V坐标为0.5
                half rampUV = half2(rampU, rampV); // 组合UV坐标
                half3 rampColor = tex2D(_RampTex, rampUV).rgb; // 采样渐变贴图颜色

                // Merge Color
                #ifdef _USE_RAMP_SHADOW //如果启用渐变阴影
                    half3 finalcolor = baseColor.rgb * rampColor * (isShadowArea ? 1 : 1.2); // 设置最终颜色为基础贴图颜色乘以渐变贴图颜色，在非阴影区域稍微提亮
                #else
                    half3 finalcolor = baseColor.rgb * halflambert; // 设置最终颜色为基础贴图颜色
                #endif

                // ---- Color Grading (shared) ----
                half3 c = finalcolor;
                // 1) tint（用于对齐脸/身体色相/饱和）
                c *= _Tint.rgb;
                // 2) exposure（整体提亮/压暗）
                c *= _Exposure;
                // 3) contrast（以 0.5 为中心拉对比，避免提亮后发灰）
                c = (c - 0.5h) * _Contrast + 0.5h;
                // 防止溢出
                c = saturate(c);
                finalcolor = c;


                return float4(finalcolor, 1);
            }

            ENDHLSL //HLSL结束
        }

        Pass
        {
            Name "ShadowCaster" //阴影投射通道名称
            Tags //标签
            {
                "LightMode" = "ShadowCaster" //光照模式为阴影投射
            }

            ZWrite On //开启深度写入
            ZTest LEqual //深度测试模式为小于等于
            ColorMask 0  //不写入颜色缓冲区
            Cull Off //关闭面剔除

            HLSLPROGRAM //HLSL程序开始
            #pragma multi_compile_instancing // 启用GPU实例化编译
            #pragma multi_compile _ DOTS_INSTANCING_ON // 启用DOTS实例化编译
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW // 启用点光源阴影

            #pragma vertex ShadowVS // 使用内置的阴影投射顶点着色器
            #pragma fragment ShadowFS // 使用内置的阴影投射片段着色器

            float3 _LightDirection; //光照方向
            float3 _LightPosition; //光照位置

            struct appdata //顶点着色器输入参数
            {
                float4 positionOS : POSITION; //顶点位置
                float3 normalOS : NORMAL; //顶点法线
            };

            struct v2f //片元着色器输入参数
            {
                float4 positionCS : SV_POSITION; //裁剪空间位置
            };

            // 将阴影的世界空间顶点位置转换为适合阴影投射的裁剪空间位置
            float4 GetShadowPositionHClip(appdata v)
            {
                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz); // 将本地空间顶点坐标转换为世界空间顶点坐标
                float3 normalWS = TransformObjectToWorldNormal(v.normalOS); // 将本地空间法线转换为世界空间法线

                #if _CASTING_PUNCTUAL_LIGHT_SHADOW // 点光源
                    float3 lightDirectionWS = normalize(_LightPosition - positionWS); // 计算光源方向
                #else // 平行光
                    float3 lightDirectionWS = _LightDirection; // 使用预定义的光源方向
                #endif

                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS)); // 应用阴影偏移

                // 根据平台的Z缓冲区方向调整Z值
                #if UNITY_REVERSED_Z // 反转Z缓冲区
                    positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE); // 限制Z值在近裁剪平面以下
                #else // 正向Z缓冲区
                    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE); // 限制Z值在远裁剪平面以上
                #endif

                return positionCS; // 返回裁剪空间顶点坐标
            }

            v2f ShadowVS (appdata v) //阴影投射顶点着色器主函数
            {
                v2f o; // 输出变量
                o.positionCS = GetShadowPositionHClip(v); // 获取阴影裁剪空间位置
                return o; // 返回裁剪空间位置
            }

            float4 ShadowFS(v2f i) : SV_Target //阴影投射片段着色器主函数
            {
                return 0; // 返回0表示完全遮挡
            }
            ENDHLSL //HLSL结束
        }
    }
}
