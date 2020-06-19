module mkrvidor4000_top
(
  // system signals
  input logic CLK_48MHZ,
  input logic RESETn,
  input logic SAM_INT_IN,
  output logic SAM_INT_OUT,
  
  // SDRAM
  output wire SDRAM_CLK,
  output logic [11:0] SDRAM_ADDR,
  output logic [1:0] SDRAM_BA,
  output logic SDRAM_CASn,
  output logic SDRAM_CKE,
  output logic SDRAM_CSn,
  inout wire [15:0] SDRAM_DQ,
  output logic [1:0] SDRAM_DQM,
  output logic SDRAM_RASn,
  output logic SDRAM_WEn,

  // HDMI output
  output logic [2:0] HDMI_TX,
  output logic [2:0] HDMI_TX_N,
  output logic HDMI_CLK,
  output logic HDMI_CLK_N,
  inout wire HDMI_SDA,
  inout wire HDMI_SCL,
  input logic HDMI_HPD
);

wire OSC_CLK;

// internal oscillator
cyclone10lp_oscillator osc ( 
    .clkout(OSC_CLK),
    .oscena(1'b1)
);

mem_pll mem_pll(.inclk0(CLK_48MHZ), .c0(SDRAM_CLK));

wire clk_pixel_x5, clk_pixel;
hdmi_pll hdmi_pll(.inclk0(CLK_48MHZ), .c0(clk_pixel), .c1(clk_pixel_x5));

logic [23:0] rgb;
logic [9:0] cx, cy, screen_start_x, screen_start_y, frame_width, frame_height, screen_width, screen_height;
hdmi #(.VIDEO_ID_CODE(1), .DDRIO(1), .DVI_OUTPUT(1)) hdmi(
  .clk_pixel_x10(clk_pixel_x5),
  .clk_pixel(clk_pixel),
  .rgb(rgb),
  .tmds_p(HDMI_TX),
  .tmds_clock_p(HDMI_CLK),
  .tmds_n(HDMI_TX_N),
  .tmds_clock_n(HDMI_CLK_N),
  .cx(cx),
  .cy(cy),
  .screen_start_x(screen_start_x),
  .screen_start_y(screen_start_y),
  .frame_width(frame_width),
  .frame_height(frame_height),
  .screen_width(screen_width),
  .screen_height(screen_height)
);

logic [15:0] countup = 16'd0;


logic first_data_ready = 1'b0;
logic first_data_ready_acknowledged = 1'b0;


logic [15:0] pixel_data_in, pixel_data_out;
logic pixel_data_in_enable, pixel_data_out_acknowledge;
logic [4:0] pixel_in_used;
fifo #(.DATA_WIDTH(16), .POINTER_WIDTH(5)) pixel_read_fifo(
    .sender_clock(SDRAM_CLK),
    .data_in_enable(pixel_data_in_enable),
    .data_in_used(pixel_in_used),
    .data_in(pixel_data_in),
    .receiver_clock(clk_pixel),
    .data_out_used(),
    .data_out_acknowledge(pixel_data_out_acknowledge),
    .data_out(pixel_data_out)
);

assign pixel_data_out_acknowledge = cx >= screen_start_x && cy >= screen_start_y && first_data_ready_acknowledged;

always @(posedge clk_pixel)
begin
  if (first_data_ready && cy < screen_start_y)
    first_data_ready_acknowledged <= 1'b1;

  if (cx == 10'd0 && cy == 10'd0)
    countup <= 16'd0;
  else if (cx >= screen_start_x && cy >= screen_start_y && first_data_ready_acknowledged)
    countup <= countup + 1'd1;
  // rgb <= {countup, 8'd0};
  rgb <= {pixel_data_out, {8{countup != pixel_data_out}}};
  // rgb <= {cy < 10'd120 + screen_start_y ? 16'hff00 : cy < 10'd240 + screen_start_y ? 16'h00ff : cy < 10'd360 + screen_start_y ? 16'haa55 : cy < 10'd480 + screen_start_y ? 16'hffff : 16'haa00, 8'd0};
end

logic [1:0] command = 2'd0;
logic [21:0] data_address = 22'd0;
logic [15:0] data_write = 16'd0, data_read;
logic data_read_valid, data_write_done;

localparam WRITE_BURST = 1;
localparam READ_BURST_LENGTH = 8;
as4c4m16sa_controller #(.CLK_RATE(140000000), .WRITE_BURST(WRITE_BURST), .READ_BURST_LENGTH(READ_BURST_LENGTH), .CAS_LATENCY(3)) as4c4m16sa_controller (
	.clk(SDRAM_CLK),
  .command(command),
  .data_address(data_address),
  .data_write(data_write),
  .data_read(data_read),
  .data_read_valid(data_read_valid),
  .data_write_done(data_write_done),
  .clock_enable(SDRAM_CKE),
  .bank_activate(SDRAM_BA),
  .address(SDRAM_ADDR),
  .chip_select(SDRAM_CSn),
  .row_address_strobe(SDRAM_RASn),
  .column_address_strobe(SDRAM_CASn),
  .write_enable(SDRAM_WEn),
  .dqm(SDRAM_DQM),
  .dq(SDRAM_DQ)
);

logic no_more_writes = 1'd0;
logic [7:0] countdown = 3'd0;

assign pixel_data_in_enable = command == 2'd2 && data_read_valid;
assign pixel_data_in = data_read;

always @(posedge SDRAM_CLK)
begin
  if (command == 2'd0 && !no_more_writes)
  begin
    command <= 2'd1;
    countdown <= WRITE_BURST ? 8'(READ_BURST_LENGTH - 1) : 8'd0;
    data_write <= data_address[15:0];
  end
  else if (command == 2'd1 && data_write_done)
  begin
    if (countdown == 3'd0)
      command <= 2'd0;
    else
      countdown <= countdown - 1'd1;

    data_address <= data_address + 1'd1;
    data_write <= 16'(data_address + 1'd1);
    if (data_address + 1'd1 == 22'd0)
      no_more_writes <= 1'b1;
  end
  else if (command == 2'd2 && data_read_valid)
  begin
    if (countdown == 3'd0)
    begin
      command <= 2'd0;
      first_data_ready <= 1'b1;
    end
    else
      countdown <= countdown - 1'd1;

    data_address <= data_address == 22'(640 * 480 - 1) ? 22'd0 : data_address + 1'd1;
  end
  else if (command == 2'd0 && no_more_writes)
  begin
    if (pixel_in_used <= 5'(24 - READ_BURST_LENGTH))
    begin
      command <= 2'd2;
      countdown <= 8'(READ_BURST_LENGTH - 1);
    end
  end
end

endmodule
