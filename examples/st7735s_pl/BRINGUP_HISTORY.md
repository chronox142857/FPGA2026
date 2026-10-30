# 本地验证记录

日期：2026-10-30（Asia/Shanghai）。项目：`E:\FPGAproject\FPGA\FPGA`。

器件：`xc7z010clg400-1`。工具：本机Vivado/XSim 2018.2。顶层`st7735s_top`，输入时钟50MHz。本文按开发顺序保留记录；下面的1MHz、74字节和debug实测均属历史版本，当前默认配置变更见文末。板子已连接并进行过JTAG临时下载，没有写入Flash。

## 仿真结果

`scripts/test.ps1`实际执行成功，包含两个测试台：

| 测试台 | 已验证内容 |
|---|---|
| tb_st7735s_driver | 74字节初始化及关键命令、每字节8位、CS建立/保持、SCK高低电平/周期、DC稳定性、矩形4像素、边界单点、非法坐标不发送、全屏填充字节数量和边界数据、两次原始字节发送及单周期raw_done |
| tb_st7735s_top | 无外部复位操作也能自动启动、板级1MHz串行时钟、传输中异步复位后输出回到安全空闲、释放后重新从Sleep Out初始化、首帧完成前背光关闭 |

仿真通过缩短等待计数加速运行，不以仿真墙钟时间证明实物复位延时；板级默认计数对应50MHz。库模块测试使用默认12.5MHz检查串行时序，板级测试单独检查顶层覆盖后的1MHz。

日志：`build/sim/tb_st7735s_driver.log`、`build/sim/tb_st7735s_top.log`。

## 综合、实现和bitstream

`scripts/build.ps1`实际完成综合、优化、布局、布线及bitstream生成，无错误或严重警告。文件：`build/st7735s_top.bit`，长度2,083,847字节；SHA256保存在`build/SHA256SUMS.txt`。

| 资源 | 使用 |
|---|---:|
| LUT | 256 / 17600（1.45%） |
| 寄存器 | 176 / 35200（0.50%） |
| BRAM | 0 / 60 |
| DSP | 1 / 80 |
| 外部IO | 8（时钟、复位、六根屏幕信号） |

内部50MHz约束下：WNS=+13.998ns，TNS=0；WHS=+0.122ns，THS=0，无失败脉宽检查。报告：`build/timing_summary.rpt`、`utilization.rpt`。

