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

    output reg ultra_start_tick, // 2Hz(500ms) 주기 펄스
    output reg dht_start_tick    // 1.5초 주기 1클럭 펄스
);

    // 2Hz = 500ms (50,000,000 클록 - 1)
    localparam ULTRA_MAX = CLK_FREQ / 2 - 1;       
    localparam DHT_MAX   = (CLK_FREQ * 3) / 2 - 1;   // 1.5s (150,000,000 - 1)

    // 50,000,000을 담기 위해 26비트로 확장 (2^26 = 67,108,864)
    reg [25:0] r_cnt_ultra;
    reg [27:0] r_cnt_dht;

    // 1. 초음파 센서 트리거 카운터 (2Hz = 500ms 주기)
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            r_cnt_ultra      <= 26'd0;
            ultra_start_tick <= 1'b0;
        end else begin
            if (r_cnt_ultra >= ULTRA_MAX) begin
                r_cnt_ultra      <= 26'd0;
                ultra_start_tick <= 1'b1;
            // 1클록(10ns) 만에 끄지 않고, 10us(1,000 클록) 동안 유지하여 초음파 모듈의 1us tick이 무조건 잡도록 함
            end else if (r_cnt_ultra >= 1000) begin
                ultra_start_tick <= 1'b0;
                r_cnt_ultra      <= r_cnt_ultra + 1'b1;
            end else begin
                r_cnt_ultra      <= r_cnt_ultra + 1'b1;
            end
        end
    end

    // 2. DHT11 센서 트리거 카운터 (1.5s) - 기존 유지
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