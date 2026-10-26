package aes_pkg;

// AES Instructions
parameter AES_OPCODE_WIDTH = 7;
parameter AES_FUNC3_WIDTH  = 3;
parameter AES_FUNC_WIDTH   = 5;

typedef enum logic [AES_FUNC_WIDTH-1:0] {
  AES32DSI =  5'b10101,
  AES32DSMI = 5'b10111,
  AES32ESI =  5'b10001,
  AES32ESMI = 5'b10011
} aes_func5_e;

typedef enum logic [AES_OPCODE_WIDTH-1:0] {
  AES32 = 7'b0110011
} aes_opcode_e;

parameter logic [AES_FUNC3_WIDTH-1:0] AES32_FUNC3 = 3'b000;

endpackage
