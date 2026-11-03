`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/03 10:52:35
// Design Name: 
// Module Name: ultrasonic_senser
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


module ultrasonic_sensor (
    input clk,
    input reset,
    input start_trig,
    output reg trig,
    input echo,
    output reg [8:0] distance
);

    parameter
        IDLE         = 2'd0,
        START_SIGNAL = 2'd1,
        WAIT_HIGH    = 2'd2,
        READ_DATA    = 2'd3;

    reg [1:0] state;
    wire tick;
    reg [14:0] tick_cnt;

    tick_generator #(
        .TICK_FREQ_HZ(1_000_000)
    ) U_tick_1Hz(
        .clk(clk),
        .reset(reset),
        .tick(tick)
    );

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            trig <= 0;
            distance <= 14'b0;
            tick_cnt <= 0;
        end else if (tick) begin
            case (state)
                IDLE: begin
                    if (start_trig) begin
                        trig <= 1;
                        tick_cnt <= 0;
                        state <= START_SIGNAL;
                    end
                end

                START_SIGNAL: begin
                    if (tick_cnt == 10) begin
                        trig <= 0;
                        tick_cnt <= 0;
                        state <= WAIT_HIGH;
                    end else begin
                        tick_cnt <= tick_cnt + 1;
                    end
                end

                WAIT_HIGH: begin
                    if (echo) begin
                        tick_cnt <= 0;
                        state <= READ_DATA;
                    end else if (tick_cnt > 10_000) begin
                        state <= IDLE;
                    end else begin
                        tick_cnt <= tick_cnt + 1;
                    end
                end

                READ_DATA: begin
                    if (!echo) begin
                        distance <= tick_cnt / 58;
                        state <= IDLE;
                    end else if (tick_cnt > 10_000) begin
                        state <= IDLE;
                    end else begin
                        tick_cnt <= tick_cnt + 1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
