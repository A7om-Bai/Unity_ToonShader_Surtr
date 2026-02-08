Shader "Genshin Toon/test"
{
    Properties
    {
        _BaseMap ("Base Map", 2D) = "white" {}
        _Darken ("Darken", Range(0,1)) = 1
        _Contrast ("Contrast", Range(0,2)) = 1
    }
    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalRenderPipeline"
        }

        HLSLINCLUDE
        #pragma multi_compile _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _LIGHT_LAYERS
            #pragma multi_compile_fragment _LIGHT_COOKIES
            #pragma multi_compile_fragment _SCREEN_SPACE_OCCLUSION
            #pragma multi_compile_fragment _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _SHADOWS_SOFT
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            CBUFFER_START (UnityPerMaterial)
                sampler2D _BaseMap;
                float _Darken;
                float _Contrast;
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

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f 
            {
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            v2f vert (appdata v)
            {
                v2f o;
                VertexPositionInputs VertexInput = GetVertexPositionInputs(v.vertex.xyz);
                o.pos = VertexInput.positionCS;
                o.uv = v.uv;
                return o;
            }

            half4 frag(v2f i ) : SV_Target
            {
                half4 baseColor = tex2D(_BaseMap, i.uv);
                half3 contrastedColor = ((baseColor.rgb - 0.5) * _Contrast) + 0.5;
                return half4(contrastedColor * _Darken, 1.0);
            }

            ENDHLSL
        }
    }

}
