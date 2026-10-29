#include "tinyfmt.h"
#include <stdarg.h>
#include <stdint.h>
typedef struct {char *p;size_t size,n;} output;
static void emit(output *o,char c){if(o->size && o->n<o->size-1)o->p[o->n]=c;o->n++;}
int la_snprintf(char *dst,size_t size,const char *fmt,...) {
    output o={dst,size,0};va_list ap;va_start(ap,fmt);
    while(*fmt) {
        unsigned width=0,zero=0,is_long=0;
        if(*fmt!='%'){emit(&o,*fmt++);continue;}
        fmt++;
        if(*fmt=='0'){zero=1;fmt++;}
        while(*fmt>='0' && *fmt<='9'){if(width<100)width=width*10+(unsigned)(*fmt-'0');fmt++;}
        if(*fmt=='l'){is_long=1;fmt++;}
        if(*fmt=='s') {
            const char *s=va_arg(ap,const char *);if(!s)s="?";
            while(*s)emit(&o,*s++);
        } else if(*fmt=='c')emit(&o,(char)va_arg(ap,int));
        else if(*fmt=='%')emit(&o,'%');
        else if(*fmt=='d' || *fmt=='u' || *fmt=='x' || *fmt=='X') {
            char buf[16];unsigned n=0,negative=0,base=(*fmt=='x'||*fmt=='X')?16:10;
            const char *digits=*fmt=='X'?"0123456789ABCDEF":"0123456789abcdef";uint32_t v;
            if(*fmt=='d') {
                int32_t s=is_long?(int32_t)va_arg(ap,long):(int32_t)va_arg(ap,int);
                negative=s<0;v=negative?0u-(uint32_t)s:(uint32_t)s;
            } else v=is_long?(uint32_t)va_arg(ap,unsigned long):(uint32_t)va_arg(ap,unsigned int);
            do{buf[n++]=digits[v%base];v/=base;}while(v);
            if(negative && zero)emit(&o,'-');
            while(width>n+negative){emit(&o,zero?'0':' ');width--;}
            if(negative && !zero)emit(&o,'-');
            while(n)emit(&o,buf[--n]);
        } else if(*fmt)emit(&o,'?');
        if(*fmt)fmt++;
    }
    va_end(ap);
    if(size)dst[o.n<size?o.n:size-1]=0;
    return (int)o.n;
}
