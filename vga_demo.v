`default_nettype none



/*  This code first displays a background image (MIF) on the VGA output. Then, the code
 *  displays two objects, each of which is read from a small memory, on the screen. Each
 *  object can be moved left/right/up/down by pressing PS2 keyboard keys. To use the circuit,
 *  first use KEY[0] to perform a reset. The background MIF should appear on the VGA output. 
 *  Pressing KEY[1] displays one object, at its initial position, and pressing KEY[2] displays
 *  the other object. Move the first object left/right/up/down using PS2 keys a/s/w/z, and 
 *  the other object using d/f/r/c.
*/

module vga_demo(CLOCK_50, SW, KEY, LEDR, PS2_CLK, PS2_DAT, HEX5, HEX4, HEX3, HEX2, HEX1, HEX0, VGA_R, VGA_G, VGA_B, VGA_HS, VGA_VS, VGA_BLANK_N, VGA_SYNC_N, VGA_CLK);

    // specify the number of bits needed for an X (column) pixel coordinate on the VGA display
    parameter nX = 10;

    // specify the number of bits needed for a Y (row) pixel coordinate on the VGA display
    parameter nY = 9;

    // state names for the FSM that controls drawing of objects

/*
A: Idle
B: received input
C: Scancode register enabled (we can take inputs yay!)
D: Drawing
*/

    parameter A = 3'b000, B = 3'b001, C = 3'b010, D = 3'b011, E = 3'b100, F = 3'b101, G = 3'b110, H = 3'b111;

	input wire CLOCK_50;
	input wire [9:0] SW;
	input wire [3:0] KEY;
	output wire [9:0] LEDR;
	inout wire PS2_CLK, PS2_DAT;
		 output wire [6:0] HEX5, HEX4, HEX3, HEX2, HEX1, HEX0;
	output wire [7:0] VGA_R;
	output wire [7:0] VGA_G;
	output wire [7:0] VGA_B;
	output wire VGA_HS;
	output wire VGA_VS;
	output wire VGA_BLANK_N;
	output wire VGA_SYNC_N;
	output wire VGA_CLK;

    // The signals below are used to multiplex the pixels displayed for the object

	wire [nX-1:0] O1_x, Block_x, MUX_x;    // x coordinate multiplexer
	wire [nY-1:0] O1_y, Block_y, MUX_y;    // y coordinate multiplexer
	wire [nX-1:0] O1_centre_x, O1_centre_x_new, left_x, right_x; // coordinates for collision check
	wire [nY-1:0] O1_centre_y, O1_centre_y_new, top_y, bottom_y;
	wire [8:0] O1_color, Block_color, MUX_color; // color multiplexer
	wire O1_write, Block_write, MUX_write; // write control multiplexer


	wire [1199:0] map;

    reg prev_ps2_clk;               // ps2_clk value in the previous clock cycle
    wire negedge_ps2_clk;           // used for PS2 keyboard signals
    wire ps2_rec;                   // set when a PS2 packet has been received
    wire object_sel;                // used to select which object to erase/draw
    reg [32:0] Serial;              // each PS2 serial data packet has 11 bits:
                                    // STOP (1) PARITY d7 d6 d5 d4 d3 d2 d1 d0 START (0)
                                    // 33 total bits are received (scancode/release/scancode
    reg [3:0] Packet;               // used to know when 11 bits have been received
    wire [7:0] scancode;            // used to save the current ps2 scancode
    reg Esc;                        // enable scancode register
    reg step; 					         // move an object
	 reg intial_draw;						// used to intialize objects

    wire O1_done, Block_done, done;    // object move completed
    wire [1:0] O1_dir;      // used to set direction of moving for objects
    reg [2:0] y_Q, Y_D;             // FSM, used to control drawing of objects

    wire Resetn, KEY1, KEY2, KEY3;        // Reset, and synchronized versions of KEYs
    wire PS2_CLK_S, PS2_DAT_S;      // synchronized versions of PS2 signals

    assign Resetn = KEY[0];
    sync S1 (~KEY[1], Resetn, CLOCK_50, KEY1);
    sync S2 (~KEY[2], Resetn, CLOCK_50, KEY2);
	sync S5 (~KEY[3], Resetn, CLOCK_50, KEY3);

    sync S3 (PS2_CLK, Resetn, CLOCK_50, PS2_CLK_S);
    sync S4 (PS2_DAT, Resetn, CLOCK_50, PS2_DAT_S);


    always @(posedge CLOCK_50)  // record PS2 clock value in previous CLOCK_50 cycle
        prev_ps2_clk <= PS2_CLK_S;


    // check when PS2_CLK has changed from 1 to 0
    assign negedge_ps2_clk = (prev_ps2_clk & !PS2_CLK_S);


    // save PS2 data packet
    always @(posedge CLOCK_50) begin    // specify a 33-bit shift register
        if (Resetn == 0)
            Serial <= 33'b0;
        else if (negedge_ps2_clk) begin
            Serial[31:0] <= Serial[32:1];
            Serial[32] <= PS2_DAT_S;
        end
    end

        

    // 'count' ps2 data bits
    always @(posedge CLOCK_50) begin    // specify a 34-bit shift register
        if (!Resetn || Packet == 'd11)
            Packet <= 'b0;
        else if (negedge_ps2_clk) begin
            Packet <= Packet + 'b1;
        end
    end

    // used to start an object move. Key press makes scancode/release/scancode, so we check
    // for Serial[30:23] == Serial[8:1]. Key repeat makes scancode/scancode/...
    assign ps2_rec = (Packet == 'd11) && (Serial[30:23] == Serial[8:1]);


    // ps2 scancode is in Serial[8:1]
    regn USC (Serial[8:1], Resetn, Esc, CLOCK_50, scancode);
    assign LEDR = {SW[1], SW[0], y_Q, scancode[4:0]};


    // select object according to which PS2 key was pressed. 
    assign O1_dir = scancode[1:0]; // ps2 key identifier (for a, s, w, z)

 

	// Below is collision check

	assign O1_centre_x_new = (O1_dir == 2'b11) ? O1_centre_x + 10'd1 :
									(O1_dir == 2'b00) ? O1_centre_x - 10'd1 :
										O1_centre_x;

	assign O1_centre_y_new = (O1_dir == 2'b10) ? O1_centre_y + 9'd1 :
									(O1_dir == 2'b01) ? O1_centre_y - 9'd1 :
									O1_centre_y;

 

	assign left_x = O1_centre_x_new - 10'd8;
	assign right_x = O1_centre_x_new + 10'd8 - 10'd1;
	assign top_y = O1_centre_y_new - 9'd8;
	assign bottom_y = O1_centre_y_new + 9'd8 - 9'd1;

 

	wire[5:0] left_grid_x = left_x / 10'd16;
	wire[5:0] right_grid_x = right_x / 10'd16;
	wire[4:0] top_grid_y = top_y / 9'd16;
	wire[4:0] bottom_grid_y = bottom_y / 9'd16;

 

	wire top_left_corner = map[top_grid_y * 40 + left_grid_x];
	wire top_right_corner = map[top_grid_y * 40 + right_grid_x];
	wire bottom_left_corner = map[bottom_grid_y * 40 + left_grid_x];
	wire bottom_right_corner = map[bottom_grid_y * 40 + right_grid_x];

 

	wire collide = top_left_corner || top_right_corner || bottom_left_corner || bottom_right_corner;

		reg initialize_go, initial_draw;
		wire initialize_done, block_exist_initial;
		wire [9:0] initializer_x; // coordinates to draw the block in the initialize phase.
		wire [8:0] initializer_y;
		
		object_map_DRAW (Resetn, CLOCK_50, initialize_go, initialize_done, map, block_exist_initial, initializer_x, initializer_y);
		
    // FSM state table

    always @ (*)
        case (y_Q)
            A:  if (SW[0] == 1) Y_D = F;
					else if (!ps2_rec) Y_D = A; 
                else Y_D = B;
            B:  Y_D = E;        // enable scancode register
				E: if (collide) Y_D = A; // Collision check
					else Y_D = C;
            C:  Y_D = D;        // send step signal to object
            D:  if (done == 1'b0) Y_D = D;
                else Y_D = A;
				F:	if (block_exist_initial) Y_D = G; // Count and find a block
					else if (initialize_done) Y_D = A;
					 else Y_D = F;
				G: if (!Block_done) Y_D = G; // Draw
					else Y_D = F;
				H: ;
            default: Y_D = A;
        endcase

    // FSM outputs
    always @ (*)
    begin
	 
        // default assignments
        Esc = 1'b0; step = 1'b0; initialize_go = 1'b0; initial_draw = 1'b0;
        case (y_Q)
            A:  ;
            B:  Esc = 1'b1;
            C:  step = 1'b1;  
            D:  ;
				E:  ;
				F:  initialize_go = 1'b1;
				G:  begin initialize_go = 1'b0; initial_draw = 1'b1; end
				H:  ;
        endcase
    end

    // FSM state FFs
    always @(posedge CLOCK_50)
        if (!Resetn)
            y_Q <= A;
        else
            y_Q <= Y_D;

    // instantiate object 1
    object O1 (Resetn, CLOCK_50, KEY1, step, O1_dir, O1_x, O1_y, O1_color, O1_write, O1_done, O1_centre_x, O1_centre_y);
        defparam O1.LEFT  = 2'b00;  // 'a'
        defparam O1.RIGHT = 2'b11;  // 's'
        defparam O1.UP    = 2'b01;  // 'w'
        defparam O1.DOWN =  2'b10;  // 'z'
  defparam O1.INIT_FILE = "./MIF/player.mif";

  // These are used to store the initial (top left coordinate) of the block being drawn.

	wire [nX-1:0] Block_ini_x;
	wire [nY-1:0] Block_ini_y;

	coordinateConverter C1 (Block_ini_x, Block_ini_y, O1_x, O1_y);
	
	wire [nX-1:0] happy_x = (KEY3) ? Block_ini_x :
									(initial_draw) ? initializer_x :
									Block_ini_x;
	wire [nY-1:0] happy_y = (KEY3) ? Block_ini_y :
									(initial_draw) ? initializer_y :
									Block_ini_y;
	
	blockObject happy (Resetn, CLOCK_50, KEY3 | initial_draw, Block_x, Block_y, Block_color, Block_write, Block_done, happy_x, happy_y, KEY2);
	defparam happy.INIT_FILE = "MIF/happy.mif";
	
	// This is to specify whether to place or break a block
	wire place_break = (KEY3 == 1'b1) ? 1'b1 : // Press key3 to place a block
							 (KEY2 == 1'b1) ? 1'b0 : // Press key2 to break a block
							 1'b0;
	
	wire write_enable_map = KEY3 | KEY2;
	
	object_map_WRITE W1 (Resetn, CLOCK_50, write_enable_map, Block_ini_x, Block_ini_y, place_break, map);

    assign done = O1_done | Block_done;

	 wire block_active = KEY3 | KEY2 | initial_draw;
    // choose x, y, color, and write for one of the two objects
    assign MUX_x = (block_active) ? Block_x : O1_x ;
    assign MUX_y = (block_active) ? Block_y : O1_y ;
    assign MUX_color = (block_active) ? Block_color : O1_color;
    assign MUX_write = (block_active) ? Block_write : O1_write;


    // display PS2 data
    hex7seg H0 (Serial[4:1], HEX0);
    hex7seg H1 (Serial[8:5], HEX1);
    hex7seg H2 (Serial[15:12], HEX2);
    hex7seg H3 (Serial[19:16], HEX3);
    hex7seg H4 (Serial[26:23], HEX4);
    hex7seg H5 (Serial[30:27], HEX5);



    // connect to VGA controller

    vga_adapter VGA (
		.resetn(Resetn),
		.clock(CLOCK_50),
		.color(MUX_color),
		.x(MUX_x),
		.y(MUX_y),
		.write(MUX_write),
		.VGA_R(VGA_R),
		.VGA_G(VGA_G),
		.VGA_B(VGA_B),
		.VGA_HS(VGA_HS),
		.VGA_VS(VGA_VS),
		.VGA_BLANK_N(VGA_BLANK_N),
		.VGA_SYNC_N(VGA_SYNC_N),
		.VGA_CLK(VGA_CLK));

	defparam VGA.BACKGROUND_IMAGE = "./MIF/green.mif" ;
endmodule



// syncronizer, implemented as two FFs in series
module sync(D, Resetn, Clock, Q);
    input wire D;
    input wire Resetn, Clock;
    output reg Q;

    reg Qi; // internal node

    always @(posedge Clock)
        if (Resetn == 0) begin
            Qi <= 1'b0;
            Q <= 1'b0;
        end

        else begin
            Qi <= D;
            Q <= Qi;
        end

endmodule



// n-bit up/down-counter with reset, load, enable, and direction control

module upDn_count (R, Clock, Resetn, L, E, Dir, Q);
    parameter n = 8;
    input wire [n-1:0] R;
    input wire Clock, Resetn, E, L, Dir;
    output reg [n-1:0] Q;

    always @ (posedge Clock)
        if (Resetn == 0)
            Q <= {n{1'b0}};
        else if (L == 1)
            Q <= R;
        else if (E)
            if (Dir)
                Q <= Q + {{n-1{1'b0}},1'b1};
            else
                Q <= Q - {{n-1{1'b0}},1'b1};
endmodule



module hex7seg (hex, display);
    input wire [3:0] hex;
    output reg [6:0] display;



    /*
     *       0  
     *      ---  
     *     |   |
     *    5|   |1
     *     | 6 |
     *      ---  
     *     |   |
     *    4|   |2
     *     |   |
     *      ---  
     *       3  
     */

    always @ (hex)

        case (hex)
            4'h0: display = 7'b1000000;
            4'h1: display = 7'b1111001;
            4'h2: display = 7'b0100100;
            4'h3: display = 7'b0110000;
            4'h4: display = 7'b0011001;
            4'h5: display = 7'b0010010;
            4'h6: display = 7'b0000010;
            4'h7: display = 7'b1111000;
            4'h8: display = 7'b0000000;
            4'h9: display = 7'b0011000;
            4'hA: display = 7'b0001000;
            4'hB: display = 7'b0000011;
            4'hC: display = 7'b1000110;
            4'hD: display = 7'b0100001;
            4'hE: display = 7'b0000110;
            4'hF: display = 7'b0001110;
        endcase

endmodule



// implements a movable object

module object (Resetn, Clock, go, ps2_rec, dir, VGA_x, VGA_y, VGA_color, VGA_write, done, x_centre, y_centre);
    // specify the number of bits needed for an X (column) pixel coordinate on the VGA display
    parameter nX = 10;
    // specify the number of bits needed for a Y (row) pixel coordinate on the VGA display
    parameter nY = 9;
	
    // by default, use offsets to center the object on the VGA display
    parameter XOFFSET = 320;
    parameter YOFFSET = 240;
    parameter LEFT = 2'b00 /*'a'*/, RIGHT = 2'b11/*'s'*/, UP = 2'b01/*'w'*/, DOWN = 2'b10/*'z'*/;
    parameter xOBJ = 4, yOBJ = 4;   // object size is 2^xOBJ x 2^yOBJ
    parameter BOX_SIZE_X = 1 << xOBJ;
    parameter BOX_SIZE_Y = 1 << yOBJ;
    parameter Mn = xOBJ + yOBJ; // address lines needed for the object memory
    parameter INIT_FILE = "./MIF/object_mem_16_16_9.mif";

    // state names for the FSM that draws the object
    parameter A = 3'b000, B = 3'b001, C = 3'b010, D = 3'b011, E = 3'b100,
              F = 3'b101, G = 3'b110, H = 3'b111;

    input wire Resetn, Clock;
    input wire go;                              // can be used to draw at initial position
    input wire ps2_rec;                         // PS2 data received
    input wire [1:0] dir;                       // movement direction
	output wire [nX-1:0] VGA_x;                 // for syncing with object memory
	output wire [nY-1:0] VGA_y;                 // for syncing with object memory
	output wire [8:0] VGA_color;                // used to draw pixels

    output wire VGA_write;                      // pixel write control

    output reg done;                            // done drawing cycle

output wire [nX-1:0] x_centre;

output wire [nY-1:0] y_centre;



wire [nX-1:0] X, X0;    // starting X location 
wire [nY-1:0] Y, Y0;    // starting Y location 
wire [nX-1:0] size_x = BOX_SIZE_X;   // store the X size (must be power of 2)
wire [nY-1:0] size_y = BOX_SIZE_Y;   // store the Y size
    wire [xOBJ-1:0] XC;                  // used to access object memory
    wire [yOBJ-1:0] YC;                  // used to access object memory
    reg write, Lxc, Lyc, Exc, Eyc;       // object control signals
    reg erase;                           // erase/draw object
    wire Right, Left, Up, Down;          // object direction
    reg Lx, Ly, Ex, Ey;                  // object counter controls
    reg [2:0] y_Q, Y_D;                  // FSM
    
wire [8:0] obj_color;    // object pixel colors, read from memory


    // object (x,y) location. For x, counter will be enabled when moving L/R, increment
    // for R, decrement for L. For y, counter will be enabled when moving U/D, increment 
    // for D, decrement for U
    assign X0 = XOFFSET;
    assign Y0 = YOFFSET;

    upDn_count UX (X0, Clock, Resetn, Lx, Ex, Right, X);
        defparam UX.n = nX;
    upDn_count UY (Y0, Clock, Resetn, Ly, Ey, Down, Y);
        defparam UY.n = nY;

    // these counter are used to generate (x,y) coordinates to read the object's pixels
    upDn_count U3 ({xOBJ{1'd0}}, Clock, Resetn, Lxc, Exc, 1'b1, XC); // object column counter
        defparam U3.n = xOBJ;
    upDn_count U4 ({yOBJ{1'd0}}, Clock, Resetn, Lyc, Eyc, 1'b1, YC); // object row counter
        defparam U4.n = yOBJ;

    // these signals are used to enable the (x,y) object location counters and to make these 
    // counters increment or decrement
    assign Left = (dir == LEFT);
    assign Right = (dir == RIGHT);
    assign Up = (dir == UP);
    assign Down = (dir == DOWN);

    // FSM state table
    always @ (*)
        case (y_Q)
            A:  Y_D = B;                        // load (x,y) location counters
            B:  if (go) Y_D = F;                // pushbutton KEY pressed to show object
                else if (ps2_rec) Y_D = C;      // PS2 key received to move object
                else Y_D = B;                   // wait
            C:  if (XC != size_x-1) Y_D = C;    // erase row of object
                else Y_D = D;
            D:  if (YC != size_y-1) Y_D = C;    // next row of object to erase
                else Y_D = E;                   // done erase cycle
            E:  Y_D = F;                        // +/- (x,y)
            F:  if (XC != size_x-1) Y_D = F;    // draw row of object
                else Y_D = G;
            G:  if (YC != size_y-1) Y_D = F;    // next row of object to draw
                else Y_D = H;                   // done draw cycle
            H:  if (go) Y_D = H;                // wait for KEY press
                else Y_D = B;
            default: Y_D = A;
        endcase

    // FSM outputs

    always @ (*)
    begin
        // default assignments
        Lx = 1'b0; Ly = 1'b0; Ex = 1'b0; Ey = 1'b0; write = 1'b0; 
        Lxc = 1'b0; Lyc = 1'b0; Exc = 1'b0; Eyc = 1'b0; erase = 1'b0; done = 1'b0;
        case (y_Q)
            A:  begin Lx = 1'b1; Ly = 1'b1; end                   // load (X,Y) counters
            B:  begin Lxc = 1'b1; Lyc = 1'b1; end                 // load (XC,YC) counters
            C:  begin Exc = 1'b1; write = 1'b1; erase = 1'b1; end // enable XC, write pixel
            D:  begin Lxc = 1'b1; Eyc = 1'b1; erase = 1'b1; end   // load XC, enable YC
            // state E is reached after erasing the object. Now, move and draw the object
            E:  begin Ex = Right | Left; Ey = Up | Down; end      // move L/R or U/D
            F:  begin Exc = 1'b1; write = 1'b1; end               // enable XC, write pixel
            G:  begin Lxc = 1'b1; Eyc = 1'b1; end                 // load XC, enable YC
            H:  done = 1'b1;
		endcase

    end



    // FSM state FFs
    always @(posedge Clock)
        if (!Resetn)
            y_Q <= 3'b0;
        else
            y_Q <= Y_D;
	
    // read a pixel color from the object memory. We can use {YC,XC} because the x dimension
    // of the object memory is a power of 2
    object_mem U6 ({YC,XC}, Clock, obj_color);
        defparam U6.n = 9;
        defparam U6.Mn = xOBJ + yOBJ;
        defparam U6.INIT_FILE = INIT_FILE;

    // compute the (x,y) location of the current pixel to be drawn (or erased). We subtract
    // half the object's width and height because we want the objec to be centered at its 
    // original (x,y) location. We add (Xc,YC) to form the correct address of the pixel. The
    // object memory takes one clock cycle to provide data, so we register the computed (x,y)
    // location to remain synchronized

    regn U7 (X - (size_x >> 1) + XC, Resetn, 1'b1, Clock, VGA_x);
        defparam U7.n = nX;
    regn U8 (Y - (size_y >> 1) + YC, Resetn, 1'b1, Clock, VGA_y);
        defparam U8.n = nY;

    // synchronize write signal with VGA_x, VGA_y, VGA_color 
    regn U9 (write, Resetn, 1'b1, Clock, VGA_write);
        defparam U9.n = 1;


    // use the background color (when erasing), or the object color when drawing
    // (black background is assumed below)
    assign VGA_color = erase ? {9'h6A} : obj_color;

	assign x_centre = X;
	assign y_centre = Y;
endmodule



module coordinateConverter(new_X, new_Y, XC, YC);

	parameter nX = 10;
	parameter nY = 9;
	input [nX-1:0]XC;
	output [nX-1:0] new_X;
	input [nY-1:0]YC;
	output [nY-1:0] new_Y;

	assign new_X = XC - XC % 10'd16;
	assign new_Y = YC - 9'd16 - YC % 9'd16;

endmodule

