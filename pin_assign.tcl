# ====================================================================================
# DE1-SoC Pin Assignments for top_sd_vga
# ====================================================================================

# 1. System Clock & Reset
# ------------------------------------------------------------------------------------
set_location_assignment PIN_AF14 -to CLOCK_50
set_location_assignment PIN_AA14 -to KEY[0]
set_location_assignment PIN_AA15 -to KEY[1]
set_location_assignment PIN_W15  -to KEY[2]
set_location_assignment PIN_Y16  -to KEY[3]

# 2. SD Card Interface (GPIO_0 Mapping)
# ------------------------------------------------------------------------------------
# Mapping Reference:
# SD_CLK    -> GPIO Header Pin 20 -> GPIO_0[17] -> PIN_AA19
# SD_CMD    -> GPIO Header Pin 18 -> GPIO_0[15] -> PIN_AG17
# SD_DAT[3] -> GPIO Header Pin 16 -> GPIO_0[13] -> PIN_AE16
# SD_DAT[2] -> GPIO Header Pin 14 -> GPIO_0[11] -> PIN_AH17
# SD_DAT[1] -> GPIO Header Pin 24 -> GPIO_0[21] -> PIN_AJ20
# SD_DAT[0] -> GPIO Header Pin 22 -> GPIO_0[19] -> PIN_AC20
# SD_CD     -> GPIO Header Pin 26 -> GPIO_0[23] -> PIN_AK21 (Used to pull high)

set_location_assignment PIN_AA19 -to SD_CLK
set_location_assignment PIN_AG17 -to SD_CMD

# User-verified DAT order: DAT3=Pin16, DAT2=Pin14, DAT1=Pin24, DAT0=Pin22
set_location_assignment PIN_AE16 -to SD_DAT[3]
set_location_assignment PIN_AH17 -to SD_DAT[2]
set_location_assignment PIN_AJ20 -to SD_DAT[1]
set_location_assignment PIN_AC20 -to SD_DAT[0]

# Pin 26 output (Ensure "assign SD_CD = 1'b1;" is in your Verilog)
set_location_assignment PIN_AK21 -to SD_CD

# 3. VGA Interface (Standard DE1-SoC DAC Pins)
# ------------------------------------------------------------------------------------
set_location_assignment PIN_A11  -to VGA_CLK
set_location_assignment PIN_B11  -to VGA_HS
set_location_assignment PIN_D11  -to VGA_VS
set_location_assignment PIN_F10  -to VGA_BLANK_N
set_location_assignment PIN_C10  -to VGA_SYNC_N

set_location_assignment PIN_A13  -to VGA_R[0]
set_location_assignment PIN_C13  -to VGA_R[1]
set_location_assignment PIN_E13  -to VGA_R[2]
set_location_assignment PIN_B12  -to VGA_R[3]
set_location_assignment PIN_C12  -to VGA_R[4]
set_location_assignment PIN_D12  -to VGA_R[5]
set_location_assignment PIN_E12  -to VGA_R[6]
set_location_assignment PIN_F13  -to VGA_R[7]

set_location_assignment PIN_J9   -to VGA_G[0]
set_location_assignment PIN_J10  -to VGA_G[1]
set_location_assignment PIN_H12  -to VGA_G[2]
set_location_assignment PIN_G10  -to VGA_G[3]
set_location_assignment PIN_G11  -to VGA_G[4]
set_location_assignment PIN_G12  -to VGA_G[5]
set_location_assignment PIN_F11  -to VGA_G[6]
set_location_assignment PIN_E11  -to VGA_G[7]

set_location_assignment PIN_B13  -to VGA_B[0]
set_location_assignment PIN_G13  -to VGA_B[1]
set_location_assignment PIN_H13  -to VGA_B[2]
set_location_assignment PIN_F14  -to VGA_B[3]
set_location_assignment PIN_H14  -to VGA_B[4]
set_location_assignment PIN_F15  -to VGA_B[5]
set_location_assignment PIN_G15  -to VGA_B[6]
set_location_assignment PIN_J14  -to VGA_B[7]

# 4. Debug Interface (LEDs & HEX)
# ------------------------------------------------------------------------------------
set_location_assignment PIN_V16  -to LEDR[0]
set_location_assignment PIN_W16  -to LEDR[1]
set_location_assignment PIN_V17  -to LEDR[2]
set_location_assignment PIN_V18  -to LEDR[3]
set_location_assignment PIN_W17  -to LEDR[4]
set_location_assignment PIN_W19  -to LEDR[5]
set_location_assignment PIN_Y19  -to LEDR[6]
set_location_assignment PIN_W20  -to LEDR[7]
set_location_assignment PIN_W21  -to LEDR[8]
set_location_assignment PIN_Y21  -to LEDR[9]

set_location_assignment PIN_AE26 -to HEX0[0]
set_location_assignment PIN_AE27 -to HEX0[1]
set_location_assignment PIN_AE28 -to HEX0[2]
set_location_assignment PIN_AG27 -to HEX0[3]
set_location_assignment PIN_AF28 -to HEX0[4]
set_location_assignment PIN_AG28 -to HEX0[5]
set_location_assignment PIN_AH28 -to HEX0[6]

# 5. I/O Standard Settings
# ------------------------------------------------------------------------------------
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to *