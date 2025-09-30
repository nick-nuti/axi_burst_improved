

module vertex_input_ip #(
    parameter DRAM_DATA_W,

    parameter DRAM_AXIBURST_ADDR_W,
    parameter DRAM_AXIBURST_DATA_W,
    parameter DRAM_AXIBURST_DATA_W_BYTES,  // # of bytes in a burst beat
    parameter DRAM_AXIBURST_MAX_BURST_LEN, // # of beats in a burst read
    parameter DRAM_AXIBURST_MEM_BOUNDARY   // must recognize boundary and split commands that cross boundary
)
(
// General
    input logic clk,
    input logic aresetn,

// Configuration Signals
    input  logic START_PULSE,
    input  logic SOFT_RESET_PULSE,             // flush vertex input ip pipeline

    output logic [5-1:0] GENERAL_STATUS_RO,    //{error:RO, done:RO, active:RO, busy:RO, ready_for_input:RO}
    output logic [32-1:0] ERROR_CMD_ID_RO,
    output logic [1-1:0]  ERROR_PENDING_W1C_IN, 
    input  logic [1-1:0]  ERROR_PENDING_W1C_CLR,   
    output logic [32-1:0] DONE_CMD_ID_RO,
    output logic [1-1:0]  DONE_PENDING_W1C_IN, 
    input  logic [1-1:0]  DONE_PENDING_W1C_CLR,    

// unsure of how to use
    //input  logic [2-1:0] IRQ_ENABLE_RW,         // {done_irq_en, error_irq_en}
    //input  logic [2-1:0] IRQ_STATUS_W1C_IN, 
    //output logic [2-1:0] IRQ_STATUS_W1C_CLR,

// Draw type
    input logic [1:0] DRAW_TYPE_RW, // 0 = DIRECT NI, 1 = DIRECT I, 2 = INDIRECT NI, 3 = INDIRECT I

// Vertex buffer
    input  logic [DRAM_DATA_W-1:0]  VERTEX_BUFFER_BASE_ADDRESS,
    input  logic [16-1:0]           VERTEX_STRIDE_BYTES,

// Index buffer
    input  logic [DRAM_DATA_W-1:0] INDEX_BUFFER_BASE_ADDRESS,
    input  logic [2-1:0] INDEX_TYPE,            // 0 =16 bit, 1 = 32 bit, 2 = 8 bit

// Metadata
    input  logic [4-1:0] PRIMITIVE_TOPOLOGY_RW, // here: https://registry.khronos.org/vulkan/specs/latest/man/html/VkPrimitiveTopology.html ; 11 kinds in vulkan
    input  logic [16-1:0] ATTR_LAYOUT_ID_RW,    // here: https://registry.khronos.org/vulkan/specs/latest/man/html/VkVertexInputAttributeDescription.html ; user defined
    input  logic [32-1:0] CMD_ID_RW,            // cp-generated ID per draw call

// Direct Draw (non-indexed)
    input  logic [32-1:0] DIRECT_VERTEXCOUNT_RW,
    input  logic [32-1:0] DIRECT_FIRSTVERTEX_RW,

// Direct Draw (indexed)
    input  logic [32-1:0] DIRECT_INDEXCOUNT_RW,
    input  logic [32-1:0] DIRECT_FIRSTINDEX_RW,
    input  logic [32-1:0] DIRECT_BASEVERTEX_RW,

// Direct Draw (common)
    input  logic [32-1:0] DIRECT_INSTANCECOUNT_RW,
    input  logic [32-1:0] DIRECT_BASEINSTANCE_RW,

// Indirect + Multi-Draw Indirect
    input  logic [DRAM_DATA_W-1:0] INDIRECT_BASE_ADDRESS_RW,
    input  logic [32-1:0] INDIRECT_BASE_OFFSET_BYTES_RW,
    input  logic [32-1:0] INDIRECT_SIZE_BYTES_RW,
    input  logic [32-1:0] INDIRECT_STRIDE_BYTES_RW,
    input  logic [32-1:0] INDIRECT_COUNT_RW,

// Indirect field offset (non-indexed)
    input  logic [8-1:0] OFFSET_N_VERTEXCOUNT_RW,
    input  logic [8-1:0] OFFSET_N_INSTANCECOUNT_RW,
    input  logic [8-1:0] OFFSET_N_FIRSTVERTEX_RW,
    input  logic [8-1:0] OFFSET_N_BASEINSTANCE_RW,

// Indirect field offset (indexed)
    input  logic [8-1:0] OFFSET_I_INDEXCOUNT_RW,
    input  logic [8-1:0] OFFSET_I_INSTANCECOUNT_RW,
    input  logic [8-1:0] OFFSET_I_FIRSTINDEX_RW,
    input  logic [8-1:0] OFFSET_I_BASEVERTEX_RW,
    input  logic [8-1:0] OFFSET_I_BASEINSTANCE_RW,

// AXI-BURST Signals
    input wire                           axi_clk,
    input wire                           axi_resetn
    output reg [ADDR_W-1:0]              m_axi_araddr, // address
    output reg [3-1:0]                   m_axi_arprot, // protection - privilege and securit level of transaction
    output reg                           m_axi_arvalid, // 
    input  wire                          m_axi_arready, // 
    output reg [3-1:0]                   m_axi_arsize, //3'b011, // burst size - size of each transfer in the burst 3'b011 for 8 bytes
    output reg [2-1:0]                   m_axi_arburst, // fixed burst = 00, incremental = 01, wrapped burst = 10
    output reg [4-1:0]                   m_axi_arcache, //4'b0011, // cache type - how transaction interacts with caches
    output reg [8-1:0]                   m_axi_arlen, // number of data transfers in the burst (0-255) (done)
    output reg [1-1:0]                   m_axi_arlock, // lock type - indicates if transaction is part of locked sequence
    output reg [4-1:0]                   m_axi_arqos, // quality of service - transaction indication of priority level
    output reg [4-1:0]                   m_axi_arregion, // region identifier - identifies targetted region
    output reg                           m_axi_rready, // read ready - 0 = not ready, 1 = ready
    input  wire [DATA_W-1:0]             m_axi_rdata, // 
    input  wire                          m_axi_rvalid, // read response valid - 0 = response not valid, 1 = response is valid
    input  wire                          m_axi_rlast, // =1 when on last read
    input  wire [2-1:0]                  m_axi_rresp // read response - status of the read transaction (00 = okay, 01 = exokay, 10 = slverr, 11 = decerr)
);

