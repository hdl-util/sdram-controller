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

  // SAM D21 PINS
  inout wire MKR_AREF,
  inout wire [6:0] MKR_A,
  inout wire [14:0] MKR_D,
  
  // Mini PCIe
  inout wire PEX_RST,
  inout wire PEX_PIN6,
  inout wire PEX_PIN8,
  inout wire PEX_PIN10,
  input logic PEX_PIN11,
  inout wire PEX_PIN12,
  input logic PEX_PIN13,
  inout wire PEX_PIN14,
  inout wire PEX_PIN16,
  inout wire PEX_PIN20,
  input logic PEX_PIN23,
  input logic PEX_PIN25,
  inout wire PEX_PIN28,
  inout wire PEX_PIN30,
  input logic PEX_PIN31,
  inout wire PEX_PIN32,
  input logic PEX_PIN33,
  inout wire PEX_PIN42,
  inout wire PEX_PIN44,
  inout wire PEX_PIN45,
  inout wire PEX_PIN46,
  inout wire PEX_PIN47,
  inout wire PEX_PIN48,
  inout wire PEX_PIN49,
  inout wire PEX_PIN51,

  // NINA interface
  inout wire WM_PIO1,
  inout wire WM_PIO2,
  inout wire WM_PIO3,
  inout wire WM_PIO4,
  inout wire WM_PIO5,
  inout wire WM_PIO7,
  inout wire WM_PIO8,
  inout wire WM_PIO18,
  inout wire WM_PIO20,
  inout wire WM_PIO21,
  inout wire WM_PIO27,
  inout wire WM_PIO28,
  inout wire WM_PIO29,
  inout wire WM_PIO31,
  input logic WM_PIO32,
  inout wire WM_PIO34,
  inout wire WM_PIO35,
  inout wire WM_PIO36,
  input logic WM_TX,
  inout wire WM_RX,
  inout wire WM_RESET,

  // HDMI output
  output logic [2:0] HDMI_TX,
  output logic [2:0] HDMI_TX_N,
  output logic HDMI_CLK,
  output logic HDMI_CLK_N,
  inout wire HDMI_SDA,
  inout wire HDMI_SCL,
  
  input logic HDMI_HPD,
  
  // MIPI input
  input logic [1:0] MIPI_D,
//   input [1:0] MIPI_D_N,
  input logic MIPI_CLK,
//   input MIPI_CLK_N,
  inout wire MIPI_SDA,
  inout wire MIPI_SCL,
  inout wire [1:0] MIPI_GP,

  // Q-SPI Flash interface
  output logic FLASH_SCK,
  output logic FLASH_CS,
  inout wire FLASH_MOSI,
  inout wire FLASH_MISO,
  inout wire FLASH_HOLD,
  inout wire FLASH_WP

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

logic [15:0] pixel_buffer [0:31];
logic [4:0] pixel_consumer = 5'd0, gray_pixel_consumer = 5'd0;

logic first_data_ready = 1'b0;
logic first_data_ready_acknowledged = 1'b0;