DRC保留三条普通警告：DPOP-1、DPOP-2为像素数量乘法器的流水线建议；ZPS7-1提示当前设计没有PS7单元。本工程以外部50MHz振荡器驱动PL，不使用PS提供的FCLK、ARM或DDR，按独立JTAG实验工程使用。关于无PS时钟的PL独立设计，可参考[Trenz厂商说明](https://wiki.trenz-electronic.de/display/PD/ZYNQ+Design+not+using+A9+Cores)及[AMD PL配置说明](https://docs.amd.com/r/en-US/ug585-zynq-7000-SoC-TRM/PL-Configuration-Considerations)。这些提示未被隐藏或降低等级。完整报告：`build/drc.rpt`。

综合中未使用的raw接口寄存器等被优化，是演示模块固定关闭raw输入等连接产生的正常裁剪；原始驱动接口另外通过仿真验证。

## 接线约束与边界

XDC已覆盖全部8个顶层IO，屏幕信号对应此前确认的J3球位：SCL V17、SDA V18、RES Y18、DC R18、CS T17、BLK Y19；时钟U18、复位N16。电源线按3.3V/GND接，不作为逻辑端口。

没有实测模块端负载或建立/保持时间，未编造LCD外部输出延迟约束。内部时序通过与RTL串行时序检查不能替代真实模块端的信号完整性、供电、颜色、偏移和背光检查。

初始化表和面板偏移沿用本目录已有Verilog版本，未按昨天ARM方案替换。原README所指`../Src/bsp_lcd.c/.h`不在当前目录树，故尚不能独立核对原C代码的所有寄存器值。此前白屏没有在本轮得到实物验证或修复确认。

## 本轮首次连接与临时下载

用户确认板子已连接后，JTAG链检测到xc7z010及两个运行中的Cortex-A9。下载前核对bitstream SHA256为`5965b1e9995c2ab17326e3a3054a77adee13b52b7b77b665719a4085482751bc`，与构建记录一致。

新增独立的`scripts/program_jtag.tcl/.ps1`：暂停两个ARM核，避免旧软件访问本PL测试中不存在的AXI外设；只向xc7z010下载`build/st7735s_top.bit`，不下载ELF、不执行PS初始化、不写Flash。已实际执行成功，XSCT报告100%并输出明确完成标记`LCD_FPGA_LOADED_PL_ONLY:`。日志：`build/check_jtag.log`、`build/jtag_download.log`。

已请用户观察10秒红绿蓝整屏循环。此刻只确认配置下载完成，屏幕显示结果待用户反馈。

用户反馈白屏，并补充刚刚按过reset。随后Hardware Manager读到DONE=0，CONFIG_STATUS=0x46001F0C，表明读取时配置/启动未完成；未确认按键种类和状态变化的确切时间，不直接断言所有复位都会清除PL配置。

随后通过Hardware Manager重新下载同一bit，立即读得CONFIG_STATUS=0x46107FFC，命名字段DONE_PIN=1、END_OF_STARTUP_(EOS)_STATUS=1、IR.DONE=1，并报告End of startup HIGH。日志：`build/program_status_run.log`。已要求用户不按复位再观察10秒。

下载包装脚本已补上读取DONE/EOS的配置检查，避免把100%上传进度单独当作配置完成。PL局部复位与PS/配置复位应分别确认；本轮新工程不依赖ARM应用，不能沿用此前“ARM回到ROM”的诊断结论。


## 用户要求芯片返回状态：纯PL读回及内部实测

用户确认DONE/EOS均为1后仍反馈白屏；因此本次白屏不能以未配置完成解释。随后按当时用户要求新增`st7735s_readback.v`，SDA由IOBUF半双工读回，新增可选ILA/VIO调试构建。当时调试构建默认读回；目前已改成必须显式加`-ReadPanel`，普通构建和仅`-DebugLcd`均不读取屏幕。

新增读回仿真通过，模型检查最后命令位升沿仍由FPGA驱动、下降沿前已高阻、读响应期间无驱动冲突；四个32位原始流正确保留，包含一次性启动和无回应全1情况。原驱动及板级启动/复位仿真也再次通过，日志`build/readback_test_run.log`。

调试实现资源：LUT1983（11.27%）、寄存器3130（8.89%）、BRAM4（6.67%）；WNS +12.404ns、WHS +0.042ns，TNS/THS均0。DRC无错误/严重警告，四条普通提示为DPOP-1、DPOP-2、ZPS7-1及debug核RTSTAT-10。内部debug跨时钟总线偏斜另行检查，四项均MET，最小裕量19.149ns，日志`build/bus_skew.rpt`。当前bit及匹配ltx在build中，原普通bit留在`build/normal_backup/`。

已实际下载，DONE/EOS=1，JTAG检测到1个ILA和1个VIO核。读得lcd_init_done=1、app_rst_n=1、read_done=1、read_busy=0、pad_flags=6；raw_id/raw_power/raw_madctl/raw_colmod全部FFFFFFFF。日志`build/lcd_read_status_run.log`。这证明FPGA完成了读回尝试及SDA近端自检，没有取得有效显示芯片回应；不能据此单独判定模块损坏或声称模块支持读回。

ILA实采16384点（50MHz），CS低触发，取得40个完整字节，CS/SCK/DC帧无错误，SCK周期50点，即1MHz；窗口为X=0..127、Y=32..159，随后2C写入001F蓝色像素。RES/BL均为高。日志`build/lcd_capture_run.log`、`build/lcd_spi_trace.csv`及`build/lcd_spi_decoded.json`。此结果验证FPGA逻辑及IOBUF读回节点的片段，不能验证杜邦线另一端电气波形或屏体内部状态。

## 恢复凌晨00:44慢速GPIO配置（当前版本，23:01下载）

用户要求停止屏幕读回和电气排查，转而比较此前慢刷新版本。本轮只核对源代码、仿真、实现及FPGA配置状态，没有再次读取LCD寄存器或要求电压测量、改线。

备份来源：`E:\FPGAproject\FPGA2026\build\diagnostic\first_light_gpio\`，备份时间2026-10-30 00:44:38，配置为软件SPI、初始化profile1、窗口偏移2/3、MADCTL=C8。该版曾获得一次“色条或文字”反馈，后来重试仍白屏，所以作为行为参考，不作为已稳定点亮的证明。源文件复制在`reference/slow_gpio_0044/`。

当前顶层默认改为INIT_PROFILE=1、SPI_HALF_CYCLES=100、X/Y偏移2/3。恢复复位高100ms→低100ms→高100ms，先写帧率/电源/VCOM/Gamma/F0/F6/3A/36，等100ms，11命令后等120ms，29命令后等20ms。初始化78字节；命令包与参数包分开，每组参数保持CS低。每行设置窗口，256字节像素保持CS低，高字节优先。SCK高2µs、普通位间低4µs，连续位约166.7kHz，字节/包间另有开销。演示为逐行整屏红绿蓝循环，与原C四竖条和ARM界面有所区别。

独立执行备份C初始化：`check_slow_reference.py`用主机GPIO记录器解码C输出，78个字节、34个CS包以及六个长延时全部与参考一致，记录`build/sim/slow_c_trace.txt`。`scripts/test.ps1`四个测试台均通过：原CSDN驱动、板级1MHz配置回归、离线读回模型回归，以及新增慢速配置。后者验证复位阶段、78字节、等待阶段、CS连续性、SCK高低时长、首行/末行窗口、256字节RGB565行数据。仿真中的毫秒计数加速，串行位时序使用真实50MHz。

普通构建READBACK_ENABLE=0，无ILA/VIO；`-DebugLcd`不再自动开启屏幕读取，必须另外显式指定`-ReadPanel`。本轮实际采用普通构建。综合、布局布线、bitstream通过；LUT266/17600、寄存器199/35200、BRAM0、DSP1、外部IO8。WNS=+14.355ns、WHS=+0.131ns，TNS/THS=0。DRC无错误/严重警告；四项普通提示为DPOP-1/2、ZPS7-1，以及读回关闭后SDA输入缓冲无负载的BUFC-1。报告`build/timing_summary.rpt`、`utilization.rpt`、`drc.rpt`。

当前`build/st7735s_top.bit` SHA256：`30b190e96788679e9794d9c3d4cc7b30a9e6fd24246c2da63f03c5bc293c3063`。2026-10-30 23:01通过JTAG实际下载，确认DONE=1、EOS=1；没有Flash写入。日志`build/slow_build_run.log`、`build/slow_program_run.log`。普通版本无debug核，Hardware Manager提示未检测到debug hub属预期。

已请用户观察20秒是否出现逐行铺色与红绿蓝循环，显示结果待反馈。初始化/协议差异已消除到上述范围，尚不能据此确认白屏原因或宣布显示修复。

后续用户反馈：此00:44慢速配置仍为均匀白屏，未通过显示验收；随后提供了STM32原版源码的本地位置，进入下述对照。

## STM32原版逐项复现（当前默认配置2）

原文件位于`E:\FPGAproject\STM32_reference\STM32_reference`。已读取`bsp_lcd.c/.h`、`main.c`、`gpio.c`，复制原始文件到`reference/stm32_csdn_original/`，未改动源文件。`bsp_lcd.c`原件与副本SHA256均为`D687993285BD98C5C2051D4A3555CD95E4E6E05CBAD47B6F23C1EA8ACADD237B`。

发现原版与此前修订/慢速配置的差异：GPIO初始CS/SCK/DC/SDA/RES/BL为低；RES低100ms、释放50ms、Sleep Out后50ms；B3后连续9个参数；每个字节先CS低，再将SCK拉低、设置MOSI、升沿发送，末位后不拉低SCK，先CS高，字节间保持SCK高；窗口X偏移0、Y偏移32；初始化后在填屏前打开背光。原main展示红绿蓝黑白，各停留500ms。没有将这些差异直接等同于白屏根因。

新增INIT_PROFILE=2复现以上行为，配置0和1保留；顶层默认选2，SPI_HALF_CYCLES=100，普通位低/高各2µs，数据高字节先发，按整屏窗口连续填色，CS每字节释放。原C通过HAL调用翻转IO，没有固定的位延时，故只能复现逻辑顺序，不能由C源码确定其真实SPI频率。B3九参数和两个50ms延时仅为原版对照测试，不称作通用初始化要求。

`check_stm32_reference.py`实际编译执行未修改的`bsp_lcd.c`，以主机HAL记录器代替GPIO，初值按`gpio.c`置低。检查77个初始化字节、100/50/50ms延时、SCK末位保持高、首字节7个下降沿/后续8个，以及32779字节整屏红色数据；生成`build/sim/stm32_wire_stream.hex`和`stm32_c_trace.txt`。记录器不执行原main、真实HAL或缺失的图片/串口依赖。

新增`tb_st7735s_stm32`对照全部32856个字节，检查初始输出、复位/恢复/退出休眠等待、每字节8位及CS边界、最后SCK高、完整全屏窗口及RGB565数据，已通过。已有四项回归也通过，共五个测试台；`build/stm32_test_run.log`。等待计数加速，串行测试采用分频2；实际板级配置采用分频100。READBACK_ENABLE继续为0，本轮没有再读取LCD寄存器或要求电气检查。

配置2普通构建已完成综合、实现与bitstream生成，WNS=+14.590ns、WHS=+0.197ns，TNS/THS=0，所有已定义时序约束通过。LUT270/17600、寄存器170/35200、BRAM0、DSP1、IO8。DRC无错误/严重警告，保留BUFC-1、DPOP-1/2、ZPS7-1四项普通提示，与上一普通版本类别一致。日志`build/stm32_build_run.log`。

当前bit SHA256：`8d7e1f4aa27c85c20f5a67a5e8ee3df6f214cb11a472221c77458a567cf83ff1`。2026-10-30 23:12通过JTAG实际下载；FPGA DONE=1、EOS=1，日志`build/stm32_program_run.log`。没有Flash写入，没有LCD状态读取；已请用户观察20秒红绿蓝黑白循环，实物显示待反馈。本次只是逐项复现原例程，不能仅凭仿真和配置成功判断白屏已经解决。

后续用户反馈：配置2仍然均匀白屏。停止继续更换初始化参数，转为记录FPGA上的实际复位和初始化输出。

## FPGA输出的完整启动记录

此前ILA只记录到正常填屏片段，缺少复位/初始化证据。本轮在可选LCD_DEBUG分支加入VIO局部重启、自由运行32位时间戳及输出变化事件；ILA启用存储条件，只在输出变化时保存，从而跨越100/50ms等待。普通构建不受影响，LCD寄存器读回保持关闭，六根信号接线和显示配置保持不变。

`test_debug.ps1`实际通过：使用仿真IP模型，检查VIO重新开始配置2初始化、时间戳在应用复位期间继续运行、事件观察器记录变化、read_busy恒0。日志`build/init_debug_test.log`。新增解码器也用原C参考生成的模拟CSV作正例、翻转一位MOSI作反例，确认能识别不匹配；该检查不代替硬件采样。

实现依据：Vivado安装目录的ILA6.2/VIO3.0参数定义，以及AMD官方[run_hw_ila](https://docs.amd.com/r/2021.2-English/ug835-vivado-tcl-commands/run_hw_ila)、[commit_hw_vio](https://docs.amd.com/r/2021.2-English/ug835-vivado-tcl-commands/commit_hw_vio)命令说明；实际使用本机2018.2执行和验证。输出观察不读取显示芯片寄存器，VIO只控制FPGA应用复位。

23:22的观察版本构建通过：SHA256=`49e3ae454d4338857d93f27aca5d84c07fd6e5edd6a50032123081c9671a729e`，DONE/EOS=1，LUT2354、寄存器3624、BRAM19、DSP1。WNS +12.225ns、WHS +0.031ns，TNS/THS=0；四项debug总线偏斜均MET，最小裕量19.179ns。DRC无错误/严重警告，普通四项DPOP-1/2、RTSTAT-10、ZPS7-1。日志`build/init_debug_build.log`、`init_debug_program.log`。

实际初始化采样完成，保存16384个变化事件、覆盖232.78892ms，解出908个完整字节及末尾2位；前77字节初始化和后续窗口/红色像素全部与原C参考相同。测得RES低100ms、11结束到下一次CS选择50.00204ms、SCK高/低各2µs、29结束到背光高0.02µs；没有异常应用/外部复位。VIO debug_status=0x60，表示READBACK_ENABLE=0、app_rst_n=1、lcd_init_done=1、read_busy=0。记录见`build/stm32_50ms_capture/`，保留对应bit/ltx、CSV和解码JSON。这是FPGA内部输出节点及SDA输入缓冲证据，不代表屏幕端已正确接收。

## 按手册修正两段等待

核对[ST7735S V1.1原手册](https://files.waveshare.com/upload/e/e2/ST7735S_V1.1_20111121.pdf)9.17脚注7及10.1.8：硬件复位释放后120ms内不能发Sleep Out，Sleep Out后也需等120ms再发后续命令。原STM32 C两段50ms虽被忠实复现，但不满足这些限制，不能将“与原C一致”视为“符合芯片要求”。现已将配置2默认两段等待都改为150ms，其余字节与波形保持不变。

用户随后提供`E:\FPGAproject\ST7735中文版.pdf`，已读取并渲染核查完整第71页（9.16复位时序，脚注7）和第91页（10.1.11 SLPOUT限制），同样要求这两个120ms等待。该资料是ST7735 V1.7（2009-12-04）的中文翻译，不是ST7735S专用模块说明；只采用与S版原手册一致的要求，未照搬型号相关寄存器差异。

默认150ms已通过新增debug测试断言。原C逐字节测试显式覆盖为50ms，保留作为历史原样对照。硬件解码器同步改为验证复位到第一SCK、11到后续命令均为150ms。此修改解决确认的等待违规，是否为白屏根因尚待实物反馈。

150ms修正版实际完成构建、下载与重新采样，DONE/EOS=1。SHA256=`8c746566dadfe6850efce33895cb69a7e286910fe06de6f983c1ed0eade39159`。WNS=+12.093ns、WHS=+0.030ns，TNS/THS=0；debug总线偏斜四项均MET，最小19.059ns；LUT2353、寄存器3624、BRAM19、DSP1；DRC无错误/严重警告，四项普通提示类别不变。日志`build/init_safe_build.log`、`init_safe_program.log`。

23:34的真实启动记录覆盖432.78892ms、16384个输出变化事件，解出908个完整字节及末尾2位，初始化77字节及窗口/红色像素参考全部一致。测得RES低100ms、RES释放到第一个SCK为150.00408ms、11结束到下一次CS选择为150.00204ms；SCK高低各2µs，29到背光高0.02µs。默认150ms解码断言通过；旧50ms实采文件按新默认规则会被拒绝。文件`build/lcd_init_trace.csv`、`lcd_init_decoded.json`及`init_safe_capture_run.log`，对应副本保存在`build/stm32_safe_capture/`。已请用户观察此修正版显示，反馈待定。

调试工具兼容性修正：2018.2当前ILA的CONTROL.TRIGGER_MODE是只读，改为读取校验BASIC_ONLY；CSV写入显式使用-force覆盖。处理脚本错误会释放VIO复位，避免将应用留在复位态。新增`capture_init.ps1`包装已验证的采样/解码命令；不额外触发LCD读回。

用户实际反馈150ms修正版：**基本全屏能随红绿蓝黑白循环，顶部约20%的中间部分仍花屏**。这是首次明确可复现的大面积填色反馈，不能将剩余花屏当作白屏问题继续更换初始化。完整bit/ltx、源代码和启动采样备份在`build/first_confirmed_display/`，SHA256仍为`8c746566dadfe6850efce33895cb69a7e286910fe06de6f983c1ed0eade39159`。

当前窗口仍为原STM32 C的X=0..127、Y=32..159。32行相当于128行的25%，与顶部约20%的未覆盖现象相符，首先检查窗口偏移；这是推断，待固定/移动区域反馈和调整后的实际显示验证。

## 全屏显示验收通过（当前版本）

用户确认花屏固定不动后，仅将板级窗口偏移从0/32调整为2/3，保留配置2全部初始化字节、两段150ms等待、SPI时序及填色流程。重新构建、下载并通过启动采样：908个完整字节核对通过，实际窗口X=2..129、Y=3..130，RES释放到首SCK=150.00408ms、11到下一CS选择=150.00204ms，SCK高/低各2µs，DONE/EOS=1。日志`build/geometry_test.log`、`geometry_build_run.log`、`geometry_program.log`、`geometry_capture.log`和`lcd_init_decoded.json`。

用户随后明确反馈：**“花屏消失，全屏正常循环”**。因此当前版本通过红/绿/蓝/黑/白全屏填色的实物显示验收；文字、图形方向、长期运行和逻辑分析仪界面仍不在本次验收范围。

当前bit SHA256=`62c3451a80ef6f0d72a94ae9d03e8d716cba6e43b2f360090cdae723c31feb6c`；WNS +11.547ns、WHS +0.041ns，TNS/THS=0；四项debug总线偏斜均MET，最小19.135ns；DRC无错误/严重警告。已验证下载文件、对应源码/约束/脚本和构建参考保存在`verified/st7735s_20261030/`。屏幕寄存器读取保持关闭，没有Flash写入。

本次增量构建复用相同的ILA/VIO IP，使用Vivado2018.2的`reset_run synth_1`并执行正常构建脚本的综合/实现/时序/DRC检查及导出部分；全新环境仍通过`scripts/build.ps1 -DebugLcd`完整重建。

## GitHub保存与文字恢复

用户要求先推送已验证版本，再恢复文字显示。已将五色基线保存至`chronox142857/FPGA2026`的`examples/st7735s_pl/`，提交`1fdfe816773054ff974ff5ea8d91055daf0741a2`，注释标签`st7735s-fullscreen-20261030`。远端main和标签解引用均核对为该提交；bit及原C的暂存对象SHA256与原文件一致，复制后的两套C参考检查通过。主工程原有未提交修改保留，未纳入本次保存。

当前文字开发继续位于本目录，GitHub标签保持为全屏五色基线。新增`st7735s_font5x7.v`和`st7735s_text_demo.v`，从原主工程`firmware/src/ui.c`47个5×7字符字模生成独立ROM，先全屏清黑，再通过已验证矩形接口逐点绘制。标题`LOGIC ANALYZER`、状态`SCREEN READY`，以及FPGA/协议名称、0..7通道、十六进制字符；页面明确标记DISPLAY TEST、CAPTURE OFF，不伪装采集或识别已运行。

`DISPLAY_TEXT=1`为当前默认，0保留五色生成器；初始化、等待、MADCTL、引脚及窗口不因文字模式改变。`test_text.ps1`的LCD GRAM模型从实际SPI字节重建所有像素，与独立按C字体行生成的画布比较：16384像素全部一致，共17788次像素写入（含16384点清屏），日志`build/text_test_run.log`。文字预览已人工目视核查。默认150ms及VIO重启集成测试仍通过，日志`build/text_debug_test.log`。本轮不启用LCD读回。

文字版普通构建通过，bit SHA256=`c021061ffc5c7c1d464985cac410ae1c8b8dd04e34cb2f8f2cc5ea245ae779e5`，WNS +9.478ns、WHS +0.122ns、TNS/THS=0；LUT440、寄存器177、BRAM0、DSP1。DRC无错误/严重警告，六项普通提示为BUFC-1、DPIP-1两项、DPOP-1/2、ZPS7-1。2026-10-30 23:58通过JTAG实际下载，DONE/EOS=1，没有Flash写入；日志`build/text_build_run.log`、`text_program_run.log`。

用户随后反馈“现在屏幕上有东西了”，并要求再次推送GitHub。该反馈确认已有实物显示内容，未额外声称方向、每个字符或颜色均已由用户逐项验收。文字恢复版本另用`st7735s-text-20261031`标签保存，五色`st7735s-fullscreen-20261030`标签保持不变。正常文字bit不带ILA/VIO，不应搭配旧五色debug的ltx；旧资料在GitHub的`artifacts/fullscreen_20261030/`保存。
