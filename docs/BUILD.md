# Building

There are two supported build environments:

1. **macOS** (recommended for most users) — uses Homebrew clang + ldid
2. **Linux** (CI / Docker) — uses Debian clang + lld + ldid

Both produce the same `.deb` artifact.

## Prerequisites (common)

- `git` (any recent version)
- `make` (GNU make 4+)
- A clone of [theos/theos](https://github.com/theos/theos) at `$THEOS`
- The `iPhoneOS16.5.sdk` from [theos/sdks](https://github.com/theos/sdks) placed at `$THEOS/sdks/iPhoneOS16.5.sdk`

## macOS build

```bash
# 1. Install prerequisites
brew install ldid xz make

# 2. Clone Theos + SDK
git clone --recursive https://github.com/theos/theos.git ~/theos
git clone --depth 1 https://github.com/theos/sdks.git /tmp/sdks
cp -R /tmp/sdks/iPhoneOS16.5.sdk ~/theos/sdks/

# 3. Clone this repo
git clone https://github.com/Sohday67/test2silence.git
cd test2silence

# 4. Build
export THEOS=~/theos
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
```

The `.deb` will be at `packages/com.ytlite.skipsilence_1.0.0_iphoneos-arm64.deb`.

## Linux build (Debian/Ubuntu)

Theos doesn't ship a Linux iPhone toolchain by default, so we have to install
clang + lld + ldid and wire them up where Theos expects them.

```bash
# 1. Install clang, lld, llvm-tools, ldid
sudo apt-get install -y clang lld llvm llvm-tools dpkg-dev perl git make
# ldid is not in Debian repos — install from Procursus:
curl -L "https://github.com/ProcursusTeam/ldid/releases/latest/download/ldid_linux_x86_64" \
     -o /usr/local/bin/ldid
chmod +x /usr/local/bin/ldid

# 2. Clone Theos + SDK
git clone --recursive https://github.com/theos/theos.git ~/theos
git clone --depth 1 https://github.com/theos/sdks.git /tmp/sdks
cp -R /tmp/sdks/iPhoneOS16.5.sdk ~/theos/sdks/

# 3. Wire the system clang/lld/strip into Theos's toolchain directory
mkdir -p ~/theos/toolchain/linux/iphone/bin
ln -sf $(command -v clang)       ~/theos/toolchain/linux/iphone/bin/clang
ln -sf $(command -v clang++)     ~/theos/toolchain/linux/iphone/bin/clang++
ln -sf $(command -v ldid)        ~/theos/toolchain/linux/iphone/bin/ldid
ln -sf $(command -v ld.lld)      ~/theos/toolchain/linux/iphone/bin/ld
ln -sf $(command -v llvm-strip)  ~/theos/toolchain/linux/iphone/bin/strip
ln -sf $(command -v llvm-lipo)   ~/theos/toolchain/linux/iphone/bin/lipo
# (If llvm-lipo isn't packaged in your distro, build a single-arch .deb by
#  setting ARCHS=arm64 in the Makefile — already the default.)

# 4. Clone + build
git clone https://github.com/Sohday67/test2silence.git
cd test2silence
export THEOS=~/theos
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
```

## Verifying the build

```bash
# Show package metadata
dpkg-deb -I packages/*.deb

# List files inside the package
dpkg-deb -c packages/*.deb

# Verify the dylib is a valid Mach-O
file .theos/obj/YTLiteSkipSilence.dylib
# expected: Mach-O 64-bit arm64 dynamically linked shared library
```

## Installing on device

```bash
# Copy the .deb to your device
scp packages/*.deb mobile@<device>:/var/mobile/

# SSH in and install
ssh mobile@<device>
sudo dpkg -i /var/mobile/com.ytlite.skipsilence_*.deb
sudo killall -9 SpringBoard   # respring
```

After the respring:

- Open **YouTube** — Skip Silence / Smart Speed is now active with default settings
- Open **Settings → YTLiteSkipSilence** to customize
- Or, if YTLite is installed, open its settings panel and tap "Skip Silence"

## Troubleshooting the build

| Error | Fix |
|---|---|
| `Makefile:XX: missing separator` | The recipe lines must use TABs, not spaces. Run `perl -i -pe 's/^        /\t/' Makefile` to convert. |
| `toolchain/linux/iphone/bin/clang: No such file or directory` | Symlink clang into `~/theos/toolchain/linux/iphone/bin/` per the Linux instructions above. |
| `unknown argument '-framework'` from `ld` | The system GNU `ld` is being used instead of `ld64.lld`. Symlink `ld` → `ld64.lld` in the toolchain bin dir. |
| `lipo: No such file or directory` | Symlink `lipo` → `llvm-lipo` in the toolchain bin dir. If `llvm-lipo` is unavailable, ensure `ARCHS=arm64` only (the default) — single-slice builds don't need lipo. |
| `no visible @interface for 'SNClassifySoundRequest' declares the selector 'initWithClassifierIdentifier:'` | Deployment target is below iOS 15. Set `TARGET_IPHONEOS_DEPLOYMENT_VERSION = 15.0` in the Makefile. |
| `OCSettings.m: bad receiver type 'BOOL'` | The `PROP_GETSET` macro was generating `setenabled:` instead of `setEnabled:`. Fixed in this commit — explicit accessors are used instead. |

## Architecture notes

The build targets **arm64** only. arm64e (A12+ devices) is not built because
Apple's `ld64` doesn't ship for Linux and `ld64.lld` from LLVM 19 cannot
distinguish arm64 from arm64e slices when merging into a fat binary.

This is fine in practice because:

- MobileSubstrate's rootless loader injects arm64 dylibs into arm64e processes via its compatibility shim
- YouTube itself ships arm64-only (no arm64e slice) on iOS 16 and later
- The dylib runs in-process with YouTube, so it inherits YouTube's architecture

If you build on macOS with Xcode's full toolchain, you can change `ARCHS = arm64`
back to `ARCHS = arm64 arm64e` in the Makefile to produce a fat arm64+arm64e dylib.