always @(posedge clk_pixel)
begin
  if (first_data_ready && cy < screen_start_y)
    first_data_ready_acknowledged <= 1'b1;

  if (cx == 10'd0 && cy == 10'd0)
    countup <= 16'd0;
  else if (cx >= screen_start_x && cy >= screen_start_y && first_data_ready_acknowledged)
  begin
    countup <= countup + 1'd1;
    pixel_consumer <= pixel_consumer + 1'd1;
    unique case (pixel_consumer + 1'd1) // Balanced gray coding
      5'd0:  gray_pixel_consumer <= 5'b00000;
      5'd1:  gray_pixel_consumer <= 5'b10000;
      5'd2:  gray_pixel_consumer <= 5'b11000;
      5'd3:  gray_pixel_consumer <= 5'b11100;
      5'd4:  gray_pixel_consumer <= 5'b11110;
      5'd5:  gray_pixel_consumer <= 5'b11111;
      5'd6:  gray_pixel_consumer <= 5'b01111;
      5'd7:  gray_pixel_consumer <= 5'b01110;
      5'd8:  gray_pixel_consumer <= 5'b00110;
      5'd9:  gray_pixel_consumer <= 5'b00010;
      5'd10: gray_pixel_consumer <= 5'b00011;
      5'd11: gray_pixel_consumer <= 5'b01011;
      5'd12: gray_pixel_consumer <= 5'b01001;
      5'd13: gray_pixel_consumer <= 5'b00001;
      5'd14: gray_pixel_consumer <= 5'b00101;
      5'd15: gray_pixel_consumer <= 5'b00111;
      5'd16: gray_pixel_consumer <= 5'b10111;
      5'd17: gray_pixel_consumer <= 5'b10101;
      5'd18: gray_pixel_consumer <= 5'b10001;
      5'd19: gray_pixel_consumer <= 5'b11001;
      5'd20: gray_pixel_consumer <= 5'b11101;
      5'd21: gray_pixel_consumer <= 5'b01101;
      5'd22: gray_pixel_consumer <= 5'b01100;
      5'd23: gray_pixel_consumer <= 5'b01000;
      5'd24: gray_pixel_consumer <= 5'b01010;
      5'd25: gray_pixel_consumer <= 5'b11010;
      5'd26: gray_pixel_consumer <= 5'b11011;
      5'd27: gray_pixel_consumer <= 5'b10011;
      5'd28: gray_pixel_consumer <= 5'b10010;
      5'd29: gray_pixel_consumer <= 5'b10110;
      5'd30: gray_pixel_consumer <= 5'b10100;
      5'd31: gray_pixel_consumer <= 5'b00100;
    endcase
  end
  // rgb <= {countup, 8'd0};
  rgb <= {pixel_buffer[pixel_consumer], {8{countup != pixel_buffer[pixel_consumer]}}};
  // rgb <= {pixel_buffer[pixel_consumer], 8'd0};
  // rgb <= {cy < 10'd120 + screen_start_y ? 16'hff00 : cy < 10'd240 + screen_start_y ? 16'h00ff : cy < 10'd360 + screen_start_y ? 16'haa55 : cy < 10'd480 + screen_start_y ? 16'hffff : 16'haa00, 8'd0};
end

logic [4:0] captured_gray_pixel_consumer = 5'd0, degray_pixel_consumer = 5'd0;
always @(posedge SDRAM_CLK)
begin
  captured_gray_pixel_consumer <= gray_pixel_consumer;
  unique case (captured_gray_pixel_consumer)
    5'b00000: degray_pixel_consumer <= 5'd0;
    5'b10000: degray_pixel_consumer <= 5'd1;
    5'b11000: degray_pixel_consumer <= 5'd2;
    5'b11100: degray_pixel_consumer <= 5'd3;
    5'b11110: degray_pixel_consumer <= 5'd4;
    5'b11111: degray_pixel_consumer <= 5'd5;
    5'b01111: degray_pixel_consumer <= 5'd6;
    5'b01110: degray_pixel_consumer <= 5'd7;
    5'b00110: degray_pixel_consumer <= 5'd8;
    5'b00010: degray_pixel_consumer <= 5'd9;
    5'b00011: degray_pixel_consumer <= 5'd10;
    5'b01011: degray_pixel_consumer <= 5'd11;
    5'b01001: degray_pixel_consumer <= 5'd12;
    5'b00001: degray_pixel_consumer <= 5'd13;
    5'b00101: degray_pixel_consumer <= 5'd14;
    5'b00111: degray_pixel_consumer <= 5'd15;
    5'b10111: degray_pixel_consumer <= 5'd16;
    5'b10101: degray_pixel_consumer <= 5'd17;
    5'b10001: degray_pixel_consumer <= 5'd18;
    5'b11001: degray_pixel_consumer <= 5'd19;
    5'b11101: degray_pixel_consumer <= 5'd20;
    5'b01101: degray_pixel_consumer <= 5'd21;
    5'b01100: degray_pixel_consumer <= 5'd22;
    5'b01000: degray_pixel_consumer <= 5'd23;
    5'b01010: degray_pixel_consumer <= 5'd24;
    5'b11010: degray_pixel_consumer <= 5'd25;
    5'b11011: degray_pixel_consumer <= 5'd26;
    5'b10011: degray_pixel_consumer <= 5'd27;
    5'b10010: degray_pixel_consumer <= 5'd28;
    5'b10110: degray_pixel_consumer <= 5'd29;
    5'b10100: degray_pixel_consumer <= 5'd30;
    5'b00100: degray_pixel_consumer <= 5'd31;
  endcase
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

logic [4:0] pixel_producer = 5'd0, pixel_diff;

assign pixel_diff = pixel_producer >= degray_pixel_consumer ? (pixel_producer - degray_pixel_consumer) : ~(degray_pixel_consumer - pixel_producer);

logic no_more_writes = 1'd0;
logic [7:0] countdown = 3'd0;

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
    pixel_buffer[pixel_producer] <= data_read;
    pixel_producer <= pixel_producer + 1'd1;
  end
  else if (command == 2'd0 && no_more_writes)
  begin
    if (pixel_diff <= 5'(24 - READ_BURST_LENGTH))
    begin
      command <= 2'd2;
      countdown <= 8'(READ_BURST_LENGTH - 1);
    end
  end
end

endmodule
