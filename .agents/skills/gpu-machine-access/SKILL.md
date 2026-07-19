---
name: gpu-machine-access
description: Connect to and safely operate a configured remote GPU machine over SSH. Use when Codex is asked to inspect GPU availability or health, run NVIDIA or AMD GPU diagnostics, check drivers and accelerator runtimes, monitor workloads, diagnose resource issues, or perform explicitly requested maintenance on a GPU host.
---

# GPU Machine Access

## Configure the Target

Use the local helper and configuration files from the repository root:

- Helper: `.agents/skills/gpu-machine-access/scripts/connect-gpu-machine.sh`
- Local configuration: `.agents/skills/gpu-machine-access/.gpu-machine.env`
- Configuration template: `.agents/skills/gpu-machine-access/.gpu-machine.env.example`

Prefer an SSH key or an SSH config alias. Verify a new host's SSH fingerprint through a trusted channel before accepting it. Never write passwords, tokens, API keys, or session secrets into tracked files, command arguments, logs, or final responses.

If the local configuration file is missing, create it from the template and restrict its permissions:

```bash
cp .agents/skills/gpu-machine-access/.gpu-machine.env.example \
  .agents/skills/gpu-machine-access/.gpu-machine.env
chmod 600 .agents/skills/gpu-machine-access/.gpu-machine.env
```

Set these values in `.gpu-machine.env`:

- `GPU_MACHINE_SSH_TARGET` (required): an SSH config alias, hostname, IP address, or `user@host` target.
- `GPU_MACHINE_SSH_PORT` (optional): a non-default SSH port.
- `GPU_MACHINE_SSH_IDENTITY_FILE` (optional): the SSH private key path, such as `~/.ssh/id_ed25519_github`.
- `GPU_MACHINE_REMOTE_DIR` (optional): the directory to enter after connecting. Leave empty to use the remote login directory.
- `GPU_MACHINE_SSH_PASSWORD` (optional): a local fallback for `sshpass`; prefer key-based authentication.

Use `GPU_MACHINE_ENV_FILE` to load a configuration file from a different local path.

## Connect

Open an interactive shell:

```bash
.agents/skills/gpu-machine-access/scripts/connect-gpu-machine.sh
```

Run one command on the remote machine:

```bash
.agents/skills/gpu-machine-access/scripts/connect-gpu-machine.sh \
  'hostname && whoami && pwd'
```

The helper loads the trusted local Bash configuration in `.gpu-machine.env`, uses `GPU_MACHINE_SSH_IDENTITY_FILE` when configured, enters `GPU_MACHINE_REMOTE_DIR` when configured, and then runs the requested command. If `GPU_MACHINE_SSH_PASSWORD` is set and `sshpass` is installed, it supplies the password through the environment. Otherwise, normal SSH authentication and host-key policy apply.

## Operate Safely

1. Treat the machine as shared and stateful unless the user says otherwise.
2. Start with read-only inspection unless the user explicitly requests a change.
3. Detect the GPU vendor and installed tooling before assuming NVIDIA/CUDA or AMD/ROCm.
4. Before stopping a process, resetting a GPU, restarting a service, or changing drivers, identify affected users, containers, jobs, and workloads.
5. Keep commands scoped to the requested files, processes, containers, or jobs.
6. Do not start benchmarks, training jobs, or other GPU-intensive work unless the user explicitly requests it.
7. Do not run destructive commands, delete data, discard Git changes, or alter system packages unless the user explicitly requests that exact operation.
8. Report the commands run and the operational result, omitting secrets and full credential-bearing environment output.

## Start With Read-Only Checks

Use only checks relevant to the task. Identify the accelerator before running vendor-specific commands:

```bash
.agents/skills/gpu-machine-access/scripts/connect-gpu-machine.sh \
  'hostname; uname -a; command -v nvidia-smi || true; command -v rocm-smi || true'
```

For NVIDIA GPUs:

```bash
.agents/skills/gpu-machine-access/scripts/connect-gpu-machine.sh 'nvidia-smi'
.agents/skills/gpu-machine-access/scripts/connect-gpu-machine.sh \
  'nvidia-smi --query-gpu=index,name,uuid,driver_version,memory.total,memory.used,utilization.gpu,temperature.gpu --format=csv'
```

For AMD GPUs:

```bash
.agents/skills/gpu-machine-access/scripts/connect-gpu-machine.sh 'rocm-smi'
```

For host capacity and active work:

```bash
.agents/skills/gpu-machine-access/scripts/connect-gpu-machine.sh \
  'uptime; free -h; df -h; ps -eo user,pid,ppid,etimes,%cpu,%mem,command --sort=-%cpu | head -n 25'
```

Inspect the machine's actual scheduler, container runtime, service manager, and workload layout before choosing deeper diagnostic or maintenance commands.
