using Godot;
using Godot.Collections;

public partial class CarController
{
	static Godot.GDScript _frameClock;

	static void AddFrameClock(string bucket, int usec)
	{
		if (usec <= 0)
			return;
		if (_frameClock == null)
			_frameClock = GD.Load<Godot.GDScript>("res://rendering/frame_clock.gd");
		_frameClock?.Call("add", bucket, usec);
	}

	public override void _PhysicsProcess(double delta)
	{
		long t0 = System.Diagnostics.Stopwatch.GetTimestamp();
		RunPhysics(delta);
		long usec = (System.Diagnostics.Stopwatch.GetTimestamp() - t0) * 1_000_000L
			/ System.Diagnostics.Stopwatch.Frequency;
		AddFrameClock("phys:car", (int)usec);
	}

	void RunPhysics(double delta)
	{
		if (setup == null)
			return;
		RefreshSetupCache();
		if (!_bodyApplied)
			ApplyBodySetup();

		float dtFrame = (float)delta;
		throttle = Mathf.Clamp(throttle, 0.0f, 1.0f);
		brake = Mathf.Clamp(brake, 0.0f, 1.0f);
		handbrake = Mathf.Clamp(handbrake, 0.0f, 1.0f);
		steering = Mathf.Clamp(steering, -1.0f, 1.0f);

		UpdateThrottleResponse(dtFrame);

		if (_shiftTimer > 0.0f)
			_shiftTimer = Mathf.Max(_shiftTimer - dtFrame, 0.0f);
		if (_autoShiftCooldown > 0.0f)
			_autoShiftCooldown = Mathf.Max(_autoShiftCooldown - dtFrame, 0.0f);

		if (automatic)
			UpdateAutomaticTransmission();
		else
		{
			debug_want_up = 0;
			debug_want_down = 0;
			debug_shift_timer = _shiftTimer;
			debug_auto_cd = 0.0f;
			debug_est_rpm_cur = EstimateTransmissionRpm(current_gear);
			if (current_gear > 0 && current_gear < _c.ForwardGearCount)
				debug_est_rpm_up = EstimateTransmissionRpm(current_gear + 1);
			else
				debug_est_rpm_up = 0.0f;
		}

		UpdateSteering(dtFrame);

		int steps = Mathf.Clamp(_c.PhysicsSubsteps, 1, 8);
		float dt = dtFrame / steps;
		float forceScale = 1.0f / steps;
		for (int i = 0; i < steps; i++)
			PhysicsSubstep(dt, forceScale);
	}

	private float _wheelbase = 2.6f;

	private void PhysicsSubstep(float dt, float forceScale)
	{
		UpdateClutch(dt);
		UpdateSuspension(dt, forceScale);
		UpdateAntiRoll(forceScale);
		UpdateEngineClutchDiff(dt);
		ApplyTireAndWheel(dt, forceScale);
		ApplyYawStability(forceScale);
		ApplyAero(forceScale);
		ApplyArcadeAssist(forceScale);
	}

	private float EstimateTransmissionRpm(int gear)
	{
		if (setup == null)
			return 0.0f;
		float gearRatio = _c.GetGearRatio(gear);
		if (Mathf.Abs(gearRatio) < 0.001f)
			return 0.0f;
		float wheelOmega = AverageDrivenOmega();
		float wheelRpm = Mathf.Abs(wheelOmega) * 60.0f / Mathf.Tau;
		return wheelRpm * Mathf.Abs(gearRatio) * _c.FinalDrive;
	}

	private float EstimateGroundTransmissionRpm(int gear)
	{
		if (setup == null)
			return 0.0f;
		float gearRatio = _c.GetGearRatio(gear);
		if (Mathf.Abs(gearRatio) < 0.001f)
			return 0.0f;
		float radius = 0.32f;
		if (_wheels.Count >= 4)
			radius = Mathf.Max(_c.GetWheelRadius(2), 0.05f);
		else if (_wheels.Count > 0)
			radius = Mathf.Max(_c.GetWheelRadius(0), 0.05f);
		float groundSpeed = Mathf.Abs(LinearVelocity.Dot(-GlobalTransform.Basis.Z));
		float wheelRpm = (groundSpeed / radius) * 60.0f / Mathf.Tau;
		return wheelRpm * Mathf.Abs(gearRatio) * _c.FinalDrive;
	}

	private float MaxDrivenSlipRatio()
	{
		float peak = 0.0f;
		foreach (var wheel in _wheels)
		{
			if (wheel.is_driven && wheel.on_ground)
				peak = Mathf.Max(peak, Mathf.Abs(wheel.slip_ratio));
		}
		return peak;
	}

	private float AverageDrivenOmega()
	{
		float sum = 0.0f;
		int count = 0;
		foreach (var wheel in _wheels)
		{
			if (wheel.is_driven)
			{
				sum += wheel.angular_velocity;
				count++;
			}
		}
		return count == 0 ? 0.0f : sum / count;
	}

