# Models and renders every Delirium Heating sprite with the PZ camera:
# 16 pipes (by neighbour mask), the riser, the pump, 4 heat units, 4 radiators,
# 2 boiler houses, the water intake.
#   blender --background --factory-startup --python render_heat.py -- <out_dir> [name ...]
# Writes <out_dir>/<name>_color.png (4x) and, for the boilers, <name>_mask.png
# (which cell every pixel stands on); cut_heat.py turns them into the frames.
#
# Same PZ camera as Delirium-Mines/art/render_rock.py: ortho, elevation 30,
# azimuth 45, 90.51 px per unit at 2x. Blender x = PZ x (east), -y = PZ y
# (south), one unit is one cell; the anchor cell is x 0..1, y -1..0.
# Everything is built from primitives here: no models, no textures.
import bpy, sys, math, os
from mathutils import Vector, Euler, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = os.path.abspath(argv[0])
ONLY = argv[1:]
os.makedirs(OUT, exist_ok=True)

SCALE = 4
PX_PER_UNIT = 128 / math.sqrt(2)
R_PIPE = 1 / 12          # a pipe is a sixth of a cell across
Z_PIPE = 0.10            # its axis above the ground

sc = bpy.context.scene

# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------


def new_material(name):
    mat = bpy.data.materials.new(name)
    try:
        mat.use_nodes = True
    except Exception:
        pass
    nt = mat.node_tree
    for node in list(nt.nodes):
        nt.nodes.remove(node)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat, nt, bsdf


def paint(name, colour, rough=0.6, metal=0.0):
    mat, nt, bsdf = new_material(name)
    bsdf.inputs["Base Color"].default_value = (*colour, 1)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    return mat


def mottled(name, colour_a, colour_b, scale, rough, metal, threshold=0.5):
    # Two colours mixed by noise in world space: rust on steel, soot on paint.
    mat, nt, bsdf = new_material(name)
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = scale
    noise.inputs["Detail"].default_value = 6
    nt.links.new(geo.outputs["Position"], noise.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = threshold - 0.12
    ramp.color_ramp.elements[0].color = (*colour_a, 1)
    ramp.color_ramp.elements[1].position = threshold + 0.12
    ramp.color_ramp.elements[1].color = (*colour_b, 1)
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    return mat


def brick(name):
    # Runs along x + y, so it reads right on both walls the camera sees.
    mat, nt, bsdf = new_material(name)
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Position"], sep.inputs["Vector"])
    add = nt.nodes.new("ShaderNodeMath")
    add.operation = "ADD"
    nt.links.new(sep.outputs["X"], add.inputs[0])
    nt.links.new(sep.outputs["Y"], add.inputs[1])
    comb = nt.nodes.new("ShaderNodeCombineXYZ")
    nt.links.new(add.outputs[0], comb.inputs["X"])
    nt.links.new(sep.outputs["Z"], comb.inputs["Y"])
    tex = nt.nodes.new("ShaderNodeTexBrick")
    tex.inputs["Scale"].default_value = 2.3
    tex.inputs["Color1"].default_value = (0.36, 0.15, 0.11, 1)
    tex.inputs["Color2"].default_value = (0.47, 0.22, 0.15, 1)
    tex.inputs["Mortar"].default_value = (0.5, 0.47, 0.42, 1)
    tex.inputs["Mortar Size"].default_value = 0.025
    tex.inputs["Brick Width"].default_value = 0.5
    tex.inputs["Row Height"].default_value = 0.22
    nt.links.new(comb.outputs[0], tex.inputs["Vector"])
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.9
    return mat


M = {}


def materials():
    M["steel"] = mottled("Steel", (0.30, 0.31, 0.32), (0.34, 0.20, 0.13), 9.0, 0.55, 0.75, 0.56)
    M["dark"] = mottled("DarkIron", (0.10, 0.10, 0.11), (0.20, 0.13, 0.09), 6.0, 0.6, 0.7, 0.6)
    M["soot"] = mottled("Soot", (0.16, 0.16, 0.17), (0.07, 0.07, 0.07), 3.0, 0.75, 0.5, 0.5)
    M["cream"] = mottled("Cream", (0.66, 0.63, 0.55), (0.48, 0.42, 0.33), 14.0, 0.55, 0.0, 0.60)
    M["green"] = mottled("Green", (0.22, 0.31, 0.27), (0.30, 0.24, 0.16), 5.0, 0.55, 0.2, 0.62)
    M["blue"] = mottled("Blue", (0.11, 0.25, 0.33), (0.25, 0.20, 0.15), 8.0, 0.5, 0.3, 0.64)
    M["red"] = mottled("Red", (0.42, 0.11, 0.08), (0.24, 0.13, 0.09), 8.0, 0.55, 0.3, 0.62)
    M["concrete"] = mottled("Concrete", (0.46, 0.45, 0.42), (0.36, 0.35, 0.33), 7.0, 0.95, 0.0)
    M["white"] = paint("White", (0.85, 0.85, 0.82), 0.4)
    M["brick"] = brick("Brick")


# ---------------------------------------------------------------------------
# Primitives
# ---------------------------------------------------------------------------

made = []


def finish(obj, mat, smooth):
    obj.data.materials.append(mat)
    if smooth:
        for poly in obj.data.polygons:
            # Sides only: the caps stay flat.
            poly.use_smooth = len(poly.vertices) == 4
    made.append(obj)
    return obj


def cyl(p1, p2, radius, mat, verts=32):
    p1, p2 = Vector(p1), Vector(p2)
    axis = p2 - p1
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=axis.length,
                                        location=(p1 + p2) / 2)
    obj = bpy.context.active_object
    obj.rotation_euler = axis.to_track_quat("Z", "Y").to_euler()
    return finish(obj, mat, True)


