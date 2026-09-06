#ifndef fishhook_h
#define fishhook_h

#include <stddef.h>
#include <stdint.h>

#if !defined(FISHHOOK_EXPORT)
#define FISHHOOK_EXPORT extern
#endif

struct rebinding {
    const char *name;
    void *replacement;
    void **replaced;
};

FISHHOOK_EXPORT int rebind_symbols(struct rebinding rebindings[],
                                   size_t rebindings_nel);

FISHHOOK_EXPORT int rebind_symbols_image(void *header,
                                         intptr_t slide,
                                         struct rebinding rebindings[],
                                         size_t rebindings_nel);
#endif
