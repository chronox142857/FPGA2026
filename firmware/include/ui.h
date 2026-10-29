#ifndef LA_UI_H
#define LA_UI_H
#include "la.h"
#define UI_W 128
#define UI_H 128
#define UI_SETTINGS 19
typedef struct {
    uint8_t divider,trigger,trigger_channel,pretrigger,mask,level_mask,level_value;
    uint8_t test_mode,test_spi_mode,repeat,test_error;
    la_options decode;
} app_config;
typedef struct {
    uint8_t page,editing,field,bank,zoom,candidate;
    uint32_t origin,event_offset,event_total;
} ui_state;
extern uint16_t ui_pixels[UI_W*UI_H];
void ui_defaults(app_config *,ui_state *);
void ui_render(const ui_state *,const app_config *,const la_record *,const la_result *,const la_decoded *,unsigned hw_state);
/* Return nonzero when selected candidate changed. */
int ui_short(ui_state *,app_config *,unsigned key,const la_record *,const la_result *);
void ui_back(ui_state *);
#endif
