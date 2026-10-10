# REAPER-Notator - Integrated MIDI Editor Manual

**Document:** Standalone Function Reference & User Guide  
**Module:** Integrated MIDI Velocity & CC Automation Drawer (`modules/ui/midi_editor_drawer.lua`)  
**Version:** 1.8.0  
**Date:** 2026-10-11  
**License:** GNU General Public License v3.0  

---

## 1. Overview & Architecture

The **Integrated MIDI Editor** in REAPER-Notator bridges traditional classical music engraving and modern DAW MIDI production. Docked directly at the bottom of the notation canvas, it provides instantaneous, bidirectional visual synchronization with Cockos REAPER's active MIDI items, takes, and continuous controllers.

```
+-----------------------------------------------------------------------------------+
|                            REAPER-NOTATOR SCORE CANVAS                            |
|       (Staves, Bravura SMuFL Glyphs, Dynamic Hairpins, Slurs & Ties, Lyrics)      |
+-----------------------------------------------------------------------------------+
| 🎹 MIDI EDITOR | CC 1 Modulation | Track 1: Violins I [Take 1] | 📈 CC 1 | ✏ Draw |
+-----------------------------------------------------------------------------------+
|  127 +-------------------------------------------------------------------------+   |
|      |                                    .-*-.                                |   |
|      |                                 .-'     '-.                             |   |
|   64 |                              .-'           '-.                          |   |
|      |                           .-'                 '-.                       |   |
|    0 +------------------------.-'-----------------------'----------------------+   |
|     Bar 1.1                  Bar 2.1                  Bar 3.1           Bar 4.1    |
+-----------------------------------------------------------------------------------+
```

### Key Architectural Strengths:
1. **Zero-Latency In-Memory Synchronization**: Edits made in the score (moving, lengthening, or inserting notes) immediately update the MIDI Editor graph. Conversely, modifications to velocities or CC points directly alter REAPER's underlying MIDI take in real time.
2. **DAW Audio Buffer Protection**: Velocity adjustments and CC curve drawing execute without causing audio dropouts, clicks, or track state glitches.
3. **Hardware-Accelerated Vector Rendering**: The editor utilizes Dear ImGui vector primitives (`ImGui_DrawList`) rasterized directly via GPU (DirectX 11, OpenGL, or Vulkan), delivering smooth 60-144 FPS responsiveness.
4. **Non-Intrusive Workflow**: Can be opened or hidden instantly with a single shortcut or mouse click, never blocking the main notation score.

---

## 2. Opening & Navigating the MIDI Editor

### 2.1 Opening the Drawer
- Click the **🎹 MIDI Editor** button in the bottom utility bar, or toggle it via the View menu.
- The editor automatically identifies the active MIDI item, take, and parent track currently focused on the score canvas.
- If no item is currently active, the editor prompts you to click any note in the score or select a MIDI item in REAPER's arrange view.

### 2.2 Header Controls & Status Badges
- **Track & Take Badge**: Displays the parent track number, user track name, track color, take name, and total note count.
- **Horizontal Zoom Controls**:
  - `－` (Zoom Out): Compresses horizontal time scaling.
  - `＋` (Zoom In): Expands horizontal time scaling for micro-timing edits.
  - `↔ Fit`: Resets horizontal zoom to comfortably fit the active MIDI item boundaries.
- **Close Button (`✕`)**: Closes the drawer and restores full vertical canvas space to the score.

---

## 3. Note Velocity Lane

The **Velocity Lane** provides visual and tactile control over MIDI Note-On velocity levels ($1$ to $127$), styled with authentic REAPER-compatible velocity stalks and flag handles (*"Fähnchen"*).

```
   127 +-------------------------------------------------------------------------+
       |             [O]                                                         |
       |              |             [O]                                          |
       |              |              |                            [O]            |
       |       [O]    |              |             [O]             |             |
       |        |     |              |              |              |             |
     0 +--------+-----+--------------+--------------+--------------+-------------+
```

### 3.1 Velocity Stalks & Flag Handles
- **Vertical Stalk**: A high-contrast vector line indicating note velocity height, positioned precisely at the musical start position (`start_qn`) of each note.
- **Flag Handle (Top Cap)**: An interactive rectangular handle atop each stalk indicating the exact velocity value. Hovering over a flag highlights it in cyan (`0x38BDF8FF`).

