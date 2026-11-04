`timescale 1ns/1ps
module tb_i2c_sensor_errors;
    reg clk=0, slave_clk=0, reset=1, start=0, connected=0, stuck_scl=0;
    always #5 clk=~clk;
    always #5.1 slave_clk=~slave_clk;
    reg [7:0] command=1;
    reg [8:0] source_dist=301;
    tri1 sda,scl;
    assign scl=stuck_scl ? 1'b0 : 1'bz;
    wire busy,done,nack,timeout_error,selected,slave_done,command_error;
    wire [15:0] response;
    i2c_sensor_read_master #(.I2C_HZ(400_000),.TIMEOUT_MS(1)) master (
        .clk(clk),.reset(reset),.start(start),.command(command),.sda(sda),.scl(scl),
        .busy(busy),.done(done),.nack(nack),.timeout_error(timeout_error),.response(response)
    );
    i2c_sensor_slave slave (
        .clk(slave_clk),.reset(reset || !connected),.scl(scl),.sda(sda),
        .reg_temp(8'd25),.reg_humi(8'd63),.reg_dist(source_dist),
        .selected(selected),.transaction_done(slave_done),.command_error(command_error)
    );
    task begin_transfer(input [7:0] selector);
        begin
            @(negedge clk); command=selector; start=1;
            @(negedge clk); start=0;
        end
    endtask
    task finish_transfer(input bit want_nack,input bit want_timeout,input [15:0] expected);
        begin
            wait(done); @(negedge clk);
            if (nack !== want_nack || timeout_error !== want_timeout || response !== expected)
                $fatal(1,"I2C result mismatch: NACK=%b timeout=%b response=%h",nack,timeout_error,response);
        end
    endtask
    initial begin
        repeat(10) @(negedge clk); reset=0;
        begin_transfer(1); finish_transfer(1,0,0); // no Slave => address NACK
        connected=1; repeat(10) @(negedge clk);
        begin_transfer(1); finish_transfer(0,0,25);
        begin_transfer(8'hFF); finish_transfer(1,0,0); // invalid selector NACK
        if (!command_error) $fatal(1,"Invalid selector did not set Slave error");
        begin_transfer(3);
        wait(slave.state == 6 && slave.bit_count == 2);
        source_dist=400; // response must keep the snapshot 301 across both bytes
        finish_transfer(0,0,301);
        begin_transfer(3); finish_transfer(0,0,400);
        stuck_scl=1;
        begin_transfer(1); finish_transfer(0,1,0);
        if (master.scl_low || master.sda_low) $fatal(1,"Timeout did not release output drivers");
        stuck_scl=0; repeat(10) @(negedge clk);
        // A bounded stretch is tolerated, then communication resumes.
        stuck_scl=1;
        begin_transfer(2);
        #100_000; stuck_scl=0;
        finish_transfer(0,0,63);
        $display("PASS: I2C error paths, NACK, invalid register, timeout, stretch, snapshot");
        $finish;
    end
    initial begin #5_000_000; $fatal(1,"I2C error test watchdog"); end
endmodule
