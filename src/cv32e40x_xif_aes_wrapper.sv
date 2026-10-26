module xif_aes_wrapper import aes_pkg::*;
#(
  parameter int          X_ID_WIDTH      =  4,  // Width of ID field.
  parameter int          X_RFR_WIDTH     =  32, // Register file read access width for the eXtension interface
  parameter logic [ 1:0] X_ECS_XS        =  '0, // Default value for mstatus.XS
  parameter int          PROTECTED       =   1,
  parameter int          PIPELINE_STAGES =   5, //Number of instructions wrapper can hold

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
    typedef struct packed {
        logic [X_ID_WIDTH-1:0] instr_id;
        logic [4:0] rd_adr;
        logic kill;
    } id_rd_packet_t;

    //OUTPUT logic
    logic ready_for_aes_output;
    logic wrapper_output_valid;
    logic output_committed, output_retire;

    //FIFO accept
    logic fifo_full_acc_instr, fifo_empty_acc_instr;
    logic fifo_push_acc_instr, fifo_pop_acc_instr;
    id_rd_packet_t fifo_data_push_acc_instr_i;
    id_rd_packet_t fifo_data_pop_acc_instr_o;
    logic [ADDR_DEPTH:0] fifo_cnt_acc_instr;

    // FIFO commit
    logic commit_matches_accepted, commit_matches_issue;

    logic fifo_full_commit, fifo_empty_commit;
    logic fifo_push_commit, fifo_pop_commit;
    id_rd_packet_t fifo_data_push_commit_i;
    id_rd_packet_t fifo_data_pop_commit_o;
    logic [ADDR_DEPTH:0] fifo_cnt_commit;

    // Input logic
    logic decrypt_i, encrypt_i, decrypt_middle_i, encrypt_middle_i;
    logic [X_ID_WIDTH-1:0]  aes_instr_id_o;
    logic [X_RFR_WIDTH-1:0] result_aes_o;
    logic [25:0] randombits;

    //Valid and ready for input and output
    logic valid_aes_input,  ready_aes_input;
    logic valid_aes_output;
    logic issue_ready;
    logic is_aes_instr, operands_valid, wrapper_has_space;

    //Instruction information
    logic [4:0] xif_rd_adr;
    logic [6:0] xif_opcode;
    logic [2:0] xif_func3;
    logic [4:0] xif_func5;
    logic [1:0] xif_byte_select;

    assign randombits = 26'h02;

    // Data taken from the instruction itself
    assign xif_byte_select = xif_issue.issue_req.instr[31:30];
    assign xif_func5       = xif_issue.issue_req.instr[29:25];
    assign xif_func3       = xif_issue.issue_req.instr[14:12];
    assign xif_rd_adr      = xif_issue.issue_req.instr[11: 7];
    assign xif_opcode      = xif_issue.issue_req.instr[ 6: 0];

    always_comb
    begin : DECODE_AES_INSTR
        decrypt_i        = 1'b0;
        decrypt_middle_i = 1'b0;
        encrypt_i        = 1'b0;
        encrypt_middle_i = 1'b0;
        case(aes_func5_e'(xif_func5))
            AES32DSI:  decrypt_i        = 1'b1;
            AES32DSMI: decrypt_middle_i = 1'b1;
            AES32ESI:  encrypt_i        = 1'b1;
            AES32ESMI: encrypt_middle_i = 1'b1;
            default: ;
        endcase
    end

    assign is_aes_instr = (xif_opcode == AES32) && (xif_func3 == AES32_FUNC3) &&
                          (decrypt_i || decrypt_middle_i || encrypt_i || encrypt_middle_i);

    assign operands_valid    = xif_issue.issue_req.rs_valid[0] && xif_issue.issue_req.rs_valid[1];
    assign wrapper_has_space = (fifo_cnt_acc_instr + fifo_cnt_commit) < PIPELINE_STAGES;

    // Instructions that are not AES are rejected right away. AES instructions are held
    // until both operands are valid and the wrapper can track one more instruction.
    assign issue_ready     = !is_aes_instr || (operands_valid && ready_aes_input && wrapper_has_space);
    assign valid_aes_input = xif_issue.issue_valid && issue_ready && is_aes_instr;

    //XIF Issue interface
    assign xif_issue.issue_ready = issue_ready;

    // XIF issue interface response
    assign xif_issue.issue_resp.accept    = is_aes_instr;
    assign xif_issue.issue_resp.writeback = is_aes_instr;
    assign xif_issue.issue_resp.dualwrite = 'b0;
    assign xif_issue.issue_resp.dualread  = 'b0;
    assign xif_issue.issue_resp.loadstore = 'b0;
    assign xif_issue.issue_resp.ecswrite  = 'b0;
    assign xif_issue.issue_resp.exc       = 'b0;

    //Push data into accept instruction FIFO
    assign fifo_data_push_acc_instr_i = '{instr_id: xif_issue.issue_req.id, rd_adr: xif_rd_adr, kill: 1'b0};

    // Commits arrive in program order, so a commit can only belong to the oldest accepted
    // instruction, or to the instruction being issued in the same cycle when none is waiting.
    always_comb
    begin : COMMIT_FIFO_LOGIC
        commit_matches_accepted = 1'b0;
        commit_matches_issue    = 1'b0;

        if(xif_commit.commit_valid) begin
            if(!fifo_empty_acc_instr)
                commit_matches_accepted = fifo_data_pop_acc_instr_o.instr_id == xif_commit.commit.id;
            else
                commit_matches_issue    = valid_aes_input && (xif_issue.issue_req.id == xif_commit.commit.id);
        end

        fifo_push_acc_instr = valid_aes_input && !commit_matches_issue;
        fifo_pop_acc_instr  = commit_matches_accepted;
        fifo_push_commit    = commit_matches_accepted || commit_matches_issue;

        fifo_data_push_commit_i      = commit_matches_issue ? fifo_data_push_acc_instr_i : fifo_data_pop_acc_instr_o;
        fifo_data_push_commit_i.kill = xif_commit.commit.commit_kill;
    end

    // The AES pipeline is in order, so the instruction at its output is the oldest one in
    // flight. It may only leave the pipeline once it has been committed.
    always_comb
    begin : OUTPUT_STAGE_LOGIC
        output_committed     = valid_aes_output && !fifo_empty_commit;
        wrapper_output_valid = output_committed && !fifo_data_pop_commit_o.kill;
        output_retire        = output_committed && (fifo_data_pop_commit_o.kill || xif_result.result_ready);

        fifo_pop_commit      = output_retire;
        ready_for_aes_output = !valid_aes_output || output_retire;
    end

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


