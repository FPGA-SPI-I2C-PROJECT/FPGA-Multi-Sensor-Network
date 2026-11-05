`timescale 1ns / 1ps
// START, address+W, register, repeated START, address+R, MSB, ACK, LSB,
// NACK, STOP. One open-drain driver per pin; supports clock stretching.
module i2c_sensor_read_master #(
    parameter CLK_HZ = 100_000_000,
    parameter I2C_HZ = 100_000,
    parameter TIMEOUT_MS = 250,
    parameter [6:0] SLAVE_ADDR = 7'h42
)(
    input clk, reset, start,
    input [7:0] command,
    inout sda, scl,
    output reg busy, done, nack, timeout_error,
    output reg [15:0] response
);
    localparam integer Q = (CLK_HZ+4*I2C_HZ-1)/(4*I2C_HZ);
    localparam integer LIMIT = (CLK_HZ/1000)*TIMEOUT_MS;
    localparam  IDLE=0, BUS_FREE=1, START_HOLD=2, START_LOW=3,
                TX_SET=4, TX_RISE=5, TX_HIGH=6, TX_FALL=7,
                ACK_SET=8, ACK_RISE=9, ACK_HIGH=10, ACK_FALL=11, NEXT_TX=12,
                RESTART_LOW=13, RESTART_RISE=14, RESTART_HIGH=15,
                RX_SET=16, RX_RISE=17, RX_HIGH=18, RX_FALL=19,
                MASTER_ACK_SET=20, MASTER_ACK_RISE=21, MASTER_ACK_HIGH=22,
                MASTER_ACK_FALL=23, STOP_SET=24, STOP_RISE=25, STOP_HIGH=26,
                STOP_RELEASE=27, STOP_FREE=28, REC_LOW=29, REC_RISE=30,
                REC_HIGH=31, REC_FALL=32;
    reg [5:0] state;
    reg [31:0] divider, watchdog;
    reg sda_low, scl_low;
    reg [7:0] tx_shift, register_select;
    reg [2:0] tx_bit;
    reg [3:0] rx_bit, recovery_count;
    reg [1:0] tx_stage;
    reg [15:0] rx_shift;
    reg recovering, recovery_attempted;
    (* ASYNC_REG = "TRUE" *) reg [1:0] sda_sync, scl_sync;
    assign sda = sda_low ? 1'b0 : 1'bz;
    assign scl = scl_low ? 1'b0 : 1'bz;
    always @(posedge clk) begin
        if (reset) begin sda_sync <= 3; scl_sync <= 3; end
        else begin sda_sync <= {sda_sync[0],sda}; scl_sync <= {scl_sync[0],scl}; end
    end
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            divider <= 0; watchdog <= 0;
            sda_low <= 0; scl_low <= 0;
            busy <= 0; done <= 0;
            nack <= 0; timeout_error <= 0; response <= 0;
            tx_shift <= 0; register_select <= 0; tx_bit <= 7; tx_stage <= 0;
            rx_shift <= 0; rx_bit <= 15; recovery_count <= 0;
            recovering <= 0; recovery_attempted <= 0;
        end else begin
            done <= 0;
            if (!busy) begin
                divider <= 0; watchdog <= 0;
                if (start) begin
                    busy <= 1; nack <= 0; timeout_error <= 0; response <= 0;
                    register_select <= command;
                    tx_shift <= {SLAVE_ADDR,1'b0};
                    tx_stage <= 0; tx_bit <= 7;
                    rx_bit <= 15; rx_shift <= 0;
                    recovering <= 0; recovery_attempted <= 0;
                    state <= BUS_FREE;
                end
            end else if (watchdog >= LIMIT-1) begin
                sda_low <= 0; scl_low <= 0;
                busy <= 0; done <= 1;
                timeout_error <= 1;
                response <= 0;
                state <= IDLE;
            end else begin
                watchdog <= watchdog+1;
                if (divider == Q-1) begin
                    divider <= 0;
                    case (state)
                        BUS_FREE: if (scl_sync[1]) begin
                            if (sda_sync[1]) begin
                                sda_low <= 1;
                                state <= START_HOLD;
                                end
                            else if (!recovery_attempted) begin
                                recovering <= 1; recovery_attempted <= 1;
                                recovery_count <= 0;
                                scl_low <= 1;
                                state <= REC_LOW;
                            end
                        end
                        START_HOLD: begin
                            scl_low <= 1;
                            state <= START_LOW;
                        end
                        START_LOW: state <= TX_SET;
                        TX_SET: begin
                            sda_low <= !tx_shift[tx_bit];
                            state <= TX_RISE;
                            end
                        TX_RISE: begin scl_low <= 0; state <= TX_HIGH; end
                        TX_HIGH: if (scl_sync[1]) state <= TX_FALL;
                        TX_FALL: begin
                            scl_low <= 1;
                            if (tx_bit == 0) state <= ACK_SET;
                            else begin tx_bit <= tx_bit-1; state <= TX_SET; end
                        end
                        ACK_SET: begin sda_low <= 0; state <= ACK_RISE; end
                        ACK_RISE: begin scl_low <= 0; state <= ACK_HIGH; end
                        ACK_HIGH: if (scl_sync[1]) begin
                            if (sda_sync[1]) nack <= 1;
                            state <= ACK_FALL;
                        end
                        ACK_FALL: begin scl_low <= 1; state <= NEXT_TX; end
                        NEXT_TX: if (nack) state <= STOP_SET;
                            else case (tx_stage)
                                0: begin tx_shift <= register_select; tx_bit <= 7; tx_stage <= 1; state <= TX_SET; end
                                1: state <= RESTART_LOW;
                                default: state <= RX_SET;
                            endcase
                        RESTART_LOW: begin sda_low <= 0; state <= RESTART_RISE; end
                        RESTART_RISE: begin scl_low <= 0; state <= RESTART_HIGH; end
                        RESTART_HIGH: if (scl_sync[1]) begin
                            sda_low <= 1; tx_shift <= {SLAVE_ADDR,1'b1};
                            tx_bit <= 7; tx_stage <= 2; state <= START_HOLD;
                        end
                        RX_SET: begin sda_low <= 0; state <= RX_RISE; end
                        RX_RISE: begin scl_low <= 0; state <= RX_HIGH; end
                        RX_HIGH: if (scl_sync[1]) begin
                            rx_shift <= {rx_shift[14:0],sda_sync[1]}; state <= RX_FALL;
                        end
                        RX_FALL: begin
                            scl_low <= 1;
                            if (rx_bit == 8 || rx_bit == 0) state <= MASTER_ACK_SET;
                            else begin rx_bit <= rx_bit-1; state <= RX_SET; end
                        end
                        MASTER_ACK_SET: begin sda_low <= (rx_bit == 8); state <= MASTER_ACK_RISE; end
                        MASTER_ACK_RISE: begin scl_low <= 0; state <= MASTER_ACK_HIGH; end
                        MASTER_ACK_HIGH: if (scl_sync[1]) state <= MASTER_ACK_FALL;
                        MASTER_ACK_FALL: begin
                            scl_low <= 1;
                            if (rx_bit == 0) state <= STOP_SET;
                            else begin rx_bit <= 7; state <= RX_SET; end
                        end
                        STOP_SET: begin sda_low <= 1; state <= STOP_RISE; end
                        STOP_RISE: begin scl_low <= 0; state <= STOP_HIGH; end
                        STOP_HIGH: if (scl_sync[1]) state <= STOP_RELEASE;
                        STOP_RELEASE: begin sda_low <= 0; state <= STOP_FREE; end
                        STOP_FREE: if (recovering) begin recovering <= 0; state <= BUS_FREE; end
                            else begin
                                busy <= 0; done <= 1; state <= IDLE;
                                response <= nack ? 16'b0 : rx_shift;
                            end
                        REC_LOW: begin sda_low <= 0; scl_low <= 1; state <= REC_RISE; end
                        REC_RISE: begin scl_low <= 0; state <= REC_HIGH; end
                        REC_HIGH: if (scl_sync[1]) state <= REC_FALL;
                        REC_FALL: begin
                            scl_low <= 1;
                            if (recovery_count == 8) state <= STOP_SET;
                            else begin recovery_count <= recovery_count+1; state <= REC_LOW; end
                        end
                        default: state <= STOP_SET;
                    endcase
                end else divider <= divider+1;
            end
        end
    end
endmodule