def box(x0, x1, y0, y1, z0, z1, mat):
    bpy.ops.mesh.primitive_cube_add(size=1, location=((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2))
    obj = bpy.context.active_object
    obj.scale = (abs(x1 - x0), abs(y1 - y0), abs(z1 - z0))
    return finish(obj, mat, False)


def ball(centre, radius, mat, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=radius, location=centre)
    obj = bpy.context.active_object
    obj.scale = scale
    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    made.append(obj)
    return obj


def transform(matrix):
    bpy.context.view_layer.update()
    for obj in made:
        obj.matrix_world = matrix @ obj.matrix_world


def turn_about(centre, degrees):
    c = Vector(centre)
    return Matrix.Translation(c) @ Matrix.Rotation(math.radians(degrees), 4, "Z") @ Matrix.Translation(-c)


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------

CENTRE = Vector((0.5, -0.5, Z_PIPE))
# Arms by mask bit: north is +y in Blender. They run a little past the cell
# edge so two neighbours overlap instead of showing a seam.
ARMS = {1: Vector((0, 1, 0)), 2: Vector((1, 0, 0)), 4: Vector((0, -1, 0)), 8: Vector((-1, 0, 0))}
OVERLAP = 0.03


def build_pipe(mask):
    if mask == 0:
        # A lone piece: a short length with a band on each end.
        a, b = CENTRE + Vector((-0.3, 0, 0)), CENTRE + Vector((0.3, 0, 0))
        cyl(a, b, R_PIPE, M["steel"])
        cyl(a, a + Vector((0.05, 0, 0)), R_PIPE * 1.22, M["dark"])
        cyl(b - Vector((0.05, 0, 0)), b, R_PIPE * 1.22, M["dark"])
        return
    ball(CENTRE, R_PIPE, M["steel"])
    for bit, direction in ARMS.items():
        if mask & bit:
            cyl(CENTRE, CENTRE + direction * (0.5 + OVERLAP), R_PIPE, M["steel"])
            # A coupling band half way along the arm.
            cyl(CENTRE + direction * 0.235, CENTRE + direction * 0.285, R_PIPE * 1.2, M["dark"])
    # A straight run through needs no joint to show; a bend or a tee gets a collar.
    if mask not in (5, 10, 1, 2, 4, 8):
        ball(CENTRE, R_PIPE * 1.25, M["dark"])


def build_radiator(degrees):
    # Cast iron sections along the north edge of the cell; turned for the
    # other three walls.
    y = -0.17
    sections, x0, x1 = 10, 0.19, 0.81
    step = (x1 - x0) / (sections - 1)
    for i in range(sections):
        x = x0 + i * step
        box(x - 0.024, x + 0.024, y - 0.06, y + 0.06, 0.15, 0.62, M["cream"])
    cyl((x0 - 0.03, y, 0.585), (x1 + 0.03, y, 0.585), 0.04, M["cream"], 20)
    cyl((x0 - 0.03, y, 0.19), (x1 + 0.03, y, 0.19), 0.04, M["cream"], 20)
    for x in (x0 + step * 0.5, x1 - step * 0.5):
        box(x - 0.02, x + 0.02, y - 0.05, y + 0.05, 0.0, 0.16, M["dark"])
    # Valve, and the feed and return going down into the floor: the pipes
    # from the heat unit run out of sight.
    cyl((x1 + 0.03, y, 0.19), (x1 + 0.09, y, 0.19), 0.03, M["dark"], 16)
    ball((x1 + 0.09, y, 0.19), 0.04, M["red"])
    cyl((x1 + 0.09, y, 0.0), (x1 + 0.09, y, 0.19), 0.026, M["steel"], 16)
    cyl((x0 - 0.03, y, 0.19), (x0 - 0.08, y, 0.19), 0.03, M["dark"], 16)
    ball((x0 - 0.08, y, 0.19), 0.03, M["steel"])
    cyl((x0 - 0.08, y, 0.0), (x0 - 0.08, y, 0.19), 0.026, M["steel"], 16)
    transform(turn_about((0.5, -0.5, 0), degrees))


def build_pump():
    y, z = -0.5, 0.30
    box(0.16, 0.84, -0.70, -0.30, 0.0, 0.09, M["concrete"])
    # Motor with cooling fins.
    cyl((0.20, y, z), (0.55, y, z), 0.15, M["blue"])
    for i in range(6):
        x = 0.24 + i * 0.05
        cyl((x, y, z), (x + 0.015, y, z), 0.165, M["blue"], 32)
    cyl((0.17, y, z), (0.20, y, z), 0.11, M["dark"])
    box(0.30, 0.44, y - 0.07, y + 0.07, z + 0.13, z + 0.21, M["dark"])
    for x in (0.25, 0.50):
        box(x - 0.03, x + 0.03, y - 0.13, y + 0.13, 0.09, z - 0.08, M["dark"])
    # Coupling and the pump casing.
    cyl((0.55, y, z), (0.62, y, z), 0.06, M["steel"], 20)
    cyl((0.62, y, z), (0.75, y, z), 0.20, M["red"])
    cyl((0.75, y, z), (0.80, y, z), 0.10, M["red"])
    box(0.63, 0.74, y - 0.12, y + 0.12, 0.09, z - 0.12, M["dark"])
    # Suction from the pipe below, discharge back down to it.
    cyl((0.80, y, z), (0.86, y, z), 0.075, M["steel"], 20)
    cyl((0.86, y, z), (0.88, y, z), 0.105, M["dark"], 20)
    cyl((0.685, y, z + 0.18), (0.685, y, z + 0.30), 0.07, M["steel"], 20)
    cyl((0.685, y, z + 0.30), (0.685, y, z + 0.32), 0.10, M["dark"], 20)


def build_inlet(degrees):
    # Heat unit: a cabinet at the north edge of the cell (turned for the
    # other three walls), fed by two pipes from the main in the middle of
    # the cell, with the valves on top. The house lines leave through the
    # wall behind it.
    y = -0.19
    box(0.24, 0.76, -0.34, -0.04, 0.0, 0.06, M["concrete"])
    for x in (0.45, 0.55):
        cyl((x, -0.5, Z_PIPE), (x, y, Z_PIPE), 0.042, M["steel"], 16)
        ball((x, y, Z_PIPE), 0.042, M["steel"])
        cyl((x, y, Z_PIPE), (x, y, 0.32), 0.042, M["steel"], 16)
    box(0.29, 0.71, y - 0.11, y + 0.11, 0.30, 0.92, M["green"])
    box(0.32, 0.68, y - 0.125, y - 0.11, 0.35, 0.87, M["steel"])
    box(0.63, 0.66, y - 0.135, y - 0.125, 0.55, 0.67, M["dark"])
    cyl((0.42, y - 0.14, 0.76), (0.42, y - 0.125, 0.76), 0.055, M["white"], 24)
    cyl((0.42, y - 0.142, 0.76), (0.42, y - 0.14, 0.76), 0.062, M["dark"], 24)
    for x in (0.40, 0.60):
        cyl((x, y, 0.92), (x, y, 1.02), 0.02, M["steel"], 12)
        cyl((x, y, 1.02), (x, y, 1.04), 0.075, M["red"], 24)
    transform(turn_about((0.5, -0.5, 0), degrees))


# One level up is 192 px at 2x.
LEVEL = 192 / (PX_PER_UNIT * math.cos(math.radians(30)))


def build_riser():
    # The pipe going up to the pipe of the cell above.
    cyl(CENTRE, CENTRE + Vector((0, 0, LEVEL)), R_PIPE, M["steel"])
    for z in (0.45, 1.25, 2.05):
        cyl(CENTRE + Vector((0, 0, z)), CENTRE + Vector((0, 0, z + 0.05)), R_PIPE * 1.2, M["dark"])
    ball(CENTRE, R_PIPE * 1.25, M["dark"])


def build_intake():
    # Water intake, x 0..2, y -2..0: a well with a hatch, the standpipe out
    # of it, the pump with its motor, the control cabinet, the discharge.
    box(0.05, 1.95, -1.95, -0.05, 0.0, 0.10, M["concrete"])
    wx, wy = 0.62, -0.62
    cyl((wx, wy, 0.10), (wx, wy, 0.60), 0.44, M["concrete"], 48)
    cyl((wx, wy, 0.60), (wx, wy, 0.64), 0.38, M["dark"], 48)
    box(wx - 0.16, wx + 0.16, wy - 0.42, wy - 0.36, 0.60, 0.66, M["steel"])
    py, pz = -1.38, 0.50
    cyl((wx, wy, 0.64), (wx, wy, 1.02), 0.085, M["steel"], 24)
    ball((wx, wy, 1.02), 0.085, M["steel"])
    cyl((wx, wy, 1.02), (wx, py, 1.02), 0.085, M["steel"], 24)
    ball((wx, py, 1.02), 0.085, M["steel"])
    cyl((wx, py, 1.02), (wx, py, pz), 0.085, M["steel"], 24)
    cyl((wx, wy, 0.84), (wx, wy, 0.88), 0.12, M["dark"], 24)
    # Pump casing, coupling, motor with fins.
    box(0.40, 1.62, py - 0.27, py + 0.27, 0.10, 0.20, M["dark"])
    cyl((0.50, py, pz), (0.74, py, pz), 0.30, M["red"], 48)
    cyl((0.74, py, pz), (0.84, py, pz), 0.09, M["steel"], 20)
    cyl((0.84, py, pz), (1.50, py, pz), 0.23, M["blue"], 48)
    for i in range(9):
        x = 0.90 + i * 0.065
        cyl((x, py, pz), (x + 0.02, py, pz), 0.25, M["blue"], 48)
    cyl((1.50, py, pz), (1.56, py, pz), 0.17, M["dark"], 32)
    box(1.05, 1.27, py - 0.09, py + 0.09, pz + 0.21, pz + 0.31, M["dark"])
    # Discharge: out of the casing, down, and along the slab to the south.
    cyl((0.50, py, pz), (0.28, py, pz), 0.085, M["steel"], 24)
    cyl((0.44, py, pz), (0.47, py, pz), 0.13, M["dark"], 24)
    ball((0.28, py, pz), 0.085, M["steel"])
    cyl((0.28, py, pz), (0.28, py, 0.10 + R_PIPE), 0.085, M["steel"], 24)
    ball((0.28, py, 0.10 + R_PIPE), 0.085, M["steel"])
    cyl((0.28, py, 0.10 + R_PIPE), (0.28, -1.95, 0.10 + R_PIPE), R_PIPE, M["steel"])
    # Control cabinet on a stand, behind on the right.
    for x in (1.44, 1.70):
        box(x - 0.025, x + 0.025, -0.52, -0.47, 0.10, 0.50, M["dark"])
    box(1.36, 1.78, -0.58, -0.40, 0.50, 1.12, M["green"])
    box(1.39, 1.75, -0.595, -0.58, 0.54, 1.08, M["steel"])
    cyl((1.48, -0.61, 0.96), (1.48, -0.595, 0.96), 0.05, M["white"], 24)
    cyl((1.66, -0.61, 0.96), (1.66, -0.595, 0.96), 0.03, M["red"], 16)
    cyl((1.57, -0.49, 0.50), (1.57, -0.49, 0.16), 0.03, M["dark"], 12)
    cyl((1.57, -0.49, 0.16), (1.57, -1.11, 0.16), 0.03, M["dark"], 12)


def build_boiler(facing):
    # Front to the south: x 0..3, y -2..0. A brick furnace with the steel
    # drum on it, the chimney behind on the right, the hot water tank in
    # front of it.
    box(0.03, 2.97, -1.97, -0.03, 0.0, 0.10, M["concrete"])
    box(0.12, 2.00, -1.88, -0.12, 0.10, 1.30, M["brick"])
    box(0.08, 2.04, -1.92, -0.08, 1.30, 1.38, M["concrete"])
    # Drum on two saddles, with bands and domed ends.
    zd = 1.80
    for x in (0.55, 1.50):
        box(x, x + 0.16, -1.42, -0.58, 1.38, zd - 0.2, M["dark"])
    cyl((0.30, -1.0, zd), (1.86, -1.0, zd), 0.50, M["soot"], 48)
    for x in (0.30, 1.86):
        ball((x, -1.0, zd), 0.50, M["soot"], (0.34, 1, 1))
    for x in (0.48, 1.08, 1.68):
        cyl((x - 0.03, -1.0, zd), (x + 0.03, -1.0, zd), 0.52, M["dark"], 48)
    # Safety valve and steam pipe on top of the drum.
    cyl((1.08, -1.0, zd + 0.48), (1.08, -1.0, zd + 0.58), 0.09, M["steel"], 20)
    ball((1.08, -1.0, zd + 0.58), 0.07, M["red"])
    # Furnace doors and ash doors on the front.
    for x in (0.42, 1.22):
        box(x - 0.04, x + 0.52, -1.92, -1.88, 0.50, 1.06, M["steel"])
        box(x, x + 0.48, -1.95, -1.90, 0.54, 1.02, M["dark"])
        box(x + 0.20, x + 0.28, -1.98, -1.95, 0.74, 0.82, M["steel"])
        box(x, x + 0.48, -1.94, -1.88, 0.20, 0.38, M["dark"])
        box(x + 0.06, x + 0.42, -1.96, -1.94, 0.27, 0.31, M["steel"])
    # Chimney on a brick base, with the flue from the furnace.
    box(2.20, 2.82, -0.86, -0.24, 0.10, 0.62, M["brick"])
    box(2.17, 2.85, -0.89, -0.21, 0.62, 0.68, M["concrete"])
    cyl((2.51, -0.55, 0.68), (2.51, -0.55, 2.40), 0.19, M["soot"], 40)
    for z in (1.25, 2.33):
        cyl((2.51, -0.55, z), (2.51, -0.55, z + 0.06), 0.215, M["dark"], 40)
    cyl((1.98, -0.55, 1.02), (2.45, -0.55, 1.02), 0.15, M["soot"], 32)
    # Hot water tank with a gauge, piped to the drum.
    cyl((2.51, -1.45, 0.10), (2.51, -1.45, 1.42), 0.35, M["green"], 48)
    ball((2.51, -1.45, 1.42), 0.35, M["green"], (1, 1, 0.38))
    for z in (0.38, 1.12):
        cyl((2.51, -1.45, z), (2.51, -1.45, z + 0.05), 0.365, M["dark"], 48)
    cyl((2.51, -1.83, 0.86), (2.51, -1.79, 0.86), 0.075, M["white"], 24)
    cyl((2.51, -1.835, 0.86), (2.51, -1.83, 0.86), 0.085, M["dark"], 24)
    cyl((2.51, -1.45, 1.55), (2.51, -1.45, zd), 0.06, M["steel"], 16)
    cyl((2.51, -1.45, zd), (2.51, -1.0, zd), 0.06, M["steel"], 16)
    cyl((2.51, -1.0, zd), (2.18, -1.0, zd), 0.06, M["steel"], 16)
    ball((2.51, -1.45, zd), 0.06, M["steel"])
    ball((2.51, -1.0, zd), 0.06, M["steel"])
    # Supply and return leaving the tank at ground level.
    cyl((2.51, -1.45, Z_PIPE), (2.97, -1.45, Z_PIPE), R_PIPE, M["steel"])
    cyl((2.51, -1.45, Z_PIPE), (2.51, -1.97, Z_PIPE), R_PIPE, M["steel"])
    if facing == "E":
        # Front to the east: x 0..2, y -3..0.
        transform(Matrix.Translation(Vector((0, -3, 0))) @ Matrix.Rotation(math.radians(90), 4, "Z"))


# ---------------------------------------------------------------------------
# Scene
# ---------------------------------------------------------------------------


def clear():
    made.clear()
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh)


