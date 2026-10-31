# 板载回接验证版（2026-10-31）

Git标签：`analyzer-selftest-20261031`。适用于领航者ZYNQ7010、Vivado/SDK2018.2及现有ST7735S接线。

FPGA与上一发布版完全一致，bit SHA256为`5a5ab497473bd2c398564e56c259ac9d310481d47916d911369a5ff6a4363a16`。仅更新ARM UART帧对齐逻辑，修正采集窗口开头误报残帧，以及错误停止位低电平与下一起始位合并后错位的问题。显示初始化、250kHz SPI配置和约1.2秒整屏传输速度保持不变；本版没有实施数字局部刷新提速。

## 已执行的验证

- 12992个独立UART窗口起点/错误停止位语料通过；原81项协议检查、采集与AXI仿真、默认32768点RTL贯通及五帧ARM画布到物理SPI输出像素回归通过。`regression.log`记录完整自动化回归。
- UART正常源约115200 baud、5MSa/s、32768点，真实P15→W18短线回接100次通过，四档预触发各25次；每次ARM样本与冻结BRAM一致，触发时间递增，AUTO速率及完整字节正确、0帧错误。见`uart_100_summary.json`。
- UART错误源8次通过，四档预触发各2次；手动指定UART115200后核对每个完整输出字节及坏停止位，错误之后的字节未再错位。见`uart_error_8_summary.json`。这是错误流的手动解码检查，不计作其自动识别通过。
- 用户换SDA线后恢复显示；测试中一次碎字经强制整屏重画后清楚。显示长期稳定性和局部刷新仍未验收，不能仅以PL发送完成代替实物显示确认。

本冻结版本SPI等待新增回接线，尚无实物结果；I2C因缺少上拉电阻尚未实测。真实最大速率、独立晶振源、全部8通道及其余触发方式仍待验收。同板源与采样共享时钟，无法标定绝对频率。

测试脚本只通过应用的正常配置/采集/分析流程取得结果，没有把软件生成的样本写入采集缓存。每次记录间经JTAG短暂停ARM导出证据，因此100次指重复采集完整性测试，不承诺无间隙连续采样。

## 恢复下载

先核对`docs/HARDWARE.md`接线，VCC为3.3V。在仓库根目录执行：

```powershell
$release='releases/analyzer-selftest-20261031'
New-Item -ItemType Directory -Force build/export,build/sdk/hw | Out-Null
foreach($name in @('system.bit','system.hdf','analyzer.elf','analyzer.map','SHA256SUMS.txt')) {
    Copy-Item -LiteralPath (Join-Path $release $name) -Destination build/export -Force
}
Copy-Item -LiteralPath "$release/ps7_init.tcl" -Destination build/sdk/hw -Force
./scripts/program_jtag.ps1
./scripts/read_status.ps1
```

这是JTAG临时下载，未写Flash；掉电后需重新下载。KEY0短按切页，KEY1长按启动/取消采集。完整刷新期间按键处理会延后。用户反馈白屏或碎字时不应仅重复确认内部寄存器就宣称显示已正常。

## 复跑UART

先断电接P15→W18，上电后恢复本版，保持小屏线不变：

```powershell
python scripts/selftest_jtag.py --protocol uart --count 100 --cycle-pre
python scripts/selftest_jtag.py --protocol uart-error --count 8 --cycle-pre
```

脚本默认核对本地SDK源码并比较板上可执行代码与ELF；复跑时需先由对应源码完成Software构建。仅恢复旧发布文件而SDK仍是其他版本时，不要绕过源码一致性检查。完整原始证据保存在本地build/hardware_selftest，发布目录另存压缩证据。

硬件时序/资源报告沿用未改动bit所对应的上一发布报告，并非重新实现的结果。ARM text46872/data1152/bss127616，OCM布局上界0x2B280。`firmware_sources.json`记录按LF归一化后的构建对应源文件SHA256；`SHA256SUMS.txt`校验四个导出文件，`FILES_SHA256SUMS.txt`校验本目录冻结产物。
