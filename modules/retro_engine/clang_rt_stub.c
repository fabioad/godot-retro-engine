#include <stdint.h>

/*
 * Minimal compiler-rt shim for osxcross builds.
 *
 * Apple's clang links libclang_rt.osx.a, which provides
 * ___isPlatformVersionAtLeast for @available checks. The Ubuntu osxcross
 * container does not ship that runtime, so the retro_engine module supplies
 * this symbol when building with OSXCROSS_ROOT. The deployment target is
 * macOS 10.13; treating availability checks as satisfied matches the modern
 * macOS versions the cross-built editor is intended for.
 */
int __isPlatformVersionAtLeast(uint32_t platform, uint32_t major, uint32_t minor, uint32_t patch) {
	(void)platform;
	(void)major;
	(void)minor;
	(void)patch;
	return 1;
}