def stage(size, drop):
    # size: side of the square image in 2x pixels; drop: how far below the
    # image centre the centre of the anchor cell lies.
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.sensor_fit = "VERTICAL"
    cam_data.ortho_scale = size / PX_PER_UNIT
    cam_data.shift_y = drop / size
    cam_data.clip_end = 100
    cam = bpy.data.objects.new("Cam", cam_data)
    sc.collection.objects.link(cam)
    cam.rotation_euler = Euler((math.radians(60), 0, math.radians(45)))
    m3 = cam.rotation_euler.to_matrix()
    fwd, right, up = m3 @ Vector((0, 0, -1)), m3 @ Vector((1, 0, 0)), m3 @ Vector((0, 1, 0))
    cam.location = Vector((0.5, -0.5, 0)) - fwd * 30
    sc.camera = cam

    def sun(energy, direction, shadow=True):
        data = bpy.data.lights.new("Sun", "SUN")
        data.energy = energy
        data.angle = math.radians(12)
        if not shadow:
            try:
                data.use_shadow = False
            except Exception:
                pass
        obj = bpy.data.objects.new("Sun", data)
        sc.collection.objects.link(obj)
        obj.rotation_euler = (-direction.normalized()).to_track_quat("-Z", "Y").to_euler()

    sun(3.4, -right * 0.7 + up * 0.9 - fwd * 0.5)
    sun(1.3, right * 0.8 + up * 0.5 - fwd * 0.6, False)

    # The ground only takes the shadows.
    bpy.ops.mesh.primitive_plane_add(size=40, location=(0.5, -0.5, 0))
    ground = bpy.context.active_object
    ground.is_shadow_catcher = True
    r = sc.render
    r.resolution_x = size * SCALE
    r.resolution_y = size * SCALE
    return ground


