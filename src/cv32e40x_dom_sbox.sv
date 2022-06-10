module cv32e40x_dom_sbox 
#(
    parameter int          X_ID_WIDTH      =  4  // Width of ID field.
)(
    input  wire  clk_i,
    input  wire  rst_n,
    input  wire  valid_i,
    output logic ready_for_sbox_i,
    input  wire  [X_ID_WIDTH-1:0] instr_id_i,

    input wire [7: 0] shareA_in,
    input wire [7: 0] shareB_in,
    input wire [17:0] randombits_i,

    // Additional signals to flow through pipeline
    input wire decrypt_i,
    input wire middle_round_i,
    input wire [1:0] bs_i,
    input wire [31:0] rs1_i,
    output wire decrypt_o,
    output wire middle_round_o,
    output wire [1:0] bs_o,
    output wire [31:0] rs1_o,

    // Output signals
    output logic valid_o,
    input   wire ready_for_sbox_o,
    output logic [X_ID_WIDTH-1:0] instr_id_o,
    output logic [7:0] shareA_out,
    output logic [7:0] shareB_out
);
typedef struct packed {
    logic [3:0] AA;
    logic [3:0] AB;
    logic [3:0] BB;
    logic [3:0] BA;
}gf16_mult_t;

typedef struct packed {
    logic [3:0] shareA;
    logic [3:0] shareB;
} gf16_mult_res_t;

typedef struct packed {
    logic [1:0] AA;
    logic [1:0] AB;
    logic [1:0] BB;
    logic [1:0] BA;
}gf4_mult_t;

typedef struct packed {
    logic [1:0] shareA;
    logic [1:0] shareB;
} gf4_mult_res_t;

typedef struct packed {
    logic [3:0] shareA;
    logic [3:0] shareB;
} gf16_inversion_t;


//Pipeline
wire STAGE_2_RDY, STAGE_3_RDY, STAGE_4_RDY, STAGE_5_RDY, STAGE_6_RDY; 
logic stage2_valid, stage3_valid, stage4_valid, stage5_valid, stage6_valid;
logic [X_ID_WIDTH-1:0] stage2_instr_id, stage3_instr_id, stage4_instr_id, stage5_instr_id, stage6_instr_id;
logic stage2_decrypt, stage3_decrypt, stage4_decrypt, stage5_decrypt, stage6_decrypt;
logic [17:0] stage2_randombits, stage3_randombits, stage4_randombits, stage5_randombits;
logic stage2_middle_round, stage3_middle_round, stage4_middle_round, stage5_middle_round, stage6_middle_round;
logic [1:0] stage2_bs, stage3_bs, stage4_bs, stage5_bs, stage6_bs;
logic [31:0] stage2_rs1, stage3_rs1, stage4_rs1, stage5_rs1, stage6_rs1;

logic [3:0] stage2_shareA_nibble_high_reg, stage3_shareA_nibble_high_reg, stage4_shareA_nibble_high_reg, stage5_shareA_nibble_high_reg;
logic [3:0] stage2_shareA_nibble_low_reg, stage3_shareA_nibble_low_reg, stage4_shareA_nibble_low_reg, stage5_shareA_nibble_low_reg;
logic [3:0] stage2_shareB_nibble_high_reg, stage3_shareB_nibble_high_reg, stage4_shareB_nibble_high_reg, stage5_shareB_nibble_high_reg;
logic [3:0] stage2_shareB_nibble_low_reg, stage3_shareB_nibble_low_reg, stage4_shareB_nibble_low_reg, stage5_shareB_nibble_low_reg;

gf16_mult_t stage3_multiplication_dom_gf16_reg;
logic [3:0] stage3_shareA_square_scale_reg, stage3_shareB_square_scale_reg;
logic [3:0] stage4_shareA_square_scale_gf4_reg, stage4_shareB_square_scale_gf4_reg;


//Forward isomorphic transfrom
logic [7:0] shareA_isomorphic_trans;
logic [7:0] shareB_isomorphic_trans;

//Inversion gf256
logic [7:0] stage6_shareA_inversion_gf256_result, stage6_shareB_inversion_gf256_result;
logic [3:0] stage2_shareA_sum_nibbles, stage2_shareB_sum_nibbles; 
logic [3:0] stage2_shareA_square_scale, stage2_shareB_square_scale; 
gf16_mult_t stage2_multiplication_dom_gf16_before_reg;
gf16_mult_res_t stage3_multiplication_dom_gf16_after_reg; 
logic [3:0] stage3_shareA_sum_multiply_gf16, stage3_shareB_sum_multiply_gf16, stage4_shareA_sum_multiply_gf16_reg, stage4_shareB_sum_multiply_gf16_reg;
logic [3:0] stage5_shareA_inverted_gf16, stage5_shareB_inverted_gf16;
gf16_mult_res_t stage6_multiplication_high_gf16_after_reg, stage6_multiplication_low_gf16_after_reg;