	private void UpdateAutomaticTransmission()
	{
		debug_want_up = 0;
		debug_want_down = 0;
		debug_shift_timer = _shiftTimer;
		debug_auto_cd = _autoShiftCooldown;
		if (setup == null)
			return;
		debug_est_rpm_cur = EstimateTransmissionRpm(current_gear);
		if (current_gear > 0 && current_gear < _c.ForwardGearCount)
			debug_est_rpm_up = EstimateTransmissionRpm(current_gear + 1);
		else
			debug_est_rpm_up = 0.0f;

		if (_shiftTimer > 0.0f || _autoShiftCooldown > 0.0f)
			return;

		int maxGear = _c.ForwardGearCount;
		float forwardSpeed = LinearVelocity.Dot(-GlobalTransform.Basis.Z);

		if (!allow_reverse)
		{
			if (current_gear < 1)
				AutoSetGear(1);
			want_reverse = false;
		}
		else
		{
			if (want_reverse && Mathf.Abs(forwardSpeed) < 1.5f)
			{
				if (current_gear != -1)
				{
					AutoSetGear(-1);
					_autoShiftCooldown = 0.4f;
				}
				return;
			}
			if (current_gear < 0)
			{
				if (!want_reverse && Mathf.Abs(forwardSpeed) < 1.0f)
				{
					AutoSetGear(1);
					_autoShiftCooldown = 0.4f;
				}
				return;
			}
			if (current_gear == 0)
			{
				AutoSetGear(1);
				return;
			}
		}

		if (current_gear < 1)
			return;

		float groundRpm = EstimateGroundTransmissionRpm(current_gear);
		float nextGround = 0.0f;
		if (current_gear < maxGear)
			nextGround = EstimateGroundTransmissionRpm(current_gear + 1);
		float drivenSlip = MaxDrivenSlipRatio();
		bool spinning = drivenSlip > 0.35f;
		bool drifting =
			_c.AutoHoldGearInDrift
			&& Mathf.Abs(forwardSpeed) > 8.0f
			&& (handbrake > 0.1f
				|| (Mathf.Abs(debug_body_slip_deg) > 10.0f && throttle > 0.15f));

		float shiftRpm = engine_rpm;
		if (clutch < 0.9f || Mathf.Abs(debug_clutch_slip_w) > 40.0f)
			shiftRpm = debug_est_rpm_cur;

		float upFrac = throttle > 0.5f ? 0.72f : 0.62f;
		bool wantUp = false;
		if (current_gear < maxGear && throttle > 0.08f)
		{
			bool roadReady = groundRpm >= _c.MaxRpm * upFrac;
			bool limiterEscape =
				engine_rpm >= _c.MaxRpm * 0.94f
				&& groundRpm >= _c.MaxRpm * 0.42f;
			if (roadReady || limiterEscape)
			{
				if (nextGround >= _c.IdleRpm * 1.15f)
					wantUp = true;
			}
		}

		bool wantDown = false;
		if (current_gear > 1)
		{
			if (shiftRpm <= _c.MaxRpm * 0.38f && throttle < 0.7f)
				wantDown = true;
			else if (throttle > 0.9f && shiftRpm < _c.MaxRpm * 0.55f)
			{
				float rpmIfDown = EstimateTransmissionRpm(current_gear - 1);
				if (rpmIfDown > 0.0f && rpmIfDown < _c.MaxRpm * 0.9f)
					wantDown = true;
			}
			if (spinning && throttle > 0.5f)
				wantDown = false;
		}

		if (drifting)
		{
			wantUp = false;
			wantDown = false;
		}
		debug_want_up = wantUp ? 1 : 0;
		debug_want_down = wantDown ? 1 : 0;

		if (wantUp && !wantDown)
		{
			AutoSetGear(current_gear + 1);
			_autoShiftCooldown = 0.55f;
		}
		else if (wantDown && !wantUp)
		{
			AutoSetGear(current_gear - 1);
			_autoShiftCooldown = 0.5f;
		}
	}

	private void AutoSetGear(int gear)
	{
		if (setup == null)
			return;
		int maxGear = _c.ForwardGearCount;
		int minGear = allow_reverse ? -1 : 1;
		int target = Mathf.Clamp(gear, minGear, maxGear);
		if (target == 0)
			target = 1;
		if (target == current_gear)
			return;
		int fromGear = current_gear;
		current_gear = target;
		BeginShift(fromGear, current_gear);
	}

	private void ApplyBodySetup()
	{
		Mass = Mathf.Max(_c.Mass, 1.0f);
		CenterOfMassMode = CenterOfMassModeEnum.Custom;
		CenterOfMass = _c.CenterOfMassOffset;
		AngularDampMode = DampMode.Replace;
		LinearDampMode = DampMode.Replace;
		AngularDamp = 0.08f;
		LinearDamp = 0.0f;
		_baseAngularDamp = AngularDamp;
		_bodyApplied = true;
	}

	private void RebuildWheels()
	{
		_wheels.Clear();
		_prevLengths.Clear();
		var positions = _c.WheelPositions;
		if (positions == null)
			return;
		for (int i = 0; i < positions.Count; i++)
		{
			var wheel = new Wheel
			{
				local_origin = positions[i].AsVector3(),
				is_steering = i < 2,
				is_driven = IsDrivenIndex(i),
			};
			_wheels.Add(wheel);
			_prevLengths.Add(_c.GetRestLength(i));
		}
		UpdateWheelbase();
	}

	private bool IsDrivenIndex(int index)
	{
		return _c.DriveType switch
		{
			0 => index < 2,
			1 => index >= 2,
			2 => true,
			_ => index >= 2,
		};
	}

	private void UpdateWheelbase()
	{
		if (_wheels.Count >= 4)
			_wheelbase = Mathf.Max(Mathf.Abs(_wheels[0].local_origin.Z - _wheels[2].local_origin.Z), 1.2f);
		else if (_wheels.Count >= 2)
			_wheelbase = Mathf.Max(Mathf.Abs(_wheels[0].local_origin.Z - _wheels[_wheels.Count - 1].local_origin.Z), 1.2f);
	}

	private void UpdateThrottleResponse(float delta)
	{
		float target = throttle;
		float rise = Mathf.Max(_c.ThrottleRiseRate, 0.1f);
		float fall = Mathf.Max(_c.ThrottleFallRate, 0.1f);
		float rate = target > _throttleCmd ? rise : fall;
		_throttleCmd = Mathf.MoveToward(_throttleCmd, target, rate * delta);
	}

