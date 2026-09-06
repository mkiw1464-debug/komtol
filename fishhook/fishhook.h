#ifndef fishhook_h
#define fishhook_h

#include <stddef.h>
#include <stdint.h>

struct rebinding {
    const char *name;
    void *replacement;
    void **replaced;
};

// extern "C" — prevent C++ name mangling so linker finds C symbols correctly
#ifdef __cplusplus
extern "C" {
#endif

int rebind_symbols(struct rebinding rebindings[], size_t rebindings_nel);

int rebind_symbols_image(void *header,
                         intptr_t slide,
                         struct rebinding rebindings[],
                         size_t rebindings_nel);

#ifdef __cplusplus
}
#endif

#endif
