// Stub implementations of __report_rangecheckfailure and __report_gsfailure
// to keep MSVC's msvcrt.lib(gs_report.obj) from being pulled in. That obj
// supplies a static body for both symbols, which clashes against vcruntime
// .lib's DLL-import thunk for __report_gsfailure when /MD code from a
// different MSVC toolchain (e.g. vcpkg's prebuilt SDL3-static) is mixed
// with c3c-driven lld-link MSVC.
//
// Behaviour matches MSVC's intent: terminate the process via __fastfail
// with the matching FAST_FAIL_* code. Compiled with /GS- (Makefile flag)
// so this file doesn't itself reference the symbols it provides.

#include <intrin.h>

#ifndef FAST_FAIL_STACK_COOKIE_CHECK_FAILURE
#define FAST_FAIL_STACK_COOKIE_CHECK_FAILURE 2
#endif

#ifndef FAST_FAIL_RANGE_CHECK_FAILURE
#define FAST_FAIL_RANGE_CHECK_FAILURE        8
#endif

__declspec(noreturn) void __cdecl __report_rangecheckfailure(void) {
    __fastfail(FAST_FAIL_RANGE_CHECK_FAILURE);
}

__declspec(noreturn) void __cdecl __report_gsfailure(unsigned __int64 cookie) {
    (void)cookie;
    __fastfail(FAST_FAIL_STACK_COOKIE_CHECK_FAILURE);
}
