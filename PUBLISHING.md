# Publishing guide: itch.io and GitHub

Everything is ready to upload. Before publishing, put your name in the credits (step 0).

---

## 0. Put your name in the game (2 minutes)

The credits currently say **"Shift Worlds Team"**. To use your own name, replace that text in these files:

| File | What to change |
|---|---|
| `scripts/game.gd` | `const AUTHOR := "Shift Worlds Team"` (shown on the in-game credits screen) |
| `export_presets.cfg` | `company_name`, `copyright` (Windows .exe properties and macOS bundle) |
| `LICENSE`, `CREDITS.md`, `README.md`, `itch/ITCH_PAGE.md` | Copyright and credit lines |

Then export again (step 1). If you keep "Shift Worlds Team", you can skip this.

---

## 1. Rebuild (only needed after you change something)

1. Install **Godot 4.5.1** from https://godotengine.org/download (standard, not .NET).
2. Open `project.godot`, then go to **Editor → Manage Export Templates → Download and Install**.
3. Go to **Project → Export...**, select **Windows Desktop**, then **Export Project...** and save to `build/windows/ShiftWorlds.exe`.
   Leave **Export With Debug** unchecked. Do the same for **Linux** if you want.
4. Make the ZIP: put `ShiftWorlds.exe`, `README.txt`, `LICENSE.txt`, `CREDITS.txt` and
   `THIRD_PARTY_LICENSES.txt` in one folder and zip it as `ShiftWorlds-v1.0.0-windows.zip`.
   The ready-made ZIPs in `dist/` already have this layout.

Always test the exported `.exe` by double-clicking it, not only by pressing Play in the editor.

---

## 2. Publish on itch.io

1. Create a free account at https://itch.io and open **Dashboard → Create new project**.
2. Fill in the form from `itch/ITCH_PAGE.md`: title, URL, short description, classification, genre, tags and description.
3. **Kind of project:** *Downloadable*. **Pricing:** *No payments* or *$0 or donate*.
4. **Uploads:** click *Upload files* and add `dist/ShiftWorlds-v1.0.0-windows.zip`. Tick **Windows**.
   Add the Linux ZIP and tick **Linux**. The macOS ZIP is optional; tick **macOS** and call it "experimental, unsigned".
5. **Cover image:** `itch/cover.png`. **Screenshots:** all files in `itch/screenshots/`.
6. **Edit theme** (top of the page view): set the banner to `itch/banner.png`, background `#0a0612`, links `#4fc3ff`.
7. **AI disclosure:** itch.io asks whether the project uses generative AI. This game was built with an AI coding
   assistant (code, procedurally generated art and audio). Answer the question honestly according to how you
   made it. The Game Off rules may also ask about this.
8. Set **Visibility** to *Draft* and press **Save**. Then open the page and test the download yourself:
   download, extract, run.
9. When everything works, change Visibility to **Public** and save.

### Optional: upload from the command line with butler
butler uploads only what changed and makes the game installable through the itch.io app.
```bash
# one-time setup: https://itch.io/docs/butler/
butler login
butler push dist/ShiftWorlds-v1.0.0-windows.zip <your-itch-username>/shift-worlds:windows --userversion 1.0.0
butler push dist/ShiftWorlds-v1.0.0-linux.zip   <your-itch-username>/shift-worlds:linux   --userversion 1.0.0
```

### Submitting to GitHub Game Off 2026
1. Open the jam page at https://itch.io/jam/game-off-2026 and click **Submit your project**.
2. Choose your SHIFT WORLDS itch.io page.
3. Game Off requires **public source code on GitHub**. Paste your repository URL (section 3) into the submission form.
4. Submit before the deadline shown on the jam page.

---

## 3. Publish the source code on GitHub

### With the GitHub website (no command line)
1. Sign in at https://github.com, click **+ → New repository**, name it `shift-worlds`, set it to **Public**,
   and leave "Add a README" unchecked. Click **Create repository**.
2. Click **uploading an existing file**. Extract `dist/ShiftWorlds-v1.0.0-source.zip` and drag **all of its contents**
   into the page (including the `scripts`, `scenes`, `assets` and `audio` folders). Commit.

### With git (command line)
```bash
cd shift-worlds                      # the extracted source folder
git init
git add .
git commit -m "SHIFT WORLDS v1.0.0"
git branch -M main
git remote add origin https://github.com/<your-username>/shift-worlds.git
git push -u origin main
```
`.gitignore` already keeps out the `.godot/` cache and the `build/` and `dist/` folders.

### Create a release with the downloads
1. On the repository page, click **Releases → Draft a new release**.
2. Tag: `v1.0.0`. Title: `SHIFT WORLDS v1.0.0`. Paste the 1.0.0 section of `CHANGELOG.md` as the description.
3. Attach `ShiftWorlds-v1.0.0-windows.zip`, `-linux.zip` and `-macos.zip` from `dist/`. Click **Publish release**.
4. Optional: in **Settings → General → Social preview**, upload `itch/social_preview.png`.
5. Optional: add the topics `godot`, `game-off`, `puzzle-platformer`, `pixel-art`, `gamedev`.

Then add the release link to your itch.io description, and the itch.io link to the GitHub README.

---

## Checklist before you announce it
- [ ] Your name is in the credits (step 0), or you are happy with "Shift Worlds Team"
- [ ] Downloaded the ZIP from your own itch.io page, extracted it, and played the first level
- [ ] itch.io page: cover, screenshots, controls and system requirements are shown
- [ ] GitHub repository is public and has the README, LICENSE and a v1.0.0 release
- [ ] Game Off submission links both pages
