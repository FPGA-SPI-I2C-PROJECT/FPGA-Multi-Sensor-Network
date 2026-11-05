`timescale 1ns / 1ps
module tb_optimized_i2c #(parameter integer TEST_I2C_HZ=100_000);
    reg clk=0, slave_clk=0, reset=1, start=0;
    always #5 clk=~clk;
    always #5.1 slave_clk=~slave_clk;
    reg [7:0] command=1;
    reg manual_sda=0, manual_scl=0, stretch=0, stuck_sda=0;
    tri1 sda, scl;
    assign sda = (manual_sda || stuck_sda) ? 1'b0 : 1'bz;
    assign scl = (manual_scl || stretch) ? 1'b0 : 1'bz;
    wire busy, done, nack, timeout_error, selected, slave_done, command_error;
    wire [15:0] response;
    i2c_sensor_read_master #(.I2C_HZ(TEST_I2C_HZ), .TIMEOUT_MS(2)) master (
        .clk(clk), .reset(reset), .start(start), .command(command), .sda(sda), .scl(scl),
        .busy(busy), .done(done), .nack(nack), .timeout_error(timeout_error), .response(response)
    );
    i2c_sensor_slave #(.IDLE_TIMEOUT_MS(1)) slave (
        .clk(slave_clk), .reset(reset), .scl(scl), .sda(sda),
        .reg_temp(8'd25), .reg_humi(8'd63), .reg_dist(9'd301),
        .selected(selected), .transaction_done(slave_done), .command_error(command_error)
    );

    // Measure bus events, independently of the implementation's phase counter.
    localparam integer MIN_LOW = TEST_I2C_HZ <= 100_000 ? 4700 : 1300;
    localparam integer MIN_HIGH = TEST_I2C_HZ <= 100_000 ? 4000 : 600;
    localparam integer MIN_START = TEST_I2C_HZ <= 100_000 ? 4000 : 600;
    localparam integer MIN_RESTART = TEST_I2C_HZ <= 100_000 ? 4700 : 600;
    localparam integer MIN_FREE = TEST_I2C_HZ <= 100_000 ? 4700 : 1300;
    localparam integer MIN_SETUP = TEST_I2C_HZ <= 100_000 ? 250 : 100;
    realtime last_rise=0, last_fall=0, last_data=0, last_start=0, last_stop=0;
    bit check_timing=0, in_transaction=0, start_pending=0;
    integer starts=0, stops=0, slave_completions=0;
    always @(posedge slave_clk) if (slave_done) slave_completions=slave_completions+1;
    always @(sda) begin
        if (check_timing && !reset && scl === 1'b1) begin
            if (sda === 1'b0) begin
                if (in_transaction && $realtime-last_rise < MIN_RESTART)
                    $fatal(1, "Repeated START setup too short");
                if (!in_transaction && last_stop != 0 && $realtime-last_stop < MIN_FREE)
                    $fatal(1, "Bus free time too short");
                last_start=$realtime; start_pending=1; in_transaction=1; starts=starts+1;
            end else if (sda === 1'b1) begin
                if ($realtime-last_rise < MIN_START) $fatal(1, "STOP setup too short");
                last_stop=$realtime; in_transaction=0; stops=stops+1;
            end
        end
        last_data=$realtime;
    end
    always @(posedge scl) begin
        if (check_timing && !reset) begin
            if (last_fall != 0 && $realtime-last_fall < MIN_LOW)
                $fatal(1, "SCL LOW too short: %0t", $realtime-last_fall);
            if ($realtime-last_data < MIN_SETUP) $fatal(1, "SDA setup too short");
        end
        last_rise=$realtime;
    end
    always @(negedge scl) begin
        if (check_timing && !reset) begin
            if ($realtime-last_rise < MIN_HIGH) $fatal(1, "SCL HIGH too short");
            if (start_pending && $realtime-last_start < MIN_START)
                $fatal(1, "START hold too short");
        end
        start_pending=0; last_fall=$realtime;
    end

    task transfer(input [7:0] selector, input bit want_timeout, input [15:0] expected);
        begin
            @(negedge clk); command=selector; start=1;
            @(negedge clk); start=0;
            wait(done); @(negedge clk);
            if (nack !== 0 || timeout_error !== want_timeout || response !== expected)
                $fatal(1, "Transfer mismatch: nack=%b timeout=%b data=%h", nack, timeout_error, response);
        end
    endtask

    // An independent bit-banged controller checks Slave behavior beyond the
    // paired Master's fixed repeated-START, ACK-first/NACK-last transaction.
    task bus_start;
        begin
            manual_sda=0; manual_scl=0; #5000;
            manual_sda=1; #5000; manual_scl=1;
        end
    endtask
    task bus_stop;
        begin
            #100; manual_sda=1; #4900; manual_scl=0;
            #5000; manual_sda=0; #5000;
        end
    endtask
    task write_bit(input bit value);
        begin
            #100; manual_sda=!value; #4900; manual_scl=0;
            #5000; manual_scl=1;
        end
    endtask
    task write_byte(input [7:0] value, input bit expect_ack);
        reg ack_value;
        integer i;
        begin
            for (i=7; i>=0; i=i-1) write_bit(value[i]);
            #100; manual_sda=0; #4900; manual_scl=0;
            #2500; ack_value=sda; #2500; manual_scl=1;
            if (ack_value !== !expect_ack) $fatal(1, "Manual address/register ACK mismatch");
        end
    endtask
    task read_byte(output [7:0] value);
        integer i;
        begin
            for (i=7; i>=0; i=i-1) begin
                #100; manual_sda=0; #4900; manual_scl=0;
                #2500; value[i]=sda; #2500; manual_scl=1;
            end
        end
    endtask
    reg [7:0] high_byte, low_byte;
    integer completions_before;
    initial begin
        repeat(10) @(negedge clk); reset=0;
        #100; check_timing=1;
        transfer(1, 0, 25); transfer(2, 0, 63); transfer(3, 0, 301);
        if (starts != 6 || stops != 3) $fatal(1, "Unexpected START/STOP count");
        $display("PASS: bus timing and values at %0d Hz", TEST_I2C_HZ);
        check_timing=0;

        // Stretch an actual data clock, rather than only the initial bus wait.
        fork
            begin
                wait(master.state == master.TX_BYTE && master.phase == 1);
                stretch=1; #20_000; stretch=0;
            end
            transfer(2, 0, 63);
        join

        // Pointer write with STOP, followed by a separate read transaction.
        bus_start(); write_byte(8'h84, 1); write_byte(3, 1); bus_stop();
        bus_start(); write_byte(8'h85, 1);
        read_byte(high_byte); write_bit(0);
        read_byte(low_byte); write_bit(1); bus_stop();
        if ({high_byte,low_byte} !== 16'd301) $fatal(1, "STOP-separated read mismatch");

        completions_before=slave_completions;
        bus_start(); write_byte(8'h85, 1); read_byte(high_byte); write_bit(1);
        #100;
        if (slave.sda_low || slave.state != slave.WAIT_STOP)
            $fatal(1, "Early Master NACK did not release Slave");
        bus_stop();
        if (slave_completions != completions_before+1) $fatal(1, "Early NACK completion mismatch");

        // This fixed-length Slave stops even if the Master ACKs byte two.
        bus_start(); write_byte(8'h85, 1);
        read_byte(high_byte); write_bit(0); read_byte(low_byte); write_bit(0);
        #100;
        if (slave.sda_low || slave.state != slave.WAIT_STOP) $fatal(1, "Fixed length not enforced");
        bus_stop();
        bus_start(); write_byte(8'h86, 0); bus_stop(); // wrong address
        bus_start(); write_byte(8'h84, 1); write_byte(8'hff, 0); bus_stop();
        bus_start(); write_byte(8'h85, 0); bus_stop(); // invalid pointer

        // Abort with no STOP; the Slave must recover on its idle timeout.
        bus_start(); write_byte(8'h84, 1); #1_200_000;
        if (selected || slave.sda_low || slave.state != slave.IDLE)
            $fatal(1, "Slave idle timeout failed");
        bus_stop(); transfer(1, 0, 25);

        // Release stuck SDA after nine recovery pulses, then retry normally.
        stuck_sda=1;
        fork
            begin
                wait(master.state == master.RECOVER);
                repeat(9) @(posedge scl);
                @(negedge scl); #50; stuck_sda=0;
            end
            transfer(1, 0, 25);
        join
        // Permanently stuck SDA must time out and release both FPGA drivers.
        stuck_sda=1; transfer(1, 1, 0);
        if (master.sda_low || master.scl_low) $fatal(1, "Timeout left drivers asserted");
        stuck_sda=0;
        #50_000; transfer(3, 0, 301);
        $display("PASS: optimized I2C at %0d Hz: timing, mid-bit stretch, STOP-separated read, early NACK, fixed length, wrong address, idle timeout, recovery, stuck SDA", TEST_I2C_HZ);
        $finish;
    end
    initial begin #20_000_000; $fatal(1, "Optimized I2C test watchdog"); end
endmodule
