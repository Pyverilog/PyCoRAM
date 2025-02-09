`include "pycoram.v"

module st #
  (
   parameter W_D = 32
   )
  (
   input CLK,
   input RST
   );

  st_main
  inst_st_main
    (
     .CLK(CLK),
     .RST(RST)
     );

endmodule
  
//------------------------------------------------------------------------------
module st_main #
  (
   parameter W_D = 32,
   parameter W_A = 9, // 512 (= Max size of Matrix) 
   parameter W_COMM_A = 4 // 16
   )
  (
   input CLK,
   input RST
   );

  localparam PIPELINE_DEPTH = W_D + 3 + 1 + 3;
  
  reg [W_D-1:0] sum;
  
  reg [W_A-1:0] mem_addr;
  wire [W_D-1:0] mem_0_q;
  wire [W_D-1:0] mem_1_q;
  wire [W_D-1:0] mem_2_q;
  
  reg [W_A-1:0] next_mem_d_addr;
  reg [W_A-1:0] mem_d_addr;
  reg [W_D-1:0] mem_d_d;
  reg mem_d0_we;

  reg [W_D-1:0] comm_d;
  wire [W_D-1:0] comm_q;
  reg comm_enq;
  reg comm_deq;
  wire comm_empty;
  wire comm_full;

  reg [7:0] state;
  
  reg [W_D-1:0] read_count;
  reg [W_D-1:0] mesh_size;
  
  reg [W_D-1:0] comp_d0;
  reg [W_D-1:0] comp_d1;
  reg [W_D-1:0] comp_d2;
  reg comp_enable;
  reg [7:0] comp_wait;

  reg init_sum;
  reg calc_sum;
  reg hot_spot;
  
  always @(posedge CLK) begin
    if(RST) begin
      state <= 0;
      comm_enq <= 0;
      comm_deq <= 0;
      comm_d <= 0;
      sum <= 0;
      init_sum <= 0;
      calc_sum <= 0;
      hot_spot <= 0;
      mesh_size <= 0;
      read_count <= 0;
      mem_addr <= 0;
      comp_enable <= 0;
      comp_d0 <= 0;
      comp_d1 <= 0;
      comp_d2 <= 0;
      comp_wait <= 0;
    end else begin
      // default value
      comm_enq <= 0;
      comm_deq <= 0;
      comp_enable <= 0;
      case(state)
        'h0: begin
          if(!comm_empty) begin
            comm_deq <= 1;
            state <= 'h1;
          end
        end
        'h1: begin
          comm_deq <= 0;
          state <= 'h2;
        end
        'h2: begin
          sum <= 0;
          init_sum <= 0;
          calc_sum <= 0;
          hot_spot <= 0;
          mesh_size <= comm_q;
          state <= 'h3;
          $display("start execution");
          $display("mesh_size=%d", comm_q);
        end
        // computation start
        'h3: begin
          if(!comm_empty) begin
            comm_deq <= 1;
            state <= 'h4;
          end
        end
        'h4: begin
          comm_deq <= 0;
          state <= 'h5;
        end
        'h5: begin
          {init_sum, calc_sum, hot_spot} <= comm_q;
          mem_addr <= 0;
          read_count <= 0;
          //if(comm_q == 0) begin // done
          if(comm_q == 'hff) begin // done
            state <= 'h0;
          end else begin
            state <= 'h6;
          end
        end
        'h6: begin
          if(init_sum) begin
            sum <= 0;
          end
          mem_addr <= mem_addr + 1;
          state <= 'h7;
        end
        'h7: begin
          mem_addr <= mem_addr + 1;
          read_count <= read_count + 1;
          comp_enable <= !calc_sum;
          comp_d0 <= mem_0_q;
          comp_d1 <= mem_1_q;
          comp_d2 <= mem_2_q;
          sum <= sum + mem_0_q;
          if(read_count + 3 >= mesh_size) begin
            state <= 'h8;
          end
        end
        'h8: begin
          read_count <= read_count + 1;
          comp_enable <= !calc_sum;
          comp_d0 <= mem_0_q;
          comp_d1 <= mem_1_q;
          comp_d2 <= mem_2_q;
          sum <= sum + mem_0_q;
          state <= 'h9;
        end
        'h9: begin
          read_count <= read_count + 1;
          comp_enable <= !calc_sum;
          comp_d0 <= mem_0_q;
          comp_d1 <= mem_1_q;
          comp_d2 <= mem_2_q;
          sum <= sum + mem_0_q;
          comp_wait <= 0;
          state <= 'ha;
        end
        'ha: begin
          comp_wait <= comp_wait + 1;
          if(comp_wait == PIPELINE_DEPTH+2) begin
            state <= 'hb;
          end else if(calc_sum) begin
            state <= 'hb;
          end
        end
        'hb: begin
          comm_d <= sum;
          if(!comm_full) begin
            comm_enq <= 1;
            state <= 'hc;
          end
        end
        'hc: begin
          comm_enq <= 0;
          state <= 'h3;
        end
      endcase
    end
  end

  // execution pipeline
  wire comp_enable_local;
  wire [W_D-1:0] comp_rslt;
  wire comp_valid;
  assign comp_enable_local = comp_enable;

  AddDiv #
   (
    .W_D(W_D)
    ) 
  inst_adddiv
    (
     .CLK(CLK),
     .RST(RST),
     .in0(comp_d0),
     .in1(comp_d1),
     .in2(comp_d2),
     .enable(comp_enable_local),
     .rslt(comp_rslt),
     .valid(comp_valid)
    );

  always @(posedge CLK) begin
    if(RST) begin
      mem_d0_we <= 0;
      mem_d_addr <= 0;
      mem_d_d <= 0;
    end else begin
      if(comp_valid && comp_rslt === 'hx) $finish;
      mem_d0_we <= 0;
      if(state == 'h3) begin
        mem_d_addr <= 0; // write to [1] to [(mesh_size -2)]
      end else if(comp_valid) begin
        if(mem_d_addr == 0 && hot_spot) begin
          mem_d_d <= 'h9999999;
        end else begin
          mem_d_d <= comp_rslt;
        end
        mem_d0_we <= 1;
        mem_d_addr <= mem_d_addr + 1;
      end
    end
  end
  
  CoramMemory1P #
    (
     .CORAM_THREAD_NAME("cthread_st"),
     .CORAM_ID(0),
     .CORAM_SUB_ID(0),
     .CORAM_ADDR_LEN(W_A),
     .CORAM_DATA_WIDTH(W_D)
     )
  inst_mem_0
   (
    .CLK(CLK),
    .ADDR(mem_addr),
    .D('hx),
    .WE(1'b0),
    .Q(mem_0_q)
    );

  CoramMemory1P #
    (
     .CORAM_THREAD_NAME("cthread_st"),
     .CORAM_ID(1),
     .CORAM_SUB_ID(0),
     .CORAM_ADDR_LEN(W_A),
     .CORAM_DATA_WIDTH(W_D)
     )
  inst_mem_1
   (
    .CLK(CLK),
    .ADDR(mem_addr),
    .D('hx),
    .WE(1'b0),
    .Q(mem_1_q)
    );

  CoramMemory1P #
    (
     .CORAM_THREAD_NAME("cthread_st"),
     .CORAM_ID(2),
     .CORAM_SUB_ID(0),
     .CORAM_ADDR_LEN(W_A),
     .CORAM_DATA_WIDTH(W_D)
     )
  inst_mem_2
   (
    .CLK(CLK),
    .ADDR(mem_addr),
    .D('hx),
    .WE(1'b0),
    .Q(mem_2_q)
    );

  CoramMemory1P #
    (
     .CORAM_THREAD_NAME("cthread_st"),
     .CORAM_ID(4),
     .CORAM_SUB_ID(0),
     .CORAM_ADDR_LEN(W_A),
     .CORAM_DATA_WIDTH(W_D)
     )
  inst_mem_d0
   (
    .CLK(CLK),
    .ADDR(mem_d_addr),
    .D(mem_d_d),
    .WE(mem_d0_we),
    .Q()
    );

  CoramChannel #
    (
     .CORAM_THREAD_NAME("cthread_st"),
     .CORAM_ID(0),
     .CORAM_ADDR_LEN(W_COMM_A),
     .CORAM_DATA_WIDTH(W_D)
     )
  inst_channel
    (
     .CLK(CLK),
     .RST(RST),
     .D(comm_d),
     .ENQ(comm_enq),
     .FULL(comm_full),
     .Q(comm_q),
     .DEQ(comm_deq),
     .EMPTY(comm_empty)
     );
    
endmodule

//------------------------------------------------------------------------------
module AddDiv #
  (
   parameter W_D = 32,
   parameter NUM_LINES = 3,
   parameter NUM_POINTS = 9 // divide value
   )
  (
   input CLK,
   input RST,
   input [W_D-1:0] in0,
   input [W_D-1:0] in1,
   input [W_D-1:0] in2,
   input enable,
   output [W_D-1:0] rslt,
   output valid
   );

  wire [W_D-1:0] add_rslt;
  wire add_valid;
  
  wire [W_D-1:0] div_in;
  wire div_en;

  Adder3 #
    (
     .W_D(W_D)
     )
  inst_addr4
    (
     .CLK(CLK),
     .RST(RST),
     .in0(in0),
     .in1(in1),
     .in2(in2),
     .enable(enable),
     .rslt(add_rslt),
     .valid(add_valid)
     );

  genvar i;
  generate for(i=0; i<NUM_LINES; i=i+1) begin: s_point
    reg [W_D-1:0] sum;
    reg svalid;
    if(i==0) begin
      always @(posedge CLK) begin
        if(RST) begin
          svalid <= 0;
        end else begin
          svalid <= add_valid;
        end
      end
      always @(posedge CLK) begin
        if(add_valid) begin
          sum <= add_rslt;
        end else begin
          sum <= 0;
        end
      end
    end else begin
      always @(posedge CLK) begin
        if(RST) begin
          svalid <= 0;
        end else begin
          svalid <= s_point[i-1].svalid && add_valid;
        end
      end
      always @(posedge CLK) begin
        if(add_valid) begin
          sum <= s_point[i-1].sum + add_rslt;
        end
      end
    end
  end endgenerate

  assign div_en = s_point[NUM_LINES-1].svalid;
  assign div_in = s_point[NUM_LINES-1].sum;

  Divider #
    (
     .W_D(W_D)
     )
  inst_divider
    (
     .CLK(CLK),
     .RST(RST),
     .in_a(div_in),
     .in_b(NUM_POINTS),
     .enable(div_en),
     .rslt(rslt),
     .mod(),
     .valid(valid)
     );
  
endmodule

//------------------------------------------------------------------------------
module Divider #
  (
   parameter W_D = 32
   )
  (
   input CLK,
   input RST,
   input [W_D-1:0] in_a,
   input [W_D-1:0] in_b,
   input enable,
   output reg [W_D-1:0] rslt,
   output reg [W_D-1:0] mod,
   output reg valid
   );

  localparam DEPTH = W_D + 1;
  
  function getsign;
    input [W_D-1:0] in;
    getsign = in[W_D-1]; //0: positive, 1: negative
  endfunction

  function is_positive;
    input [W_D-1:0] in;
    is_positive = (getsign(in) == 0);
  endfunction
    
  function [W_D-1:0] complement2;
    input [W_D-1:0] in;
    complement2 = ~in + {{(W_D-1){1'b0}}, 1'b1};
  endfunction
    
  function [W_D*2-1:0] complement2_2x;
    input [W_D*2-1:0] in;
    complement2_2x = ~in + {{(W_D*2-1){1'b0}}, 1'b1};
  endfunction
    
  function [W_D-1:0] absolute;
    input [W_D-1:0] in;
    begin
      if(getsign(in)) //Negative
        absolute = complement2(in);
      else //Positive
        absolute = in;
    end
  endfunction

  wire [W_D-1:0] abs_in_a;
  wire [W_D-1:0] abs_in_b;
  assign abs_in_a = absolute(in_a);
  assign abs_in_b = absolute(in_b);

  genvar d;
  generate 
    for(d=0; d<DEPTH; d=d+1) begin: s_depth
      reg stage_valid;
      reg in_a_positive;
      reg in_b_positive;
      reg [W_D*2-1:0] dividend;
      reg [W_D*2-1:0] divisor;
      reg [W_D*2-1:0] stage_rslt;

      wire [W_D*2-1:0] sub_value;
      wire is_large;
      assign sub_value = dividend - divisor;
      assign is_large = !sub_value[W_D*2-1];
      
      if(d == 0) begin 
        always @(posedge CLK) begin
          if(RST) begin
            stage_valid   <= 0;
            in_a_positive <= 0;
            in_b_positive <= 0;          
          end else begin
            stage_valid   <= enable;
            in_a_positive <= is_positive(in_a);
            in_b_positive <= is_positive(in_b);
          end
        end
      end else begin
        always @(posedge CLK) begin
          if(RST) begin
            stage_valid   <= 0;
            in_a_positive <= 0;
            in_b_positive <= 0;
          end else begin
            stage_valid   <= s_depth[d-1].stage_valid;
            in_a_positive <= s_depth[d-1].in_a_positive;
            in_b_positive <= s_depth[d-1].in_b_positive;
          end
        end
      end
      
      if(d==0) begin
        always @(posedge CLK) begin
          dividend <= abs_in_a;
          divisor <= abs_in_b << (W_D-1);
          stage_rslt <= 0;
        end
      end else begin
        always @(posedge CLK) begin
          dividend <= s_depth[d-1].is_large? s_depth[d-1].sub_value : s_depth[d-1].dividend;
          divisor <= s_depth[d-1].divisor >> 1;
          stage_rslt <= {s_depth[d-1].stage_rslt, s_depth[d-1].is_large};
        end
      end
    end
  endgenerate
  
  always @(posedge CLK) begin
    if(RST) begin
      valid <= 0;
    end else begin
      valid <= s_depth[DEPTH-1].stage_valid;
    end
  end
    
  always @(posedge CLK) begin
    rslt <= (s_depth[DEPTH-1].in_a_positive && s_depth[DEPTH-1].in_b_positive)?
            s_depth[DEPTH-1].stage_rslt:
            (!s_depth[DEPTH-1].in_a_positive && s_depth[DEPTH-1].in_b_positive)?
            complement2_2x(s_depth[DEPTH-1].stage_rslt):
            (s_depth[DEPTH-1].in_a_positive && !s_depth[DEPTH-1].in_b_positive)?
            complement2_2x(s_depth[DEPTH-1].stage_rslt):
            (!s_depth[DEPTH-1].in_a_positive && !s_depth[DEPTH-1].in_b_positive)?
            s_depth[DEPTH-1].stage_rslt:
            'hx;
    mod  <= (s_depth[DEPTH-1].in_a_positive && s_depth[DEPTH-1].in_b_positive)?
            s_depth[DEPTH-1].dividend[W_D-1:0]:
            (!s_depth[DEPTH-1].in_a_positive && s_depth[DEPTH-1].in_b_positive)?
            complement2_2x(s_depth[DEPTH-1].dividend[W_D-1:0]):
            (s_depth[DEPTH-1].in_a_positive && !s_depth[DEPTH-1].in_b_positive)?
            s_depth[DEPTH-1].dividend[W_D-1:0]:            
            (!s_depth[DEPTH-1].in_a_positive && !s_depth[DEPTH-1].in_b_positive)?
            complement2_2x(s_depth[DEPTH-1].dividend[W_D-1:0]):
            'hx;
  end
endmodule

module Adder3 #
  (
   parameter W_D = 32
   )
  (
   input CLK,
   input RST,
   input [W_D-1:0] in0,
   input [W_D-1:0] in1,
   input [W_D-1:0] in2,
   input enable,
   output reg [W_D-1:0] rslt,
   output reg valid
   );

  wire [W_D-1:0] t0;
  wire [W_D-1:0] t1;
  wire [W_D-1:0] t2;
  
  reg [W_D-1:0] r0;
  reg [W_D-1:0] r1;
  reg [W_D-1:0] r2;
  
  reg [W_D-1:0] sum_0_1;
  reg [W_D-1:0] sum_2;
  reg d_enable;
  reg dd_enable;

  assign t0 = in0;
  assign t1 = in1;
  assign t2 = in2;
  
  always @(posedge CLK) begin
    if(RST) begin
      d_enable <= 0;
      dd_enable <= 0;
      valid <= 0;
    end else begin
      d_enable <= enable;
      dd_enable <= d_enable;
      valid <= dd_enable;
    end
  end

  always @(posedge CLK) begin
    r0 <= t0;
    r1 <= t1;
    r2 <= t2;
    sum_0_1 <= r0 + r1;
    sum_2 <= r2;
    rslt <= sum_0_1 + sum_2;
  end
  
endmodule