	private void UpdateSteering(float delta)
	{
		float speedMs = new Vector3(LinearVelocity.X, 0.0f, LinearVelocity.Z).Length();
		float baseLock = _c.SampleSteerLockFactor(speedMs);
		float lockDesired = baseLock;
		bool isFwd = _c.DriveType == 0;
		float csScale = 1.0f;
		float recoverBleed = 1.0f;
		if (isFwd)
		{
			csScale = Mathf.Clamp(_c.FwdCounterSteerScale, 0.15f, 1.0f);
			recoverBleed = Mathf.Clamp(_c.FwdRecoverBleed, 0.8f, 2.0f);
		}

		Vector3 forward = -GlobalTransform.Basis.Z;
		Vector3 right = GlobalTransform.Basis.X;
		Vector3 up = GlobalTransform.Basis.Y;
		float vLong = LinearVelocity.Dot(forward);
		float vLat = LinearVelocity.Dot(right);
		float beta = Mathf.Atan2(vLat, Mathf.Max(Mathf.Abs(vLong), 0.8f));
		float yawRate = AngularVelocity.Dot(up);
		float slipEnter = Mathf.DegToRad(_c.CounterSteerSlipDeg);
		float absBeta = Mathf.Abs(beta);
		// Counter-steer soft-lock is an assist: drift_assist = 0 must mean
		// "the sim never touches my steering" (pure rack, base rates only).
		bool assistsOn = _c.DriftAssist > 0.001f;
		bool countering =
			assistsOn
			&& absBeta > slipEnter
			&& steering * beta < 0.0f
			&& Mathf.Abs(steering) > 0.05f;
		bool closing = yawRate * beta < -0.05f;
		bool opening = yawRate * beta > 0.05f;

		if (countering)
		{
			float slipT = Mathf.Clamp((absBeta - slipEnter) / Mathf.DegToRad(22.0f), 0.0f, 1.0f);
			if (closing)
			{
				float closeStrength = Mathf.Clamp(Mathf.Abs(yawRate) / 1.35f, 0.0f, 1.0f);
				float bleedLo = isFwd ? 0.85f / recoverBleed : 0.85f;
				float bleedHi = isFwd ? 0.15f / recoverBleed : 0.15f;
				slipT *= Mathf.Lerp(bleedLo, Mathf.Max(bleedHi, 0.05f), closeStrength);
			}
			float lockCap = Mathf.Lerp(baseLock, _c.CounterSteerLockMax, csScale);
			float boostLock = Mathf.Clamp(lockCap, baseLock, 1.0f);
			lockDesired = Mathf.Lerp(baseLock, boostLock, slipT);
		}

		float lockW = Mathf.Clamp(_c.SteerLockSmooth * delta, 0.0f, 1.0f);
		float fallMult = isFwd ? 1.8f * recoverBleed : 1.8f;
		if (lockDesired < _steerLockSmooth)
			lockW = Mathf.Clamp(_c.SteerLockSmooth * fallMult * delta, 0.0f, 1.0f);
		_steerLockSmooth = Mathf.Lerp(_steerLockSmooth, lockDesired, lockW);
		float lockF = _steerLockSmooth;

		float raw = Mathf.Clamp(steering, -1.0f, 1.0f);
		float gamma = Mathf.Max(_c.SteerInputGamma, 1.0f);
		float shaped = Mathf.Sign(raw) * Mathf.Pow(Mathf.Abs(raw), gamma);

		float maxAngle = Mathf.DegToRad(_c.MaxSteerAngle) * lockF;
		float target = shaped * maxAngle;

		float rateT = Mathf.Clamp(speedMs / Mathf.Max(_c.SteerSpeedRef, 1.0f), 0.0f, 1.0f);
		float rateF = Mathf.Lerp(1.0f, _c.SteerHighSpeedFactor, rateT);
		bool increasing = Mathf.Abs(target) > Mathf.Abs(_currentSteer) + 0.002f;
		float csRate = Mathf.Lerp(1.0f, _c.CounterSteerRateMult, csScale);
		float csRecover = _c.CounterSteerRecoverRate;
		if (isFwd)
			csRecover = Mathf.Clamp(csRecover / recoverBleed, 0.1f, 1.0f);
		if (countering && opening)
			rateF = Mathf.Max(rateF, csRate);
		else if (countering && closing && increasing)
			rateF *= csRecover;
		else if (countering && closing && !increasing)
			rateF = Mathf.Max(rateF, csRate * (isFwd ? 1.35f : 1.15f));
		float rate = Mathf.Max(_c.SteerSpeed, 0.1f) * rateF;

		// Caster: mechanical trail converts front lateral load into an aligning
		// torque — self-centering when the input is released, heavier wheel under load.
		float casterRad = Mathf.DegToRad(Mathf.Clamp(_c.FrontCasterDeg, 0.0f, 12.0f));
		float casterN = Mathf.Tan(casterRad) * Mathf.Max(_c.GetWheelRadius(0), 0.1f) / 0.07f;
		if (casterN > 0.001f)
		{
			float fyFront = 0.0f;
			if (_wheels.Count >= 2)
				fyFront = Mathf.Abs(_wheels[0].lat_force) + Mathf.Abs(_wheels[1].lat_force);
			float loadFrac = Mathf.Clamp(fyFront / Mathf.Max(_c.Mass * 9.81f * 0.5f, 1.0f), 0.0f, 1.0f);
			if (Mathf.Abs(raw) < 0.08f)
				rate *= 1.0f + 2.5f * casterN * (0.3f + 0.7f * loadFrac);
			else
				rate /= 1.0f + 1.1f * casterN * loadFrac;
		}

		_currentSteer = Mathf.MoveToward(_currentSteer, target, rate * delta);
		debug_steer_rad = _currentSteer;
		debug_steer_lock = lockF;
		debug_steer_target = target;
		for (int i = 0; i < _wheels.Count; i++)
			_wheels[i].steer_angle = GetWheelSteerAngle(i);
	}

	private float GetWheelSteerAngle(int index)
	{
		if (index >= 2 || index >= _wheels.Count)
			return 0.0f;
		float steer = _currentSteer;
		if (_wheels.Count < 4 || Mathf.Abs(steer) < 0.0001f)
			return steer;

		float track = Mathf.Abs(_wheels[1].local_origin.X - _wheels[0].local_origin.X);
		float turnRadius = _wheelbase / Mathf.Max(Mathf.Tan(Mathf.Abs(steer)), 0.0001f);
		bool leftTurn = steer > 0.0f;
		bool leftWheel = _wheels[index].local_origin.X < 0.0f;
		bool inner = leftTurn == leftWheel;
		float halfTrack = track * 0.5f;
		float radius = inner ? turnRadius - halfTrack : turnRadius + halfTrack;
		return Mathf.Sign(steer) * Mathf.Atan(_wheelbase / Mathf.Max(radius, 0.35f));
	}

