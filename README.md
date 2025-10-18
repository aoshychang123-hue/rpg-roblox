# RPG Roblox

This repository contains the server-side scripts and module setup for a Roblox RPG project.

Structure
- src/ServerScriptService/Bootstrap: Startup scripts (remotes, skill replication, ability remotes).
- src/ServerScriptService/Data: Data scripts (player progress datastore).
- src/ServerScriptService/MainHandlers: Orchestration and main handlers (combat, abilities, missions, run, player data, preload).
- src/ServerScriptService/Modules: Server modules (combat, dash, abilities, weapon manager, character state).

Next
ReplicatedStorage modules will be added under src/ReplicatedStorage/Assets/Modules in follow-up commits/PRs.