// Inversion gf16
logic [1:0] stage3_shareA_sum_gf4, stage3_shareB_sum_gf4;
logic [1:0] stage3_shareA_square_gf4, stage3_shareB_square_gf4;
logic [1:0] stage3_shareA_square_scale_gf4, stage3_shareB_square_scale_gf4;
gf4_mult_res_t stage4_multiplication_dom_gf4_after_reg;
gf4_mult_t stage3_multiplication_dom_gf4_before_reg, stage4_multiplication_dom_gf4_reg;
logic [1:0] stage4_shareA_multiply_gf4, stage4_shareB_multiply_gf4;
logic [1:0] stage4_shareA_sum_multiply_gf4, stage4_shareB_sum_multiply_gf4;
logic [1:0] stage4_shareA_inverted_sum_gf4, stage4_shareB_inverted_sum_gf4;
gf4_mult_t stage4_result_h_before_reg_gf4, stage4_result_l_before_reg_gf4;
gf4_mult_res_t stage5_result_h_after_reg_gf4, stage5_result_l_after_reg_gf4;
gf4_mult_t stage5_result_h_gf4_reg, stage5_result_l_gf4_reg;
gf16_mult_t stage5_multiplication_high_gf16_before_reg, stage5_multiplication_low_gf16_before_reg;
gf16_mult_t stage6_multiplication_dom_gf16_high_reg, stage6_multiplication_dom_gf16_low_reg;
gf16_inversion_t stage5_inversion_gf16_result;

//PIPELINE_FORWARD_DATA
assign STAGE_2_RDY = !stage2_valid || STAGE_3_RDY;
assign STAGE_3_RDY = !stage3_valid || STAGE_4_RDY;
assign STAGE_4_RDY = !stage4_valid || STAGE_5_RDY;
assign STAGE_5_RDY = !stage5_valid || STAGE_6_RDY;
assign STAGE_6_RDY = !stage6_valid || ready_for_sbox_o;


//Output signals
assign valid_o          = stage6_valid;
assign ready_for_sbox_i = STAGE_2_RDY;
assign instr_id_o       = stage6_instr_id;
assign bs_o             = stage6_bs;
assign middle_round_o   = stage6_middle_round;
assign decrypt_o        = stage6_decrypt;
assign rs1_o            = stage6_rs1;

function logic [7:0] isomorphic_mapping;
input [7:0] byte_in;

logic [7:0] im;
begin
    im[7] = byte_in[7] ^ byte_in[6] ^ byte_in[5] ^ byte_in[2] ^ byte_in[1] ^ byte_in[0];
    im[6] = byte_in[6] ^ byte_in[5] ^ byte_in[4] ^ byte_in[0];
    im[5] = byte_in[6] ^ byte_in[5] ^ byte_in[1] ^ byte_in[0];
    im[4] = byte_in[7] ^ byte_in[6] ^ byte_in[5] ^ byte_in[0];
    im[3] = byte_in[7] ^ byte_in[4] ^ byte_in[3] ^ byte_in[1] ^ byte_in[0];
    im[2] = byte_in[0];
    im[1] = byte_in[6] ^ byte_in[5] ^ byte_in[0];
    im[0] = byte_in[6] ^ byte_in[3] ^ byte_in[2] ^ byte_in[1] ^ byte_in[0];

    isomorphic_mapping = im;
end
endfunction

function logic [7:0] inverse_isomorphic_mapping;
input [7:0] byte_in;

logic [7:0] im;
begin
    im[7] = byte_in[4] ^ byte_in[1];
    im[6] = byte_in[7] ^ byte_in[6] ^ byte_in[5] ^ byte_in[3] ^ byte_in[1] ^ byte_in[0];
    im[5] = byte_in[7] ^ byte_in[6] ^ byte_in[5] ^ byte_in[3] ^ byte_in[2] ^ byte_in[0];
    im[4] = byte_in[6] ^ byte_in[1];
    im[3] = byte_in[6] ^ byte_in[5] ^ byte_in[4] ^ byte_in[3] ^ byte_in[2] ^ byte_in[1];
    im[2] = byte_in[7] ^ byte_in[5] ^ byte_in[4] ^ byte_in[1];
    im[1] = byte_in[5] ^ byte_in[1];
    im[0] = byte_in[2];

    inverse_isomorphic_mapping = im;
end

endfunction

function logic [7:0] affine_transformation_addition;
input [7:0] byte_in;