	private void UpdateClutch(float dt)
	{
		if (setup == null)
			return;
		if (current_gear == 0 || _shiftTimer > 0.0f)
		{
			clutch = 0.0f;
			_clutchEngageTimer = _c.ClutchEngageTime;
			return;
		}
		if (_clutchEngageTimer > 0.0f)
		{
			_clutchEngageTimer = Mathf.Max(_clutchEngageTimer - dt, 0.0f);
			float engage = _c.ClutchEngageTime;
			clutch = engage <= 0.001f ? 1.0f : 1.0f - (_clutchEngageTimer / engage);
		}
		else
			clutch = 1.0f;
	}

	private void UpdateSuspension(float dt, float forceScale)
	{
		var space = GetWorld3D().DirectSpaceState;
		var exclude = new Array<Rid> { GetRid() };
		float maxForce = _c.Mass * 9.81f * 4.5f;
		float safeDt = Mathf.Max(dt, 0.0001f);

		for (int i = 0; i < _wheels.Count; i++)
		{
			var wheel = _wheels[i];
			wheel.reset_forces();

			float rest = _c.GetRestLength(i);
			float travel = _c.GetTravel(i);
			float rayLength = rest + travel;
			float stiffness = _c.GetStiffness(i);

			Vector3 originWorld = ToGlobal(wheel.local_origin);
			Vector3 up = GlobalTransform.Basis.Y.Normalized();
			Vector3 down = -up;
			var query = PhysicsRayQueryParameters3D.Create(originWorld, originWorld + down * rayLength);
			query.Exclude = exclude;
			query.CollideWithAreas = false;
			query.CollideWithBodies = true;

			var hit = space.IntersectRay(query);
			if (hit.Count == 0)
			{
				wheel.on_ground = false;
				wheel.compression = 0.0f;
				wheel.suspension_length = rayLength;
				wheel.normal_load = 0.0f;
				_prevLengths[i] = rayLength;
				continue;
			}

			wheel.on_ground = true;
			wheel.hit_point = (Vector3)hit["position"];
			wheel.hit_normal = ((Vector3)hit["normal"]).Normalized();
			float springLength = originWorld.DistanceTo(wheel.hit_point);
			wheel.suspension_length = springLength;

			float compressionDistance = rest - springLength;
			float compression = Mathf.Clamp(compressionDistance / Mathf.Max(travel, 0.001f), 0.0f, 1.0f);
			wheel.compression = compression;

			float lengthRate = (springLength - _prevLengths[i]) / safeDt;
			lengthRate = Mathf.Clamp(lengthRate, -12.0f, 12.0f);
			float springTravel = Mathf.Clamp(compressionDistance, 0.0f, travel);
			float springForce = stiffness * springTravel;
			float dampCoeff = _c.GetDamping(i, lengthRate);
			float damperForce = -dampCoeff * lengthRate;
			if (damperForce < 0.0f && springForce > 0.0f)
				damperForce = Mathf.Max(damperForce, -springForce * 0.75f);

			float bump = 0.0f;
			if (compressionDistance > travel)
			{
				float overrun = compressionDistance - travel;
				bump = stiffness * overrun * 3.0f + _c.Mass * 9.81f * overrun * 8.0f;
			}
			else if (compression > 0.75f)
			{
				float t = (compression - 0.75f) / 0.25f;
				bump = t * t * _c.Mass * 9.81f;
			}

			wheel.suspension_force = Mathf.Clamp(springForce + damperForce + bump, 0.0f, maxForce);
			wheel.normal_load = wheel.suspension_force;
			_prevLengths[i] = springLength;

			ApplyForce(wheel.hit_normal * wheel.suspension_force * forceScale, originWorld - GlobalPosition);
			UpdateWheelBasis(wheel);
		}
	}

	private void UpdateWheelBasis(Wheel wheel)
	{
		Basis steerBasis = GlobalTransform.Basis.Rotated(GlobalTransform.Basis.Y, wheel.steer_angle);
		Vector3 forward = -steerBasis.Z;
		Vector3 up = wheel.hit_normal;
		forward = (forward - up * forward.Dot(up)).Normalized();
		if (forward.LengthSquared() < 0.0001f)
			forward = -GlobalTransform.Basis.Z;
		Vector3 right = up.Cross(forward);
		if (right.LengthSquared() < 0.0001f)
			right = GlobalTransform.Basis.X;
		else
			right = right.Normalized();
		forward = right.Cross(up).Normalized();
		wheel.forward = forward;
		wheel.right = right;
		wheel.up = up;
	}

	private void UpdateAntiRoll(float forceScale)
	{
		if (_wheels.Count < 4)
			return;
		ApplyAntiRollPair(0, 1, true, forceScale);
		ApplyAntiRollPair(2, 3, false, forceScale);
	}

	private void ApplyAntiRollPair(int leftI, int rightI, bool axleFront, float forceScale)
	{
		float bar = _c.GetAntiRoll(axleFront);
		if (bar <= 0.0f)
			return;
		var left = _wheels[leftI];
		var right = _wheels[rightI];
		if (!left.on_ground && !right.on_ground)
			return;
		float diff = left.compression - right.compression;
		float axleForce = diff * bar;
		if (left.on_ground)
		{
			left.normal_load = Mathf.Max(left.suspension_force + axleForce, 0.0f);
			Vector3 leftOrigin = ToGlobal(left.local_origin);
			ApplyForce(left.hit_normal * axleForce * forceScale, leftOrigin - GlobalPosition);
		}
		if (right.on_ground)
		{
			right.normal_load = Mathf.Max(right.suspension_force - axleForce, 0.0f);
			Vector3 rightOrigin = ToGlobal(right.local_origin);
			ApplyForce(right.hit_normal * -axleForce * forceScale, rightOrigin - GlobalPosition);
		}
	}

