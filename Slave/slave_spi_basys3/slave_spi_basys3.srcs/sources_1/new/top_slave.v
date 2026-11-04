`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/03 10:53:25
// Design Name: 
// Module Name: top_slave
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module top_slave(
    input clk,
    input reset,
    input echo,
    input RsRx,

    output trig,
    output RsTx,
    output [15:0] led,

    inout dht11_data,

    //spi 통신
    input spi_sclk, //외부 클록 수신
    input spi_mosi, //데이터 수신
    input spi_cs,   //활성화 신호 수신
    output reg spi_miso, //데이터 송신

    output test_uart_rx, test_uart_tx

    );

    reg [7:0] r_temp;
    reg [7:0] r_humi;
    reg [8:0] r_dist;


    wire [7:0] w_dht_temp, w_dht_humi;
    wire       w_dht_done;
    wire       w_dht11_err;

    wire [8:0] w_ultra_dist;
    wire       w_ultra_done;

    wire [7:0] w_out_dht_temp, w_out_dht_humi;
    wire [8:0] w_out_ultra_dist;

    wire w_dht_start, w_ultra_start;

    
    sensor_trigger_generator u_trigger_genergenerator (
        .clk(clk),
        .reset(reset),
        .ultra_start_tick(w_ultra_start),
        .dht_start_tick(w_dht_start)
    );

    dht11_sensor u_dht11_sensor(
        .clk(clk),
        .reset(reset),
        .start(w_dht_start),      
        .dht11_data(dht11_data), 
        .humidity(w_dht_humi),   
        .temperature(w_dht_temp),
        .done(w_dht_done),       
        .err(w_dht11_err)         
    );

    ultrasonic_sensor u_ultrasonic_sensor(
        .clk(clk),
        .reset(reset),
        .start_trig(w_ultra_start),
        .trig(trig),
        .echo(echo),
        .distance(w_ultra_dist),
        .done(w_ultra_done)
    );

    sensor_reg_bank u_reg_bank (
        .clk(clk), .reset(reset),
        .dht_done(w_dht_done),
        .dht_temp(w_dht_temp),
        .dht_humi(w_dht_humi),
        .ultra_done(w_ultra_done),
        .ultra_dist(w_ultra_dist),

        .reg_temp(w_out_dht_temp),
        .reg_humi(w_out_dht_humi),
        .reg_dist(w_out_ultra_dist)
    );


    uart_controller u_uart_controller(
        .clk(clk),
        .reset(reset),
        .rx(RsRx),
        .reg_temp(w_out_dht_temp),
        .reg_humi(w_out_dht_humi),
        .reg_dist(w_out_ultra_dist),
        .tx(RsTx)
    );

    assign test_uart_rx = RsRx;
    assign test_uart_tx = RsTx;

    // Spi_slave_controller u_Spi_slave_controller(
    //     .clk(clk),
    //     .reset(reset),          
    //     .spi_sclk(spi_sclk),   
    //     .spi_mosi(spi_mosi),   
    //     .spi_miso(),   
    //     .spi_cs(spi_cs),     
    //     .sensor_data_in() 
    // );

endmodule
