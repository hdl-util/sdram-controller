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

wire clk_pixel_x5;
// assign SDRAM_CLK = clk_pixel_x5;
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

localparam WRITE_BURST = 1;
localparam READ_BURST_LENGTH = 1;
as4c4m16sa_controller #(.CLK_RATE(100000000), .WRITE_BURST(WRITE_BURST), .READ_BURST_LENGTH(READ_BURST_LENGTH), .CAS_LATENCY(2)) as4c4m16sa_controller (
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
logic errored = 1'd0;

// always @(posedge SDRAM_CLK)
// begin
//   if (command == 2'd0)
//   begin
//     if (!errored)
//     begin
//       command <= 2'd1;
//       countdown <= WRITE_BURST ? 3'(READ_BURST_LENGTH - 1) : 3'd0;
//       codepoints <= '{8'd2, 8'd2, 8'd2, 8'd2, 8'd2, 8'd2, 8'd2, 8'd2, 8'h47, 8'h4f, 8'h4f, 8'h44, 8'd1, 8'd1, 8'd1, 8'd1};
//     end
//   end
//   else if (command == 2'd1 && data_write_done)
//   begin
//     data_write <= data_write + 1'd1;
//     if (countdown == 3'd0)
//     begin
//       command <= 2'd2;
//       countdown <= 3'(READ_BURST_LENGTH - 1);
//     end
//     else
//       countdown <= countdown - 1'd1;
//   end
//   else if (command == 2'd2 && data_read_valid)
//   begin
//     if (countdown == 3'd0)
//     begin
//       data_address <= data_address + READ_BURST_LENGTH;
//       command <= 2'd0;
//     end
//     else
//       countdown <= countdown - 1'd1;
//     if (!errored && data_read != (data_address[15:0] + 3'(READ_BURST_LENGTH - 1) - countdown))
//     begin
//       codepoints <= '{8'h30 + countdown, 8'h30 + data_address[21:20], 8'h30 + data_address[19:16], 8'h30 + data_address[15:12], 8'h30 + data_address[11:8], 8'h30 + data_address[7:4], 8'h30 + data_address[3:0] + (3'(READ_BURST_LENGTH - 1) - countdown), 8'd61, 8'h30 + data_read[15:12], 8'h30 + data_read[11:8], 8'h30 + data_read[7:4], 8'h30 + data_read[3:0], 8'h30 + data_address[15:12], 8'h30 + data_address[11:8], 8'h30 + data_address[7:4], 8'h30 + data_address[3:0] + (3'(READ_BURST_LENGTH-1) - countdown)};
//       errored <= 1'b1;
//     end
//   end
// end

always @(posedge SDRAM_CLK)
begin
  if (command == 2'd0 && !no_more_writes)
  begin
    command <= 2'd1;
    countdown <= WRITE_BURST ? 8'(READ_BURST_LENGTH - 1) : 8'd0;
  end
  else if (command == 2'd1 && data_write_done)
  begin
    if (countdown == 3'd0)
      command <= 2'd0;
    else
      countdown <= countdown - 1'd1;

    data_address <= data_address == 22'h3_fff_ff ? 22'd0 : data_address + 1'd1;
    data_write <= data_address[15:0] + 1'd1;
    if (data_address == 22'h3_fff_ff)
      no_more_writes <= 1'b1;
  end
  else if (command == 2'd2 && data_read_valid)
  begin
    if (countdown == 3'd0)
      command <= 2'd0;
    else
      countdown <= countdown - 1'd1;

    data_address <= data_address == 22'h3_fff_ff ? 22'd0 : data_address + 1'd1;
    if (!errored && data_read != data_address[15:0])
    begin
      codepoints <= '{8'd2, 8'h30 + data_address[21:20], 8'h30 + data_address[19:16], 8'h30 + data_address[15:12], 8'h30 + data_address[11:8], 8'h30 + data_address[7:4], 8'h30 + data_address[3:0], 8'd61, 8'h30 + data_read[15:12], 8'h30 + data_read[11:8], 8'h30 + data_read[7:4], 8'h30 + data_read[3:0], 8'h30 + data_write[15:12], 8'h30 + data_write[11:8], 8'h30 + data_write[7:4], 8'h30 + data_write[3:0]};
      errored <= 1'b1;
    end
  end
  else if (command == 2'd0 && no_more_writes && !errored)
  begin
    if (data_address[2:0] % READ_BURST_LENGTH != 3'd0) // Will be subject to sequential ordering effects from Table 8, this makes the test fail because the ordering isn't handled
    begin
      codepoints <= '{8'd127, 8'd127, 8'd127, 8'd127, 8'd127, 8'd127, 8'd127, 8'd127, 8'd127, 8'd127, 8'd127, 8'd127, 8'd127, 8'd127, 8'd127, 8'd127};
      errored <= 1'b1;
    end
    else
    begin
      command <= 2'd2;
      countdown <= 8'(READ_BURST_LENGTH - 1);
    end
  end
end


logic [7:0] codepoints [0:15] = '{8'd2, 8'd2, 8'd2, 8'd2, 8'd2, 8'd2, 8'd2, 8'd2, 8'h47, 8'h4f, 8'h4f, 8'h44, 8'd1, 8'd1, 8'd1, 8'd1};

logic [3:0] codepoint_counter = 4'd0;
logic [5:0] prevcy = 6'd0;
always @(posedge clk_pixel)
begin
    if (cy == 10'd0)
    begin
        prevcy <= 6'd0;
    end
    else if (prevcy != cy[9:4])
    begin
        codepoint_counter <= codepoint_counter + 1'd1;
        prevcy <= cy[9:4];
    end
end

console console(.clk_pixel(clk_pixel), .codepoint(codepoints[codepoint_counter]), .attribute({cx[9], cy[8:6], cx[8:5]}), .cx(cx), .cy(cy), .rgb(rgb));

endmodule
