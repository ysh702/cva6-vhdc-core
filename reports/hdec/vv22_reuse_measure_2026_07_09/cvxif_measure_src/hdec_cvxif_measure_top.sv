typedef logic [1:0]  measure_readregflags_t;
typedef logic [0:0]  measure_writeregflags_t;
typedef logic [7:0]  measure_id_t;
typedef logic [0:0]  measure_hartid_t;

typedef struct packed {
    logic [15:0] instr;
    measure_hartid_t hartid;
} measure_x_compressed_req_t;

typedef struct packed {
    logic [31:0] instr;
    logic accept;
} measure_x_compressed_resp_t;

typedef struct packed {
    logic [31:0] instr;
    measure_hartid_t hartid;
    measure_id_t id;
} measure_x_issue_req_t;

typedef struct packed {
    logic accept;
    measure_writeregflags_t writeback;
    measure_readregflags_t register_read;
} measure_x_issue_resp_t;

typedef struct packed {
    measure_hartid_t hartid;
    measure_id_t id;
    logic [1:0][63:0] rs;
    measure_readregflags_t rs_valid;
} measure_x_register_t;

typedef struct packed {
    measure_hartid_t hartid;
    measure_id_t id;
    logic commit_kill;
} measure_x_commit_t;

typedef struct packed {
    measure_hartid_t hartid;
    measure_id_t id;
    logic [63:0] data;
    logic [4:0] rd;
    measure_writeregflags_t we;
} measure_x_result_t;

typedef struct packed {
    logic compressed_valid;
    measure_x_compressed_req_t compressed_req;
    logic issue_valid;
    measure_x_issue_req_t issue_req;
    logic register_valid;
    measure_x_register_t register;
    logic commit_valid;
    measure_x_commit_t commit;
    logic result_ready;
} measure_cvxif_req_t;

typedef struct packed {
    logic compressed_ready;
    measure_x_compressed_resp_t compressed_resp;
    logic issue_ready;
    measure_x_issue_resp_t issue_resp;
    logic register_ready;
    logic result_valid;
    measure_x_result_t result;
} measure_cvxif_resp_t;

module hdec_cvxif_measure_top (
    input  logic clk_i,
    input  logic rst_ni,
    input  measure_cvxif_req_t  cvxif_req_i,
    output measure_cvxif_resp_t cvxif_resp_o
);
    hdec_cvxif_wrapper #(
        .NrRgprPorts(2),
        .XLEN(64),
        .readregflags_t(measure_readregflags_t),
        .writeregflags_t(measure_writeregflags_t),
        .id_t(measure_id_t),
        .hartid_t(measure_hartid_t),
        .x_compressed_req_t(measure_x_compressed_req_t),
        .x_compressed_resp_t(measure_x_compressed_resp_t),
        .x_issue_req_t(measure_x_issue_req_t),
        .x_issue_resp_t(measure_x_issue_resp_t),
        .x_register_t(measure_x_register_t),
        .x_commit_t(measure_x_commit_t),
        .x_result_t(measure_x_result_t),
        .cvxif_req_t(measure_cvxif_req_t),
        .cvxif_resp_t(measure_cvxif_resp_t)
    ) i_accel (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .cvxif_req_i(cvxif_req_i),
        .cvxif_resp_o(cvxif_resp_o)
    );
endmodule

