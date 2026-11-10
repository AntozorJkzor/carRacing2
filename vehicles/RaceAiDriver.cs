using System.Collections.Generic;
using Godot;
using Godot.Collections;

/// <summary>
/// Primitive lap AI: chase track waypoints, throttle/steer into CarController.
/// Tries a light overtake offset when the player is nearby ahead.
/// </summary>
[GlobalClass]
public partial class RaceAiDriver : Node
{
	[Export] public string WaypointsPath { get; set; } = "res://assets/scenes/tracks/track2_waypoints.json";
	[Export] public float LookAhead { get; set; } = 18.0f;
	[Export] public float MaxThrottle { get; set; } = 0.92f;
	[Export] public float CornerBrakeAngleDeg { get; set; } = 28.0f;
	[Export] public float OvertakeOffset { get; set; } = 2.4f;
	[Export] public int SkillSeed { get; set; }

	public bool Racing { get; set; }

	private CarController _car;
	private readonly List<Vector3> _waypoints = new();
	private int _wpIndex;
	private float _skill;
	private Node3D _playerCar;

	public override void _Ready()
	{
		_car = GetParentOrNull<CarController>();
		if (_car == null)
			return;

		_skill = 0.78f + (Mathf.Abs(SkillSeed) % 17) * 0.01f;
		MaxThrottle = Mathf.Clamp(MaxThrottle * _skill, 0.7f, 0.98f);

		var playerDriver = _car.GetNodeOrNull("PlayerDriver");
		if (playerDriver != null)
			playerDriver.ProcessMode = ProcessModeEnum.Disabled;

		_car.RemoveFromGroup("player_cars");
		_car.AddToGroup("ai_cars");
		LoadWaypoints();
		SnapToNearestWaypoint();
		ProcessPriority = 40;
	}

	public override void _PhysicsProcess(double delta)
	{
		if (_car == null)
			return;

		if (!Racing)
		{
			_car.throttle = 0.0f;
			_car.brake = 1.0f;
			_car.handbrake = 1.0f;
			_car.steering = 0.0f;
			_car.want_reverse = false;
			return;
		}

		if (_waypoints.Count < 2)
		{
			_car.throttle = 0.0f;
			_car.brake = 1.0f;
			return;
		}

		AdvanceWaypoint();
		Vector3 target = GetLookAheadTarget();
		target += GetOvertakeLateral();

		Vector3 local = _car.GlobalTransform.Inverse() * target;
		// Car forward is -Z.
		float steer = Mathf.Clamp(-local.X / Mathf.Max(6.0f, Mathf.Abs(local.Z) * 0.35f + 4.0f), -1.0f, 1.0f);
		float angle = Mathf.RadToDeg(Mathf.Atan2(Mathf.Abs(local.X), Mathf.Max(0.1f, -local.Z)));

		float throttle = MaxThrottle;
		float brake = 0.0f;
		if (angle > CornerBrakeAngleDeg)
		{
			throttle *= Mathf.Clamp(1.0f - (angle - CornerBrakeAngleDeg) / 55.0f, 0.25f, 1.0f);
			brake = Mathf.Clamp((angle - CornerBrakeAngleDeg) / 70.0f, 0.0f, 0.55f);
		}

		float speed = _car.get_speed_kmh();
		if (speed > 130.0f * _skill && angle > 18.0f)
			brake = Mathf.Max(brake, 0.25f);

		_car.steering = steer;
		_car.throttle = throttle;
		_car.brake = brake;
		_car.handbrake = 0.0f;
		_car.want_reverse = false;
	}

	private void LoadWaypoints()
	{
		_waypoints.Clear();
		if (!FileAccess.FileExists(WaypointsPath))
		{
			GD.PushWarning($"RaceAiDriver: missing waypoints {WaypointsPath}");
			return;
		}

		using var file = FileAccess.Open(WaypointsPath, FileAccess.ModeFlags.Read);
		string json = file.GetAsText();
		var root = Json.ParseString(json).AsGodotDictionary();
		if (root == null || !root.ContainsKey("waypoints"))
			return;

		var arr = root["waypoints"].AsGodotArray();
		foreach (Variant item in arr)
		{
			var p = item.AsGodotDictionary();
			float x = p["x"].AsSingle();
			float y = p["y"].AsSingle();
			float z = p["z"].AsSingle();
			_waypoints.Add(new Vector3(x, y, z));
		}
	}

	private void SnapToNearestWaypoint()
	{
		if (_waypoints.Count == 0)
			return;
		float best = float.MaxValue;
		int bestI = 0;
		Vector3 pos = _car.GlobalPosition;
		for (int i = 0; i < _waypoints.Count; i++)
		{
			float d = pos.DistanceSquaredTo(_waypoints[i]);
			if (d < best)
			{
				best = d;
				bestI = i;
			}
		}
		_wpIndex = bestI;
	}

	private void AdvanceWaypoint()
	{
		Vector3 pos = _car.GlobalPosition;
		for (int n = 0; n < 8; n++)
		{
			Vector3 wp = _waypoints[_wpIndex];
			Vector3 flat = new Vector3(wp.X, pos.Y, wp.Z);
			if (pos.DistanceTo(flat) > LookAhead * 0.45f)
				break;
			_wpIndex = (_wpIndex + 1) % _waypoints.Count;
		}
	}

	private Vector3 GetLookAheadTarget()
	{
		Vector3 pos = _car.GlobalPosition;
		float traveled = 0.0f;
		int i = _wpIndex;
		Vector3 prev = _waypoints[i];
		Vector3 target = prev;
		int guard = _waypoints.Count;
		while (traveled < LookAhead && guard-- > 0)
		{
			i = (i + 1) % _waypoints.Count;
			Vector3 next = _waypoints[i];
			traveled += prev.DistanceTo(next);
			target = next;
			prev = next;
		}
		target.Y = pos.Y;
		return target;
	}

	private Vector3 GetOvertakeLateral()
	{
		_playerCar ??= FindPlayerCar();
		if (_playerCar == null)
			return Vector3.Zero;

		Vector3 toPlayer = _playerCar.GlobalPosition - _car.GlobalPosition;
		toPlayer.Y = 0.0f;
		float dist = toPlayer.Length();
		if (dist > 28.0f || dist < 0.1f)
			return Vector3.Zero;

		Vector3 forward = -_car.GlobalTransform.Basis.Z;
		forward.Y = 0.0f;
		forward = forward.Normalized();
		float ahead = toPlayer.Normalized().Dot(forward);
		if (ahead < 0.15f)
			return Vector3.Zero;

		// Nudge sideways to pass when stuck behind the player.
		Vector3 right = _car.GlobalTransform.Basis.X;
		right.Y = 0.0f;
		right = right.Normalized();
		float side = Mathf.Sign(SkillSeed % 2 == 0 ? 1.0f : -1.0f);
		float strength = Mathf.Clamp((28.0f - dist) / 28.0f, 0.0f, 1.0f);
		return right * (OvertakeOffset * side * strength);
	}

	private Node3D FindPlayerCar()
	{
		foreach (Node n in GetTree().GetNodesInGroup("player_cars"))
		{
			if (n is CarController cc && cc.occupied)
				return cc;
		}
		return null;
	}
}