	private void UpdateEngineClutchDiff(float dt)
	{
		float gearRatio = _c.GetGearRatio(current_gear);
		float engineOmega = engine_rpm * Mathf.Tau / 60.0f;
		float idleOmega = _c.IdleRpm * Mathf.Tau / 60.0f;
		float maxOmega = _c.MaxRpm * Mathf.Tau / 60.0f;

		float effectiveThrottle = _throttleCmd;
		_revLimiterCut = UpdateRevLimiterCut(engine_rpm);
		rev_limiter_active = _revLimiterCut;
		debug_rev_limiter_cut = _revLimiterCut;
		if (_revLimiterCut)
			effectiveThrottle = 0.0f;
		else if (throttle < 0.05f)
			effectiveThrottle = 0.0f;
		debug_eff_throttle = effectiveThrottle;

		float combustion = _c.GetEngineTorque(engine_rpm) * effectiveThrottle;
		// Turbo: boost ramps in with rpm (spool window above idle), up to
		// +13% torque per level at full spool.
		if (_c.TurboLevel > 0)
		{
			float spoolT = Mathf.Clamp((engine_rpm - (_c.IdleRpm + 1200.0f)) / 2600.0f, 0.0f, 1.0f);
			spoolT = spoolT * spoolT * (3.0f - 2.0f * spoolT);
			combustion *= 1.0f + 0.13f * _c.TurboLevel * spoolT;
		}
		// Nitrous: flat power add while the pedal is flat (auto arcade shot).
		if (_c.NosPowerAdd > 0.5f && _throttleCmd > 0.85f && !_revLimiterCut)
			combustion += _c.NosPowerAdd * 745.7f / Mathf.Max(engineOmega, 10.0f);
		float engineFriction = 12.0f + 0.004f * engine_rpm;
		if (throttle < 0.05f)
		{
			float coast = _c.EngineCoastFrictionScale;
			engineFriction += coast * (14.0f + 0.018f * engine_rpm);
			combustion = -engineFriction;
		}
		else if (_revLimiterCut)
		{
			engineFriction += 0.35f * (10.0f + 0.012f * engine_rpm);
			combustion = -engineFriction;
		}

		bool inGear = Mathf.Abs(gearRatio) > 0.001f;
		float transOmega = 0.0f;
		if (inGear)
			transOmega = AverageDrivenOmega() * gearRatio * _c.FinalDrive;

		float clutchTorque = 0.0f;
		float slipW = 0.0f;
		if (inGear && clutch > 0.001f)
		{
			slipW = engineOmega - transOmega;
			float maxT = clutch * _c.ClutchMaxTorque;
			const float lockBand = 40.0f;
			if (clutch >= 0.95f && Mathf.Abs(slipW) < lockBand)
			{
				float sync = Mathf.Clamp(slipW * 28.0f, -maxT * 0.25f, maxT * 0.25f);
				clutchTorque = Mathf.Clamp(combustion + sync, -maxT, maxT);
				if (throttle > 0.1f)
					clutchTorque = Mathf.Max(clutchTorque, -maxT * 0.08f);
				engineOmega = Mathf.Lerp(engineOmega, transOmega, Mathf.Clamp(10.0f * dt, 0.0f, 1.0f));
				slipW = engineOmega - transOmega;
			}
			else if (throttle < 0.05f)
				clutchTorque = Mathf.Clamp(slipW * 12.0f, -60.0f, 60.0f);
			else
			{
				float slipLimit = maxT * Mathf.Clamp(Mathf.Max(_throttleCmd, throttle), 0.15f, 1.0f);
				float target = combustion + slipW * 45.0f;
				if (throttle > 0.1f)
					target = Mathf.Max(target, -slipLimit * 0.08f);
				clutchTorque = Mathf.Clamp(target, -slipLimit, slipLimit);
			}
		}

		float netEngine = combustion - clutchTorque;
		float iE = Mathf.Max(_c.EngineInertia, 0.05f);
		engineOmega += (netEngine / iE) * dt;
		engineOmega = Mathf.Clamp(engineOmega, idleOmega * 0.5f, maxOmega);
		if (!inGear || clutch < 0.05f)
		{
			if (throttle < 0.05f && engineOmega < idleOmega)
				engineOmega = Mathf.MoveToward(engineOmega, idleOmega, 40.0f * dt);
		}
		else if (engineOmega < idleOmega && throttle < 0.02f)
			engineOmega = idleOmega;
		engine_rpm = engineOmega * 60.0f / Mathf.Tau;

		for (int i = 0; i < _wheels.Count; i++)
		{
			var wheel = _wheels[i];
			float bias = wheel.is_steering ? _c.BrakeBiasFront : (1.0f - _c.BrakeBiasFront);
			float service = _c.BrakeForce * brake * bias * 0.5f;
			float hb = 0.0f;
			if (!wheel.is_steering)
				hb = _c.HandbrakeForce * handbrake * 0.5f;
			wheel.brake_torque = service + hb;
		}

		float driveline = 0.0f;
		if (inGear)
			driveline = clutchTorque * gearRatio * _c.FinalDrive;

		float horizSpeed = new Vector3(LinearVelocity.X, 0.0f, LinearVelocity.Z).Length();
		bool parked =
			throttle < 0.05f
			&& brake < 0.05f
			&& handbrake < 0.05f
			&& horizSpeed < 1.25f
			&& Mathf.Abs(LinearVelocity.Y) < 0.6f
			&& IsPlanted();
		if (parked)
		{
			driveline = 0.0f;
			clutchTorque = 0.0f;
		}

		debug_eng_combustion = combustion;
		debug_clutch_torque = clutchTorque;
		debug_trans_rpm = transOmega * 60.0f / Mathf.Tau;
		debug_clutch_slip_w = slipW;
		debug_driveline = driveline;
		debug_gear_ratio = gearRatio;
		debug_shift_timer = _shiftTimer;

		AssignDriveTorques(driveline);
		ApplyTractionControl();
		ApplyFwdLatPriorityTorque();
		ApplyBrakeElsd();
		UpdateSpinDebug();
		if (parked)
			SettleParked(dt);
	}

	private bool UpdateRevLimiterCut(float rpm)
	{
		if (setup == null || throttle < 0.3f)
			return false;
		float cutHigh = _c.MaxRpm * _c.RevLimiterCutHighFrac;
		float cutLow = Mathf.Min(_c.MaxRpm * _c.RevLimiterCutLowFrac, cutHigh - 50.0f);
		if (rpm >= cutHigh)
			return true;
		if (rpm <= cutLow)
			return false;
		return _revLimiterCut;
	}

