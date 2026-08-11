# Platformer-Game

A basic 2D platformer game built with Godot Engine 4.2.

## Features

- Player character with left/right movement
- Jump mechanics with gravity
- Ledge hang + climb movement flow (legacy ledge-grab snap removed)
- Multiple platforms to jump on
- Camera that follows the player
- Physics-based movement

## Controls

- **A / Left Arrow**: Move left
- **D / Right Arrow**: Move right
- **W / Space / Up Arrow**: Jump
- **While ledge hanging**: Press toward the ledge or jump to climb up

## How to Run

1. Download and install [Godot Engine 4.2](https://godotengine.org/)
2. Open Godot and click "Import"
3. Navigate to this project folder and select `project.godot`
4. Click "Import & Edit"
5. Press F5 or click the Play button to run the game

## Project Structure

- `Main.tscn` - Main game scene that combines all elements
- `Level.tscn` - Level layout with platforms
- `Player.tscn` - Player character scene
- `Player.gd` - Player movement script
- `Platform.tscn` - Reusable platform scene
- `project.godot` - Godot project configuration
