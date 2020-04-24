module as4c4m16sa #(
	// The minimum possible clock speed is 64.103 kHz, at which point the controller is saturated by auto refresh commands
	// The maximum possible clock speeds for each speed grade are: 7: 143 Mhz, 6: 166 MHz, 5: 200 Mhz
    parameter CLK_RATE = 143000000,
	parameter SPEED_GRADE = 7, // 7, 6, or 5
	parameter READ_BURST_LENGTH = 1, // 1, 2, 4, 8, or 256 (full page)
	parameter WRITE_BURST = 1, // 0 = Single write mode, 1 = Burst write mode (same length as read burst)
	parameter CAS_LATENCY = 2 // 2 or 3
) (
	input logic clk,

	// 0 = Idle
	// 1 = Write (with Auto Precharge)
	// 2 = Read (with Auto Precharge)
	// 3 = Self Refresh (TODO)
	input logic [1:0] command,
	input logic [21:0] data_address,
	input logic [15:0] data_write,
	output logic [15:0] data_read,
	output logic data_read_valid = 1'b0, // goes high when a burst-read is ready
	output logic data_write_done = 1'b0, // goes high once the first write of a burst-write / single-write is done

	// These ports should be connected directly to the SDRAM chip
	output logic clock_enable = 1'b0,
	output logic [1:0] bank_activate,
	output logic [11:0] address,
	output logic chip_select,
	output logic row_address_strobe,
	output logic column_address_strobe,
	output logic write_enable,
	output logic [1:0] dqm = 2'b11,
	inout wire [15:0] dq
);

localparam READ_BURST_BITS = READ_BURST_LENGTH == 1 ? 3'd0 : READ_BURST_LENGTH == 2 ? 3'd1 : READ_BURST_LENGTH == 4 ? 3'd2 : READ_BURST_LENGTH == 8 ? 3'd3 : READ_BURST_LENGTH == 256 ? 3'd7 : 3'd0;

