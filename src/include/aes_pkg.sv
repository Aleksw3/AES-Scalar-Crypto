package aes_pkg;

// AES Instructions
parameter AES_OPCODE_WIDTH = 6;
parameter AES_FUNC_WIDTH   = 5;

typedef enum logic [AES_FUNC_WIDTH-1:0] {
  AES32DSI =  5'b10101,
  AES32DSMI = 5'b10111,
  AES32ESI =  5'b10001,
  AES32ESMI = 5'b10011
} aes_func5_e;

typedef enum logic [AES_OPCODE_WIDTH-1:0] {
  AES32 = 6'b110011
} aes_opcode_e;

typedef struct packed {
    logic [3:0] instr_id;
    logic [4:0] rd_adr;
    logic kill;
} id_rd_packet_t;


endpackage