#ifndef LA_H
#define LA_H
#include <stdint.h>
#include <stddef.h>
#define LA_DEPTH 32768u
#define LA_MASTER_HZ 50000000u
#define LA_MAX_EVENTS 128u
#define LA_MAX_CANDIDATES 16u
enum la_protocol { LA_AUTO=0, LA_UART=1, LA_I2C=2, LA_SPI=3 };
enum la_result_status { LA_UNKNOWN=0, LA_CERTAIN=1, LA_AMBIGUOUS=2, LA_MANUAL=3 };
enum la_event_type { LA_BYTE=0, LA_START=1, LA_RESTART=2, LA_STOP=3, LA_SELECT=4, LA_DESELECT=5 };
enum la_flags { LA_FRAME_ERROR=1, LA_TRUNCATED=2, LA_NACK=4, LA_ADDRESS=8, LA_READ=16 };
typedef struct {
    const uint8_t *samples;
    uint32_t count, sample_hz, trigger_index;
    uint64_t first_tick, trigger_tick;
    uint8_t channel_mask;
} la_record;
typedef struct {
    uint32_t sample, end_sample;
    uint16_t data, aux;
    uint8_t type, flags;
} la_event;
typedef struct {
    uint8_t protocol, channels[4], mode, score;
    uint32_t rate, valid, errors;
} la_candidate;
typedef struct {
    la_candidate candidate;
    la_event events[LA_MAX_EVENTS];
    uint32_t event_count, dropped;
} la_decoded;
typedef struct {
    uint8_t candidate_mask, protocol, channels[4];
    int8_t spi_mode; /* -1 searches modes; 0..3 is explicit */
    uint32_t uart_baud; /* 0 estimates */
} la_options;
typedef struct {
    uint8_t status, candidate_count, more_candidates;
    la_candidate candidates[LA_MAX_CANDIDATES];
} la_result;
void la_decode_uart(const la_record *, uint8_t ch, uint32_t baud, la_decoded *);
void la_decode_i2c(const la_record *, uint8_t scl, uint8_t sda, la_decoded *);
void la_decode_spi(const la_record *, const uint8_t channels[4], uint8_t mode, la_decoded *);
void la_identify(const la_record *, const la_options *, la_result *);
void la_decode_candidate(const la_record *, const la_candidate *, la_decoded *);
const char *la_protocol_name(uint8_t);
uint64_t la_sample_tick(const la_record *, uint32_t sample);
#endif
