`timescale 1ns / 1ps
// Companion to spi_master_transfer: mode 0, MSB first, 8 command + 16 reply.
// All internal state uses the Slave's independent 100 MHz clock.
// At 100 MHz use SCLK <= 1 MHz, with CS setup/high time >= 100 ns.
module spi_sensor_slave #(
    parameter [7:0] CMD_TEMP = 8'h01,
    parameter [7:0] CMD_HUMI = 8'h02,
    parameter [7:0] CMD_DIST = 8'h03
)(
    input wire clk, reset,
    input wire spi_sclk, spi_mosi, spi_cs_n,
    output wire spi_miso,
    input wire [7:0] reg_temp, reg_humi,
    input wire [8:0] reg_dist,
    output wire selected,
    output reg transaction_done, command_error,
    output reg [7:0] last_command
);
    (* ASYNC_REG = "TRUE" *) reg [2:0] sclk_sync, cs_sync, mosi_sync;
    reg [4:0] bit_count;
    reg [7:0] command_shift;
    reg [15:0] reply_shift;
    reg miso_bit;
    wire rising_sclk = sclk_sync[2:1] == 2'b01;
    wire falling_sclk = sclk_sync[2:1] == 2'b10;
    wire [7:0] received_command = {command_shift[6:0],mosi_sync[2]};
    assign selected = !cs_sync[2];
    // Raw CS gates the output buffer immediately, including a Master abort.
    assign spi_miso = (!spi_cs_n && !reset) ? miso_bit : 1'bz;

    always @(posedge clk) begin
        if (reset) begin
            sclk_sync <= 0; cs_sync <= 3'b111; mosi_sync <= 0;
        end else begin
            sclk_sync <= {sclk_sync[1:0],spi_sclk};
            cs_sync <= {cs_sync[1:0],spi_cs_n};
            mosi_sync <= {mosi_sync[1:0],spi_mosi};
        end
    end
    always @(posedge clk) begin
        if (reset) begin
            bit_count <= 0; command_shift <= 0; reply_shift <= 0;
            miso_bit <= 0; transaction_done <= 0;
            command_error <= 0; last_command <= 0;
        end else begin
            transaction_done <= 0;
            if (cs_sync[2]) begin
                bit_count <= 0; command_shift <= 0;
                reply_shift <= 0; miso_bit <= 0;
            end else begin
                if (rising_sclk && bit_count < 24) begin
                    bit_count <= bit_count+1;
                    if (bit_count < 8) begin
                        command_shift <= received_command;
                        if (bit_count == 7) begin
                            last_command <= received_command;
                            command_error <= 0;
                            // Snapshot one selected register; later sensor updates
                            // cannot change the remaining bits of this response.
                            case (received_command)
                                CMD_TEMP: reply_shift <= {8'b0,reg_temp};
                                CMD_HUMI: reply_shift <= {8'b0,reg_humi};
                                CMD_DIST: reply_shift <= {7'b0,reg_dist};
                                default: begin reply_shift <= 0; command_error <= 1; end
                            endcase
                        end
                    end
                    if (bit_count == 23) transaction_done <= 1;
                end
                // The falling edge after command bit 0 sets reply bit 15.
                if (falling_sclk && bit_count >= 8 && bit_count < 24) begin
                    miso_bit <= reply_shift[15];
                    reply_shift <= {reply_shift[14:0],1'b0};
                end
            end
        end
    end
endmodule
