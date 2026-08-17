# Графика: что прикрутить, чтобы было красиво

Рендер уже **Forward+** (Godot 4.7). Меню качества живое: FSR 1/2, TAA/FXAA, MSAA 2x, glow, SSAO, SSIL, SSR, туман, объёмный туман, ACES, тени. Это база, не картинка.

Сейчас сцена выглядит «технически»: `ProceduralSky`, одно солнце, без GI, без шейдеров, без следов, без грейда камеры. Красота в гонке почти всегда = **свет + материалы + VFX + камера**, а не ещё один тумблер SSAO.

## Что уже есть

| Кусок | Где | Заметка |
|-------|-----|---------|
| Пресеты Low–Ultra | `rendering/graphics_config.gd` | SDFGI принудительно выкл: Volga чернеет |
| MSAA | тот же файл | выше 2x даёт чёрные артефакты — не поднимать |
| Небо | `physics_test_track.tscn` | простой `ProceduralSkyMaterial` |
| Солнце | `Sun` DirectionalLight3D | тени до 400 м |
| Камера | `follow_camera.gd` | FOV 72, far 800, без экспозиции |
| Фары / стопы | `car_lights.gd` | Spot + Omni, без cookies и flare |
| Дым / пламя | `wheel_smoke.gd`, `exhaust_flame.gd` | GPUParticles, только слип и выхлоп |
| Кастомные шейдеры | — | нет ни одного `.gdshader` |

Не дублировать меню эффектов, пока Environment не настроен руками: glow/туман без HDRI и PBR-краски выглядят как «мыло».

## Порядок работ (от большого выигрыша к косметике)

```
1. Свет и небо          ← сразу «дорого»
2. PBR материалы машин/дороги
3. Отражения (пробы, не только SSR)
4. Камера и постпроцесс
5. Следы, пыль, декали
6. Мир: трава, камни, LOD
7. Погода / мокрое / ночь
```

---

## 1. Свет и небо

Сейчас небо плоское, ambient залит цветом. Гонки читаются по **контровому солнцу и отражениям в лаке**.

Сделать:

- Заменить `ProceduralSky` на **`PhysicalSkyMaterial`** (солнце, Rayleigh/Mie, ground albedo) **или** HDRI-панораму (`PanoramaSkyMaterial`, `.hdr` / `.exr` с Poly Haven).
- Связать `DirectionalLight3D` с диском солнца (угол + цвет + energy). Один скрипт «время суток»: утро / день / закат / ночь.
- `CameraAttributesPractical` на `FollowCamera` и кокпит: exposure, опционально auto-exposure. Без этого ACES часто «серый» или выжженный.
- Подкрутить fog: высота (`fog_height` / aerial perspective), цвет от неба, не серая стена. Для гор — `volumetric_fog` уже в Ultra, но density 0.02 может быть жирным; цель — дымка вдали, не молоко у капота.
- `ambient_light_source = SKY` уже ставит `GraphicsConfig` — после HDRI это заработает как надо.

Не включать SDFGI, пока у GLB нормальный albedo/metallic. Когда материалы живые — попробовать **VoxelGI** на статическом треке (печётся, стабильнее SDFGI) или SDFGI только на Ultra и с `use_occlusion`.

Файлы: `physics_test_track.tscn`, новый `rendering/day_cycle.gd`, слоты в `GraphicsConfig` (время суток, exposure).

---

## 2. Материалы (больше красоты, чем любой постэффект)

Кузов и дорога, скорее всего, приходят из GLB как «цвет + нормаль». Для лака нужно:

| Слой | Зачем |
|------|--------|
| Albedo + paint mask | перекрас в тюнинге (`visual_parts_tuning.md`) |
| Roughness / Metallic (ORM) | мокрый асфальт vs сухой, хром vs пластик |
| Normal | микродеталь без геометрии |
| **Clearcoat** + clearcoat roughness | автомобильная краска в Godot 4 (`StandardMaterial3D`) |
| Anisotropy | щёточный металл дисков |
| Emission | стопы, фары, приборка — дешёвое «светится само» |