// fsm signals
    typedef enum {
        IDLE,
        INIT,
        DIRECT_NON_INDEXED,
        DIRECT_INDEXED,
        INDIRECT_NON_INDEXED,
        INDIRECT_INDEXED,
        DONE,
        ERROR
    } viip_fsm_enum;

    viip_fsm_enum viip_fsm_cs, viip_fsm_ns;

    // FSM for sub loops
    typedef enum {
        IDLE,
        INDIRECT_COMMAND_COUNT,
        INSTANCE_COUNT,
        ELEMENT_COUNT, // this includes index fetch to fill fifo if draw is indexed
        DONE
    } sub_fsm_enum;

    sub_fsm_enum sub_fsm_cs, sub_fsm_ns;

// regfile pulse signals
    wire start_pulse_wire, start_pulse_posedge_wire;
    wire reset_pulse_wire, reset_pulse_posedge_wire;

    logic start_pulse_reg;
    logic reset_pulse_reg;

    assign start_pulse_wire = START_PULSE;
    assign reset_pulse_wire = SOFT_RESET_PULSE;

    always @ (posedge clk)
    begin
        if(~aresetn)
        begin
            start_pulse_reg <= 'h0;
            reset_pulse_reg <= 'h0;
        end
       
        else
        begin
            start_pulse_reg <= start_pulse_wire;
            reset_pulse_reg <= reset_pulse_wire;
        end
    end

    // posedge detection
    assign start_pulse_posedge_wire = (start_pulse_wire && ~start_pulse_reg);
    assign reset_pulse_posedge_wire = (reset_pulse_wire && ~reset_pulse_reg);

