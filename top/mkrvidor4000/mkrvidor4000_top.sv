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

// signal declaration
wire OSC_CLK;

// internal oscillator
cyclone10lp_oscillator osc ( 
    .clkout(OSC_CLK),
    .oscena(1'b1)
);

mem_pll mem_pll (
    .inclk0(CLK_48MHZ),
    .c0(SDRAM_CLK)
);

wire clk_pixel_x5;
wire clk_pixel;
hdmi_pll hdmi_pll(.inclk0(CLK_48MHZ), .c0(clk_pixel), .c1(clk_pixel_x5));

logic [23:0] rgb;
logic [9:0] cx, cy, screen_start_x, screen_start_y;
hdmi #(.VIDEO_ID_CODE(1), .DDRIO(1), .DVI_OUTPUT(1)) hdmi(.clk_pixel_x10(clk_pixel_x5), .clk_pixel(clk_pixel), .rgb(rgb), .tmds_p(HDMI_TX), .tmds_clock_p(HDMI_CLK), .tmds_n(HDMI_TX_N), .tmds_clock_n(HDMI_CLK_N), .cx(cx), .cy(cy), .screen_start_x(screen_start_x), .screen_start_y(screen_start_y));

logic [1:0] command = 2'd0;
logic [21:0] data_address = 22'd0;
logic [15:0] data_write = 16'd0;
logic [15:0] data_read;
logic data_read_valid;
logic data_write_done;

as4c4m16sa #(.CLK_RATE(143000000), .WRITE_BURST(0), .READ_BURST_LENGTH(8)) as4c4m16sa (
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

logic [15:0] buffer [31:0];
logic [4:0] producer = 5'd0;
logic [4:0] consumer = 5'd0;
logic [4:0] diff;
assign diff = producer >= consumer ? (producer - consumer) : ~(consumer - producer);

logic no_more_writes = 1'd0;
logic [2:0] read_countdown = 3'd0;
always @(posedge SDRAM_CLK)
begin
  if (command == 2'd0 && !no_more_writes)
  begin
    command <= 2'd1;
  end
  else if (command == 2'd1 && data_write_done)
  begin
    command <= 2'd0;
    data_address <= data_address + 1'd1 == 22'd307200 ? 22'd0 : data_address + 1'd1;
    if (data_address == 22'd307200 - 1'd1)
    begin
      no_more_writes <= 1'b1;
      data_write <= 16'd0;
    end
    else
      data_write <= data_write + 1'd1;
  end
  else if (command == 2'd2 && data_read_valid)
  begin
    if (read_countdown == 3'd0)
    begin
      command <= 2'd0;
    end
    else
    begin
      producer <= producer + 1'd1;
      buffer[producer] <= data_read;
      read_countdown <= read_countdown - 1'd1;
      data_address <= data_address + 1'd1 == 22'd307200 ? 22'd0 : data_address + 1'd1;
    end
  end
  else if (command == 2'd0 && no_more_writes && diff < 5'd20)
  begin
    command <= 2'd2;
    read_countdown <= 3'd7;
  end
end

always @(posedge clk_pixel)
begin
  if (cx >= screen_start_x && cy >= screen_start_y)
  begin
    // rgb <= {6'(cy-screen_start_y), (cx - screen_start_x), 8'd0};
    if (consumer != producer)
    begin
      consumer <= consumer + 1'd1;
      rgb <= {buffer[consumer], 8'd0};
    end
    else
      rgb <= 24'h0000ff;
  end
end

// logic [7:0] codepoints [0:3];
// always @(posedge SDRAM_CLK) codepoints <= '{state + 8'h30, producer + 8'h30, diff + 8'h30, no_more_writes + 8'h30};//'{image_data[1][7:4] + 8'h30, image_data[1][7:4] + 8'h30, image_data[0][7:4] + 8'h30, image_data[0][3:0] + 8'h30};

// logic [1:0] codepoint_counter = 2'd0;
// logic [5:0] prevcy = 6'd0;
// always @(posedge clk_pixel)
// begin
//     if (cy == 10'd0)
//     begin
//         prevcy <= 6'd0;
//     end
//     else if (prevcy != cy[9:4])
//     begin
//         codepoint_counter <= codepoint_counter + 1'd1;
//         prevcy <= cy[9:4];
//     end
// end

// console console(.clk_pixel(clk_pixel), .codepoint(codepoints[codepoint_counter]), .attribute({cx[9], cy[8:6], cx[8:5]}), .cx(cx), .cy(cy), .rgb(rgb));

endmodule
