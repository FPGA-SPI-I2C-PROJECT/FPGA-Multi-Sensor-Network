`timescale 1ns / 1ps

module tb_top_slave;

    // --- 시간 파라미터 ---
    localparam CLK_PERIOD = 10;          // 100MHz (10ns)
    localparam BIT_PERIOD = 104_167;     // 9600 BPS 1비트 주기 (~104.167 us)

    // --- DUT 신호 선언 ---
    reg         clk;
    reg         reset;
    reg         echo;
    reg         RsRx;

    wire        trig;
    wire        RsTx;
    wire [15:0] led;
    wire        dht11_data;

    wire        test_uart_rx;
    wire        test_uart_tx;

    // DHT11 양방향 버스 모델링용 레지스터
    reg         dht_drive_en;
    reg         dht_drive_val;
    assign dht11_data = (dht_drive_en) ? dht_drive_val : 1'bz;

    // --- DUT 인스턴스화 ---
    top_slave uut (
        .clk(clk),
        .reset(reset),
        .echo(echo),
        .RsRx(RsRx),
        .trig(trig),
        .RsTx(RsTx),
        .led(led),
        .dht11_data(dht11_data),
        .test_uart_rx(test_uart_rx),
        .test_uart_tx(test_uart_tx)
    );

    // --- 100MHz 클럭 생성 ---
    always #(CLK_PERIOD / 2) clk = ~clk;

    // --- UART 바이트 전송 Task (PC -> top_slave) ---
    task send_uart_byte(input [7:0] data);
        integer i;
        begin
            RsRx = 1'b0; // Start Bit
            #(BIT_PERIOD);
            for (i = 0; i < 8; i = i + 1) begin
                RsRx = data[i]; // LSB first
                #(BIT_PERIOD);
            end
            RsRx = 1'b1; // Stop Bit
            #(BIT_PERIOD);
            #(BIT_PERIOD * 2); // 여유 갭
        end
    endtask

    // --- 초음파 Echo 응답 에뮬레이션 Task ---
    // trig 신호의 상승 에지를 감지하면 일정 시간 High 펄스를 생성하여 거리 전달
    task emulate_ultrasonic_echo(input integer pulse_us);
        begin
            @(posedge trig);
            #1000; // 센서 내부 처리 딜레이
            echo = 1'b1;
            #(pulse_us * 1000); // us 단위 펄스 폭 (1us = 1000ns)
            echo = 1'b0;
        end
    endtask
// 초음파 Echo 응답 백그라운드 프로세스 (표준 Verilog 지원)
    initial begin
        // 리셋 해제 대기
        wait(reset == 1'b0);
        
        // 트리거 신호 감지 시 Echo 펄스 회신
        emulate_ultrasonic_echo(500);
    end
    // --- 시뮬레이션 시나리오 ---
    initial begin
        // 초기화
        clk           = 1'b0;
        reset         = 1'b1;
        echo          = 1'b0;
        RsRx          = 1'b1; // UART Idle = High
        dht_drive_en  = 1'b0;
        dht_drive_val = 1'b1;

        // 리셋 해제
        #(CLK_PERIOD * 20);
        reset = 1'b0;
        #(CLK_PERIOD * 10);

        $display("=== [TOP Module Simulation] Start ===");


        // 센서 데이터 갱신 및 FSM 안정화를 위한 대기
        #(BIT_PERIOD * 2);

        // 2. UART 테스트: 온도 요청 ('T')
        $display("[Time: %0t] Sending UART Command: 'T'", $time);
        send_uart_byte("T");
        #(BIT_PERIOD * 12); // DUT에서 1바이트 회신 완료될 때까지 대기

        // 3. UART 테스트: 습도 요청 ('H')
        $display("[Time: %0t] Sending UART Command: 'H'", $time);
        send_uart_byte("H");
        #(BIT_PERIOD * 12);

        // 4. UART 테스트: 거리 요청 ('D')
        $display("[Time: %0t] Sending UART Command: 'D'", $time);
        send_uart_byte("D");
        #(BIT_PERIOD * 12);

        // 5. 예외 처리: 지원하지 않는 명령 전송 ('Z')
        $display("[Time: %0t] Sending Invalid UART Command: 'Z'", $time);
        send_uart_byte("Z");
        #(BIT_PERIOD * 5);

        $display("=== [TOP Module Simulation] Finished ===");
        $finish;
    end

endmodule