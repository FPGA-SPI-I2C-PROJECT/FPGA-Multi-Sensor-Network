`timescale 1ns / 1ps

module uart_tx #(parameter BPS = 9600)(
    input clk,
    input reset,
    input [7:0] tx_data,
    input tx_start,
    output reg tx,
    output reg tx_busy
    );

    localparam DIV = 100_000_000 / BPS;
    localparam S_IDLE = 2'b00;
    localparam S_START_BIT = 2'b01;
    localparam S_DATA_BIT = 2'b10;
    localparam S_STOP_BIT = 2'b11;

    reg [1:0] tx_state;
    reg [3:0] bit_cnt;
    reg [7:0] data_reg;
    reg [15:0] baud_cnt;
    reg baud_tick;  // 10416 ns마다 1 tick 발생용

    // 10416 ns 마다 1 tick 발생
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            baud_cnt <= 0;
            baud_tick <= 0;
        end
        else begin
            if (baud_cnt >= DIV - 1) begin
                baud_cnt <= 0;
                baud_tick <= 1;
            end
            else begin
                baud_cnt <= baud_cnt + 1;
                baud_tick <= 0;
            end
        end
    end

    always @(posedge clk, posedge reset) begin
        if (reset) begin
            tx_state <= S_IDLE; // state transition
            bit_cnt <= 0;       // 전송 bit cnt
            data_reg <= 0;      // 전송할 1 byte
            tx_busy <= 0;   
            tx <= 1;            // IDLE: HIGH
        end
        else begin
            case (tx_state)
                S_IDLE: begin
                    if(tx_start) begin
                        tx_state <= S_START_BIT;
                        data_reg <= tx_data;    // 전송할 data를 복사
                        tx_busy <= 1'b1;        // 전송 중을 알림
                        bit_cnt <= 0;
                    end
                end
                S_START_BIT: begin
                    if(baud_tick) begin
                        tx <= 1'b0;
                        tx_state <= S_DATA_BIT;
                    end
                end
                S_DATA_BIT: begin
                    if(baud_tick) begin
                        tx <= data_reg[bit_cnt];
                        if (bit_cnt == 4'd7) begin
                            tx_state <= S_STOP_BIT;
                        end
                        else begin
                            bit_cnt <= bit_cnt + 1;
                        end
                    end
                end
                S_STOP_BIT: begin
                    if(baud_tick) begin
                        tx <= 1'b1;     // STOP bit
                        tx_busy <= 1'b0;
                        tx_state <= S_IDLE;
                    end
                end
                default: tx_state <= S_IDLE;
            endcase
        end
    end
endmodule
