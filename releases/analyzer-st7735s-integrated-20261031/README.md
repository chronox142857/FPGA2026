# 逻辑分析仪＋ST7735S整合版，2026-10-31

Git标签：`analyzer-st7735s-integrated-20261031`。器件`xc7z010clg400-1`，Vivado/SDK2018.2；使用原有J3小屏接线和3.3V供电。

保留已点亮的Verilog初始化/串行驱动，通过AXI画布桥接入8路采集、触发缓存、ARM协议识别和四页界面。修正显示复位与PS/AXI复位的关系，DC/RES/BLK引脚设置与独立成功版对齐。用户确认界面正常、KEY0可以切页。真实输入未回接，不能将本版标记为三协议实物采集已验收。

## 恢复下载

在仓库根目录运行PowerShell（先核对`docs/HARDWARE.md`接线）：

```powershell
$release='releases/analyzer-st7735s-integrated-20261031'
New-Item -ItemType Directory -Force build/export,build/sdk/hw | Out-Null
foreach($name in @('system.bit','system.hdf','analyzer.elf','analyzer.map','SHA256SUMS.txt')) {
    Copy-Item -LiteralPath (Join-Path $release $name) -Destination build/export -Force
}
Copy-Item -LiteralPath "$release/ps7_init.tcl" -Destination build/sdk/hw -Force
./scripts/program_jtag.ps1
./scripts/read_status.ps1
```

必须加载配套bit和ARM ELF；只加载bit不会自动出现四页菜单。脚本只临时下载，不写Flash。保持供电、不按RESET，等待初始绘制约数秒。KEY0短按切页，KEY1长按约1秒启动/取消采集。完整断电会丢失JTAG配置；RESET使ARM回启动位置时需重新下载，DAP报错时可能需要完整断电恢复。

## 源码构建与验证

在仓库根目录运行`./scripts/test.ps1`及`./scripts/build.ps1 -Stage All`。源代码与驱动位于`rtl/`、`firmware/`和`examples/st7735s_pl/`。依赖路径与覆盖参数见根README。

`SHA256SUMS.txt`校验配套四个导出文件；`FILES_SHA256SUMS.txt`额外校验本目录其余冻结产物。bit SHA256为`5a5ab497473bd2c398564e56c259ac9d310481d47916d911369a5ff6a4363a16`。

当前报告：WNS+9.878ns、WHS+0.041ns，TNS/THS=0；LUT2046、FF3115、BRAM16、DSP2。DRC无错误/严重警告、五条普通DSP流水线建议。ARM链接末地址0x2B280，低192KiB OCM剩余19840字节。

`validation_summary.txt`记录仿真通过项，`runtime_status.txt`记录实际ARM/接口状态。用户实物反馈及剩余验收项见`docs/VALIDATION.md`。满屏约1.2秒，刷新等待期间暂缓按键/串口处理；采集在PL独立执行。旧五色/独立文字标签保持可用。
