Shader "hair"
{
	Properties
	{
		[Header(Texture)]
		_MainTex ("Texture", 2D) = "white" {}
		_NormalMap("Normal Map", 2D) = "bump" {}
		_EnvSpecMap("Env Specular Map", Cube) = "black" {}
		_HairLineTex("Hair Line Tex", 2D) = "white" {}

		[Header(IBL)]
		_IBLSpecIntensity("IBL Specular Intensity", float) = 1
		_IBLSpecRoughness("IBL Specular Roughness", float) = 1
		
		[Header(Specular)]
		_SpecColor1("Specular Color1", Color) = (0,0,0,0)
		_SpecShiness1("Spec Shininess1", Range(0, 1)) = 0
		_SpecNoise1("Spec Noise1", float) = 1
		_SpecOffset1("Spec Offset", float) = 0

		_SpecColor2("Specular Color2", Color) = (0,0,0,0)
		_SpecShiness2("Spec Shininess2", Range(0, 1)) = 0
		_SpecNoise2("Spec Noise2", float) = 1
		_SpecOffset2("Spec Offset2", float) = 0
			
	}
	SubShader
	{
		Tags { "RenderType"="Opaque" }
		LOD 100

		Pass
		{
			Tags{"LightMode" = "ForwardBase" }
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma multi_compile_fwdbase
			#include "AutoLight.cginc"
			#include "Lighting.cginc"
			#include "UnityCG.cginc"

			struct appdata
			{
				float4 pos : POSITION;
				float2 texcood : TEXCOORD0;
				float3 normal : NORMAL;
				float4 tangent : TANGENT;
			};

			struct v2f
			{
				float2 uv : TEXCOORD0;
				float4 pos : SV_POSITION;
				float3 vertex_world : TEXCOORD1;
				float3 normal_world : TEXCOORD2;
				float3 tangent_dir : TEXCOORD3;
				float3 binormal_dir : TEXCOORD4;
				LIGHTING_COORDS(5, 6)
			};

			sampler2D _MainTex;
			float4 _MainTex_ST;
			sampler2D _HairLineTex;
			float4 _HairLineTex_ST;
			sampler2D _NormalMap;
			float4 _NormalMap_ST;			
			samplerCUBE _EnvSpecMap;
			float4 _EnvSpecMap_HDR;

			float _IBLSpecIntensity;
			float _IBLSpecRoughness;

			float4 _SpecColor1;
			float _SpecShiness1;
			float _SpecNoise1;
			float _SpecOffset1;

			float4 _SpecColor2;
			float _SpecShiness2;
			float _SpecNoise2;
			float _SpecOffset2;
			
			inline float3 ACES_Tonemapping(float3 x)
			{
				float a = 2.51f;
				float b = 0.03f;
				float c = 2.43f;
				float d = 0.59f;
				float e = 0.14f;
				float3 encode_color = saturate((x*(a*x + b)) / (x*(c*x + d) + e));
				return encode_color;
			};

			v2f vert (appdata v)
			{
				v2f o;
				o.pos = UnityObjectToClipPos(v.pos);
				o.uv = v.texcood;
				o.normal_world = normalize(mul(float4(v.normal, 0), unity_WorldToObject).xyz);
				o.vertex_world = mul(unity_ObjectToWorld, v.pos).xyz;
				o.tangent_dir = normalize(mul(unity_ObjectToWorld, float4(v.tangent.xyz, 0)).xyz);
				o.binormal_dir = normalize(cross(o.normal_world, o.tangent_dir)) * v.tangent.w; 
				TRANSFER_VERTEX_TO_FRAGMENT(o);
				return o;
			}
			
			half4 frag (v2f i) : SV_Target
			{
				half light_atten = LIGHT_ATTENUATION(i);

				//vector calculation
				half3 normal_dir = normalize(i.normal_world);
				half3 tangent_dir = normalize(i.tangent_dir);
				half3 binormal_dir = normalize(i.binormal_dir);				
				float3x3 TBN = float3x3(tangent_dir, binormal_dir, normal_dir);
				half3 view_dir = normalize(_WorldSpaceCameraPos.xyz - i.vertex_world);
				half3 normal_world = normal_dir;
				half3 light_dir = normalize(_WorldSpaceLightPos0.xyz - i.vertex_world);

				//sample the texture
				half4 base_color_gamma = tex2D(_MainTex, i.uv);
				half4 albedo_color = pow(base_color_gamma, 2.2);
				half4 normal_color = tex2D(_NormalMap, i.uv);
				half3 base_diffuse_color = albedo_color.rgb;  
				half3 base_spec_color = albedo_color.rgb;  
				half2 hairLine_uv = i.uv * _HairLineTex_ST.xy + _HairLineTex_ST.zw;
				half3 hairLineTex = tex2D(_HairLineTex, hairLine_uv);
				
				//diffuse light
				half3 light_vec = normalize(_WorldSpaceLightPos0.xyz);
				half NdotL = dot(normal_world, light_vec);
				NdotL = max(NdotL, 0);
				half diff_term =  NdotL;
				half half_lambert = (diff_term + 1) * 0.5;
				half3 diffuse_color_term = light_atten * diff_term * _LightColor0.rgb;
				half3 diffuse_color = base_diffuse_color * diffuse_color_term;						
				
				//spec light
				half aniso_noise = hairLineTex.r - 0.5;
				aniso_noise *= 4;
				half3 half_dir = normalize(light_dir + view_dir);
				half NdotH = dot(normal_dir, half_dir);
				half TdotH = dot(half_dir, tangent_dir);

				half NdotV = max(0, dot(view_dir, normal_dir));
				float aniso_atten = saturate(sqrt(max(0, half_lambert / NdotV))) * light_atten;

				//spec1
				half3 spec_color1 = _SpecColor1.rgb + base_spec_color;
				half3 aniso_offset1 = normal_dir * (aniso_noise * _SpecNoise1 + _SpecOffset1);
				half3 binormal_dir1 = normalize(binormal_dir + aniso_offset1);
				half BdotH1 = dot(half_dir, binormal_dir1) / _SpecShiness1;
				half3 spec_term1 = exp(-(TdotH * TdotH + BdotH1 * BdotH1) / (1 + NdotH));

				//spec2 
				half3 spec_color2 = _SpecColor2.rgb + base_spec_color;
				half3 aniso_offset2 = normal_dir * (aniso_noise * _SpecNoise2 + _SpecOffset2);
				half3 binormal_dir2 = normalize(binormal_dir + aniso_offset2);
				half BdotH2 = dot(half_dir, binormal_dir2) / _SpecShiness2;
				half3 spec_term2 = exp(-(TdotH * TdotH + BdotH2 * BdotH2) / (1 + NdotH));
				
				half3 final_spec_color1 = spec_term1 * aniso_atten * spec_color1 * _LightColor0.xyz;
				half3 final_spec_color2 = spec_term2 * aniso_atten * spec_color2 * _LightColor0.xyz;
				half3 spec_color = final_spec_color2 ;//+ final_spec_color1;//+ final_spec_color2;

				//indirect specular
				half3 reflect_dir = reflect(-view_dir, normal_world);
				half roughness = _IBLSpecRoughness;
				roughness = roughness * (1.7 - 0.7 * roughness);
				float mip_level = roughness * 6.0;
				half4 color_cubemap = texCUBElod(_EnvSpecMap, float4(reflect_dir, mip_level));
				half3 env_spec = DecodeHDR(color_cubemap, _EnvSpecMap_HDR);
				env_spec = env_spec * _IBLSpecIntensity * aniso_noise * base_spec_color;
				
				//final color
				half3 final_color = diffuse_color * 0.6 + spec_color * 0.2 + env_spec;
				final_color = ACES_Tonemapping(final_color);
				final_color = pow(final_color, 1/2.2);
				return half4(final_color, 0);
			}
			ENDCG
		}
	}
	Fallback "Diffuse"
}
