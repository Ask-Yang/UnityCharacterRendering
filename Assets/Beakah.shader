Shader "Beakah"
{
	Properties
	{	
		[Header(Texture)]
		_MainTex ("Texture", 2D) = "white" {}
		_NormalMap("Normal Map", 2D) = "bump" {}
		_EnvSpecMap("Env Specular Map", Cube) = "black" {}
		_CompMask("Comp Mask", 2D) = "white" {}
		_SkinLUT("Skin LUT", 2D) = "white" {}

		[Header(Direct Specular)]
		_SpecAtten("Specular Attenuation", float) = 1
		_SpecIntensity("Specular Intensity", float) = 1 
		
		[Header(Env Diffuse)]
		_EnvDiffuseIntensity("Env Diffuse Intensity", float) = 1

		[Header(Env IBL Specular)]
		_IBLSpecIntensity("IBL Specular Intensity", float) = 1

		[Header(Effect Weight)]
		_MetalIntensity("Mental Intensity", Range(-1,1)) = 0
		_RoughnessIntensity("Roughness Intensity", Range(-1,1)) = 0
		_SSSTexWeight("SSS Tex Weight", Range(0, 1)) = 0.5
		_NormalIntensity("Normal Intensity", float) = 1 

		[HideInInspector]custom_SHAr("Custom SHAr", Vector) = (0, 0, 0, 0)
		[HideInInspector]custom_SHAg("Custom SHAg", Vector) = (0, 0, 0, 0)
		[HideInInspector]custom_SHAb("Custom SHAb", Vector) = (0, 0, 0, 0)
		[HideInInspector]custom_SHBr("Custom SHBr", Vector) = (0, 0, 0, 0)
		[HideInInspector]custom_SHBg("Custom SHBg", Vector) = (0, 0, 0, 0)
		[HideInInspector]custom_SHBb("Custom SHBb", Vector) = (0, 0, 0, 0)
		[HideInInspector]custom_SHC("Custom SHC", Vector) = (0, 0, 0, 1)
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
			sampler2D _NormalMap;
			samplerCUBE _EnvSpecMap;
			sampler2D _CompMask;
			sampler2D _SkinLUT;

			float4 _NormalMap_ST;
			float4 _MainTex_ST;
			float4 _EnvSpecMap_HDR;

			float _NormalIntensity;
			float _SpecAtten;
			float _SpecIntensity;
			float _EnvDiffuseIntensity;
			float _IBLSpecIntensity;

			float _SSSTexWeight;
			float _RoughnessIntensity;
			float _MetalIntensity;
			//SH
			half4 custom_SHAr;
			half4 custom_SHAg;
			half4 custom_SHAb;
			half4 custom_SHBr;
			half4 custom_SHBg;
			half4 custom_SHBb;
			half4 custom_SHC;

			inline float3 custom_sh(float3 normal_dir)
			{
				float4 normalForSH = float4(normal_dir, 1.0);
				//SHEvalLinearL0L1
				half3 x;
				x.r = dot(custom_SHAr, normalForSH);
				x.g = dot(custom_SHAg, normalForSH);
				x.b = dot(custom_SHAb, normalForSH);

				//SHEvalLinearL2
				half3 x1, x2;
				// 4 of the quadratic (L2) polynomials
				half4 vB = normalForSH.xyzz * normalForSH.yzzx;
				x1.r = dot(custom_SHBr, vB);
				x1.g = dot(custom_SHBg, vB);
				x1.b = dot(custom_SHBb, vB);

				// Final (5th) quadratic (L2) polynomial
				half vC = normalForSH.x*normalForSH.x - normalForSH.y*normalForSH.y;
				x2 = custom_SHC.rgb * vC;

				float3 sh = max(float3(0.0, 0.0, 0.0), (x + x1 + x2));
				sh = pow(sh, 1.0 / 2.2);
				return sh;
			}

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
				o.uv = TRANSFORM_TEX(v.texcood, _MainTex);
				o.normal_world = normalize(mul(float4(v.normal, 0), unity_WorldToObject).xyz);
				o.vertex_world = mul(unity_ObjectToWorld, v.pos).xyz;
				o.tangent_dir = normalize(mul(unity_ObjectToWorld, float4(v.tangent.xyz, 0)).xyz);
				o.binormal_dir = normalize(cross(o.normal_world, o.tangent_dir)) * v.tangent.w; 
				TRANSFER_VERTEX_TO_FRAGMENT(o);
				return o;
			}

			half3 normal_world_calu(half4 normal_color, half3 tangent_dir, half3 binormal_dir, half3 normal_dir)
			{
				half3 normal_data = UnpackNormal(normal_color);
				normal_data.xy = normal_data.xy  * _NormalIntensity ;
				half3 normal_world = tangent_dir * normal_data.x
					+ binormal_dir * normal_data.y
					+ normal_dir * normal_data.z;
				return normal_world;
			}
			
			half3 diffuse_light_calu(half NdotL, half light_atten, half3 base_diffuse_color)
			{
				half diff_term =  NdotL;
				half3 diffuse_color = light_atten * diff_term * _LightColor0.rgb * base_diffuse_color;
				return diffuse_color;
			}

			half3 sss_diffuse_calu(half light_atten, half NdotL, half3 base_diffuse_color)
			{
				half diff_term = NdotL;
				half2 uv_lut = half2(light_atten * diff_term, 1);
				half3 lut_color_gamma = tex2D(_SkinLUT, uv_lut);
				half3 lut_color = pow(lut_color_gamma, 2.2);
				half3 sss_diffuse = diff_term * _LightColor0.rgb * base_diffuse_color ; 
				sss_diffuse = _SSSTexWeight * lut_color * sss_diffuse
								+ (1 - _SSSTexWeight) * sss_diffuse;
				return sss_diffuse;
			}

			half3 spec_color_calu(half NdotL, half RdotV, half roughness, half light_atten, half3 base_spec_color)
			{
				half half_lambert = NdotL*0.5 + 0.5;
				half smoothness = 1 - roughness;
				half shininess0 = lerp(1, 1.8, smoothness);
				half spec_term = pow(RdotV, shininess0 * _SpecAtten) * shininess0 * _SpecIntensity;
				half3 spec_color = light_atten * spec_term * _LightColor0.rgb  * base_spec_color * half_lambert;
				return spec_color;
			}

			half3 SH_light_calu(half NdotL, half3 base_diffuse_color, half3 normal_dir)
			{
				half diff_term =  NdotL;
				half half_lambert = (diff_term + 1) * 0.5;
				float3 env_diffuse = custom_sh(normal_dir) * _EnvDiffuseIntensity * base_diffuse_color;
				return env_diffuse;
			}

			half3 IBL_light_calu(half NdotL, half3 view_dir, half3 normal_world, half roughness, half3 base_spec_color)
			{
				half half_lambert = NdotL/2;
				half3 reflect_dir_view = reflect(-view_dir, normal_world);
				roughness = roughness * (1.7 - 0.7 * roughness);
				float mip_level = roughness * 6.0;
				half4 color_cubemap = texCUBElod(_EnvSpecMap, float4(reflect_dir_view, mip_level));
				half3 env_spec = DecodeHDR(color_cubemap, _EnvSpecMap_HDR);
				env_spec = env_spec * base_spec_color * _IBLSpecIntensity ;
				return env_spec;
			}

			half4 frag (v2f i) : SV_Target
			{
				half light_atten = LIGHT_ATTENUATION(i);

				//sample the texture
				half normal_u = saturate(i.uv.x);
				half normal_v = saturate(i.uv.y);
				half2 normal_uv = half2(normal_u, normal_v);
				half4 base_color_gamma = tex2D(_MainTex, i.uv);
				half4 albedo_color = pow(base_color_gamma, 2.2);
				half4 normal_color = tex2D(_NormalMap, normal_uv);
				half4 comp_mask = tex2D(_CompMask, i.uv);

				//vector calculation
				half3 normal_dir = normalize(i.normal_world);
				half3 tangent_dir = normalize(i.tangent_dir);
				half3 binormal_dir = normalize(i.binormal_dir);				
				float3x3 TBN = float3x3(tangent_dir, binormal_dir, normal_dir);
				half3 view_dir = normalize(_WorldSpaceCameraPos.xyz - i.vertex_world);
				half3 light_vec = normalize(_WorldSpaceLightPos0.xyz);
				half3 normal_world = normal_world_calu(normal_color, tangent_dir, binormal_dir, normal_dir);
				half3 reflect_dir = reflect(-light_vec, normal_world);

				//calu base parameter
				half roughness = comp_mask.r + _RoughnessIntensity;
				half metal = comp_mask.g + _MetalIntensity;
				half skin_area = 1 - comp_mask.b;
				half3 base_diffuse_color = albedo_color.rgb * (1 - metal);  
				half3 base_spec_color = lerp(0.04, albedo_color.rgb, metal);  
				half NdotL = max(0, dot(normal_world, light_vec));
				half RdotV = max(0, dot(reflect_dir, view_dir));

				//direct diffuse 
				half3 diffuse_color = diffuse_light_calu(NdotL, light_atten, base_diffuse_color);
				half3 sss_diffuse = sss_diffuse_calu(light_atten, NdotL, base_diffuse_color);	//sss detail
				diffuse_color = lerp(diffuse_color, sss_diffuse, skin_area);

				//direct specular
				half3 spec_color = spec_color_calu(NdotL, RdotV, roughness, light_atten, base_spec_color);

				//indirect diffuse 
				half3 env_diffuse = SH_light_calu(NdotL, base_diffuse_color, normal_dir);
				//env_diffuse *= lerp(1, 0.9, skin_area);

				//indirect specular
				half3 env_spec = IBL_light_calu(NdotL, view_dir, normal_world, roughness, base_spec_color);

				//final color
				half3 final_color = diffuse_color + spec_color + env_diffuse + env_spec;
				final_color = ACES_Tonemapping(final_color);
				final_color = pow(final_color, 1/2.2);
				return half4(final_color, 0);
			}
			ENDCG
		}
	}
	Fallback "Diffuse"
}
