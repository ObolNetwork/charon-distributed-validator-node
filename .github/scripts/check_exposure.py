#!/usr/bin/env python3
"""Fails if the default configuration exposes more than the P2P ports to the internet.

- Every port published by a top-level compose file must, with its default values, either bind to
  a loopback address or be a P2P port.
- Anonymous Grafana users must not get more than the Viewer role.
"""

import configparser
import glob
import re
import sys

import yaml

# Container ports that must be reachable by peers: EL, CL (incl. Prysm's 13000/12000) and charon.
P2P_PORTS = {"30303", "9000", "12000", "13000", "3610"}
LOOPBACK = {"127.0.0.1", "::1", "[::1]"}


def expand_defaults(value):
    """Replaces ${VAR:-default} and ${VAR-default} with the default, and ${VAR} with an empty string."""
    return re.sub(r"\$\{[A-Za-z0-9_]+(?::?-([^}]*))?\}", lambda m: m.group(1) or "", value)


def check_ports():
    errors = []
    for path in sorted(glob.glob("*.yml")):
        compose = yaml.safe_load(open(path)) or {}
        for name, service in (compose.get("services") or {}).items():
            for port in (service or {}).get("ports") or []:
                if not isinstance(port, str):
                    errors.append(f"{path}: {name}: use the short port syntax so this check can read it: {port}")
                    continue
                spec = expand_defaults(port).split("/")[0]
                parts = spec.rsplit(":", 2)
                host_ip = parts[0] if len(parts) == 3 else ""
                container_port = parts[-1]
                if host_ip in LOOPBACK or container_port in P2P_PORTS:
                    continue
                errors.append(f"{path}: {name}: '{port}' is published on all interfaces by default; bind it to 127.0.0.1")
    return errors


def check_grafana():
    ini = configparser.ConfigParser(interpolation=None)
    ini.read("grafana/grafana.ini")
    anonymous = ini["auth.anonymous"] if ini.has_section("auth.anonymous") else {}
    if anonymous.get("enabled", "false").lower() == "true" and anonymous.get("org_role", "Viewer") != "Viewer":
        return [f"grafana/grafana.ini: anonymous users get the {anonymous['org_role']} role; use Viewer"]
    return []


def main():
    errors = check_ports() + check_grafana()
    for error in errors:
        print(f"::error::{error}")
    if not errors:
        print("Only P2P ports are exposed by default and anonymous Grafana access is read-only.")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
