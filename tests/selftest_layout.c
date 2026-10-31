/* Read these constants from an ARM object, rather than assuming host pointer
 * size or hardcoding firmware structure offsets in the hardware test harness. */
#include "ui.h"
#include <stddef.h>
const unsigned selftest_layout[]={
    sizeof(app_config),offsetof(app_config,divider),offsetof(app_config,trigger),
    offsetof(app_config,trigger_channel),offsetof(app_config,pretrigger),
    offsetof(app_config,mask),offsetof(app_config,level_mask),offsetof(app_config,level_value),
    offsetof(app_config,test_mode),offsetof(app_config,test_spi_mode),offsetof(app_config,repeat),
    offsetof(app_config,test_error),offsetof(app_config,decode),
    sizeof(la_options),offsetof(la_options,candidate_mask),offsetof(la_options,protocol),
    offsetof(la_options,channels),offsetof(la_options,spi_mode),offsetof(la_options,uart_baud),
    sizeof(la_record),offsetof(la_record,samples),offsetof(la_record,count),offsetof(la_record,sample_hz),
    offsetof(la_record,trigger_index),offsetof(la_record,first_tick),offsetof(la_record,trigger_tick),
    offsetof(la_record,channel_mask),sizeof(la_result),offsetof(la_result,candidates),
    sizeof(la_candidate),offsetof(la_candidate,rate),offsetof(la_candidate,valid),offsetof(la_candidate,errors),
    sizeof(la_decoded),offsetof(la_decoded,events),offsetof(la_decoded,event_count),
    offsetof(la_decoded,dropped),sizeof(la_event),offsetof(la_event,data),offsetof(la_event,aux),
    offsetof(la_event,type),offsetof(la_event,flags),sizeof(ui_state),offsetof(ui_state,page),
    offsetof(la_candidate,channels),offsetof(la_candidate,mode)
};
