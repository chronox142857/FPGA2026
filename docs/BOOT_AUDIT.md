# 启动与程序残留核查（2026-10-31）

用户报告恢复发布原版后仍白屏，并询问之前调试是否在板内留下程序。此次仅通过调试器读取状态和内存，没有复位、下载、写显示寄存器、写Flash或修改启动拨码。

## 已取得的证据

- 读取SLCR BOOT_MODE（0xF800025C）=0x00000000，启动方式为JTAG。此模式冷启动不会自动加载本项目的bit和ARM程序；当前项目仅提供易失性下载，尚未制作自动启动镜像。
- FPGA采集接口ID=0x4C410101，显示接口ID=0x4C440101，与发布提交3b3488e匹配。导出bit和ELF的SHA256此前也已与发布文件核对一致。
- ARM核心0处于Running；last_paint两次只读采样递增。显示状态=1，发送器帧计数=3。这些只证明主机运行和发送器完成，不证明LCD收到命令或显示正常。
- 直接读取ARM内存中的.text（0x00000000，27428字节）和.rodata（0x00006B54，2616字节），与发布ELF对应节逐字节哈希核对一致。因此当前运行代码及常量中没有混用实验版的证据。
- FPGA_RESET=0x00000000、LEVEL_SHIFTERS=0x0000000F；与配套ps7_post_config所设值一致，不是PS到PL接口一直保持复位或电平转换器关闭。
- 在FPGA2026和用户提供的FPGA例程目录的Tcl、PowerShell、Python及日志中，未找到program_flash、write_cfgmem、program_hw_cfgmem等实际Flash烧写命令。已检查的本项目下载流程仅执行JTAG易失性配置及ARM内存下载。

没有读取QSPI/SD全部内容，因此不声称外部存储为空；当前JTAG启动模式不会自动运行其中可能存在的出厂镜像。没有理由为了本次白屏擦除Flash。

## 当前结论与限制

1. 断电后需要重新下载，这是当前启动交付范围的缺项，不是程序残留证据。
2. 完整重新下载原版后仍白屏，是另一项尚未解决的显示故障。不能用第1项解释第2项。
3. ARM显式启动LCD初始化的实验版（显示ID=0x4C440102）用户反馈仍全白，该实验未解决故障。其构建快照保留；板上已按用户要求恢复3b3488e原版，实验源码仍为未提交工作区修改。
4. 此次没有检测实际屏幕端动态信号，因此不能断言故障必然由初始化、时序或电气因素中的某一项造成。

原始只读脚本和记录：`build/audit_boot_readonly.tcl`、`build/audit_boot_readonly.log`；内存与ELF节快照：`build/audit_running_{text,rodata}.bin`、`build/audit_release_{text,rodata}.bin`。核查没有恢复显示，也未做新的显示验收。

启动模式依据：[AMD UG585启动模式引脚设置](https://docs.amd.com/r/en-US/ug585-zynq-7000-SoC-TRM/Boot-Mode-Pin-Settings)。
