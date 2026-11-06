`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/11/03 18:51:05
// Design Name: 
// Module Name: tb_ultrasonic_sensor
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1ns / 1ps

module tb_ultrasonic_sensor();

    // 1. 입출력 신호 선언
    reg        clk;
    reg        reset;
    reg        start_trig;
    wire       trig;
    reg        echo;
    wire [8:0] distance;
    wire       done;

    // 2. 클록 주기 설정 (100MHz = 10ns)
    localparam CLK_PERIOD = 10;
    always #(CLK_PERIOD / 2) clk = ~clk;

    // 3. DUT(Device Under Test) 인스턴스화
    ultrasonic_sensor uut (
        .clk        (clk),
        .reset      (reset),
        .start_trig (start_trig),
        .trig       (trig),
        .echo       (echo),
        .distance   (distance),
        .done       (done)
    );

    // =========================================================================
    // 센서 응답 모사 태스크 (HC-SR04 동작 에뮬레이션)
    // - Trig 핀이 10us High 후 Low로 떨어질 때까지 대기
    // - 센서 내부 발진 지연 대기 (약 450us)
    // - 목표 거리(cm) * 58us 동안 Echo를 High로 인가
    // =========================================================================
    task send_echo_task(input [8:0] target_cm);
        integer echo_duration_us;
        begin
            echo_duration_us = target_cm * 58;

            // 1. Trig가 1로 올라갈 때까지 대기
            wait(trig == 1'b1);
            $display("[SENSOR MODEL] Trig pulse detected (High)!");

            // 2. Trig가 0으로 완전히 떨어질 때까지 대기 (10us 통과 확인)
            wait(trig == 1'b0);
            $display("[SENSOR MODEL] Trig pulse ended (Low)! Generating Echo for %0d cm...", target_cm);

            // 3. 초음파 발진 및 반사 지연 모사 (450us 대기)
            #450_000;

            // 4. Echo 펄스 인가
            echo = 1'b1;
            #(echo_duration_us * 1000); // target_cm * 58us
            echo = 1'b0;

            // 5. 측정 완료 신호 대기
            wait(done == 1'b1);
            $display("[RESULT] Expected: %0d cm | Measured distance: %0d cm", target_cm, distance);
            
            #100_000; // 100us 대기 후 다음 테스트로 이동
        end
    endtask

    // =========================================================================
    // 메인 시뮬레이션 시나리오
    // =========================================================================
    initial begin
        // 초기화
        clk        = 1'b0;
        reset      = 1'b1;
        start_trig = 1'b0;
        echo       = 1'b0;

        // 리셋 해제 (100ns 대기)
        #100;
        reset = 1'b0;
        #1_000; // 1us 대기

        // -----------------------------------------------------------------
        // 시나리오 1: 15cm 거리 측정
        // -----------------------------------------------------------------
        $display("--------------------------------------------------");
        $display("[TEST 1] Triggering measurement for 15 cm...");
        
        // 주의: 현재 모듈은 tick(1us) 주기로 start_trig를 샘플링하므로
        // 안전하게 2us(2000ns) 동안 start_trig를 유지합니다.
        @(posedge clk);
        start_trig = 1'b1;
        #2000;
        start_trig = 1'b0;

        // 센서 응답 실행
        send_echo_task(9'd15);

        // -----------------------------------------------------------------
        // 시나리오 2: 50cm 거리 측정
        // -----------------------------------------------------------------
        $display("--------------------------------------------------");
        $display("[TEST 2] Triggering measurement for 50 cm...");
        
        @(posedge clk);
        start_trig = 1'b1;
        #2000;
        start_trig = 1'b0;

        send_echo_task(9'd50);

        // -----------------------------------------------------------------
        // 시나리오 3: 100cm 거리 측정
        // -----------------------------------------------------------------
        $display("--------------------------------------------------");
        $display("[TEST 3] Triggering measurement for 100 cm...");
        
        @(posedge clk);
        start_trig = 1'b1;
        #2000;
        start_trig = 1'b0;

        send_echo_task(9'd100);

        // -----------------------------------------------------------------
        // 시나리오 4: 타임아웃 검증 (Echo가 전혀 오지 않는 장애물 없음/단선 상황)
        // -----------------------------------------------------------------
        $display("--------------------------------------------------");
        $display("[TEST 4] Timeout Test (No Echo response)...");
        
        @(posedge clk);
        start_trig = 1'b1;
        #2000;
        start_trig = 1'b0;

        // Echo를 주지 않고 WAIT_HIGH 타임아웃(10ms) 발생 대기
        @(posedge done);
        $display("[RESULT] Timeout handled successfully! (done=%b, distance=%0d)", done, distance);

        #1_000_000; // 1ms 대기 후 시뮬레이션 종료
        $display("--------------------------------------------------");
        $display("All test scenarios completed!");
        $finish;
    end

endmodule
