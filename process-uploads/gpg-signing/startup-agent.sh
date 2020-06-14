#!/bin/bash

echo
echo "This script needs to be run when gpg-agent no longer has the passphrase for our signing"
echo "key cached (e.g. after default-cache-ttl/max-cache-ttl have expired, or after reboot)."
echo "It is harmless to run the script when the gpg-agent is already running with the cached"
echo "passphrase."
echo

# Start up gpg-agent (yes, this syntax is a bit odd)
gpg-connect-agent /bye

# Load the TTY
GPG_TTY=$(tty)
export GPG_TTY
export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR}/gnupg/S.gpg-agent.ssh"

# Prompt for the passphrase, so that gpg-agent will cache it
echo | gpg -sa -u 305E0DFF >/dev/null

echo "If you were not prompted for the key passphrase, that means the gpg-agent is already"
echo "active with the passphrase cached. If you were prompted for the key passphrase and"
echo "provided the correct answer, the gpg-agent should now be running with the passphrase"
echo "cached."
echo
