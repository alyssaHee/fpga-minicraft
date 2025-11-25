/*
 *  This code is a modified version of the example "Colors" and “Object” provided by the ECE241 Teaching Team.
 *  It draws an object block at a given x and y coordinate.
*/
/*
	// example instantiation happy block
    blockObject happy (KEY[0], CLOCK_50, ~KEY[3], happy_x, happy_y, happy_color, happy_write, happy_done, locationX, locationY);
		defparam happy.INIT_FILE = "MIF/happy.mif";
*/	

// object block
module blockObject (Resetn, Clock, draw, VGA_x, VGA_y, VGA_color, VGA_write, done, locationX, locationY, erase);
    // specify the number of bits needed for an X (column) and Y (row) pixel coordinate on the VGA display
    parameter nX = 10;
    parameter nY = 9;
    parameter xOBJ = 4, yOBJ = 4;   			// object size is 2^xOBJ x 2^yOBJ
	parameter BOX_SIZE_X = 1 << xOBJ;			// object width and height
    parameter BOX_SIZE_Y = 1 << yOBJ;
    parameter Mn = xOBJ + yOBJ; 				// address lines needed for the object memory
    parameter INIT_FILE = "MIF/happy.mif";
	parameter X_OFFSET = 8;						// use offsets to get the centre of the box
    parameter Y_OFFSET = 8;
    
	input wire Resetn, Clock;
    input wire draw, erase;
	 wire go = draw || erase;
	 
	input [nX-1:0] locationX;
	input [nY-1:0] locationY;
	output wire [nX-1:0] VGA_x;                 // for syncing with object memory
	output wire [nY-1:0] VGA_y;                 // for syncing with object memory
	output wire [8:0] VGA_color;                // used to draw pixels
    output wire VGA_write;                      // pixel write control
	output reg done;
	
	reg write, Lxc, Lyc, Exc, Eyc;       		// object control signals
    reg Lx, Ly;                  				// object counter controls
	reg [2:0] y_Q, Y_D;                  		// FSM
	wire [xOBJ-1:0] XC;                  		// used to access object memory
    wire [yOBJ-1:0] YC;                  		// used to access object memory
    wire [nX-1:0] X, X0;    					// used to record the center of the box
    wire [nY-1:0] Y, Y0;    					// used to record the center of the box
	wire [nX-1:0] size_x = BOX_SIZE_X;   		// store the X size (must be power of 2)
	wire [nY-1:0] size_y = BOX_SIZE_Y;   		// store the Y size
	
	// Store the location of block
    assign X0 = locationX + X_OFFSET;
    assign Y0 = locationY + Y_OFFSET;
    regn U1 (X0, Resetn, 1'b1, Clock, X);
        defparam U1.n = nX;
    regn U2 (Y0, Resetn, 1'b1, Clock, Y);
        defparam U2.n = nY;

	// these counters are used to generate (x,y) coordinates to read the object's pixels
    Up_count U4 ({xOBJ{1'd0}}, Clock, Resetn, Lxc, Exc, XC); // object column counter
        defparam U4.n = xOBJ;
    Up_count U5 ({yOBJ{1'd0}}, Clock, Resetn, Lyc, Eyc, YC); // object row counter
        defparam U5.n = yOBJ;
		
	parameter A = 2'b00, B = 2'b01, C = 2'b10, D = 2'b11;
		
	// FSM state table
    always @ (*)
        case (y_Q)
            A:  if (!go) Y_D = A;
                else Y_D = B;
            B:  if (XC != size_x-1) Y_D = B;  // box x coordinate (column)
                else Y_D = C;
            C:  if (YC != size_y-1) Y_D = B;  // box y coordinate (row)
                else Y_D = D;
            D:  Y_D = A;
        endcase
		
    // FSM outputs
    always @ (*)
    begin
        // default assignments
        write = 1'b0; Lxc = 1'b0; Lyc = 1'b0; Exc = 1'b0; Eyc = 1'b0; done = 1'b0;
        case (y_Q)
            A:  begin Lxc = 1'b1; Lyc = 1'b1; end   // load (XC,YC) counter
            B:  begin Exc = 1'b1; write = 1'b1; end // enable XC, write pixel
            C:  begin Lxc = 1'b1; Eyc = 1'b1; end   // enable YC, load XC
            D:  begin Lyc = 1'b1; done = 1'b1; end  // load YC
        endcase
    end

    always @(posedge Clock)
        if (!Resetn)
            y_Q <= 2'b0;
        else
            y_Q <= Y_D;

	 
	 wire [8:0] obj_color;    					// object pixel colors, read from memory
	 wire [8:0] resulting_color = (draw == 1'b1) ? obj_color: // This is the color output (green when erasing, obj_color when drawing)
											(erase == 1'b1) ? 9'h6B :
											9'h6B;
    // read a pixel color from the object memory. We can use {YC,XC} because the x dimension
    // of the object memory is a power of 2
    block_mem U3 ({YC,XC}, Clock, obj_color);
        defparam U3.n = 9; // depth
        defparam U3.Mn = xOBJ + yOBJ;
        defparam U3.INIT_FILE = INIT_FILE;
		
	// compute the (x,y) location of the current pixel to be drawn (or erased). We subtract
    // half the object's width and height because we want the object to be centered at its 
    // original (x,y) location. We add (Xc,YC) to form the correct address of the pixel. The
    // object memory takes one clock cycle to provide data, so we register the computed (x,y)
    // location to remain synchronized
    regn U6 (X - (size_x >> 1) + XC, Resetn, 1'b1, Clock, VGA_x);
        defparam U6.n = nX;
    regn U7 (Y - (size_y >> 1) + YC, Resetn, 1'b1, Clock, VGA_y);
        defparam U7.n = nY;
    // synchronize write signal with VGA_x, VGA_y, VGA_color 
    regn U8 (write, Resetn, 1'b1, Clock, VGA_write);
        defparam U8.n = 1;

    assign VGA_color = resulting_color;

endmodule

// this reg just stores data
module regn(R, Resetn, E, Clock, Q);
    parameter n = 8;
    input [n-1:0] R;
    input Resetn, E, Clock;
    output reg [n-1:0] Q;

    always @(posedge Clock)
        if (!Resetn)
            Q <= 0;
        else if (E)
            Q <= R;
endmodule

// n-bit up-counter with reset, load, and enable
module Up_count (R, Clock, Resetn, L, E, Q);
    parameter n = 8;
    input [n-1:0] R;
    input Clock, Resetn, E, L;
    output reg [n-1:0] Q;

    always @ (posedge Clock)
        if (Resetn == 0)
            Q <= {n{1'b0}};
        else if (L == 1)
            Q <= R;
        else if (E)
            Q <= Q + 1'b1;
endmodule


module block_mem (address, clock, q);
    parameter n = 3;    // memory width
    parameter Mn = 6;   // address bits
    parameter INIT_FILE = "MIF/happy.mif";

	input wire [Mn-1:0] address;
	input wire clock;
	output [n-1:0]  q;
	wire [n-1:0] sub_wire0;
	assign q = sub_wire0[n-1:0];

	altsyncram	altsyncram_component (
				.address_a (address),
				.clock0 (clock),
				.q_a (sub_wire0),
				.aclr0 (1'b0),
				.aclr1 (1'b0),
				.address_b (1'b1),
				.addressstall_a (1'b0),
				.addressstall_b (1'b0),
				.byteena_a (1'b1),
				.byteena_b (1'b1),
				.clock1 (1'b1),
				.clocken0 (1'b1),
				.clocken1 (1'b1),
				.clocken2 (1'b1),
				.clocken3 (1'b1),
				.data_a ({n{1'b1}}),
				.data_b (1'b1),
				.eccstatus (),
				.q_b (),
				.rden_a (1'b1),
				.rden_b (1'b1),
				.wren_a (1'b0),
				.wren_b (1'b0));
	defparam
		altsyncram_component.address_aclr_a = "NONE",
		altsyncram_component.clock_enable_input_a = "BYPASS",
		altsyncram_component.clock_enable_output_a = "BYPASS",
		altsyncram_component.init_file = INIT_FILE,
		altsyncram_component.intended_device_family = "Cyclone V",
		altsyncram_component.lpm_hint = "ENABLE_RUNTIME_MOD=NO",
		altsyncram_component.lpm_type = "altsyncram",
		altsyncram_component.numwords_a = 1 << Mn,
		altsyncram_component.operation_mode = "ROM",
		altsyncram_component.outdata_aclr_a = "NONE",
		altsyncram_component.outdata_reg_a = "UNREGISTERED",
		altsyncram_component.widthad_a = Mn,
		altsyncram_component.width_a = n,
		altsyncram_component.width_byteena_a = 1;
endmodule


