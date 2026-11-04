`timescale 1ns / 1ps
// Mode 0, MSB first. One CS assertion covers command[7:0] + 16 dummy bits.
// This is a proposed transport, NOT a protocol implemented by feat/slave/unit.
module spi_master_transfer #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer SPI_HZ = 100_000
)(
    input clk,
    input reset,
    input start,
    input [7:0] command,
    input spi_miso,
    output reg spi_sclk, spi_mosi, spi_cs_n,
    output reg busy, done,
    output reg [15:0] response
);
    localparam integer HALF = CLK_HZ / (2 * SPI_HZ);
    reg [31:0] divider;
    reg [23:0] tx_shift, rx_shift;
    reg [4:0] bit_count;
    reg tail;
    (* ASYNC_REG = "TRUE" *) reg [1:0] miso_sync;
    always @(posedge clk) begin
        if (reset) miso_sync <= 0;
        else miso_sync <= {miso_sync[0], spi_miso};
    end
    always @(posedge clk) begin
        if (reset) begin
            spi_sclk <= 0; spi_mosi <= 0; spi_cs_n <= 1;
            busy <= 0; done <= 0; response <= 0;
            divider <= 0; tx_shift <= 0; rx_shift <= 0;
            bit_count <= 0; tail <= 0;
        end else begin
            done <= 0;
            if (!busy) begin
                if (start) begin
                    tx_shift <= {command,16'b0}; rx_shift <= 0;
                    spi_mosi <= command[7]; spi_cs_n <= 0;
                    spi_sclk <= 0; busy <= 1;
                    divider <= 0; bit_count <= 0; tail <= 0;
                end
            end else if (divider == HALF-1) begin
                divider <= 0;
                if (tail) begin
                    spi_cs_n <= 1; spi_mosi <= 0;
                    response <= rx_shift[15:0];
                    busy <= 0; done <= 1; tail <= 0;
                end else if (!spi_sclk) begin
                    spi_sclk <= 1;
                    rx_shift <= {rx_shift[22:0],miso_sync[1]};
                end else begin
                    spi_sclk <= 0;
                    if (bit_count == 23) tail <= 1;
                    else begin
                        bit_count <= bit_count+1;
                        tx_shift <= {tx_shift[22:0],1'b0};
                        spi_mosi <= tx_shift[22];
                    end
                end
            end else divider <= divider+1;
        end
    end
endmodule
