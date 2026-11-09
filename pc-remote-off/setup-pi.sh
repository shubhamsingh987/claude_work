#!/bin/bash
# Run on pihole as kudo:  bash setup-pi.sh <pc-tailscale-ip-or-magicdns> <windows-username>
# Makes a dedicated key and an ssh alias "pc-off". Prints the public key for setup-windows.ps1.
set -euo pipefail
HOST=${1:?pc tailscale ip/name}; WUSER=${2:?windows username}
KEY=~/.ssh/id_ed25519_pcoff
[ -f "$KEY" ] || ssh-keygen -t ed25519 -N '' -C pi-pc-off -f "$KEY"
grep -q '^Host pc-off$' ~/.ssh/config 2>/dev/null || cat >> ~/.ssh/config <<CFG

Host pc-off
    HostName $HOST
    User $WUSER
    IdentityFile $KEY
    IdentitiesOnly yes
    ConnectTimeout 8
CFG
chmod 600 ~/.ssh/config
echo "Public key (pass to setup-windows.ps1 -PubKey):"; cat "$KEY.pub"
