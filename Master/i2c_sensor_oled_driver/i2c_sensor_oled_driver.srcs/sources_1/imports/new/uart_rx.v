`timescale 1ns / 1ps

module uart_rx # (
    parameter BPS = 9600
) (
    input clk,
    input reset,
    input rx,
    output reg [7:0] data_out,
    output reg rx_done  // 수신 완료
    );
    
    localparam S_IDLE = 2'b00;
    localparam S_START_BIT = 2'b01;
    localparam S_DATA_8BITS = 2'b10;
    localparam S_STOP_BIT = 2'b11;

    // 9600 * 16 = 153,600
    // 100_000_000 Hz / 153,600 = 651 ns (651 ns 주기로 sampling)
    // 9600 Hz ( 651 ns * 16 = 10416 ns) * 9600 => 100_000_000 Hz
    localparam DIV = 100_000_000 / (BPS * 16);  // 16 oversampling

    reg [1:0] rx_state;         // state: IDLE START DATA_BITS STOP_BIT
    reg [3:0] bit_cnt;          // r_data_reg에 들어갈 index 값
    reg [7:0] data_reg;         // rx 포트로부터 들어온 bit를 담을 그릇
    reg [15:0] baud_cnt;        // 651 ns: 9600 x 16 오버샘플링 (16) cnt 변수
    reg baud_tick;              // 651 ns 마다 tick 발생
    reg [3:0] baud_tick_cnt;    // 16개 오버샘플링 값 count

    // 1. 651 ns tick을 생성하는 logic
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            baud_cnt <= 0;
            baud_tick <= 0;
        end
        
        else begin
            if(baud_cnt >= DIV - 1) begin
                baud_cnt <= 0;
                baud_tick <= 1'b1;
            end
            else begin
                baud_cnt <= baud_cnt + 1;
                baud_tick <= 1'b0;
            end
        end
    end

    // 2. rx_bit을 수신하는 FSM
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            rx_state <= S_IDLE;
            bit_cnt <= 4'd0;
            data_reg <= 8'b0;
            baud_tick_cnt <= 4'd0;
            data_out <= 8'd0;
            rx_done <= 1'b0;
        end

        else begin
            case(rx_state)
                S_IDLE: begin
                    rx_done <= 1'b0;
                    if(!rx) begin
                        rx_state <= S_START_BIT;
                        baud_tick_cnt <= 4'd0;
                    end
                end
                S_START_BIT: begin
                    if(baud_tick) begin
                        baud_tick_cnt <= baud_tick_cnt + 1;
                        if(baud_tick_cnt >= 4'd7) begin
                            rx_state <= S_DATA_8BITS;
                            baud_tick_cnt <= 4'd0;
                            bit_cnt <= 4'd0;
                        end
                    end
                end
                S_DATA_8BITS: begin
                    if(baud_tick) begin
                        baud_tick_cnt <= baud_tick_cnt + 1;
                        if(baud_tick_cnt >= 4'd15) begin
                            data_reg[bit_cnt] <= rx;
                            baud_tick_cnt <= 4'd0;

                            if(bit_cnt >= 4'd7) begin
                                rx_state <= S_STOP_BIT;
                                bit_cnt <= 4'd0;
                            end
                            else bit_cnt <= bit_cnt + 1;        
                        end
                    end
                end
                S_STOP_BIT: begin
                    if(baud_tick) begin
                        baud_tick_cnt <= baud_tick_cnt + 1;
                        if(baud_tick_cnt >= 4'd15) begin
                            rx_state <= S_IDLE;
                            baud_tick_cnt <= 4'd0;
                            data_out <= data_reg;
                            rx_done <= 1'b1;
                        end
                    end
                end
                default: rx_state <= S_IDLE;
            endcase
        end
    end
endmodule
