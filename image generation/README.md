<a id="cn"></a>

# 图像生成脚本说明

[中文](#cn) | [English](#en)

## 1. 功能说明

本目录包含将测试图案或实际图片转换为项目可用 `IMAGE.BIN` 的脚本，以及用于预览 RGB332 二进制图像的脚本。

当前目录内容：

- [generate_image_bin.py](generate_image_bin.py)：生成测试图案，或将 PNG/JPG 等图片缩放并转换为 320x240 RGB332 BIN
- [view_image_bin.py](view_image_bin.py)：预览 RGB332 BIN 文件，可窗口显示，也可导出 PPM 或输出 ASCII 预览
- [IMAGE.BIN](IMAGE.BIN)：示例输出文件

## 2. 输出格式

- 文件名通常使用 `IMAGE.BIN`
- 默认分辨率为 320x240
- 每个像素 1 字节，格式为 RGB332
- 总大小应为 76800 字节

## 3. 使用方式

### 3.1 生成测试图案

```bash
python generate_image_bin.py -o IMAGE.BIN -p gradient
python generate_image_bin.py -o IMAGE.BIN -p checker -b 8
python generate_image_bin.py -o IMAGE.BIN -p stripes -b 16
python generate_image_bin.py -o IMAGE.BIN -p ramp
```

### 3.2 从实际图片生成 BIN

```bash
python generate_image_bin.py -i input.png -o IMAGE.BIN
python generate_image_bin.py -i input.jpg -o IMAGE.BIN
```

脚本会将输入图片缩放到 320x240，并自动量化为 RGB332。

### 3.3 预览 BIN 文件

```bash
python view_image_bin.py IMAGE.BIN
python view_image_bin.py IMAGE.BIN --ascii
python view_image_bin.py IMAGE.BIN -o preview.ppm
```

## 4. 实际照片预留

后续可在这里放置真实照片或效果图。

### 4.1 原始图片

请在此处插入待转换的原始图片。

### 4.2 转换后显示效果

请在此处插入 FPGA + VGA 的实际显示照片。

### 4.3 转接板实物图

请在此处插入 breakout board 的实物照片。

<a id="en"></a>

# Image Generation Script Notes

[中文](#cn) | [English](#en)

## 1. Purpose

This directory contains the scripts used to generate project-compatible `IMAGE.BIN` files from test patterns or real images, as well as a preview tool for RGB332 binary images.

Current contents:

- [generate_image_bin.py](generate_image_bin.py): generates test patterns or converts PNG/JPG images into 320x240 RGB332 BIN files
- [view_image_bin.py](view_image_bin.py): previews RGB332 BIN files in a window, exports PPM, or prints an ASCII preview
- [IMAGE.BIN](IMAGE.BIN): sample output file

## 2. Output Format

- The output file is typically named `IMAGE.BIN`
- Default resolution is 320x240
- Each pixel uses 1 byte in RGB332 format
- Total file size should be 76800 bytes

## 3. Usage

### 3.1 Generate Test Patterns

```bash
python generate_image_bin.py -o IMAGE.BIN -p gradient
python generate_image_bin.py -o IMAGE.BIN -p checker -b 8
python generate_image_bin.py -o IMAGE.BIN -p stripes -b 16
python generate_image_bin.py -o IMAGE.BIN -p ramp
```

### 3.2 Generate BIN from a Real Image

```bash
python generate_image_bin.py -i input.png -o IMAGE.BIN
python generate_image_bin.py -i input.jpg -o IMAGE.BIN
```

The script resizes the input image to 320x240 and quantizes it into RGB332 automatically.

### 3.3 Preview a BIN File

```bash
python view_image_bin.py IMAGE.BIN
python view_image_bin.py IMAGE.BIN --ascii
python view_image_bin.py IMAGE.BIN -o preview.ppm
```

## 4. Reserved Space for Real Photos

You can place real project photos or screenshots here later.

### 4.1 Source Image

Insert the original source image here.

### 4.2 Display Result

Insert the real FPGA + VGA display photo here.

### 4.3 Breakout Board Photo

Insert the breakout board photo here.