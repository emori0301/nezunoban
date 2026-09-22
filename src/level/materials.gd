class_name LevelMaterials
extends RefCounted
## 壁/床/天井のマテリアルを返す静的ヘルパ。
## assets/textures/<name>.png があればテクスチャを貼り、無ければ近い単色で代用する。
## models 担当がテクスチャを置いたら、level 側のコードを変えずに見た目が差し替わる。
##
## UV はワールド空間のトライプラナーなので「1m あたり tiles 枚」が全メッシュで揃う。
## texture_filter は PSX 風に NEAREST_WITH_MIPMAPS 固定。

const TEX_DIR := "res://assets/textures/"

## テクスチャが無いときの代用色。実物のテクスチャに近い明度にしてある。
const FALLBACK_COLORS := {
	"floor_lino": Color(0.33, 0.30, 0.27),
	"tatami": Color(0.40, 0.42, 0.26),
	"wall_plaster": Color(0.60, 0.58, 0.53),
	"wall_wood": Color(0.31, 0.23, 0.16),
	"ceiling_tile": Color(0.52, 0.51, 0.48),
	"concrete": Color(0.33, 0.33, 0.32),
	"asphalt": Color(0.085, 0.085, 0.095),
	"wood_dark": Color(0.18, 0.13, 0.09),
	"white_cloth": Color(0.85, 0.84, 0.81),
	"brocade": Color(0.46, 0.34, 0.12),
	"steel": Color(0.50, 0.52, 0.55),
}

## テクスチャに掛ける色。models のテクスチャは明るめなので、夜の建物として落とす。
const TINTS := {
	"floor_lino": 0.68,
	"ceiling_tile": 0.68,
	"wall_plaster": 0.80,
	"concrete": 0.76,
	"tatami": 0.82,
	"wall_wood": 0.86,
	"white_cloth": 0.86,
	"wood_dark": 0.88,
	"brocade": 0.88,
	"steel": 0.82,
	"asphalt": 1.0,
}

static var _cache: Dictionary = {}

## 面のマテリアル。tiles = 1m あたりのタイル数。
static func get_mat(kind: String, tiles: float = 1.0) -> StandardMaterial3D:
	var key := "%s#%.3f" % [kind, tiles]
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	var path := TEX_DIR + kind + ".png"
	if ResourceLoader.exists(path):
		mat.albedo_texture = load(path)
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = true
		mat.uv1_scale = Vector3(tiles, tiles, tiles)
		var t: float = float(TINTS.get(kind, 1.0))
		mat.albedo_color = Color(t, t, t)
	else:
		mat.albedo_color = FALLBACK_COLORS.get(kind, Color(0.5, 0.5, 0.5))
	_cache[key] = mat
	return mat

## 単色のマテリアル(小物や作り込み用)。
static func plain(color: Color, rough: float = 1.0) -> StandardMaterial3D:
	var key := "plain#%s#%.2f" % [color.to_html(false), rough]
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	_cache[key] = mat
	return mat

## 半透明(窓ガラス・障子)。
static func translucent(color: Color, alpha: float) -> StandardMaterial3D:
	var key := "glass#%s#%.2f" % [color.to_html(false), alpha]
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.4
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	_cache[key] = mat
	return mat

## 発光マテリアル(蛍光灯・自販機・ロウソク)。消灯できるように毎回新しい実体を返す。
static func emissive(color: Color, energy: float = 1.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	return mat
