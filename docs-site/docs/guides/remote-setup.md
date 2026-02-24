---
sidebar_label: Remote Setup
---

# Remote Dev Server Setup

Use NoCrumbs with Claude Code on a remote dev server. All prompt-to-commit linkage flows back to the Mac app over an SSH tunnel.

## Prerequisites

- NoCrumbs installed on your Mac (`brew install --cask geneyoo/tap/nocrumbs`)
- SSH access to your remote server (`ssh myserver` works without password prompts)

## One-Command Setup

From your Mac:

```bash
nocrumbs setup-remote myserver
```

This single command:

1. **Copies the CLI binary** to `~/.local/bin/nocrumbs` on the remote
2. **Sets `NOCRUMBS_HOST=localhost`** in the remote shell profile (`.zshrc`, `.bashrc`, or `config.fish`)
3. **Installs Claude Code hooks** on the remote (`nocrumbs install --remote`)
4. **Adds `RemoteForward`** to your local `~/.ssh/config`
5. **Enables the TCP listener** on your Mac (port 19876)

After it completes, SSH into your server and start a Claude Code session — events flow to your Mac automatically.

## How It Works

```
Remote Server                          Your Mac
┌──────────────────┐    SSH Tunnel    ┌──────────────────┐
│ Claude Code      │                  │                  │
│   ↓ hooks        │                  │                  │
│ nocrumbs CLI     │───────────────→  │ TCP :19876       │
│ (localhost:19876)│  RemoteForward   │   ↓              │
│                  │                  │ NoCrumbs.app     │
│                  │                  │   ↓              │
│                  │                  │ SQLite DB        │
└──────────────────┘                  └──────────────────┘
```

The CLI on the remote sends events to `localhost:19876`. SSH's `RemoteForward` tunnels that port back to your Mac, where NoCrumbs listens on TCP 19876.

## Manual Setup

If you need to configure things individually (custom environments, non-standard SSH setups):

### 1. Copy the CLI

```bash
scp /Applications/NoCrumbs.app/Contents/Resources/nocrumbs myserver:~/.local/bin/nocrumbs
ssh myserver 'chmod +x ~/.local/bin/nocrumbs'
```

Or build from source:

```bash
# On the remote server
git clone https://github.com/geneyoo/nocrumbs.git
cd nocrumbs && swift build -c release --package-path CLI/
cp .build/release/nocrumbs ~/.local/bin/
```

### 2. Set Environment Variable

Add to your remote shell profile:

```bash
# .zshrc or .bashrc
export NOCRUMBS_HOST=localhost
```

### 3. Install Hooks

```bash
# On the remote
nocrumbs install --remote
```

### 4. Configure SSH Tunnel

Add to `~/.ssh/config` on your Mac:

```
Host myserver
    RemoteForward 19876 localhost:19876
```

### 5. Enable TCP Listener

In the NoCrumbs Mac app: **Settings > Accept remote connections** and set the port to `19876`.

Or via the command line:

```bash
defaults write com.geneyoo.nocrumbs remoteTCPPort -int 19876
```

## Troubleshooting

### Verify the tunnel is active

While connected via SSH to the remote:

```bash
nc -zw1 localhost 19876 && echo "Tunnel OK" || echo "Tunnel down"
```

### Port already in use

```bash
# On your Mac — check what's using port 19876
lsof -i :19876
```

If another process holds the port, either stop it or choose a different port:

```bash
# Mac
defaults write com.geneyoo.nocrumbs remoteTCPPort -int 19877

# Remote ~/.ssh/config
Host myserver
    RemoteForward 19877 localhost:19877

# Remote shell profile
export NOCRUMBS_PORT=19877
```

### Broken pipe / disconnected tunnel

SSH tunnels drop when the connection closes. Reconnect with `ssh myserver`. For persistent connections, consider:

- **`autossh`** — automatically reconnects SSH sessions
- **`ServerAliveInterval 60`** in your SSH config to prevent idle disconnects

```
Host myserver
    RemoteForward 19876 localhost:19876
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

### Events not appearing in NoCrumbs

1. Check the CLI is on PATH: `which nocrumbs`
2. Check hooks are installed: `cat ~/.claude/settings.json | grep nocrumbs`
3. Check the env var: `echo $NOCRUMBS_HOST` (should be `localhost`)
4. Check tunnel: `nc -zw1 localhost 19876`
5. Check Mac listener: open NoCrumbs Settings and verify TCP listener is enabled

### Re-running setup

`setup-remote` is idempotent — safe to run again. It skips steps already configured.

```bash
nocrumbs setup-remote myserver
```
