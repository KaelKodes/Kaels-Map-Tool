# Kaels Map Tool
![Kael's Map Tool Banner](https://i.imgur.com/3wv43Z2.png)

Upload a map image and annotate it together with friends — markers, layers, notes, and pings — in real time.

My friends and I always felt like we needed a more interactive map for the games we play: something that lets us drop in a map image and edit it together, at the same time. Kaels Map Tool works great as a second-screen map while you play — plan routes, mark loot, call out enemies, and ping locations for everyone to see.

Built with **Godot 4.6**. Current version: **[A0.0.1](https://github.com/KaelKodes/Kaels-Map-Tool/releases/tag/A0.0.1)**.

## Download

**Use the exported build** — that is the intended way to run Kaels Map Tool.

1. Go to **[Releases](https://github.com/KaelKodes/Kaels-Map-Tool/releases)** and download **A0.0.1** for your platform.
2. Extract and run the app. No Godot install required.

Everyone in a session should use the **same release version** when playing together.

<details>
<summary>Running from source (developers only)</summary>

Clone this repo and open it in [Godot 4.6](https://godotengine.org/) if you are contributing or testing unreleased changes. Players should use the release build above instead.

</details>

## Features

### Layers
Organize markers into layers for different categories (enemy bases, rare loot, notes, and more). Show or hide any layer whenever you want.

### Markers
Place markers on the map and style them with icons and size. Click a marker to open the **Notes** panel — add a title and write notes for that spot. Marker color comes from its layer.

### Pings
Hold **Ctrl** and click the map to send a ping. Everyone sees an expanding ring in your color — handy for quick callouts during a session.

### Host and Join
One person **Hosts** the session; everyone else **Joins** with the host's IP address. Up to **4 people** can edit the same map together in real time. The host runs a built-in relay server (port **9090**).

- **Same network (LAN):** join using the host's local IP shown in the toolbar.
- **Over the internet:** join using the host's public IP. The host may need port **9090** forwarded on their router.

### Save and Load
Save your work as a `.kmap` file (map image + layers, markers, and notes). Open it later or share the file with your group.

## Getting Started

1. **Download** the latest [release](https://github.com/KaelKodes/Kaels-Map-Tool/releases) and run the app.
2. Click **New Map** to upload a map image.
3. Use **Add Marker** to place markers, then click them to edit notes.
4. To play together: one person clicks **Host**, others enter the host IP and click **Join**.

## Controls

| Action | Input |
|--------|--------|
| Pan map | Middle mouse drag, or right mouse drag |
| Zoom | Mouse wheel |
| Place marker | **Add Marker**, then click the map |
| Ping | **Ctrl** + click |
| Select marker | Left click |

## Project Layout

```
scenes/          Main UI scene
scripts/         Map canvas, session state, networking, save/load
server/          Optional standalone Python relay (host-embedded relay is default)
```

## License

This project uses the [Kaels Map Tool License](LICENSE).

- **Use and share** unmodified copies freely.
- **Changes** should go through the [official repo](https://github.com/KaelKodes/Kaels-Map-Tool) as branches and pull requests — not as separate public forks or spin-offs.
- **Feature ideas** are best submitted as [issues](https://github.com/KaelKodes/Kaels-Map-Tool/issues) so they can be added officially.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full contribution workflow.

This is a **source-available** license (not OSI “open source”). It keeps the project centralized while still letting friends and communities use and pass around the app.
