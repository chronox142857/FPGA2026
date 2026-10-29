#ifndef LA_REGS_H
#define LA_REGS_H
#define LA_ID             0x00u
#define LA_COMMAND        0x04u
#define LA_STATE          0x08u
#define LA_CFG_MASK       0x0cu
#define LA_CFG_DIV        0x10u
#define LA_CFG_TRIGGER    0x14u
#define LA_CFG_LEVEL_MASK 0x18u
#define LA_CFG_LEVEL      0x1cu
#define LA_CFG_PRE        0x20u
#define LA_START_INDEX    0x24u
#define LA_VALID_COUNT    0x28u
#define LA_TRIGGER_INDEX  0x2cu
#define LA_FIRST_TICK_LO  0x30u
#define LA_FIRST_TICK_HI  0x34u
#define LA_TRIG_TICK_LO   0x38u
#define LA_TRIG_TICK_HI   0x3cu
#define LA_ACTIVE_MASK    0x40u
#define LA_ACTIVE_DIV     0x44u
#define LA_STAT_CHANNEL   0x48u
#define LA_EDGE_COUNT     0x4cu
#define LA_FIRST_EDGE_LO  0x50u
#define LA_FIRST_EDGE_HI  0x54u
#define LA_LAST_EDGE_LO   0x58u
#define LA_LAST_EDGE_HI   0x5cu
#define LA_TEST_MODE      0x60u
#define LA_KEYS           0x64u
#define LA_TEST_LEVELS    0x68u
#define LA_CMD_ARM 1u
#define LA_CMD_CANCEL 2u
#define LA_IDLE 0u
#define LA_WAITING 1u
#define LA_POST 2u
#define LA_DONE 3u
#define LA_ERROR 4u
#define LA_DRAIN 5u
#endif
