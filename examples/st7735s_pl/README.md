# ST7735S：ZYNQ7010独立PL显示已验证版本

2026-10-30用户实物确认：**花屏消失，全屏红、绿、蓝、黑、白正常循环**。这是独立的Verilog显示测试工程，使用领航者ZYNQ7010板载50MHz时钟，无需ARM应用。逻辑分析仪主工程的ARM界面尚未与本例程合并。

版本标签：`st7735s-fullscreen-20261030`。已验证的bit/ltx在`artifacts/`，bit SHA256：

```text
62c3451a80ef6f0d72a94ae9d03e8d716cba6e43b2f360090cdae723c31feb6c
```

## 已验证配置

- 顶层`st7735s_top`，器件`xc7z010clg400-1`，Vivado2018.2。
- `INIT_PROFILE=2`保留STM32参考程序的77个初始化字节和逐字节CS行为。
- RES低100ms；RES释放到Sleep Out、Sleep Out到下一命令均等待150ms，修正参考C的两处50ms不足。
- 窗口偏移X=2、Y=3；全屏地址X=2..129、Y=3..130。原参考0/32曾造成顶部固定花屏。
- RGB565高字节先发，MSB先发，升沿采样；SCK普通位高/低各2µs，逐字节结束及间隔保持高。
- 初始化后打开背光，依次循环五种颜色，每屏停留500ms。
- 已验证bit包含ILA/VIO输出记录功能，**屏幕寄存器读取关闭**；未写入Flash，断电后需重新下载。

## 接线

以内排靠板中央、外排靠PCB边缘定位J3，球位名称不是连接器针号。

| 屏幕 | 线色 | 开发板 |
|---|---|---|
| GND | 棕 | GND |
| VCC | 白 | 3.3V |
| SCL | 橙 | V17，J3内排 |
| SDA | 黄 | V18，J3外排 |
| RES | 绿 | Y18，J3内排 |
| DC | 蓝 | R18，J3外排 |
| CS | 紫 | T17，J3内排 |
| BLK | 灰 | Y19，J3外排 |

板载时钟U18，低有效PL复位N16。所有信号LVCMOS33；J3与并行RGB LCD共用IO。屏幕标记ST7735S、HD14008H14 JY，1.44寸128×128。

## 恢复已验证文件

在本目录打开PowerShell，保持原接线并连接JTAG：

```powershell
New-Item -ItemType Directory -Path build -Force | Out-Null
Copy-Item artifacts/st7735s_top.bit,artifacts/st7735s_top.ltx -Destination build
./scripts/program_jtag.ps1
```

下载脚本暂停两个ARM核，只临时配置PL并检查DONE/EOS。保持供电，观察约20秒颜色循环。

## 从源码构建与检查

```powershell
./scripts/test.ps1
./scripts/test_debug.ps1
./scripts/build.ps1 -DebugLcd
./scripts/program_jtag.ps1
./scripts/capture_init.ps1
```

默认Vivado/SDK路径为`E:\fpga\Vivado\2018.2`及`E:\fpga\SDK\2018.2`，可通过脚本参数覆盖。参考C对照需要Python和Windows GCC，默认GCC为`E:\DevC++\Dev-Cpp\MinGW64\bin\gcc.exe`。Python检查脚本的首个参数可覆盖GCC路径。普通`build.ps1`不生成调试核；`-DebugLcd`只记录FPGA输出，另加`-ReadPanel`才启用历史的可选屏幕读取功能。

主机检查直接执行参考C生成串行字节，五个核心测试台及debug重启/150ms测试通过。实际JTAG启动记录解出908个完整字节，77个初始化字节、窗口及红色像素与期望一致，两个等待分别150.00408ms和150.00204ms。WNS +11.547ns、WHS +0.041ns，TNS/THS=0；debug总线偏斜全部通过。数据与报告在`artifacts/`。

本次验收为全屏填色，不包含文字、方向、长期运行或逻辑分析仪功能。历史排查记录见`BRINGUP_HISTORY.md`；其中本机绝对路径和早期失败状态保留为历史资料，当前使用本目录相对路径构建。

## 参考来源

`reference/stm32_csdn_original/`保留用户提供的原C参考与主机记录器；`reference/slow_gpio_0044/`保留此前GPIO实现。原文件编码及换行保留，测试桩不是完整STM32 HAL。芯片时序依据[ST7735S V1.1手册](https://files.waveshare.com/upload/e/e2/ST7735S_V1.1_20111121.pdf)9.17/10.1.8；用户提供的ST7735 V1.7中文翻译71/91页交叉确认相同等待要求。