def render(path, samples):
    sc.cycles.samples = samples
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


def mask_material():
    # Every surface emits the cell it stands on: R = column (PZ x), G = row
    # (PZ y), 0 / 0.214 / 1 linear = 0 / 0.5 / 1 in sRGB; cut_heat.py rounds.
    mat = bpy.data.materials.new("Mask")
    try:
        mat.use_nodes = True
    except Exception:
        pass
    nt = mat.node_tree
    for node in list(nt.nodes):
        nt.nodes.remove(node)
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Position"], sep.inputs["Vector"])
    neg = nt.nodes.new("ShaderNodeMath")
    neg.operation = "MULTIPLY"
    neg.inputs[1].default_value = -1.0
    nt.links.new(sep.outputs["Y"], neg.inputs[0])

    def cell_level(socket):
        fl = nt.nodes.new("ShaderNodeMath")
        fl.operation = "FLOOR"
        nt.links.new(socket, fl.inputs[0])
        cl = nt.nodes.new("ShaderNodeClamp")
        cl.inputs["Min"].default_value = 0.0
        cl.inputs["Max"].default_value = 2.0
        nt.links.new(fl.outputs[0], cl.inputs["Value"])
        sq = nt.nodes.new("ShaderNodeMath")
        sq.operation = "MULTIPLY"
        nt.links.new(cl.outputs[0], sq.inputs[0])
        nt.links.new(cl.outputs[0], sq.inputs[1])
        lin = nt.nodes.new("ShaderNodeMath")
        lin.operation = "MULTIPLY"
        nt.links.new(cl.outputs[0], lin.inputs[0])
        lin.inputs[1].default_value = -0.072
        out = nt.nodes.new("ShaderNodeMath")
        out.operation = "MULTIPLY_ADD"
        nt.links.new(sq.outputs[0], out.inputs[0])
        out.inputs[1].default_value = 0.286
        nt.links.new(lin.outputs[0], out.inputs[2])
        return out

    comb = nt.nodes.new("ShaderNodeCombineXYZ")
    nt.links.new(cell_level(sep.outputs["X"]).outputs[0], comb.inputs["X"])
    nt.links.new(cell_level(neg.outputs[0]).outputs[0], comb.inputs["Y"])
    comb.inputs["Z"].default_value = 1.0
    emit = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(comb.outputs[0], emit.inputs["Color"])
    outn = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(emit.outputs["Emission"], outn.inputs["Surface"])
    return mat


