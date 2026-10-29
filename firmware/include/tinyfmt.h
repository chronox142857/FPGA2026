#ifndef TINYFMT_H
#define TINYFMT_H
#include <stddef.h>
/* Integer-only bounded formatter: %% %c %s %d %u %x %X, optional l/width/zero pad. */
int la_snprintf(char *dst,size_t size,const char *fmt,...);
#endif
