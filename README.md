# Roblox update alerts on GitHub Actions

The bot checks Roblox Windows Player every five minutes. It announces a newer build seen in public deployment history and separately announces changes to LIVE. Early sightings do not predict a release date.

## Set up once

1. Create a new **public** repository at https://github.com/new. Use a dedicated repository for this bot. Leave README, .gitignore, and license initialization unchecked.
2. Run the deployment command from Windows PowerShell and paste the empty repository URL when asked. Git may ask you to sign in to GitHub. Only the standalone bot files are published.
3. In the repository, open **Settings → Secrets and variables → Actions → New repository secret**. Name it **DISCORD_BOT_TOKEN** and paste the current bot token as its value.
4. In **Actions → Roblox update alerts**, choose **Run workflow** on the default branch. The first run should post the current LIVE build and any newer build to channel **1567254518796648468**. Ensure the bot is installed in the server and has View Channel and Send Messages there.

Use this command to publish from the Codex workspace:

```powershell
powershell -NoProfile -File "C:\Users\Administrator\Downloads\roblox-base (1)\tools\roblox-update-bot\deploy.ps1"
```

A standard GitHub-hosted runner in a public repository is free under current terms. Your PC can be off. Scheduled runs can be delayed or dropped, and GitHub may disable schedules after 60 days with no repository activity. Re-enable the workflow from the Actions tab if that happens. The workflow records delivered versions in a small state file and commits changes after successful posts. Keep the repository free of unrelated project files or secrets.

For a local preview, run `pwsh -NoProfile -File ./watch.ps1 -DryRun -Once` with PowerShell 7. This checks Roblox without posting or saving state.
