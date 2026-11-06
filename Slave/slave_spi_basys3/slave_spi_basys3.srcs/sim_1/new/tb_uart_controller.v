`timescale 1ns / 1ps

module tb_uart_controller();

    // 1. 클록 및 신호 정의
    reg clk;
    reg reset;
    reg rx;

    reg [7:0] reg_temp;
    reg [7:0] reg_humi;
    reg [8:0] reg_dist;

    wire tx;

    // 100MHz 클록: 주기 10ns
    parameter CLK_PERIOD = 10;
    
    // 9600 bps 기준 1비트 전송 시간: 1 / 9600 = 104,166.6ns
    parameter BIT_PERIOD = 104_167;

    // 2. DUT(Device Under Test) 인스턴스화
    uart_controller uut (
        .clk(clk),
        .reset(reset),
        .rx(rx),
        .reg_temp(reg_temp),
        .reg_humi(reg_humi),
        .reg_dist(reg_dist),
        .tx(tx)
    );

    // 3. 100MHz 시스템 클록 생성
    always #(CLK_PERIOD / 2) clk = ~clk;

    // 4. PC에서 UART RX로 1바이트를 보내는 태스크 (9600 bps 타이밍 준수)
    task send_uart_byte(input [7:0] data);
        integer i;
        begin
            // Start Bit (0)
            rx = 1'b0;
            #(BIT_PERIOD);

            // Data Bits (LSB First)
            for (i = 0; i < 8; i = i + 1) begin
                rx = data[i];
                #(BIT_PERIOD);
            end

            // Stop Bit (1)
            rx = 1'b1;
            #(BIT_PERIOD);
        end
    endtask

    // 5. 테스트 시나리오
    initial begin
        // 초기화
        clk = 0;
        reset = 1;
        rx = 1; // UART Idle 상태는 High

        // 가상의 센서 측정값 설정
        reg_temp = 8'd25;   // 25℃  -> ASCII 기대값: "0", "2", "5", \r, \n
        reg_humi = 8'd64;   // 64%   -> ASCII 기대값: "0", "6", "4", \r, \n
        reg_dist = 9'd182;  // 182cm -> ASCII 기대값: "1", "8", "2", \r, \n

        // 리셋 해제
        #(CLK_PERIOD * 10);
        reset = 0;
        #(BIT_PERIOD * 2);

        // --------------------------------------------------
        // Case 1: 't' (온도 요청) 송신
        // --------------------------------------------------
        $display("[%0t ns] Sending Command: 't'", $time);
        send_uart_byte("t");
        
        // 5바이트("025\r\n") 전송 완료 대기: 5바이트 * 약 1.04ms = 약 5.2ms
        #(BIT_PERIOD * 60);

        // --------------------------------------------------
        // Case 2: 'h' (습도 요청) 송신
        // --------------------------------------------------
        $display("[%0t ns] Sending Command: 'h'", $time);
        send_uart_byte("h");
        #(BIT_PERIOD * 60);

        // --------------------------------------------------
        // Case 3: 'd' (초음파 거리 요청) 송신
        // --------------------------------------------------
        $display("[%0t ns] Sending Command: 'd'", $time);
        send_uart_byte("d");
        #(BIT_PERIOD * 60);

        $display("[%0t ns] Simulation Finished Successfully", $time);
        $finish;
    end

endmodule