	private bool IsPlanted()
	{
		int grounded = 0;
		foreach (var wheel in _wheels)
		{
			if (wheel.on_ground)
				grounded++;
		}
		return grounded >= 2;
	}

	private void SettleParked(float dt)
	{
		float damp = Mathf.Clamp(12.0f * dt, 0.0f, 1.0f);
		Vector3 v = LinearVelocity;
		v.X = Mathf.Lerp(v.X, 0.0f, damp);
		v.Z = Mathf.Lerp(v.Z, 0.0f, damp);
		if (Mathf.Abs(v.Y) < 0.35f)
			v.Y = Mathf.Lerp(v.Y, 0.0f, damp);
		LinearVelocity = v;
		AngularVelocity = AngularVelocity.Lerp(Vector3.Zero, damp);
		if (new Vector3(v.X, 0.0f, v.Z).Length() < 0.08f && Mathf.Abs(v.Y) < 0.08f)
		{
			LinearVelocity = Vector3.Zero;
			AngularVelocity = Vector3.Zero;
		}
		foreach (var wheel in _wheels)
		{
			wheel.angular_velocity = Mathf.MoveToward(wheel.angular_velocity, 0.0f, 40.0f * dt);
			wheel.drive_torque = 0.0f;
			wheel.brake_torque = 0.0f;
		}
	}

	private void AssignDriveTorques(float drivelineTorque)
	{
		foreach (var wheel in _wheels)
			wheel.drive_torque = 0.0f;

		if (_wheels.Count < 4)
			return;

		float[] torques = VehicleDiff.SplitDriveline(
			drivelineTorque,
			_c.DriveType,
			_c.AwdFrontBias,
			_wheels[0].angular_velocity,
			_wheels[1].angular_velocity,
			_wheels[2].angular_velocity,
			_wheels[3].angular_velocity,
			_c.RearDiffType,
			_c.DiffPreload,
			_c.DiffPowerLock,
			_c.DiffCoastLock,
			_c.LockedDiffStiffness);

		for (int i = 0; i < 4; i++)
			_wheels[i].drive_torque = torques[i];
	}

	private void UpdateSpinDebug()
	{
		debug_rear_spin = 0;
		if (_wheels.Count < 4)
			return;
		if (Mathf.Abs(_wheels[2].slip_ratio) > 0.2f || Mathf.Abs(_wheels[3].slip_ratio) > 0.2f)
			debug_rear_spin = 1;
	}

	private void ApplyTractionControl()
	{
		debug_tc_scale = 1.0f;
		if (setup == null || !_c.TractionControl)
			return;
		float target = _c.TcSlipRatio;
		float gain = _c.TcGain;
		float scaleSum = 0.0f;
		int scaleN = 0;
		float floorCut = _c.TcMinScale;
		foreach (var wheel in _wheels)
		{
			if (Mathf.Abs(wheel.drive_torque) < 0.01f)
				continue;
			if (wheel.drive_torque * wheel.slip_ratio <= 0.0f)
			{
				scaleSum += 1.0f;
				scaleN++;
				continue;
			}
			float over = Mathf.Abs(wheel.slip_ratio) - target;
			float cut = 1.0f;
			if (over > 0.0f)
			{
				cut = Mathf.Clamp(1.0f - over * gain, floorCut, 1.0f);
				wheel.drive_torque *= cut;
			}
			scaleSum += cut;
			scaleN++;
		}
		if (scaleN > 0)
			debug_tc_scale = scaleSum / scaleN;
	}

	private void ApplyFwdLatPriorityTorque()
	{
		debug_fwd_lat_scale = 1.0f;
		if (setup == null || _c.DriveType != 0)
			return;
		float priority = Mathf.Clamp(_c.FwdLatPriority, 0.0f, 1.0f);
		if (priority <= 0.001f)
			return;
		float startDeg = Mathf.Max(_c.FwdSlipAngleStartDeg, 1.0f);
		float scaleSum = 0.0f;
		int scaleN = 0;
		int limit = Mathf.Min(_wheels.Count, 4);
		for (int i = 0; i < limit; i++)
		{
			var wheel = _wheels[i];
			if (!wheel.is_driven || Mathf.Abs(wheel.drive_torque) < 0.01f)
				continue;
			if (i > 1)
				continue;
			float alphaDeg = Mathf.Abs(Mathf.RadToDeg(wheel.slip_angle));
			float aT = Mathf.Clamp((alphaDeg - startDeg) / 12.0f, 0.0f, 1.0f);
			float kT = Mathf.Clamp((Mathf.Abs(wheel.slip_ratio) - 0.12f) / 0.45f, 0.0f, 1.0f);
			float cut = 1.0f - priority * Mathf.Lerp(0.0f, 0.88f, aT) * Mathf.Lerp(0.55f, 1.0f, kT);
			cut = Mathf.Clamp(cut, 0.12f, 1.0f);
			wheel.drive_torque *= cut;
			scaleSum += cut;
			scaleN++;
		}
		if (scaleN > 0)
			debug_fwd_lat_scale = scaleSum / scaleN;
	}

	/// <summary>
	/// Brake-based eLSD on the driven axle(s): apply brake torque to the faster
	/// driven wheel so an open diff can't dump all torque into a spinning wheel.
	/// For FWD this is also the steering axle, so killing inside-wheel spin keeps
	/// the front tires' lateral budget intact (what real brake-based LSD/ESC does).
	/// </summary>
	private void ApplyBrakeElsd()
	{
		if (setup == null || _c.BrakeElsd <= 0.001f)
			return;
		if (_wheels.Count < 4)
			return;
		if (_throttleCmd < 0.08f)
			return;
		ApplyElsdToPair(_wheels[0], _wheels[1]);
		ApplyElsdToPair(_wheels[2], _wheels[3]);
	}

