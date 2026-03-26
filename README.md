# DE1-SoC TF Card Reader and VGA Display
## 1. Overview

This project targets the DE1-SoC board and uses FPGA logic to access a TF card in SD Native 1-bit mode. It parses a FAT32 file system, locates `IMAGE.BIN`, stores a 320x240 RGB332 image into on-chip RAM, and displays it through VGA at 640x480@60Hz using 2x pixel scaling.

Main data path:

`TF Card -> sdcmd_ctrl -> sd_reader -> sd_file_reader -> img_ram -> vga_ctrl -> VGA`

This repository includes:

- Synthesizable RTL
- Quartus pin constraints
- Layered UVM verification environment
- RGB332 image generation and preview utilities

## 2. Features

- SD native initialization sequence: CMD0, CMD8, CMD55, ACMD41, CMD2, CMD3, CMD7, CMD16
- CMD17 single-block read with DAT0 data capture
- FAT32 parsing: MBR, boot sector, root directory, and file data
- Automatic search for `IMAGE.BIN`
- VGA output after buffering image data in RAM
- Python tools for generating and previewing RGB332 test images
- Layered UVM verification environment from Layer1 to Layer3

## 3. Hardware Result

The design has been validated on real hardware. After correcting the TF card DAT pin mapping, the system can display the full `IMAGE.BIN` image successfully.

Current debug indicators:

- `HEX0 = 6`: file reader state machine reached `DONE`
- `LEDR0 = 1`: `IMAGE.BIN` found
- `LEDR1 = 1`: image read completed

`LEDR6` is currently a latched historical timeout indicator, so it may remain on even when the final display is successful.

## 4. Required Materials

- DE1-SoC fpga board
- TF or Micro SD card
- TF card breakout board(schematic provided in this project) or custom adapter
- VGA monitor and VGA cable
- USB-Blaster programming cable
- Windows host PC
- Intel Quartus Prime Lite 18.1
- QuestaSim
- Python 3

## 5. Repository Structure

- [RTL/top_sd_vga.sv](RTL/top_sd_vga.sv): top-level integration
- [RTL/sdcmd_ctrl.sv](RTL/sdcmd_ctrl.sv): SD command and response controller
- [RTL/sd_reader.sv](RTL/sd_reader.sv): SD initialization and sector reader
- [RTL/sd_file_reader.sv](RTL/sd_file_reader.sv): FAT32 parsing and file reader
- [RTL/img_ram.sv](RTL/img_ram.sv): image RAM
- [RTL/vga_ctrl.sv](RTL/vga_ctrl.sv): VGA timing controller
- [quartus/pin_assign.tcl](quartus/pin_assign.tcl): pin assignment reference script
- [uvm_tb](uvm_tb): UVM verification environment
- [generate_image_bin.py](generate_image_bin.py): generate RGB332 image files
- [view_image_bin.py](view_image_bin.py): preview RGB332 image files

## 6. Pin Mapping

The following TF card mapping is the currently verified working configuration:

| Signal | JP1 Pin | GPIO_0 | FPGA Pin |
| --- | --- | --- | --- |
| SD_CLK | 20 | GPIO_0_D17 | PIN_AA19 |
| SD_CMD | 18 | GPIO_0_D15 | PIN_AG17 |
| SD_DAT3 | 16 | GPIO_0_D13 | PIN_AE16 |
| SD_DAT2 | 14 | GPIO_0_D11 | PIN_AH17 |
| SD_DAT1 | 24 | GPIO_0_D21 | PIN_AJ20 |
| SD_DAT0 | 22 | GPIO_0_D19 | PIN_AC20 |
| SD_CD | 26 | GPIO_0_D23 | PIN_AK21 |

## 7. IMAGE.BIN Format

- The file name must be `IMAGE.BIN`
- Default resolution is 320x240
- Pixel format is RGB332
- Total size is `320 x 240 = 76800` bytes
- The file must be stored in a FAT32 file system so the design can locate it automatically

## 8. Generate and Preview Images

Generate test images:

```bash
python generate_image_bin.py -o IMAGE.BIN -p gradient
python generate_image_bin.py -o IMAGE.BIN -p checker -b 8
python generate_image_bin.py -o IMAGE.BIN -p stripes -b 16
python generate_image_bin.py -o IMAGE.BIN -p ramp
```

Preview images:

```bash
python view_image_bin.py IMAGE.BIN
python view_image_bin.py IMAGE.BIN --ascii
python view_image_bin.py IMAGE.BIN -o preview.ppm
```

**中文**
## 1. 项目简介