localparam ROW_CYCLE_TIME = $unsigned(integer'((SPEED_GRADE == 5 ? 55E-9 : SPEED_GRADE == 6 ? 60E-9 : 63E-9) * CLK_RATE));
localparam RAS_TO_CAS_DELAY = $unsigned(integer'((SPEED_GRADE == 5 ? 15E-9 : SPEED_GRADE == 6 ? 18E-9 : 21E-9) * CLK_RATE));
localparam PRECHARGE_TO_REFRESH_OR_ROW_ACTIVATE_SAME_BANK = RAS_TO_CAS_DELAY;
localparam ROW_ACTIVATE_TO_ROW_ACTIVATE_DIFFERENT_BANK = $unsigned(integer'((SPEED_GRADE == 5 ? 10E-9 : SPEED_GRADE == 6 ? 12E-9 : 14E-9) * CLK_RATE));
localparam ROW_ACTIVATE_TO_PRECHARGE_SAME_BANK = $unsigned(integer'((SPEED_GRADE == 5 ? 40E-9 : SPEED_GRADE == 6 ? 42E-9 : 42E-9) * CLK_RATE));
localparam MINIMUM_STABLE_CONDITION_TIME = $unsigned(integer'(200E-6 * CLK_RATE));

localparam MODE_REGISTER_SET_CYCLE_TIME = 2;
localparam WRITE_RECOVERY_TIME = MODE_REGISTER_SET_CYCLE_TIME;

localparam AVERAGE_REFRESH_INTERVAL_TIME = $unsigned(integer'(15.6E-6 * CLK_RATE));

localparam [2:0] STATE_UNINIT = 3'd0;
localparam [2:0] STATE_IDLE = 3'd1;
localparam [2:0] STATE_WRITING = 3'd2;
localparam [2:0] STATE_READING = 3'd3;
localparam [2:0] STATE_WAITING = 3'd4;
localparam [2:0] STATE_PRECHARGE = 3'd5;
logic [2:0] state = STATE_UNINIT;

localparam REFRESH_TIMER_WIDTH = $clog2(AVERAGE_REFRESH_INTERVAL_TIME + 1);
localparam REFRESH_TIMER_END = REFRESH_TIMER_WIDTH'(AVERAGE_REFRESH_INTERVAL_TIME);
logic [REFRESH_TIMER_WIDTH-1:0] refresh_timer = REFRESH_TIMER_WIDTH'(0);

always @(posedge clk)
begin
	// TODO: abort a read/write and refresh if it's taking too long (i.e. full-page)
	if (state == STATE_IDLE && refresh_timer >= REFRESH_TIMER_END) // Refresh will always occur from an idle state
		refresh_timer <= REFRESH_TIMER_WIDTH'(0);
	else if (state == STATE_UNINIT)
		refresh_timer <= REFRESH_TIMER_WIDTH'(0);
	else
		refresh_timer <= refresh_timer + 1'd1;
end

localparam COUNTER_WIDTH = $clog2(MINIMUM_STABLE_CONDITION_TIME + 1); // Row cycle time is the longest delay
logic [COUNTER_WIDTH-1:0] countdown = COUNTER_WIDTH'(0);

// Jump from waiting to a specified state
logic [2:0] destination_state = STATE_UNINIT;

// "Step" counter used for burst write/read counting and initialization steps. Must be at least 3 bits wide.
localparam STEP_WIDTH = $clog2(READ_BURST_LENGTH == 1 ? $unsigned(8) : $unsigned(READ_BURST_LENGTH + 1 + CAS_LATENCY));
logic [STEP_WIDTH-1:0] step = STEP_WIDTH'(0);

logic [15:0] internal_dq = 16'd0;
assign dq = state == STATE_WRITING ? internal_dq : 16'hzzzz; // Tri-State driver


localparam [3:0] CMD_BANK_ACTIVATE = 4'd0;
localparam [3:0] CMD_PRECHARGE_ALL = 4'd1;
localparam [3:0] CMD_WRITE = 4'd2;
localparam [3:0] CMD_READ = 4'd3;
localparam [3:0] CMD_MODE_REGISTER_SET = 4'd4;
localparam [3:0] CMD_NO_OP = 4'd5;
localparam [3:0] CMD_BURST_STOP = 4'd6;
localparam [3:0] CMD_AUTO_REFRESH = 4'd7;

logic [3:0] internal_command = CMD_NO_OP;
assign chip_select = !(internal_command != CMD_NO_OP);
assign row_address_strobe = !(internal_command == CMD_BANK_ACTIVATE || internal_command == CMD_PRECHARGE_ALL || internal_command == CMD_MODE_REGISTER_SET || internal_command == CMD_AUTO_REFRESH);
assign column_address_strobe = !(internal_command == CMD_WRITE || internal_command == CMD_READ || internal_command == CMD_MODE_REGISTER_SET || internal_command == CMD_AUTO_REFRESH);
assign write_enable = !(internal_command == CMD_PRECHARGE_ALL || internal_command == CMD_WRITE || internal_command == CMD_MODE_REGISTER_SET || internal_command == CMD_BURST_STOP);

always @(posedge clk)
begin
	if (state == STATE_UNINIT)
	begin
		step <= step + 1'd1;
		// $display("Initializing %d", step);
		// See Note 11 on page 20: Power up Sequence
		if (step == 3'd0)
		begin
			state <= STATE_WAITING;
			countdown <= MINIMUM_STABLE_CONDITION_TIME; // Wait for clock to stabilize
			destination_state <= STATE_UNINIT;
			clock_enable <= 1'b0;
			internal_command <= CMD_NO_OP;
			bank_activate <= 2'dx;
			address <= 12'dx;
		end
		else if (step == 3'd1) // Power Down Mode Exit
		begin
			clock_enable <= 1'b1;
			internal_command <= CMD_NO_OP;
			bank_activate <= 2'dx;
			address <= 12'dx;
		end
		else if (step == 3'd2) // Pre-charge all banks
		begin
			state <= STATE_WAITING;
			countdown <= COUNTER_WIDTH'(PRECHARGE_TO_REFRESH_OR_ROW_ACTIVATE_SAME_BANK - 1);
			destination_state <= STATE_UNINIT;
			internal_command <= CMD_PRECHARGE_ALL;
			bank_activate <= 2'dx;
			address <= {1'bx, 1'b1, 10'dx};
		end
		else if (step == 3'd3) // Extended mode register set
		begin
			state <= STATE_WAITING;
			countdown <= COUNTER_WIDTH'(MODE_REGISTER_SET_CYCLE_TIME - 1);
			destination_state <= STATE_UNINIT;
			internal_command <= CMD_MODE_REGISTER_SET;
			bank_activate <= 2'b01;
			address <= {10'd0, 1'b0, 1'b0}; // Full strength driver
		end
		else if (step == 3'd4) // Mode register set
		begin
			state <= STATE_WAITING;
			countdown <= COUNTER_WIDTH'(MODE_REGISTER_SET_CYCLE_TIME - 1);
			destination_state <= STATE_UNINIT;
			internal_command <= CMD_MODE_REGISTER_SET;
			bank_activate <= 2'b00;
			address <= {2'b00, WRITE_BURST == 1 ? 1'b0: 1'b1, 2'b00, CAS_LATENCY == 2 ? 3'b010 : 3'b011, 1'b0,  READ_BURST_BITS};
		end
		else if (step == 3'd5 || step == 3'd6) // Double auto refresh
		begin
			state <= STATE_WAITING;
			countdown <= COUNTER_WIDTH'(ROW_CYCLE_TIME - 1);
			destination_state <= step == 3'd6 ? STATE_IDLE : STATE_UNINIT;
			internal_command <= CMD_AUTO_REFRESH;
			bank_activate <= 2'dx;
			address <= 12'dx;
		end
	end
	else if (state == STATE_IDLE)
	begin
		if (refresh_timer >= REFRESH_TIMER_END) // Refresh timer expires
		begin
			// $display("Refreshing");
			state <= STATE_WAITING;
			countdown <= COUNTER_WIDTH'(ROW_CYCLE_TIME - 1);
			destination_state <= STATE_IDLE;
			internal_command <= CMD_AUTO_REFRESH;
			bank_activate <= 2'dx;
			address <= 12'dx;
		end
		else if (command == 2'd1 || command == 2'd2) // Write or Read (does a bank activate)
		begin
			// $display("Enter R/W");
			state <= STATE_WAITING;
			countdown <= COUNTER_WIDTH'(RAS_TO_CAS_DELAY - 1);
			destination_state <= command == 2'd1 ? STATE_WRITING : STATE_READING; // go to the correct state
			internal_command <= CMD_BANK_ACTIVATE;
			bank_activate <= data_address[21:20];
			address <= data_address[19:8];
			step <= STEP_WIDTH'(0);
			dqm <= 2'b00; // Don't mask input, enable output
		end
		else
		begin
			state <= STATE_IDLE;
			internal_command <= CMD_NO_OP;
			bank_activate <= 2'dx;
			address <= 12'dx;
		end
	end
	else if (state == STATE_WRITING)
	begin
		step <= step + 1'd1;
		if (step == STEP_WIDTH'(0))
		begin
			internal_command <= CMD_WRITE;
			bank_activate <= data_address[21:20];
			address[11] <= 1'dx;
			address[10] <= 1'b0;
			address[9:8] <= 2'dx;
			address[7:0] <= data_address[7:0];
		end
		else
		begin
			internal_command <= CMD_NO_OP;
			bank_activate <= 2'dx;
			address <= 12'dx;
		end

		if (step == STEP_WIDTH'(WRITE_BURST ? READ_BURST_LENGTH : 1)) // Last write just finished
		begin
			state <= STATE_WAITING;
			countdown <= COUNTER_WIDTH'(WRITE_RECOVERY_TIME - 2);
			destination_state <= STATE_PRECHARGE;
			data_write_done <= 1'b0;
			dqm <= 2'b11; // Enable masking
			internal_dq <= 16'd0;
		end
		else // Still writing
		begin
			data_write_done <= 1'b1;
			internal_dq <= data_write;
		end
	end
	else if (state == STATE_READING)
	begin
		internal_dq <= 16'dx;
		step <= step + 1'd1;
		if (step == STEP_WIDTH'(0)) // Read
		begin
			internal_command <= CMD_READ;
			bank_activate <= data_address[21:20];
			address[11] <= 1'dx;
			address[10] <= 1'b0;
			address[9:8] <= 2'dx;
			address[7:0] <= data_address[7:0];
		end
		else // No-Operation
		begin
			internal_command <= CMD_NO_OP;
			bank_activate <= 2'dx;
			address <= 12'dx;
		end

		if (step == STEP_WIDTH'(CAS_LATENCY + READ_BURST_LENGTH - 1)) // Last read just finished
		begin
			// $display("Read done");
			state <= STATE_PRECHARGE;
			data_read_valid <= 1'b0;
			dqm <= 2'b11; // Enable masking
		end
		else if (step >= STEP_WIDTH'(CAS_LATENCY - 1)) // Still reading
		begin
			data_read <= dq;
			data_read_valid <= 1'b1;
		end
		else
		begin
			data_read <= 16'd0;
			data_read_valid <= 1'd0;
		end
	end
	else if (state == STATE_WAITING)
	begin
		if (countdown == COUNTER_WIDTH'(0))
			state <= destination_state;
		else
			countdown <= countdown - 1'd1;
		internal_command <= CMD_NO_OP;
		bank_activate <= 2'dx;
		address <= 12'dx;
	end
	else if (state == STATE_PRECHARGE)
	begin
		state <= STATE_WAITING;
		destination_state <= STATE_IDLE;
		countdown <= COUNTER_WIDTH'(PRECHARGE_TO_REFRESH_OR_ROW_ACTIVATE_SAME_BANK - 1);
		internal_command <= CMD_PRECHARGE_ALL;
		bank_activate <= 2'dx;
		address <= {1'bx, 1'b1, 10'dx};
	end
end

endmodule
