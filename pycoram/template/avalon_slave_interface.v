
module avalon_slave_interface #
  (
   //------------------------------------------------------------------------------
   // Avalon Parameter
   //------------------------------------------------------------------------------
   parameter integer C_AVS_ADDR_WIDTH = 32,
   parameter integer C_AVS_DATA_WIDTH = 32
   )
  (
   //----------------------------------------------------------------------------
   // Common Clock
   //----------------------------------------------------------------------------
   input wire ACLK,
   input wire ARESETN,

   //----------------------------------------------------------------------------
   // User Bus Interface
   //----------------------------------------------------------------------------
   // Write Address
   output wire [C_AVS_ADDR_WIDTH-1:0]   awaddr,
   output wire [8-1:0]                  awlen,
   output wire                          awvalid,
   input wire                           awready,
  
   // Write Data
   output wire [C_AVS_DATA_WIDTH-1:0]   wdata,
   output wire [C_AVS_DATA_WIDTH/8-1:0] wstrb,
   output wire                          wlast,
   output wire                          wvalid,
   input wire                           wready,

   // Read Address
   output wire [C_AVS_ADDR_WIDTH-1:0]   araddr,
   output wire [8-1:0]                  arlen,
   output wire                          arvalid,
   input wire                           arready,

   // Read Data
   input wire  [C_AVS_DATA_WIDTH-1:0]   rdata,
   input wire                           rlast,
   input wire                           rvalid,
   output wire                          rready,

   //----------------------------------------------------------------------------
   // Avalon Slave Interface
   //----------------------------------------------------------------------------
   // Common
   input  wire [C_AVS_ADDR_WIDTH-1:0]   avs_address,
   output wire                          avs_waitrequest,
   input  wire [C_AVS_DATA_WIDTH/8-1:0] avs_byteenable,
   input  wire [8:0]                    avs_burstcount,
   
   // Read
   input  wire                          avs_read,
   output wire [C_AVS_DATA_WIDTH-1:0]   avs_readdata,
   output wire                          avs_readdatavalid,

   // Write
   input  wire                          avs_write,
   input  wire [C_AVS_DATA_WIDTH-1:0]   avs_writedata
   );

  //----------------------------------------------------------------------------
  // Reset logic
  //----------------------------------------------------------------------------
  reg aresetn_r;
  reg aresetn_rr;
  reg aresetn_rrr;

  always @(posedge ACLK) begin
    aresetn_r <= ARESETN;
    aresetn_rr <= aresetn_r;
    aresetn_rrr <= aresetn_rr;
  end

  //------------------------------------------------------------------------------
  // User-logic Interface
  //------------------------------------------------------------------------------
  reg write_busy;
  reg [8:0] write_count;

  // Write Address
  assign awvalid = avs_write && !write_busy;
  assign awaddr = avs_address;
  assign awlen = avs_burstcount - 1;

  // Write Data
  assign wdata = avs_writedata;
  assign wstrb = avs_byteenable;
  assign wlast = 1'b0;
  assign wvalid = avs_write;

  // Read Address
  assign arvalid = avs_read && !write_busy;
  assign araddr = avs_address;
  assign arlen = avs_burstcount - 1;

  // Read Data
  assign rready = 1'b1;
  
  //------------------------------------------------------------------------------
  // Avalon Interface
  //------------------------------------------------------------------------------
  // Common
  assign avs_waitrequest = ((awvalid || wvalid) && !(awready && wready)) ||
                           (arvalid && !arready);
    
  // Read
  assign avs_readdata = rdata;
  assign avs_readdatavalid = rvalid;
  
  //------------------------------------------------------------------------------
  always @(posedge ACLK) begin
    if (aresetn_rrr == 0) begin
      write_busy <= 0;
      write_count <= 0;
    end else if(write_busy) begin
      if(!avs_waitrequest && avs_write) begin
        write_count <= write_count - 1;
        if(write_count == 1) begin
          write_busy <= 0;
        end
      end
    end else begin
      if(!avs_waitrequest && awvalid && wvalid) begin
        write_count <= awlen;
        if(awlen == 0) write_busy <= 0;
        else write_busy <= 1;
      end
    end
  end
  
endmodule