def shoot(name, build, size, drop, with_mask=False):
    if ONLY and name not in ONLY:
        return
    clear()
    ground = stage(size, drop)
    build()
    sc.cycles.filter_width = 1.5
    render(os.path.join(OUT, name + "_color.png"), 24)
    if with_mask:
        mask = mask_material()
        ground.is_shadow_catcher = False
        for obj in made + [ground]:
            obj.data.materials.clear()
            obj.data.materials.append(mask)
        sc.cycles.filter_width = 0.01
        render(os.path.join(OUT, name + "_mask.png"), 1)
    print("RENDERED", name)


world = bpy.data.worlds.new("W")
sc.world = world
try:
    world.use_nodes = True
except Exception:
    pass
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.3

r = sc.render
r.engine = "CYCLES"
sc.cycles.device = "CPU"
r.resolution_percentage = 100
r.film_transparent = True
r.image_settings.file_format = "PNG"
r.image_settings.color_mode = "RGBA"
sc.view_settings.view_transform = "Standard"

materials()

# One cell: a 256x256 image whose middle 128 columns are the frame; the
# cell's centre is 32 px above the frame's bottom, 96 px below the centre.
for mask in range(16):
    shoot("pipe_%d" % mask, lambda: build_pipe(mask), 256, 96)
shoot("pump", build_pump, 256, 96)
shoot("riser", build_riser, 256, 96)
for facing, degrees in (("N", 0), ("W", 90), ("S", 180), ("E", 270)):
    shoot("radiator_" + facing, lambda: build_radiator(degrees), 256, 96)
    shoot("inlet_" + facing, lambda: build_inlet(degrees), 256, 96)
# The boilers and the intake: a 384x384 image of the 3x3 cells around, as in
# Delirium-Mines.
for facing in ("S", "E"):
    shoot("boiler_" + facing, lambda: build_boiler(facing), 384, 32, True)
shoot("intake", build_intake, 384, 32, True)
