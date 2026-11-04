`timescale 1ns / 1ps
// Standalone Basys3 output-pad diagnostic. No clock, reset, or SPI state.
module cs_pin_test (
    output wire spi_cs_n
);
    assign spi_cs_n = 1'b1;
endmodule
