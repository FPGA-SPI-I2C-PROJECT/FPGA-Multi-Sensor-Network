`timescale 1ns / 1ps

module bin2ascii (
    input  wire [8:0] bin_val,   // 9비트 센서 입력 (0 ~ 511)
    output wire [7:0] ascii_hun, // 100의 자리 ASCII ('0'~'9')
    output wire [7:0] ascii_ten, // 10의 자리 ASCII ('0'~'9')
    output wire [7:0] ascii_one  // 1의 자리 ASCII ('0'~'9')
);

    wire [3:0] d_hun = (bin_val / 100) % 10;
    wire [3:0] d_ten = (bin_val / 10) % 10;
    wire [3:0] d_one = bin_val % 10;

    // 숫자 0~9에 8'h30('0')을 더해 ASCII 문자로 변환
    assign ascii_hun = {4'h3, d_hun}; // 8'h30 + d_hun과 동일
    assign ascii_ten = {4'h3, d_ten};
    assign ascii_one = {4'h3, d_one};

endmodule