本项目基于 DE1-SoC 开发板，使用 FPGA 逻辑直接以 SD Native 1-bit 模式读取 TF 卡，解析 FAT32 文件系统中的 `IMAGE.BIN` 文件，将 320x240、RGB332 格式的图像写入片上 RAM，并通过 VGA 输出为 640x480@60Hz、2 倍放大的图像。

项目主数据路径如下：

`TF Card -> sdcmd_ctrl -> sd_reader -> sd_file_reader -> img_ram -> vga_ctrl -> VGA`

当前仓库同时包含：

- 可综合的 RTL 设计
- Quartus 工程与引脚约束
- QuestaSim/UVM 分层验证环境
- RGB332 图像生成与预览脚本

## 2. 功能特性

- SD 原生模式初始化流程：CMD0, CMD8, CMD55, ACMD41, CMD2, CMD3, CMD7, CMD16
- 单块读命令 CMD17 与 DAT0 数据接收
- FAT32 解析：MBR、Boot Sector、Root Directory、文件数据读取
- 自动查找 `IMAGE.BIN`
- 图像缓存到 RAM 后通过 VGA 显示
- 支持 Python 工具快速生成和预览 RGB332 测试图像
- 提供 Layer1 到 Layer3 的 UVM 验证环境

## 3. 当前硬件结果

项目已经在实际硬件上完成验证，修正 TF 卡 DAT 引脚映射后，可以完整显示 `IMAGE.BIN` 图像。当前调试指示含义如下：

- `HEX0 = 6`：文件读取状态机进入 `DONE`
- `LEDR0 = 1`：找到 `IMAGE.BIN`
- `LEDR1 = 1`：图像读取完成

`LEDR6` 在当前设计中是历史超时锁存灯，即使最终成功显示，也可能保持点亮。

## 4. 所需材料

- DE1-SoC 开发板
- TF 卡或 Micro SD 卡
- TF 卡转接板或自制连接板
- VGA 显示器与 VGA 线缆
- USB-Blaster 下载线
- Intel Quartus Prime Lite 18.1
- QuestaSim
- Python 3

## 5. 仓库结构

- [RTL/top_sd_vga.sv](RTL/top_sd_vga.sv): 顶层模块
- [RTL/sdcmd_ctrl.sv](RTL/sdcmd_ctrl.sv): SD CMD 发送与响应接收
- [RTL/sd_reader.sv](RTL/sd_reader.sv): SD 初始化与扇区读取
- [RTL/sd_file_reader.sv](RTL/sd_file_reader.sv): FAT32 解析与文件读取
- [RTL/img_ram.sv](RTL/img_ram.sv): 图像 RAM
- [RTL/vga_ctrl.sv](RTL/vga_ctrl.sv): VGA 时序控制
- [pin_assign.tcl](pin_assign.tcl): 引脚分配参考脚本
- [sim/Makefile](sim/Makefile): 仿真入口
- [generate_image_bin.py](generate_image_bin.py): 生成 RGB332 图像文件
- [view_image_bin.py](view_image_bin.py): 预览 RGB332 图像文件

## 6. 关键引脚映射

当前已经在硬件上验证可工作的 TF 卡映射如下：

| Signal | JP1 Pin | GPIO_0 | FPGA Pin |
| --- | --- | --- | --- |
| SD_CLK | 20 | GPIO_0_D17 | PIN_AA19 |
| SD_CMD | 18 | GPIO_0_D15 | PIN_AG17 |
| SD_DAT3 | 16 | GPIO_0_D13 | PIN_AE16 |
| SD_DAT2 | 14 | GPIO_0_D11 | PIN_AH17 |
| SD_DAT1 | 24 | GPIO_0_D21 | PIN_AJ20 |
| SD_DAT0 | 22 | GPIO_0_D19 | PIN_AC20 |
| SD_CD | 26 | GPIO_0_D23 | PIN_AK21 |


## 7. 图像文件格式

- 文件名必须为 `IMAGE.BIN`
- 分辨率默认为 320x240
- 像素格式为 RGB332
- 总字节数为 `320 x 240 = 76800` 字节
- 文件需放入 FAT32 文件系统中，供设计自动搜索

## 8. 生成与预览图像

生成测试图像：

```bash
python generate_image_bin.py -o IMAGE.BIN -p gradient
python generate_image_bin.py -o IMAGE.BIN -p checker -b 8
python generate_image_bin.py -o IMAGE.BIN -p stripes -b 16
python generate_image_bin.py -o IMAGE.BIN -p ramp
```

预览图像：

```bash
python view_image_bin.py IMAGE.BIN
python view_image_bin.py IMAGE.BIN --ascii
python view_image_bin.py IMAGE.BIN -o preview.ppm
```