logic [7:0] im;
begin
    im[7] = byte_in[7] ^ 0;
    im[6] = byte_in[6] ^ 1;
    im[5] = byte_in[5] ^ 1;
    im[4] = byte_in[4] ^ 0;
    im[3] = byte_in[3] ^ 0;
    im[2] = byte_in[2] ^ 0;
    im[1] = byte_in[1] ^ 1;
    im[0] = byte_in[0] ^ 1;

    affine_transformation_addition = im;
end

endfunction

function logic [7:0] affine_transformation_multiplication;
input [7:0] byte_in;

logic [7:0] im;
begin
    im[7] = byte_in[7] ^ byte_in[6] ^ byte_in[5] ^ byte_in[4] ^ byte_in[3];
    im[6] = byte_in[6] ^ byte_in[5] ^ byte_in[4] ^ byte_in[3] ^ byte_in[2];
    im[5] = byte_in[5] ^ byte_in[4] ^ byte_in[3] ^ byte_in[2] ^ byte_in[1];
    im[4] = byte_in[4] ^ byte_in[3] ^ byte_in[2] ^ byte_in[1] ^ byte_in[0];
    im[3] = byte_in[7] ^ byte_in[3] ^ byte_in[2] ^ byte_in[1] ^ byte_in[0];
    im[2] = byte_in[7] ^ byte_in[6] ^ byte_in[2] ^ byte_in[1] ^ byte_in[0];
    im[1] = byte_in[7] ^ byte_in[6] ^ byte_in[5] ^ byte_in[1] ^ byte_in[0];
    im[0] = byte_in[7] ^ byte_in[6] ^ byte_in[5] ^ byte_in[4] ^ byte_in[0];

    affine_transformation_multiplication = im;
end
endfunction

function logic [7:0] inverse_affine_transformation_addition;
input  [7:0] byte_in;

logic [7:0] im;
begin
    im[7] = byte_in[7] ^ 0;
    im[6] = byte_in[6] ^ 0;
    im[5] = byte_in[5] ^ 0;
    im[4] = byte_in[4] ^ 0;
    im[3] = byte_in[3] ^ 0;
    im[2] = byte_in[2] ^ 1;
    im[1] = byte_in[1] ^ 0;
    im[0] = byte_in[0] ^ 1;

    inverse_affine_transformation_addition = im;
end
endfunction

function logic [7:0] inverse_affine_transformation_multiplication;
    input [7:0] byte_in;

    logic [7:0] im;
    begin
        im[7] = byte_in[6] ^ byte_in[4] ^ byte_in[1];
        im[6] = byte_in[5] ^ byte_in[3] ^ byte_in[0];
        im[5] = byte_in[7] ^ byte_in[4] ^ byte_in[2];
        im[4] = byte_in[6] ^ byte_in[3] ^ byte_in[1];
        im[3] = byte_in[5] ^ byte_in[2] ^ byte_in[0];
        im[2] = byte_in[7] ^ byte_in[4] ^ byte_in[1];
        im[1] = byte_in[6] ^ byte_in[3] ^ byte_in[0];
        im[0] = byte_in[7] ^ byte_in[5] ^ byte_in[2];

        inverse_affine_transformation_multiplication = im;
    end
endfunction

function logic [3:0] square_scale_gf16;
    input [3:0] nibble_in;
    logic [1:0] sum_bits;       
    logic [1:0] square_sum;     
    logic [1:0] scale_h;        
    logic [1:0] square_scale_h;
    begin
        sum_bits       = nibble_in[3:2] ^ nibble_in[1:0];
        square_sum     = square_gf4(sum_bits);
        scale_h        = scale_N_gf4(nibble_in[1:0]);
        square_scale_h = square_gf4(scale_h);

        square_scale_gf16 = {square_sum, square_scale_h};
    end
endfunction;

function gf16_mult_t dom_multiplication_before_reg_gf16;
    input [3:0] shareA_gf16_l_in;
    input [3:0] shareA_gf16_h_in;
    input [3:0] shareB_gf16_l_in;
    input [3:0] shareB_gf16_h_in;

    input [3:0] fresh_randomness;
    logic [3:0] AA_hl_mult; 
    logic [3:0] AB_hl_mult; 
    logic [3:0] AB_hl_mult_r; 
    logic [3:0] BB_hl_mult; 
    logic [3:0] BA_hl_mult;
    logic [3:0] BA_hl_mult_r; 

    begin 

        AA_hl_mult = multiplication_gf16(shareA_gf16_h_in, shareA_gf16_l_in);
        AB_hl_mult = multiplication_gf16(shareA_gf16_h_in, shareB_gf16_l_in);
        BB_hl_mult = multiplication_gf16(shareB_gf16_h_in, shareB_gf16_l_in);
        BA_hl_mult = multiplication_gf16(shareB_gf16_h_in, shareA_gf16_l_in);

        AB_hl_mult_r = AB_hl_mult ^ fresh_randomness;
        BA_hl_mult_r = BA_hl_mult ^ fresh_randomness;

        dom_multiplication_before_reg_gf16.AA = AA_hl_mult;
        dom_multiplication_before_reg_gf16.AB = AB_hl_mult_r;
        dom_multiplication_before_reg_gf16.BB = BB_hl_mult;
        dom_multiplication_before_reg_gf16.BA = BA_hl_mult_r;
    end endfunction;

