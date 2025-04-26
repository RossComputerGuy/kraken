#pragma once

#include <string.h>

#ifdef __cplusplus
#define ZIG_EXTERN_C extern "C"
#else
#define ZIG_EXTERN_C
#endif

struct NixMachine;

ZIG_EXTERN_C const NixMachine** nix_store_machine_parse_config(const char**, size_t, const char*, size_t, size_t*);
