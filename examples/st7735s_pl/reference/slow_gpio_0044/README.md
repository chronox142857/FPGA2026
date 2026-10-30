# 2026-10-30 00:44 慢速GPIO参考

`tft.c`、`board_config.h`未改动地复制自：
`E:\FPGAproject\FPGA2026\build\diagnostic\first_light_gpio\`。
这是曾获得一次“色条或文字”反馈、后续尚未稳定复现的版本，不能当作已证明可靠的硬件基准。

`tft.h`是相同API的公共声明，`xgpio.h/xspi.h/sleep.h`及`emit_init.c`仅用于在电脑上执行C初始化并记录输出，不访问开发板。测试不调用`tft_probe()`；当前用户要求停止读取屏幕。

运行`scripts/check_slow_reference.py`执行C初始化、记录SPI升沿上的字节及CS包边界，并与`../slow_gpio_init.hex`比较。原C注释“<=125kHz”不是精确频率：每位含三个2µs等待，理想周期6µs，GPIO/循环另有开销。

Verilog恢复初始化及逐行传输流程，演示像素仍采用红、绿、蓝整屏循环；旧C色条及ARM界面没有移植。全部像素采用RGB565、高字节优先。
