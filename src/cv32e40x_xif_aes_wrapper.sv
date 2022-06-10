module cv32e40x_xif_aes_wrapper import cv32e40x_pkg::*;
#(
  parameter int          X_ID_WIDTH      =  4,  // Width of ID field.
  parameter int          X_RFR_WIDTH     =  32, // Register file read access width for the eXtension interface
  parameter logic [ 1:0] X_ECS_XS        =  '0, // Default value for mstatus.XS
  parameter int          PROTECTED       =   1,
  parameter int          PIPELINE_STAGES =   5 //Number of instructions wrapper can hold
  
  // DONT MODIFY
  parameter int unsigned ADDR_DEPTH = (PIPELINE_STAGES > 1) ? $clog2(PIPELINE_STAGES) : 1
)
(
  input  logic          clk_i,
  input  logic          rst_n,

  // eXtension interface
  if_xif.coproc_issue       xif_issue,         // Issue interface
  if_xif.coproc_commit      xif_commit,        // Commit Interface
  if_xif.coproc_result      xif_result         // Result interface
);
    //Output logic
    logic enable_output_registers;
    logic ready_for_aes_output;


    //OUTPUT logic
    logic wrapper_output_valid;

    //FIFO accept
    logic fifo_flush, fifo_flush_but_first, test_mode;
    logic fifo_full_acc_instr, fifo_empty_acc_instr;
    logic fifo_push_acc_instr, fifo_pop_acc_instr;
    id_rd_packet_t fifo_data_push_acc_instr_i;
    id_rd_packet_t fifo_data_pop_acc_instr_o;
    logic [ADDR_DEPTH:0] fifo_cnt_acc_instr;

    // FIFO commit
    logic id_match;

    logic fifo_full_commit, fifo_empty_commit;
    logic fifo_push_commit, fifo_pop_commit;
    id_rd_packet_t fifo_data_pop_commit_o;
    logic [ADDR_DEPTH:0] fifo_cnt_commit;

    // Input logic
    logic valid_i, decrypt_i, encrypt_i, decrypt_middle_i, encrypt_middle_i;
    logic [X_ID_WIDTH-1:0]  aes_instr_id_o, instr_id_i;
    logic [X_RFR_WIDTH-1:0]  instr_i, result_aes_o;
    logic [25:0] randombits;

    //Valid and ready for input and output
    logic valid_aes_input,  ready_aes_input;
    logic valid_aes_output, ready_aes_output;
    logic issue_ready;

    //Instruction information
    logic [4:0] xif_rd_adr;
    logic [6:0] xif_opcode;
    logic [1:0] xif_byte_select;

    assign randombits = 32'h02;

    //XIF Issue interface
    assign xif_issue.issue_ready = issue_ready;
    assign issue_ready = !valid_aes_input || ready_aes_input;


    // XIF issue interface response
    assign xif_issue.issue_resp.accept    = valid_aes_input;
    assign xif_issue.issue_resp.writeback = 'b1;
    assign xif_issue.issue_resp.dualwrite = 'b0;
    assign xif_issue.issue_resp.dualread  = 'b0;
    assign xif_issue.issue_resp.loadstore = 'b0;
    assign xif_issue.issue_resp.ecswrite  = 'b0;
    assign xif_issue.issue_resp.exc       = 'b0;

    // XIF result interface
    assign xif_result.result_valid   = wrapper_output_valid;
    assign xif_result.result.data    = result_aes_o;
    assign xif_result.result.rd      = fifo_data_pop_commit_o.rd_adr;
    assign xif_result.result.id      = aes_instr_id_o;
    assign xif_result.result.we      = 1'b1;
    assign xif_result.result.ecswe   =  '0;
    assign xif_result.result.ecsdata =  '0;
    assign xif_result.result.exc     =  '0;
    assign xif_result.result.exccode =  '0;


    // Data taken from the instruction itself
    assign xif_byte_select = xif_issue.issue_req.instr[31:30];
    assign xif_rd_adr      = xif_issue.issue_req.instr[11: 7];
    assign xif_opcode      = xif_issue.issue_req.instr[ 6: 0];


    //Push data into accept instruction FIFO
    assign fifo_data_push_acc_instr_i = {xif_issue.issue_req.id, xif_rd_adr, 1'b0};
    assign fifo_push_acc_instr        = valid_aes_input;

    always_comb 
    begin : ACCEPT_INSTRUCTION
        valid_aes_input = 'b0;

        if(xif_opcode == AES32) begin
            if(xif_issue.issue_valid && issue_ready && (xif_issue.issue_req.rs_valid[0] && xif_issue.issue_req.rs_valid[1]))
                valid_aes_input = 'b1;
        end    
    end

    always_comb
    begin : ONEHOT_AES_INSTR_TYPE
        decrypt_i        = 1'b0;
        decrypt_middle_i = 1'b0;
        encrypt_i        = 1'b0;
        encrypt_middle_i = 1'b0;
        unique case(xif_issue.issue_req.instr[29:25])
            AES32DSI:  decrypt_i        = 1'b1;
            AES32DSMI: decrypt_middle_i = 1'b1;
            AES32ESI:  encrypt_i        = 1'b1;
            AES32ESMI: encrypt_middle_i = 1'b1;
            default:  encrypt_middle_i  = 1'b0; //Removes simulation warning
        endcase
    end


    always_comb 
    begin : COMMIT_FIFO_LOGIC
        fifo_push_commit    = 1'b0;
        id_match            = 1'b0; 
        fifo_pop_acc_instr  = 1'b0;

        if(!fifo_empty_acc_instr)
            if(fifo_data_pop_acc_instr_o.instr_id == xif_commit.commit.id)
                id_match = 'b1;

        if(xif_commit.commit_valid && id_match) begin
            fifo_push_commit   = 1'b1;
            fifo_pop_acc_instr = 1'b1;
        end
    end

    logic id_match_output;
    logic pop_commit_fifo;
    assign pop_commit_fifo = id_match_output;

    always_comb 
    begin : OUTPUT_STAGE_LOGIC
        // Accept new data in output stage?
        ready_for_aes_output = 1'b0;
        wrapper_output_valid = 1'b0;
        id_match_output      = 1'b0;

        if(aes_instr_id_o == fifo_data_pop_commit_o.instr_id)
            id_match_output = 1'b1;

        if(id_match_output && valid_aes_output && !fifo_data_pop_commit_o.kill)
            wrapper_output_valid = 1'b1;

        // Is output stage ready for new output            
        if(!wrapper_output_valid || xif_result.result_ready )
            ready_for_aes_output = 1'b1;
    end



        riscv_crypto_fu_saes32_protected
        #(
            .X_ID_WIDTH(X_ID_WIDTH)
        )
        aes_prot_i
        (
            .clk_i(clk_i)                       ,
            .rst_n(rst_n)                       ,
            .valid_i(valid_aes_input)           ,
            .ready_i(ready_aes_input)           ,

            .rs1_i(xif_issue.issue_req.rs[0])   , 
            .rs2_i(xif_issue.issue_req.rs[1])   , 
            .randombits_i(randombits)           ,
            .instr_id_i(xif_issue.issue_req.id) ,
            .bs_i(xif_byte_select)              ,

            .op_saes32_decs(decrypt_i)          ,
            .op_saes32_decsm(decrypt_middle_i)  ,
            .op_saes32_encs(encrypt_i)          ,
            .op_saes32_encsm(encrypt_middle_i)  ,

            .result_o(result_aes_o)             ,
            .instr_id_o(aes_instr_id_o)         ,
            .valid_o(valid_aes_output)          ,
            .ready_o(ready_for_aes_output)
        );



