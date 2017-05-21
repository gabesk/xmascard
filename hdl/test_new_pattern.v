`timescale 1ns / 1ps

//
// Validates that updating a pattern works according to design.
//


// In testing on the hardware, PuTTY was having trouble reliably sending and
// receiving the lowercase letter 'a'. Nothing else; the test data here worked
// fine. So this variation attempts to figure out why.
// Wait a random amount of time, then send 'a', repeatedly over and over. If the
// receiver ever receives something other than 'a' back, assert.

module test;

    // Inputs
    reg clk = 0;
    reg rx = 1; // RS-232 idle condition is logic high
    reg xmit = 0;
    reg recv = 0;
    reg [7:0] test_data [255:0];
    reg write_complete_received = 0;

    integer file;
    integer amt_read;
    integer i = 0;
    integer random_delay;
    reg [7:0] received_byte = 0;
    reg [7:0] test_vector [0:10];

    initial begin
        test_vector[0]  = "w";
        test_vector[1]  = 8'hAA; // addr

        test_vector[2]  = 8'h00;
        test_vector[3]  = 8'h01;
        test_vector[4]  = 8'h02;
        test_vector[5]  = 8'h03;

        test_vector[6]  = 8'h04;
        test_vector[7]  = 8'h05;
        test_vector[8]  = 8'h06;
        test_vector[9]  = 8'h07;
        test_vector[10] = 8'h08;
    end

    // Outputs
    wire tx;
    wire [23:0] leds;

    // Instantiate the Unit Under Test (UUT)
    lights uut (
        .clk(clk),
        .rx(rx),
        .tx(tx),
        .leds(leds)
    );

    always #20 clk = ~clk;

    //
    // The format is: "w" [ADDR] [DATA] where data is 72 bits (9 bytes). The
    // data is sent big-endian, in that the highest byte is sent first.
    // After sending this, expect to get "o" back.
    //

    // Transmission loop
    initial begin
        // Read test data
        file = $fopen("test_data.txt", "rb" );
        amt_read = $fread(test_data, file, 0, 256);

        // Wait 100 ns for global reset to finish and a little longer for good measure.
        #100;
        #1234;

        for (i=0; i<11; i=i+1) begin
            xmit_byte(test_vector[i]); // Send "a"
            // Wait random time
            random_delay = $random % 1000000; // Up to 1 ms
            #(random_delay);
        end

        #100000
        if (write_complete_received == 0)   $display("Test failed");
        else                                $display("Test passed");
        $stop;
    end
    
    // Receiver loop
    always begin
        recv_byte(received_byte);
        if (received_byte != "o") $stop;
        write_complete_received = 1;
    end

    task xmit_byte();
        input [7:0] b;
        integer i;
        begin
            #8681 rx = 0; xmit = 1; // start bit

            for (i=0;i<8;i = i+1) begin
                #8681 rx = b[0]; xmit = 0; // 0
                b = {1'b0, b[7:1]};
            end

            #8681 rx = 1; // stop bit
        end
    endtask
    
    task recv_byte();
        output [7:0] b;
        integer i;
        begin
            b = 0;
            @ (negedge tx); // Wait for start bit
            recv = 1;
            #4340;          // Wait half a bit period to align sampling to middle of transition.
            // 8 times, wait a bit period and then sample the value, shifting in from left to right.
            for (i=0;i<8;i = i+1) begin
                b = {1'b0, b[7:1]};
                #8681 b[7] = tx; recv = 0;
            end
            #4340;          // Wait another half a bit period to give the stop bit some time to occur.
        end
    endtask
    
endmodule