// regfile w1c signals
    logic error_pending_ff;
    logic done_pending_ff;

    always @ (posedge clk)
    begin
        if(~aresetn)
        begin
            error_pending_ff <= 'h0;
            done_pending_ff <= 'h0;
        end

        else
        begin
            if(ERROR_PENDING_W1C_IN)        error_pending_ff <= 0;
            else if(viip_fsm_cs == ERROR)   error_pending_ff <= 1;
            else                            error_pending_ff <= error_pending_ff;


            if(DONE_PENDING_W1C_IN)         done_pending_ff <= 0;
            else if(viip_fsm_cs == DONE)    done_pending_ff <= 1;
            else                            done_pending_ff <= done_pending_ff;

        end
    end

    assign ERROR_PENDING_W1C_CLR    = error_pending_ff;
    assign DONE_PENDING_W1C_CLR     = done_pending_ff;

// ro status signals out to register file
    logic error_status_ff;
    logic done_status_ff;
    logic active_status_ff;
    logic busy_status_ff;
    logic ready_for_input_ff;

    logic [32-1:0] last_error_cmd_id_ff;
    logic [8-1:0]  error_type_ff;
    logic [32-1:0] last_done_cmd_id_ff;


    assign GENERAL_STATUS_RO        = {error_status_ff, done_status_ff, active_status_ff, busy_status_ff, ready_for_input_ff};
    assign ERROR_CMD_ID_RO          = last_error_cmd_id_ff;
    assign DONE_CMD_ID_RO           = last_done_cmd_id_ff;

// REG FILE <-> internal flip flops
    logic [1:0]             draw_type_ff;
    logic [DRAM_DATA_W-1:0] vertex_buffer_base_address_ff;
    logic [16-1:0]          vertex_stride_bytes_ff;

    logic [DRAM_DATA_W-1:0] index_buffer_base_address_ff;
    logic [2-1:0]           index_type_ff;

    logic [4-1:0]           primitive_topology_ff;
    logic [16-1:0]          attr_layout_id_ff;
    logic [32-1:0]          cmd_id_ff;

    logic [32-1:0]          direct_vertexcount_ff;
    logic [32-1:0]          direct_firstvertex_ff;

    logic [32-1:0]          direct_indexcount_ff;
    logic [32-1:0]          direct_firstindex_ff;
    logic signed [32-1:0]   direct_basevertex_ff;

    logic [32-1:0]          direct_instancecount_ff;
    logic [32-1:0]          direct_baseinstance_ff;

    logic [DRAM_DATA_W-1:0] indirect_base_address_ff;
    logic [32-1:0]          indirect_base_offset_bytes_ff;
    logic [32-1:0]          indirect_size_bytes_ff;
    logic [32-1:0]          indirect_stride_bytes_ff;
    logic [32-1:0]          indirect_count_ff;

    logic [8-1:0]           offset_n_vertexcount_ff;
    logic [8-1:0]           offset_n_instancecount_ff;
    logic [8-1:0]           offset_n_firstvertex_ff;
    logic [8-1:0]           offset_n_baseinstance_ff;

    logic [8-1:0]           offset_i_indexcount_ff;
    logic [8-1:0]           offset_i_instancecount_ff;
    logic [8-1:0]           offset_i_firstindex_ff;
    logic [8-1:0]           offset_i_basevertex_ff;
    logic [8-1:0]           offset_i_baseinstance_ff;

    always @ (posedge clk)
    begin
        if(~aresetn)
        begin
            draw_type_ff <= 'h0;
            vertex_buffer_base_address_ff <= 'h0;
            vertex_stride_bytes_ff <= 'h0;

            index_buffer_base_address_ff <= 'h0;
            index_type_ff <= 'h0;

            primitive_topology_ff <= 'h0;
            attr_layout_id_ff <= 'h0;
            cmd_id_ff <= 'h0;

            direct_vertexcount_ff <= 'h0;
            direct_firstvertex_ff <= 'h0;

            direct_indexcount_ff <= 'h0;
            direct_firstindex_ff <= 'h0;
            direct_basevertex_ff <= 'h0;

            direct_instancecount_ff <= 'h0;
            direct_baseinstance_ff <= 'h0;

            indirect_base_address_ff <= 'h0;
            indirect_base_offset_bytes_ff <= 'h0;
            indirect_size_bytes_ff <= 'h0;
            indirect_stride_bytes_ff <= 'h0;
            indirect_count_ff <= 'h0;
                
            offset_n_vertexcount_ff <= 'h0;
            offset_n_instancecount_ff <= 'h0;
            offset_n_firstvertex_ff <= 'h0;
            offset_n_baseinstance_ff <= 'h0;

            offset_i_indexcount_ff <= 'h0;
            offset_i_instancecount_ff <= 'h0;
            offset_i_firstindex_ff <= 'h0;
            offset_i_basevertex_ff <= 'h0;
            offset_i_baseinstance_ff <= 'h0;

            error_type_ff <= 'h0;
            last_error_cmd_id_ff <= 'h0;
            last_done_cmd_id_ff <= 'h0;
        end
       
        else
        begin