function gf16_mult_res_t dom_multiplication_after_reg_gf16;
    input gf16_mult_t shares_i;
    logic [3:0] AA_hl_mult; 
    logic [3:0] AB_hl_mult; 
    logic [3:0] BB_hl_mult; 
    logic [3:0] BA_hl_mult; 
    logic [3:0] shareA_result;
    logic [3:0] shareB_result;

    begin 

        AA_hl_mult = shares_i.AA;
        AB_hl_mult = shares_i.AB;
        BB_hl_mult = shares_i.BB;
        BA_hl_mult = shares_i.BA;

        shareA_result = AA_hl_mult ^ AB_hl_mult;
        shareB_result = BB_hl_mult ^ BA_hl_mult;

        dom_multiplication_after_reg_gf16.shareA = shareA_result;
        dom_multiplication_after_reg_gf16.shareB = shareB_result;
    end
endfunction;

function logic [1:0][3:0] dom_multiplication_gf16;
    input [3:0] shareA_gf16_l_in;
    input [3:0] shareA_gf16_h_in;
    input [3:0] shareB_gf16_l_in;
    input [3:0] shareB_gf16_h_in;

    input [3:0] fresh_randomness;
    logic [3:0] AA_hl_mult; 
    logic [3:0] AB_hl_mult; 
    logic [3:0] BB_hl_mult; 
    logic [3:0] BA_hl_mult; 
    logic [3:0] AB_hl_mult_r;
    logic [3:0] BA_hl_mult_r;
    logic [3:0] shareA_result;
    logic [3:0] shareB_result;

    begin 

        AA_hl_mult = multiplication_gf16(shareA_gf16_h_in, shareA_gf16_l_in);
        AB_hl_mult = multiplication_gf16(shareA_gf16_h_in, shareB_gf16_l_in);
        BB_hl_mult = multiplication_gf16(shareB_gf16_h_in, shareB_gf16_l_in);
        BA_hl_mult = multiplication_gf16(shareB_gf16_h_in, shareA_gf16_l_in);

        AB_hl_mult_r = AB_hl_mult ^ fresh_randomness;
        BA_hl_mult_r = BA_hl_mult ^ fresh_randomness;

        shareA_result = AA_hl_mult ^ AB_hl_mult_r;
        shareB_result = BB_hl_mult ^ BA_hl_mult_r;

        dom_multiplication_gf16[0] = shareA_result;
        dom_multiplication_gf16[1] = shareB_result;
    end
endfunction;

function logic [3:0] multiplication_gf16;
    input [3:0] a_in;
    input [3:0] b_in;

    logic [1:0] a_sum;
    logic [1:0] b_sum;
    logic [1:0] a_high_b_high_mult; 
    logic [1:0] a_low_b_low_mult;   
    logic [1:0] ab_sum_mult;        
    logic [1:0] ab_sum_scale_N; 
    logic [1:0] result_h; 
    logic [1:0] result_l; 
    begin
        a_sum = a_in[3:2] ^ a_in[1:0];
        b_sum = b_in[3:2] ^ b_in[1:0];

        a_high_b_high_mult = multiplication_gf4(a_in[3:2], b_in[3:2]);
        a_low_b_low_mult   = multiplication_gf4(a_in[1:0], b_in[1:0]);
        ab_sum_mult        = multiplication_gf4(a_sum, b_sum);

        ab_sum_scale_N = scale_N_gf4(ab_sum_mult);

        result_h = ab_sum_scale_N ^ a_high_b_high_mult;
        result_l = ab_sum_scale_N ^ a_low_b_low_mult;

        multiplication_gf16 = {result_h, result_l};
    end
endfunction

function logic [1:0] square_gf4;
    input [1:0] bits_in;
    square_gf4 = {bits_in[0], bits_in[1]};
endfunction

function logic [1:0] inverse_gf4;
    input [1:0] bits_in;
    inverse_gf4 = {bits_in[0], bits_in[1]};