### 3.2 Editing Note Velocities
1. **Interactive Dragging**:
   - Click and drag any flag handle vertically to adjust velocity.
   - If multiple notes are selected, dragging one handle scales or offsets all selected velocities proportionally.
   - Real-time acoustic auditioning plays the note at the exact velocity being dragged, allowing acoustic verification of timbre and dynamic response.
2. **Pencil Draw Tool (`✏ Draw`)**:
   - Activate the Draw tool in the toolbar.
   - The mouse cursor transforms into a high-contrast vector pencil.
   - Click and sweep across the lane horizontally to paint smooth velocity arcs across consecutive notes in a single gesture.
3. **Marquee Box Selection**:
   - In Select mode (`↖ Select`), click and drag over empty space in the lane to draw a selection rectangle. All notes whose stalks or flags intersect the box are selected.

### 3.3 Dynamic Velocity Presets
Five instantaneous buttons in the toolbar allow one-click velocity quantization across selected notes (or all notes if none are selected):
- **`pp` (Pianissimo)**: Sets velocity to `32`.
- **`mp` (Mezzo-piano)**: Sets velocity to `64`.
- **`mf` (Mezzo-forte)**: Sets velocity to `80`.
- **`f` (Forte)**: Sets velocity to `96`.
- **`ff` (Fortissimo)**: Sets velocity to `112`.

### 3.4 Velocity Transformation Tools
- **📈 Linear Ramp**: Select two or more notes across a passage and click **Ramp**. The engine calculates a mathematically linear progression between the velocity of the first note and the velocity of the last note.
- **🎲 Humanize**: Click **Humanize** to apply a subtle, natural variation ($\pm 7$ velocity units) across selected notes. This introduces organic acoustic realism to mechanical quantized passages without breaking musical balance.

---

## 4. 128 Continuous Controller (CC) Automation Lanes

REAPER-Notator includes complete support for all **128 MIDI CC channels** ($CC\ 0$ through $CC\ 127$).

### 4.1 Lane Selection Dropdown
Click the lane combo box next to the track badge to choose any controller. Frequently used controllers are clearly annotated:
- **CC 1**: Modulation Wheel (Vibrato / Dynamic Layer)
- **CC 2**: Breath Controller
- **CC 7**: Channel Volume
- **CC 10**: Pan Position
- **CC 11**: Expression Controller
- **CC 64**: Sustain / Damper Pedal
- **CC 65**: Portamento On/Off
- **CC 66**: Sostenuto Pedal
- **CC 67**: Soft Pedal (Una Corda)
- **CC 71**: Resonance / Timbre
- **CC 74**: Frequency Cutoff / Brightness

### 4.2 Interactive CC Curve Drawing
- **Pencil Draw Tool (`✏ Draw`)**:
  - Click and drag across the timeline to draw organic, high-resolution continuous controller curves.
  - Generates smooth CC event streams synchronized with REAPER's PPQ resolution.
- **Node Selection & Editing (`↖ Select`)**:
  - Click any CC point node to select it.
  - Drag nodes vertically to alter value ($0$ to $127$) or horizontally to adjust musical timing.
  - **Insert Node**: Double-click anywhere along the lane to insert a new CC point.
  - **Delete Node**: Right-click any CC node, or select nodes and press `Delete` / `Backspace`.
  - **Marquee Selection**: Drag a rectangular bounding box across multiple CC nodes to select and transform them together.

### 4.3 REAPER CC Curve Shapes & Anti-Step Technology
Standard MIDI controllers often suffer from staircase artifacts (*"Treppenstufen"*) when drawn in primitive editors. REAPER-Notator natively writes REAPER CC curve envelope flags directly to the take:
- **📈 Linear (Ramp) [Default]**: Connects adjacent CC nodes with smooth linear interpolation slopes. Eliminates stepped zipper noise.
- **⎍ Square (Step)**: Holds values constant until the next node (classic step envelope).
- **〰 Slow Start / End (S-Curve)**: Smooth sinusoidal ease-in and ease-out interpolation.
- **⚡ Fast Start**: Exponential decay curve.
- **⏳ Fast End**: Logarithmic rise curve.
- **∿ Bézier**: Smooth Bézier cubic curvature.

> [!TIP]
> **Convert All to Linear**: If you imported a legacy MIDI take containing staircase CC steps, click **📈 Convert All to Linear** in the toolbar. REAPER-Notator will instantly iterate through all CC events in the active lane and convert their curve shapes to smooth linear ramps.

