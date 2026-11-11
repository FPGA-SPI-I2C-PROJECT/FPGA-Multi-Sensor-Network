`timescale 1ns / 1ps
// Alternative implementation. Compile instead of the original .v module.
// 0x42, register selectors 01/02/03, two-byte MSB-first response snapshot.
module i2c_sensor_slave #(
    parameter [6:0] SLAVE_ADDR = 7'h42,
    parameter integer CLK_HZ = 100_000_000,
    parameter integer IDLE_TIMEOUT_MS = 25
)(
    input wire clk, reset,
    input wire scl,
    inout wire sda,
    input wire [7:0] reg_temp, reg_humi,
    input wire [8:0] reg_dist,
    output wire selected,
    output reg transaction_done, command_error
);
    localparam [2:0] IDLE=0, RX_ADDRESS=1, RX_REGISTER=2,
        SLAVE_ACK=3, TX=4, MASTER_ACK=5, WAIT_STOP=6, IGNORE=7;
    localparam integer LIMIT = (64'd1 * CLK_HZ * IDLE_TIMEOUT_MS + 999) / 1000;
    localparam integer IDLE_W = LIMIT > 1 ? $clog2(LIMIT) : 1;
    (* ASYNC_REG = "TRUE" *) reg [2:0] sda_sync, scl_sync;
    reg [2:0] state, after_ack;
    reg [2:0] bit_count;
    reg [1:0] ack_phase;
    reg [7:0] rx_shift, register_select;
    reg [15:0] tx_shift;
    reg pointer_valid, sda_low, second_byte, master_nack;
    reg [IDLE_W-1:0] idle_count;
    wire scl_rise = scl_sync[2:1] == 2'b01;
    wire scl_fall = scl_sync[2:1] == 2'b10;
    wire start_seen = scl_sync[2] && sda_sync[2:1] == 2'b10;
    wire stop_seen = scl_sync[2] && sda_sync[2:1] == 2'b01;
    wire bus_activity = scl_rise || scl_fall || start_seen || stop_seen;
    wire idle_expired = state != IDLE && idle_count == LIMIT-1 && !bus_activity;
    wire [7:0] received = {rx_shift[6:0], sda_sync[2]};
    assign sda = sda_low ? 1'b0 : 1'bz;
    assign selected = state != IDLE && state != IGNORE;

    always @(posedge clk) begin
        if (reset) begin sda_sync <= 3'b111; scl_sync <= 3'b111; end
        else begin
            sda_sync <= {sda_sync[1:0], sda};
            scl_sync <= {scl_sync[1:0], scl};
        end
    end
    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE; after_ack <= IDLE; bit_count <= 0; ack_phase <= 0;
            rx_shift <= 0; register_select <= 0; tx_shift <= 0;
            pointer_valid <= 0; sda_low <= 0; second_byte <= 0; master_nack <= 0;
            transaction_done <= 0; command_error <= 0; idle_count <= 0;
        end else begin
            transaction_done <= 0;
            if (bus_activity || state == IDLE) idle_count <= 0;
            else if (idle_count < LIMIT-1) idle_count <= idle_count + 1'b1;

            // START, including repeated START, overrides the current transfer.
            // The register pointer deliberately survives STOP and idle timeout.
            if (start_seen) begin
                state <= RX_ADDRESS; rx_shift <= 0; bit_count <= 0;
                sda_low <= 0; ack_phase <= 0; second_byte <= 0;
            end else if (stop_seen || idle_expired) begin
                state <= IDLE; sda_low <= 0; idle_count <= 0; ack_phase <= 0;
            end else case (state)
                RX_ADDRESS, RX_REGISTER: if (scl_rise) begin
                    rx_shift <= received;
                    if (bit_count == 7) begin
                        bit_count <= 0; ack_phase <= 0;
                        if (state == RX_ADDRESS) begin
                            if (received[7:1] != SLAVE_ADDR) state <= IGNORE;
                            else if (!received[0]) begin
                                state <= SLAVE_ACK; after_ack <= RX_REGISTER;
                            end else if (!pointer_valid) state <= IGNORE;
                            else begin
                                state <= SLAVE_ACK; after_ack <= TX;
                                // Snapshot once for both response bytes.
                                case (register_select)
                                    8'h01: tx_shift <= {8'b0, reg_temp};
                                    8'h02: tx_shift <= {8'b0, reg_humi};
                                    default: tx_shift <= {7'b0, reg_dist};
                                endcase
                            end
                        end else if (received == 1 || received == 2 || received == 3) begin
                            register_select <= received; pointer_valid <= 1;
                            command_error <= 0;
                            state <= SLAVE_ACK; after_ack <= WAIT_STOP;
                        end else begin
                            pointer_valid <= 0; command_error <= 1; state <= IGNORE;
                        end
                    end else bit_count <= bit_count + 1'b1;
                end
                SLAVE_ACK: begin
                    if (ack_phase == 0 && scl_fall) begin
                        sda_low <= 1; ack_phase <= 1;
                    end else if (ack_phase == 1 && scl_rise) ack_phase <= 2;
                    else if (ack_phase == 2 && scl_fall) begin
                        sda_low <= 0; rx_shift <= 0; bit_count <= 0; ack_phase <= 0;
                        state <= after_ack;
                        if (after_ack == TX) begin
                            second_byte <= 0;
                            sda_low <= !tx_shift[15]; tx_shift <= {tx_shift[14:0], 1'b0};
                        end
                    end
                end
                TX: begin
                    if (scl_rise) begin
                        if (bit_count == 7) begin state <= MASTER_ACK; ack_phase <= 0; end
                        else bit_count <= bit_count + 1'b1;
                    end
                    if (scl_fall) begin
                        sda_low <= !tx_shift[15]; tx_shift <= {tx_shift[14:0], 1'b0};
                    end
                end
                MASTER_ACK: begin
                    // Reuse ack_phase: release at bit 8 fall, sample bit 9 rise,
                    // then act at bit 9 fall. Never release SDA at bit 8 rise.
                    if (ack_phase == 0 && scl_fall) begin
                        sda_low <= 0; ack_phase <= 1;
                    end else if (ack_phase == 1 && scl_rise) begin
                        master_nack <= sda_sync[2]; ack_phase <= 2;
                    end else if (ack_phase == 2 && scl_fall) begin
                        ack_phase <= 0;
                        if (master_nack || second_byte) begin
                            sda_low <= 0; state <= WAIT_STOP; transaction_done <= 1;
                        end else begin
                            second_byte <= 1; bit_count <= 0; state <= TX;
                            sda_low <= !tx_shift[15]; tx_shift <= {tx_shift[14:0], 1'b0};
                        end
                    end
                end
                default: sda_low <= 0;
            endcase
        end
    end
    // synthesis translate_off
    initial begin
        if (CLK_HZ <= 0 || IDLE_TIMEOUT_MS <= 0 || LIMIT <= 0)
            $fatal(1, "Invalid I2C Slave parameters");
    end
    // synthesis translate_on
endmodule
