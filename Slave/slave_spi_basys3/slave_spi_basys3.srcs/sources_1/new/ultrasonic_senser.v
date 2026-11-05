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
    output reg [8:0] distance,
    output reg done
);

    parameter
        IDLE         = 2'd0,
        START_SIGNAL = 2'd1,
        WAIT_HIGH    = 2'd2,
        READ_DATA    = 2'd3;

    reg [1:0] state;
    wire tick;
    reg [15:0] tick_cnt;

    tick_generator #(
        .TICK_FREQ_HZ(1_000_000)
    ) U_tick_1us (
        .clk(clk),
        .reset(reset),
        .tick(tick)
    );



    reg [2:0] echo_sync;
    always @(posedge clk or posedge reset) begin
        if (reset) echo_sync <= 3'b0;
        else       echo_sync <= {echo_sync[1:0], echo};
    end

    wire echo_posedge = (echo_sync[2:1] == 2'b01);
    wire echo_negedge = (echo_sync[2:1] == 2'b10);
    // wire echo_level   = echo_sync[1];

    // FSM: 상태 전환은 100MHz로 즉각 감지하되, 카운터 누적은 1us tick 기준으로 수행
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state    <= IDLE;
            trig     <= 1'b0;
            distance <= 9'd0;
            tick_cnt <= 15'd0;
            done     <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state)
                IDLE: begin
                    trig     <= 1'b0;
                    if (start_trig) begin
                        trig     <= 1'b1;
                        tick_cnt <= 15'd0;
                        state    <= START_SIGNAL;
                    end
                end

                START_SIGNAL: begin
                    if (tick) begin
                        if (tick_cnt >= 15'd10) begin // 10us 경과
                            trig     <= 1'b0;
                            tick_cnt <= 15'd0;
                            state    <= WAIT_HIGH;
                        end else begin
                            tick_cnt <= tick_cnt + 1'b1;
                        end
                    end
                end

                WAIT_HIGH: begin
                    if (echo_posedge) begin
                        tick_cnt <= 15'd0;
                        state    <= READ_DATA;
                    end else if (tick) begin
                        if (tick_cnt > 16'd60_000) begin // 타임아웃 보호
                            state <= IDLE;
                            done  <= 1'b1;
                        end else begin
                            tick_cnt <= tick_cnt + 1'b1;
                        end
                    end
                end

                READ_DATA: begin
                    if (echo_negedge) begin
                        distance <= tick_cnt / 58;
                        state    <= IDLE;
                        done     <= 1'b1;
                    end else if (tick) begin
                        if (tick_cnt > 15'd60_000) begin // 타임아웃 보호
                            state <= IDLE;
                            done  <= 1'b1;
                        end else begin
                            tick_cnt <= tick_cnt + 1'b1;
                        end
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule

module tick_generator (
    input clk, reset,
    output reg tick
);
    parameter INPUT_FREQ = 100_000_000;
    parameter TICK_FREQ_HZ = 1_000_000; // 1MHz = 1us 주기
    parameter TICK_COUNT = INPUT_FREQ / TICK_FREQ_HZ; // 100_000_000 / 1_000_000 = 100

    reg [$clog2(TICK_COUNT)-1:0] r_tick_1Hz_counter;

    always @(posedge clk, posedge reset) begin
        if(reset)begin
            tick <= 0;
            r_tick_1Hz_counter <= 0;
        end
        else begin
            if(r_tick_1Hz_counter == (TICK_COUNT - 1))begin
                tick <= 1;
                r_tick_1Hz_counter <= 0;
            end
            else begin
                r_tick_1Hz_counter <= r_tick_1Hz_counter + 1; 
                tick <= 0;
            end
        end
    end
    
endmodule
