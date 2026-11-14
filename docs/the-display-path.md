# The display path

One frame, from a Hyprland window to the panel on this board. Written down
because the chain has six links and five of them are places where a "sensible"
default is wrong.

## The chain

```text
application
  │  OpenGL 4.6 / Vulkan 1.4
  ▼
vendor EGL or ICD          libEGL_nvidia.so.0       (10_nvidia.json)
                           libGLX_nvidia.so.0       (nvidia_icd.json)
  │
  ▼
compositor renderer        aquamarine, wlroots
  │
  ▼
GBM backend                GBM_BACKEND=nvidia-drm
                           libnvidia-allocator.so
  │  buffers carrying real DRM format modifiers
  ▼
scanout device             /dev/dri/card2
                           driver nv_platform
                           nvidia,tegra234-display
                           connector card2-DP-1
  │
  ▼
host1x                     /dev/dri/card1
                           driver drm, nvidia,tegra234-host1x
                           syncpoints and job submission
  │
  ▼
panel
```

Six links, and only one of them is a device node you would guess.

## The modules behind it

```console
$ lsmod | grep -E 'nvgpu|nvidia|host1x|tegra-dc'
nvgpu           6082560   38
nvidia_modeset  1576960    4   [nvidia_drm]
nvidia_drm       114688   21
```

`nvgpu` is 5.8 MB of driver with 38 live references. It is not a package. It
came out of the L4T kernel tree, and the only way to replace it is to rebuild
the kernel from NVIDIA's tarball with the same config, which is what `kernel/`
exists for.

`nvidia_drm` and `nvidia_modeset` are the DRM glue and the modeset half. They
talk to `nvidia,tegra234-display`, which is the node the panel actually hangs
off.

## What each setting does, and what breaks if you change it

**`AQ_DRM_DEVICES=/dev/dri/card2`**
Aquamarine's device selection. `card1` is host1x and cannot scan out. Point the
compositor at it and you get a black screen with no error, because nothing
failed: the wrong device was simply asked to do the job.

**`GBM_BACKEND=nvidia-drm`**
Chooses NVIDIA's allocator instead of Mesa's. Without it, buffer allocation
falls back to something that does not know about the vendor's memory layout, and
you either get a refusal or a very slow desktop.

**Real DRM modifiers (leave them alone)**
The allocator advertises tiling and compression through modifiers, and the
compositor uses them. `AQ_NO_MODIFIERS=1` and `AQ_TEGRA_LINEAR=1` exist because
they make certain torn frames go away, by removing the fast path. They are the
Linux equivalent of fixing a wheel wobble by removing the wheel.

**`LIBGL_ALWAYS_SOFTWARE=1`**
Not a workaround. This is the off switch. Everything renders, nothing uses the
GPU, and the desktop becomes a slideshow. If you set this to "test something"
and forget, you will spend an afternoon debugging performance that was never
broken.

**EGL vendor order**
`10_nvidia.json` and `50_mesa.json` both exist. NVIDIA wins by sort order today.
If Mesa wins, `glxinfo -B` still says `direct rendering: Yes` and the renderer
string quietly says llvmpipe. Always read the renderer string, never the boolean.

**The Vulkan ICD**
`/etc/vulkan/icd.d/nvidia_icd.json` points at `libGLX_nvidia.so.0` with
`api_version 1.4.329`. There is no distro package for that file on aarch64, and
nothing in pacman's database owns the library it names.

## How to tell it is healthy

```console
$ glxinfo -B | grep -E 'renderer|OpenGL version'
OpenGL renderer string: NVIDIA Tegra Orin (nvgpu)/integrated
OpenGL version string: 4.6.0 NVIDIA 595.78

$ vulkaninfo --summary | grep -E 'deviceName|driverVersion'
apiVersion    = 1.4.329
driverVersion = 595.78.0.0
deviceName    = NVIDIA Tegra Orin (nvgpu)
```

Three checks that catch the realistic failures:

```sh
ls -l /dev/dri/                                   # card1, card2, renderD128/129
cat /sys/class/drm/card2/device/uevent | grep DRIVER   # DRIVER=nv_platform
glxinfo -B | grep renderer                        # must say nvgpu, not llvmpipe
```

`omarchy-gpu-mode gpu` / `omarchy-gpu-mode cpu` flips the whole path, and
`/var/log/omarchy-gpu-check.txt` records the renderer per boot. That log is the
cheapest way to notice that an update quietly moved you to software rendering.

## The part that cannot be fixed

`nvidia-smi` is absent because it ships inside the desktop driver package, and
installing that package overwrites the vendor files this entire chain depends on.
On Jetson the supported telemetry is `tegrastats` and sysfs. Anyone telling you
to install `nvidia-utils` on this board is telling you to break the display.
