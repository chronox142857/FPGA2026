# 验证记录

验证日期：2026-10-29，Asia/Shanghai。主项目：`E:\FPGAproject\FPGA2026`。

## 已通过

| 项目 | 结果与范围 |
|---|---|
| 协议 C 测试 | 81 项检查通过：9档常见 UART 波特率、非标准17123 baud、停止位错误、截断、I²C三档速率/重复START/ACK/NACK、SPI四模式及5MHz、静态/30组确定性噪声、采样不足、手动设置等 |
| 采集 RTL | XSim 2018.2，100次采集通过；测试深度32点，以覆盖5档分频×4种触发×4种预触发的完整组合，并变化通道掩码；检查同步数据、时间、环形回绕、最后一笔写、忙时ARM、锁存配置、非法参数、WAIT/POST取消 |
| AXI RTL | AW先到/W先到/同时到、R/B背压、byte strobe、ID、ARM/CANCEL、记录元数据检查通过 |
| 默认深度贯通 | 使用默认32768点，Verilog发生器→采集核心→导出原始采样→同一套C分析器，共7组：正常UART、I²C、SPI0..3、错误UART |
| 数据内容核对 | 正常UART逐字节检查0x13递增序列；I²C检查地址A0；SPI四模式逐字节检查两方向按位取反关系 |
| 异常演示源 | Verilog UART停止位错误注入，在完整采样中检测到14个帧错误；保留错误条目，不计入正常字节 |
| 界面 | 四页离屏渲染、掩码菜单约束、返回操作、有边界的整数格式化测试通过，并人工查看布局预览 |
| 工程重建 | Vivado 2018.2实际执行脚本，block design验证通过；检查proc_sys_reset实际传播为低有效；关闭DDR |
| 综合与实现 | 实际完成综合、布局布线、bitstream生成；没有错误和严重警告；设计规则检查只剩3条DSP流水线建议 |
| ARM构建 | SDK 2018.2，Cortex-A9/VFPv3/hard-float，Release -Os，应用源码开启-Wall -Wextra -Werror -std=c99；实际链接成功 |

RTL与C贯通结果：UART识别115200 baud；I²C识别100000 Hz；SPI0..3均包含SPI候选并报告AMBIGUOUS，各自约100000 Hz。候选数量随波形不同，为5或6，符合保留模式/方向歧义的策略。噪声测试不代表对任意未知输入的全局误判率。

## 资源与时序

器件 `xc7z010clg400-1`，实现报告：

| 资源 | 使用 | 比例 |
|---|---:|---:|
| LUT | 2108 / 17600 | 11.98% |
| 寄存器 | 3314 / 35200 | 9.41% |
| BRAM | 8 / 60 | 13.33% |
| DSP | 1 / 80 | 1.25% |

50MHz约束下，WNS **+10.368ns**，TNS 0；WHS **+0.036ns**，THS 0；脉宽检查无失败。用户指定时序约束满足。外部探头、异步UART和实际屏幕的电气/时序表现仍需硬件验证，不能由内部时序通过代替。

三条剩余DRC普通警告为 DPIP-1、DPOP-1、DPOP-2，均针对触发时间偏移乘法器未额外流水化的性能建议；当前时序已满足。自测IO已显式使用IOBUF，原先的三态转换/缓冲不完整问题已修正。

ARM `size`：text=52348、data=1200、bss=127728字节，总和181276字节。考虑MMU表对齐、堆栈等布局后，链接末地址为 `0x0002F2F0`，小于低OCM的上限 `0x00030000`，剩余3344字节。堆栈已在链接脚本中预留；后续扩展须重新核对布局。当前不使用DDR。

## 产物与复现

- `build/export/system.bit`：FPGA配置文件。
- `build/export/system.hdf`：含bitstream的SDK硬件定义。
- `build/export/analyzer.elf`：ARM程序。
- `build/export/analyzer.map`：内存布局。
- `build/timing_summary.rpt`、`utilization.rpt`、`drc.rpt`：实际实现报告。
- `build/tests/tb_capture.log`、`tb_axi.log`、`tb_loopback.log`：XSim结果。
- `build/tests/loop_*.hex`：RTL产生的默认深度原始采样。
- `docs/ui-preview.png`：电脑渲染的2倍放大布局预览，不是上板照片。

从源码复现：`./scripts/test.ps1`，然后 `./scripts/build.ps1 -Stage All`。构建及测试生成文件已忽略，不依赖远程仓库保存缓存。测试默认使用本机已有的Windows GCC，其他电脑可通过-Gcc覆盖。

## 尚未完成的真实硬件验收

没有宣称完成JTAG下载、真实ARM读取BRAM、真实屏幕显示、真实按键、电气波形、最大协议速率或上板100次连续采集。还需核对板卡修订版/排针编号、PS参考时钟、屏幕控制芯片/供电/偏移/背光电路，按HARDWARE.md和USER_GUIDE.md上板逐项验收。

当前启动方式为JTAG易失性下载，断电后需重新下载。SD/QSPI独立启动、DDR深度缓存、DMA、历史记录和额外协议不属于此次首版交付。