endfunction

function logic [1:0] scale_N_gf4;
    input [1:0] bits_in;
    scale_N_gf4 = {bits_in[0], bits_in[1] ^ bits_in[0]};
endfunction

function gf4_mult_t dom_multiplication_before_reg_gf4;
    input [1:0] shareA_l_in;
    input [1:0] shareA_h_in;
    input [1:0] shareB_l_in;
    input [1:0] shareB_h_in;
    input [1:0] fresh_randomness;

    logic [1:0] AA_hl_mult;
    logic [1:0] AB_hl_mult;
    logic [1:0] AB_hl_mult_r;
    logic [1:0] BB_hl_mult;
    logic [1:0] BA_hl_mult;
    logic [1:0] BA_hl_mult_r;
    begin
        AA_hl_mult = multiplication_gf4(shareA_h_in, shareA_l_in);
        AB_hl_mult = multiplication_gf4(shareA_h_in, shareB_l_in);
        BB_hl_mult = multiplication_gf4(shareB_h_in, shareB_l_in);
        BA_hl_mult = multiplication_gf4(shareB_h_in, shareA_l_in);

        AB_hl_mult_r = AB_hl_mult ^ fresh_randomness;
        BA_hl_mult_r = BA_hl_mult ^ fresh_randomness;

        dom_multiplication_before_reg_gf4.AA = AA_hl_mult;
        dom_multiplication_before_reg_gf4.AB = AB_hl_mult_r;
        dom_multiplication_before_reg_gf4.BB = BB_hl_mult;
        dom_multiplication_before_reg_gf4.BA = BA_hl_mult_r;
    end 
endfunction;


function gf4_mult_res_t dom_multiplication_after_reg_gf4;
    input gf4_mult_t shares_i;
    logic [1:0] shareA_result;
    logic [1:0] shareB_result;
    begin
        shareA_result = shares_i.AA ^ shares_i.AB;
        shareB_result = shares_i.BB ^ shares_i.BA;

        dom_multiplication_after_reg_gf4.shareA = shareA_result;
        dom_multiplication_after_reg_gf4.shareB = shareB_result;
    end
endfunction

function logic [1:0][1:0] dom_multiplication_gf4;
    input [1:0] shareA_h_in;
    input [1:0] shareA_l_in;
    input [1:0] shareB_h_in;
    input [1:0] shareB_l_in;

    input [1:0] fresh_randomness;
    logic [1:0] AA_hl_mult; 
    logic [1:0] AB_hl_mult; 
    logic [1:0] BB_hl_mult; 
    logic [1:0] BA_hl_mult; 
    logic [1:0] AB_hl_mult_r;
    logic [1:0] BA_hl_mult_r;
    logic [1:0] shareA_result;
    logic [1:0] shareB_result;
    begin
        AA_hl_mult = multiplication_gf4(shareA_h_in, shareA_l_in);
        AB_hl_mult = multiplication_gf4(shareA_h_in, shareB_l_in);
        BB_hl_mult = multiplication_gf4(shareB_h_in, shareB_l_in);
        BA_hl_mult = multiplication_gf4(shareB_h_in, shareA_l_in);

        AB_hl_mult_r = AB_hl_mult ^ fresh_randomness;
        BA_hl_mult_r = BA_hl_mult ^ fresh_randomness;

        shareA_result = AA_hl_mult ^ AB_hl_mult_r;
        shareB_result = BB_hl_mult ^ BA_hl_mult_r;

        dom_multiplication_gf4[0] = shareA_result;
        dom_multiplication_gf4[1] = shareB_result;
    end
endfunction

function logic [1:0] multiplication_gf4;
    input [1:0] a_in;
    input [1:0] b_in;
    logic a_sum_bits;
    logic b_sum_bits;
    logic msb_ab_mult;
    logic lsb_ab_mult;
    logic a_sum_b_sum_mult;
    logic result_h;
    logic result_l;
    begin
        a_sum_bits = a_in[1] ^ a_in[0]; 
        b_sum_bits = b_in[1] ^ b_in[0]; 

        msb_ab_mult = a_in[1] & b_in[1]; 
        lsb_ab_mult = a_in[0] & b_in[0]; 
        a_sum_b_sum_mult = a_sum_bits & b_sum_bits; 

        result_h = msb_ab_mult ^ a_sum_b_sum_mult; 
        result_l = lsb_ab_mult ^ a_sum_b_sum_mult; 

        multiplication_gf4 = {result_h, result_l};
    end
endfunction