### 4.4 Quick Level Stamps & Clear
- **Levels (0, 32, 64, 96, 127)**: Click any level button to immediately stamp a flat continuous CC value across the entire length of the active MIDI item.
- **🗑 Clear CC**: Completely purges all CC events of the active controller number from the take, resetting the lane to empty.

---

## 5. Dynamic CC Shaping Protection & Bypass Lock

Modern orchestral sample libraries (Spitfire Audio, Orchestral Tools, Cinematic Studio Series, Vienna Symphonic Library) rely heavily on continuous dynamic modulators—typically **CC 1 (Modulation)** for dynamic layer crossfading and **CC 11 (Expression)** for musical volume swells.

REAPER-Notator features an intelligent **Dynamic CC Shaping Protection** system to safeguard your score dynamics:

```
[ Dynamic Engine Active ] ---> Locks CC 1 & CC 11 ---> "🔒 CC 1 Locked (Dynamic Shaping)"
                                                                   |
                                              [ 🔓 Unlock (Enable Bypass) ]
                                                                   v
                                                     "Manual CC Drawing Enabled"
```

### 5.1 How the Lock Works
- When the score's automated Dynamics Engine is generating dynamics from score hairpins ($cresc.$, $dim.$, $p$, $f$), the corresponding controllers (by default CC 1 and CC 11) are automatically locked.
- The lane selector displays a padlock icon: `🔒 CC 1 [Dynamic A]` or `🔒 CC 11 [Dynamic B]`.
- Manual mouse drawing is disabled, preventing accidental pencil strokes from overwriting hours of carefully crafted orchestral phrasing.

### 5.2 1-Click Unlock / Bypass
- To override automatic dynamics and manually draw custom CC curves on an item:
  1. Select the locked lane.
  2. Click **🔓 Unlock (Enable Bypass)** in the toolbar.
  3. The lock is immediately released for this specific MIDI item, allowing full manual pencil and marquee editing.

---

## 6. Visual Theme & Color Customization

The MIDI Editor's color scheme is fully configurable to match your monitor and studio environment. Open **⚙ Settings -> MIDI Editor Colors** to adjust:

| Color Property | Default Hex | Description |
| :--- | :--- | :--- |
| **`midi_bg`** | `#181A20` | Outer pane and toolbar background |
| **`midi_lane_bg`** | `#121418` | Graph canvas background |
| **`midi_grid_major`** | `#4A5568` | Barline and measure downbeat grid lines |
| **`midi_grid_minor`** | `#334155` | Sub-beat division grid lines |
| **`midi_vel_stalk`** | `#64748B` | Unselected velocity stalk line |
| **`midi_vel_flag`** | `#94A3B8` | Unselected velocity handle flag |
| **`midi_vel_sel`** | `#FF9F1C` | Selected velocity stalk and flag highlight |
| **`midi_vel_hov`** | `#38BDF8` | Mouse-hovered velocity handle highlight |
| **`midi_cc_line`** | `#38BDF8` | Continuous CC curve interpolation stroke |
| **`midi_cc_fill`** | `#38BDF828` | Semi-transparent area fill beneath CC curve |
| **`midi_cc_node`** | `#7DD3FC` | CC control point circles |
| **`midi_cc_locked`** | `#64748B` | Disabled / locked CC curve tint |

---

## 7. Keyboard & Mouse Quick Reference

| Action | Input / Shortcut | Context |
| :--- | :--- | :--- |
| **Select / Move Flag** | Left-Click & Drag | Velocity Lane (`Select` Tool) |
| **Audition Note** | Left-Click Flag Handle | Velocity Lane |
| **Multi-Select Notes** | Marquee Box Drag | Velocity Lane (`Select` Tool) |
| **Freehand Velocity Draw** | Left-Click & Sweep | Velocity Lane (`Draw` Tool) |
| **Draw CC Curve** | Left-Click & Drag | CC Lane (`Draw` Tool) |
| **Move CC Points** | Left-Click & Drag Nodes | CC Lane (`Select` Tool) |
| **Insert CC Point** | Double-Click Lane | CC Lane (`Select` Tool) |
| **Delete CC Point** | Right-Click Node | CC Lane |
| **Delete Selected CC** | `Delete` / `Backspace` | CC Lane with selected points |
| **Horizontal Zoom** | `+` / `-` Toolbar Buttons | All Lanes |
| **Reset Zoom (Fit)** | `↔ Fit` Toolbar Button | All Lanes |
| **Toggle Drawer** | Bottom Utility Bar | Score Canvas |
