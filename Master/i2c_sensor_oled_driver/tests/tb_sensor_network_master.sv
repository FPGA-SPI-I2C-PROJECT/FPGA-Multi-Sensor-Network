`timescale 1ns/1ps
// Real Master + SPI/I2C Slave RTL + unchanged upstream sensor_reg_bank.
module tb_sensor_network_master #(parameter integer TEST_HEIGHT=32);
    reg clk=0;
    always #5 clk=~clk;
    reg [15:0] sw=16'h8000;
    reg btnC=0;
    wire miso;
    reg slave_clk=0,slave_reset=1;
    always #5.1 slave_clk=~slave_clk; // independent clock and drifting phase
    wire sclk, mosi, cs_n;
    tri1 oled_sda, oled_scl, board_sda, board_scl;
    wire [15:0] led;
    wire i2c_selected,i2c_done,i2c_error;
    sensor_network_master #(.CLK_HZ(100_000_000),.SPI_HZ(1_000_000),
        .OLED_HEIGHT(TEST_HEIGHT),
        .I2C_HZ(2_000_000),.BOARD_I2C_HZ(400_000),.POWERUP_MS(0),.TIMEOUT_MS(10),
        .BUTTON_CYCLES(3),.SPI_PROTOCOL_READY(1)) dut (
        .clk(clk),.btnC(btnC),.sw(sw),.spi_miso(miso),.spi_sclk(sclk),
        .spi_mosi(mosi),.spi_cs_n(cs_n),.board_sda(board_sda),.board_scl(board_scl),
        .oled_sda(oled_sda),.oled_scl(oled_scl),.led(led)
    );

    // Default production guard must never clock an unimplemented Slave.
    reg guard_reset=1, guard_request=0;
    reg [1:0] guard_mode=1;
    wire guard_sclk,guard_mosi,guard_cs,guard_busy,guard_update;
    wire [7:0] guard_temp,guard_humi;
    wire [8:0] guard_dist;
    wire [2:0] guard_valid,guard_error;
    tri1 guard_sda,guard_scl;
    sensor_request_master guard (
        .clk(clk),.reset(guard_reset),.request(guard_request),.mode(guard_mode),
        .request_mask(3'b111),.spi_miso(1'b0),.spi_sclk(guard_sclk),
        .board_sda(guard_sda),.board_scl(guard_scl),
        .spi_mosi(guard_mosi),.spi_cs_n(guard_cs),.temperature(guard_temp),
        .humidity(guard_humi),.distance(guard_dist),.valid_mask(guard_valid),
        .busy(guard_busy),.update(guard_update),.error_code(guard_error)
    );

    integer spi_bits=0, spi_transactions=0;
    reg [7:0] received_command=0;
    reg [7:0] source_temp=25,source_humi=63;
    reg [8:0] source_dist=301;
    wire [7:0] bank_temp,bank_humi;
    wire [8:0] bank_dist;
    wire slave_selected,slave_done,slave_error;
    wire [7:0] slave_command;
    sensor_reg_bank slave_bank (
        .clk(slave_clk),.reset(slave_reset),.dht_done(1'b1),
        .dht_temp(source_temp),.dht_humi(source_humi),
        .ultra_done(1'b1),.ultra_dist(source_dist),
        .reg_temp(bank_temp),.reg_humi(bank_humi),.reg_dist(bank_dist)
    );
    spi_sensor_slave slave (
        .clk(slave_clk),.reset(slave_reset),.spi_sclk(sclk),.spi_mosi(mosi),
        .spi_cs_n(cs_n),.spi_miso(miso),.reg_temp(bank_temp),.reg_humi(bank_humi),
        .reg_dist(bank_dist),.selected(slave_selected),.transaction_done(slave_done),
        .command_error(slave_error),.last_command(slave_command)
    );
    i2c_sensor_slave slave_i2c (
        .clk(slave_clk),.reset(slave_reset),.scl(board_scl),.sda(board_sda),
        .reg_temp(bank_temp),.reg_humi(bank_humi),.reg_dist(bank_dist),
        .selected(i2c_selected),.transaction_done(i2c_done),.command_error(i2c_error)
    );
    always @(negedge cs_n) begin
        if (sclk !== 0) $fatal(1,"SPI CPOL is not 0");
        spi_bits=0; received_command=0;
        spi_transactions=spi_transactions+1;
    end
    always @(posedge sclk) if (!cs_n) begin
        if (spi_bits < 8) received_command={received_command[6:0],mosi};
        else if (mosi !== 0) $fatal(1,"SPI dummy clocks must send 0");
        spi_bits=spi_bits+1;
        if (spi_bits == 8) begin
            case (received_command)
                8'h01,8'h02,8'h03: begin end
                default: $fatal(1,"Unknown command or bit order");
            endcase
        end
    end
    always @(posedge cs_n) if (!sw[15] && $time > 100)
        if (spi_bits != 24) $fatal(1,"CS released before/after 24 bits");

    // Wire-level OLED receiver. ACK every byte; track the actual frame bytes.
    reg ack_low=0, in_packet=0;
    reg [7:0] rx_byte=0;
    integer i2c_bit=0,packet_bytes=0,frame_bytes=0,frame_count=0,display_page=0;
    reg [7:0] control_byte=0;
    reg [7:0] screen[0:128*(TEST_HEIGHT/8)-1];
    assign oled_sda=ack_low ? 1'b0 : 1'bz;
    always @(posedge sw[15]) begin ack_low=0; in_packet=0; end
    always @(negedge oled_sda) if (oled_scl === 1'b1) begin
        in_packet=1; i2c_bit=0; packet_bytes=0; frame_bytes=0;
    end
    always @(posedge oled_sda) if (oled_scl === 1'b1 && in_packet) begin
        in_packet=0;
        if (control_byte == 8'h40 && frame_bytes != 0) begin
            if (frame_bytes != 128) $fatal(1,"Incomplete OLED page rewrite: %0d",frame_bytes);
            if (display_page == TEST_HEIGHT/8-1) frame_count=frame_count+1;
        end
    end
    always @(posedge oled_scl) if (in_packet) begin
        if (i2c_bit < 8) begin
            rx_byte={rx_byte[6:0],oled_sda}; i2c_bit=i2c_bit+1;
            if (i2c_bit == 8) begin
                if (packet_bytes == 0 && rx_byte != 8'h78) $fatal(1,"Wrong OLED address");
                if (packet_bytes == 1) control_byte=rx_byte;
                if (packet_bytes == 2 && control_byte == 0 && rx_byte[7:3] == 5'b10110)
                    display_page=rx_byte[2:0];
                if (packet_bytes > 1 && control_byte == 8'h40) begin
                    if (frame_bytes >= 128 || display_page >= TEST_HEIGHT/8) $fatal(1,"OLED page address/length error");
                    screen[display_page*128+frame_bytes]=rx_byte; frame_bytes=frame_bytes+1;
                end
                packet_bytes=packet_bytes+1;
            end
        end else i2c_bit=9;
    end
    always @(negedge oled_scl) if (in_packet) begin
        if (i2c_bit == 8) ack_low=1;
        else if (i2c_bit == 9) begin ack_low=0; i2c_bit=0; end
    end

    task press_request(input [1:0] mode,input [2:0] mask);
        begin
            @(negedge clk); sw[4:0]={mask,mode};
            repeat(8) @(negedge clk);
            btnC=1; repeat(12) @(negedge clk);
            btnC=0; repeat(12) @(negedge clk);
        end
    endtask
    task wait_idle;
        begin
            wait(!dut.request_busy && dut.display.state == 4 && !dut.display.pending);
            repeat(3) @(negedge clk);
        end
    endtask
    task check_regs(input [2:0] mask);
        begin
            if (dut.valid_mask !== mask ||
                dut.temperature !== (mask[0] ? source_temp : 0) ||
                dut.humidity !== (mask[1] ? source_humi : 0) ||
                dut.distance !== (mask[2] ? source_dist : 0))
                $fatal(1,"Published request contains wrong or stale data, mask=%b",mask);
        end
    endtask
    task check_screen(input [2:0] mask);
        integer row,col;
        begin
            // Check actual I2C pixels against independent known font columns.
            if (screen[0] !== 8'h01 || screen[2] !== 8'h7F || screen[128] !== 8'h7F || screen[256] !== 8'h7F)
                $fatal(1,"OLED labels missing");
            for(row=0;row<3;row=row+1) if (!mask[row])
                for(col=78;col<96;col=col+1)
                    if (screen[row*128+col] !== 0) $fatal(1,"Omitted field left stale OLED pixels");
            for(col=384;col<128*(TEST_HEIGHT/8);col=col+1)
                if (screen[col] !== 0) $fatal(1,"Unused OLED page not cleared");
        end
    endtask
    integer m,before_count;
    initial begin
        repeat(8) @(negedge clk); sw=0; guard_reset=0; slave_reset=0;
        @(negedge clk); guard_request=1;
        @(negedge clk); guard_request=0;
        repeat(4) @(negedge clk);
        if (guard_error !== 3 || guard_cs !== 1 || guard_sclk !== 0 || guard_valid !== 0)
            $fatal(1,"Missing-protocol guard failed");
        wait_idle(); check_screen(0);
        if (!led[15] || led[14]) $fatal(1,"OLED startup failed");
        // All masks, including all -> temp+distance, zero values, 9-bit distance.
        for(m=7;m>=1;m=m-1) begin
            before_count=spi_transactions;
            press_request(1,m[2:0]); wait_idle(); check_regs(m[2:0]); check_screen(m[2:0]);
            if (spi_transactions-before_count != (m[0]+m[1]+m[2])) $fatal(1,"Unrequested sensor was read");
        end
        for(m=7;m>=1;m=m-1) begin
            before_count=spi_transactions;
            press_request(2,m[2:0]); wait_idle(); check_regs(m[2:0]); check_screen(m[2:0]);
            if (dut.error_code !== 0 || spi_transactions != before_count)
                $fatal(1,"I2C request failed or activated SPI");
        end
        source_temp=0; source_humi=0; source_dist=511;
        press_request(1,7); wait_idle(); check_regs(7);
        // Zero must be displayed, and distance must retain its ninth bit.
        if (screen[90] !== 8'h3E || screen[218] !== 8'h3E)
            $fatal(1,"Valid zero not displayed");
        if (screen[334] !== 8'h27 || screen[340] !== 0 || screen[342] !== 8'h7F)
            $fatal(1,"511 distance not rendered");
        source_temp=255; source_humi=255;
        press_request(1,7); wait_idle(); check_regs(7);
        if (dut.error_code !== 0) $fatal(1,"Valid zero-padded maximum value was rejected");
        // An undriven/incorrect MISO read as FFFF must never become valid maxima.
        force miso=1'b1;
        press_request(1,7); wait_idle(); check_regs(0); check_screen(0);
        if (dut.error_code !== 6 || !led[2]) $fatal(1,"Invalid SPI padding was accepted");
        release miso;
        before_count=spi_transactions;
        press_request(2,7);
        // Changing physical switches during a request must not change its mode/mask.
        sw[4:0]={3'b001,2'b01};
        wait_idle(); check_regs(7);
        if (dut.error_code !== 0 || spi_transactions != before_count || board_sda !== 1 || board_scl !== 1)
            $fatal(1,"Latched I2C mode changed or bus was not released");
        press_request(1,5); wait_idle(); check_regs(5); check_screen(5);
        press_request(3,7); wait_idle(); check_regs(0);
        if (dut.error_code !== 1) $fatal(1,"Both mode switches high not rejected");
        press_request(0,7); wait_idle();
        if (dut.error_code !== 1) $fatal(1,"No mode not rejected");
        press_request(1,0); wait_idle();
        if (dut.error_code !== 2) $fatal(1,"Empty mask not rejected");
        // Reset only Master; the simulated Slave sensor source remains 511.
        press_request(1,7);
        wait(!cs_n); repeat(10) @(negedge clk); sw[15]=1;
        repeat(8) @(negedge clk);
        if (cs_n !== 1 || sclk !== 0 || dut.valid_mask !== 0 || dut.distance !== 0)
            $fatal(1,"Master reset did not abort and clear");
        sw[15]=0; sw[4:0]=0; wait_idle(); check_screen(0);
        if (source_dist !== 511) $fatal(1,"Master reset affected Slave source");
        if (bank_dist !== 511 || slave_error) $fatal(1,"Slave bank reset or command error");
        // Abort an I2C read while Slave is driving zero, then recover without resetting Slave.
        press_request(2,4);
        wait(slave_i2c.state == 6 && slave_i2c.bit_count == 2 && !slave_i2c.second_byte);
        @(negedge clk); sw[15]=1;
        repeat(8) @(negedge clk);
        if (dut.valid_mask !== 0 || dut.distance !== 0) $fatal(1,"I2C reset did not clear Master");
        sw[15]=0; sw[4:0]=0; wait_idle();
        press_request(2,4); wait_idle(); check_regs(4); check_screen(4);
        if (dut.error_code !== 0 || bank_dist !== 511 || i2c_error)
            $fatal(1,"I2C recovery after Master-only reset failed");
        $display("PASS: paired SPI/I2C RTL, OLED page writes, padding, recovery; height=%0d frames=%0d",TEST_HEIGHT,frame_count);
        $finish;
    end
    initial begin #400_000_000; $fatal(1,"Testbench watchdog"); end
endmodule
