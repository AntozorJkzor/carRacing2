using Godot;
using Godot.Collections;

/// <summary>
/// Snapshot of CarSetup values for the physics hot-path.
/// Refresh once per physics frame (or when setup changes) — never Get/Call inside substeps.
/// </summary>
public sealed class CarSetupCache
{
	public float Mass = 1200f;
	public Vector3 CenterOfMassOffset = new(0f, -0.32f, 0.06f);

	public float IdleRpm = 800f;
	public float MaxRpm = 7000f;
	public float MaxPowerHp = 241f;
	public float EngineInertia = 0.25f;
	public float EngineCoastFrictionScale = 1.65f;
	public float RevLimiterCutHighFrac = 0.98f;
	public float RevLimiterCutLowFrac = 0.91f;
	public float PeakTorqueNm = 300f;
	public Curve TorqueCurve;

	public float[] GearRatios = { 3.67f, 2.10f, 1.36f, 1.00f, 0.82f };
	public float ReverseRatio = 3.53f;
	public float FinalDrive = 3.9f;
	public int DriveType; // 0 FWD, 1 RWD, 2 AWD
	public float ShiftTime = 0.15f;
	public float ClutchMaxTorque = 1000f;
	public float ClutchEngageTime = 0.12f;
	public float AwdFrontBias = 0.4f;
	public int RearDiffType = 1;
	public float DiffPreload = 80f;
	public float DiffPowerLock = 0.35f;
	public float DiffCoastLock = 0.15f;
	public float LockedDiffStiffness = 800f;
	/// <summary>Brake-based eLSD on the driven axle(s): 0 = off, 1 = street, 2 = aggressive.</summary>
	public float BrakeElsd = 0f;

	public float WheelInertia = 0.85f;
	public float FrontWheelRadius = 0.321f;
	public float RearWheelRadius = 0.321f;
	public float FrontWheelWidth = 0.205f;
	public float RearWheelWidth = 0.205f;
	public Array WheelPositions = new();

	public float FrontRestLength = 0.4f;
	public float RearRestLength = 0.4f;
	public float FrontTravel = 0.2f;
	public float RearTravel = 0.2f;
	public float FrontStiffness = 35000f;
	public float RearStiffness = 35000f;
	public float FrontDampingCompression = 3500f;
	public float RearDampingCompression = 3500f;
	public float FrontDampingRebound = 4200f;
	public float RearDampingRebound = 4200f;
	public float FrontAntiRoll = 5600f;
	public float RearAntiRoll = 2600f;

	public float TireMuFront = 1.7f;
	public float TireMuRear = 1.55f;
	public float RearCamberDeg = -1f;
	public float TireVLow = 0.5f;
	public float PacejkaBLong = 10f;
	public float PacejkaCLong = 1.55f;
	public float PacejkaELong = 0.2f;
	public float PacejkaBLat = 5.5f;
	public float PacejkaCLat = 1.2f;
	public float PacejkaELat = 0.25f;
	public float TireRelaxationLongitudinal = 0.3f;
	public float TireRelaxationLateral = 0.45f;
	public float RollingResistance = 0.015f;
	public float MinLoadFraction;

	public float BrakeForce = 12000f;
	public float HandbrakeForce = 22000f;
	public float HandbrakeLatGrip = 0.15f;
	public float BrakeBiasFront = 0.65f;

	public float DragCoefficient = 0.32f;
	public float DownforceCoefficient = 0.95f;
	public float FrontalArea = 2.1f;
	public float AirDensity = 1.225f;

	public float MaxSteerAngle = 32f;
	public float SteerSpeed = 2.4f;
	public float FrontCasterDeg = 4f;
	public float SteerCurveMaxKmh = 140f;
	public Curve SteerAngleCurve;
	public float SteerSpeedRef = 22f;
	public float SteerHighSpeedFactor = 0.35f;
	public float SteerInputGamma = 1.35f;
	public float CounterSteerSlipDeg = 7f;
	public float CounterSteerLockMax = 0.58f;
	public float CounterSteerRateMult = 1.85f;
	public float CounterSteerRecoverRate = 0.32f;
	public float SteerLockSmooth = 6f;

	public float ThrottleRiseRate = 2f;
	public float ThrottleFallRate = 6f;
	public float DriftAssist = 1f;

	public float FwdLatPriority;
	public float FwdSlipAngleStartDeg = 5f;
	public float FwdCounterSteerScale = 0.55f;
	public float FwdRecoverBleed = 1.4f;

