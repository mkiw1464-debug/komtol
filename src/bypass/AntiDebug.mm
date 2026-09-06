#import "AntiDebug.h"
#include "../../fishhook/fishhook.h"
#include <sys/ptrace.h>
#include <sys/sysctl.h>

// ─── Block PT_DENY_ATTACH ─────────────────────────────────────────────────────
static int (*orig_ptrace)(int, pid_t, caddr_t, int) = nullptr;

static int fake_ptrace(int req, pid_t pid, caddr_t addr, int data) {
    if (req == PT_DENY_ATTACH) return 0;
    return orig_ptrace(req, pid, addr, data);
}

// ─── Block debugger flag in sysctl ───────────────────────────────────────────
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

void InitAntiDebug() {
    struct rebinding r[] = {
        {"ptrace", (void*)fake_ptrace, (void**)&orig_ptrace},
        {"sysctl", (void*)fake_sysctl, (void**)&orig_sysctl},
    };
    rebind_symbols(r, 2);
}
