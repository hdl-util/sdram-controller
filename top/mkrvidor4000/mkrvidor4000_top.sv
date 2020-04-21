module mkrvidor4000_top
(
  // system signals
  input logic CLK_48MHZ,
  input logic RESETn,
  input logic SAM_INT_IN,
  output logic SAM_INT_OUT,
  
  // SDRAM
  output logic SDRAM_CLK,
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

wire [31:0] JTAG_ADDRESS, JTAG_READ_DATA, JTAG_WRITE_DATA, DPRAM_READ_DATA;
wire JTAG_READ, JTAG_WRITE, JTAG_WAIT_REQUEST, JTAG_READ_DATAVALID;
wire [4:0] JTAG_BURST_COUNT;
wire DPRAM_CS;

wire [7:0] DVI_RED,DVI_GRN,DVI_BLU;
wire DVI_HS, DVI_VS, DVI_DE;

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
wire clk_audio;
hdmi_pll hdmi_pll(.inclk0(CLK_48MHZ), .c0(clk_pixel), .c1(clk_pixel_x5), .c2(clk_audio));

localparam AUDIO_BIT_WIDTH = 16;
localparam AUDIO_RATE = 48000;
localparam WAVE_RATE = 480;

logic [AUDIO_BIT_WIDTH-1:0] audio_sample_word;
// sawtooth #(.BIT_WIDTH(AUDIO_BIT_WIDTH), .SAMPLE_RATE(AUDIO_RATE), .WAVE_RATE(WAVE_RATE)) sawtooth (.clk_audio(clk_audio), .level(audio_sample_word));

logic [23:0] rgb;
logic [9:0] cx, cy, screen_start_x, screen_start_y;
hdmi #(.VIDEO_ID_CODE(1), .DDRIO(1), .AUDIO_RATE(AUDIO_RATE), .AUDIO_BIT_WIDTH(AUDIO_BIT_WIDTH)) hdmi(.clk_pixel_x10(clk_pixel_x5), .clk_pixel(clk_pixel), .clk_audio(clk_audio), .rgb(rgb), .audio_sample_word('{audio_sample_word, audio_sample_word}), .tmds_p(HDMI_TX), .tmds_clock_p(HDMI_CLK), .tmds_n(HDMI_TX_N), .tmds_clock_n(HDMI_CLK_N), .cx(cx), .cy(cy), .screen_start_x(screen_start_x), .screen_start_y(screen_start_y));

logic [1:0] command = 2'd0;
logic [21:0] data_address = {2'b00, 20'hCAFEE};
logic [15:0] data_write = 16'hFACE;
logic [15:0] data_read;
logic data_ready;
logic data_next;

as4c4m16sa as4c4m16sa (
  .clk(SDRAM_CLK),
  .command(command),
  .data_address(data_address),
  .data_write(data_write),
  .data_read(data_read),
  .data_ready(data_ready),
  .data_next(data_next),
  .cke(SDRAM_CKE),
  .ba(SDRAM_BA),
  .a(SDRAM_ADDR),
  .cs(SDRAM_CSn),
  .ras(SDRAM_RASn),
  .cas(SDRAM_CASn),
  .we(SDRAM_WEn),
  .dqm(SDRAM_DQM),
  .dq(SDRAM_DQ)
);

logic [1:0] state = 2'd0;
logic [7:0] codepoints [0:3] = '{8'h2a, 8'h2a, 8'h2a, 8'h2a};
always @(posedge SDRAM_CLK)
begin
  if (state == 2'd0)
  begin
    command <= 2'd1;
    state <= 2'd1;
    codepoints[0] <= 8'h23;
  end
  else if (state == 2'd1 && data_next)
  begin
    command <= 2'd2;
    state <= 2'd2;
    codepoints[0] <= 8'h24;
  end
  else if (state == 2'd2 && data_ready)
  begin
    command <= 2'd0;
    codepoints <= '{data_read[15:12] + 8'h30, data_read[11:8] + 8'h30, data_read[7:4] + 8'h30, data_read[3:0] + 8'h30};
  end
end


logic [1:0] counter = 2'd0;
logic [5:0] prevcy = 6'd0;
always @(posedge clk_pixel)
begin
    if (cy == 10'd0)
    begin
        prevcy <= 6'd0;
    end
    else if (prevcy != cy[9:4])
    begin
        counter <= counter + 1'd1;
        prevcy <= cy[9:4];
    end
end

console console(.clk_pixel(clk_pixel), .codepoint(codepoints[counter]), .attribute({cx[9], cy[8:6], cx[8:5]}), .cx(cx), .cy(cy), .rgb(rgb));

endmodule