// Signals driven by reg file --------------            
            if(viip_fsm_cs == IDLE && start_pulse_posedge_wire)
            begin
                draw_type_ff <= DRAW_TYPE_RW;
                vertex_buffer_base_address_ff <= VERTEX_BUFFER_BASE_ADDRESS;
                vertex_stride_bytes_ff <= VERTEX_STRIDE_BYTES;

                index_buffer_base_address_ff <= INDEX_BUFFER_BASE_ADDRESS;
                index_type_ff <= INDEX_TYPE;

                primitive_topology_ff <= PRIMITIVE_TOPOLOGY_RW;
                attr_layout_id_ff <= ATTR_LAYOUT_ID_RW;
                cmd_id_ff <= CMD_ID_RW;

                direct_vertexcount_ff <= DIRECT_VERTEXCOUNT_RW;
                direct_firstvertex_ff <= DIRECT_FIRSTVERTEX_RW;

                direct_indexcount_ff <= DIRECT_INDEXCOUNT_RW;
                direct_firstindex_ff <= DIRECT_FIRSTINDEX_RW;
                direct_basevertex_ff <= DIRECT_BASEVERTEX_RW;

                direct_instancecount_ff <= DIRECT_INSTANCECOUNT_RW;
                direct_baseinstance_ff <= DIRECT_BASEINSTANCE_RW;

                indirect_base_address_ff <= INDIRECT_BASE_ADDRESS_RW;
                indirect_base_offset_bytes_ff <= INDIRECT_BASE_OFFSET_BYTES_RW;
                indirect_size_bytes_ff <= INDIRECT_SIZE_BYTES_RW;
                indirect_stride_bytes_ff <= INDIRECT_STRIDE_BYTES_RW;
                indirect_count_ff <= INDIRECT_COUNT_RW;
                    
                offset_n_vertexcount_ff <= OFFSET_N_VERTEXCOUNT_RW;
                offset_n_instancecount_ff <= OFFSET_N_INSTANCECOUNT_RW;
                offset_n_firstvertex_ff <= OFFSET_N_FIRSTVERTEX_RW;
                offset_n_baseinstance_ff <= OFFSET_N_BASEINSTANCE_RW;

                offset_i_indexcount_ff <= OFFSET_I_INDEXCOUNT_RW;
                offset_i_instancecount_ff <= OFFSET_I_INSTANCECOUNT_RW;
                offset_i_firstindex_ff <= OFFSET_I_FIRSTINDEX_RW;
                offset_i_basevertex_ff <= OFFSET_I_BASEVERTEX_RW;
                offset_i_baseinstance_ff <= OFFSET_I_BASEINSTANCE_RW;

                // this should go below the fsm
                error_type_ff <= 'h0;
                last_error_cmd_id_ff <= 'h0;
                last_done_cmd_id_ff <= 'h0;
            end

