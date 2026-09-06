#import "AntiDebug.h"
#include "../../fishhook/fishhook.h"
#include <sys/sysctl.h>
#include <sys/types.h>
#include <unistd.h>
#include <dlfcn.h>

// sys/ptrace.h tidak wujud dalam iOS SDK — define manual
#define PT_DENY_ATTACH 31

// Declare ptrace manually (syscall masih wujud, cuma header yang takde)
extern int ptrace(int request, pid_t pid, caddr_t addr, int data);

// ─── Block PT_DENY_ATTACH ─────────────────────────────────────────────────────
static int (*orig_ptrace)(int, pid_t, caddr_t, int) = nullptr;

static int fake_ptrace(int req, pid_t pid, caddr_t addr, int data) {
    if (req == PT_DENY_ATTACH) return 0; // silently swallow
    return orig_ptrace(req, pid, addr, data);
}

// ─── Block debugger flag via sysctl ──────────────────────────────────────────
static int (*orig_sysctl)(int*, u_int, void*, size_t*, void*, size_t) = nullptr;

static int fake_sysctl(int *name, u_int nlen, void *oldp,
                       size_t *oldlenp, void *newp, size_t newlen) {
    int ret = orig_sysctl(name, nlen, oldp, oldlenp, newp, newlen);
    if (nlen == 4 &&
        name[0] == CTL_KERN &&
        name[1] == KERN_PROC &&
        name[2] == KERN_PROC_PID &&
        oldp) {
        struct kinfo_proc *info = (struct kinfo_proc *)oldp;
        info->kp_proc.p_flag &= ~P_TRACED;
    }
    return ret;
}

// ─── Block sysctl debugger check via direct name lookup ──────────────────────
static int (*orig_sysctlbyname)(const char*, void*, size_t*, void*, size_t) = nullptr;

static int fake_sysctlbyname(const char *name, void *oldp, size_t *oldlenp,
                              void *newp, size_t newlen) {
    // Block security.mac.* and kern.proc queries used by AC
    if (name && (strstr(name, "security.mac") || strstr(name, "kern.codesign")))
        return -1;
    return orig_sysctlbyname(name, oldp, oldlenp, newp, newlen);
}

void InitAntiDebug() {
    struct rebinding r[] = {
        {"ptrace",       (void*)fake_ptrace,       (void**)&orig_ptrace},
        {"sysctl",       (void*)fake_sysctl,        (void**)&orig_sysctl},
        {"sysctlbyname", (void*)fake_sysctlbyname,  (void**)&orig_sysctlbyname},
    };
    rebind_symbols(r, 3);
}
