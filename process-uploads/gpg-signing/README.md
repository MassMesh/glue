
# GPG signing

The openwrt package repositories contain a Packages.asc file. This file appears
to be unused by opkg client so MassMesh does not currently provide a Packages.asc
file.

When we want to start providing it, here's how the server should be configured to
generate this file automatically whenever our package repositories are updated.

## 1. Create a keypair

Follow the instructions at https://openwrt.org/docs/guide-user/security/keygen to generate a GPG keypair and a signing subkey.

## 2. Install the subkey on the server

Install the subkey (only!) on the host that is going to sign the Packages file. This is also described at https://openwrt.org/docs/guide-user/security/keygen

## 3. Set up gpg-agent on the server

Install gpg-agent, and create ~uploader/.gnupg/gpg-agent.conf:

<pre>
# keep the passphrase in memory for 1 year
default-cache-ttl 31536000
max-cache-ttl 31536000
enable-ssh-support
</pre>

## 4. Load the passphrase in memory on the server

After every boot (or whenever gpg-agent is stopped), run the 'startup-agent.sh' script.

## 5. Patch process-uploads.sh

Apply the `process-uploads-gpg-signing.patch` patch from this directory to process-uploads.sh.
