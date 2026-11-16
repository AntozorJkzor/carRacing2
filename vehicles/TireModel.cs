using Godot;

/// <summary>Pacejka tire forces with bounded sliding grip and combined slip.</summary>
public static class TireModel
{
	public static float MagicFormula(float x, float b, float c, float d, float e)
	{
		float bx = b * x;
		return d * Mathf.Sin(c * Mathf.Atan(bx - e * (bx - Mathf.Atan(bx))));
	}

	public static Vector2 ComputeSlip(
		float longSpeed,
		float latSpeed,
		float wheelOmega,
		float radius,
		float vLow)
	{
		float vRef = Mathf.Max(Mathf.Abs(longSpeed), vLow);
		float kappa = Mathf.Clamp((wheelOmega * radius - longSpeed) / vRef, -3.0f, 3.0f);
		float alpha = Mathf.Atan2(latSpeed, vRef);
		return new Vector2(kappa, alpha);
	}

	public static Vector2 Evaluate(
		float kappa,
		float alpha,
		float fz,
		float mu,
		float bLong,
		float cLong,
		float eLong,
		float bLat,
		float cLat,
		float eLat,
		float gamma,
		float peakKappa,
		float peakAlpha,
		float slideLong,
		float slideLat,
		float combined)
	{
		float load = Mathf.Max(fz, 0.0f);
		if (load < 1.0f)
			return Vector2.Zero;

		const float FzRef = 3200.0f;
		const float LoadSens = 0.18f;
		float loadScale = Mathf.Clamp(1.0f - LoadSens * (load / FzRef - 1.0f), 0.72f, 1.12f);
		float dLong = mu * load * loadScale;
		float dLat = mu * load * loadScale;

		float fxPure = ForceWithSlidingTail(kappa, bLong, cLong, dLong, eLong, peakKappa, slideLong);
		float fyPure = -ForceWithSlidingTail(alpha, bLat, cLat, dLat, eLat, peakAlpha, slideLat);

		// Slip-vector combined slip: the force points against the slip vector, so
		// wheelspin (or a locked wheel) takes lateral force away and the throttle
		// steers the slide. `combined` blends it in over the plain ellipse below;
		// at full strength a spinning rear axle lets go much more abruptly.
		combined = Mathf.Clamp(combined, 0.0f, 1.0f);
		if (combined > 0.001f)
		{
			float peakK = Mathf.Max(peakKappa, 0.03f);
			float tanPeakA = Mathf.Tan(Mathf.Clamp(peakAlpha, 0.03f, 1.2f));
			float sx = kappa / peakK;
			float sy = Mathf.Tan(Mathf.Clamp(alpha, -1.5f, 1.5f)) / tanPeakA;
			float s = Mathf.Sqrt(sx * sx + sy * sy);
			if (s > 0.0001f)
			{
				// Each axis is sampled at the equivalent total slip, so pure
				// longitudinal or pure lateral slip reproduces the curves above.
				float fx0 = ForceWithSlidingTail(s * peakK, bLong, cLong, dLong, eLong, peakKappa, slideLong);
				float fy0 = ForceWithSlidingTail(
					Mathf.Atan(s * tanPeakA), bLat, cLat, dLat, eLat, peakAlpha, slideLat);
				fxPure = Mathf.Lerp(fxPure, sx / s * fx0, combined);
				fyPure = Mathf.Lerp(fyPure, -sy / s * fy0, combined);
			}
		}

		fyPure += dLat * 0.65f * gamma;

		float gx = Mathf.Abs(fxPure) / Mathf.Max(dLong, 1.0f);
		float gy = Mathf.Abs(fyPure) / Mathf.Max(dLat, 1.0f);
		float g = Mathf.Sqrt(gx * gx + gy * gy);
		if (g > 1.0f)
		{
			float inv = 1.0f / g;
			fxPure *= inv;
			fyPure *= inv;
		}
		return new Vector2(fxPure, fyPure);
	}

	private static float ForceWithSlidingTail(float x, float b, float c, float d, float e, float peak, float slide)
	{
		peak = Mathf.Max(peak, 0.03f);
		float absX = Mathf.Abs(x);
		if (absX <= peak)
			return MagicFormula(x, b, c, d, e);

		float peakForce = MagicFormula(peak, b, c, d, e);
		float slideForce = d * Mathf.Clamp(slide, 0.55f, 1.0f);
		float t = 1.0f - Mathf.Exp(-(absX / peak - 1.0f) * 1.35f);
		return Mathf.Sign(x) * Mathf.Lerp(peakForce, slideForce, t);
	}
}
