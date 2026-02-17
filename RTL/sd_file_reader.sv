module sd_file_reader (
    input  logic        clk,
    input  logic        rst_n,

    // Interface with sd_reader
    output logic        rstart,
    output logic [31:0] rsector,
    input  logic        rbusy,
    input  logic        rdone,
    input  logic        outen,
    input  logic [7:0]  outbyte,

    // Interface with RAM
    output logic [16:0] ram_addr, // 320*240 = 76800 < 2^17
    output logic [7:0]  ram_wdata,
    output logic        ram_we,
    
    // Status
    output logic        file_found,
    output logic        read_done,
    output logic [3:0]  state_debug
);

    // State definitions
    typedef enum logic [3:0] {
        IDLE,
        WAIT_INIT,
        READ_MBR,
        READ_BOOT,
        READ_ROOT,
        READ_FILE,
        DONE,
        ERROR
    } state_t;

    state_t state, next_state;

    // FAT32 Parameters
    logic [31:0] partition_lba;
    logic [31:0] boot_sector_lba;
    logic [15:0] reserved_sectors;
    logic [7:0]  num_fats;
    logic [31:0] sectors_per_fat;
    logic [31:0] root_cluster;
    logic [7:0]  sectors_per_cluster;
    
    logic [31:0] fat_start_lba;
    logic [31:0] data_start_lba;
    logic [31:0] root_dir_lba;
    
    logic [31:0] current_cluster;
    logic [31:0] current_sector;
    logic [7:0]  sector_in_cluster_cnt;
    
    // Byte counter for processing sector data
    logic [9:0] byte_cnt;
    
    // Filename matching
    logic [7:0] target_filename [0:10]; // 8.3 format "IMAGE   BIN"
    logic [3:0] char_cnt; // Kept for future flexibility if we loop through chars differently
    logic       match_fail;
    
    // RAM Address Logic
    logic [16:0] addr_cnt;

    // Temporary storage for multi-byte values
    logic [31:0] temp_val; // Kept as placeholder or remove if unused

    logic [31:0] file_start_cluster;

    assign state_debug = state;

    // Initialize target filename "IMAGE   BIN"
    initial begin
        target_filename[0] = "I"; target_filename[1] = "M"; target_filename[2] = "A";
        target_filename[3] = "G"; target_filename[4] = "E"; target_filename[5] = " ";
        target_filename[6] = " "; target_filename[7] = " "; 
        target_filename[8] = "B"; target_filename[9] = "I"; target_filename[10] = "N";
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            partition_lba <= 0;
            byte_cnt <= 0;
            ram_addr <= 0;
            ram_wdata <= 0;
            ram_we <= 0;
            file_found <= 0;
            read_done <= 0;
            addr_cnt <= 0;
            sector_in_cluster_cnt <= 0;
            file_start_cluster <= 0;
        end else begin
            ram_we <= 0; // Default
            
            case (state)
                IDLE: begin
                    if (!rbusy) // Wait for SD init to complete
                        state <= READ_MBR;
                end

                READ_MBR: begin
                    if (rbusy == 0 && rdone == 0 && byte_cnt == 0) begin
                        rstart <= 1;
                        rsector <= 0;
                        state <= READ_MBR; // Wait for data
                    end else if (rstart) begin
                        rstart <= 0;
                    end
                    
                    if (outen) begin
                        byte_cnt <= byte_cnt + 1;
                        // Partition 1 LBA at 0x1C6 (454)
                        if (byte_cnt == 454) partition_lba[7:0]   <= outbyte;
                        if (byte_cnt == 455) partition_lba[15:8]  <= outbyte;
                        if (byte_cnt == 456) partition_lba[23:16] <= outbyte;
                        if (byte_cnt == 457) partition_lba[31:24] <= outbyte;
                    end
                    
                    if (rdone) begin
                        byte_cnt <= 0;
                        boot_sector_lba <= partition_lba;
                        state <= READ_BOOT;
                    end
                end

                READ_BOOT: begin
                    if (rbusy == 0 && rdone == 0 && byte_cnt == 0) begin
                        rstart <= 1;
                        rsector <= boot_sector_lba;
                    end else if (rstart) begin
                        rstart <= 0;
                    end

                    if (outen) begin
                        byte_cnt <= byte_cnt + 1;
                        // BPB_SecPerClus at 0x0D (13)
                        if (byte_cnt == 13) sectors_per_cluster <= outbyte;
                        // BPB_RsvdSecCnt at 0x0E (14)
                        if (byte_cnt == 14) reserved_sectors[7:0] <= outbyte;
                        if (byte_cnt == 15) reserved_sectors[15:8] <= outbyte;
                        // BPB_NumFATs at 0x10 (16)
                        if (byte_cnt == 16) num_fats <= outbyte;
                        // BPB_FATSz32 at 0x24 (36)
                        if (byte_cnt == 36) sectors_per_fat[7:0] <= outbyte;
                        if (byte_cnt == 37) sectors_per_fat[15:8] <= outbyte;
                        if (byte_cnt == 38) sectors_per_fat[23:16] <= outbyte;
                        if (byte_cnt == 39) sectors_per_fat[31:24] <= outbyte;
                        // BPB_RootClus at 0x2C (44)
                        if (byte_cnt == 44) root_cluster[7:0] <= outbyte;
                        if (byte_cnt == 45) root_cluster[15:8] <= outbyte;
                        if (byte_cnt == 46) root_cluster[23:16] <= outbyte;
                        if (byte_cnt == 47) root_cluster[31:24] <= outbyte;
                    end

                    if (rdone) begin
                        byte_cnt <= 0;
                        // Calculate Offsets
                        fat_start_lba <= boot_sector_lba + reserved_sectors;
                        data_start_lba <= boot_sector_lba + reserved_sectors + (num_fats * sectors_per_fat);
                        // First sector of root dir
                        current_cluster <= root_cluster;
                        // Sector = DataStart + (Cluster-2)*SecPerCluster
                        // We will compute this in the transition
                        state <= READ_ROOT;
                        
                        // Reset search logic
                        char_cnt <= 0;
                        match_fail <= 0;
                        sector_in_cluster_cnt <= 0;
                        // Avoid warning for temp_val not used
                        temp_val <= 0;
                    end
                end

                READ_ROOT: begin
                    if (rbusy == 0 && rdone == 0 && byte_cnt == 0) begin
                        rstart <= 1;
                        rsector <= data_start_lba + (current_cluster - 2) * sectors_per_cluster + sector_in_cluster_cnt;
                    end else if (rstart) begin
                        rstart <= 0;
                    end

                    if (outen) begin
                        byte_cnt <= byte_cnt + 1;
                        
                        // Check 32-byte entries
                        // Offset within entry: byte_cnt % 32
                        // Filename is at offset 0-10
                        
                        if ((byte_cnt & 31) == 0) begin
                            match_fail <= 0; // Reset for new entry
                        end
                        
                        if ((byte_cnt & 31) < 11) begin // 0 to 10
                            if (outbyte != target_filename[byte_cnt & 31]) begin
                                match_fail <= 1;
                            end
                        end
                        
                        // At end of filename (offset 11), check match
                        if ((byte_cnt & 31) == 11) begin
                            if (!match_fail && outbyte != 8'h0F && outbyte != 8'hE5 && outbyte != 8'h00) begin 
                                // Match found! Capture cluster
                                // 0F is LFN, E5 is deleted, 00 is empty
                                file_found <= 1;
                            end
                        end
                        
                        // Capture Cluster info if match found
                        if (file_found) begin
                            if ((byte_cnt & 31) == 20) file_start_cluster[23:16] <= outbyte;
                            if ((byte_cnt & 31) == 21) file_start_cluster[31:24] <= outbyte;
                            if ((byte_cnt & 31) == 26) file_start_cluster[7:0] <= outbyte;
                            if ((byte_cnt & 31) == 27) file_start_cluster[15:8] <= outbyte;
                        end
                    end

                    if (rdone) begin
                        byte_cnt <= 0;
                        if (file_found) begin
                            state <= READ_FILE;
                            sector_in_cluster_cnt <= 0;
                            current_cluster <= file_start_cluster;
                            addr_cnt <= 0; // Reset RAM addr
                        end else begin
                            // Go to next sector
                            if (sector_in_cluster_cnt < sectors_per_cluster - 1) begin
                                sector_in_cluster_cnt <= sector_in_cluster_cnt + 1;
                            end else begin
                                // End of cluster. Ideally we should follow FAT chain.
                                // For simplicity, we fail or stop here as requested.
                                state <= DONE; // Not found in first cluster of root dir
                            end
                        end
                    end
                end

                READ_FILE: begin
                    if (rbusy == 0 && rdone == 0 && byte_cnt == 0) begin
                        rstart <= 1;
                        rsector <= data_start_lba + (current_cluster - 2) * sectors_per_cluster + sector_in_cluster_cnt;
                    end else if (rstart) begin
                        rstart <= 0;
                    end

                    if (outen) begin
                        byte_cnt <= byte_cnt + 1;
                        // RAM Write Logic
                        if (addr_cnt < 76800) begin
                            ram_we <= 1;
                            ram_addr <= addr_cnt[16:0];
                            ram_wdata <= outbyte;
                            addr_cnt <= addr_cnt + 1;
                        end
                    end

                    if (rdone) begin
                        byte_cnt <= 0;
                        if (addr_cnt >= 76800) begin
                            read_done <= 1;
                            state <= DONE;
                        end else begin
                            // Next sector
                            if (sector_in_cluster_cnt < sectors_per_cluster - 1) begin
                                sector_in_cluster_cnt <= sector_in_cluster_cnt + 1;
                            end else begin
                                // Next Cluster
                                // Assuming contiguous file
                                current_cluster <= current_cluster + 1;
                                sector_in_cluster_cnt <= 0;
                            end
                        end
                    end
                end

                DONE: begin
                    // Idle
                    rstart <= 0;
                end
                
                ERROR: begin
                    rstart <= 0;
                end
            endcase
        end
    end

endmodule
