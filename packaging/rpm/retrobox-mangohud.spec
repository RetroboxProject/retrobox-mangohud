# Binary-only spec: the tree is built and staged beforehand by
# scripts/build.sh + scripts/stage.sh and handed in through %%{stage}.
# Shared-library Requires are generated automatically from the ELF files.
%global debug_package %{nil}
%global __strip /bin/true
%global _build_id_links none

# Private libraries: never advertise them to the rest of the system (they
# would otherwise appear as Provides of libMangoHud.so and fight the
# distribution's mangohud), and do not require them from outside either.
%global __provides_exclude_from ^/opt/retrobox/.*$
%global __requires_exclude ^libMangoHud.*$

Name:           retrobox-mangohud
Version:        %{mh_version}
Release:        %{pkg_revision}%{?dist}
Summary:        MangoHud with background image support, for Retrobox
# MIT (MangoHud, imgui, implot, spdlog, Mesa and others), Apache-2.0
# (Vulkan libraries), Zlib (elfhacks), OFL-1.1 (Fork Awesome font),
# LGPL-3.0-or-later (parts of the patches derived from batocera.linux), and the
# NVIDIA NVML header notice. See /usr/share/doc/retrobox-mangohud/copyright.
License:        MIT AND Apache-2.0 AND Zlib AND OFL-1.1 AND LGPL-3.0-or-later AND LicenseRef-NVIDIA-NVML
URL:            https://github.com/manu-romero-411/retrobox-mangohud
ExclusiveArch:  x86_64 x86_64_v3 aarch64

Requires:       retrobox-core
# Loaded with dlopen() at run time, so no ELF dependency expresses them.
Recommends:     dbus-libs
Recommends:     libX11
Recommends:     vulkan-loader

%description
MangoHud built with the Retrobox patches (background_image/image) in a
private prefix, /opt/retrobox/resources/mangohud, with its own Vulkan layer
(VK_LAYER_RETROBOX_MANGOHUD_*) switched on by RETROBOX_MANGOHUD=1.

It does not replace, nor conflict with, the MangoHud package of the
distribution: both can be installed at the same time.

%install
mkdir -p %{buildroot}
cp -a %{stage}/. %{buildroot}/

%files
/opt/retrobox/resources/mangohud
/usr/lib/environment.d/64-retrobox-mangohud.conf
%license /usr/share/doc/retrobox-mangohud/copyright
%license /usr/share/doc/retrobox-mangohud/licenses
/usr/share/doc/retrobox-mangohud/patches
/usr/share/doc/retrobox-mangohud/BUILDINFO

%changelog
* Sat Oct 24 2026 Retrobox <manu-romero-411@users.noreply.github.com> - %{mh_version}-%{pkg_revision}
- Automated build.
