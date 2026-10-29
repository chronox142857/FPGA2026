# 接线与首次启动

主项目目录：`E:\FPGAproject\FPGA2026`。本文件的封装引脚来自本机领航者 7010 配套 FPGA 例程，不代表已经核对过你手中板卡的修订版或排针编号。

## 引脚来源与分配

采用开发板原有 **RGB LCD 排针中的数据线** 接入探头和小尺寸 SPI 屏，不使用并行 RGB 显示协议。不得同时连接原有并行 RGB 面板。本机参考文件：

```text
E:\FPGAproject\ZYNQ_7010_FPGA\ZYNQ_7010_FPGA\21_lcd_rgb_colorbar\prj\lcd_rgb_colorbar.srcs\constrs_1\new\lcd_rgb_colorbar.xdc
E:\FPGAproject\ZYNQ_7010_FPGA\ZYNQ_7010_FPGA\11_key_led\prj\key_led.srcs\constrs_1\new\key_led.xdc
E:\FPGAproject\ZYNQ_7010_FPGA\ZYNQ_7010_FPGA\19_uart_loopback\prj\uart_loopback.srcs\constrs_1\new\uart_loopback.xdc
```

| 项目端口 | 原 LCD 信号 | FPGA 封装引脚 | 作用 |
|---|---|---|---|
| probe[0] | LCD_D0 | W18 | CH0 |
| probe[1] | LCD_D1 | W19 | CH1 |
| probe[2] | LCD_D2 | R16 | CH2 |
| probe[3] | LCD_D3 | R17 | CH3 |
| probe[4] | LCD_D4 | W20 | CH4 |
| probe[5] | LCD_D5 | V20 | CH5 |
| probe[6] | LCD_D6 | P18 | CH6 |
| probe[7] | LCD_D7 | N17 | CH7 |
| tft_sck | LCD_D8 | V17 | 彩屏 SCL（SPI 时钟） |
| tft_mosi | LCD_D9 | V18 | 彩屏 SDA（SPI 写数据） |
| tft_cs_n | LCD_D10 | T17 | 彩屏 CS |
| tft_ctrl[0] | LCD_D11 | R18 | 彩屏 DC |
| tft_ctrl[1] | LCD_D12 | Y18 | 彩屏 RES |
| tft_ctrl[2] | LCD_D13 | Y19 | 彩屏 BLK 控制 |
| test_io[0] | LCD_D14 | P15 | 自测 TX / SCL / SCK |
| test_io[1] | LCD_D15 | P16 | 自测 SDA / MOSI |
| test_io[2] | LCD_D16 | V16 | 自测 MISO |
| test_io[3] | LCD_D17 | W16 | 自测 CSn |

这里的 W18 等是 **Zynq 球位名称，不是排针编号**。接线前应在板卡原理图或 IO 分配表中找到 LCD_D0 等信号对应的排针编号。当前资料中没有这份已核实的表，不能直接把 W18 当成排针第 18 针。

板载连接：50 MHz 时钟 U18；低有效 PL 复位 N16；KEY0/KEY1 为 L14/K16；LED0/LED1 为 H15/L15；板载 USB UART 的 PL RX/TX 为 T19/J15，115200 8N1。

## 彩屏

用户提供的接口为 `GND VCC SCL SDA RES DC CS BLK`，符合常见 4 线 SPI 写入接口，不是 I²C。屏幕驱动默认 ST7735 系列、RGB565、128×128；`board_config.h` 中提供控制寄存器、X/Y 偏移、反色开关，实际芯片型号仍需由模块资料确认。

- GND 接公共地；VCC 按实际模块要求供电；不要因为有 VCC 名称就默认可接 5V。
- FPGA 信号按 LVCMOS33 配置，外部信号须匹配对应 IO Bank 电压；禁止将 5V、RS232、RS485 或 CAN 电平直接接入采集脚。
- BLK 只有在模块自带限流/驱动、允许逻辑控制时才接 GPIO；若它是裸背光电源脚，应使用合适的限流与驱动，不能让 FPGA IO 承担背光电流。
- 默认 SPI 6.25 MHz（50 MHz / 8）、模式 0；初始化后先检查红绿蓝白色条、128×128 四角、偏移和方向，再查看文字。
- SPI 是单向的。`TFT SPI init=1` 仅说明驱动调用成功，不能证明屏幕已正确显示。

## 自测回接

先将测试发生器关闭（复位默认关闭），再接回路。只能将测试输出接到本项目的输入，不能接到其他正在输出的信号。

| 测试 | 回接 | 额外要求 |
|---|---|---|
| UART | test_io[0] → CH0 | 共地 |
| I²C | test_io[0] → CH0，test_io[1] → CH1 | SCL/SDA 各用适当电阻上拉至 3.3V，例如短线低速演示可先用 4.7 kΩ；确认边沿满足采样要求 |
| SPI | test_io[0..3] → CH0..3 | 共地 |

I²C 测试源是开漏输出，未加上拉时释放状态可能悬空。内部仿真使用理想上拉，不替代硬件上拉验证。

## 首次运行

1. 核对板卡型号、PS 33.333 MHz 参考时钟、PL 50 MHz 时钟和上述排针连接。工程关闭 DDR，也不启用 SD/QSPI/MIO 外设，不使用未经核实的 DDR 参数。
2. 保持外部输入断开，构建并打开串口 115200 8N1。
3. 将启动方式设为适用于 JTAG 的配置，连接下载器、供电。按板卡手册操作启动拨码。
4. 通过 SDK/XSCT 手动运行 `scripts/program_jtag.tcl`，或者在 SDK 选择生成的 HDF、bit 和 ELF。脚本仅用于易失性下载，不写 Flash。
5. 检查串口版本与寄存器 ID；LED0 为慢心跳，LED1 为采集完成指示。
6. 运行 `color` 检查屏幕。若白屏、偏移或颜色颠倒，先核对模块型号及 `board_config.h`，不要先修改采样逻辑。
7. 接自测回路，再按 USER_GUIDE 的三类演示命令逐项验证。

由短盘符生成的 SDK 工作区同样引用该盘符。JTAG 调试前可手动将仓库映射回原盘符，例如在确认 T: 空闲后使用 `subst T: E:\FPGAproject\FPGA2026`，退出调试后 `subst T: /D`。`build.ps1` 在构建期间会自动管理该映射。

## 仍需真实硬件确认的项目

板卡修订版与排针编号、屏幕控制芯片及供电/背光电路、输入电压、PS 参考时钟、真实采样信号、电气边沿、按键手感、屏幕刷新表现和上板连续采集。构建与仿真不等于这些项目已经通过。
