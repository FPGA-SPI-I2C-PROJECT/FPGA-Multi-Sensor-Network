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
    output reg spi_miso //데이터 송신

    );

    wire [7:0] w_humidity;
    wire [15:0] w_temperature;
    wire [8:0] w_distance;
    wire w_rx_done;
    wire [7:0] w_rx_data;

    // DHT11_controller u_DHT11_controller(
    //     .clk(clk),
    //     .reset(reset),
    //     .dht11_data(dht11_data),
    //     .humidity(w_humidity),
    //     .temperature(w_temperature)
    // );

    Ultrasonic_controller u_Ultrasonic_controller(
        .clk(clk),
        .reset(reset),
        .echo(echo),
        .trig(trig),
        .distance(w_distance)
    );

    Control_Unit u_Control_Unit(
        .clk(clk),
        .reset(reset),
        .humidity(w_humidity),
        .temperature(w_temperature),
        .distance(w_distance),
        .rx_done(w_rx_done),
        .rx_data(w_rx_data),
        .led(led),
        .tx_busy(),
        .tx_data(),
        .tx_req()
    ); 

    // Uart_controller u_Uart_controller(
    //     .clk(clk),
    //     .reset(reset),
    //     .rx(RsRx),
    //     .tx(RsTx),
    //     .rx_done(w_rx_done),
    //     .rx_data(w_rx_data)
    // );

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
