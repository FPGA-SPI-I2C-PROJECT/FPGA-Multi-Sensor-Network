`timescale 1ns / 1ps
// Alternate Top. The upstream top_slave.v and all sensor/UART RTL stay intact.
module top_slave_spi (
    input wire clk, reset, echo, RsRx,
    output wire trig, RsTx,
    output wire [15:0] led,
    inout wire dht11_data,
    input wire spi_sclk, spi_mosi, spi_cs,
    output wire spi_miso,
    output wire test_uart_rx, test_uart_tx
);
    (* ASYNC_REG = "TRUE" *) reg [3:0] reset_pipe = 4'b1111;
    always @(posedge clk or posedge reset)
        if (reset) reset_pipe <= 4'b1111;
        else reset_pipe <= {reset_pipe[2:0],1'b0};
    wire local_reset = reset_pipe[3];
    wire dht_start, ultra_start, dht_done, ultra_done, dht_error;
    wire [7:0] measured_temp, measured_humi, reg_temp, reg_humi;
    wire [8:0] measured_dist, reg_dist;
    wire spi_selected, spi_done, spi_error;
    wire [7:0] last_command;
    reg spi_seen;

    sensor_trigger_generator trigger_generator (
        .clk(clk),.reset(local_reset),.ultra_start_tick(ultra_start),.dht_start_tick(dht_start)
    );
    dht11_sensor dht (
        .clk(clk),.reset(local_reset),.start(dht_start),.dht11_data(dht11_data),
        .humidity(measured_humi),.temperature(measured_temp),.done(dht_done),.err(dht_error)
    );
    ultrasonic_sensor ultrasonic (
        .clk(clk),.reset(local_reset),.start_trig(ultra_start),.trig(trig),
        .echo(echo),.distance(measured_dist),.done(ultra_done)
    );
    sensor_reg_bank registers (
        .clk(clk),.reset(local_reset),.dht_done(dht_done),
        .dht_temp(measured_temp),.dht_humi(measured_humi),
        .ultra_done(ultra_done),.ultra_dist(measured_dist),
        .reg_temp(reg_temp),.reg_humi(reg_humi),.reg_dist(reg_dist)
    );
    uart_controller uart (
        .clk(clk),.reset(local_reset),.rx(RsRx),
        .reg_temp(reg_temp),.reg_humi(reg_humi),.reg_dist(reg_dist),.tx(RsTx)
    );
    spi_sensor_slave spi (
        .clk(clk),.reset(local_reset),.spi_sclk(spi_sclk),.spi_mosi(spi_mosi),
        .spi_cs_n(spi_cs),.spi_miso(spi_miso),.reg_temp(reg_temp),
        .reg_humi(reg_humi),.reg_dist(reg_dist),.selected(spi_selected),
        .transaction_done(spi_done),.command_error(spi_error),.last_command(last_command)
    );
    always @(posedge clk)
        if (local_reset) spi_seen <= 0;
        else if (spi_done) spi_seen <= 1;
    assign test_uart_rx = RsRx;
    assign test_uart_tx = RsTx;
    assign led = {dht_error,spi_error,spi_selected,spi_seen,3'b0,reg_dist};
endmodule
