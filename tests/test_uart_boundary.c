/* Independent known-stream oracle for capture windows beginning inside bytes.
 * Waveform uses absolute time, not decoder events or its baud estimator. */
#include "la.h"
#include <stdio.h>
#include <stdlib.h>

static uint8_t samples[LA_DEPTH];
static la_decoded decoded;
static const unsigned bit_ticks=434, sample_ticks=10;

static unsigned payload(unsigned frame,unsigned seed) {
    return (seed+frame*19u)&255u;
}
static unsigned frame_at(unsigned ticks) {
    unsigned slot=ticks/bit_ticks;
    return (slot/128u)*8u+(slot%128u)/10u;
}
static unsigned source(unsigned ticks,unsigned seed,int bad_stop) {
    unsigned slot=ticks/bit_ticks,phase=slot%128u,b=phase%10u;
    if(phase>=80u)return 1;
    if(!b)return 0;
    if(b==9)return !(bad_stop && phase/10u==3u);
    return (payload(frame_at(ticks),seed)>>(b-1u))&1u;
}
static void check_window(unsigned origin,unsigned seed,int bad_stop) {
    la_record record={samples,LA_DEPTH,5000000,0,0,0,1};
    unsigned i,n=0,last_frame=0,errors=0;
    for(i=0;i<LA_DEPTH;i++)samples[i]=(uint8_t)source(origin+i*sample_ticks,seed,bad_stop);
    la_decode_uart(&record,0,115200,&decoded);
    for(i=0;i<decoded.event_count;i++) {
        const la_event *e=&decoded.events[i];
        unsigned absolute,slot,phase,frame,delta;
        if(e->type!=LA_BYTE || (e->flags&LA_TRUNCATED))continue;
        absolute=origin+e->sample*sample_ticks;
        slot=(absolute+sample_ticks)/bit_ticks;phase=slot%128u;
        frame=(slot/128u)*8u+phase/10u;
        delta=absolute>slot*bit_ticks?absolute-slot*bit_ticks:slot*bit_ticks-absolute;
        if(phase>=80 || phase%10 || delta>sample_ticks ||
           e->data!=payload(frame,seed) ||
           !!(e->flags&LA_FRAME_ERROR)!=!!(bad_stop && phase/10u==3u) ||
           (n && frame!=last_frame+1u)) {
            fprintf(stderr,"FAIL origin=%u seed=%u bad=%d event=%u sample=%lu data=%02x flags=%u slot=%u delta=%u previous_frame=%u\n",
                    origin,seed,bad_stop,i,(unsigned long)e->sample,e->data,e->flags,slot,delta,last_frame);
            exit(1);
        }
        last_frame=frame;n++;if(e->flags&LA_FRAME_ERROR)errors++;
    }
    if(n<30 || (!bad_stop && errors) || (bad_stop && errors<3)) {
        fprintf(stderr,"FAIL too few valid oracle events (%u), errors=%u\n",n,errors);exit(1);
    }
}
int main(void) {
    unsigned origin,seed,cases=0;
    for(seed=0;seed<256;seed+=17)for(origin=0;origin<128u*bit_ticks;origin+=137) {
        check_window(origin,seed,0);check_window(origin,seed,1);cases+=2;
    }
    printf("PASS UART boundary corpus: %u windows; every complete decoded byte matches absolute source timing/data/error\n",cases);
    return 0;
}