	public int PhysicsSubsteps = 4;
	public bool AutoHoldGearInDrift = true;
	/// <summary>Arcade handling helper: 0 = pure sim, 1 = strong arcade grip/nose control.</summary>
	public float ArcadeAssist = 0.4f;
	public float NosPowerAdd = 0f;
	public int TurboLevel = 0;
	public bool TractionControl;
	public float TcSlipRatio = 0.35f;
	public float TcGain = 1.4f;
	public float TcMinScale = 0.55f;

	public int ForwardGearCount => GearRatios?.Length ?? 0;

	public void RefreshFrom(Resource setup)
	{
		if (setup == null)
			return;

		Mass = Gf(setup, "mass", Mass);
		CenterOfMassOffset = Gv3(setup, "center_of_mass_offset", CenterOfMassOffset);

		IdleRpm = Gf(setup, "idle_rpm", IdleRpm);
		MaxRpm = Gf(setup, "max_rpm", MaxRpm);
		EngineInertia = Gf(setup, "engine_inertia", EngineInertia);
		EngineCoastFrictionScale = Gf(setup, "engine_coast_friction_scale", EngineCoastFrictionScale);
		RevLimiterCutHighFrac = Gf(setup, "rev_limiter_cut_high_frac", RevLimiterCutHighFrac);
		RevLimiterCutLowFrac = Gf(setup, "rev_limiter_cut_low_frac", RevLimiterCutLowFrac);
		TorqueCurve = setup.Get("torque_curve").AsGodotObject() as Curve;

		var gearsVar = setup.Get("gear_ratios");
		if (gearsVar.VariantType != Variant.Type.Nil)
		{
			var arr = gearsVar.AsGodotArray();
			GearRatios = new float[arr.Count];
			for (int i = 0; i < arr.Count; i++)
				GearRatios[i] = arr[i].AsSingle();
		}
		ReverseRatio = Gf(setup, "reverse_ratio", ReverseRatio);
		FinalDrive = Gf(setup, "final_drive", FinalDrive);
		DriveType = Gi(setup, "drive_type", DriveType);
		ShiftTime = Gf(setup, "shift_time", ShiftTime);
		ClutchMaxTorque = Gf(setup, "clutch_max_torque", ClutchMaxTorque);
		ClutchEngageTime = Gf(setup, "clutch_engage_time", ClutchEngageTime);
		AwdFrontBias = Gf(setup, "awd_front_bias", AwdFrontBias);
		RearDiffType = Gi(setup, "rear_diff_type", RearDiffType);
		DiffPreload = Gf(setup, "diff_preload", DiffPreload);
		DiffPowerLock = Gf(setup, "diff_power_lock", DiffPowerLock);
		DiffCoastLock = Gf(setup, "diff_coast_lock", DiffCoastLock);
		LockedDiffStiffness = Gf(setup, "locked_diff_stiffness", LockedDiffStiffness);
		BrakeElsd = Gf(setup, "brake_elsd", BrakeElsd);

		WheelInertia = Gf(setup, "wheel_inertia", WheelInertia);
		FrontWheelRadius = Gf(setup, "front_wheel_radius", FrontWheelRadius);
		RearWheelRadius = Gf(setup, "rear_wheel_radius", RearWheelRadius);
		FrontWheelWidth = Gf(setup, "front_wheel_width", FrontWheelWidth);
		RearWheelWidth = Gf(setup, "rear_wheel_width", RearWheelWidth);
		var wp = setup.Get("wheel_positions");
		if (wp.VariantType != Variant.Type.Nil)
			WheelPositions = wp.AsGodotArray();

		FrontRestLength = Gf(setup, "front_rest_length", FrontRestLength);
		RearRestLength = Gf(setup, "rear_rest_length", RearRestLength);
		FrontTravel = Gf(setup, "front_travel", FrontTravel);
		RearTravel = Gf(setup, "rear_travel", RearTravel);
		FrontStiffness = Gf(setup, "front_stiffness", FrontStiffness);
		RearStiffness = Gf(setup, "rear_stiffness", RearStiffness);
		FrontDampingCompression = Gf(setup, "front_damping_compression", FrontDampingCompression);
		RearDampingCompression = Gf(setup, "rear_damping_compression", RearDampingCompression);
		FrontDampingRebound = Gf(setup, "front_damping_rebound", FrontDampingRebound);
		RearDampingRebound = Gf(setup, "rear_damping_rebound", RearDampingRebound);
		FrontAntiRoll = Gf(setup, "front_anti_roll", FrontAntiRoll);
		RearAntiRoll = Gf(setup, "rear_anti_roll", RearAntiRoll);

		TireMuFront = Gf(setup, "tire_mu_front", TireMuFront);
		TireMuRear = Gf(setup, "tire_mu_rear", TireMuRear);
		RearCamberDeg = Gf(setup, "rear_camber_deg", RearCamberDeg);
		TireVLow = Gf(setup, "tire_v_low", TireVLow);
		PacejkaBLong = Gf(setup, "pacejka_b_long", PacejkaBLong);
		PacejkaCLong = Gf(setup, "pacejka_c_long", PacejkaCLong);
		PacejkaELong = Gf(setup, "pacejka_e_long", PacejkaELong);
		PacejkaBLat = Gf(setup, "pacejka_b_lat", PacejkaBLat);
		PacejkaCLat = Gf(setup, "pacejka_c_lat", PacejkaCLat);
		PacejkaELat = Gf(setup, "pacejka_e_lat", PacejkaELat);
		TireRelaxationLongitudinal = Gf(setup, "tire_relaxation_longitudinal", TireRelaxationLongitudinal);
		TireRelaxationLateral = Gf(setup, "tire_relaxation_lateral", TireRelaxationLateral);
		RollingResistance = Gf(setup, "rolling_resistance", RollingResistance);
		MinLoadFraction = Gf(setup, "min_load_fraction", MinLoadFraction);

		BrakeForce = Gf(setup, "brake_force", BrakeForce);
		HandbrakeForce = Gf(setup, "handbrake_force", HandbrakeForce);
		HandbrakeLatGrip = Gf(setup, "handbrake_lat_grip", HandbrakeLatGrip);
		BrakeBiasFront = Gf(setup, "brake_bias_front", BrakeBiasFront);

		DragCoefficient = Gf(setup, "drag_coefficient", DragCoefficient);
		DownforceCoefficient = Gf(setup, "downforce_coefficient", DownforceCoefficient);
		FrontalArea = Gf(setup, "frontal_area", FrontalArea);
		AirDensity = Gf(setup, "air_density", AirDensity);

		MaxSteerAngle = Gf(setup, "max_steer_angle", MaxSteerAngle);
		SteerSpeed = Gf(setup, "steer_speed", SteerSpeed);
		FrontCasterDeg = Gf(setup, "front_caster_deg", FrontCasterDeg);
		SteerCurveMaxKmh = Gf(setup, "steer_curve_max_kmh", SteerCurveMaxKmh);
		SteerAngleCurve = setup.Get("steer_angle_curve").AsGodotObject() as Curve;
		SteerSpeedRef = Gf(setup, "steer_speed_ref", SteerSpeedRef);
		SteerHighSpeedFactor = Gf(setup, "steer_high_speed_factor", SteerHighSpeedFactor);
		SteerInputGamma = Gf(setup, "steer_input_gamma", SteerInputGamma);
		CounterSteerSlipDeg = Gf(setup, "counter_steer_slip_deg", CounterSteerSlipDeg);
		CounterSteerLockMax = Gf(setup, "counter_steer_lock_max", CounterSteerLockMax);
		CounterSteerRateMult = Gf(setup, "counter_steer_rate_mult", CounterSteerRateMult);
		CounterSteerRecoverRate = Gf(setup, "counter_steer_recover_rate", CounterSteerRecoverRate);
		SteerLockSmooth = Gf(setup, "steer_lock_smooth", SteerLockSmooth);

		ThrottleRiseRate = Gf(setup, "throttle_rise_rate", ThrottleRiseRate);
		ThrottleFallRate = Gf(setup, "throttle_fall_rate", ThrottleFallRate);
		DriftAssist = Gf(setup, "drift_assist", DriftAssist);

		FwdLatPriority = Gf(setup, "fwd_lat_priority", FwdLatPriority);
		FwdSlipAngleStartDeg = Gf(setup, "fwd_slip_angle_start_deg", FwdSlipAngleStartDeg);
		FwdCounterSteerScale = Gf(setup, "fwd_counter_steer_scale", FwdCounterSteerScale);
		FwdRecoverBleed = Gf(setup, "fwd_recover_bleed", FwdRecoverBleed);

		PhysicsSubsteps = Gi(setup, "physics_substeps", PhysicsSubsteps);
		AutoHoldGearInDrift = Gb(setup, "auto_hold_gear_in_drift", AutoHoldGearInDrift);
		ArcadeAssist = Gf(setup, "arcade_assist", ArcadeAssist);
		NosPowerAdd = Gf(setup, "nos_power_add", NosPowerAdd);
		TurboLevel = Gi(setup, "turbo_level", TurboLevel);
		TractionControl = Gb(setup, "traction_control", TractionControl);
		TcSlipRatio = Gf(setup, "tc_slip_ratio", TcSlipRatio);
		TcGain = Gf(setup, "tc_gain", TcGain);
		TcMinScale = Gf(setup, "tc_min_scale", TcMinScale);

		// Peak torque from cached power (same formula as CarSetup.get_peak_torque_nm).
		MaxPowerHp = Gf(setup, "max_power_hp", MaxPowerHp);
		float powerRpm = MaxRpm * 0.8f;
		float omega = powerRpm * Mathf.Tau / 60f;
		float curveAtPower = SampleTorqueMultiplier(powerRpm);
		float powerW = MaxPowerHp * 0.7457f * 1000f;
		float torqueAtRated = powerW / Mathf.Max(omega, 1f);
		PeakTorqueNm = torqueAtRated / Mathf.Max(curveAtPower, 0.25f);
	}

