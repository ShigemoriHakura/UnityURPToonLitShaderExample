// For more information, visit -> https://github.com/ColinLeung-NiloCat/UnityURPToonLitShaderExample

// This file is intented for you to edit and experiment with different lighting equation.
// Add or edit whatever code you want here

// #pragma once is a safe guard best practice in almost every .hlsl (need Unity2020 or up), 
// doing this can make sure your .hlsl's user can include this .hlsl anywhere anytime without producing any multi include conflict
#pragma once

half3 ShadeGI(ToonSurfaceData surfaceData, ToonLightingData lightingData)
{
    // hide 3D feeling by ignoring all detail SH (leaving only the constant SH term)
    // we just want some average envi indirect color only
    half3 averageSH = SampleSH(0);

    // can prevent result becomes completely black if lightprobe was not baked 
    averageSH = max(_IndirectLightMinColor,averageSH);

    // occlusion (maximum 50% darken for indirect to prevent result becomes completely black)
    half indirectOcclusion = lerp(1, surfaceData.occlusion, 0.5);
    return averageSH * indirectOcclusion;
}

half3 CustomFaceShade(ToonSurfaceData surfaceData, ToonLightingData lightingData, Light light, bool isAdditionalLight) {

	half3 N = lightingData.normalWS;
	half3 L = light.direction;
	half3 V = lightingData.viewDirectionWS;
	half3 H = normalize(L + V);
	half3 shadowColor = surfaceData._shadowColor;

	half NoL = dot(N, L);

	// ====== Module Start: Genshin style facial shading ======

	// Get forward and right vectors from rotation matrix;
	float3 ForwardVector = unity_ObjectToWorld._m02_m12_m22;
	float3 RightVector = unity_ObjectToWorld._m00_m10_m20;

	// Normalize light direction in relation to forward and right vectors;
	float FrontLight = dot(normalize(ForwardVector.xz), normalize(L.xz));
	float RightLight = dot(normalize(RightVector.xz), normalize(L.xz));

	RightLight = -(acos(RightLight) / 3.14159265 - 0.5) * 2; // Shadow coverage fix for smoother transition -> https://zhuanlan.zhihu.com/p/279334552;

	// Use r value from the original lightmapileft part in shadow) or flipped lightmap (right part in shadow) depending on normalized light direction;
	float LightMap = RightLight > 0 ? surfaceData._lightMapR.r : surfaceData._lightMapL.r;

	// This controls how we distribute the speed at which we scroll across the lightmap based on normalized light direction;
	// Higher values = faster transitions when facing light and slower transitions when facing away from light, lower values = opposite;
	float dirThreshold = 0.1;

	// If facing light, use right-normalized light direction with dirThreshold. 
	// If facing away from light, use front-normalized light direction with (1 - dirThreshold) and a corresponding translation...
	// ...to ensure smooth transition at 180 degrees (where front-normalized light direction == 0).
	float lightAttenuation_temp = (FrontLight > 0) ?
		min((LightMap > dirThreshold * RightLight), (LightMap > dirThreshold * -RightLight)) :
		min((LightMap > (1 - dirThreshold * 2)* FrontLight - dirThreshold), (LightMap > (1 - dirThreshold * 2)* -FrontLight + dirThreshold));

	// [REDUNDANT] Compensate for translation when facing away from light;
	//lightAttenuation_temp += (FrontLight < -0.9) ? (min((LightMap > 1 * FrontLight), (LightMap > 1 * -FrontLight))) : 0;

	// ====== Module End ======



	float lightAttenuation = surfaceData._useLightMap ? lightAttenuation_temp : 1;



	return lightAttenuation;
}

