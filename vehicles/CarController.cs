using Godot;
using Godot.Collections;

/// <summary>Custom vehicle simulator on RigidBody3D (Phisyx hot-path).</summary>
[GlobalClass]
public partial class CarController : RigidBody3D
{
	[Signal]
	public delegate void gear_shiftedEventHandler(int fromGear, int toGear);

	[Export] public Resource setup { get; set; }
	[Export] public StringName car_id { get; set; } = "golf";
	[Export] public PackedScene wheel_scene { get; set; }
	[Export] public Resource audio_profile { get; set; }
	[Export] public float clearance { get; set; }
	[Export] public bool allow_reverse { get; set; } = true;
	[Export] public NodePath cockpit_camera_path { get; set; } = "Camera3D";

	public float throttle;
	public float brake;
	public float handbrake;
	public float steering;
	public bool want_reverse;

	public int current_gear = 1;
	public float engine_rpm = 800.0f;
	public bool automatic = true;
	public float clutch = 1.0f;

	public float debug_steer_rad;
	public float debug_steer_lock = 1.0f;
	public float debug_steer_target;
	public float debug_eng_combustion;
	public float debug_clutch_torque;
	public float debug_trans_rpm;
	public float debug_clutch_slip_w;
	public float debug_driveline;
	public float debug_gear_ratio;
	public float debug_shift_timer;
	public float debug_auto_cd;
	public float debug_est_rpm_cur;
	public float debug_est_rpm_up;
	public int debug_want_up;
	public int debug_want_down;
	public float debug_tc_scale = 1.0f;
	public float debug_fwd_lat_scale = 1.0f;
	public float debug_eff_throttle;
	public bool debug_rev_limiter_cut;
	public bool rev_limiter_active;
	public int debug_rear_spin;
	public float debug_body_slip_deg;
	public float debug_yaw_assist_nm;
	/// <summary>Self-steer contribution to the rack target, degrees.</summary>
	public float debug_self_steer_deg;
	public bool debug_self_steer_active;

	private readonly System.Collections.Generic.List<Wheel> _wheels = new();
	private float _currentSteer;
	private float _steerLockSmooth = 1.0f;
	private float _throttleCmd;
	private float _shiftTimer;
	private int _shiftDirection;
	private bool _autoHold;
	private bool _brakeStop;
	private float _restTime;
	private readonly System.Collections.Generic.List<float> _prevLengths = new();
	private bool _bodyApplied;
	private float _baseAngularDamp = 1.2f;
	private float _autoShiftCooldown;
	private Transform3D _spawnTransform = Transform3D.Identity;
	private float _clutchEngageTimer;
	private float _launchEngage;
	private bool _creepBrake;
	private float _steerDriftBlend;
	private bool _revLimiterCut;
	public bool occupied;
	public Node occupant;
	/// <summary>Pose is written from outside. The tire solver does not run.</summary>
	public bool scripted_motion;
	private float _modelBaseY;
	private float _collisionBaseY;
	private bool _visualBasesCached;
	private bool _cockpitView;
	private readonly CarSetupCache _c = new();

	private void RefreshSetupCache()
	{
		if (setup != null)
			_c.RefreshFrom(setup);
	}

	private Node TuningStore => GetNodeOrNull("/root/TuningStore");

	public override void _Ready()
	{
		bool tandem = HasMeta("tandem_rival") && GetMeta("tandem_rival").AsBool();
		if (!tandem)
			AddToGroup("player_cars");
		_spawnTransform = GlobalTransform;
		if (setup != null)
			setup = (Resource)setup.Duplicate(true);
		else
			setup = (Resource)GD.Load<GDScript>("res://vehicles/car_setup.gd").New();
		setup.Call("ensure_torque_curve");
		setup.Call("ensure_steer_angle_curve");
		setup.Call("migrate_legacy_fields");
		if (!tandem)
			TuningStore?.Call("apply_overrides_to_car", this);
		RefreshSetupCache();
		bool showroom = HasMeta("showroom") && GetMeta("showroom").AsBool();
		ApplyPackAssets(showroom);
		ApplyBodySetup();
		RebuildWheels();
		ApplyVisualTuning();
		CanSleep = false;
		ContinuousCd = true;
		_baseAngularDamp = AngularDamp;
		AngularDamp = _baseAngularDamp;
		PhysicsMaterialOverride = new PhysicsMaterial
		{
			Friction = 0.0f,
			Bounce = 0.0f,
		};
		if (!tandem)
			TuningStore?.Call("bind_car_id", car_id);
		if (tandem)
			BeginScriptedMotion();
	}

