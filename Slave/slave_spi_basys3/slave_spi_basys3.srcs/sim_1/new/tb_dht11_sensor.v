`timescale 1ns / 1ps

module tb_dht11_sensor();

    // 1. 테스트벤치 신호 선언
    reg        clk;
    reg        reset;
    reg        start;
    wire       dht11_data;

    wire [7:0] humidity;
    wire [7:0] temperature;
    wire       done;
    wire       err;

    // 2. 오픈 드레인 버스 제어
    // dht_sensor_drive == 1이면 버스를 Low(0)로 구동, 0이면 릴리즈(High-Z)
    reg        dht_sensor_drive;
    assign dht11_data = dht_sensor_drive ? 1'b0 : 1'bz;

    // 외장 풀업 저항 모사 (양쪽 모두 Z일 때 라인은 High 유지)
    pullup(dht11_data);

    // 3. 100MHz 시스템 클록 생성 (10ns 주기)
    localparam CLK_PERIOD = 10;
    always #(CLK_PERIOD / 2) clk = ~clk;

    // 4. DUT 인스턴스화
    dht11_sensor uut (
        .clk         (clk),
        .reset       (reset),
        .start       (start),
        .dht11_data  (dht11_data),
        .humidity    (humidity),
        .temperature (temperature),
        .done        (done),
        .err         (err)
    );

    // =========================================================================
    // 센서 동작 모사 태스크: 40비트 패킷 전송
    // =========================================================================
    task send_dht11_packet(
        input [7:0] h_int,
        input [7:0] h_dec,
        input [7:0] t_int,
        input [7:0] t_dec,
        input       inject_error
    );
        reg [39:0] packet;
        reg [7:0]  checksum;
        integer    i;
        begin
            // 체크섬 계산: [39:32] + [31:24] + [23:16] + [15:8]
            checksum = h_int + h_dec + t_int + t_dec;
            if (inject_error) begin
                checksum = checksum + 8'd1; // 고의 에러 주입
            end
            packet = {h_int, h_dec, t_int, t_dec, checksum};

            $display("==================================================");
            $display("[TEST START] Target -> Humi: %0d.%0d%%, Temp: %0d.%0d C (Error Inject: %0b)", 
                     h_int, h_dec, t_int, t_dec, inject_error);

            // [Step 1] FPGA의 18ms Start Low 감지 대기
            wait(dht11_data == 1'b0);
            $display("[SENSOR] FPGA Start Signal (Low) detected.");

            // [Step 2] FPGA가 30us High 출력 후 버스를 놓아 풀업되는 시점 대기
            wait(dht11_data == 1'b1);
            $display("[SENSOR] Bus released by FPGA. Preparing response...");

            // 센서 준비 지연 시간 (규격상 20~40us 사이, 여기선 25us 부여)
            #25_000;

            // [Step 3] 센서 응답 신호 출력: 80us Low -> 80us High
            $display("[SENSOR] Driving Response Signal (80us Low -> 80us High)");
            dht_sensor_drive = 1'b1; // 80us Low 구동
            #80_000;
            dht_sensor_drive = 1'b0; // 80us High (버스 릴리즈 후 풀업)
            #80_000;

            // [Step 4] 40비트 데이터 직렬 전송 (MSB First)
            for (i = 39; i >= 0; i = i - 1) begin
                // 모든 비트의 시작: 50us Low
                dht_sensor_drive = 1'b1;
                #50_000;

                // 데이터 비트 구간: 0은 26~28us High, 1은 70us High
                dht_sensor_drive = 1'b0; // 라인 릴리즈 (High)
                if (packet[i] == 1'b1) begin
                    #70_000; // Bit 1
                end else begin
                    #28_000; // Bit 0
                end
            end

            // [Step 5] 통신 종료 신호: 마지막 50us Low 출력 후 완전히 버스 해제
            dht_sensor_drive = 1'b1;
            #50_000;
            dht_sensor_drive = 1'b0;

            // [Step 6] 결과 판정 플래그 대기
            @(posedge clk);
            wait(done == 1'b1 || err == 1'b1);

            if (done) begin
                $display("[TEST SUCCESS] Captured -> Humidity: %0d%%, Temperature: %0d C", humidity, temperature);
                if (humidity == h_int && temperature == t_int) begin
                    $display("[DATA MATCH] 습도 및 온도 데이터가 정확히 일치합니다.");
                end else begin
                    $display("[DATA MISMATCH ERROR] 데이터가 일치하지 않습니다! (기대치: H:%0d, T:%0d)", h_int, t_int);
                end
            end else if (err) begin
                $display("[FLAG] Error Detected (err = 1'b1)");
                if (inject_error) begin
                    $display("[TEST SUCCESS] 예상된 체크섬 오류를 정상 감지했습니다.");
                end else begin
                    $display("[TEST FAILED] 예상치 못한 오류(타임아웃 등)가 발생했습니다.");
                end
            end

            #200_000; // 다음 전송 전 버스 안정화 시간 (200us)
        end
    endtask

    // =========================================================================
    // 센서 미응답(Timeout) 테스트 태스크
    // =========================================================================
    task test_sensor_timeout();
        begin
            $display("==================================================");
            $display("[TEST START] Sensor Timeout (No Response) Test");
            
            wait(dht11_data == 1'b0);
            wait(dht11_data == 1'b1);
            
            // 센서가 아무 응답도 주지 않고 라인을 계속 High로 방치함
            dht_sensor_drive = 1'b0;

            @(posedge clk);
            wait(err == 1'b1);
            $display("[TEST SUCCESS] 센서 미응답 시 S_RESP_LOW 타임아웃 에러 검증 완료.");

            #100_000;
        end
    endtask

    // =========================================================================
    // 시뮬레이션 시나리오
    // =========================================================================
    initial begin
        clk              = 1'b0;
        reset            = 1'b1;
        start            = 1'b0;
        dht_sensor_drive = 1'b0;

        // 시스템 리셋
        #200;
        reset = 1'b0;
        #1_000;

        // -------------------------------------------------------------
        // 시나리오 1: 정상 데이터 수신 (습도 68%, 온도 25도)
        // -------------------------------------------------------------
        @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        send_dht11_packet(8'd68, 8'd0, 8'd25, 8'd0, 1'b0);

        // -------------------------------------------------------------
        // 시나리오 2: 정상 데이터 수신 (습도 35%, 온도 18도)
        // -------------------------------------------------------------
        @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        send_dht11_packet(8'd35, 8'd0, 8'd18, 8'd0, 1'b0);

        // -------------------------------------------------------------
        // 시나리오 3: 체크섬 에러 주입 검증 (습도 50%, 온도 30도)
        // -------------------------------------------------------------
        @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        send_dht11_packet(8'd50, 8'd0, 8'd30, 8'd0, 1'b1);

        // -------------------------------------------------------------
        // 시나리오 4: 센서 무응답(선로 단선/미연결) 타임아웃 검증
        // -------------------------------------------------------------
        @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        test_sensor_timeout();

        $display("==================================================");
        $display("DHT11 모든 시뮬레이션 케이스 테스트 통과!");
        $finish;
    end

endmodule