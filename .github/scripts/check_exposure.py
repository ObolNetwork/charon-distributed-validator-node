#!/usr/bin/env python3
"""Fails if the default configuration exposes more than the P2P ports to the internet.

- Every port published by a top-level compose file must, with its default values, either bind to
  a loopback address or be a P2P port. Example ports in *.sample files must bind to 127.0.0.1 too.
- Anonymous Grafana users must not get more than the Viewer role.
- Grafana must not accept passwords, neither through the login form and POST /login nor through
  HTTP basic auth on its API. Compose files must not configure Grafana with GF_* variables or an
  env_file, since those override grafana.ini.
- Grafana must only join the monitoring network, so it cannot reach charon, the clients or the ejector.
- Grafana must mount files from this repository read-only, so it cannot change its own provisioning.
- Only the Docker socket proxy may mount the Docker socket.
- Outside compose-debug.yml, no service may run privileged or share the host's network or PID namespace.
"""

import configparser
import glob
import re
import sys

import yaml

# Container ports that must be reachable by peers: EL, CL (incl. Prysm's 13000/12000) and charon.
P2P_PORTS = {"30303", "9000", "12000", "13000", "3610"}
LOOPBACK = {"127.0.0.1", "::1", "[::1]"}
SOCKET_PROXY = "docker-socket-proxy"
DEBUG_FILES = {"compose-debug.yml"}


def compose_files():
    """Yields (path, services) for every top-level compose file."""
    for path in sorted(glob.glob("*.yml") + glob.glob("*.yaml")):
        with open(path) as f:
            compose = yaml.safe_load(f) or {}
        yield path, {name: service or {} for name, service in (compose.get("services") or {}).items()}


def expand_defaults(value):
    """Replaces ${VAR:-default} with the default, and ${VAR} with an empty string."""
    return re.sub(r"\$\{\w+(?::-([^}]*))?\}", lambda m: m.group(1) or "", value)


def check_port(where, port):
    """Returns an error if the port is published on all interfaces by default and is not a P2P port."""
    if not isinstance(port, str):
        return f"{where}: use the short port syntax so this check can read it: {port}"
    if re.search(r"\$\{\w+-", port):
        # ${VAR-default} keeps an empty VAR= from .env, which publishes on all interfaces.
        return f"{where}: '{port}' uses ${{VAR-default}}; use ${{VAR:-default}} so an empty value keeps the default"
    parts = expand_defaults(port).split("/")[0].rsplit(":", 2)
    host_ip = parts[0] if len(parts) == 3 else ""
    if host_ip in LOOPBACK or parts[-1] in P2P_PORTS:
        return None
    return f"{where}: '{port}' is published on all interfaces by default; bind it to 127.0.0.1"


def check_ports():
    errors = []
    for path, services in compose_files():
        for name, service in services.items():
            for port in service.get("ports") or []:
                errors.append(check_port(f"{path}: {name}", port))
    return [error for error in errors if error]


def check_sample_ports():
    """Returns errors for commented-out example ports in *.sample files that would publish on all interfaces."""
    errors = []
    for path in sorted(glob.glob("*.sample")):
        with open(path) as f:
            for number, line in enumerate(f, 1):
                match = re.match(r"\s*#?\s*-\s*['\"]?([^\s'\"#]+:\d+(?:/\w+)?)", line)
                if match:
                    errors.append(check_port(f"{path}:{number}", match.group(1)))
    return [error for error in errors if error]


# Grafana settings that, with their GF_* environment variable, must keep password logins off.
GRAFANA_REQUIRED = {
    ("auth", "disable_login_form"): "true",
    ("auth.basic", "enabled"): "false",
}


def check_grafana():
    ini = configparser.ConfigParser(interpolation=None)
    ini.read("grafana/grafana.ini")
    errors = []
    anonymous = ini["auth.anonymous"] if ini.has_section("auth.anonymous") else {}
    if anonymous.get("enabled", "false").lower() == "true" and anonymous.get("org_role", "Viewer") != "Viewer":
        errors.append(f"grafana/grafana.ini: anonymous users get the {anonymous['org_role']} role; use Viewer")
    for (section, key), want in GRAFANA_REQUIRED.items():
        if ini.get(section, key, fallback="").lower() != want:
            errors.append(f"grafana/grafana.ini: set [{section}] {key} = {want} so Grafana does not accept passwords")
    return errors


def check_grafana_service():
    """Returns errors for compose files that configure Grafana around grafana.ini, join it to other networks or mount it writable."""
    errors = []
    for path, services in compose_files():
        grafana = services.get("grafana")
        if grafana is None:
            continue
        env = grafana.get("environment") or {}
        keys = env.keys() if isinstance(env, dict) else [item.split("=")[0] for item in env]
        errors += [f"{path}: grafana sets {key}; configure Grafana in grafana/grafana.ini" for key in keys if key.startswith("GF_")]
        if grafana.get("env_file"):
            errors.append(f"{path}: grafana has an env_file, which can override grafana.ini; remove it")
        networks = grafana.get("networks")
        if networks is not None and list(networks) != ["monitoring"]:
            errors.append(f"{path}: grafana joins {list(networks)}; it must only join the monitoring network")
        for volume in grafana.get("volumes") or []:
            if isinstance(volume, dict):
                source, read_only = str(volume.get("source", "")), volume.get("read_only", False)
            else:
                source, read_only = volume, volume.endswith(":ro")
            if source.startswith(".") and not read_only:
                errors.append(f"{path}: grafana mounts '{source}' writable; make it read-only")
    return errors


def check_privileges():
    """Returns errors for Docker socket mounts outside the socket proxy, and for privileged or host-namespace services."""
    errors = []
    for path, services in compose_files():
        for name, service in services.items():
            for volume in service.get("volumes") or []:
                source = str(volume.get("source", "")) if isinstance(volume, dict) else volume.split(":")[0]
                if source.endswith("docker.sock") and name != SOCKET_PROXY:
                    errors.append(f"{path}: {name} mounts the Docker socket; go through {SOCKET_PROXY}")
            if path in DEBUG_FILES:
                continue
            if service.get("privileged"):
                errors.append(f"{path}: {name} runs privileged")
            for key in ("network_mode", "pid", "ipc"):
                if service.get(key) == "host":
                    errors.append(f"{path}: {name} sets {key}: host")
    return errors


def main():
    errors = check_ports() + check_sample_ports() + check_grafana() + check_grafana_service() + check_privileges()
    for error in errors:
        print(f"::error::{error}")
    if not errors:
        print("Only P2P ports are exposed by default and anonymous Grafana access is read-only without password logins.")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
