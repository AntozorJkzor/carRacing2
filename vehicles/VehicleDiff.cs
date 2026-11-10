using Godot;

/// <summary>
/// Axle torque split helpers. Front axle is always open.
/// rear_diff_type: 0=open, 1=LSD, 2=welded
/// drive_type: 0=FWD, 1=RWD, 2=AWD
/// </summary>
public static class VehicleDiff
{
	public static Vector2 SplitOpen(float totalTorque)
	{
		float half = totalTorque * 0.5f;
		return new Vector2(half, half);
	}

	public static Vector2 SplitLsd(
		float totalTorque,
		float omegaLeft,
		float omegaRight,
		float preloadTorque,
		float powerLock,
		float coastLock)
	{
		float half = totalTorque * 0.5f;
		float avgOmega = (omegaLeft + omegaRight) * 0.5f;
		bool isPower = totalTorque * avgOmega >= 0.0f;
		float lockRatio = isPower ? powerLock : coastLock;
		float deltaW = omegaLeft - omegaRight;
		// Faster wheel gets less torque (transfer toward the slower wheel).
		float tLock = (preloadTorque + Mathf.Abs(totalTorque) * lockRatio) * Mathf.Sign(deltaW);
		float maxTransfer = Mathf.Abs(half) + preloadTorque;
		tLock = Mathf.Clamp(tLock, -maxTransfer, maxTransfer);
		return new Vector2(half - tLock * 0.5f, half + tLock * 0.5f);
	}

	public static Vector2 SplitWelded(
		float totalTorque,
		float omegaLeft,
		float omegaRight,
		float stiffness)
	{
		// Spool / welded: equal torque only. Wheel speeds are hard-synced in
		// CarController after tire integration. The old stiff viscous couple
		// (±k·Δω clamped huge) made a limit cycle — one wheel +κ, other −κ.
		_ = omegaLeft;
		_ = omegaRight;
		_ = stiffness;
		return SplitOpen(totalTorque);
	}

	public static Vector2 SplitRear(
		float totalTorque,
		float omegaLeft,
		float omegaRight,
		int diffType,
		float preloadTorque,
		float powerLock,
		float coastLock,
		float lockedStiffness)
	{
		if (diffType == 0)
			return SplitOpen(totalTorque);
		if (diffType == 2)
			return SplitWelded(totalTorque, omegaLeft, omegaRight, lockedStiffness);
		return SplitLsd(
			totalTorque,
			omegaLeft,
			omegaRight,
			preloadTorque,
			powerLock,
			coastLock);
	}

	public static float[] SplitDriveline(
		float drivelineTorque,
		int driveType,
		float frontBias,
		float fl,
		float fr,
		float rl,
		float rr,
		int rearDiffType,
		float preloadTorque,
		float powerLock,
		float coastLock,
		float lockedStiffness)
	{
		var output = new float[4];

		if (driveType == 0)
		{
			Vector2 front = SplitOpen(drivelineTorque);
			output[0] = front.X;
			output[1] = front.Y;
		}
		else if (driveType == 1)
		{
			Vector2 rear = SplitRear(
				drivelineTorque,
				rl,
				rr,
				rearDiffType,
				preloadTorque,
				powerLock,
				coastLock,
				lockedStiffness);
			output[2] = rear.X;
			output[3] = rear.Y;
		}
		else if (driveType == 2)
		{
			float bias = Mathf.Clamp(frontBias, 0.0f, 1.0f);
			Vector2 frontAwd = SplitOpen(drivelineTorque * bias);
			Vector2 rearAwd = SplitRear(
				drivelineTorque * (1.0f - bias),
				rl,
				rr,
				rearDiffType,
				preloadTorque,
				powerLock,
				coastLock,
				lockedStiffness);
			output[0] = frontAwd.X;
			output[1] = frontAwd.Y;
			output[2] = rearAwd.X;
			output[3] = rearAwd.Y;
		}

		return output;
	}
}
