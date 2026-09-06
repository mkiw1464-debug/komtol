#pragma once
#include <stdint.h>
#include <dlfcn.h>
#include <mach/mach.h>
#include <mach-o/dyld.h>
#include <string.h>

// ─── Safe memory read using vm_read_overwrite ─────────────────────────────────
// Direct pointer deref crashes if addr is unmapped.
// vm_read_overwrite returns KERN_SUCCESS only if page is readable.

template<typename T>
static bool SafeRead(uintptr_t addr, T &out) {
    if (!addr || addr < 0x1000) return false;
    vm_size_t outSize = 0;
    kern_return_t kr = vm_read_overwrite(
        mach_task_self(),
        (vm_address_t)addr,
        sizeof(T),
        (vm_address_t)&out,
        &outSize
    );
    return (kr == KERN_SUCCESS && outSize == sizeof(T));
}

template<typename T>
static T Read(uintptr_t addr) {
    T val{};
    SafeRead(addr, val);
    return val;
}

template<typename T>
static void Write(uintptr_t addr, T val) {
    if (!addr || addr < 0x1000) return;
    // Make page writable first
    vm_protect(mach_task_self(), addr, sizeof(T), FALSE,
               VM_PROT_READ | VM_PROT_WRITE);
    memcpy(reinterpret_cast<void*>(addr), &val, sizeof(T));
}

// ─── Get Free Fire main module base ──────────────────────────────────────────
// dladdr on our own symbol returns OUR dylib base — wrong.
// We need UnityFramework or the main executable base instead.

static uintptr_t GetImageBase() {
    static uintptr_t base = 0;
    if (base) return base;

    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        // Free Fire main binary
        if (strstr(name, "FreeFire") ||
            strstr(name, "freefire") ||
            strstr(name, "com.dts") ||
            strstr(name, "UnityFramework")) {
            base = (uintptr_t)_dyld_get_image_vmaddr_slide(i) +
                   (uintptr_t)_dyld_get_image_header(i);
            // Slide-only formula for ASLR
            base = (uintptr_t)_dyld_get_image_header(i);
            break;
        }
    }
    // Fallback — first image (main executable)
    if (!base && count > 0)
        base = (uintptr_t)_dyld_get_image_header(0);

    return base;
}

static uintptr_t GetOffset(uintptr_t offset) {
    uintptr_t b = GetImageBase();
    if (!b) return 0;
    return b + offset;
}
