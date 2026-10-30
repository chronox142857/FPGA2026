# 用户提供的CSDN STM32原版参考

原位置：`E:\FPGAproject\STM32_reference\STM32_reference`。
`bsp_lcd.c`、`bsp_lcd.h`、`main.c`、`gpio.c`按原字节复制，保留原编码。

`stm32f1xx_hal.h`和`emit_stm32.c`是本项目增加的主机记录器，不属于原版，也不是完整STM32 HAL。只编译并执行`bsp_lcd.c`中的初始化和整屏红色填充；不会执行缺少串口、图片依赖的原`main.c`，不访问硬件。

运行`scripts/check_stm32_reference.py`：记录HAL GPIO写操作的串行位流，检查每字节8个升沿、末尾/间隔SCK高，输出77个初始化字节以及32779个填屏字节。生成`build/sim/stm32_wire_stream.hex`供Verilog逐字节比较；同时检查GPIO初值对应的首字节7次下降沿、后续字节8次下降沿。

原代码B3后有9个参数，RESET释放和Sleep Out后各50ms。配置2保留初始化字节和发送行为，但默认两段等待已按手册修正为150ms，板级窗口偏移调整为2/3；原样测试台显式覆盖50ms及0/32。配置0保留此前六参数修订版。九参数不作为通用初始化建议。C中没有位延时，无法仅凭源代码声称STM32实际SPI频率与FPGA相同。
