# SD卡自动启动保存版（2026-10-31）

Git标签：`sd-boot-20261031`。适用于正点原子领航者ZYNQ7010、当前ST7735S接线。**首次独立冷启动已通过，用户确认文字清楚、KEY0能切页。** 多次冷启动统计和显示长期稳定性尚未验收。

## 恢复使用

1. 从本目录下载真正的二进制文件 `BOOT.bin`（GitHub文件页面使用Raw/Download，不能把网页另存为BOOT.bin）。
2. 校验SHA256：`857c88573bd738ccbe17c9ef34cbe2df8b012ae5407ca8e580d948f7fd58fbff`，长度2237264字节。
3. 用电脑读卡器将文件复制到现有FAT32卡根目录；先备份已有同名文件。用户当前卡约32GB，无需因本更新格式化。
4. 安全弹出，开发板断电时插入TF卡槽，BOOT_CFG 1/2均OFF，再上电等约10秒；不需要连接电脑或JTAG下载。短按并松开KEY0切页。

卡必须保留在板内。此方案没有写板载Flash；卡内文件保持旧版时，JTAG临时测试的新程序断电后仍会回到卡内版本。开发时直接JTAG更新bit和ARM程序，功能通过后再生成并换入新的BOOT.bin。

只适用于这里记录的板型/接线，不作为7020或未核实DDR板卡的启动文件。新RGB屏尚未适配，不能直接插入当前占用LCD引脚的工程。

## 内容与验证

- 应用和FPGA使用[analyzer-selftest-20261031](../analyzer-selftest-20261031/README.md)原产物，屏幕初始化与250kHz SPI不变。
- FPGA bit SHA256：`5a5ab497473bd2c398564e56c259ac9d310481d47916d911369a5ff6a4363a16`。
- ARM ELF SHA256：`7f78db8cf2852305b9eed6ad6f7f657b1fb02c0b58c62bafa363501b4177d4e8`。
- 7010供应商纯PL固化FSBL在加载后等待，缺应用交接。只在已核对输入哈希和指令的副本上将0xE6E4修正为跳转现有FsblHandoff；原始供应商文件未修改。
- FSBL初始化DDR/SD、配置FPGA，在0x00200000交接到小型加载器；加载器把未修改的应用复制到OCM0并进入原复位向量。DDR仅用于此启动路径，未实现DDR深度采集。
- 修正版写卡后读回SHA256一致。用户未连接电脑完成独立上电和显示/按键检查，再接下载器只读复核：SD模式5、OCM主程序一致、采集/显示ID正确、状态1、帧数5、screen_ok=1、应用循环时间前进。该次复核没有暂停CPU、下载、复位或写目标寄存器。
- 原先调试器临时补执行交接只作诊断，不计入此次独立冷启动通过证据。

`cold_boot_readonly.log`为最终成功复核原日志；其中工具清理临时文件的permission denied提示保留原样，但后续寄存器、程序比较和成功标记均完成。`cold_validation.json`保留结果及原日志哈希，`card_write.json`记录写卡校验，`manifest.json`记录输入产物哈希和交接修正。`SOURCE_SHA256SUMS.txt`记录相关源码/脚本的LF规范化SHA256；`SHA256SUMS.txt`记录本目录其余文件的原始字节哈希。不要修改已冻结文件后继续沿用旧校验表。

## 重建

参考[SD启动说明](../../docs/SD_BOOT.md)，用SDK2018.2运行 `python -X utf8 scripts/build_sd_boot.py`。需要原7010 FSBL准确输入，脚本默认本机例程路径，也可用 `--fsbl` 指定；拒绝其他哈希。这里只保存复合BOOT.bin，不单独保存原始FSBL文件。

脚本校验Bootgen分区头、修正后FSBL、FPGA和完整加载器/应用载荷。构建输出在build/sd_boot；写卡是另一个显式指定盘符的脚本，不自动格式化、烧Flash或重新下载板子。

当前未完成事项、外部STM32分工见[项目状态](../../docs/PROJECT_STATUS.md)和[信号源开发要求](../../docs/STM32_SIGNAL_SOURCE_REQUIREMENTS.md)。UART/SPI已有同板实物结果，I²C实物、独立源、最大速率与偶发局部乱码仍按各自记录待验收。