	private void BeginScriptedMotion()
	{
		scripted_motion = true;
		// Layer 3 only. The player already scans it, and the road does not,
		// so the body can shove the player without planting itself in the asphalt.
		CollisionLayer = 4;
		CollisionMask = 4;
		CanSleep = false;
		FreezeMode = FreezeModeEnum.Kinematic;
		Freeze = true;
		Sleeping = false;
		GravityScale = 0.0f;
		var driver = GetNodeOrNull("PlayerDriver");
		if (driver != null)
			driver.ProcessMode = ProcessModeEnum.Disabled;
		var lights = GetNodeOrNull("CarLights");
		if (lights != null)
			lights.Set("lights_on", true);
		foreach (Node node in FindChildren("*", "Camera3D", true, false))
		{
			if (node is Camera3D cam)
				cam.Current = false;
		}
	}

	public void refresh_camera()
	{
		if (!occupied)
			return;
		ApplyCameraMode();
	}

	/// <summary>
	/// Plant the body on a recorded pose. Wheels, slip and rpm are faked so the
	/// rival still steers, smokes and revs while ignoring the tire solver.
	/// </summary>
	public void apply_scripted_motion(Transform3D xf, Vector3 velocity, Vector3 angularVelocity, float steerInput, float slipDeg, bool snap)
	{
		scripted_motion = true;
		if (!Freeze)
			BeginScriptedMotion();
		steerInput = Mathf.Clamp(steerInput, -1.0f, 1.0f);
		Sleeping = false;
		// A frozen kinematic body does not integrate linear_velocity. The pose
		// has to be written, and the velocity is what shoves a dynamic car.
		if (snap)
		{
			GlobalTransform = xf;
			PhysicsServer3D.BodySetState(GetRid(), PhysicsServer3D.BodyState.Transform, xf);
		}
		LinearVelocity = velocity;
		AngularVelocity = angularVelocity;
		PhysicsServer3D.BodySetState(GetRid(), PhysicsServer3D.BodyState.LinearVelocity, velocity);
		PhysicsServer3D.BodySetState(GetRid(), PhysicsServer3D.BodyState.AngularVelocity, angularVelocity);
		xf = GlobalTransform;

		steering = steerInput;
		throttle = 0.85f;
		brake = 0.0f;
		handbrake = Mathf.Abs(slipDeg) > 10.0f ? 0.4f : 0.0f;
		float speed = velocity.Length();
		engine_rpm = Mathf.Clamp(1500.0f + speed * 150.0f + Mathf.Abs(slipDeg) * 28.0f, 900.0f, 7600.0f);
		float maxSteer = setup != null ? Mathf.Max(setup.Get("max_steer_angle").AsSingle(), 1.0f) : 32.0f;
		debug_steer_rad = steerInput * Mathf.DegToRad(maxSteer);
		debug_body_slip_deg = slipDeg;

		float radius = 0.3f;
		if (setup != null)
			radius = Mathf.Max(setup.Get("wheel_radius").AsSingle(), 0.15f);
		Vector3 up = xf.Basis.Y.Normalized();
		float slipRad = Mathf.DegToRad(slipDeg);
		bool sliding = Mathf.Abs(slipDeg) > 8.0f && speed > 3.0f;
		foreach (Wheel wheel in _wheels)
		{
			wheel.on_ground = true;
			wheel.contact_time = 1.0f;
			wheel.up = up;
			wheel.hit_normal = up;
			wheel.steer_angle = wheel.is_steering ? debug_steer_rad : 0.0f;
			Basis steered = xf.Basis.Rotated(up, wheel.steer_angle);
			wheel.forward = (-steered.Z).Normalized();
			wheel.right = up.Cross(wheel.forward).Normalized();
			wheel.effective_radius = radius;
			wheel.longitudinal_speed = speed;
			wheel.lateral_speed = speed * Mathf.Sin(slipRad);
			wheel.angular_velocity = speed / radius;
			wheel.slip_angle = slipRad;
			wheel.filtered_slip_angle = slipRad;
			wheel.slip_ratio = sliding && !wheel.is_steering ? 0.42f : 0.02f;
			wheel.filtered_slip_ratio = wheel.slip_ratio;
			wheel.normal_load = 2800.0f;
			Vector3 hub = xf * wheel.local_origin;
			wheel.hit_point = hub - up * radius;
		}
	}

