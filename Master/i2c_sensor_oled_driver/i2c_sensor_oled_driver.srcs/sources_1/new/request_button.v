`timescale 1ns / 1ps
module btn_debouncer #(
    parameter integer DEBOUNCING_TIME = 1_000_000
)(input wire clk, reset, button, output reg pressed);
    (* ASYNC_REG = "TRUE" *) reg [1:0] sync_button;
    reg stable;
    reg [31:0] count;
    always @(posedge clk) begin
        if (reset) begin
            sync_button <= 0; stable <= 0; count <= 0; pressed <= 0;
        end else begin
            sync_button <= {sync_button[0],button}; pressed <= 0;
            if (sync_button[1] == stable) count <= 0;
            else if (count >= DEBOUNCING_TIME-1) begin
                stable <= sync_button[1]; count <= 0;
                if (sync_button[1]) pressed <= 1;
            end else count <= count+1;
        end
    end
endmodule
