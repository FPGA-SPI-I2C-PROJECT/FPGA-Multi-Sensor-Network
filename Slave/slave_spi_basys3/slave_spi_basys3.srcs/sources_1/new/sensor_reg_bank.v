`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/04 10:35:25
// Design Name: 
// Module Name: sensor_reg_bank
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


module sensor_reg_bank (
    input clk,
    input reset,

    // 센서 쓰기 인터페이스 (Producer)
    input        dht_done,
    input  [7:0] dht_temp,
    input  [7:0] dht_humi,
    input        ultra_done,
    input  [8:0] ultra_dist,

    // 통신 블록 읽기 포트 (Consumer: UART, SPI, I2C가 공유)
    output reg [7:0] reg_temp,
    output reg [7:0] reg_humi,
    output reg [8:0] reg_dist
);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            reg_temp <= 8'd0;
            reg_humi <= 8'd0;
            reg_dist <= 9'd0;
        end else begin
            if (dht_done) begin
                reg_temp <= dht_temp;
                reg_humi <= dht_humi;
            end
            if (ultra_done) begin
                reg_dist <= ultra_dist;
            end
        end
    end

endmodule