// Signals driven by design --------------
            error_status_ff     <= error_pending_ff;
            done_status_ff      <= done_pending_ff;
            active_status_ff    <= ~((viip_fsm_cs == IDLE) | (viip_fsm_cs == ERROR) | (dmaviip_fsm_cs_cs == DONE));
            busy_status_ff      <= (viip_fsm_cs != IDLE);
            ready_for_input_ff  <= (viip_fsm_cs == IDLE); // this will change later when pipelining is added and a new sequence can start without the fsm going to idle
            
            // this should go below the fsm
            error_type_ff <= 
            last_error_cmd_id_ff <= 
            last_done_cmd_id_ff <= 
        end
    end

// FSM
    always @ (posedge clk)
    begin
        if(~aresetn)
        begin
            viip_fsm_cs <= IDLE;
        end

        else
        begin
            viip_fsm_cs <= viip_fsm_ns;
        end
    end

    always @ (*)
    begin
        case(viip_fsm_cs)
            IDLE:
            begin
                if(start_pulse_posedge_wire)
                begin
                    viip_fsm_ns = INIT;
                end
            end

            INIT:
            begin
                if(draw_type_ff == 'b00)        viip_fsm_ns = DIRECT_NON_INDEXED;
                else if(draw_type_ff == 'b01)   viip_fsm_ns = DIRECT_INDEXED;
                else if(draw_type_ff == 'b10)   viip_fsm_ns = INDIRECT_NON_INDEXED;
                else if(draw_type_ff == 'b11)   viip_fsm_ns = INDIRECT_INDEXED;
                else viip_fsm_ns = ERROR;
            end

            DIRECT_NON_INDEXED:
            begin
                if(sub_fsm_cs == DONE) viip_fsm_ns = DONE;
                else viip_fsm_ns = DIRECT_NON_INDEXED;
            end

            DIRECT_INDEXED:
            begin
                if(sub_fsm_cs == DONE) viip_fsm_ns = DONE;
                else viip_fsm_ns = DIRECT_INDEXED;
            end

            INDIRECT_NON_INDEXED:
            begin
                if(sub_fsm_cs == DONE) viip_fsm_ns = DONE;
                else viip_fsm_ns = INDIRECT_NON_INDEXED;
            end

            INDIRECT_INDEXED:
            begin
                if(sub_fsm_cs == DONE) viip_fsm_ns = DONE;
                else viip_fsm_ns = INDIRECT_INDEXED;
            end

            DONE:
            begin

            end

            ERROR:
            begin

            end

            default:
            begin
                viip_fsm_ns = IDLE;
            end
        endcase
    end

    logic nonindexed_flag;
    logic indexed_flag;
    logic direct_flag;
    logic indirect_flag;

    assign nonindexed_flag  = (viip_fsm_cs == IDLE) ? 'b0 : ~draw_type_ff[0];
    assign indexed_flag     = (viip_fsm_cs == IDLE) ? 'b0 :  draw_type_ff[0];
    assign direct_flag      = (viip_fsm_cs == IDLE) ? 'b0 : ~draw_type_ff[1];
    assign indirect_flag    = (viip_fsm_cs == IDLE) ? 'b0 :  draw_type_ff[1];

    logic indirect_command_counter_active;
    logic instance_counter_active;
    logic element_counter_active;

    logic [31:0] indirect_command_counter; // for indirect multi-draw
    logic [31:0] instance_counter; // for instancing
    logic [31:0] element_counter; // vertex count for non-indexed, index count for indexed

    logic stall_sub_fsm;

    always @ (posedge clk)
    begin
        if(~aresetn)
        begin
            sub_fsm_cs <= IDLE;
        end

        else
        begin
            sub_fsm_cs <= sub_fsm_ns;
        end
    end

    always @ (*)
    begin
        case(sub_fsm_cs)
            IDLE:
            begin
                if(viip_fsm_cs == INIT)
                begin
                    if(indirect_flag) sub_fsm_ns = INDIRECT_COMMAND_COUNT;
                    else sub_fsm_ns = INSTANCE_COUNT;
                end

                else sub_fsm_ns = IDLE;
            end

            INDIRECT_COMMAND_COUNT:
            begin
                sub_fsm_ns = INSTANCE_COUNT;
            end

            INSTANCE_COUNT:
            begin
                sub_fsm_ns = ELEMENT_COUNT;
            end

            ELEMENT_COUNT:
            begin
                if(nonindexed_flag && (element_counter < direct_vertexcount_ff))
                begin
                    sub_fsm_ns = ELEMENT_COUNT;
                end

                else if(indexed_flag && (element_counter < direct_indexcount_ff))
                begin
                    sub_fsm_ns = ELEMENT_COUNT;
                end

                else
                begin
                    if(indirect_flag && (indirect_command_counter < indirect_count_ff))
                    begin
                        sub_fsm_ns = INDIRECT_COMMAND_COUNT;
                    end

                    else if (instance_counter < direct_instancecount_ff) sub_fsm_ns = INSTANCE_COUNT;
                    else sub_fsm_ns = DONE;
                end

                else sub_fsm_ns = ELEMENT_COUNT;
            end

            DONE:
            begin
            end

            default:
            begin
                sub_fsm_ns = IDLE;
            end
        endcase
    end

    always @ (posedge clk)
    begin
        if(~aresetn)
        begin
            indirect_command_counter    <= 'h0;
            instance_counter            <= 'h0;
            element_counter             <= 'h0;
        end

        else
        begin
            if(sub_fsm_cs == IDLE)
            begin
                indirect_command_counter    <= 'h0;
                instance_counter            <= 'h0;
                element_counter             <= 'h0;
            end

            else
            begin
                if(~stall_sub_fsm)
                begin
                    if(sub_fsm_cs == INDIRECT_COMMAND_COUNT)
                    begin
                        // need to figure out how to initiate axi-read here to read the indirect command
                    end

                    if(sub_fsm_cs == INSTANCE_COUNT) instance_counter <= instance_counter + 1;

                    if(sub_fsm_cs == ELEMENT_COUNT)
                    begin
                        // need to figure out how to initiate axi-read here to read the indices
                    end
                end
            end
        end
    end

// AXI BURST MASTER
    
    

endmodule

// things to keep note of
// -> how should i handle soft reset?
// -> handling errors
// -> handling interrupts

// -> "Indexed base offsets (DIRECT_BASEVERTEX, baseVertex from indirect records) are signed 32-bit and must be treated as signed when added to index values."
//  --> when issuing indexed draw, command includes "baseVertex". for direct calls its passed explicitly: vkcmddrawindexed has 'vertexoffset', for indirect calls its part of the indirect command record: 'vkdrawindexedindirectcommand.basevertex'
//  --> for indirect indexed, 'vkdrawindexedindirectcommand.basevertex' shifts all index values read from index buffer by some constant amount before they used to fetch vertices
//  ---> basevertex is a signed 32 bit integer, it allows shifting index buffer either forward or backward relative to the vertex buffer base
//  EXAMPLE: index buffer has [0, 1, 2], baseVertex = -2 -> effective indices become [-2, -1, 0]
    // -> when fetching from vertex buffer, this means 'effective_index = index + baseVertex'
//  Actual application: negative baseVertex is useful if your index buffer is shared between meshes and you want to shift indices into a different region of the vertex buffer

// packet to send to vertex cache looks like this:
//{ vertex_addr, vertex_id, instance_id, primitive_topology, attr_layout_id, cmd_id, flags }
// NOTE: trying to think of a way to end the transmission by sending {instance_id, primitive_topology, attr_layout_id, cmd_id, flags } and instead each packet is {vertex_addr, vertex_id}