// Most important part: lighting equation, edit it according to your needs, write whatever you want here, be creative!
// This function will be used by all direct lights (directional/point/spot)
half3 ShadeSingleLight(ToonSurfaceData surfaceData, ToonLightingData lightingData, Light light, bool isAdditionalLight)
{
    half3 N = lightingData.normalWS;
    half3 L = light.direction;

    half NoL = dot(N,L);

    half lightAttenuation = 1;

    // light's distance & angle fade for point light & spot light (see GetAdditionalPerObjectLight(...) in Lighting.hlsl)
    // Lighting.hlsl -> https://github.com/Unity-Technologies/Graphics/blob/master/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl
    half distanceAttenuation = min(4,light.distanceAttenuation); //clamp to prevent light over bright if point/spot light too close to vertex

    // N dot L
    // simplest 1 line cel shade, you can always replace this line by your own method!
    half litOrShadowArea = smoothstep(_CelShadeMidPoint-_CelShadeSoftness,_CelShadeMidPoint+_CelShadeSoftness, NoL);

    // occlusion
    litOrShadowArea *= surfaceData.occlusion;

    // face ignore celshade since it is usually very ugly using NoL method
    litOrShadowArea = _IsFace? lerp(0.5,1,litOrShadowArea) : litOrShadowArea;

    // light's shadow map
    litOrShadowArea *= lerp(1,light.shadowAttenuation,_ReceiveShadowMappingAmount);

    half3 litOrShadowColor = lerp(_ShadowMapColor,1, litOrShadowArea);

    half3 lightAttenuationRGB = litOrShadowColor * distanceAttenuation;

    // saturate() light.color to prevent over bright
    // additional light reduce intensity since it is additive
    return saturate(light.color) * lightAttenuationRGB * (isAdditionalLight ? 0.25 : 1);
}

half3 CalculateRamp(half ndlWrapped)
{
#if defined(TCP2_RAMPTEXT)
	half3 ramp = tex2D(_Ramp, _RampOffset + ((ndlWrapped.xx - 0.5) * _RampScale) + 0.5).rgb;
#elif defined(TCP2_RAMP_BANDS) || defined(TCP2_RAMP_BANDS_CRISP)
	half bands = _RampBands;

	half rampThreshold = _RampThreshold;
	half rampSmooth = _RampSmoothing * 0.5;
	half x = smoothstep(rampThreshold - rampSmooth, rampThreshold + rampSmooth, ndlWrapped);

#if defined(TCP2_RAMP_BANDS_CRISP)
	half bandsSmooth = fwidth(ndlWrapped) * (2.0 + bands);
#else
	half bandsSmooth = _RampBandsSmoothing * 0.5;
#endif
	half3 ramp = saturate((smoothstep(0.5 - bandsSmooth, 0.5 + bandsSmooth, frac(x * bands)) + floor(x * bands)) / bands).xxx;
#else
#if defined(TCP2_RAMP_CRISP)
	half rampSmooth = fwidth(ndlWrapped) * 0.5;
#else
	half rampSmooth = 0.1 * 0.5;
#endif
	half rampThreshold = 0.75;
	half3 ramp = smoothstep(rampThreshold - rampSmooth, rampThreshold + rampSmooth, ndlWrapped).xxx;
#endif
	return ramp;
}

half3 ShadeEmission(ToonSurfaceData surfaceData, ToonLightingData lightingData)
{
    half3 emissionResult = lerp(surfaceData.emission, surfaceData.emission * surfaceData.albedo, _EmissionMulByBaseColor); // optional mul albedo
    return emissionResult;
}

half3 CompositeAllLightResults(half3 indirectResult, half3 mainLightResult, half3 additionalLightSumResult, half3 emissionResult,  half3 faceShadowMask, ToonSurfaceData surfaceData, ToonLightingData lightingData)
{
    // [remember you can write anything here, this is just a simple tutorial method]
    // here we prevent light over bright,
    // while still want to preserve light color's hue
	half3 shadowColor = lerp(1 * surfaceData._shadowColor, 1, faceShadowMask);
    half3 rawLightSum = max(indirectResult * shadowColor, mainLightResult + additionalLightSumResult); // pick the highest between indirect and direct light
    //return surfaceData.albedo * rawLightSum + emissionResult;
    half lightLuminance = Luminance(rawLightSum);

    half3 finalLightMulResult = rawLightSum / max(1,lightLuminance / max(1,log(lightLuminance))); // allow controlled over bright using log
    return surfaceData.albedo * finalLightMulResult + emissionResult;
}

half3 ShadeFaceShadow(ToonSurfaceData surfaceData, ToonLightingData lightingData, Light light)
{
	return CustomFaceShade(surfaceData, lightingData, light, false);
}