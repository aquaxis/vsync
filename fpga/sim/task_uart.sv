`timescale 1ns / 1ps

module task_uart #(
    parameter rate = 115200
) (
    output reg  tx,
    input  wire rx
);

  reg clk, clk2;
  reg [7:0] rdata;

  initial begin
    clk  <= 1'b0;
    clk2 <= 1'b0;
    tx   <= 1'b1;
  end

  always begin
    #(1000000000 / rate / 2) clk <= ~clk;
  end

  task write;
    input [7:0] data;
    begin
      #1;
      tx <= 1'b1;
      #1;
      tx <= 1'b0;
      #(1000000000 / rate);
      tx <= data[0];
      #(1000000000 / rate);
      tx <= data[1];
      #(1000000000 / rate);
      tx <= data[2];
      #(1000000000 / rate);
      tx <= data[3];
      #(1000000000 / rate);
      tx <= data[4];
      #(1000000000 / rate);
      tx <= data[5];
      #(1000000000 / rate);
      tx <= data[6];
      #(1000000000 / rate);
      tx <= data[7];
      #(1000000000 / rate);
      tx <= 1'b1;
      #1;
    end
  endtask

  // Receive
  always begin
    #1;
    if (rx == 1'b0) begin
      #(1000000000 / rate);  // Startbit
      #(1000000000 / rate / 2);
      rdata[0] <= rx;
      #(1000000000 / rate);
      rdata[1] <= rx;
      #(1000000000 / rate);
      rdata[2] <= rx;
      #(1000000000 / rate);
      rdata[3] <= rx;
      #(1000000000 / rate);
      rdata[4] <= rx;
      #(1000000000 / rate);
      rdata[5] <= rx;
      #(1000000000 / rate);
      rdata[6] <= rx;
      #(1000000000 / rate);
      rdata[7] <= rx;
      #(1000000000 / rate / 2);
      while (!(rx == 1'b1)) #1;
      $write("%s", rdata[7:0]);
    end
  end

endmodule