	private void ApplyPackAssets(bool showroom)
	{
		if (wheel_scene != null)
		{
			var visual = GetNodeOrNull("VisualWheels");
			if (visual != null && visual.Get("wheel_scene").AsGodotObject() == null)
				visual.Set("wheel_scene", wheel_scene);
			var layout = GetNodeOrNull("WheelLayout");
			if (layout != null && layout.Get("wheel_scene").AsGodotObject() == null)
				layout.Set("wheel_scene", wheel_scene);
		}

		if (!showroom && audio_profile != null)
		{
			var engineAudio = GetNodeOrNull("EngineAudio");
			if (engineAudio != null && engineAudio.HasMethod("apply_profile"))
			{
				engineAudio.Call("apply_profile", audio_profile, true);
				bool isLive = engineAudio.HasMethod("is_live") && (bool)engineAudio.Call("is_live");
				if (isLive)
				{
					if (engineAudio.HasMethod("apply_setup"))
						engineAudio.Call("apply_setup", setup);
				}
				else
				{
					var userBanks = CallBaker("load_user", car_id);
					var banksArr = userBanks.AsGodotArray();
					if ((banksArr == null || banksArr.Count == 0) && audio_profile != null)
					{
						string bankDir = audio_profile.Get("engine_bank_dir").AsString();
						if (!string.IsNullOrEmpty(bankDir))
							userBanks = CallBaker("load_dir", bankDir);
					}
					banksArr = userBanks.AsGodotArray();
					if (banksArr != null && banksArr.Count > 0 && engineAudio.HasMethod("apply_banks"))
						engineAudio.Call("apply_banks", userBanks);
				}
			}
		}

		if (!showroom)
		{
			EnsureChild("WheelSmoke", "res://vehicles/wheel_smoke.gd", typeof(Node3D));
			EnsureChild("SkidMarks", "res://vehicles/skid_marks.gd", typeof(Node3D));
			EnsureChild("TireAudio", "res://vehicles/tire_audio.gd", typeof(Node3D));
			EnsureChild("ExhaustFlame", "res://vehicles/exhaust_flame.gd", typeof(Node3D));
		}
		EnsureChild("PlayerDriver", "res://vehicles/player_driver.gd", typeof(Node));
		EnsureChild("CarLights", "res://vehicles/car_lights.gd", typeof(Node3D));
	}

	private static Variant CallBaker(string method, params Variant[] args)
	{
		if (ClassDB.ClassExists("EngineBankBaker") && ClassDB.ClassHasMethod("EngineBankBaker", method))
			return ClassDB.ClassCallStatic("EngineBankBaker", method, args);
		var script = GD.Load<GDScript>("res://vehicles/engine_sound_baker.gd");
		return script != null ? script.Call(method, args) : default;
	}

	private void EnsureChild(string name, string scriptPath, System.Type nodeType)
	{
		if (GetNodeOrNull(name) != null)
			return;
		Node node = nodeType == typeof(Node3D) ? new Node3D() : new Node();
		node.Name = name;
		var script = GD.Load<Script>(scriptPath);
		node.SetScript(script);
		AddChild(node);
	}

	public void set_occupied(bool value, Node who = null)
	{
		occupied = value;
		occupant = value ? who : null;
		var driver = GetNodeOrNull("PlayerDriver");
		if (driver != null && driver.Get("active").VariantType != Variant.Type.Nil)
			driver.Set("active", value);
		if (!value)
			_cockpitView = false;
		if (!IsInsideTree())
			return;
		ApplyCameraMode();
		if (value)
		{
			foreach (Node hud in GetTree().GetNodesInGroup("car_huds"))
			{
				if (hud.HasMethod("bind_car"))
					hud.Call("bind_car", this);
			}
			TuningStore?.Call("bind_car_id", car_id);
		}
	}

	public void toggle_camera_view()
	{
		if (!occupied)
			return;
		if (GetCockpitCamera() == null)
			return;
		_cockpitView = !_cockpitView;
		ApplyCameraMode();
	}

	private void ApplyCameraMode()
	{
		var cockpit = GetCockpitCamera();
		foreach (Node cam in GetTree().GetNodesInGroup("car_follow_cameras"))
		{
			if (occupied && cam.HasMethod("set_target"))
				cam.Call("set_target", this);
			bool active = occupied && !_cockpitView;
			if (cam.HasMethod("set_active"))
				cam.Call("set_active", active);
			else if (cam is Camera3D camera3D)
				camera3D.Current = active;
		}
		if (cockpit != null)
			cockpit.Current = occupied && _cockpitView;
	}

	private Camera3D GetCockpitCamera()
	{
		if (cockpit_camera_path != null && !cockpit_camera_path.IsEmpty)
		{
			var explicitCam = GetNodeOrNull<Camera3D>(cockpit_camera_path);
			if (explicitCam != null)
				return explicitCam;
		}
		return GetNodeOrNull<Camera3D>("Camera3D");
	}

