# Phisyx — свой физический движок машины

Кастомная vehicle-физика поверх Godot `RigidBody3D`: кузов — rigid body, колёса — raycast + Pacejka-силы через `apply_force`. Движок Godot не считает шины/подвеску сам — всё в наших скриптах.

Целевой feel: **sim** (slip-шины, инерция колёс, LSD, clutch). Arcade `_rear_drift` удалён; дрифт/снос из физики шин.

## Файлы

| Файл | Роль |
|------|------|
| `vehicles/car_controller.gd` | Главный симулятор + substeps (`CarController`) |
| `vehicles/wheel.gd` | Состояние колеса: ω, slip, Fx/Fy, load |
| `vehicles/tire_model.gd` | Pacejka Magic Formula + combined slip |
| `vehicles/differential.gd` | Open/LSD split + AWD bias |
| `vehicles/car_setup.gd` | Тюнинг-ресурс (`CarSetup`) |
| `vehicles/tuning_store.gd` | Сохранение/загрузка тюнинга (autoload) |
| `vehicles/player_driver.gd` | Ввод → throttle/brake/steer |
| `vehicles/car_debug_draw.gd` | Debug F3: лучи, Fx/Fy, HUD slip |
| `vehicles/engine_audio.gd` | Звук от RPM |

Конвенция колёс: `[FL, FR, RL, RR]`.

---

## Что реализовано (sim)

### Кузов
- `RigidBody3D` + масса + кастомный CoM
- `continuous_cd`, `can_sleep = false`
- Нулевой friction/bounce на кузове — сцепление только через шины

### Подвеска (raycast, раздельно перед/зад)
- Отдельные `front_*` / `rear_*`: rest, travel, stiffness, compression/rebound damping, anti-roll
- Spring + damper + bump-stop
- Legacy-поля (`stiffness` и т.д.) для миграции старых `.tres` / cfg

### Шины (Pacejka)
- Slip ratio κ и slip angle α с `tire_v_low`
- Magic Formula B/C/D/E long + lat, D = µ·Fz
- Combined-slip эллипс (нормализация по D)
- Отдельные `tire_mu_front` / `tire_mu_rear`
- Rolling resistance

### Инерция колёс
- `wheel_inertia`: τ_drive + τ_brake + (−Fx·R) → ω
- Тормоз не прокручивает колесо через ноль одним шагом

### Дифференциал / AWD
- **Перед** всегда свободный (open, 50/50)
- **Зад** на выбор: свободный / LSD (preload + power/coast lock) / заварка (жёсткая синхронизация ω)
- FWD / RWD / AWD (`awd_front_bias` только для AWD)
- Ручник — тормозной момент на зад (не меняет тип диффа)

### Двигатель / clutch / КПП
- Torque curve + `engine_inertia`
- Clutch 0..1: открыт на shift, плавное замыкание
- Вязкий lock clutch → driveline torque → дифф
- Автомат / механика, reverse (опционально)

### Тормоза / аэро
- `brake_bias_front` + отдельный handbrake на зад
- Cd / Cl / frontal area / air density; downforce к CoM

### Симуляция
- `physics_substeps` (дефолт 4): suspension → clutch/engine → diff → tires/ω → aero

### Инфраструктура
- TuningStore + Settings UI под новые параметры
- F3: векторы Fx/Fy, HUD κ/α/Fz/ω

---

## Порядок substep

1. Clutch engage  
2. Suspension rays + spring/damper  
3. Anti-roll  
4. Engine + clutch torque + brake torques + diff split  
5. Pacejka Fx/Fy → `apply_force` + integrate wheel ω  
6. Aero drag + downforce  

(Руль и автомат КПП — раз в кадр.)

---

## Что ещё можно доработать (вне текущего scope)

- Surface µ / погода
- Ackermann, camber, toe
- Tire temperature / wear
- ABS / TCS
- Sphere/capsule sweep вместо тонкого луча
- Full engine stall
- Pitch-момент от downforce (сейчас только сила к CoM)
