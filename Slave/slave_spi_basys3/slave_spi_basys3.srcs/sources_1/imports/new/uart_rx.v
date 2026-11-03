`timescale 1ns / 1ps


module uart_rx #(
    parameter BPS = 9600
)(
    input clk, reset,
    input rx,

    output reg [7:0] data_out,
    output reg rx_done
);
    parameter S_IDLE = 2'b00;
    parameter S_START_BIT = 2'b01;
    parameter S_DATA_8BITS = 2'b10;
    parameter S_STOP_BIT = 2'b11;

    //9600 * 16 = 153,600
    // 100_000_000 Hz / 153,600 = 651ns (651ns주기로 sampling)
    //9600Hz (651ns * 16 = 10416ns) 9600 ==> 100_000_000 Hz
    parameter integer  DIVIDER_CNT = 100_000_000 / (BPS * 16);

    reg [1:0] r_rx_state; // state transition
    reg [3:0] r_bit_cnt; // r_data_reg에 저장할 index값
    reg [7:0] r_data_reg; // rx 포트로 부터 들어온 bit를 담을 그릇 (8bit)
    reg [15:0] r_baud_cnt; // 651ns
    reg r_baud_tick; // 651ns마다 1tick 발생
    reg [3:0] r_baud_tick_cnt; //16개 오버 샘플링 count

    //1. 651ns tick을 생성 하는 logic
    always @(posedge clk, posedge reset) begin
        if(reset)begin
            r_baud_cnt <=0;
            r_baud_tick <=0;
        end else begin
            if(r_baud_cnt >= DIVIDER_CNT -1) begin
                r_baud_cnt <=0;
                r_baud_tick <=1;
            end else begin
                r_baud_cnt <= r_baud_cnt + 1;
                r_baud_tick <= 0;
            end
        end
    end

    //2. rx bit를 수신하는 FSM
    always @(posedge clk, posedge reset) begin
        if (reset) begin
            r_rx_state <= S_IDLE; 
            r_bit_cnt <= 4'b0;      
            r_data_reg <= 8'b0;   
            r_baud_tick_cnt <= 4'd0;   
            data_out <= 8'd0;
            rx_done <= 1'b0;
        end else begin
            case (r_rx_state)
               S_IDLE : begin
                    rx_done <= 1'b0;
                    if(!rx) begin
                        r_rx_state <= S_START_BIT;
                        r_baud_tick_cnt <= 4'd0;
                    end
               end
               S_START_BIT : begin
                    if (r_baud_tick) begin
                        r_baud_tick_cnt <= r_baud_tick_cnt + 1;
                        if (r_baud_tick_cnt >= 4'd7) begin
                            r_rx_state <= S_DATA_8BITS;
                            r_baud_tick_cnt <= 4'd0;
                            r_bit_cnt <= 4'd0;
                        end 
                    end
               end
               S_DATA_8BITS : begin
                    if (r_baud_tick) begin
                        r_baud_tick_cnt <= r_baud_tick_cnt + 1;
                        if (r_baud_tick_cnt >= 4'd15) begin
                            r_data_reg[r_bit_cnt] <= rx;
                            r_baud_tick_cnt <= 4'd0;

                            if (r_bit_cnt >= 4'd7) r_rx_state <= S_STOP_BIT;
                            else r_bit_cnt <= r_bit_cnt + 1;
                        end 
                    end
               end
               S_STOP_BIT : begin
                    if (r_baud_tick) begin
                        r_baud_tick_cnt <= r_baud_tick_cnt + 1;
                        if (r_baud_tick_cnt >= 4'd15) begin
                            r_rx_state <= S_IDLE;
                            data_out <= r_data_reg;
                            rx_done <= 1;
                        end 
                    end
               end
                default:  r_rx_state <= S_IDLE;
            endcase
        end
    end
endmodule
