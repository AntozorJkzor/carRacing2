using Godot;

/// <summary>Simplified Pacejka Magic Formula + combined-slip friction ellipse.</summary>
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
		float kappa = (wheelOmega * radius - longSpeed) / vRef;
		// Clamp extreme kappa at near-zero speed so combined grip does not collapse.
		kappa = Mathf.Clamp(kappa, -3.0f, 3.0f);
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
		float gamma = 0.0f)
	{
		float load = Mathf.Max(fz, 0.0f);
		if (load < 1.0f)
			return Vector2.Zero;

		// Mild load sensitivity: peak force grows sub-linearly with Fz so weight
		// transfer under throttle doesn't give an unrealistically sticky axle.
		const float FzRef = 3200.0f;
		const float LoadSens = 0.18f;
		float loadScale = 1.0f - LoadSens * (load / FzRef - 1.0f);
		loadScale = Mathf.Clamp(loadScale, 0.72f, 1.12f);
		float dLong = mu * load * loadScale;
		float dLat = mu * load * loadScale;

		float fxPure = MagicFormula(kappa, bLong, cLong, dLong, eLong);
		float fyPure = -MagicFormula(alpha, bLat, cLat, dLat, eLat);

		// Camber consumes the same friction budget as steering and drive torque.
		fyPure += dLat * 0.65f * gamma;

		// One friction ellipse only. A second kappa-based lateral cut made a
		// spinning rear axle snap from grip into an unrecoverable spin.
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
}
