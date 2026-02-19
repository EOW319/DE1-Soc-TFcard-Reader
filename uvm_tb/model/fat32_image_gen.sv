// =============================================================================
// fat32_image_gen.sv
// FAT32 磁盘镜像生成器
//
// 在仿真初始化时，调用 generate_image() task 向 sd_card_model.mem 写入
// 合法的 FAT32 磁盘布局，供 sd_file_reader 解析。
//
// 生成内容:
//   Sector 0        : MBR (partition entry at offset 446)
//   Boot sector     : FAT32 BPB (所有字段可参数化)
//   FAT 扇区         : 文件 IMAGE.BIN 的簇号链 (简单: 连续簇，链表单条)
//   根目录扇区       : 1 个 32-byte 8.3 目录项 "IMAGE   BIN"
//   文件数据扇区     : 76800 字节 RGB332 测试图案
// =============================================================================
`ifndef FAT32_IMAGE_GEN_SV
`define FAT32_IMAGE_GEN_SV

module fat32_image_gen ();

    // =========================================================================
    // 配置参数 (可通过 defparam 或 SV parameter 覆盖)
    // =========================================================================
    parameter bit [31:0] PARTITION_START_LBA  = 32'h800;  // MBR 分区起始 LBA
    parameter bit [7:0]  SECTORS_PER_CLUSTER  = 8'd8;     // BPB_SecPerClus
    parameter bit [15:0] RESERVED_SECTORS     = 16'd32;   // BPB_RsvdSecCnt
    parameter bit [7:0]  NUM_FATS             = 8'd2;     // BPB_NumFATs
    parameter bit [31:0] SECTORS_PER_FAT      = 32'd256;  // BPB_FATSz32
    parameter bit [31:0] ROOT_CLUSTER         = 32'd2;    // BPB_RootClus
    parameter bit        HAS_IMAGE_FILE       = 1;        // 是否写入 IMAGE.BIN
    parameter bit [31:0] FILE_START_CLUSTER   = 32'd3;    // 文件起始簇号
    parameter int        IMAGE_SIZE           = 76800;    // 字节数

    // 指向 sd_card_model 的 mem 引用 (通过层次路径访问)
    // 在 top_tb 中直接通过 hierarchical reference 调用 write_byte task

    // =========================================================================
    // 入口任务
    // =========================================================================
    task automatic generate_image(
        // mem 句柄通过 ref 传入
        ref   logic [7:0] mem [],
        input int         total_sectors,
        input bit         has_file = HAS_IMAGE_FILE
    );
        if (mem.size() == 0) begin
            $display("[FAT32GEN] ERROR: mem is empty");
            return;
        end

        $display("[FAT32GEN] Generating FAT32 image: partition_lba=0x%0X, spc=%0d, rsvd=%0d",
                 PARTITION_START_LBA, SECTORS_PER_CLUSTER, RESERVED_SECTORS);

        write_mbr(mem);
        write_boot_sector(mem);
        write_fat(mem);
        if (has_file) begin
            write_root_dir(mem);
            write_file_data(mem);
        end

        $display("[FAT32GEN] Done.");
    endtask

    // =========================================================================
    // MBR (Sector 0)
    // =========================================================================
    task automatic write_mbr(ref logic [7:0] mem []);
        int base = 0;
        // 清零首扇区
        for (int i = 0; i < 512; i++) mem[base + i] = 8'h00;

        // Partition entry 1 at offset 446 (bytes 446-461)
        // Status byte
        mem[base + 446] = 8'h80;  // bootable
        // CHS First (3 bytes, 忽略)
        mem[base + 447] = 8'hFE; mem[base + 448] = 8'hFF; mem[base + 449] = 8'hFF;
        // Partition type: 0x0C = FAT32 LBA
        mem[base + 450] = 8'h0C;
        // CHS Last (3 bytes, 忽略)
        mem[base + 451] = 8'hFE; mem[base + 452] = 8'hFF; mem[base + 453] = 8'hFF;
        // LBA Start (little-endian 32-bit)
        mem[base + 454] = PARTITION_START_LBA[7:0];
        mem[base + 455] = PARTITION_START_LBA[15:8];
        mem[base + 456] = PARTITION_START_LBA[23:16];
        mem[base + 457] = PARTITION_START_LBA[31:24];
        // LBA Size (dummy: 全部剩余)
        mem[base + 458] = 8'hFF; mem[base + 459] = 8'hFF;
        mem[base + 460] = 8'hFF; mem[base + 461] = 8'hFF;
        // Boot signature
        mem[base + 510] = 8'h55;
        mem[base + 511] = 8'hAA;
    endtask

    // =========================================================================
    // Boot Sector (Sector PARTITION_START_LBA)
    // =========================================================================
    task automatic write_boot_sector(ref logic [7:0] mem []);
        int base = PARTITION_START_LBA * 512;
        for (int i = 0; i < 512; i++) mem[base + i] = 8'h00;

        // Jump boot (3 bytes)
        mem[base + 0] = 8'hEB; mem[base + 1] = 8'h58; mem[base + 2] = 8'h90;
        // OEM Name "MSDOS5.0"
        mem[base + 3]  = 8'h4D; mem[base + 4]  = 8'h53; mem[base + 5]  = 8'h44;
        mem[base + 6]  = 8'h4F; mem[base + 7]  = 8'h53; mem[base + 8]  = 8'h35;
        mem[base + 9]  = 8'h2E; mem[base + 10] = 8'h30;
        // BPB_BytsPerSec = 512  [0x0B-0x0C]
        mem[base + 11] = 8'h00; mem[base + 12] = 8'h02;
        // BPB_SecPerClus = SECTORS_PER_CLUSTER  [0x0D]
        mem[base + 13] = SECTORS_PER_CLUSTER;
        // BPB_RsvdSecCnt = RESERVED_SECTORS  [0x0E-0x0F]
        mem[base + 14] = RESERVED_SECTORS[7:0];
        mem[base + 15] = RESERVED_SECTORS[15:8];
        // BPB_NumFATs = NUM_FATS  [0x10]
        mem[base + 16] = NUM_FATS;
        // BPB_RootEntCnt = 0 (FAT32)  [0x11-0x12]
        mem[base + 17] = 8'h00; mem[base + 18] = 8'h00;
        // BPB_TotSec16 = 0  [0x13-0x14]
        mem[base + 19] = 8'h00; mem[base + 20] = 8'h00;
        // BPB_Media = 0xF8  [0x15]
        mem[base + 21] = 8'hF8;
        // BPB_FATSz16 = 0  [0x16-0x17]
        mem[base + 22] = 8'h00; mem[base + 23] = 8'h00;
        // BPB_SecPerTrk [0x18-0x19], BPB_NumHeads [0x1A-0x1B] (忽略)
        // BPB_HiddSec [0x1C-0x1F] = PARTITION_START_LBA
        mem[base + 28] = PARTITION_START_LBA[7:0];
        mem[base + 29] = PARTITION_START_LBA[15:8];
        mem[base + 30] = PARTITION_START_LBA[23:16];
        mem[base + 31] = PARTITION_START_LBA[31:24];
        // BPB_TotSec32 [0x20-0x23] (dummy)
        mem[base + 32] = 8'hFF; mem[base + 33] = 8'hFF; mem[base + 34] = 8'hFF; mem[base + 35] = 8'hFF;
        // BPB_FATSz32 [0x24-0x27] = SECTORS_PER_FAT
        mem[base + 36] = SECTORS_PER_FAT[7:0];
        mem[base + 37] = SECTORS_PER_FAT[15:8];
        mem[base + 38] = SECTORS_PER_FAT[23:16];
        mem[base + 39] = SECTORS_PER_FAT[31:24];
        // BPB_ExtFlags [0x28-0x29], BPB_FSVer [0x2A-0x2B]
        // BPB_RootClus [0x2C-0x2F] = ROOT_CLUSTER
        mem[base + 44] = ROOT_CLUSTER[7:0];
        mem[base + 45] = ROOT_CLUSTER[15:8];
        mem[base + 46] = ROOT_CLUSTER[23:16];
        mem[base + 47] = ROOT_CLUSTER[31:24];
        // Boot signature
        mem[base + 510] = 8'h55; mem[base + 511] = 8'hAA;
    endtask

    // =========================================================================
    // FAT 表 (仅填写文件簇链: FILE_START_CLUSTER → EOC)
    // =========================================================================
    task automatic write_fat(ref logic [7:0] mem []);
        // FAT1 起始扇区
        int fat1_lba = PARTITION_START_LBA + RESERVED_SECTORS;
        int fat1_base = fat1_lba * 512;
        int needed_clusters;
        int cluster_size_bytes;
        int entry_base;

        cluster_size_bytes = SECTORS_PER_CLUSTER * 512;
        needed_clusters = (IMAGE_SIZE + cluster_size_bytes - 1) / cluster_size_bytes;

        // 初始化 FAT: 全 0
        for (int i = 0; i < SECTORS_PER_FAT * 512; i++)
            mem[fat1_base + i] = 8'h00;

        // FAT[0] = 0xFFFFFFF8 (media byte), FAT[1] = 0xFFFFFFFF (reserved)
        write_fat_entry(mem, fat1_base, 0, 32'hFFFFFFF8);
        write_fat_entry(mem, fat1_base, 1, 32'hFFFFFFFF);

        // 根目录簇: ROOT_CLUSTER → EOC
        write_fat_entry(mem, fat1_base, ROOT_CLUSTER, 32'h0FFFFFFF);

        // 文件簇链 (连续分配)
        for (int i = 0; i < needed_clusters - 1; i++)
            write_fat_entry(mem, fat1_base, FILE_START_CLUSTER + i, FILE_START_CLUSTER + i + 1);
        write_fat_entry(mem, fat1_base, FILE_START_CLUSTER + needed_clusters - 1, 32'h0FFFFFFF);

        // 如有 FAT2，复制 FAT1
        if (NUM_FATS >= 2) begin
            int fat2_base = (fat1_lba + SECTORS_PER_FAT) * 512;
            for (int i = 0; i < SECTORS_PER_FAT * 512; i++)
                mem[fat2_base + i] = mem[fat1_base + i];
        end
    endtask

    // 写 FAT32 entry (4 字节, little-endian, 高 4 位保留)
    task automatic write_fat_entry(ref logic [7:0] mem [], int base, int cluster, logic [31:0] val);
        int ofs = base + cluster * 4;
        mem[ofs + 0] = val[7:0];
        mem[ofs + 1] = val[15:8];
        mem[ofs + 2] = val[23:16];
        mem[ofs + 3] = {4'h0, val[27:24]};
    endtask

    // =========================================================================
    // 根目录 (ROOT_CLUSTER 对应的数据区扇区)
    // =========================================================================
    task automatic write_root_dir(ref logic [7:0] mem []);
        int fat1_lba     = PARTITION_START_LBA + RESERVED_SECTORS;
        int data_lba     = fat1_lba + NUM_FATS * SECTORS_PER_FAT;
        int root_lba     = data_lba + (ROOT_CLUSTER - 2) * SECTORS_PER_CLUSTER;
        int base         = root_lba * 512;

        // 清零根目录首扇区
        for (int i = 0; i < 512; i++) mem[base + i] = 8'h00;

        // 第一个目录项 (offset 0): "IMAGE   BIN"
        // 文件名 8 字节: "IMAGE   " (3空格填充)
        mem[base +  0] = 8'h49; // I
        mem[base +  1] = 8'h4D; // M
        mem[base +  2] = 8'h41; // A
        mem[base +  3] = 8'h47; // G
        mem[base +  4] = 8'h45; // E
        mem[base +  5] = 8'h20; // (space)
        mem[base +  6] = 8'h20; // (space)
        mem[base +  7] = 8'h20; // (space)
        // 扩展名 3 字节: "BIN"
        mem[base +  8] = 8'h42; // B
        mem[base +  9] = 8'h49; // I
        mem[base + 10] = 8'h4E; // N
        // 属性: 0x20 = Archive
        mem[base + 11] = 8'h20;
        // 保留字段 (offset 12-19)
        // 起始簇号高 16 位 (offset 20-21)
        mem[base + 20] = FILE_START_CLUSTER[23:16];
        mem[base + 21] = FILE_START_CLUSTER[31:24]; // 通常为 0
        // 修改时间/日期 (offset 22-25, 忽略)
        // 起始簇号低 16 位 (offset 26-27)
        mem[base + 26] = FILE_START_CLUSTER[7:0];
        mem[base + 27] = FILE_START_CLUSTER[15:8];
        // 文件大小 (offset 28-31)
        mem[base + 28] = IMAGE_SIZE[7:0];
        mem[base + 29] = IMAGE_SIZE[15:8];
        mem[base + 30] = IMAGE_SIZE[23:16];
        mem[base + 31] = IMAGE_SIZE[31:24];
    endtask

    // =========================================================================
    // 文件数据 (IMAGE.BIN: 76800 字节 RGB332 测试图案)
    // =========================================================================
    task automatic write_file_data(ref logic [7:0] mem []);
        int fat1_lba   = PARTITION_START_LBA + RESERVED_SECTORS;
        int data_lba   = fat1_lba + NUM_FATS * SECTORS_PER_FAT;
        int file_lba   = data_lba + (FILE_START_CLUSTER - 2) * SECTORS_PER_CLUSTER;
        int base       = file_lba * 512;

        // 生成渐变色测试图案 (可改为棋盘格等)
        for (int y = 0; y < 240; y++) begin
            for (int x = 0; x < 320; x++) begin
                int idx = y * 320 + x;
                bit [2:0] r3 = (x * 7) / 319;  // 0~7
                bit [2:0] g3 = (y * 7) / 239;  // 0~7
                bit [1:0] b2 = ((x + y) * 3) / (319 + 239); // 0~3
                mem[base + idx] = {r3, g3, b2};
            end
        end
    endtask

endmodule : fat32_image_gen

`endif // FAT32_IMAGE_GEN_SV