cv32e40x_fifo #(
     .DEPTH(PIPELINE_STAGES),
     .dtype(id_rd_packet_t)
)
accepted_instruction_fifo_i
(
    .clk_i(clk_i),
    .rst_ni(rst_n),
    .flush_i(1'b0),
    .flush_but_first_i(1'b0),
    .testmode_i(1'b0),

    .full_o(fifo_full_acc_instr),
    .empty_o(fifo_empty_acc_instr),
    .cnt_o(fifo_cnt_acc_instr),

    .data_i(fifo_data_push_acc_instr_i),
    .push_i(fifo_push_acc_instr),

    .data_o(fifo_data_pop_acc_instr_o),
    .pop_i(fifo_pop_acc_instr)
);

cv32e40x_fifo #(
     .DEPTH(PIPELINE_STAGES),
     .dtype(id_rd_packet_t)
)
commited_instruction_fifo_i
(
    .clk_i(clk_i),
    .rst_ni(rst_n),
    .flush_i(1'b0),
    .flush_but_first_i(1'b0),
    .testmode_i(1'b0),

    .full_o(fifo_full_commit),
    .empty_o(fifo_empty_commit),
    .cnt_o(fifo_cnt_commit),

    .data_i(fifo_data_push_commit_i),
    .push_i(fifo_push_commit),

    .data_o(fifo_data_pop_commit_o),
    .pop_i(fifo_pop_commit)
);



endmodule  // xif_aes_wrapper
