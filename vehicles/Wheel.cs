using Godot;

/// <summary>Per-wheel runtime state for the vehicle simulator.</summary>
[GlobalClass]
public partial class Wheel : RefCounted
{
	public Vector3 local_origin { get; set; } = Vector3.Zero;
	public bool is_steering { get; set; }
	public bool is_driven { get; set; }

	public bool on_ground { get; set; }
	public Vector3 hit_point { get; set; } = Vector3.Zero;
	public Vector3 hit_normal { get; set; } = Vector3.Up;
	public float compression { get; set; }
	public float suspension_length { get; set; }

	public float suspension_force { get; set; }
	public float long_force { get; set; }
	public float lat_force { get; set; }

	public float angular_velocity { get; set; }
	public float steer_angle { get; set; }
	public float drive_torque { get; set; }
	public float brake_torque { get; set; }

	public float slip_ratio { get; set; }
	public float slip_angle { get; set; }
	public float filtered_slip_ratio { get; set; }
	public float filtered_slip_angle { get; set; }
	public float normal_load { get; set; }

	public Vector3 forward { get; set; } = Vector3.Forward;
	public Vector3 right { get; set; } = Vector3.Right;
	public Vector3 up { get; set; } = Vector3.Up;

	public void reset_forces()
	{
		suspension_force = 0.0f;
		long_force = 0.0f;
		lat_force = 0.0f;
		drive_torque = 0.0f;
		brake_torque = 0.0f;
	}
}
