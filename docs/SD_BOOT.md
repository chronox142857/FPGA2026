# SD 卡自动启动（首次独立冷启动通过）

目标硬件为正点原子领航者 ZYNQ7010。SD 启动拨码为 BOOT_CFG 1=OFF、2=OFF；改变拨码后需断电再上电。卡保留在开发板 TF 槽中，根目录放置 `BOOT.bin`。

已验证文件及冻结证据见[sd-boot-20261031](../releases/sd-boot-20261031/README.md)。恢复可直接使用其中BOOT.bin，无需重新生成FPGA工程。

当前进度：首个启动文件已写入用户确认的 D: 约 32GB FAT32 可移动卡并读回核对。后续用户确认插卡、断电重新上电后，读得 BOOT_MODE=5、REBOOT_STATUS=0x60400000；CPU0 停在供应商 FSBL 的 0xE6E4 等待循环，R0=0x00200000。DDR 内完整加载器和应用载荷与卡内封装逐字节一致。供应商这个“纯 PL 固化”FSBL 在 LoadBootImage 返回后缺少应用交接，这是当前已定位的启动阻塞。

临时通过调试器将 CPU0 的 PC 指向原有 FsblHandoff（0x1380），没有重新下载镜像，应用随后启动：OCM 指令匹配发布 ELF、采集/显示 ID 正确、显示状态=1、首帧完成、screen_ok=1、应用循环时间前进。用户确认文字清楚、KEY0 能切页。此项属于调试器辅助验证，**不算自主冷启动通过**。

修正版已写入用户再次确认的 D: FAT32 可移动卡，读回校验通过，旧 BOOT.bin 已备份到 `build/sd_card_backup/20261031_170009_409/`。用户在开发板断电时插卡、OFF/OFF 上电后确认文字清楚、KEY0 能切页。

随后只读核对通过：BOOT_MODE=5，REBOOT_STATUS=0x00400000，OCM 指令与发布 ELF 一致；采集 ID=0x4C410101、显示 ID=0x4C440101、显示状态=1、帧数=5、screen_ok=1，应用循环时间从 57943 前进到 58351。本次没有下载、复位、暂停 CPU 或写目标寄存器，成功标记 `SD_AUTONOMOUS_BOOT_VERIFIED_WITHOUT_TARGET_WRITES`。日志：`build/sd_boot/cold_check/20261031_170331_569427/status.log`；写卡日志：`build/sd_boot/card_write.json`。

这是首次完整独立冷启动通过，未宣称多次冷启动或长期显示稳定性已验收。此前偶发乱码记录仍保留。

## 启动文件组成

1. 用户本地 7010 例程附带的 `zynq_fsbl.elf`，负责板卡 DDR、SD 和 FPGA 配置。构建时仅将已核对版本的 0xE6E4 指令从等待循环 `0xEAFFFFFE` 改为跳转原有 FsblHandoff 的 `0xEAFFCB25`。原供应商文件不修改，输出副本记录补丁和哈希。输入 SHA、前一条 LoadBootImage 调用及交接函数入口不匹配时拒绝构建。7010/7020 的 DDR 不同，不能替换成 7020 文件或通用预设。
2. `releases/analyzer-selftest-20261031/system.bit`，保持已保存测试版不变。
3. `boot/sd/ocm_loader.S` 生成的 DDR 跳转程序，加载到 `0x00200000`。FSBL 交接后将原应用复制到 OCM 地址零，再进入原应用复位向量。

引入跳转程序的原因：原应用运行在低地址 OCM，直接由常规 FSBL 加载会覆盖 FSBL 自身。启动阶段临时使用 DDR，应用的采集缓存和运行内存布局保持原样。本方案依赖供应商 FSBL 正确初始化本板 DDR，必须经过实际冷启动验证。

本次未修改显示初始化、SPI 刷新速度或逻辑分析仪程序，未写板载 Flash。卡片自动启动依赖卡内文件，不需要电脑每次重新下载。

供应商文件来源：`E:\FPGAproject\ZYNQ_7010_FPGA\ZYNQ_7010_FPGA\11_key_led\zynq纯PL端固化脚本\zynq_fsbl.elf`。SHA256 为 `e69bc124d76f6eeecaebd1ff6a5fb354576f41937571d61b0c6458762a8eb569`；同目录文件说明明确区分 7010/7020 DDR。原始FSBL不单独发布，重建时需提供这个准确输入；冻结目录提供已经包含修正FSBL的整机BOOT.bin。

## 构建与写卡

在仓库根目录使用 SDK 2018.2 执行：

```powershell
python -X utf8 scripts\build_sd_boot.py
```

输出到 `build/sd_boot/`。构建脚本校验原发布文件、指定 FSBL、BOOT 头和分区校验和，并逐字节检查封装后的 FPGA、加载器和应用载荷。只生成文件，不写卡。

将卡接到电脑，先确认实际盘符、容量和文件系统，再执行（以下 D 仅对应本次用户确认的卡）：

```powershell
.\scripts\write_sd_boot.ps1 -DriveLetter D
```

写卡脚本要求 FAT32 可移动卷；已有 BOOT.bin 会先备份到本地。通过临时文件写入、刷盘、替换和读回校验完成，不格式化、不写其他分区。安全弹出后，在开发板断电时插卡，拨码 OFF/OFF，再上电。

首个已写卡候选：2237264 字节，SHA256 `11d528f57301ae1ea68e3131a161c0ea1700bf93817a598fe65c52c041fb1db4`，存在上述缺失交接问题。

交接修正版：2237264 字节，SHA256 `857c88573bd738ccbe17c9ef34cbe2df8b012ae5407ca8e580d948f7fd58fbff`。原 FPGA、ARM 应用、OCM 加载器保持原哈希，只有 FSBL 交接指令及由 Bootgen 更新的相关校验变化。修正版写卡、读回及首次独立冷启动通过。

## 验收方法

先保持卡启动后的状态，不运行 JTAG 下载脚本。连接下载器后执行：

```powershell
python -X utf8 scripts\check_sd_boot.py
```

此脚本不暂停、不复位、不下载、不写目标寄存器。它核对启动模式低三位等于 5、OCM 指令与封装应用一致、采集/显示接口 ID、首帧完成和应用循环时间前进。每次日志保存在 `build/sd_boot/cold_check/<时间>/`。成功标记为 `SD_AUTONOMOUS_BOOT_VERIFIED_WITHOUT_TARGET_WRITES`。

内部检查通过后，仍须用户确认屏幕文字清楚、KEY0 能切页，并再次断电上电复现。若需要 JTAG 强制重画才能显示，应单独记录为显示冷启动问题，不能算无需电脑的完整验收通过。当前项目已有偶发乱码、全屏重画恢复的记录，见 VALIDATION.md。

参考：[正点原子启动方式说明](https://www.openedv.com/thread-331198-1-1.html)、[AMD Zynq FSBL 说明](https://docs.amd.com/r/en-US/ug821-zynq-7000-swdev/First-Stage-Bootloader)。
