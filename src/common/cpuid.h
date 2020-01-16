#pragma once

#include "types.h"

namespace bezos
{
    struct cpuid_val
    {
        u32 eax, ebx, ecx, edx;
    };

    inline cpuid_val cpuid(u32 a, u32 c)
    {
        cpuid_val ret = {};

        asm("cpuid" : "=a"(ret.eax), "=b"(ret.ebx), "=c"(ret.ecx), "=d"(ret.edx) : "a"(a), "c"(c));

        return ret;
    }
}