always_comb 
begin : ISOMORPHIC_TRANS
    if(decrypt_i) begin
        shareA_isomorphic_trans = isomorphic_mapping(
                                    inverse_affine_transformation_addition(
                                        inverse_affine_transformation_multiplication(shareA_in)));

        shareB_isomorphic_trans = isomorphic_mapping(
                                    inverse_affine_transformation_multiplication(shareB_in));
    end else begin
        shareA_isomorphic_trans = isomorphic_mapping(shareA_in);
        shareB_isomorphic_trans = isomorphic_mapping(shareB_in);
    end
end

always_ff @( posedge clk_i, negedge rst_n ) begin : SBOX_PIPELINE_REGISTERS
    if(!rst_n) begin 
        stage2_valid = 'b0;
        stage3_valid = 'b0;
        stage4_valid = 'b0;
        stage5_valid = 'b0;
        stage6_valid = 'b0; 
    end else 
    begin
        if(STAGE_6_RDY)
        begin
            //Register Between stage 5 & 6

            stage6_valid                       = stage5_valid;
            stage6_instr_id                    = stage5_instr_id;
            stage6_decrypt                     = stage5_decrypt;
            stage6_middle_round                = stage5_middle_round;
            stage6_bs                          = stage5_bs;
            stage6_rs1                         = stage5_rs1;


            stage6_multiplication_dom_gf16_high_reg = stage5_multiplication_high_gf16_before_reg;
            stage6_multiplication_dom_gf16_low_reg  = stage5_multiplication_low_gf16_before_reg;
        end
        if(STAGE_5_RDY)
        begin
            //Register Between stage 4 & 5

            stage5_valid                       = stage4_valid;
            stage5_instr_id                    = stage4_instr_id;
            stage5_decrypt                     = stage4_decrypt;
            stage5_randombits                  = stage4_randombits;
            stage5_middle_round                = stage4_middle_round;
            stage5_bs                          = stage4_bs;
            stage5_rs1                         = stage4_rs1;

            stage5_result_h_gf4_reg            = stage4_result_h_before_reg_gf4;             
            stage5_result_l_gf4_reg            = stage4_result_l_before_reg_gf4;

            stage5_shareA_nibble_high_reg      = stage4_shareA_nibble_high_reg;
            stage5_shareA_nibble_low_reg       = stage4_shareA_nibble_low_reg;
            stage5_shareB_nibble_high_reg      = stage4_shareB_nibble_high_reg;
            stage5_shareB_nibble_low_reg       = stage4_shareB_nibble_low_reg;
        end

        if(STAGE_4_RDY)
        begin
            //Register Between stage 3 & 4

            stage4_valid                       = stage3_valid;
            stage4_instr_id                    = stage3_instr_id;
            stage4_decrypt                     = stage3_decrypt;
            stage4_randombits                  = stage3_randombits;
            stage4_middle_round                = stage3_middle_round;
            stage4_bs                          = stage3_bs;
            stage4_rs1                         = stage3_rs1;

            stage4_multiplication_dom_gf4_reg  = stage3_multiplication_dom_gf4_before_reg;
            stage4_shareA_square_scale_gf4_reg = stage3_shareA_square_scale_gf4;
            stage4_shareB_square_scale_gf4_reg = stage3_shareB_square_scale_gf4;

            stage4_shareA_sum_multiply_gf16_reg         = stage3_shareA_sum_multiply_gf16;
            stage4_shareB_sum_multiply_gf16_reg         = stage3_shareB_sum_multiply_gf16;

            stage4_shareA_nibble_high_reg      = stage3_shareA_nibble_high_reg;
            stage4_shareA_nibble_low_reg       = stage3_shareA_nibble_low_reg;
            stage4_shareB_nibble_high_reg      = stage3_shareB_nibble_high_reg;
            stage4_shareB_nibble_low_reg       = stage3_shareB_nibble_low_reg;
        end

        if(STAGE_3_RDY)
        begin
            //Register Between stage 2 & 3
            stage3_valid                       = stage2_valid;
            stage3_instr_id                    = stage2_instr_id;
            stage3_decrypt                     = stage2_decrypt;
            stage3_randombits                  = stage2_randombits;
            stage3_middle_round                = stage2_middle_round;
            stage3_bs                          = stage2_bs;
            stage3_rs1                         = stage2_rs1;

            stage3_multiplication_dom_gf16_reg = stage2_multiplication_dom_gf16_before_reg;
            stage3_shareA_square_scale_reg     = stage2_shareA_square_scale;
            stage3_shareB_square_scale_reg     = stage2_shareB_square_scale;

            stage3_shareA_nibble_high_reg      = stage2_shareA_nibble_high_reg;
            stage3_shareA_nibble_low_reg       = stage2_shareA_nibble_low_reg;
            stage3_shareB_nibble_high_reg      = stage2_shareB_nibble_high_reg;
            stage3_shareB_nibble_low_reg       = stage2_shareB_nibble_low_reg;
        end

        if(STAGE_2_RDY)
        begin
            if(valid_i) begin
                //Register Between stage 1 & 2
                stage2_valid                       = valid_i;
                stage2_instr_id                    = instr_id_i;
                stage2_decrypt                     = decrypt_i;
                stage2_randombits                  = randombits_i;
                stage2_middle_round                = middle_round_i;
                stage2_bs                          = bs_i;
                stage2_rs1                         = rs1_i;

                stage2_shareA_nibble_high_reg      = shareA_isomorphic_trans[7:4];
                stage2_shareA_nibble_low_reg       = shareA_isomorphic_trans[3:0];
                stage2_shareB_nibble_high_reg      = shareB_isomorphic_trans[7:4];
                stage2_shareB_nibble_low_reg       = shareB_isomorphic_trans[3:0];
            end else begin
                //Register Between stage 1 & 2
                stage2_valid                       = 'b0;
                stage2_instr_id                    = 'b0;
                stage2_decrypt                     = 'b0;
                stage2_randombits                  = 'b0;
                stage2_middle_round                = 'b0;
                stage2_bs                          = 'b0;
                stage2_rs1                         = 'b0;

                stage2_shareA_nibble_high_reg      = 'b0;
                stage2_shareA_nibble_low_reg       = 'b0;
                stage2_shareB_nibble_high_reg      = 'b0;
                stage2_shareB_nibble_low_reg       = 'b0;
            end

        end
    end
