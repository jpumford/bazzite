# Persistent Scarlett driver

This fork starts from Bazzite stable release
[`45.20261123.1`](https://github.com/ublue-os/bazzite/releases/tag/45.20261123.1),
commit `09b2a594862175d9394eaf1529a980dc85f06f73`.
At the time of the fork, `main` pointed to that commit too. A branch moves;
the release tag identifies the released source snapshot. The `stable` OCI
image tag also moves as releases are published. A Git commit identifies the
recipe, whereas an OCI digest identifies a particular built image, including
its packages and base image. Rebuilding the same Git commit later need not
produce the same image because upstream package repositories and base tags move.

## What the fork changes

`build_files/bazzite/13-build-scarlett-driver.sh` runs after package installation
and before the existing initramfs build. It installs the replacement
`snd-usb-audio.ko` under the image kernel's `updates/snd-usb-audio/` directory,
runs `depmod`, and verifies module lookup selects the replacement. The stock
module remains installed as a fallback if this recipe is removed later.

The source is Geoffrey Bennett's
[`v6.18-f22` release](https://github.com/geoffreybennett/linux-fcp/releases/tag/v6.18-f22),
which supports Scarlett Solo/2i2/4i4 4th Gen firmware 2452. Each source archive
is pinned to the SHA256 published in the release's GitHub API asset metadata.
The build records its archive, checksum and target kernel in
`/usr/share/doc/scarlett-driver/source.txt`.

Every image build compiles against that image's installed kernel-devel headers,
not the Actions runner's kernel. A successful image therefore contains the
matching replacement module across reboots and updates built from this fork.
This does not persist mixer levels, change audio routing, or install a boot-time
rebuild service. Other snd-usb-audio-supported devices use this module too.

## Build and test on Forgejo

Use the fork's existing `build.py` entry point in your Forgejo job, for example:

```bash
git submodule update --init --recursive
python3 build.py build --image bazzite --tag localhost/bazzite-scarlett:test
```

The kernel fix is part of the Containerfile build, so it does not depend on
GitHub Actions. This commit does not convert upstream `.github/workflows` into
Forgejo workflows or configure publishing, registry credentials, or signing.
Choose the image variant matching your machine; `bazzite` is the KDE desktop
variant without NVIDIA. The current default kernel is `7.3.5-ogc2.1.fc45`;
the LTS variants use `6.18.64-ogc1.1.fc45`.

After building, inspect the module without loading it into the runner:

```bash
podman run --rm --entrypoint /bin/bash localhost/bazzite-scarlett:test -c '
  set -e
  kernel=$(rpm -q --qf "%{VERSION}-%{RELEASE}.%{ARCH}" kernel-core)
  cat /usr/share/doc/scarlett-driver/source.txt
  modinfo -k "$kernel" -n snd_usb_audio
  modinfo -k "$kernel" -F vermagic snd_usb_audio
'
```

After deploying and booting your built image, verify initialization:

```bash
modinfo -n snd_usb_audio
journalctl -b -k --no-pager | grep -E 'Scarlett.*Mixer Driver|Firmware version'
```

The expected module path ends in `updates/snd-usb-audio/snd-usb-audio.ko`.
For the 2i2 with updated firmware, initialization should report firmware `2452`
and the maintainer's `f22` driver. Then test playback, capture, direct monitoring,
and the controller. Module lookup alone does not prove hardware works.

## Kernel updates and Secure Boot

Pinned backports are supplied for kernel series 6.18, 7.2 and 7.3. Patch-level
updates rebuild the module with matching headers. Compilation or module lookup
failure stops the build. An unsupported series such as 7.4 also stops the build:
add a compatible maintainer source and checksum, or verify the stock kernel has
the fix and remove this build step. A failed build does not alter an installed
machine; publish and deploy only successful images.

The replacement module is unsigned. Secure Boot was disabled on the target
machine when this change was prepared. Machines enforcing module signatures
need an additional module-signing step using a private key whose certificate
they trust, or must use a stock signed kernel that includes the fix. Signing an
OCI image with cosign does not sign the kernel module. Never commit private keys.