	private void ApplyElsdToPair(Wheel left, Wheel right)
	{
		if (!left.is_driven || !right.is_driven)
			return;
		// Handbrake owns the rear axle — don't fight it.
		if (handbrake > 0.1f && !left.is_steering)
			return;
		float drive = Mathf.Max(Mathf.Abs(left.drive_torque), Mathf.Abs(right.drive_torque));
		if (drive < 1.0f)
			return;
		float dOmega = left.angular_velocity - right.angular_velocity;
		if (Mathf.Abs(dOmega) < 0.8f)
			return;
		float strength = _c.BrakeElsd;
		float maxTau = 900.0f * strength;
		float tau = Mathf.Clamp(dOmega * 60.0f * strength, -maxTau, maxTau);
		if (tau > 0.0f)
			left.brake_torque += tau;
		else
			right.brake_torque += -tau;
	}

	private void ApplyTireAndWheel(float dt, float forceScale)
	{
		float wheelI = Mathf.Max(_c.WheelInertia, 0.15f);

		// Rear camber: static setting plus roll-induced gain. Raycast wheels stay
		// upright to the ground, so body roll adds outside-wheel negative camber
		// analytically (inside goes positive — like a real swing-axle/MCA setup).
		float camberRear = Mathf.DegToRad(Mathf.Clamp(_c.RearCamberDeg, -8.0f, 8.0f));
		float rollSigned = Mathf.Asin(Mathf.Clamp(GlobalTransform.Basis.X.Dot(Vector3.Up), -1.0f, 1.0f));

		for (int i = 0; i < _wheels.Count; i++)
		{
			var wheel = _wheels[i];
			float radius = Mathf.Max(_c.GetWheelRadius(i), 0.05f);
			if (!wheel.on_ground)
			{
				IntegrateWheelOmega(wheel, 0.0f, radius, wheelI, dt);
				wheel.slip_ratio = 0.0f;
				wheel.slip_angle = 0.0f;
				wheel.filtered_slip_ratio = 0.0f;
				wheel.filtered_slip_angle = 0.0f;
				continue;
			}

			Vector3 pointVelocity = VelocityAtPoint(wheel.hit_point);
			float longSpeed = pointVelocity.Dot(wheel.forward);
			float latSpeed = pointVelocity.Dot(wheel.right);
			float fz = Mathf.Max(wheel.normal_load, 0.0f);

			Vector2 slip = TireModel.ComputeSlip(
				longSpeed,
				latSpeed,
				wheel.angular_velocity,
				radius,
				_c.TireVLow);
			wheel.slip_ratio = slip.X;
			wheel.slip_angle = slip.Y;

			float wheelSurfaceSpeed = Mathf.Abs(wheel.angular_velocity * radius);
			float responseSpeed = Mathf.Max(Mathf.Abs(longSpeed), wheelSurfaceSpeed);
			wheel.filtered_slip_ratio = RelaxSlip(
				wheel.filtered_slip_ratio,
				slip.X,
				responseSpeed,
				_c.TireRelaxationLongitudinal,
				dt);
			wheel.filtered_slip_angle = RelaxSlip(
				wheel.filtered_slip_angle,
				slip.Y,
				Mathf.Abs(longSpeed),
				_c.TireRelaxationLateral,
				dt);

			float gamma = 0.0f;
			if (i >= 2)
			{
				float side = wheel.local_origin.X >= 0.0f ? 1.0f : -1.0f;
				gamma = Mathf.Clamp(camberRear - side * rollSigned, -0.24f, 0.24f);
			}
			Vector2 forces = TireModel.Evaluate(
				wheel.filtered_slip_ratio,
				wheel.filtered_slip_angle,
				fz,
				_c.GetTireMu(i),
				_c.PacejkaBLong,
				_c.PacejkaCLong,
				_c.PacejkaELong,
				_c.PacejkaBLat,
				_c.PacejkaCLat,
				_c.PacejkaELat,
				gamma);

			float rr = -Mathf.Sign(longSpeed) * _c.RollingResistance * fz;
			if (Mathf.Abs(longSpeed) < 0.05f)
				rr = 0.0f;

			wheel.long_force = forces.X + rr;
			wheel.lat_force = forces.Y;

			Vector3 tireForce = wheel.forward * wheel.long_force + wheel.right * wheel.lat_force;
			tireForce -= wheel.hit_normal * tireForce.Dot(wheel.hit_normal);
			ApplyForce(tireForce * forceScale, wheel.hit_point - GlobalPosition);

			IntegrateWheelOmega(wheel, wheel.long_force, radius, wheelI, dt);
		}

		SyncWeldedRearAxle(dt);
	}

	private static float RelaxSlip(float current, float target, float speed, float length, float dt)
	{
		float rate = Mathf.Clamp(speed / Mathf.Max(length, 0.05f), 4.0f, 80.0f);
		float weight = 1.0f - Mathf.Exp(-rate * dt);
		return Mathf.Lerp(current, target, weight);
	}

	private void ApplyYawStability(float forceScale)
	{
		Vector3 forward = -GlobalTransform.Basis.Z;
		Vector3 right = GlobalTransform.Basis.X;
		Vector3 up = GlobalTransform.Basis.Y;
		float vLong = LinearVelocity.Dot(forward);
		float vLat = LinearVelocity.Dot(right);
		float speedH = new Vector3(LinearVelocity.X, 0.0f, LinearVelocity.Z).Length();
		float beta = Mathf.Atan2(vLat, Mathf.Max(Mathf.Abs(vLong), 0.8f));
		debug_body_slip_deg = Mathf.RadToDeg(beta);
		debug_yaw_assist_nm = 0.0f;

		if (setup == null || _c.DriftAssist <= 0.001f || speedH < 5.0f)
			return;

		const float EnterDeg = 14.0f;
		const float HoldDeg = 35.0f;
		const float SpinDeg = 55.0f;
		const float BaseDampDrift = 900.0f;
		const float BaseDampSpin = 3600.0f;
		const float BaseBetaRestore = 2200.0f;
		const float BaseMaxTorque = 5500.0f;

		float assist = Mathf.Clamp(_c.DriftAssist, 0.0f, 2.0f);
		float absBeta = Mathf.Abs(beta);
		float enter = Mathf.DegToRad(EnterDeg);
		float hold = Mathf.DegToRad(HoldDeg);
		float spin = Mathf.DegToRad(SpinDeg);
		if (absBeta < enter)
			return;

		float yawRate = AngularVelocity.Dot(up);
		bool opening = yawRate * beta > 0.0f;
		if (!opening)
			return;

		float thr = Mathf.Clamp(_throttleCmd, 0.0f, 1.0f);
		float tDrift = Mathf.Clamp((absBeta - enter) / Mathf.Max(hold - enter, 0.001f), 0.0f, 1.0f);
		float damp = BaseDampDrift * assist * tDrift * Mathf.Lerp(1.0f, 0.65f, thr);
		float restore = 0.0f;

		bool countering = _currentSteer * beta < 0.0f && Mathf.Abs(steering) > 0.15f;
		if (countering)
			damp *= 0.65f;

		if (absBeta > spin)
		{
			float tSpin = Mathf.Clamp((absBeta - spin) / Mathf.DegToRad(20.0f), 0.0f, 1.0f);
			damp += BaseDampSpin * assist * tSpin;
			restore += BaseBetaRestore * assist * tSpin;
		}

		float maxTq = BaseMaxTorque * assist;
		float torqueNm = Mathf.Clamp(-damp * yawRate - restore * beta, -maxTq, maxTq);
		debug_yaw_assist_nm = torqueNm;
		if (Mathf.Abs(torqueNm) >= 1.0f)
			ApplyTorque(up * (torqueNm * forceScale));
	}