	public float GetGearRatio(int gear)
	{
		if (gear == 0)
			return 0f;
		if (gear < 0)
			return -ReverseRatio;
		int index = gear - 1;
		if (GearRatios == null || index < 0 || index >= GearRatios.Length)
			return 0f;
		return GearRatios[index];
	}

	public float SampleTorqueMultiplier(float rpm)
	{
		if (TorqueCurve == null || TorqueCurve.GetPointCount() == 0)
			return 1f;
		float t = MaxRpm > 0f ? Mathf.Clamp(rpm / MaxRpm, 0f, 1f) : 0f;
		return Mathf.Max(TorqueCurve.Sample(t), 0f);
	}

	public float GetEngineTorque(float rpm)
		=> PeakTorqueNm * SampleTorqueMultiplier(Mathf.Max(rpm, IdleRpm * 0.5f));

	public float SampleSteerLockFactor(float speedMs)
	{
		if (SteerAngleCurve == null || SteerAngleCurve.GetPointCount() == 0)
			return 1f;
		float maxKmh = Mathf.Max(SteerCurveMaxKmh, 40f);
		float t = Mathf.Clamp((speedMs * 3.6f) / maxKmh, 0f, 1f);
		return Mathf.Clamp(SteerAngleCurve.Sample(t), 0.08f, 1f);
	}

