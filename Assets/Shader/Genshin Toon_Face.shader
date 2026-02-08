Shader "Genshin Toon/Genshin Toon_Face" //着色器名称
{
    Properties //属性,相当于一个公共变量区
    {
        [Header(Texture)] //纹理头
        _BaseMap ("Base Map", 2D) = "white" {} //基础贴图
        [Header(Shadow Options)]
        [Toggle (_USE_SDF_SHADOW)] _USE_SDF_SHADOW ("Use SDF Shadow", Range(0,1)) = 1 //使用SDF阴影开关
        _SDF ("SDF", 2D) = "white" {} //距离场纹理
        _ShadowMask ("Shadow Mask", 2D) = "white" {} //阴影遮罩贴图
        _ShadowColor ("Shadow Color", Color) = (1,0.87,0.87,1) //阴影颜色
        [Header(Head Direction)]
        [HideInInspector]_HeadForward ("Head Forward", Vector) = (0,0,1,0) //头部前方向量
        [HideInInspector]_HeadRight ("Head Right", Vector) = (1,0,0,0) //头部右方向量
        [HideInInspector]_HeadUp ("Head Up", Vector) = (0,1,0,0) //头部上方向量
        _Exposure ("Exposure", Range(0.5, 2.0)) = 1.0 //曝光
        _Contrast ("Contrast", Range(0.0, 2.0)) = 1.0 //对比度
        _Tint ("Tint", Color) = (1,1,1,1) //色调

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

            #pragma shader_feature_local _USE_SDF_SHADOW // 使用SDF阴影特性

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl" // 核心库
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl" // 光照库

            CBUFFER_START (UnityPerMaterial) // 材质常量缓冲区开始
                sampler2D _BaseMap; // 基础贴图采样器
                sampler2D _SDF; // SDF采样器
                sampler2D _ShadowMask; // 阴影遮罩采样器
                float3 _HeadForward; // 头部前方向量
                float3 _HeadRight; //头部右方向量
                float3 _HeadUp; // 头部上方向量
                float4 _ShadowColor; // 阴影颜色
                float _Exposure; // 曝光
                float _Contrast; // 对比度
                float4 _Tint; // 色调
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

            struct attributions //顶点着色器输入参数
            {
                float4 vertex : POSITION; //顶点位置
                float2 uv : TEXCOORD0; //顶点纹理坐标
                float3 normal : NORMAL; //顶点法线
            };

            struct varyings //片元着色器输入参数
            {
                float4 posCS : SV_POSITION; //裁剪空间位置
                float2 uv : TEXCOORD0; //纹理坐标
                float3 normalWS : TEXCOORD1; //世界空间法线
            };

            varyings vert(attributions v) //顶点着色器主函数
            {
                // 顶点着色器逻辑（如果需要，可以在这里添加）
                varyings o; // 输出变量
                VertexPositionInputs VertexInput = GetVertexPositionInputs (v.vertex.xyz); // 获取顶点位置
                VertexNormalInputs NormalInput = GetVertexNormalInputs (v.normal); // 获取顶点法线
                o.normalWS = NormalInput.normalWS; // 传递世界空间法线
                o.posCS = VertexInput.positionCS; // 设置裁剪空间位置
                o.uv = v.uv; // 传递纹理坐标
                return o; // 返回裁剪空间位置
            }

            half4 frag(varyings i) : SV_Target //片段着色器主函数
            {
                // 片段着色器逻辑（如果需要，可以在这里添加）
                Light light = GetMainLight(); // 获取主光源
                half3 N = normalize(i.normalWS); // 计算法线
                half3 L = normalize(light.direction); // 计算光照方向
                half NoL = dot(N,L); // 计算法线与光照方向的点积
                // half3 headUpDir = normalize(_HeadUp); // 头部上方向量归一化
                // half3 headForwardDir = normalize(_HeadForward); // 头部前方向量归一化
                // half3 headRightDir = normalize(_HeadRight); // 头部右方向量归一化
                half3 headRightDir   = normalize(TransformObjectToWorldDir(half3(1,0,0)));
                half3 headUpDir      = normalize(TransformObjectToWorldDir(half3(0,1,0)));
                half3 headForwardDir = normalize(TransformObjectToWorldDir(half3(0,0,1)));


                half4 baseColor = tex2D(_BaseMap, i.uv); // 采样基础贴图颜色
                half4 shadowMask = tex2D(_ShadowMask, i.uv); // 采样阴影遮罩贴图颜色

                half lambert = NoL; //Lambert光照（-1到1）
                half halflambert = lambert * 0.5 + 0.5; //Halflambert光照（0到1）
                halflambert *= pow(halflambert,1); //增强Halflambert效果

                half3 LpU = dot(L, headUpDir) / pow(length(headUpDir), 2) * headUpDir; // 计算光源方向在面部上方的投影
                half3 LpHeadHorizon = normalize(L- LpU); // 光照方向在头部水平面上的投影
                half value = acos(dot(LpHeadHorizon, headRightDir)) / 3.141592654; // 计算光照方向与面部右方的夹角
                half exposeRight = step(value, 0.5); // 判断光照是来自右侧还是左侧
                half valueR = pow(1 - value * 2, 3); // 右侧阴影强度
                half valueL = pow(value * 2 - 1, 3); // 左侧阴影强度
                half mixValue = lerp(valueL, valueR, exposeRight); // 混合阴影强度
                half sdfLeft = tex2D(_SDF, half2(1 - i.uv.x, i.uv.y)).r; // 左侧距离场
                half sdfRight = tex2D(_SDF, i.uv).r; // 右侧距离场
                half mixSdf = lerp(sdfRight, sdfLeft, exposeRight); // 采样SDF纹理
                // half sdf = step(mixValue, mixSdf); // 计算硬边界阴影
                float sdfSoft = 0.05; // 可做成属性
                half sdf = smoothstep(mixValue - sdfSoft, mixValue + sdfSoft, mixSdf); // 计算软边界阴影

                sdf = lerp(0, sdf, step(0, dot(LpHeadHorizon, headForwardDir))); // 计算右侧阴影
                sdf *= shadowMask.g; // 使用G通道控制阴影强度
                sdf = lerp(sdf, 1, shadowMask.a); // 使用A通道作为阴影遮罩

                // Merge Color
                #ifdef _USE_SDF_SHADOW // 如果使用SDF阴影
                    half3 finalcolor = lerp(_ShadowColor.rgb * baseColor.rgb, baseColor.rgb, sdf); // 设置最终颜色为阴影颜色和基础贴图颜色的混合
                    // half3 shadowCol = lerp(_ShadowColor.rgb, 1.0.xxx, 0.3);
                    // half3 finalcolor = lerp(shadowCol * baseColor.rgb, baseColor.rgb, sdf);

                #else
                    half3 finalcolor = baseColor.rgb * halflambert; // 设置最终颜色为基础贴图颜色
                #endif

                half frontBoost = saturate(dot(L, headForwardDir)); // 计算面部正面光照增强
                finalcolor *= lerp(1.0, 1.1, frontBoost); // 增强面部正面光照

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

        Pass //阴影投射通道
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

            struct attributions //顶点着色器输入参数
            {
                float4 positionOS : POSITION; //顶点位置
                float3 normalOS : NORMAL; //顶点法线
            };

            struct varyings //片元着色器输入参数
            {
                float4 positionCS : SV_POSITION; //裁剪空间位置
            };

            // 将阴影的世界空间顶点位置转换为适合阴影投射的裁剪空间位置
            float4 GetShadowPositionHClip(attributions v)
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

            varyings ShadowVS (attributions v) //阴影投射顶点着色器主函数
            {
                varyings o; // 输出变量
                o.positionCS = GetShadowPositionHClip(v); // 获取阴影裁剪空间位置
                return o; // 返回裁剪空间位置
            }

            float4 ShadowFS(varyings i) : SV_Target //阴影投射片段着色器主函数
            {
                return 0; // 返回0表示完全遮挡
            }
            ENDHLSL //HLSL结束
        }
    }
}