	public void reset_to_spawn()
	{
		throttle = 0.0f;
		brake = 0.0f;
		handbrake = 0.0f;
		steering = 0.0f;
		_currentSteer = 0.0f;
		_steerLockSmooth = 1.0f;
		_steerDriftBlend = 0.0f;
		_throttleCmd = 0.0f;
		current_gear = 1;
		RefreshSetupCache();
		engine_rpm = setup != null ? _c.IdleRpm : 800.0f;
		clutch = 1.0f;
		_clutchEngageTimer = 0.0f;
		_launchEngage = 0.0f;
		_shiftTimer = 0.0f;
		_autoShiftCooldown = 0.0f;
		want_reverse = false;
		AngularDamp = _baseAngularDamp;
		Sleeping = false;
		PhysicsServer3D.BodySetState(GetRid(), PhysicsServer3D.BodyState.Transform, _spawnTransform);
		PhysicsServer3D.BodySetState(GetRid(), PhysicsServer3D.BodyState.LinearVelocity, Vector3.Zero);
		PhysicsServer3D.BodySetState(GetRid(), PhysicsServer3D.BodyState.AngularVelocity, Vector3.Zero);
		GlobalTransform = _spawnTransform;
		LinearVelocity = Vector3.Zero;
		AngularVelocity = Vector3.Zero;
		if (setup != null)
			RebuildWheels();
	}

	private void CacheVisualBases()
	{
		if (_visualBasesCached)
			return;
		var model = GetNodeOrNull<Node3D>("Model");
		var col = GetNodeOrNull<CollisionShape3D>("CollisionShape3D");
		if (model != null)
			_modelBaseY = model.Position.Y;
		if (col != null)
			_collisionBaseY = col.Position.Y;
		_visualBasesCached = true;
	}

	public void refresh_visual_tuning() => ApplyVisualTuning();

	private void ApplyVisualTuning()
	{
		CacheVisualBases();
		var model = GetNodeOrNull<Node3D>("Model");
		if (model != null)
		{
			var p = model.Position;
			p.Y = _modelBaseY + clearance;
			model.Position = p;
		}
		var col = GetNodeOrNull<CollisionShape3D>("CollisionShape3D");
		if (col != null)
		{
			var p = col.Position;
			p.Y = _collisionBaseY + clearance;
			col.Position = p;
		}
	}

	public void apply_setup(Resource newSetup)
	{
		setup = newSetup;
		if (setup == null)
			setup = (Resource)GD.Load<GDScript>("res://vehicles/car_setup.gd").New();
		setup.Call("ensure_torque_curve");
		setup.Call("ensure_steer_angle_curve");
		setup.Call("migrate_legacy_fields");
		RefreshSetupCache();
		_bodyApplied = false;
		RebuildWheels();
		if (IsInsideTree())
			ApplyBodySetup();
	}

	public void shift_up()
	{
		if (setup == null || _shiftTimer > 0.0f)
			return;
		int maxGear = _c.ForwardGearCount;
		if (current_gear < maxGear)
		{
			int fromGear = current_gear;
			current_gear += 1;
			BeginShift(fromGear, current_gear);
			if (automatic)
				_autoShiftCooldown = 0.7f;
		}
	}

	public void shift_down()
	{
		if (setup == null || _shiftTimer > 0.0f)
			return;
		int minGear = allow_reverse ? -1 : 1;
		if (current_gear > minGear)
		{
			int fromGear = current_gear;
			current_gear -= 1;
			BeginShift(fromGear, current_gear);
			if (automatic)
				_autoShiftCooldown = 0.55f;
		}
	}

	private void BeginShift(int fromGear, int toGear)
	{
		_shiftTimer = Mathf.Clamp(_c.ShiftTime * 0.6f, 0.07f, 0.14f);
		_shiftDirection = Mathf.Sign(toGear - fromGear);
		clutch = 0.0f;
		_clutchEngageTimer = Mathf.Clamp(_c.ClutchEngageTime * 0.55f, 0.05f, 0.1f);
		EmitSignal(SignalName.gear_shifted, fromGear, toGear);
	}

	public void toggle_transmission()
	{
		automatic = !automatic;
		want_reverse = false;
		_autoShiftCooldown = 0.0f;
		if (automatic && current_gear <= 0)
			current_gear = 1;
	}

	public string get_transmission_label() => automatic ? "AUTO" : "MANUAL";

	public void set_gear(int gear)
	{
		if (setup == null)
			return;
		int maxGear = _c.ForwardGearCount;
		int minGear = allow_reverse ? -1 : 1;
		int target = Mathf.Clamp(gear, minGear, maxGear);
		if (target == current_gear)
			return;
		int fromGear = current_gear;
		current_gear = target;
		BeginShift(fromGear, current_gear);
	}

	public float get_speed_ms() => LinearVelocity.Length();

	public float get_speed_kmh() => get_speed_ms() * 3.6f;

	public float get_power_hp() => setup == null ? 0f : _c.MaxPowerHp;

	public string get_gear_label()
	{
		if (current_gear < 0)
			return "R";
		if (current_gear == 0)
			return "N";
		return current_gear.ToString();
	}

	public Array<Wheel> get_wheels()
	{
		var arr = new Array<Wheel>();
		foreach (var w in _wheels)
			arr.Add(w);
		return arr;
	}
}