end

always_comb 
begin: GF256_INVERSION_PIPELINED
    //-------------------Stage 2---------------------------------
    stage2_shareA_sum_nibbles = stage2_shareA_nibble_high_reg ^ stage2_shareA_nibble_low_reg;
    stage2_shareB_sum_nibbles = stage2_shareB_nibble_high_reg ^ stage2_shareB_nibble_low_reg;

    stage2_shareA_square_scale = square_scale_gf16(stage2_shareA_sum_nibbles);
    stage2_shareB_square_scale = square_scale_gf16(stage2_shareB_sum_nibbles);

    stage2_multiplication_dom_gf16_before_reg = dom_multiplication_before_reg_gf16(stage2_shareA_nibble_low_reg, 
                                                                                   stage2_shareA_nibble_high_reg,
                                                                                   stage2_shareB_nibble_low_reg, 
                                                                                   stage2_shareB_nibble_high_reg,
                                                                                   stage2_randombits[11:8]);
    

    //-------------------Stage 3 & 4---------------------------------
    stage3_multiplication_dom_gf16_after_reg = dom_multiplication_after_reg_gf16(stage3_multiplication_dom_gf16_reg);

    stage3_shareA_sum_multiply_gf16 = stage3_multiplication_dom_gf16_after_reg.shareA ^ stage3_shareA_square_scale_reg;
    stage3_shareB_sum_multiply_gf16 = stage3_multiplication_dom_gf16_after_reg.shareB ^ stage3_shareB_square_scale_reg;

    // GF16 inversion, see combinatoric block below
    //-------------------Stage 5---------------------------------

    stage5_shareA_inverted_gf16 = stage5_inversion_gf16_result.shareA;
    stage5_shareB_inverted_gf16 = stage5_inversion_gf16_result.shareB;

    stage5_multiplication_high_gf16_before_reg = dom_multiplication_before_reg_gf16(stage5_shareA_nibble_low_reg, 
                                                                               stage5_shareA_inverted_gf16, 
                                                                               stage5_shareB_nibble_low_reg, 
                                                                               stage5_shareB_inverted_gf16,
                                                                               stage5_randombits[3:0]
                                                                               );
    stage5_multiplication_low_gf16_before_reg  = dom_multiplication_before_reg_gf16(stage5_shareA_nibble_high_reg, 
                                                                               stage5_shareA_inverted_gf16, 
                                                                               stage5_shareB_nibble_high_reg, 
                                                                               stage5_shareB_inverted_gf16,
                                                                               stage5_randombits[7:4]);
    //-------------------Stage 6---------------------------------
    stage6_multiplication_high_gf16_after_reg  = dom_multiplication_after_reg_gf16(stage6_multiplication_dom_gf16_high_reg);
    stage6_multiplication_low_gf16_after_reg   = dom_multiplication_after_reg_gf16(stage6_multiplication_dom_gf16_low_reg);
    
    stage6_shareA_inversion_gf256_result = {stage6_multiplication_high_gf16_after_reg.shareA, stage6_multiplication_low_gf16_after_reg.shareA};
    stage6_shareB_inversion_gf256_result = {stage6_multiplication_high_gf16_after_reg.shareB, stage6_multiplication_low_gf16_after_reg.shareB};
