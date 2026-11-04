`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/04 10:47:24
// Design Name: 
// Module Name: senser_trig_generator
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


`timescale 1ns / 1ps

module sensor_trigger_generator #(
    parameter CLK_FREQ = 100_000_000
)(
    input clk,
    input reset,

    output reg ultra_start_tick, // 100ms 주기 1클럭 펄스
    output reg dht_start_tick    // 1.5초 주기 1클럭 펄스
);

    localparam ULTRA_MAX = CLK_FREQ / 10 - 1;       // 100ms (10,000,000 - 1)
    localparam DHT_MAX   = (CLK_FREQ * 3) / 2 - 1;   // 1.5s  (150,000,000 - 1)

    reg [23:0] r_cnt_ultra;
    reg [27:0] r_cnt_dht;

    // 1. 초음파 센서 트리거 카운터 (100ms)
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            r_cnt_ultra      <= 24'd0;
            ultra_start_tick <= 1'b0;
        end else begin
            if (r_cnt_ultra >= ULTRA_MAX) begin
                r_cnt_ultra      <= 24'd0;
                ultra_start_tick <= 1'b1; // 1클럭 펄스
            end else begin
                r_cnt_ultra      <= r_cnt_ultra + 1'b1;
                ultra_start_tick <= 1'b0;
            end
        end
    end

    // 2. DHT11 센서 트리거 카운터 (1.5s)
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            r_cnt_dht      <= 28'd0;
            dht_start_tick <= 1'b0;
        end else begin
            if (r_cnt_dht >= DHT_MAX) begin
                r_cnt_dht      <= 28'd0;
                dht_start_tick <= 1'b1;   // 1클럭 펄스
            end else begin
                r_cnt_dht      <= r_cnt_dht + 1'b1;
                dht_start_tick <= 1'b0;
            end
        end
    end

endmodule