	public float GetRestLength(int i) => i < 2 ? FrontRestLength : RearRestLength;
	public float GetTravel(int i) => i < 2 ? FrontTravel : RearTravel;
	public float GetStiffness(int i) => i < 2 ? FrontStiffness : RearStiffness;
	public float GetDamping(int i, float lengthRate)
	{
		if (i < 2)
			return lengthRate > 0f ? FrontDampingRebound : FrontDampingCompression;
		return lengthRate > 0f ? RearDampingRebound : RearDampingCompression;
	}
	public float GetAntiRoll(bool front) => front ? FrontAntiRoll : RearAntiRoll;
	public float GetTireMu(int i) => i < 2 ? TireMuFront : TireMuRear;
	public float GetWheelRadius(int i) => i < 2 ? FrontWheelRadius : RearWheelRadius;
	public float GetWheelWidth(int i) => i < 2 ? FrontWheelWidth : RearWheelWidth;

	private static float Gf(Resource s, string n, float d)
	{
		Variant v = s.Get(n);
		return v.VariantType == Variant.Type.Nil ? d : v.AsSingle();
	}

	private static int Gi(Resource s, string n, int d)
	{
		Variant v = s.Get(n);
		return v.VariantType == Variant.Type.Nil ? d : v.AsInt32();
	}

	private static bool Gb(Resource s, string n, bool d)
	{
		Variant v = s.Get(n);
		return v.VariantType == Variant.Type.Nil ? d : v.AsBool();
	}

	private static Vector3 Gv3(Resource s, string n, Vector3 d)
	{
		Variant v = s.Get(n);
		return v.VariantType == Variant.Type.Nil ? d : v.AsVector3();
	}
}
