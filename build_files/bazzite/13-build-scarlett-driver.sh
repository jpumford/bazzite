#!/usr/bin/env bash
# Build the firmware-2452-compatible USB audio module for the IMAGE's kernel.
set -euo pipefail

echo "::group::Build Scarlett firmware 2452 driver"
workdir=$(mktemp -d /tmp/scarlett-driver.XXXXXXXX)
trap 'rm -rf "$workdir"; echo "::endgroup::"' EXIT

# Never use uname here: container builds share the runner's kernel.
kernel=$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core)
if [[ -z "$kernel" || "$kernel" == *$'\n'* || ! -d "/usr/src/kernels/$kernel" ]]; then
    echo "Expected one image kernel and matching kernel-devel headers; got: $kernel" >&2
    exit 1
fi

# Maintainer backports, not a moving Git branch. Review when changing kernels.
case "$kernel" in
    6.18.*)
        source_version=6.18.59-f22
        source_sha256=8421efed9a13d96ea133435f59a1a2c2cc31447effaec5787c14421b4a24d9cd
        ;;
    7.2.*)
        source_version=7.2.13-f22
        source_sha256=d180317652b3002318c8c9564ac0e445f422570b7cd97e4576590f5f187c3f20
        ;;
    7.3.*)
        source_version=7.3-f22
        source_sha256=4197d77c673ab9dde612d32e3c4d0ddb56b661c2cbe42ae1ad7dd12f988e04d7
        ;;
    *)
        echo "No pinned Scarlett backport for $kernel. Update this recipe or confirm upstream firmware support before removing it." >&2
        exit 1
        ;;
esac

dnf5 -y install gcc make elfutils-libelf-devel openssl-devel perl tar xz

archive="snd-usb-audio-v${source_version}.tar.xz"
curl --fail --location --retry 3 \
    "https://github.com/geoffreybennett/linux-fcp/releases/download/v6.18-f22/$archive" \
    --output "$workdir/$archive"
printf '%s  %s\n' "$source_sha256" "$workdir/$archive" | sha256sum --check --strict
mkdir "$workdir/source"
tar --extract --xz --file "$workdir/$archive" --directory "$workdir/source" --strip-components=1

# Build only the replacement module; retain the kernel's other USB drivers.
make -j"$(nproc)" -C "/usr/src/kernels/$kernel" \
    M="$workdir/source" CONFIG_SND_USB_AUDIO=m snd-usb-audio.ko
module="$workdir/source/snd-usb-audio.ko"
vermagic=$(modinfo -F vermagic "$module")
if [[ "${vermagic%% *}" != "$kernel" ]]; then
    echo "Scarlett module vermagic mismatch: $vermagic (expected $kernel)" >&2
    exit 1
fi

destination="/usr/lib/modules/$kernel/updates/snd-usb-audio/snd-usb-audio.ko"
install -D -m 0644 "$module" "$destination"
depmod -a "$kernel"
selected=$(modinfo -k "$kernel" -n snd_usb_audio)
if [[ "$(readlink -f "$selected")" != "$(readlink -f "$destination")" ]]; then
    echo "Module lookup selected $selected instead of $destination" >&2
    exit 1
fi

# Retain provenance after temporary build files are removed.
install -d /usr/share/doc/scarlett-driver
printf 'Release: v6.18-f22\nArchive: %s\nSHA256: %s\nKernel: %s\n' \
    "$archive" "$source_sha256" "$kernel" \
    > /usr/share/doc/scarlett-driver/source.txt
echo "Scarlett firmware 2452 driver installed for $kernel: $selected"
