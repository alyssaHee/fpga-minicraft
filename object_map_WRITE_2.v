// inputs a 1 or 0 into the map if a block is placed or broken (to be called by placing/breaking logic)
module object_map_WRITE_2 (Resetn, Clock, go, screenX, screenY, data_in, map);
	input Resetn, Clock, go;
	input [9:0] screenX;		// original coordinate from vga
	input [8:0] screenY;
	input data_in;

	output reg [1199:0] map;
	initial
	begin
		map = 1200'b0;
		map[2 * 40 + 26] = 1'b1;
		map[2 * 40 + 27] = 1'b1;
		map[2 * 40 + 29] = 1'b1;
		map[2 * 40 + 30] = 1'b1;
		map[2 * 40 + 32] = 1'b1;
		map[2 * 40 + 33] = 1'b1;
		map[2 * 40 + 34] = 1'b1;
		map[2 * 40 + 35] = 1'b1;
	end
	
	wire [6:0] blockX = screenX / 16;		// LOCATIONS IN CONDENSED FORM (0-39, 0,29)
	wire [5:0] blockY = screenY / 16;
	wire [10:0] blockAddr = blockY*40+blockX;		// Get the address of the location to write to
	
	always @(posedge Clock)
	begin
	/*
		if(!Resetn)
		begin   // initialize the map here
			map = 1200'b0;
			map[2] = 1'b1;
			map[42] = 1'b1;
			map[77] = 1'b1;
			
		end
	*/
		// if the write enable is 1, write to the map
		if (go)
			map[blockAddr] <= data_in;
	end
endmodule
