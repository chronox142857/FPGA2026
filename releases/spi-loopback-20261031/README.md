# SPI四模式实物回接验证（2026-10-31）

Git标签：`spi-loopback-20261031`。这是同一程序的补充证据快照，不包含新编译的固件。程序和恢复步骤见[analyzer-selftest-20261031](../analyzer-selftest-20261031/README.md)。

- FPGA bit SHA256：`5a5ab497473bd2c398564e56c259ac9d310481d47916d911369a5ff6a4363a16`。
- ARM ELF SHA256：`7f78db8cf2852305b9eed6ad6f7f657b1fb02c0b58c62bafa363501b4177d4e8`。
- 四根短线：P15→W18、P16→W19、V16→R16、W16→R17。ST7735S接线不变，3.3V供电。

## 结果

32组全部通过：模式0～3 × 预触发0/25/50/75% × AUTO/手动；均5MSa/s、32768点、源时钟100kHz、CS下降沿触发。

每次核对环形BRAM与ARM数据一致、CS触发边沿、采样时间和通道掩码。AUTO保留实际模式和角色候选，输出AMBIGUOUS；不能唯一确定方向/相位时不强行宣称唯一识别。已知角色/模式下，ARM解析与独立物理线采样核对的每个完整CS事务相同，包括两个相同数据字节、下一事务按0x13递增、双向数据互补，以及字节起止采样序号。

每次39～41个完整字节、19～20个完整事务，窗口末尾恰有一个TRUNCATED DESELECT标记。已检查错误计数只来自采集窗口结束，没有完整事务结构错误。未通过人为清零错误计数掩盖截断。

用户确认“小屏文字清楚，显示正常”；结果页在每轮完成后整屏重画，SPI屏时钟和初始化未改，刷新提速尚未开始。最终界面留在额外一次模式0 AUTO采集的解析页，测试输出关闭，记录冻结、ARM运行。

I2C因缺上拉电阻未实测；SPI最高速率、独立设备、全部8通道及SPI实物100次等仍待验证。同板发生器/采样共享时钟，这些结果不标定绝对频率，也不证明对任意外部SPI波形都能唯一辨别模式。

## 证据与复跑

`matrix_summary.json`给出32组结果；`physical_evidence.zip`保留每组的物理BRAM、ARM样本、寄存器、候选、解析事件、结构偏移与调试日志。`offline_recheck.log`记录最终脚本对全部32组原始证据的再验证。`runtime_status.log`是最后额外一次AUTO采集后的运行核查；`output_disabled.log`记录测试输出已关闭。`SHA256SUMS.txt`校验本目录冻结文件。

接好四根短线、上电、下载对应bit/ELF后，在仓库根目录执行（默认SDK需与源码一致）：

```powershell
foreach($mode in 0..3) {
    python scripts/selftest_jtag.py --protocol spi --mode $mode --count 4 --cycle-pre
    python scripts/selftest_jtag.py --protocol spi --mode $mode --manual-spi --count 4 --cycle-pre
}
```

测试器先比较运行可执行代码与ELF，再使用生产主循环完成采集/读取/识别/解码，不注入样本。记录间短暂停ARM以导出证据，结束后恢复执行；不是无间隙连续采集。与旧SDK不匹配时可用脚本的release参数绑定`analyzer-selftest-20261031`产物及头文件。