//Reassign commit kill signal for commit instruction FIFO
id_rd_packet_t accept_commit_kill;
assign accept_commit_kill.rd_adr   = fifo_data_pop_acc_instr_o.rd_adr;
assign accept_commit_kill.instr_id = fifo_data_pop_acc_instr_o.instr_id;
assign accept_commit_kill.kill     = xif_commit.commit.commit_kill;


cv32e40x_fifo #(
     .DEPTH(1)
)
accepted_instruction_fifo_i
(
    .clk_i(clk_i),  
    .rst_ni(rst_n),  
    .flush_i(fifo_flush),
    .flush_but_first_i(fifo_flush_but_first),
    .testmode_i(test_mode),

    .full_o(fifo_full_acc_instr),
    .empty_o(fifo_empty_acc_instr),
    .cnt_o(fifo_cnt_acc_instr),

    .data_i(fifo_data_push_acc_instr_i),
    .push_i(fifo_push_acc_instr),

    .data_o(fifo_data_pop_acc_instr_o),
    .pop_i(fifo_pop_acc_instr)
);

cv32e40x_fifo #(
     .DEPTH(PIPELINE_STAGES)
)
commited_instruction_fifo_i
(
    .clk_i(clk_i),
    .rst_ni(rst_n),
    .flush_i(fifo_flush),
    .flush_but_first_i(fifo_flush_but_first),
    .testmode_i(test_mode), 

    .full_o(fifo_full_commit),
    .empty_o(fifo_empty_commit),
    .cnt_o(fifo_cnt_commit),

    .data_i(accept_commit_kill),
    .push_i(fifo_push_commit),

    .data_o(fifo_data_pop_commit_o),
    .pop_i(pop_commit_fifo)                
);



endmodule  // cv32e40x_xif_aes_wrapper