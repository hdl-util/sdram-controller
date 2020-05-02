module as4c4m16sa_controller #(
	// The minimum possible clock speed is 64.103 kHz, at which point the controller is saturated by auto refresh commands
	// The maximum possible clock speeds for each speed grade are: 7: 143 Mhz, 6: 166 MHz, 5: 200 Mhz
    parameter int CLK_RATE = 143000000,
	parameter int SPEED_GRADE = 7, // 7, 6, or 5
	parameter int READ_BURST_LENGTH = 1, // 1, 2, 4, 8, or 256 (full page)
	parameter int WRITE_BURST = 1, // 0 = Single write mode, 1 = Burst write mode (same length as read burst)
	parameter int CAS_LATENCY = 3 // 2 or 3

) (
	input logic clk,
	input logic [1:0] command,
	input logic [21:0] data_address,
	input logic [15:0] data_write,
	output logic [15:0] data_read,
	output logic data_read_valid,
	output logic data_write_done,

	// These ports should be connected directly to the SDRAM chip
	output logic clock_enable,
	output logic [1:0] bank_activate,
	output logic [11:0] address,
	output logic chip_select,
	output logic row_address_strobe,
	output logic column_address_strobe,
	output logic write_enable,
	output logic [1:0] dqm,
	inout wire [15:0] dq
);

localparam int MODE_REGISTER_SET_CYCLE_TIME = 2;
localparam real WRITE_RECOVERY_TIME = MODE_REGISTER_SET_CYCLE_TIME;

sdram_controller #(
	.CLK_RATE(CLK_RATE),
	.READ_BURST_LENGTH(READ_BURST_LENGTH),
	.WRITE_BURST(WRITE_BURST),
	.BANK_ADDRESS_WIDTH(2),
	.ROW_ADDRESS_WIDTH(12),
	.COLUMN_ADDRESS_WIDTH(8),
	.DATA_WIDTH(16),
	.DQM_WIDTH(2),
	.CAS_LATENCY(CAS_LATENCY),
	.ROW_CYCLE_TIME(SPEED_GRADE == 5 ? 55E-9 : SPEED_GRADE == 6 ? 60E-9 : 63E-9),
	.RAS_TO_CAS_DELAY(SPEED_GRADE == 5 ? 15E-9 : SPEED_GRADE == 6 ? 18E-9 : 21E-9),
	.PRECHARGE_TO_REFRESH_OR_ROW_ACTIVATE_SAME_BANK_TIME(SPEED_GRADE == 5 ? 15E-9 : SPEED_GRADE == 6 ? 18E-9 : 21E-9),
	.ROW_ACTIVATE_TO_ROW_ACTIVATE_DIFFERENT_BANK_TIME(SPEED_GRADE == 5 ? 10E-9 : SPEED_GRADE == 6 ? 12E-9 : 14E-9),
	.ROW_ACTIVATE_TO_PRECHARGE_SAME_BANK_TIME(SPEED_GRADE == 5 ? 40E-9 : SPEED_GRADE == 6 ? 42E-9 : 42E-9),
	.MINIMUM_STABLE_CONDITION_TIME(200E-6), // 200 us
	.MODE_REGISTER_SET_CYCLE_TIME(2.0 / CLK_RATE), // 2 clocks
	.WRITE_RECOVERY_TIME(2.0 / CLK_RATE), // 2 clocks
	.AVERAGE_REFRESH_INTERVAL_TIME(15.6E-6) // 15.6 us
) sdram_controller (
	.clk(clk),
    .command(command),
    .data_address(data_address),
    .data_write(data_write),
    .data_read(data_read),
    .data_read_valid(data_read_valid),
    .data_write_done(data_write_done),
    .clock_enable(clock_enable),
    .bank_activate(bank_activate),
    .address(address),
    .chip_select(chip_select),
    .row_address_strobe(row_address_strobe),
    .column_address_strobe(column_address_strobe),
    .write_enable(write_enable),
    .dqm(dqm),
    .dq(dq)
);

endmodule
