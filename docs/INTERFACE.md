# 寄存器与数据接口 v1.1

ID 为 `0x4C410101`。寄存器基址 `0x43C00000`，BRAM 基址 `0x42000000`，均为处理器物理地址。统一使用 32 位对齐读写；寄存器支持 AXI byte strobes，未定义偏移读 0、写忽略。AXI AW/W 独立握手，B/R 在背压期间保持稳定。

| 偏移 | 名称 | 说明 |
|---|---|---|
| 0x00 | ID | 只读版本标识 |
| 0x04 | COMMAND | bit0=ARM，bit1=CANCEL，写 1 产生脉冲；同时置位时 CANCEL 优先 |
| 0x08 | STATE | 0 IDLE，1 WAITING，2 POST，3 DONE，4 ERROR，5 DRAIN |
| 0x0C | CFG_MASK | 启用通道 bit0..7，不得为 0 |
| 0x10 | CFG_DIV | 1、2、5、10、50；采样率=50 MHz / DIV |
| 0x14 | CFG_TRIGGER | bits1:0：0立即、1上升、2下降、3电平组合；bits6:4 为边沿触发通道 |
| 0x18 | CFG_LEVEL_MASK | 电平触发参与通道；电平触发时非零且必须包含于启用通道 |
| 0x1C | CFG_LEVEL_VALUE | `(sample & mask) == (value & mask)` 时满足电平触发 |
| 0x20 | CFG_PRE | 0/1/2/3 对应 0/25/50/75% |
| 0x24 | START_INDEX | 最终时间顺序第一点在物理环形 RAM 中的字节索引 |
| 0x28 | VALID_COUNT | 完成后为 32768；未完成不能读取为有效记录 |
| 0x2C | TRIGGER_INDEX | 触发点在逻辑连续记录中的索引 |
| 0x30/34 | FIRST_TICK | 低/高 32 位，最终窗口第一点时间 |
| 0x38/3C | TRIGGER_TICK | 低/高 32 位，触发点时间 |
| 0x40 | ACTIVE_MASK | 当前采集实际锁存的 mask |
| 0x44 | ACTIVE_DIV | 当前采集实际锁存的 divider |
| 0x48 | STAT_CHANNEL | 选择统计通道 0..7 |
| 0x4C | EDGE_COUNT | 本次采集会话该通道边沿数量 |
| 0x50/54 | FIRST_EDGE_TICK | 首个边沿低/高 32 位，无边沿时为 0 |
| 0x58/5C | LAST_EDGE_TICK | 最后边沿低/高 32 位，无边沿时为 0 |
| 0x60 | TEST_MODE | bits1:0=0关闭/1UART/2I²C/3SPI；bits3:2=SPI模式0..3；bit4=UART错误注入 |
| 0x64 | KEYS | 低两位为消抖后的按下状态，1=按下 |
| 0x68 | TEST_LEVELS | 四个自测引脚实际读回电平，供接线/上拉调试 |

## 所有权与一致性

配置寄存器可以随时修改，但一次采集在 ARM 时锁存配置。ARM 只在 IDLE、DONE、ERROR 接受；CANCEL 可随时中止。读取 BRAM 只在 DONE 后进行，期间不要重新启动采集。硬件忽略 CPU 对 BRAM 的写操作。

ARM 端将采集前的分析选项另存为 `acquired_options`，避免等待触发时编辑下一次设置影响当前结果。有效记录的逻辑第 i 点：

```text
physical_byte = (START_INDEX + i) & 32767
sample = (read32(BRAM_BASE + (physical_byte & ~3)) >> (8 * (physical_byte & 3))) & 255
sample_tick = FIRST_TICK + i * ACTIVE_DIV
```

最后一笔缓存写完成后才进入 DONE，元数据冻结到下一次 ARM/CANCEL。统计计数在运行期间会变，64 位统计/时间戳只保证 DONE 后一致。记录未完成、取消或非法配置均不能作为新有效记录导出。

采集 tick 为 64 位 50 MHz 自由运行计数，不是日期时间。软件边沿位置保留为样本序号，必要时换算为 tick 或相对微秒。

## 其他外设

| 外设 | 地址 | 用途 |
|---|---|---|
| AXI Quad SPI | 0x44A00000 | 单片选、标准 SPI、8 位传输、6.25 MHz TFT 接口 |
| AXI GPIO | 0x41200000 | bit0 DC、bit1 RES、bit2 BLK |
| AXI UARTLite | 0x40600000 | 115200 8N1，调试控制和原始记录导出 |

## C 接口

`la_record`：只读连续样本、采样率、启用通道、触发位置、时间基准。

`la_options`：候选通道掩码、自动/手动协议、手动通道角色、UART 波特率、SPI 模式。

`la_result`：UNKNOWN / CERTAIN / AMBIGUOUS / MANUAL、候选列表及候选溢出标志。

`la_candidate`：协议、角色、参数、有效字节数、错误数、规则评分。

`la_decoded`：选中候选的前 128 个解析条目和条目溢出计数；条目保留样本起止索引、字节、SPI 对向字节、类型和错误/ACK/地址标志。

解码器不访问寄存器、不分配堆内存，可直接在 Windows 上运行同一份 C 代码测试。