Дорога `mountainRoad`: 2K color/normal уже лежат рядом с GLB. Добавить roughness (асфальт 0.4–0.7, мокрый ниже), AO, и **triplanar / world UV**, если швы растянуты.

Шины: отдельный материал, тёмный, roughness высокий; при деформации (`tire_deformation_physics.md`) можно крутить normal scale.

Инструмент: не писать uber-шейдер сразу. Сначала `StandardMaterial3D` / `ORMMaterial3D`. Кастомный `car_paint.gdshader` — когда понадобятся flake, two-tone, dirt overlay.

---

## 3. Отражения

SSR в Ultra уже есть, но на машине сзади камеры он слабый.

- **`ReflectionProbe`** на машине (обновлять раз в N кадров или при остановке) — зеркальный капот.
- Несколько **статических проб** вдоль дороги / в тоннеле / у скал.
- Металл дисков и лак выиграют больше, чем SSIL.

Не ставить realtime-probe каждый кадр на две машины — дорого. Режим `UPDATE_ONCE` + апдейт при смене погоды.

---

## 4. Камера и постпроцесс

`Environment` уже умеет: adjustment (яркость/контраст/saturation), glow, fog, SSAO.

Добавить поверх:

| Эффект | Как в Godot 4 | Зачем в гонке |
|--------|----------------|---------------|
| Speed FOV | скрипт на `FollowCamera` | 72 → ~80–85 на скорости |
| Motion blur | `CompositorEffect` (4.3+) или аддон | кино, только не мылить HUD |
| Vignette + grain | шейдер на `ColorRect` / compositor | чуть «плёнки», слабые значения |
| Chromatic aberration | тот же пост | только на краях и на высокой скорости |
| Color grading | `Environment.adjustment` + LUT (`gradient`/кривые) | единый look закат vs ночь |
| DOF | `CameraAttributesPractical` dof | кокпит: размытый мир; снаружи выкл |
| Sharpen | FSR sharpness уже есть | не класть FXAA+TAA+FSR вместе |

Glow: включить `glow_bloom` чуть-чуть, чтобы фары и солнце давали ореол; `glow_hdr_threshold` чтобы асфальт не светился.

Нода `Compositor` на камере / WorldEnvironment — правильное место для кастомных эффектов, не CanvasLayer на весь UI.

---

## 5. VFX машины и дороги

Уже есть дым слипа и выхлоп. Не хватает того, что мозг считает «дорогой»:

- **Декали следов** (`Decal`) по κ/α, TTL, fade. Дешевле бесконечных партиклов.
- Пыль / гравий с поверхности (когда появится surface в шинах).
- Искры при касании кузова (`soft_body_damage.md`) — короткие GPUParticles.
- Heat haze: искажение над капотом/выхлопом (экранный шейдер в маленьком quad).
- Брызги воды / мокрый шейдер дороги — после погоды.
- Cookie для фар (`SpotLight3D.light_projector`) — «соты», сразу ночь красивее.
- Lens flare солнца: осторожно, легко скатиться в 2007; лучше glare через glow.

`MultiMeshInstance3D` для камней/травы у обочины даёт плотность без тысяч нод.

---

## 6. Мир и масштаб

Камера `far = 800` на горной дороге режет горизонт. Для открытого мира (`open_world.md`):

- far 2000–4000 + fog, иначе z-fighting и пустота
- LOD мешей дороги/скал (импорт GLB: generate lods)
- Impostor / billboard дальних деревьев
- `DirectionalLight.directional_shadow_max_distance` сейчас 400 — поднять на Ultra, на Low оставить
- Scatter: камни, сосны, трава (`MultiMesh` или аддон)

Аддоны под ландшафт (не обязательно все):

- **Terrain3D** — большие холмы, splats, дыры под дорогу
- Scatter / Proton Scatter — пропы
- Готовое HDRI + Physical Sky, без своего скайбокса с нуля