	private void SyncWeldedRearAxle(float dt)
	{
		if (setup == null || _c.RearDiffType != 2)
			return;
		if (_wheels.Count < 4)
			return;
		var left = _wheels[2];
		var right = _wheels[3];
		if (!left.is_driven && !right.is_driven)
			return;
		float avg = (left.angular_velocity + right.angular_velocity) * 0.5f;
		float rate = Mathf.Clamp(_c.LockedDiffStiffness * 0.02f, 12.0f, 60.0f);
		float blend = Mathf.Clamp(rate * dt, 0.0f, 1.0f);
		left.angular_velocity = Mathf.Lerp(left.angular_velocity, avg, blend);
		right.angular_velocity = Mathf.Lerp(right.angular_velocity, avg, blend);
	}

	private static void IntegrateWheelOmega(Wheel wheel, float fx, float radius, float wheelInertia, float dt)
	{
		float tauTire = -fx * radius;
		float tauDrive = wheel.drive_torque;
		float tauBrake = 0.0f;
		if (wheel.brake_torque > 0.0f)
		{
			float opposing = -Mathf.Sign(wheel.angular_velocity);
			if (Mathf.Abs(wheel.angular_velocity) < 0.05f)
			{
				if (Mathf.Abs(tauDrive + tauTire) <= wheel.brake_torque)
				{
					wheel.angular_velocity = 0.0f;
					return;
				}
				opposing = -Mathf.Sign(tauDrive + tauTire);
			}
			tauBrake = opposing * wheel.brake_torque;
		}

		float alpha = (tauDrive + tauBrake + tauTire) / wheelInertia;
		float newOmega = wheel.angular_velocity + alpha * dt;

		if (wheel.brake_torque > 0.0f && wheel.angular_velocity * newOmega < 0.0f)
			newOmega = 0.0f;

		wheel.angular_velocity = newOmega;
	}

	private Vector3 VelocityAtPoint(Vector3 worldPoint)
	{
		Vector3 local = worldPoint - GlobalPosition;
		return LinearVelocity + AngularVelocity.Cross(local);
	}

	private void ApplyAero(float forceScale)
	{
		Vector3 horiz = new(LinearVelocity.X, 0.0f, LinearVelocity.Z);
		float speedH = horiz.Length();
		if (speedH < 0.05f)
			return;
		float q = 0.5f * _c.AirDensity * speedH * speedH;
		Vector3 drag = -horiz.Normalized() * (_c.DragCoefficient * _c.FrontalArea * q);
		Vector3 down = Vector3.Down * (_c.DownforceCoefficient * _c.FrontalArea * q);
		ApplyCentralForce((drag + down) * forceScale);
	}

	/// <summary>
	/// Optional low-slip handling helper. It fades out as the body starts sliding,
	/// leaving breakaway and counter-steer to the tire model and drift assistant.
	/// </summary>
	private void ApplyArcadeAssist(float forceScale)
	{
		if (_c.ArcadeAssist <= 0.001f)
			return;
		float strength = Mathf.Clamp(_c.ArcadeAssist, 0.0f, 1.0f);
		float speedH = new Vector3(LinearVelocity.X, 0.0f, LinearVelocity.Z).Length();
		if (speedH < 3.0f)
			return;

		Vector3 forward = -GlobalTransform.Basis.Z;
		Vector3 up = GlobalTransform.Basis.Y.Normalized();
		Vector3 right = GlobalTransform.Basis.X;
		float vLong = LinearVelocity.Dot(forward);
		float vLat = LinearVelocity.Dot(right);
		float beta = Mathf.Atan2(vLat, Mathf.Max(Mathf.Abs(vLong), 0.8f));
		float driftFade = 1.0f - Mathf.Clamp((Mathf.Abs(beta) - Mathf.DegToRad(8.0f)) / Mathf.DegToRad(16.0f), 0.0f, 1.0f);
		strength *= driftFade;
		if (strength < 0.001f)
			return;
		float yawRate = AngularVelocity.Dot(up);

		// Bicycle model: the yaw rate that follows the current steer angle.
		float targetYaw = vLong * Mathf.Tan(_currentSteer) / Mathf.Max(_wheelbase, 1.0f);
		float yawErr = targetYaw - yawRate;
		float tauGain = _c.Mass * Mathf.Clamp(Mathf.Abs(vLong), 0.0f, 40.0f) * 0.55f;
		float maxTau = _c.Mass * 9.81f * 0.4f;
		float tau = Mathf.Clamp(yawErr * tauGain * strength, -maxTau, maxTau);
		ApplyTorque(up * (tau * forceScale));

		// Central lateral force kills the slide without spinning the body.
		float latGain = _c.Mass * 4.5f * strength;
		float maxLat = _c.Mass * 9.81f * 0.35f;
		float latForce = Mathf.Clamp(-vLat * latGain, -maxLat, maxLat);
		ApplyCentralForce(right * (latForce * forceScale));
	}
}
