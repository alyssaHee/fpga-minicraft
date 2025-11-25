// inputs a 1 or 0 into the map if a block is placed or broken (to be called by placing/breaking logic)
module object_map_WRITE_1 (Resetn, Clock, go, screenX, screenY, data_in, map);
	input Resetn, Clock, go;
	input [9:0] screenX;		// original coordinate from vga
	input [8:0] screenY;
	input data_in;

	output reg [1199:0] map;
	initial
	begin
		map = 1200'b0;
		map[1 * 40 + 14] = 1'b1;
		map[2 * 40 + 14] = 1'b1;
		map[3 * 40 + 14] = 1'b1;
		map[4 * 40 + 14] = 1'b1;
		map[5 * 40 + 14] = 1'b1;
		map[6 * 40 + 14] = 1'b1;
		map[7 * 40 + 14] = 1'b1;
		map[8 * 40 + 14] = 1'b1;
		map[9 * 40 + 14] = 1'b1;
		
		map[9 * 40 + 15] = 1'b1;
		map[9 * 40 + 16] = 1'b1;
		map[9 * 40 + 17] = 1'b1;
		map[9 * 40 + 18] = 1'b1;
		map[9 * 40 + 19] = 1'b1;
		map[9 * 40 + 20] = 1'b1;
		map[9 * 40 + 21] = 1'b1;
		
		map[1 * 40 + 22] = 1'b1;
		map[2 * 40 + 22] = 1'b1;
		map[3 * 40 + 22] = 1'b1;
		map[6 * 40 + 22] = 1'b1;
		map[7 * 40 + 22] = 1'b1;
		map[8 * 40 + 22] = 1'b1;
		map[9 * 40 + 22] = 1'b1;
		
		map[1 * 40 + 15] = 1'b1;
		map[1 * 40 + 16] = 1'b1;
		map[1 * 40 + 17] = 1'b1;
		map[1 * 40 + 18] = 1'b1;
		map[1 * 40 + 19] = 1'b1;
		map[1 * 40 + 20] = 1'b1;
		map[1 * 40 + 21] = 1'b1;
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