---

## 7. Погода и смена кадра

Отдельный слой, когда свет и материалы готовы:

- Дождь: партиклы + wetness uniform на дороге и кузове (roughness ↓, cubemap ярче)
- Туман в долине: volumetric density по высоте
- Ночь: солнце 0, луна слабый Directional, фары уже есть — нужны emissive стёкла и фонари мира
- Грязь на кузове: вторая UV / маска, копится от бездорожья, смывается в гараже

---

## 8. Что прикрутить из коробки Godot, а что аддоном

### Уже в движке — брать первым

- `PhysicalSkyMaterial` / panorama sky
- `CameraAttributesPractical`
- `ReflectionProbe`, `Decal`, `VoxelGI`
- `StandardMaterial3D.clearcoat`, emission, detail albedo
- `GPUParticles3D` + `ParticleProcessMaterial` (turbulence уже в дыме)
- `Environment.adjustment`, glow bloom, volumetric fog
- `Compositor` + `CompositorEffect`
- Light cookies, projector
- Mesh LOD, visibility ranges (`geometry_instance.visibility_range_*`)
- `LightmapGI` только если мир статичен и без стрима; для открытого мира обычно нет

### Имеет смысл искать аддон

- Motion blur под Forward+ (пока нет кнопки в Environment)
- Terrain3D / grass scatter
- Качественный water (озёра в горах)
- LUT color grading, если встроенного adjustment мало

### Не стоит ждать от Godot

- RTX / path tracing как в AAA
- DLSS (есть FSR2 в проекте)
- SDFGI «включил и красота» на тёмных GLB — уже проверено, ломает Volga

---

## Пресеты и производительность

Не плодить новые галочки без нужды. Разложить фичи по уже существующим пресетам:

| | Low | Medium | High | Ultra |
|--|-----|--------|------|-------|
| Небо | procedural | physical | HDRI | HDRI + volumetric |
| GI | нет | нет | VoxelGI или пробы | пробы + SSIL |
| Следы | нет | декали мало | декали | декали + пыль |
| Motion blur | выкл | выкл | слабо | средне |
| Трава/scatter | нет | ближний | средний | дальний LOD |
| SDFGI | выкл | выкл | выкл | только после фикса материалов |

MSAA > 2x и SDFGI не трогать, пока не сняты текущие баги в `_sanitize_unsafe_settings`.

---

## Этапы внедрения

1. HDRI или PhysicalSky + CameraAttributes + связка солнца. Скрин «до/после» на той же трассе.
2. Clearcoat на кузове Golf/Volga, roughness асфальта.
3. ReflectionProbe на машине, cookie фар.
4. Speed FOV + лёгкий grading (contrast/saturation), glow только на фарах.
5. Decal-следы от колёс.
6. Scatter у дороги, far clip, тени дальше.
7. Motion blur / vignette через Compositor.
8. Погода и ночь.

## Файлы

- `rendering/graphics_config.gd` — только новые безопасные тумблеры
- `assets/scenes/tracks/physics_test_track.tscn` — Environment, sky, probes
- `vehicles/follow_camera.gd` — FOV, attributes
- материалы машин/трека (импорт GLB)
- `rendering/post_process.tscn` или compositor resource
- `vehicles/skid_decals.gd` (новый)
- опционально `addons/terrain_3d` — только по отдельному решению

## Приёмка

- [ ] День: небо не плоский градиент, солнце даёт блик на капоте
- [ ] Лак читается (clearcoat), пластик бампера не как хром
- [ ] Фары ночью с формой пучка, не голая точка Omni
- [ ] На скорости камера чуть шире, HUD не в motion blur
- [ ] Следы остаются на асфальте и гаснут
- [ ] Low по-прежнему играбелен без VoxelGI и blur
- [ ] Volga не чернеет (SDFGI по-прежнему выкл, пока материалы не починены)
- [ ] Сравнение скрина до/после на одном ракурсе `mountainRoad`
