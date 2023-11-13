#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>

#if __RP2040__

#define PSEUDO_LOCK() \
  uint32_t status; \
  __asm__ volatile (".syntax unified\ndmb" : : : "memory"); \
  __asm__ volatile (".syntax unified\n" \
    "mrs %0, PRIMASK\n" \
    "cpsid i" \
    : "=r" (status) ::)

#define PSEUDO_UNLOCK() \
  __asm__ volatile (".syntax unified\nmsr PRIMASK,%0"::"r" (status) : ); \
  __asm__ volatile (".syntax unified\ndmb" : : : "memory")

unsigned int __atomic_load_4(unsigned int *p, int model) {
  uint32_t value;
  PSEUDO_LOCK();
  value = *p;
  PSEUDO_UNLOCK();
  return value;
}

unsigned int __atomic_fetch_add_4(unsigned int *p, unsigned int v, int model) {
  uint32_t value;
  PSEUDO_LOCK();
  value = *p;
  *p += v;
  PSEUDO_UNLOCK();
  return value;
}

unsigned int __atomic_fetch_sub_4(unsigned int *p, unsigned int v, int model) {
  uint32_t value;
  PSEUDO_LOCK();
  value = *p;
  *p -= v;
  PSEUDO_UNLOCK();
  return value;
}

_Bool __atomic_compare_exchange_4(unsigned int *p, unsigned int *expected, unsigned int desired, _Bool weak, int success, int failure) {
  _Bool result;
  PSEUDO_LOCK();
  if (*p == *expected) {
    *p = desired;
    result = true;
  } else {
    *expected = *p;
    result = false;
  }
  PSEUDO_UNLOCK();
  return result;
}

void __atomic_store_4(unsigned int *p, unsigned int v, int model) {
  PSEUDO_LOCK();
  *p = v;
  PSEUDO_UNLOCK();
}

#endif

FILE _stdout = { };
FILE _stderr = { };

FILE *const stdout = &_stdout;
FILE *const stderr = &_stderr;

struct _SwiftHashingParameters {
  uint64_t seed0;
  uint64_t seed1;
  _Bool deterministic;
};

struct _SwiftHashingParameters _swift_stdlib_Hashing_parameters = { 0, 0, 1 };

#if __RP2040__
__asm__(".cpu cortex-m0plus\n\t"
        ".thumb\n\t"
        ".section .boot2, \"ax\"\n\t"
        ".byte 0x00, 0xb5, 0x32, 0x4b, 0x21, 0x20, 0x58, 0x60, 0x98, 0x68, 0x02, 0x21, 0x88, 0x43, 0x98, 0x60\n\t"
        ".byte 0xd8, 0x60, 0x18, 0x61, 0x58, 0x61, 0x2e, 0x4b, 0x00, 0x21, 0x99, 0x60, 0x02, 0x21, 0x59, 0x61\n\t"
        ".byte 0x01, 0x21, 0xf0, 0x22, 0x99, 0x50, 0x2b, 0x49, 0x19, 0x60, 0x01, 0x21, 0x99, 0x60, 0x35, 0x20\n\t"
        ".byte 0x00, 0xf0, 0x44, 0xf8, 0x02, 0x22, 0x90, 0x42, 0x14, 0xd0, 0x06, 0x21, 0x19, 0x66, 0x00, 0xf0\n\t"
        ".byte 0x34, 0xf8, 0x19, 0x6e, 0x01, 0x21, 0x19, 0x66, 0x00, 0x20, 0x18, 0x66, 0x1a, 0x66, 0x00, 0xf0\n\t"
        ".byte 0x2c, 0xf8, 0x19, 0x6e, 0x19, 0x6e, 0x19, 0x6e, 0x05, 0x20, 0x00, 0xf0, 0x2f, 0xf8, 0x01, 0x21\n\t"
        ".byte 0x08, 0x42, 0xf9, 0xd1, 0x00, 0x21, 0x99, 0x60, 0x1b, 0x49, 0x19, 0x60, 0x00, 0x21, 0x59, 0x60\n\t"
        ".byte 0x1a, 0x49, 0x1b, 0x48, 0x01, 0x60, 0x01, 0x21, 0x99, 0x60, 0xeb, 0x21, 0x19, 0x66, 0xa0, 0x21\n\t"
        ".byte 0x19, 0x66, 0x00, 0xf0, 0x12, 0xf8, 0x00, 0x21, 0x99, 0x60, 0x16, 0x49, 0x14, 0x48, 0x01, 0x60\n\t"
        ".byte 0x01, 0x21, 0x99, 0x60, 0x01, 0xbc, 0x00, 0x28, 0x00, 0xd0, 0x00, 0x47, 0x12, 0x48, 0x13, 0x49\n\t"
        ".byte 0x08, 0x60, 0x03, 0xc8, 0x80, 0xf3, 0x08, 0x88, 0x08, 0x47, 0x03, 0xb5, 0x99, 0x6a, 0x04, 0x20\n\t"
        ".byte 0x01, 0x42, 0xfb, 0xd0, 0x01, 0x20, 0x01, 0x42, 0xf8, 0xd1, 0x03, 0xbd, 0x02, 0xb5, 0x18, 0x66\n\t"
        ".byte 0x18, 0x66, 0xff, 0xf7, 0xf2, 0xff, 0x18, 0x6e, 0x18, 0x6e, 0x02, 0xbd, 0x00, 0x00, 0x02, 0x40\n\t"
        ".byte 0x00, 0x00, 0x00, 0x18, 0x00, 0x00, 0x07, 0x00, 0x00, 0x03, 0x5f, 0x00, 0x21, 0x22, 0x00, 0x00\n\t"
        ".byte 0xf4, 0x00, 0x00, 0x18, 0x22, 0x20, 0x00, 0xa0, 0x00, 0x01, 0x00, 0x10, 0x08, 0xed, 0x00, 0xe0\n\t"
        ".byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x74, 0xb2, 0x4e, 0x7a\n\t");
#endif