end

always_comb 
begin : GF16_INVERSION_PIPELINED
    //-------------------Stage 3-----------------------------------

    stage3_shareA_sum_gf4 = stage3_shareA_sum_multiply_gf16[3:2] ^ stage3_shareA_sum_multiply_gf16[1:0];
    stage3_shareB_sum_gf4 = stage3_shareB_sum_multiply_gf16[3:2] ^ stage3_shareB_sum_multiply_gf16[1:0];

    stage3_shareA_square_gf4       = square_gf4(stage3_shareA_sum_gf4);
    stage3_shareB_square_gf4       = square_gf4(stage3_shareB_sum_gf4);

    stage3_shareA_square_scale_gf4 = scale_N_gf4(stage3_shareA_square_gf4);
    stage3_shareB_square_scale_gf4 = scale_N_gf4(stage3_shareB_square_gf4);

    stage3_multiplication_dom_gf4_before_reg = dom_multiplication_before_reg_gf4(stage3_shareA_sum_multiply_gf16[1:0],
                                                                                 stage3_shareA_sum_multiply_gf16[3:2], 
                                                                                 stage3_shareB_sum_multiply_gf16[1:0], 
                                                                                 stage3_shareB_sum_multiply_gf16[3:2],
                                                                                 stage3_randombits[13:12]
                                                                                 );

    //-------------------Stage 4-----------------------------------
    stage4_multiplication_dom_gf4_after_reg  = dom_multiplication_after_reg_gf4(stage4_multiplication_dom_gf4_reg);

    stage4_shareA_multiply_gf4 = stage4_multiplication_dom_gf4_after_reg.shareA;
    stage4_shareB_multiply_gf4 = stage4_multiplication_dom_gf4_after_reg.shareB;

    stage4_shareA_sum_multiply_gf4 = stage4_shareA_multiply_gf4 ^ stage4_shareA_square_scale_gf4_reg;
    stage4_shareB_sum_multiply_gf4 = stage4_shareB_multiply_gf4 ^ stage4_shareB_square_scale_gf4_reg;

    stage4_shareA_inverted_sum_gf4 = inverse_gf4(stage4_shareA_sum_multiply_gf4);
    stage4_shareB_inverted_sum_gf4 = inverse_gf4(stage4_shareB_sum_multiply_gf4);


    stage4_result_h_before_reg_gf4 = dom_multiplication_before_reg_gf4(stage4_shareA_sum_multiply_gf16_reg[1:0], 
                                                                       stage4_shareA_inverted_sum_gf4, 
                                                                       stage4_shareB_sum_multiply_gf16_reg[1:0], 
                                                                       stage4_shareB_inverted_sum_gf4,
                                                                       stage4_randombits[15:14]
                                                                       );

    stage4_result_l_before_reg_gf4 = dom_multiplication_before_reg_gf4(stage4_shareA_sum_multiply_gf16_reg[3:2], 
                                                                       stage4_shareA_inverted_sum_gf4, 
                                                                       stage4_shareB_sum_multiply_gf16_reg[3:2], 
                                                                       stage4_shareB_inverted_sum_gf4,
                                                                       stage4_randombits[17:16]
                                                                       );
    
    //-------------------(Parts of) Stage 5---------------------------
    
    stage5_result_h_after_reg_gf4  = dom_multiplication_after_reg_gf4(stage5_result_h_gf4_reg);
    stage5_result_l_after_reg_gf4  = dom_multiplication_after_reg_gf4(stage5_result_l_gf4_reg);

    stage5_inversion_gf16_result.shareA = {stage5_result_h_after_reg_gf4.shareA, stage5_result_l_after_reg_gf4.shareA};
    stage5_inversion_gf16_result.shareB = {stage5_result_h_after_reg_gf4.shareB, stage5_result_l_after_reg_gf4.shareB};
end


always_comb begin
    //-------------------Stage 6---------------------------------
    if(stage6_decrypt) begin
        shareA_out = inverse_isomorphic_mapping(stage6_shareA_inversion_gf256_result);
        shareB_out = inverse_isomorphic_mapping(stage6_shareB_inversion_gf256_result);
    end else begin
        shareA_out = affine_transformation_addition(
                        affine_transformation_multiplication(
                            inverse_isomorphic_mapping(stage6_shareA_inversion_gf256_result)));
                            
        shareB_out = affine_transformation_multiplication(
                        inverse_isomorphic_mapping(stage6_shareB_inversion_gf256_result));
    end
end

endmodule