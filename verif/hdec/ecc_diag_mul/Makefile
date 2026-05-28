# ==============================================================================
# Makefile — GF(2^256) diagonal multiplier standalone Verilator test
# ==============================================================================
# Usage: make -C verif/hdec/ecc_diag_mul run
# ==============================================================================

REPO_ROOT  ?= $(CURDIR)/../../..
TOOLS_DIR  ?= $(REPO_ROOT)/tools/hdec
RTL_DIR    ?= $(REPO_ROOT)/core/hdec/rtl
VECTORS    ?= $(TOOLS_DIR)/ecc_diag_mul_vectors.txt

VERILATOR  ?= verilator
WORK_DIR   ?= work_gf2_diag_mul

.PHONY: vectors verilate run clean

# Step 1: generate golden vectors
vectors:
	@echo "[1/3] Generating Python golden vectors..."
	python3 $(TOOLS_DIR)/ecc_diag_mul_verify.py
	@if [ ! -f $(VECTORS) ]; then \
		echo "ERROR: vector file not generated"; exit 1; \
	fi
	@echo "       Vectors ready"

# Step 2: compile with Verilator + C++ testbench
verilate:
	@echo "[2/3] Verilating gf2_256_diag_mul_raw + C++ tb..."
	@mkdir -p $(WORK_DIR)
	$(VERILATOR) --cc --build -j \
		--timing \
		-Wno-fatal --autoflush \
		-Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-UNSIGNED \
		-Wno-IMPLICIT -Wno-CASEINCOMPLETE \
		--top-module gf2_256_diag_mul_raw \
		$(RTL_DIR)/gf2_256_diag_mul_raw.sv \
		--exe $(CURDIR)/tb_gf2_256_diag_mul_raw.cpp \
		-o Vgf2_256_diag_mul_raw \
		--Mdir $(WORK_DIR)
	@echo "       Verilator build complete"

# Step 3: run simulation
run: vectors verilate
	@echo "[3/3] Running simulation..."
	cd $(REPO_ROOT) && $(CURDIR)/$(WORK_DIR)/Vgf2_256_diag_mul_raw $(VECTORS)

clean:
	rm -rf $(WORK_DIR)
