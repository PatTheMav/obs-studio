libobs-metal
============

This is a not-even-alpha quality implementation of a Metal renderer backend for OBS for Apple Silicon Macs. Basic functionality is implemented, albeit with a lot of known issues and missing implementations.

## Overview

* The renderer backend is implemented entirely in Swift
* C header is generated automatically via the `-emit-objc-header` compile flag and `@cdecl("<FUNCTION NAME>")` decorators to expose desired functions to `libobs` as required
* Only Metal Version 3 is supported (this is by design)
* Only Apple Silicon Macs are supported (this is by design)

## Implemented functionality

* Basic set of sources that do render:
    * Image source
    * Capture source
    * Media source
    * SCK capute source
    * Browser source
* Recording via VideoToolbox encoders works
* Multi-view works (with quirks)
* Fullscreen and windowed projectors work
* Preview scaling works

## Required Fixes and Workarounds

* Metal Shader Language is stricter than HLSL and GLSL and does not allow type punning or implicit casting - all type conversions have to be explicit - and commonly allows only a specific set of types for vector data, colour data, or UV coordinates
    * The transpiler has to force conversions to unsigned integers and unsigned integer vectors for texture `Load` calls because `libobs` shaders depend on the implicit conversion of a 32-bit float vector to integer values when passed to the texture's load command (`read` in MSL)
    * Metal has no support for BGRX/RGBX formats, colour always has to be specified using a vector of 4 floats, some `libobs` shaders assume BGRX and only provide a `float3` value in their pixel shaders. Transpiled Metal shaders instead return a `float4` with a `1.0` alpha value
    * This might not be exhaustive, as other - so far untested - shaders might depend on other implicit conversions of HLSL/GLSL and will require additional workarounds and wrapping of existing code to return the correct types expected by MSL
* Metal does not support unpacking `UInt32` values into a `float4` in vertex data provided via the `[[stage_in]]` attribute to benefit from vertex fetch (where the pipeline itself is made aware of the buffer layout via a vertex descriptor and thus fetches the data from the buffer as needed) vs the classic "vertex push" method
    * This is commonly used in `libobs` to provide colour buffer data - to fix this, the values are unpacked and converted into a `float4` when the GPU buffers are created for a vertex buffer
* Every draw call (even a clear) has to be explicit, which is why there is a bespoke `clear` function that creates and commits a single command buffer to clear a render target

## Known Issues

* Only `libobs` shaders are proven to transpile with current code, any other shaders (even filter shaders) haven't been tested and will require additional bespoke workarounds in the transpiler
* Switching to scenes without sources retains the last render output of another scene - root cause is the expectation of `libobs` graphics engine seems to be the expectation that clears are implicit draw calls, whereas Metal (as well as D3D12 and Vulkan) require clears to happen as part of an explicit draw call
* Any text rendered via the Freetype 2 will be broken - the plugin creates dynamic vertex buffers but treats them like static buffers (it creates them once but does not refresh the vertex data per frame), which is different from how libobs works with vertex buffers
    * The backend expects dynamic buffers to be truly "dynamic" (as in: refreshed every frame) and thus releases all buffers when `libobs` flushes the current command queue (or presents the preview output) so that dynamic buffers can be re-used by later draw calls
    * The Freetype 2 source creates a vertex buffer only when text is changed, but marks it explicitly as "dynamic". By holding onto the dynamic vertex buffer, it also holds onto buffer objects which will be re-used by other draw calls and thus visual artefacts occur
* This issue might also affect other sources that create dynamic buffers but expect that their underlying API-specific buffers are retained
* The spacing helpers are implemented using 4 freetype 2 sources as their labels, thus the spacing helpers will also exhibit visual errors
* Spacing helpers, highlight borders and grabbers for resizing/positioning are not drawn in batches - instead each grabber, each line, each label, gets their own draw calls which creates a lot of CPU overhead and has a negative impact on rendering performance (according to Metal docs this is particularly bad for modern APIs like Metal which desire lots of combination/batching and want to keep the GPU busy with lots of work and minimise context switches as much as possible)
* sRGB support is not implemented, neither is XDR support and colour accuracy was not considered in this first implementation

## Preview Issues

* Currently OBS Studio on macOS replaces the backing layer of the preview area with an OpenGL layer and switches between OpenGL contexts to simulate double buffering
* The analog with Metal is to replace the backing layer of the preview with an `MTLLayer` which has a function to retrieve a `Drawable` (effectively a texture-backed animation layer for the macOS windowing system)
* An `MTLLayer` will only provide up to 3 `Drawable`s (to enable triple buffering) - if no `Drawable`s are available, the caller will be blocked until one is available again
* macOS windowing system is always synced to the display refresh rate (to achieve effects like dynamic desktop refresh rates to improve battery runtime) with no way to circumvent this (which would allow an application to still refresh at higher rates even though the OS is in "energy saver" mode and limits refreshes)
* OBS will always try to draw the preview at the internal rendering framerate (e.g. 120 fps) but `MTLLayer` will not yield a new `Drawable` faster than the internal OS screen refresh rate
* As such, requesting a new `Drawable` in the graphics thread will limit its framerate to the screen refresh rate
* A possible solution to this has not been found yet (some ideas include doing the preview/multiview refreshes in yet another thread which fetches the "current" output texture on its own timer)
* An alternative would be to nest an `MTKView` into the `QNSView` created by Qt and implement its draw callback which will be called whenever it needs its output and would just require the graphics thread to have generated output textures
    * This would require implementing an `MTKView` for the preview (in normal and studio mode), every source's preview, the multiview, and possibly other areas
